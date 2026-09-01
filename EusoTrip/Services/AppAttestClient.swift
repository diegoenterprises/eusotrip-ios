//
//  AppAttestClient.swift
//  EusoTrip — Apple App Attest (DCAppAttestService) hardware-attestation
//  client for high-trust calls.
//
//  WHAT THIS IS
//  ------------
//  A thin, FAIL-SOFT wrapper around Apple's App Attest service. It proves
//  that a high-trust request (wallet cash-out / KYC identity submit / SOS
//  trigger) originates from a genuine, unmodified instance of this app on
//  a real device, by signing a server-issued challenge with a Secure-
//  Enclave-backed key that Apple's servers vouch for.
//
//  Server counterpart (PR #107):
//    • appAttest.challenge  → issues a one-time nonce (base64).
//    • appAttest.register   → verifies the one-time attestation object,
//                             binding our keyId to this app + device.
//    • assertHighTrust(...)  on the gated procs (wallet payout / KYC
//                             submit / SOS) reads an OPTIONAL `_attest`
//                             field. Production enforcement is strict and
//                             rejects missing or unverifiable proof; local
//                             development uses the documented soft rollout.
//
//  THE BINDING — HONEST CLIENT RESULT, STRICT PRODUCTION GATE
//  ----------------------------------------------------------
//  `isSupported` (simulator, older device, or unavailable App Attest service)
//  short-circuits to `nil`. Key generation, registration, challenge, or
//  assertion failures also return `nil` so callers can encode the request
//  deterministically. Production high-trust routes then reject that missing
//  proof; development may admit it only under the server's explicit soft
//  rollout mode. The client never fabricates a successful attestation.
//
//  No entitlement is required: DeviceCheck / App Attest is automatic.
//
//  THREADING
//  ---------
//  All public entry points are `async` and `nonisolated` (this is a plain
//  actor-free enum over a global serial executor: DCAppAttestService is
//  thread-safe, and the per-key state is serialized through `keyId(...)`).
//  Per-request work runs off the main actor so the UI is never blocked.
//

import Foundation
#if canImport(DeviceCheck)
import DeviceCheck
#endif
import CryptoKit

enum AppAttestClient {

    // MARK: - Configuration

    /// Keychain anchors for the persisted attested keyId. Bumped if the
    /// attestation format/contract ever changes — clients then re-generate
    /// + re-attest a fresh key on next high-trust call.
    private static let kcService = "com.eusotrip.appattest.keyid.v1"
    private static let kcAccount = "primary"

    /// tRPC procedure paths for the server attestation seam (PR #107).
    private static let challengePath = "appAttest.challenge"
    private static let registerPath  = "appAttest.register"

    /// Hard ceiling on the attestation round-trip so a stalled network can
    /// never make a high-trust call wait on App Attest. If we don't have an
    /// assertion within this budget we give up and return nil (fail-soft).
    /// Comfortably under the shared session's 22s request timeout.
    private static let timeoutSeconds: UInt64 = 6

    // MARK: - Support gate

    /// True only on a real device where App Attest is available. Simulator
    /// and older/unsupported hardware report false → every call no-ops to
    /// nil. This is the single gate that keeps the feature honest.
    static var isSupported: Bool {
        #if canImport(DeviceCheck)
        if #available(iOS 14.0, *) {
            return DCAppAttestService.shared.isSupported
        }
        return false
        #else
        return false
        #endif
    }

    // MARK: - Public API

    /// Best-effort per-request assertion over a caller-supplied client-data
    /// hash, wrapped in the canonical `_attest` envelope the server expects.
    ///
    /// Returns `nil` — NEVER throws — when:
    ///   • App Attest is unsupported (simulator / old device), or
    ///   • the challenge round-trip, key registration, or assertion fails,
    ///   • or the whole thing exceeds `timeoutSeconds`.
    ///
    /// On `nil` the caller sends the high-trust mutation without `_attest`.
    /// Production strict mode rejects it; development soft mode may allow it.
    ///
    /// - Parameter context: stable, low-cardinality bytes that pin the
    ///   assertion to *this* request (e.g. "wallet.requestPayout|<amount>").
    ///   The server's challenge nonce is folded in automatically, so the
    ///   assertion is anti-replay even if `context` repeats.
    static func attestation(for context: Data) async -> AttestEnvelope? {
        guard isSupported else { return nil }

        // Bound the whole best-effort flow. If anything stalls past the
        // budget we abandon attestation and return nil rather than waiting on
        // the network. The server's configured enforcement mode decides it.
        return await withTaskGroupTimeout(seconds: timeoutSeconds) {
            await buildAttestation(for: context)
        }
    }

    /// Convenience: assert over a UTF-8 context string.
    static func attestation(forContext string: String) async -> AttestEnvelope? {
        await attestation(for: Data(string.utf8))
    }

    // MARK: - Wire envelope

    /// The optional `_attest` field attached to a gated high-trust mutation.
    /// Encodes to the canonical App Attest assertion shape the server's
    /// `assertHighTrust` reads (production rejects an absent envelope):
    ///   { keyId, challenge, clientDataHash, assertion }
    /// All four are base64. `challenge` is the exact nonce the server issued
    /// via appAttest.challenge (round-trips so the server can match + burn
    /// it); `clientDataHash` is SHA256(challenge ‖ context) — what we
    /// actually signed; `assertion` is DCAppAttestService's CBOR blob.
    struct AttestEnvelope: Encodable, Sendable {
        let keyId: String
        let challenge: String
        let clientDataHash: String
        let assertion: String
    }

    // MARK: - Core flow (all internal, all swallow errors)

    private static func buildAttestation(for context: Data) async -> AttestEnvelope? {
        #if canImport(DeviceCheck)
        guard #available(iOS 14.0, *) else { return nil }
        let service = DCAppAttestService.shared
        guard service.isSupported else { return nil }

        do {
            // 1) Ensure we have a registered (attested) keyId. Generated +
            //    attested once, then reused for every subsequent assertion.
            let keyId = try await ensureAttestedKey(service: service)

            // 2) Fetch a fresh one-time challenge from the server.
            let challengeB64 = try await fetchChallenge()
            guard let challengeData = Data(base64Encoded: challengeB64) else { return nil }

            // 3) clientDataHash = SHA256(challenge ‖ context). Binding the
            //    server nonce makes the assertion anti-replay; binding the
            //    request context pins it to this specific high-trust call.
            var hasher = SHA256()
            hasher.update(data: challengeData)
            hasher.update(data: context)
            let clientDataHash = Data(hasher.finalize())

            // 4) Generate the per-request assertion. Apple may throw
            //    `invalidKey` if the key was wiped server/Keychain-side out
            //    of sync; in that case drop our cached keyId and re-attest
            //    once, then retry the assertion. Still fail-soft on failure.
            let assertion: Data
            do {
                assertion = try await service.generateAssertion(keyId, clientDataHash: clientDataHash)
            } catch {
                // One self-heal attempt: clear + re-attest, then retry.
                clearKeyId()
                let freshKeyId = try await ensureAttestedKey(service: service)
                let retried = try await service.generateAssertion(freshKeyId, clientDataHash: clientDataHash)
                return AttestEnvelope(
                    keyId: freshKeyId,
                    challenge: challengeB64,
                    clientDataHash: clientDataHash.base64EncodedString(),
                    assertion: retried.base64EncodedString()
                )
            }

            return AttestEnvelope(
                keyId: keyId,
                challenge: challengeB64,
                clientDataHash: clientDataHash.base64EncodedString(),
                assertion: assertion.base64EncodedString()
            )
        } catch {
            // Any failure is reported honestly as no attestation. Production
            // high-trust routes reject it; no fake proof is ever synthesized.
            return nil
        }
        #else
        return nil
        #endif
    }

    #if canImport(DeviceCheck)
    /// Returns a keyId whose key has been attested + registered server-side.
    /// Reuses the persisted keyId when present; otherwise generates a fresh
    /// Secure-Enclave key, attests it against a server challenge, registers
    /// it, and persists the keyId for reuse. Throws on failure (the single
    /// caller swallows it → fail-soft).
    @available(iOS 14.0, *)
    private static func ensureAttestedKey(service: DCAppAttestService) async throws -> String {
        if let existing = loadKeyId() { return existing }

        // 1) Fresh hardware key (private key never leaves the Secure Enclave).
        let keyId = try await service.generateKey()

        // 2) One-time attestation: bind keyId to app+device over a server
        //    challenge. Apple's CBOR attestation object goes to the server.
        let challengeB64 = try await fetchChallenge()
        guard let challengeData = Data(base64Encoded: challengeB64) else {
            throw AttestError.badChallenge
        }
        let attestHash = Data(SHA256.hash(data: challengeData))
        let attestationObject = try await service.attestKey(keyId, clientDataHash: attestHash)

        // 3) Server-side register: verifies the attestation, stores the
        //    public key bound to keyId. Throws if the server rejects it.
        try await registerKey(
            keyId: keyId,
            attestation: attestationObject.base64EncodedString(),
            challenge: challengeB64
        )

        // 4) Persist only AFTER a successful server register so a failed
        //    registration is retried (not silently reused) next time.
        storeKeyId(keyId)
        return keyId
    }
    #endif

    // MARK: - Server round-trips (appAttest.challenge / appAttest.register)

    private struct ChallengeAck: Decodable { let challenge: String }
    private struct EmptyInput: Encodable {}

    /// GET-equivalent: ask the server for a one-time base64 challenge nonce.
    private static func fetchChallenge() async throws -> String {
        let ack: ChallengeAck = try await EusoTripAPI.shared.mutation(
            challengePath, input: EmptyInput()
        )
        return ack.challenge
    }

    private struct RegisterInput: Encodable {
        let keyId: String
        let attestation: String
        let challenge: String
    }
    private struct RegisterAck: Decodable { let ok: Bool? }

    /// POST: hand the one-time attestation object to the server to verify +
    /// bind keyId. Throws if the server rejects (caller re-attests / drops).
    private static func registerKey(keyId: String, attestation: String, challenge: String) async throws {
        let _: RegisterAck = try await EusoTripAPI.shared.mutation(
            registerPath,
            input: RegisterInput(keyId: keyId, attestation: attestation, challenge: challenge)
        )
    }

    // MARK: - Keychain (persisted keyId)

    private static func loadKeyId() -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: kcService,
            kSecAttrAccount as String: kcAccount,
            kSecReturnData as String:  true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let s = String(data: data, encoding: .utf8),
              !s.isEmpty else { return nil }
        return s
    }

    private static func storeKeyId(_ keyId: String) {
        let delQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: kcService,
            kSecAttrAccount as String: kcAccount,
        ]
        SecItemDelete(delQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    kcService,
            kSecAttrAccount as String:    kcAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String:      Data(keyId.utf8),
        ]
        // Best-effort: a Keychain failure just means we re-attest next time.
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func clearKeyId() {
        let delQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: kcService,
            kSecAttrAccount as String: kcAccount,
        ]
        SecItemDelete(delQuery as CFDictionary)
    }

    // MARK: - Errors + timeout helper

    private enum AttestError: Error { case badChallenge }

    /// Runs `work` with a hard timeout. Returns `nil` if the budget elapses
    /// first — the attestation is abandoned and nil is returned. Never throws
    /// to the caller; server policy remains authoritative.
    private static func withTaskGroupTimeout(
        seconds: UInt64,
        _ work: @escaping @Sendable () async -> AttestEnvelope?
    ) async -> AttestEnvelope? {
        await withTaskGroup(of: AttestEnvelope?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                return nil
            }
            // First non-nil wins; if the timeout fires first we get nil.
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
