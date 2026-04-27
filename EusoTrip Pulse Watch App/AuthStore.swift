//
//  AuthStore.swift
//  EusoTrip Watch App
//
//  Holds the Esang auth token on the watch. Populated by the iOS
//  companion app via WCSession applicationContext when the user signs in
//  on the phone. Persisted to Keychain between launches.
//

import Foundation
import Security
import Combine

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var token: String?
    @Published private(set) var userId: String?
    @Published private(set) var userName: String?
    @Published private(set) var role: String? // "driver" | "dispatcher" | "broker" | "shipper"

    var isSignedIn: Bool { token != nil }

    var firstName: String? {
        userName?.split(separator: " ").first.map(String.init)
    }

    private let service = "com.eusotrip.watch.auth"
    private let tokenAccount = "esang.token"
    private let userAccount = "esang.user"
    private let roleAccount = "esang.role"

    /// Shared keychain access group — matches the Pulse watch +
    /// iPhone companion entitlements so either bundle can read the
    /// other's Esang auth token. Dropping this into every SecItem*
    /// query removes WCSession as the single pairing transport SPOF
    /// (L3, per synth_B).
    ///
    /// Format: `$(AppIdentifierPrefix)com.app.eusotrip.shared`. We
    /// resolve the team prefix at runtime from the bundle so this
    /// builds without hard-coding a team ID.
    private static let accessGroupSuffix = "com.app.eusotrip.shared"

    private var accessGroup: String {
        // `kSecAttrAccessGroup` wants the full prefixed identifier. We
        // derive it from the running bundle's seed id when available;
        // on first run we query keychain for the seed and cache it.
        if let cached = Self._cachedAccessGroup { return cached }
        let prefix = Self.resolveTeamPrefix()
        let group = "\(prefix)\(Self.accessGroupSuffix)"
        Self._cachedAccessGroup = group
        return group
    }

    nonisolated(unsafe) private static var _cachedAccessGroup: String?

    private static func resolveTeamPrefix() -> String {
        // Query keychain for our bundleSeedID. The approach: add a
        // throwaway generic-password item with no access group + read
        // it back to observe the resolved group. Failures fall back
        // to empty — in which case kSecAttrAccessGroup is simply
        // omitted from the query (back-compat with today's behavior).
        let queryAdd: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "com.eusotrip.seedid.probe",
            kSecAttrService as String: "com.eusotrip.seedid.probe",
            kSecReturnAttributes as String: true,
        ]
        var ref: AnyObject?
        var status = SecItemCopyMatching(queryAdd as CFDictionary, &ref)
        if status == errSecItemNotFound {
            var addQuery = queryAdd
            addQuery[kSecValueData as String] = Data("probe".utf8)
            status = SecItemAdd(addQuery as CFDictionary, &ref)
        }
        if status == errSecSuccess,
           let dict = ref as? [String: Any],
           let full = dict[kSecAttrAccessGroup as String] as? String,
           let dot = full.firstIndex(of: ".") {
            return String(full[..<full.index(after: dot)])
        }
        return ""
    }

    // MARK: - Bootstrap

    func restore() {
        if let t = keychainRead(account: tokenAccount) {
            token = t
        }
        if let data = keychainRead(account: userAccount)?.data(using: .utf8),
           let info = try? JSONDecoder().decode(UserInfo.self, from: data) {
            userId = info.id
            userName = info.name
        }
        if let r = keychainRead(account: roleAccount) {
            role = r
        }
    }

    /// Called when iOS pushes a new session context via WCSession.
    func update(token: String?, userId: String?, userName: String?, role: String? = nil) {
        self.token = token
        self.userId = userId
        self.userName = userName
        self.role = role

        if let token {
            keychainWrite(account: tokenAccount, value: token)
        } else {
            keychainDelete(account: tokenAccount)
        }

        if let userId {
            let info = UserInfo(id: userId, name: userName)
            if let data = try? JSONEncoder().encode(info),
               let str = String(data: data, encoding: .utf8) {
                keychainWrite(account: userAccount, value: str)
            }
        } else {
            keychainDelete(account: userAccount)
        }

        if let role {
            keychainWrite(account: roleAccount, value: role)
        } else {
            keychainDelete(account: roleAccount)
        }
    }

    // MARK: - Keychain helpers

    private struct UserInfo: Codable {
        let id: String
        let name: String?
    }

    @discardableResult
    private func keychainWrite(account: String, value: String) -> Bool {
        let data = Data(value.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let group = accessGroup
        if !group.isEmpty {
            query[kSecAttrAccessGroup as String] = group
        }
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    private func keychainRead(account: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        let group = accessGroup
        if !group.isEmpty {
            query[kSecAttrAccessGroup as String] = group
        }
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainDelete(account: String) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let group = accessGroup
        if !group.isEmpty {
            query[kSecAttrAccessGroup as String] = group
        }
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Preview helper
    static var preview: AuthStore {
        let s = AuthStore()
        s.token = "preview-token"
        s.userId = "42"
        s.userName = "Michael Reyes"
        s.role = "driver"
        return s
    }

    #if DEBUG
    /// Simulator-only bootstrap. On a paired physical watch you always
    /// wait for the companion iPhone to push an `auth.update` through
    /// WCSession; in the simulator there IS no paired companion, so the
    /// orb screen sits on "Open EusoTrip on iPhone to pair" forever.
    /// Lay down a synthetic driver identity so the rest of the app
    /// (Instrument Panel, HOS, Loads, Messaging) becomes reachable for
    /// visual QA. The keychain writes behind `update(...)` only live
    /// inside the simulator container.
    func mockSignInForSimulator() {
        guard token == nil else { return }
        update(
            token: "sim-debug-token",
            userId: "sim-42",
            userName: "Michael Reyes",
            role: "driver"
        )
    }
    #endif
}

// Convenience singleton accessor for use inside WCSessionDelegate callbacks
// (which run off the main actor). The app assigns this at launch.
extension AuthStore {
    nonisolated(unsafe) static weak var shared: AuthStore?
}
