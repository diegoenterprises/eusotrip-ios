//
//  DriverProfileStore.swift
//  EusoTrip — Session-scoped driver profile (name, email, CDL class, photo).
//
//  Why a dedicated store instead of folding this into `EusoTripSession`:
//    • `EusoTripSession` holds *auth* state (token, AuthUser record) — read-
//      mostly, rotated on sign-in/sign-out.
//    • `DriverProfileStore` holds *profile* state (first name, last name,
//      email display, license class, member-since year, phone, avatar) —
//      written when the user edits their profile, read in several places
//      that are far apart in the hierarchy (Home greeting "Hey, Michael",
//      Me tab header card, Settings ACCOUNT row).
//    • Separating them keeps ProfileEdit → profile store a narrow write
//      surface, while `EusoTripSession.signOut()` can still tear down auth
//      without dragging profile state into the auth flow.
//
//  Persisted to `UserDefaults` under `"com.eusorone.EusoTrip.profile.*"`
//  so the edits survive a cold launch. On future waves this can be swapped
//  for a backend `me.update(...)` call without changing the SwiftUI call
//  sites that bind to `@EnvironmentObject var profile: DriverProfileStore`.
//
//  Powered by ESANG AI™.
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class DriverProfileStore: ObservableObject {

    // MARK: - Published fields (read by Home greeting, Me header, Settings)

    @Published var firstName: String
    @Published var lastName: String
    @Published var email: String
    @Published var licenseClass: String         // e.g. "CDL-A"
    @Published var memberSinceYear: String      // e.g. "2023"
    @Published var phone: String

    /// Set when a server write behind a Save fails. Editors read this to
    /// show the user that their save did not reach the server (instead of
    /// the prior `try?` which silently dropped it). Cleared on next success.
    @Published var lastSaveError: String? = nil

    // MARK: - Driver-specific fields (CDL / medical / TWIC)
    //
    // Persisted server-side via `profile.updateDriverProfile`
    // (writes to `users.metadata.driver` JSON). Read on launch +
    // on `eusoProfileUpdated` realtime events so cross-device
    // sync reaches every Me-section surface that renders these.
    @Published var cdlNumber: String = ""
    @Published var cdlState: String = ""
    @Published var cdlEndorsements: [String] = []
    @Published var cdlExpirationDate: String = ""
    @Published var medicalExpirationDate: String = ""
    @Published var medicalExaminerName: String = ""
    @Published var twicNumber: String = ""
    @Published var twicExpirationDate: String = ""
    @Published var hazmatEndorsement: Bool = false
    @Published var tankerEndorsement: Bool = false
    @Published var homeTerminal: String = ""
    @Published var hireDate: String = ""
    @Published var yearsExperience: Int = 0

    /// Raw bytes of the driver's avatar (JPEG). `nil` → fall back to the
    /// gradient monogram avatar the header already renders. We store PNG
    /// bytes, not a cached `UIImage`, so `@Published` equality checks stay
    /// cheap and UserDefaults can persist it across cold launch.
    @Published var avatarData: Data?

    // MARK: - Init

    /// Hydrate from UserDefaults synchronously (cold-start UX) then
    /// kick off a background refresh from `profile.getMyProfile` so the
    /// server-side row wins on every launch. UserDefaults stays as a
    /// local cache for offline use; the SERVER is the source of truth
    /// so edits made on iPad / web propagate to iPhone next launch.
    /// Founder direction 2026-05-04: "1000% iOS app and web platform
    /// parity meaning whatever happens on app reflects on web platform
    /// and persist for that user across multiple devices in real time."
    init() {
        let d = UserDefaults.standard
        self.firstName       = d.string(forKey: Key.firstName)       ?? ""
        self.lastName        = d.string(forKey: Key.lastName)        ?? ""
        self.email           = d.string(forKey: Key.email)           ?? ""
        self.licenseClass    = d.string(forKey: Key.licenseClass)    ?? ""
        self.memberSinceYear = d.string(forKey: Key.memberSinceYear) ?? ""
        self.phone           = d.string(forKey: Key.phone)           ?? ""
        self.avatarData      = d.data(forKey: Key.avatarData)

        // Background refresh — server is canonical. Errors are
        // tolerated silently because the cached UserDefaults values
        // already painted the UI; the user never sees a flash of
        // empty fields while the network round-trips.
        Task { [weak self] in
            await self?.refreshFromServer()
        }

        // Real-time cross-device sync — listen for `profile:updated`
        // (broadcast by `profile.updateProfile` / `.updateAvatar` on
        // the server's `user:<id>` channel via the Socket.IO bridge)
        // and re-pull the canonical row. Resolves the founder's
        // "persist for that user across multiple devices in real
        // time" doctrine: edit on iPad → iPhone repaints within one
        // round-trip while both apps are open.
        NotificationCenter.default.addObserver(
            forName: .eusoProfileUpdated, object: nil, queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.refreshFromServer()
            }
        }
    }

    /// Pull the canonical profile from `profile.getMyProfile` and fold
    /// it into the published fields. Splits the server's combined
    /// `name` back into first/last so the editor's two text fields
    /// hydrate correctly. Idempotent — safe to call from the editor's
    /// `.task` modifier or anywhere a fresh fetch is wanted.
    func refreshFromServer() async {
        struct Profile: Decodable {
            let name: String?
            let email: String?
            let phone: String?
            let avatar: String?
            let createdAt: String?
        }
        guard let p: Profile = try? await EusoTripAPI.shared.queryNoInput("profile.getMyProfile") else {
            return
        }
        // Split combined `name` into first / last using whitespace as
        // the delimiter. First token = first name; the rest joined =
        // last name. Single-word names land entirely in `firstName`.
        if let combined = p.name, !combined.isEmpty {
            let parts = combined.split(separator: " ", maxSplits: 1).map(String.init)
            self.firstName = parts.first ?? ""
            self.lastName  = parts.count > 1 ? parts[1] : ""
        }
        if let e = p.email, !e.isEmpty { self.email = e }
        if let ph = p.phone, !ph.isEmpty { self.phone = ph }
        // Year-extract from createdAt (ISO 8601) for the
        // "Member since" line. Falls back to existing value.
        if let iso = p.createdAt, iso.count >= 4 {
            let year = String(iso.prefix(4))
            if !year.isEmpty { self.memberSinceYear = year }
        }
        // Mirror the fresh values into UserDefaults so the next cold
        // start renders correctly when offline.
        let d = UserDefaults.standard
        d.set(self.firstName,       forKey: Key.firstName)
        d.set(self.lastName,        forKey: Key.lastName)
        d.set(self.email,           forKey: Key.email)
        d.set(self.phone,           forKey: Key.phone)
        d.set(self.memberSinceYear, forKey: Key.memberSinceYear)

        // Driver-specific fields — fetched from `profile.getDriverProfile`
        // which reads `users.metadata.driver` JSON on the server.
        struct CDL: Decodable { let number: String?; let `class`: String?; let state: String?; let endorsements: [String]?; let expirationDate: String? }
        struct Med: Decodable { let expirationDate: String?; let examinerName: String? }
        struct TWIC: Decodable { let number: String?; let expirationDate: String? }
        struct DriverProfile: Decodable {
            let cdl: CDL?
            let medicalCard: Med?
            let twic: TWIC?
            let hazmatEndorsement: Bool?
            let tankerEndorsement: Bool?
            let homeTerminal: String?
            let hireDate: String?
            let yearsExperience: Double?
        }
        if let dp: DriverProfile = try? await EusoTripAPI.shared.queryNoInput("profile.getDriverProfile") {
            self.cdlNumber             = dp.cdl?.number ?? ""
            self.licenseClass          = dp.cdl?.class ?? self.licenseClass
            self.cdlState              = dp.cdl?.state ?? ""
            self.cdlEndorsements       = dp.cdl?.endorsements ?? []
            self.cdlExpirationDate     = dp.cdl?.expirationDate ?? ""
            self.medicalExpirationDate = dp.medicalCard?.expirationDate ?? ""
            self.medicalExaminerName   = dp.medicalCard?.examinerName ?? ""
            self.twicNumber            = dp.twic?.number ?? ""
            self.twicExpirationDate    = dp.twic?.expirationDate ?? ""
            self.hazmatEndorsement     = dp.hazmatEndorsement ?? false
            self.tankerEndorsement     = dp.tankerEndorsement ?? false
            self.homeTerminal          = dp.homeTerminal ?? ""
            self.hireDate              = dp.hireDate ?? ""
            self.yearsExperience       = Int(dp.yearsExperience ?? 0)
            d.set(self.licenseClass, forKey: Key.licenseClass)
        }
    }

    /// Persist driver-specific fields (CDL, medical, TWIC,
    /// endorsements, home terminal, etc.) to the server. Mirrors
    /// `commit(...)` for the basic profile — fire-and-forget; local
    /// values flip immediately so the UI doesn't wait on the network.
    /// Server broadcasts `profile:updated` so other devices repaint.
    func commitDriver(
        cdlNumber: String,
        cdlClass: String,
        cdlState: String,
        cdlEndorsements: [String],
        cdlExpirationDate: String,
        medicalExpirationDate: String,
        medicalExaminerName: String,
        twicNumber: String,
        twicExpirationDate: String,
        hazmatEndorsement: Bool,
        tankerEndorsement: Bool,
        homeTerminal: String,
        hireDate: String,
        yearsExperience: Int
    ) {
        self.cdlNumber             = cdlNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        self.licenseClass          = cdlClass.trimmingCharacters(in: .whitespacesAndNewlines)
        self.cdlState              = cdlState.trimmingCharacters(in: .whitespacesAndNewlines)
        self.cdlEndorsements       = cdlEndorsements
        self.cdlExpirationDate     = cdlExpirationDate
        self.medicalExpirationDate = medicalExpirationDate
        self.medicalExaminerName   = medicalExaminerName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.twicNumber            = twicNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        self.twicExpirationDate    = twicExpirationDate
        self.hazmatEndorsement     = hazmatEndorsement
        self.tankerEndorsement     = tankerEndorsement
        self.homeTerminal          = homeTerminal.trimmingCharacters(in: .whitespacesAndNewlines)
        self.hireDate              = hireDate
        self.yearsExperience       = yearsExperience
        UserDefaults.standard.set(self.licenseClass, forKey: Key.licenseClass)

        struct In: Encodable {
            let cdlNumber: String
            let cdlClass: String
            let cdlState: String
            let cdlEndorsements: [String]
            let cdlExpirationDate: String
            let medicalExpirationDate: String
            let medicalExaminerName: String
            let twicNumber: String
            let twicExpirationDate: String
            let hazmatEndorsement: Bool
            let tankerEndorsement: Bool
            let homeTerminal: String
            let hireDate: String
            let yearsExperience: Int
        }
        struct Out: Decodable { let success: Bool }
        let payload = In(
            cdlNumber: cdlNumber, cdlClass: cdlClass, cdlState: cdlState,
            cdlEndorsements: cdlEndorsements, cdlExpirationDate: cdlExpirationDate,
            medicalExpirationDate: medicalExpirationDate,
            medicalExaminerName: medicalExaminerName,
            twicNumber: twicNumber, twicExpirationDate: twicExpirationDate,
            hazmatEndorsement: hazmatEndorsement, tankerEndorsement: tankerEndorsement,
            homeTerminal: homeTerminal, hireDate: hireDate, yearsExperience: yearsExperience
        )
        Task { @MainActor in
            do {
                let out: Out? = try await EusoTripAPI.shared.mutation(
                    "profile.updateDriverProfile",
                    input: payload
                )
                // updateDriverProfile returns {success:false} when the DB write
                // can't resolve the user — treat that as a real failure so the
                // driver isn't told their CDL is on file when it isn't.
                lastSaveError = (out?.success == true)
                    ? nil
                    : "Your credentials didn't save. Please try again."
            } catch {
                lastSaveError = (error as? EusoTripAPIError)?.errorDescription
                    ?? "Your credentials didn't save. Please try again."
            }
        }
    }

    // MARK: - Derived read-only displays

    /// "Michael Eusorone". Centralized so Home + Me + Settings never
    /// drift in how they concatenate the name.
    var fullName: String {
        "\(firstName) \(lastName)"
            .trimmingCharacters(in: .whitespaces)
    }

    /// "michael@eusorone.com · CDL-A · Member since 2023". The Settings
    /// ACCOUNT card reads this verbatim.
    var accountSummary: String {
        "\(email) · \(licenseClass) · Member since \(memberSinceYear)"
    }

    /// Reputation line on the Me tab header card. Returns just the
    /// license class today — the "4.92★ · 127 loads completed" literal
    /// was mock data. Once a `profile.getReputation` router ships, it
    /// will be appended here from a live store; until then callers
    /// render only what the backend actually knows.
    ///
    /// TODO(backend): POST /v1/profile/getReputation — returns { rating, completedLoads }
    var reputationSummary: String {
        licenseClass
    }

    // MARK: - Write surface used by ProfileEditView

    /// Atomic save — ProfileEditView calls this once, after the user
    /// taps the "Save" CTA. Individual `@Published` bindings in the
    /// editor are driven via a draft value; we flip them all together
    /// here so the Home greeting / Me header card do not flicker
    /// through each keystroke.
    ///
    /// Now round-trips to the server via `profile.updateProfile` so
    /// edits propagate to web + iPad in real time. UserDefaults stays
    /// as a local cache for offline reads. Server failure does NOT
    /// roll back the local state — the user sees their edit
    /// immediately and the next `refreshFromServer()` will
    /// reconcile if the write was rejected.
    func commit(
        firstName: String,
        lastName: String,
        email: String,
        licenseClass: String,
        phone: String,
        avatarData: Data?
    ) {
        self.firstName    = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lastName     = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.email        = email.trimmingCharacters(in: .whitespacesAndNewlines)
        self.licenseClass = licenseClass.trimmingCharacters(in: .whitespacesAndNewlines)
        self.phone        = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        self.avatarData   = avatarData

        let d = UserDefaults.standard
        d.set(self.firstName,       forKey: Key.firstName)
        d.set(self.lastName,        forKey: Key.lastName)
        d.set(self.email,           forKey: Key.email)
        d.set(self.licenseClass,    forKey: Key.licenseClass)
        d.set(self.phone,           forKey: Key.phone)
        // memberSinceYear is not user-editable — driver cannot backdate
        // when they joined. It's displayed read-only in ProfileEditView.
        if let avatarData {
            d.set(avatarData, forKey: Key.avatarData)
        } else {
            d.removeObject(forKey: Key.avatarData)
        }

        // Server round-trip — fire-and-forget. The mutation writes to
        // `users` (name, email, phone) so any other surface
        // (`shippers.getProfile`, `profile.getMyProfile`,
        // `auth.me`) sees the fresh row on next read.
        let firstSnapshot = self.firstName
        let lastSnapshot = self.lastName
        let emailSnapshot = self.email
        let phoneSnapshot = self.phone
        let avatarSnapshot = avatarData
        Task {
            struct In: Encodable {
                let firstName: String
                let lastName: String
                let email: String
                let phone: String
            }
            struct Out: Decodable { let success: Bool }
            do {
                let _: Out? = try await EusoTripAPI.shared.mutation(
                    "profile.updateProfile",
                    input: In(firstName: firstSnapshot,
                              lastName:  lastSnapshot,
                              email:     emailSnapshot,
                              phone:     phoneSnapshot)
                )
                await MainActor.run { lastSaveError = nil }
            } catch {
                // Local edit is kept (offline-first); refreshFromServer() will
                // reconcile. But the failure is no longer invisible.
                await MainActor.run {
                    lastSaveError = (error as? EusoTripAPIError)?.errorDescription
                        ?? "Profile changes didn't sync. They'll retry on next refresh."
                }
            }
        }

        // Avatar round-trip — separate mutation. Compresses the picked
        // image to ≤512px JPEG and ships as a base64 data URL through
        // `profile.updateAvatar` (writes `users.profilePicture` server-
        // side). Web `/profile` reads from the same column so the new
        // photo appears there immediately. Server broadcasts
        // `profile:updated` so iPad / Watch repaint without a manual
        // refresh.
        if let avatarData = avatarSnapshot, !avatarData.isEmpty {
            Task {
                let bytes: Data = {
                    #if canImport(UIKit)
                    if let img = UIImage(data: avatarData) {
                        let target: CGFloat = 512
                        let scale = min(target / max(img.size.width, 1), target / max(img.size.height, 1), 1)
                        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
                        let renderer = UIGraphicsImageRenderer(size: size)
                        let resized = renderer.image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
                        if let jpeg = resized.jpegData(compressionQuality: 0.8) { return jpeg }
                    }
                    #endif
                    return avatarData
                }()
                let dataURL = "data:image/jpeg;base64,\(bytes.base64EncodedString())"
                struct AIn: Encodable { let avatarUrl: String }
                struct AOut: Decodable { let success: Bool; let avatarUrl: String }
                do {
                    let _: AOut? = try await EusoTripAPI.shared.mutation(
                        "profile.updateAvatar",
                        input: AIn(avatarUrl: dataURL)
                    )
                    await MainActor.run { lastSaveError = nil }
                } catch {
                    await MainActor.run {
                        lastSaveError = (error as? EusoTripAPIError)?.errorDescription
                            ?? "Your photo didn't upload. Please try again."
                    }
                }
            }
        }
    }

    // MARK: - UserDefaults keys

    private enum Key {
        static let firstName       = "com.eusorone.EusoTrip.profile.firstName"
        static let lastName        = "com.eusorone.EusoTrip.profile.lastName"
        static let email           = "com.eusorone.EusoTrip.profile.email"
        static let licenseClass    = "com.eusorone.EusoTrip.profile.licenseClass"
        static let memberSinceYear = "com.eusorone.EusoTrip.profile.memberSinceYear"
        static let phone           = "com.eusorone.EusoTrip.profile.phone"
        static let avatarData      = "com.eusorone.EusoTrip.profile.avatarData"
    }
}
