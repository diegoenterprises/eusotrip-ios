//
//  EpodLockEngine.swift
//  T-026 (2026-05-20) — Canonical iOS-side ePOD-lock gate.
//
//  Audit finding (01_AUDIT_FINDINGS_SYNTHESIS.md §7):
//    "ePOD lock engine: not present"
//
//  ePOD lock = settlement disbursement waits for cryptographically-
//  verified proof of delivery before EusoWallet releases funds.
//  Canonical activation rules (mirrored from T-011 in PostLoadDraft):
//    - Cross-border lanes (customs fraud risk)
//    - Hazmat lanes (regulatory compliance)
//    - High-value lanes (rate > $5k, escrow protection)
//    - Heavy-haul vertical (permits + escort verification)
//
//  This service is the iOS-side counterpart to the server's
//  `epodLock.status({shipmentId})` endpoint (shipped 2026-05-20,
//  commit c4905024 — server/routers/epodLock.ts).
//  Every iOS surface that exposes a disbursement-style CTA — wallet
//  home (290), day close (055), settlement preview, broker payout —
//  must `try await EpodLockEngine.assertCanDisburse(shipmentId:)`
//  before firing the mutation. The throw short-circuits the UI with a
//  clear remediation message; once the server lifts the lock (POD
//  verified), the disburse fires normally.
//

import Foundation

public enum EpodLockEngine {

    /// Why a shipment is currently ePOD-locked. Mirrors the trigger
    /// set declared in PostLoadDraft.requiresEpodLock (T-011) so the
    /// reason surfaced to the user matches what they saw on Post.
    public enum LockReason: String, Codable, Hashable {
        case crossBorder        = "cross_border"
        case hazmat             = "hazmat"
        case highValueOver5k    = "high_value_over_5k"
        case heavyHaul          = "heavy_haul"
        /// Set when the server can't classify the trigger (e.g., legacy
        /// row without canonical vertical). Treated as locked for safety.
        case unknown

        public var humanLabel: String {
            switch self {
            case .crossBorder:     return "cross-border (customs)"
            case .hazmat:          return "hazmat (regulatory)"
            case .highValueOver5k: return "rate > $5,000 (escrow)"
            case .heavyHaul:       return "heavy haul (escort + permits)"
            case .unknown:         return "regulatory hold"
            }
        }
    }

    /// One row from `epodLock.status({shipmentId})`. Decodes verbatim
    /// from the server response — additional fields ride through as
    /// long as the wire keeps the declared keys.
    public struct LockState: Codable, Hashable {
        public let shipmentId: String
        public let isLocked: Bool
        public let reasons: [LockReason]
        /// ISO-8601 timestamp the lock was armed (typically at POSTED
        /// state when the auto-trigger fires). Nil when never armed.
        public let armedAt: String?
        /// ISO-8601 timestamp the lock was lifted (POD verified).
        /// Nil when still locked.
        public let liftedAt: String?
        /// Human-readable remediation hint surfaced to the driver /
        /// catalyst when the lock fires. Server-localized.
        public let remediation: String?

        /// All-clear shorthand for surfaces that just need a bool.
        public var canDisburse: Bool { !isLocked }
    }

    /// Thrown by `assertCanDisburse(shipmentId:)` when the shipment is
    /// still under ePOD lock. Surfaces a localized description that
    /// the caller can hand straight to a SwiftUI alert / error banner.
    public struct LockedError: LocalizedError, Hashable {
        public let state: LockState
        public var errorDescription: String? {
            let why = state.reasons.map(\.humanLabel).joined(separator: " · ")
            let base = "Settlement disbursement is locked pending verified POD."
            if why.isEmpty {
                return base
            }
            return "\(base) Reason: \(why). " + (state.remediation ?? "Verify the proof of delivery to lift the lock.")
        }
    }

    /// Query the canonical lock state for a shipment. Returns the
    /// server's verdict verbatim; callers should branch on `isLocked`.
    public static func status(shipmentId: String) async throws -> LockState {
        struct Input: Encodable { let shipmentId: String }
        return try await EusoTripAPI.shared.query(
            "epodLock.status",
            input: Input(shipmentId: shipmentId)
        )
    }

    /// Convenience — true if locked, false if cleared. Swallows
    /// network errors as `true` (fail-safe: never disburse on an
    /// unreachable server). The strict `assertCanDisburse` below is
    /// the recommended path when you need a usable error message.
    public static func isLocked(shipmentId: String) async -> Bool {
        do {
            let s = try await status(shipmentId: shipmentId)
            return s.isLocked
        } catch {
            return true   // fail-safe — treat network/server errors as locked
        }
    }

    /// Throw `LockedError` when the shipment is still locked. Use this
    /// in front of every disbursement mutation:
    ///
    ///     try await EpodLockEngine.assertCanDisburse(shipmentId: id)
    ///     try await eusoWallet.disburse(...)
    ///
    /// Wraps any underlying network error in a forced-lock state so
    /// the UI never disburses against an unverified shipment.
    public static func assertCanDisburse(shipmentId: String) async throws {
        let s: LockState
        do {
            s = try await status(shipmentId: shipmentId)
        } catch {
            // Server unreachable — synthesize a worst-case lock state so
            // the caller sees a clear error rather than silently proceeding.
            throw LockedError(state: LockState(
                shipmentId: shipmentId,
                isLocked: true,
                reasons: [.unknown],
                armedAt: nil, liftedAt: nil,
                remediation: "Couldn't verify POD lock status (server unreachable). Retry when network is up."
            ))
        }
        guard s.canDisburse else {
            throw LockedError(state: s)
        }
    }
}
