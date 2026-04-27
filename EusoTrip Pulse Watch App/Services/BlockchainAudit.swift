//
//  BlockchainAudit.swift
//  EusoTrip Pulse Watch App
//
//  Q4 2026 offline-mode tier — tamper-evident local audit log.
//
//  Not a cryptocurrency. Not a public chain. What we actually need:
//    A local append-only log where every entry's SHA-256 includes the
//    hash of the previous entry. A server-side periodic anchor records
//    the tip hash + a signed timestamp so the driver can prove — in
//    a roadside inspection or a trailer-theft dispute — that a given
//    event was logged at the claimed moment, unchanged since.
//
//  Use cases:
//    • FMCSA ELD log integrity — HOS status changes chain to each
//      other; an auditor can replay the chain + verify every hash.
//    • POD (proof-of-delivery) — the VisionKit scan hash chains into
//      the log so a consignee dispute can't falsify the scan time.
//    • Chain-of-custody for hazmat escort — every coordinate handoff
//      is a block; breaking the chain = evidence of tampering.
//
//  Storage: append-only JSON-lines file under Application Support.
//  A 30-entry rolling window is cached in memory for fast verification.
//  Periodic server anchor: the tip hash is posted to `audit.anchor`
//  with the driver's signature; the server counter-signs and returns
//  a Merkle proof the driver can carry offline.
//

import Foundation
import Combine
import CryptoKit

enum AuditKind: String, Codable {
    case hosStatus       = "hos.status"
    case loadAccept      = "load.accept"
    case loadArrived     = "load.arrived"
    case podScan         = "pod.scan"
    case hazmatHandoff   = "hazmat.handoff"
    case emergency       = "emergency"
    case voiceIntent     = "voice.intent"
}

struct AuditBlock: Codable, Equatable {
    let index: UInt64
    let ts: Date
    let kind: AuditKind
    let payload: [String: String]   // small, opaque — large blobs go to CAS
    let prevHash: String            // hex of previous block's hash
    let hash: String                // hex of this block's hash

    /// Compute this block's hash from its fields, EXCLUDING `hash` itself.
    static func computeHash(
        index: UInt64,
        ts: Date,
        kind: AuditKind,
        payload: [String: String],
        prevHash: String
    ) -> String {
        let sortedPayload = payload
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        let joined = "\(index)|\(ts.timeIntervalSince1970)|\(kind.rawValue)|\(sortedPayload)|\(prevHash)"
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// A counter-signed server anchor the watch persists so the driver can
/// prove chain integrity offline (e.g. at a roadside inspection when
/// the truck has no signal). Wire-shaped like an SCT: the server gives
/// us back the tip hash it saw, a merkle root it computed over the
/// anchored window, its own signature over the envelope, and a wall
/// clock the auditor can cross-reference against regulated time.
struct AuditAnchorProof: Codable, Equatable {
    let driverId: String
    let tipIndex: UInt64
    let tipHash: String
    let merkleRoot: String
    /// Driver-side P-256 ECDSA signature over the canonical envelope.
    let driverSignatureB64: String
    /// Server-side counter-signature over (envelope ‖ driverSignature).
    let serverSignatureB64: String
    /// Server wall-clock at anchor time (ISO-8601 UTC).
    let anchoredAt: String
}

@MainActor
final class BlockchainAudit: ObservableObject {
    static let shared = BlockchainAudit()

    @Published private(set) var tipHash: String = String(repeating: "0", count: 64)
    @Published private(set) var length: UInt64 = 0
    @Published private(set) var latestAnchor: AuditAnchorProof?
    @Published private(set) var lastAnchorError: String?

    private let fileURL: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("audit-chain.jsonl")
    }()

    /// Where the latest server-countersigned anchor proof is cached so
    /// the driver can present it during an offline inspection.
    private let anchorURL: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("audit-anchor.json")
    }()

    private var recentCache: [AuditBlock] = [] // last 30 blocks

    func restore() {
        if let data = try? Data(contentsOf: fileURL),
           let text = String(data: data, encoding: .utf8) {
            var blocks: [AuditBlock] = []
            for line in text.split(separator: "\n") where !line.isEmpty {
                if let b = try? JSONDecoder().decode(AuditBlock.self, from: Data(line.utf8)) {
                    blocks.append(b)
                }
            }
            recentCache = Array(blocks.suffix(30))
            if let last = blocks.last {
                tipHash = last.hash
                length = last.index + 1
            }
        }
        // Restore last server-countersigned anchor so the driver's
        // offline-inspection proof survives a watch relaunch.
        if let data = try? Data(contentsOf: anchorURL),
           let proof = try? JSONDecoder().decode(AuditAnchorProof.self, from: data) {
            latestAnchor = proof
        }
    }

    /// Append a new audit event. Returns the block that was written.
    @discardableResult
    func append(kind: AuditKind, payload: [String: String]) -> AuditBlock {
        let index = length
        let ts = Date()
        let prev = tipHash
        let hash = AuditBlock.computeHash(
            index: index, ts: ts, kind: kind, payload: payload, prevHash: prev
        )
        let block = AuditBlock(
            index: index, ts: ts, kind: kind, payload: payload,
            prevHash: prev, hash: hash
        )
        // Append to file + cache.
        if let line = try? JSONEncoder().encode(block),
           let str = String(data: line, encoding: .utf8) {
            let toWrite = str + "\n"
            if let data = toWrite.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: fileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: fileURL, options: .atomic)
                }
            }
        }
        recentCache.append(block)
        if recentCache.count > 30 { recentCache.removeFirst(recentCache.count - 30) }
        tipHash = hash
        length = index + 1
        return block
    }

    /// Verify the cached window's chain integrity. Returns the index of
    /// the first broken link, or nil if the window is intact.
    func verifyRecent() -> UInt64? {
        var prev = recentCache.first?.prevHash ?? String(repeating: "0", count: 64)
        for block in recentCache {
            let expected = AuditBlock.computeHash(
                index: block.index,
                ts: block.ts,
                kind: block.kind,
                payload: block.payload,
                prevHash: prev
            )
            if expected != block.hash { return block.index }
            if block.prevHash != prev { return block.index }
            prev = block.hash
        }
        return nil
    }

    // MARK: - Merkle root

    /// Compute a SHA-256 Merkle root over the hex hashes in the rolling
    /// cache. Odd leaves get promoted (standard Bitcoin-style layering,
    /// minus the double-SHA — single SHA-256 is fine here because the
    /// leaf values are already hex-encoded digests, not user bytes, so
    /// length-extension attacks don't apply to our use case).
    ///
    /// Returns the all-zeros sentinel when the cache is empty so the
    /// server-side schema doesn't need to special-case an optional.
    func merkleRoot() -> String {
        return Self.merkleRoot(over: recentCache)
    }

    static func merkleRoot(over blocks: [AuditBlock]) -> String {
        let zero = String(repeating: "0", count: 64)
        guard !blocks.isEmpty else { return zero }

        // Leaves are the hex `block.hash` strings, lowercased so server
        // and client canonicalize the same way before hashing pairs.
        var layer: [String] = blocks.map { $0.hash.lowercased() }
        while layer.count > 1 {
            // Promote the lone tail if we have an odd count.
            if layer.count % 2 == 1, let tail = layer.last {
                layer.append(tail)
            }
            var next: [String] = []
            next.reserveCapacity(layer.count / 2)
            var i = 0
            while i < layer.count {
                let l = layer[i]
                let r = layer[i + 1]
                let pair = "\(l)\(r)"
                let digest = SHA256.hash(data: Data(pair.utf8))
                next.append(digest.map { String(format: "%02x", $0) }.joined())
                i += 2
            }
            layer = next
        }
        return layer.first ?? zero
    }

    // MARK: - Anchor envelope + signing

    /// The canonical anchor envelope the driver signs. Deterministic
    /// key order + fixed number formatting are critical — if the server
    /// and client canonicalize differently, signatures will never
    /// verify. Timestamp is an integer unix-seconds (not Double) so
    /// there's no locale-dependent fractional drift across runtimes.
    func buildAnchorEnvelope(driverId: String) -> [String: Any] {
        return [
            "driverId": driverId,
            "tipIndex": length,
            "tipHash": tipHash,
            "merkleRoot": merkleRoot(),
            "ts": Int(Date().timeIntervalSince1970)
        ]
    }

    /// Render the envelope into a deterministic byte representation
    /// suitable for P-256 signing. We use JSONSerialization with
    /// `.sortedKeys` so the key ordering matches the server's
    /// canonical form regardless of the dict's iteration order.
    private func canonicalEnvelopeBytes(_ envelope: [String: Any]) -> Data? {
        return try? JSONSerialization.data(
            withJSONObject: envelope,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    /// POST the signed anchor envelope to `audit.anchor`. On success
    /// the server returns a counter-signed `AuditAnchorProof` which we
    /// persist so the driver can present it offline during a roadside
    /// inspection. Returns the proof on success, nil otherwise (errors
    /// are surfaced via `lastAnchorError`, never thrown — this is a
    /// fire-and-forget periodic background call from the HOS tick).
    @discardableResult
    func anchor(auth: AuthStore, driverId: String) async -> AuditAnchorProof? {
        guard auth.isSignedIn else {
            lastAnchorError = "not signed in"
            return nil
        }
        // Bootstrap the secure-enclave key lazily; nop if already up.
        ConvoySignature.shared.bootstrap()
        guard ConvoySignature.shared.isReady else {
            lastAnchorError = "secure-enclave unavailable"
            return nil
        }

        let envelope = buildAnchorEnvelope(driverId: driverId)
        guard let envelopeBytes = canonicalEnvelopeBytes(envelope) else {
            lastAnchorError = "envelope encoding failed"
            return nil
        }
        guard let signature = ConvoySignature.shared.sign(envelopeBytes) else {
            lastAnchorError = "signing failed"
            return nil
        }
        let sigB64 = signature.base64EncodedString()
        let pubB64 = ConvoySignature.shared.localPublicKeyB64 ?? ""

        // tRPC input: we keep the envelope fields at top-level so the
        // server can echo them back in its proof without needing to
        // redecode the raw bytes. The raw bytes + signature are also
        // shipped so the server can verify the driver signature exactly
        // the way an offline auditor would.
        var input: [String: Any] = [:]
        for (k, v) in envelope { input[k] = v }
        input["envelopeB64"] = envelopeBytes.base64EncodedString()
        input["driverSignatureB64"] = sigB64
        input["driverPublicKeyB64"] = pubB64

        do {
            let client = EsangClient(auth: auth)
            let data = try await client.mutateJSON("audit.anchor", input: input)
            // Response envelope: { result: { data: { json: AuditAnchorProof } } }
            struct ServerEnvelope: Decodable {
                struct Result: Decodable {
                    struct DataContainer: Decodable {
                        let json: AuditAnchorProof
                    }
                    let data: DataContainer
                }
                let result: Result
            }
            let decoded = try JSONDecoder().decode(ServerEnvelope.self, from: data)
            let proof = decoded.result.data.json
            latestAnchor = proof
            lastAnchorError = nil
            if let out = try? JSONEncoder().encode(proof) {
                try? out.write(to: anchorURL, options: .atomic)
            }
            return proof
        } catch EsangError.unauthorized {
            lastAnchorError = "unauthorized"
            return nil
        } catch EsangError.server(let status, _) {
            lastAnchorError = "server \(status)"
            return nil
        } catch {
            lastAnchorError = error.localizedDescription
            return nil
        }
    }
}
