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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    private func keychainRead(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainDelete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
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
}

// Convenience singleton accessor for use inside WCSessionDelegate callbacks
// (which run off the main actor). The app assigns this at launch.
extension AuthStore {
    nonisolated(unsafe) static weak var shared: AuthStore?
}
