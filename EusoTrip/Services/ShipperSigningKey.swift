//
//  ShipperSigningKey.swift
//  T-014 (2026-05-20) — Persistent Ed25519 identity key for shipper-side
//  agreement signing. Keychain-backed so the key survives app reinstall
//  scenarios (kSecAttrAccessibleAfterFirstUnlock) and the public key is
//  consistent across signing sessions — letting the server verify every
//  past signature against the same key.
//
//  Audit gap (01_AUDIT_FINDINGS_SYNTHESIS.md §3, Agreement Wizard):
//    "Signature is base64 PNG only — no Ed25519 cryptographic signing /
//     No hash chaining (parent hashChainAnchor exists but not wired
//     to agreement)."
//
//  This service is the shipper-side counterpart to `Vehicle.identityChain`
//  on the driver-asset side. Catalyst / Broker / Driver each get their
//  own variant in T-014b once the contract surface stabilizes.
//

import Foundation
import CryptoKit

public enum ShipperSigningKey {

    /// Keychain service + account anchors. Bumped if the key format
    /// ever changes — clients then re-generate on next sign.
    private static let kcService = "com.eusotrip.shipper.signing.ed25519.v1"
    private static let kcAccount = "primary"

    /// Returns the persistent Ed25519 private key. Generates one on
    /// first use and stores it in Keychain (after-first-unlock so a
    /// background sync can sign without user interaction once the
    /// device has been unlocked at least once since reboot).
    public static func current() throws -> Curve25519.Signing.PrivateKey {
        if let raw = try loadFromKeychain() {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
        }
        let fresh = Curve25519.Signing.PrivateKey()
        try storeToKeychain(fresh.rawRepresentation)
        return fresh
    }

    /// Public key the server uses to verify signatures. Base64 raw
    /// representation matches the standard wire format used by
    /// CryptoKit on the verifying side.
    public static func currentPublicKeyB64() throws -> String {
        try current().publicKey.rawRepresentation.base64EncodedString()
    }

    /// Sign an arbitrary payload (typically the SHA-256 of the
    /// canonical signing-context tuple). Returns base64 signature
    /// bytes for direct wire serialization.
    public static func sign(_ payload: Data) throws -> String {
        let key = try current()
        let sig = try key.signature(for: payload)
        return sig.base64EncodedString()
    }

    /// Compose the canonical signing-context tuple and SHA-256 it.
    /// Inputs:
    ///   - agreementBody: server-generated contract text (the bytes
    ///                    the parties are committing to)
    ///   - signatureDataURL: base64 PNG of the gradient signature pad
    ///   - timestampISO: ISO-8601 timestamp of the signing event
    /// The order matters: a different order produces a different hash,
    /// so server-side verifier must use the same ordering.
    public static func canonicalDigest(
        agreementBody: String,
        signatureDataURL: String,
        timestampISO: String
    ) -> Data {
        var hasher = SHA256()
        hasher.update(data: Data(agreementBody.utf8))
        hasher.update(data: Data(signatureDataURL.utf8))
        hasher.update(data: Data(timestampISO.utf8))
        return Data(hasher.finalize())
    }

    // MARK: - Keychain primitives

    private static func loadFromKeychain() throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: kcService,
            kSecAttrAccount as String: kcAccount,
            kSecReturnData as String:  true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw NSError(
                domain: "ShipperSigningKey",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Keychain load failed (OSStatus \(status))"]
            )
        }
        _ = query   // silence unused warning if compiler ever objects
    }

    private static func storeToKeychain(_ data: Data) throws {
        // Delete any stale entry first so SecItemAdd doesn't return
        // duplicate-item — happens after Keychain restores from a
        // backup that included a partial entry.
        let delQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: kcService,
            kSecAttrAccount as String: kcAccount,
        ]
        SecItemDelete(delQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     kcService,
            kSecAttrAccount as String:     kcAccount,
            kSecAttrAccessible as String:  kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String:       data,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(
                domain: "ShipperSigningKey",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Keychain save failed (OSStatus \(status))"]
            )
        }
    }
}
