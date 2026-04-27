//
//  ConvoySignature.swift
//  EusoTrip Pulse Watch App
//
//  F13 — Convoy envelope signing.
//
//  Every outbound convoy envelope carries a P-256 ECDSA signature
//  computed against the envelope's canonical byte representation.
//  Every inbound envelope is verified before being handed to the
//  coordinator's ingest pipeline. Unsigned or mis-signed envelopes
//  are dropped on the floor — they never reach `ConvoyCoordinator`.
//
//  Why P-256 instead of Ed25519:
//    Ed25519 has nicer properties (smaller signatures, faster
//    signing, no signature-malleability surface). But the Secure
//    Enclave on Apple Watch ONLY supports P-256 ECDSA. Using
//    software Ed25519 keys would mean the private key sits in the
//    keychain where any process with the app's keychain entitlement
//    could extract it. The whole point of cryptographically
//    identifying a convoy member is that a compromised companion
//    app can't forge messages from the wrist. So we take the
//    slightly larger 70-byte ECDSA signatures in exchange for
//    the physical key isolation.
//
//  Trust model: trust-on-first-use, backed by a fleet-roster
//  verification call to the server when connectivity allows.
//    1. Heartbeat envelopes include the sender's public key.
//    2. The first time we see a heartbeat from driver X, we pin
//       their public key locally.
//    3. Every subsequent envelope from X must verify against the
//       pinned key. Mis-signed → dropped.
//    4. When terrestrial connectivity returns, the coordinator
//       posts the pinned key to `fleet.verifyConvoyMember`. A
//       successful roster match upgrades the key to "confirmed."
//       A rejected match downgrades the peer to "suspect," still
//       visible in the convoy list but flagged in red.
//
//  Persistence:
//    • Private key reference (SEP-opaque bytes) → Keychain item
//      with kSecAttrAccessibleAfterFirstUnlock.
//    • TOFU table (driverId → publicKey) → Application Support
//      JSON file. Rebuildable from the network if corrupted.
//

import Foundation
import CryptoKit
import Security

@MainActor
final class ConvoySignature {
    static let shared = ConvoySignature()

    // MARK: - Keychain tags

    /// Keychain tag for the SEP-backed private key reference.
    /// Stored as a generic password so it survives app reinstalls
    /// when the same device is used (keychain migration).
    private let keychainAccount = "com.eusotrip.convoy.signingKey.v1"
    private let keychainService = "com.eusotrip.convoy"

    // MARK: - State

    /// The local signing key. Lazily loaded from keychain on first
    /// access, generated if absent. Never leaves this class.
    private var signingKey: SecureEnclave.P256.Signing.PrivateKey?

    /// Pinned peer public keys — driverId → P256 public key.
    /// Loaded from disk at launch, persisted on every new pin.
    private var pinnedPeerKeys: [String: P256.Signing.PublicKey] = [:]

    /// Peers we've posted to the server for roster verification.
    /// Each carries the resolution state: unknown (no reply yet),
    /// confirmed (server matched), suspect (server rejected).
    /// `Equatable` so the SwiftUI adapter can diff frames; `Hashable`
    /// so `[String: PeerTrustState]` itself is comparable.
    enum PeerTrustState: Equatable, Hashable { case unknown, confirmed, suspect }
    private var peerTrustStates: [String: PeerTrustState] = [:]

    // MARK: - File URL

    private let pinnedKeysFileURL: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("convoy-pinned-keys.json")
    }()

    // MARK: - Bootstrap

    /// Load the private key from keychain (or generate one), then
    /// restore the pinned-peer-key table. Safe to call multiple
    /// times — subsequent calls after a successful bootstrap no-op.
    func bootstrap() {
        if signingKey == nil {
            signingKey = loadOrCreateSigningKey()
        }
        restorePinnedKeys()
    }

    /// Has the signing layer successfully initialized? False on
    /// devices without a Secure Enclave (iPhone Simulator, older
    /// Apple Watches before Series 3). Callers use this to decide
    /// whether to degrade to unsigned operation or fail closed.
    var isReady: Bool {
        signingKey != nil
    }

    /// Base64-encoded raw representation of the local public key.
    /// Embedded in heartbeat envelopes so peers can pin on TOFU.
    var localPublicKeyB64: String? {
        guard let key = signingKey else { return nil }
        return key.publicKey.rawRepresentation.base64EncodedString()
    }

    // MARK: - Signing

    /// Produce a P-256 ECDSA signature over `payload`. Returns nil
    /// if the signing key isn't available (SEP unsupported).
    func sign(_ payload: Data) -> Data? {
        guard let key = signingKey else { return nil }
        do {
            let sig = try key.signature(for: payload)
            return sig.rawRepresentation
        } catch {
            return nil
        }
    }

    /// Verify a signature against a pinned peer's public key.
    ///
    /// If we have no pinned key for `driverId`, the peer presented
    /// `presentedPublicKey` in their envelope (typical for a first
    /// heartbeat), we pin it AND verify against the just-pinned
    /// key. This is the TOFU step.
    ///
    /// Returns true on successful verification, false otherwise.
    func verify(
        _ signature: Data,
        payload: Data,
        fromDriverId driverId: String,
        presentedPublicKeyB64: String?
    ) -> Bool {
        let pubKey: P256.Signing.PublicKey

        if let pinned = pinnedPeerKeys[driverId] {
            pubKey = pinned
        } else if let raw = presentedPublicKeyB64,
                  let rawData = Data(base64Encoded: raw),
                  let parsed = try? P256.Signing.PublicKey(rawRepresentation: rawData) {
            // First sighting of this driver — TOFU pin.
            pinnedPeerKeys[driverId] = parsed
            peerTrustStates[driverId] = .unknown
            persistPinnedKeys()
            pubKey = parsed
        } else {
            // No pinned key AND no presented key → we have no way
            // to verify. Drop the envelope.
            return false
        }

        guard let parsedSig = try? P256.Signing.ECDSASignature(rawRepresentation: signature) else {
            return false
        }
        return pubKey.isValidSignature(parsedSig, for: payload)
    }

    /// Canonical bytes of an envelope, suitable for both signing
    /// and verification. Sorting the fields by key makes this
    /// deterministic across devices / languages. Signatures computed
    /// this way survive any implementation-detail differences in
    /// how the envelope got into memory (decoded, hand-built, etc).
    ///
    /// `nonisolated` because this is a pure function over its inputs.
    /// Keeping it off the main actor lets the BLE delegate queue
    /// recompute canonical bytes during signature verification
    /// without hopping to @MainActor first — which matters when
    /// verifying a high-volume heartbeat stream on hardware.
    nonisolated static func canonicalBytes(
        id: String,
        kind: String,
        fromDriverId: String,
        sentAt: Date,
        fields: [String: String]
    ) -> Data {
        let sortedPairs = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        let joined = [
            id,
            kind,
            fromDriverId,
            String(sentAt.timeIntervalSince1970),
            sortedPairs
        ].joined(separator: "|")
        return Data(joined.utf8)
    }

    // MARK: - Trust state queries

    func trustState(for driverId: String) -> PeerTrustState {
        peerTrustStates[driverId] ?? .unknown
    }

    /// Called by the roster-verification path (see comment at top)
    /// after the server has matched the pinned key against the
    /// fleet roster. Persists immediately so a reboot mid-trip
    /// doesn't erase a confirmation we paid a round-trip for.
    func setTrustState(_ state: PeerTrustState, for driverId: String) {
        peerTrustStates[driverId] = state
        persistPinnedKeys()
    }

    /// Snapshot of every driver we've TOFU-pinned, paired with the
    /// base64-encoded raw public-key bytes and the current trust
    /// state. The reconciler uses this to build a batch that can be
    /// posted to `fleet.verifyConvoyMember` on the phone.
    ///
    /// Callers typically filter down to `.unknown` before posting —
    /// we don't want to re-verify confirmed peers on every reconcile.
    struct PinnedEntry: Equatable {
        let driverId: String
        let pinnedPublicKeyB64: String
        let trust: PeerTrustState
    }

    func pinnedEntries() -> [PinnedEntry] {
        pinnedPeerKeys.map { (driverId, key) in
            PinnedEntry(
                driverId: driverId,
                pinnedPublicKeyB64: key.rawRepresentation.base64EncodedString(),
                trust: peerTrustStates[driverId] ?? .unknown
            )
        }
    }

    /// Drop a pinned key entirely. Called by the reconciler when
    /// the server reports `unknown` (driverId doesn't exist in any
    /// roster) — we don't want to keep verifying a ghost peer, and
    /// we definitely don't want future envelopes from that driverId
    /// to TOFU-succeed against the stale pin. Next heartbeat from
    /// the peer (if any) will re-pin.
    func dropPin(for driverId: String) {
        pinnedPeerKeys.removeValue(forKey: driverId)
        peerTrustStates.removeValue(forKey: driverId)
        persistPinnedKeys()
    }

    // MARK: - Persistence

    private func loadOrCreateSigningKey() -> SecureEnclave.P256.Signing.PrivateKey? {
        // Short-circuit on devices without SEP (Simulator).
        guard SecureEnclave.isAvailable else { return nil }

        if let existing = readPrivateKeyBytesFromKeychain(),
           let reconstructed = try? SecureEnclave.P256.Signing.PrivateKey(
               dataRepresentation: existing
           ) {
            return reconstructed
        }

        // First launch — generate a new key and persist its
        // SEP-opaque reference bytes. These bytes are NOT the
        // actual private key — they're a handle the SEP returns
        // when asked to recall the key in a future session. The
        // actual key material physically cannot leave the SEP.
        do {
            let fresh = try SecureEnclave.P256.Signing.PrivateKey()
            writePrivateKeyBytesToKeychain(fresh.dataRepresentation)
            return fresh
        } catch {
            return nil
        }
    }

    private func readPrivateKeyBytesFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return nil }
        return data
    }

    private func writePrivateKeyBytesToKeychain(_ data: Data) {
        // Delete any stale entry first — SecItemAdd fails on
        // duplicates and we don't want a half-migrated state.
        let deleteQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    keychainService,
            kSecAttrAccount as String:    keychainAccount,
            kSecValueData as String:      data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func restorePinnedKeys() {
        guard let data = try? Data(contentsOf: pinnedKeysFileURL) else { return }
        struct Snapshot: Codable {
            var pinned: [String: Data]          // driverId → raw pubkey bytes
            var trusts: [String: String]        // driverId → trust raw value
        }
        guard let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        for (driverId, rawBytes) in snap.pinned {
            if let pub = try? P256.Signing.PublicKey(rawRepresentation: rawBytes) {
                pinnedPeerKeys[driverId] = pub
            }
        }
        for (driverId, rawTrust) in snap.trusts {
            switch rawTrust {
            case "confirmed": peerTrustStates[driverId] = .confirmed
            case "suspect":   peerTrustStates[driverId] = .suspect
            default:          peerTrustStates[driverId] = .unknown
            }
        }
    }

    private func persistPinnedKeys() {
        struct Snapshot: Codable {
            var pinned: [String: Data]
            var trusts: [String: String]
        }
        let pinned = pinnedPeerKeys.mapValues { $0.rawRepresentation }
        let trusts = peerTrustStates.mapValues { state -> String in
            switch state {
            case .confirmed: return "confirmed"
            case .suspect:   return "suspect"
            case .unknown:   return "unknown"
            }
        }
        let snap = Snapshot(pinned: pinned, trusts: trusts)
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: pinnedKeysFileURL, options: .atomic)
        }
    }
}
