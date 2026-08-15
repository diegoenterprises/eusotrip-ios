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

private enum ProfileSaveError: LocalizedError {
    case firstNameRequired
    case unreadableAvatar
    case avatarTooLarge
    case readbackMismatch

    var errorDescription: String? {
        switch self {
        case .firstNameRequired: return "First name is required."
        case .unreadableAvatar: return "That profile photo could not be read."
        case .avatarTooLarge: return "That profile photo could not be reduced to the secure upload limit."
        case .readbackMismatch: return "The saved profile could not be verified. Nothing was shown as complete."
        }
    }
}

@MainActor
final class DriverProfileStore: ObservableObject {

    private struct ProfileResponse: Decodable {
        let name: String?
        let email: String?
        let phone: String?
        let avatar: String?
        let createdAt: String?
    }
    private struct CDLResponse: Decodable {
        let number: String?
        let `class`: String?
        let state: String?
        let endorsements: [String]?
        let expirationDate: String?
    }
    private struct MedicalResponse: Decodable {
        let expirationDate: String?
        let examinerName: String?
    }
    private struct TWICResponse: Decodable {
        let number: String?
        let expirationDate: String?
    }
    private struct DriverResponse: Decodable {
        let cdl: CDLResponse?
        let medicalCard: MedicalResponse?
        let twic: TWICResponse?
        let hazmatEndorsement: Bool?
        let tankerEndorsement: Bool?
        let homeTerminal: String?
        let hireDate: String?
        let yearsExperience: Double?
    }

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
        do {
            try await refreshAuthoritativeProfile()
            lastSaveError = nil
        } catch {
            lastSaveError = profileFailureMessage(
                error,
                fallback: "Your profile could not be refreshed."
            )
        }
    }

    private func profileFailureMessage(_ error: Error, fallback: String) -> String {
        if let profileError = error as? ProfileSaveError {
            return profileError.errorDescription ?? fallback
        }
        guard let apiError = error as? EusoTripAPIError else { return fallback }
        switch apiError {
        case .unauthenticated:
            return "Sign in again to update your profile."
        case .forbidden:
            return "This account is not permitted to update that profile."
        case .httpStatus(let code, _):
            return code == 401 || code == 403
                ? "Sign in again or confirm that this is your profile."
                : "Your profile could not be updated (error \(code)). Nothing was recorded as complete."
        case .decodingFailed, .empty:
            return "Your profile response could not be verified. Refresh before trying again."
        case .queuedForOfflineReplay:
            return "Your profile update needs an internet connection. Reconnect and try again."
        case .notConfigured, .badURL, .trpcError:
            return fallback
        }
    }

    private func refreshAuthoritativeProfile() async throws {
        async let profileRequest: ProfileResponse = EusoTripAPI.shared.queryNoInput("profile.getMyProfile")
        async let driverRequest: DriverResponse = EusoTripAPI.shared.queryNoInput("profile.getDriverProfile")
        let (p, dp) = try await (profileRequest, driverRequest)
        // Split combined `name` into first / last using whitespace as
        // the delimiter. First token = first name; the rest joined =
        // last name. Single-word names land entirely in `firstName`.
        let parts = (p.name ?? "").split(separator: " ", maxSplits: 1).map(String.init)
        self.firstName = parts.first ?? ""
        self.lastName = parts.count > 1 ? parts[1] : ""
        self.email = p.email ?? ""
        self.phone = p.phone ?? ""
        self.avatarData = Self.avatarBytes(from: p.avatar)
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
        if let avatarData { d.set(avatarData, forKey: Key.avatarData) }
        else { d.removeObject(forKey: Key.avatarData) }

        self.cdlNumber = dp.cdl?.number ?? ""
        self.licenseClass = dp.cdl?.class ?? ""
        self.cdlState = dp.cdl?.state ?? ""
        self.cdlEndorsements = dp.cdl?.endorsements ?? []
        self.cdlExpirationDate = dp.cdl?.expirationDate ?? ""
        self.medicalExpirationDate = dp.medicalCard?.expirationDate ?? ""
        self.medicalExaminerName = dp.medicalCard?.examinerName ?? ""
        self.twicNumber = dp.twic?.number ?? ""
        self.twicExpirationDate = dp.twic?.expirationDate ?? ""
        self.hazmatEndorsement = dp.hazmatEndorsement ?? false
        self.tankerEndorsement = dp.tankerEndorsement ?? false
        self.homeTerminal = dp.homeTerminal ?? ""
        self.hireDate = dp.hireDate ?? ""
        self.yearsExperience = Int(dp.yearsExperience ?? 0)
        d.set(self.licenseClass, forKey: Key.licenseClass)
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

    /// One awaited transaction for identity, photo and driver credentials.
    /// Local state changes only after the server returns its readback and a
    /// second authoritative fetch agrees with it.
    func saveProfileBundle(
        firstName: String,
        lastName: String,
        licenseClass: String,
        phone: String,
        avatarData: Data?,
        avatarChanged: Bool,
        cdlNumber: String,
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
    ) async throws {
        struct AvatarPayload: Encodable { let action: String; let value: String? }
        struct DriverPayload: Encodable {
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
        struct Input: Encodable {
            let firstName: String
            let lastName: String
            let phone: String
            let avatar: AvatarPayload
            let driver: DriverPayload
        }
        struct SavedProfile: Decodable {
            let name: String?
            let phone: String?
            let avatar: String?
        }
        struct Output: Decodable { let success: Bool; let profile: SavedProfile }

        let cleanFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLast = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanFirst.isEmpty else { throw ProfileSaveError.firstNameRequired }

        let avatarPayload: AvatarPayload
        if !avatarChanged {
            avatarPayload = AvatarPayload(action: "unchanged", value: nil)
        } else if let avatarData, !avatarData.isEmpty {
            let jpeg = try Self.compressedAvatarJPEG(avatarData)
            avatarPayload = AvatarPayload(
                action: "set",
                value: "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
            )
        } else {
            avatarPayload = AvatarPayload(action: "remove", value: nil)
        }
        let payload = Input(
            firstName: cleanFirst,
            lastName: cleanLast,
            phone: cleanPhone,
            avatar: avatarPayload,
            driver: DriverPayload(
                cdlNumber: cdlNumber, cdlClass: licenseClass, cdlState: cdlState,
                cdlEndorsements: cdlEndorsements, cdlExpirationDate: cdlExpirationDate,
                medicalExpirationDate: medicalExpirationDate,
                medicalExaminerName: medicalExaminerName, twicNumber: twicNumber,
                twicExpirationDate: twicExpirationDate,
                hazmatEndorsement: hazmatEndorsement,
                tankerEndorsement: tankerEndorsement, homeTerminal: homeTerminal,
                hireDate: hireDate, yearsExperience: yearsExperience
            )
        )
        do {
            let output: Output = try await EusoTripAPI.shared.mutation(
                "profile.saveProfileBundle",
                input: payload
            )
            let expectedName = "\(cleanFirst) \(cleanLast)".trimmingCharacters(in: .whitespaces)
            guard output.success,
                  output.profile.name == expectedName,
                  (output.profile.phone ?? "") == cleanPhone,
                  avatarPayload.action != "set" || output.profile.avatar == avatarPayload.value,
                  avatarPayload.action != "remove" || output.profile.avatar == nil else {
                throw ProfileSaveError.readbackMismatch
            }
            try await refreshAuthoritativeProfile()
            lastSaveError = nil
            NotificationCenter.default.post(name: .eusoProfileUpdated, object: nil)
        } catch {
            lastSaveError = profileFailureMessage(
                error,
                fallback: "Your profile was not saved. Nothing was recorded as complete."
            )
            throw error
        }
    }

    private static func avatarBytes(from raw: String?) -> Data? {
        guard let raw, !raw.isEmpty else { return nil }
        let encoded: String
        if raw.hasPrefix("data:"), let comma = raw.firstIndex(of: ",") {
            encoded = String(raw[raw.index(after: comma)...])
        } else if !raw.hasPrefix("https://") {
            encoded = raw
        } else {
            return nil
        }
        return Data(base64Encoded: encoded, options: .ignoreUnknownCharacters)
    }

    private static func compressedAvatarJPEG(_ source: Data) throws -> Data {
        #if canImport(UIKit)
        guard let image = UIImage(data: source) else { throw ProfileSaveError.unreadableAvatar }
        for dimension: CGFloat in [512, 384, 320, 256, 192, 128, 96] {
            let scale = min(dimension / max(image.size.width, 1), dimension / max(image.size.height, 1), 1)
            let size = CGSize(width: max(image.size.width * scale, 1), height: max(image.size.height * scale, 1))
            let format = UIGraphicsImageRendererFormat.default()
            format.opaque = true
            format.scale = 1
            let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.black.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            for quality: CGFloat in [0.82, 0.70, 0.58, 0.46, 0.34, 0.24] {
                if let jpeg = rendered.jpegData(compressionQuality: quality), jpeg.count <= 37_000 {
                    return jpeg
                }
            }
        }
        throw ProfileSaveError.avatarTooLarge
        #else
        throw ProfileSaveError.unreadableAvatar
        #endif
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
