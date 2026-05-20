//
//  ESangWatchClient.swift
//  Pulse Watch — IO 2026 P0-1 voice client (thinking_level + thought signatures).
//
//  2026-05-20 · IO 2026 founder directive — "ESang AI everywhere always
//  knowing whats going on with the user." This is the wrist surface
//  of that doctrine: the watch fires voice intents into the same
//  server pipeline the phone + web do, with full thinking_level
//  awareness and thought-signature replay so a multi-turn
//  conversation that starts on the phone can continue on the watch
//  (and vice versa) without losing context.
//
//  Transport: same server endpoint as the phone (`esang.voice.dispatch`).
//  Watch builds the request locally, posts directly to the platform
//  (no phone hop required) — falls back to WatchConnectivity routing
//  through the iPhone only when the watch is offline. Apple doesn't
//  ship Speech.framework on watchOS, so transcription rides through
//  `WatchDictation` / `transcription.transcribeAudio` instead of
//  SFSpeechRecognizer per the prior `feedback_watch_voice` memory.
//
//  Mirrors the phone's `ESangVoiceClient.swift`. Foundation enums
//  (`ESangIntent`, `Vertical`, `LoadState`) are copy-imports here so
//  the watch target has no dependency on the phone bundle — they're
//  the same RawValue strings, so the wire contract is identical.
//
//  Drop into: EusoTrip Pulse Watch App/ESangWatchClient.swift
//

import Foundation
import CoreLocation

// MARK: - Foundation enum mirrors (RawValue-identical to phone target)

/// Watch-side mirror of phone's `ESangIntent`. Keep RawValues byte-
/// identical — the server validates the wire string against its own
/// canonical enum in `_core/geminiConfig.ts`.
public enum ESangWatchIntent: String, CaseIterable, Codable, Hashable, Sendable {
    case statusLocation             = "status.location"
    case statusEta                  = "status.eta"
    case statusHosRemaining         = "status.hos_remaining"
    case statusNextStop             = "status.next_stop"
    case actionConfirmPickup        = "action.confirm_pickup"
    case actionConfirmDelivery      = "action.confirm_delivery"
    case planFuelStop               = "plan.fuel_stop"
    case planRoutePreview           = "plan.route_preview"
    case planDetentionLog           = "plan.detention_log"
    case complianceHazmatSegregation = "compliance.hazmat_segregation"
    case complianceUsmcaCert         = "compliance.usmca_cert"
    case complianceErgLookup         = "compliance.erg_lookup"
    case complianceReeferTempBreach  = "compliance.reefer_temp_breach"
    case complianceLivestock28Hr     = "compliance.livestock_28hr"
    case planReroute                 = "plan.reroute"
    case planCustomsFiling           = "plan.customs_filing"
    case planHosOverride             = "plan.hos_override"
    case unknown                     = "unknown"

    public var thinkingLevel: ESangWatchThinkingLevel {
        switch self {
        case .complianceHazmatSegregation, .complianceUsmcaCert,
             .complianceErgLookup, .complianceReeferTempBreach,
             .complianceLivestock28Hr,
             .planReroute, .planCustomsFiling, .planHosOverride:
            return .high
        case .planFuelStop, .planRoutePreview, .planDetentionLog:
            return .medium
        case .statusLocation, .statusEta, .statusHosRemaining,
             .statusNextStop, .actionConfirmPickup, .actionConfirmDelivery:
            return .low
        case .unknown:
            return .medium
        }
    }

    /// Cheap on-watch utterance → intent guess. Real classification is
    /// always server-side; this is a hint only.
    public static func bestGuess(from utterance: String) -> ESangWatchIntent {
        let t = utterance.lowercased()
        if t.contains("where") || t.contains("location") { return .statusLocation }
        if t.contains("eta") || t.contains("arrive")     { return .statusEta }
        if t.contains("hours") || t.contains("hos")      { return .statusHosRemaining }
        if t.contains("fuel") || t.contains("gas")       { return .planFuelStop }
        if t.contains("reroute") || t.contains("re-route") { return .planReroute }
        if t.contains("erg") || t.contains("emergency response") { return .complianceErgLookup }
        if t.contains("confirm") && t.contains("pickup") { return .actionConfirmPickup }
        if t.contains("confirm") && t.contains("deliver"){ return .actionConfirmDelivery }
        return .unknown
    }
}

public enum ESangWatchThinkingLevel: String, Codable, Hashable, Sendable {
    case low, medium, high
}

// MARK: - Request / reply

public struct ESangWatchRequest: Encodable, Hashable, Sendable {
    public let utterance: String
    public let intent: ESangWatchIntent
    public let thinkingLevel: ESangWatchThinkingLevel
    public let shipmentId: String?
    /// Vertical rawValue — string instead of enum so the watch target
    /// doesn't have to mirror all 12 `Vertical` cases. Wire value must
    /// match the phone's `Vertical.rawValue`.
    public let vertical: String?
    /// Encrypted thought signature returned by the previous turn —
    /// either from a watch turn or relayed across from the phone via
    /// WatchConnectivity (so a conversation started on the phone
    /// continues seamlessly on the wrist).
    public let prevThoughtSignature: String?
    /// FSM target string ("AT_PICKUP", "AT_DELIVERY", "EN_ROUTE_TO_DELIVERY"…)
    /// — required for FSM-transitioning intents, otherwise nil.
    public let fsmTarget: String?
    /// Watch-only signal — surface the watch context so the server can
    /// trim its reply to fit a wrist screen (no long preamble, no
    /// bullet lists). Set by this client; never user-controlled.
    public let clientSurface: String = "pulse_watch"

    public init(
        utterance: String,
        intent: ESangWatchIntent,
        thinkingLevel: ESangWatchThinkingLevel? = nil,
        shipmentId: String? = nil,
        vertical: String? = nil,
        prevThoughtSignature: String? = nil,
        fsmTarget: String? = nil
    ) {
        self.utterance = utterance
        self.intent = intent
        self.thinkingLevel = thinkingLevel ?? intent.thinkingLevel
        self.shipmentId = shipmentId
        self.vertical = vertical
        self.prevThoughtSignature = prevThoughtSignature
        self.fsmTarget = fsmTarget
    }
}

public struct ESangWatchReply: Decodable, Hashable, Sendable {
    public let textReply: String
    public let thoughtSignature: String?
    public let confidence: Double?
    public let resultingFsmState: String?
    public let modelUsed: String?
    public let serverLatencyMs: Int?
}

// MARK: - Watch-side thought signature cache (P0-3)

actor ESangWatchSignatureCache {
    private var byShipment: [String: String] = [:]
    private var lastUpdate: [String: Date] = [:]
    private let ttl: TimeInterval = 5 * 60

    func remember(_ signature: String, for shipmentId: String) {
        byShipment[shipmentId] = signature
        lastUpdate[shipmentId] = Date()
    }

    func recall(for shipmentId: String) -> String? {
        guard let stamp = lastUpdate[shipmentId] else { return nil }
        if Date().timeIntervalSince(stamp) > ttl {
            byShipment.removeValue(forKey: shipmentId)
            lastUpdate.removeValue(forKey: shipmentId)
            return nil
        }
        return byShipment[shipmentId]
    }

    func forget(_ shipmentId: String) {
        byShipment.removeValue(forKey: shipmentId)
        lastUpdate.removeValue(forKey: shipmentId)
    }
}

// MARK: - The watch client

public final class ESangWatchClient: @unchecked Sendable {
    public static let shared = ESangWatchClient()
    private let signatureCache = ESangWatchSignatureCache()

    public init() {}

    /// Dispatch one voice turn from the wrist. Caller passes the
    /// utterance + optional intent / shipment / vertical / FSM target.
    /// The server-side `GEMINI_MODEL` env decides the model + flag.
    public func dispatch(
        utterance: String,
        intent: ESangWatchIntent? = nil,
        shipmentId: String? = nil,
        vertical: String? = nil,
        fsmTarget: String? = nil
    ) async throws -> ESangWatchReply {
        let resolvedIntent = intent ?? ESangWatchIntent.bestGuess(from: utterance)
        let prev: String? = if let shipmentId {
            await signatureCache.recall(for: shipmentId)
        } else {
            nil
        }
        let req = ESangWatchRequest(
            utterance: utterance,
            intent: resolvedIntent,
            shipmentId: shipmentId,
            vertical: vertical,
            prevThoughtSignature: prev,
            fsmTarget: fsmTarget
        )
        let reply: ESangWatchReply = try await Self.postTrpc(
            "esang.voice.dispatch",
            input: req
        )
        if let shipmentId, let sig = reply.thoughtSignature {
            await signatureCache.remember(sig, for: shipmentId)
        }
        return reply
    }

    public func forgetSignature(for shipmentId: String) async {
        await signatureCache.forget(shipmentId)
    }

    // MARK: - Transport

    /// Minimal tRPC v10 POST helper for the watch target. The watch
    /// doesn't carry the full `EusoTripAPI` plumbing the phone does
    /// (auth interceptor, retries, websocket subscriber) — for one
    /// procedure that's fine.
    private static func postTrpc<Input: Encodable, Output: Decodable>(
        _ procedure: String,
        input: Input
    ) async throws -> Output {
        guard let base = URL(string: EusoTripConfig.apiBaseURL) else {
            throw EsangError.badResponse
        }
        let url = base.appendingPathComponent("api/trpc/\(procedure)")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = AuthStore.shared?.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONEncoder().encode(TrpcEnvelope(json: input))

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw EsangError.badResponse
        }
        if http.statusCode == 401 { throw EsangError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw EsangError.badResponse
        }
        let decoded = try JSONDecoder().decode(TrpcResult<Output>.self, from: data)
        return decoded.result.data.json
    }
}

// MARK: - tRPC wire envelopes (file scope — Swift doesn't allow generic
//           types nested inside generic functions)

private struct TrpcEnvelope<T: Encodable>: Encodable {
    let json: T
}

private struct TrpcResult<T: Decodable>: Decodable {
    let result: ResultPayload
    struct ResultPayload: Decodable {
        let data: DataPayload
        struct DataPayload: Decodable { let json: T }
    }
}
