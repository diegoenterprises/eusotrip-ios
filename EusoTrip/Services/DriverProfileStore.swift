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

    /// Raw bytes of the driver's avatar (JPEG). `nil` → fall back to the
    /// gradient monogram avatar the header already renders. We store PNG
    /// bytes, not a cached `UIImage`, so `@Published` equality checks stay
    /// cheap and UserDefaults can persist it across cold launch.
    @Published var avatarData: Data?

    // MARK: - Init

    /// Hydrate from UserDefaults when we have persisted edits, otherwise
    /// fall back to empty strings. The prior seed ("Michael Eusorone",
    /// "michael@eusorone.com", "+1 (713) 555-0142") was mock data — it's
    /// gone. Call-sites already branch to the `auth.me()`-derived value
    /// when these are empty, which is the correct first-launch behavior
    /// for an authenticated driver.
    init() {
        let d = UserDefaults.standard
        self.firstName       = d.string(forKey: Key.firstName)       ?? ""
        self.lastName        = d.string(forKey: Key.lastName)        ?? ""
        self.email           = d.string(forKey: Key.email)           ?? ""
        self.licenseClass    = d.string(forKey: Key.licenseClass)    ?? ""
        self.memberSinceYear = d.string(forKey: Key.memberSinceYear) ?? ""
        self.phone           = d.string(forKey: Key.phone)           ?? ""
        self.avatarData      = d.data(forKey: Key.avatarData)
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
