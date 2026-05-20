//
//  ESangVoiceClient.swift
//  Canonical iOS-side ESang AI voice client.
//
//  2026-05-20 · IO 2026 P0-1 + P0-2 + P0-3 — single entry point every
//  iOS voice/text surface (phone, Pulse Watch, CarPlay, Siri shortcut,
//  Spotlight intent) hits when it wants to talk to ESang. All routes
//  funnel here, which means:
//
//    - Model identifier + thinking_level are owned server-side via
//      `GeminiConfig.primaryModel()` (P0-1). Client never picks a
//      model, only an intent.
//    - Thought-signature replay (P0-3) is centralised here: every
//      multi-turn voice flow caches the encrypted signature returned
//      with the previous turn and replays it on the follow-up so the
//      model resumes the conversation in ~40% the latency of a
//      cold-start re-reason.
//    - The feature flag `gemini_3_5_flash_voice` is mirrored from
//      `esang.getFlags` so a single server env (`GEMINI_MODEL`) flips
//      this entire client without an iOS rebuild.
//    - Foundation enums (`ESangIntent`, `Vertical`, `LoadState`) are
//      mandatory at the API boundary — no raw strings cross the wire.
//
//  Drop into: EusoTrip/Services/ESangVoiceClient.swift
//

import Foundation

/// One round-trip request to ESang.
public struct ESangVoiceRequest: Encodable, Hashable, Sendable {
    public let utterance: String
    public let intent: ESangIntent
    public let thinkingLevel: ThinkingLevel
    /// Active load context, when one exists. Lets the server skip a
    /// `loads.getById` round-trip and pre-bind hazmat/reefer overlays.
    public let shipmentId: String?
    /// Active vertical (escalates `medium` intents on hazmat/tanker/
    /// heavy-haul lanes). Server cross-checks against the load row.
    public let vertical: Vertical?
    /// Encrypted thought signature returned by the previous turn.
    /// When present the server skips the re-reason phase and resumes
    /// the conversation; this is the P0-3 latency win.
    public let prevThoughtSignature: String?
    /// Optional FSM target — required when `intent.triggersFsmTransition`
    /// is true. Server uses this to verify the suggested action lands
    /// on a valid LoadState (T-014 ECPO chain).
    public let fsmTarget: LoadState?

    public init(
        utterance: String,
        intent: ESangIntent,
        thinkingLevel: ThinkingLevel? = nil,
        shipmentId: String? = nil,
        vertical: Vertical? = nil,
        prevThoughtSignature: String? = nil,
        fsmTarget: LoadState? = nil
    ) {
        self.utterance = utterance
        self.intent = intent
        self.thinkingLevel = thinkingLevel ?? intent.thinkingLevel(forVertical: vertical)
        self.shipmentId = shipmentId
        self.vertical = vertical
        self.prevThoughtSignature = prevThoughtSignature
        self.fsmTarget = fsmTarget
    }
}

/// One server reply. Mirrors the server's `VoiceActionReply` shape.
public struct ESangVoiceReply: Decodable, Hashable, Sendable {
    public let textReply: String
    /// Encrypted reasoning state the server returned for multi-turn
    /// replay. Nil for single-turn intents. Cache this and pass it
    /// back as `prevThoughtSignature` on the very next request to
    /// take the P0-3 latency path.
    public let thoughtSignature: String?
    /// Server's confidence the intent classification was correct.
    /// Surface this in the UI so a low-confidence reply gets a
    /// "Did you mean…?" follow-up.
    public let confidence: Double?
    /// FSM state the server thinks the load should now be in. Client
    /// must NOT apply this directly; the server will have already
    /// fired the transition. We surface it here so the UI can update
    /// optimistically while the websocket catches up.
    public let resultingFsmState: LoadState?
    /// Model that actually answered (gemini-3.5-flash on the happy
    /// path, gemini-2.5-flash if the fallback fired). Useful in the
    /// debug HUD + cost telemetry post-mortems.
    public let modelUsed: String?
    /// Latency observed server-side (model time + tRPC overhead).
    public let serverLatencyMs: Int?

    public init(
        textReply: String,
        thoughtSignature: String? = nil,
        confidence: Double? = nil,
        resultingFsmState: LoadState? = nil,
        modelUsed: String? = nil,
        serverLatencyMs: Int? = nil
    ) {
        self.textReply = textReply
        self.thoughtSignature = thoughtSignature
        self.confidence = confidence
        self.resultingFsmState = resultingFsmState
        self.modelUsed = modelUsed
        self.serverLatencyMs = serverLatencyMs
    }
}

/// Per-conversation thought-signature cache (P0-3). Owned by the
/// view-model that hosts the conversation thread; not a singleton.
public actor ESangThoughtSignatureCache {
    private var byShipment: [String: String] = [:]
    private var lastUpdate: [String: Date] = [:]
    /// 5-minute TTL per the IO 2026 doc — older signatures get dropped
    /// because the underlying shipment state has likely changed.
    private let ttl: TimeInterval = 5 * 60

    public init() {}

    public func remember(_ signature: String, for shipmentId: String) {
        byShipment[shipmentId] = signature
        lastUpdate[shipmentId] = Date()
    }

    public func recall(for shipmentId: String) -> String? {
        guard let stamp = lastUpdate[shipmentId] else { return nil }
        if Date().timeIntervalSince(stamp) > ttl {
            byShipment.removeValue(forKey: shipmentId)
            lastUpdate.removeValue(forKey: shipmentId)
            return nil
        }
        return byShipment[shipmentId]
    }

    public func forget(_ shipmentId: String) {
        byShipment.removeValue(forKey: shipmentId)
        lastUpdate.removeValue(forKey: shipmentId)
    }
}

/// The canonical ESang voice client. Use `ESangVoiceClient.shared` from
/// any iOS surface (phone view-models, Pulse Watch bridge, CarPlay
/// shortcut, Siri intent). Pulse Watch has its own thin wrapper that
/// forwards to the phone client via WatchConnectivity — but the
/// transport contract is owned here.
public final class ESangVoiceClient: @unchecked Sendable {
    public static let shared = ESangVoiceClient()

    private let signatureCache = ESangThoughtSignatureCache()

    public init() {}

    /// Dispatch one voice turn to the server. The intent + vertical
    /// determine the server-side thinking_level + model thinking budget.
    /// Caller doesn't pick the model — the server does, based on the
    /// `gemini_3_5_flash_voice` flag mirrored from `GEMINI_MODEL`.
    public func dispatch(
        utterance: String,
        intent: ESangIntent? = nil,
        shipmentId: String? = nil,
        vertical: Vertical? = nil,
        fsmTarget: LoadState? = nil
    ) async throws -> ESangVoiceReply {
        let resolvedIntent = intent ?? ESangIntent.bestGuess(from: utterance)
        let prev: String? = if let shipmentId {
            await signatureCache.recall(for: shipmentId)
        } else {
            nil
        }
        let req = ESangVoiceRequest(
            utterance: utterance,
            intent: resolvedIntent,
            shipmentId: shipmentId,
            vertical: vertical,
            prevThoughtSignature: prev,
            fsmTarget: fsmTarget
        )
        let reply: ESangVoiceReply = try await EusoTripAPI.shared.mutation(
            "esang.voice.dispatch",
            input: req
        )
        // Cache the new thought signature for the next turn.
        if let shipmentId, let sig = reply.thoughtSignature {
            await signatureCache.remember(sig, for: shipmentId)
        }
        return reply
    }

    /// Drop the cached signature for a shipment — call this on
    /// AT_PICKUP / AT_DELIVERY / POD_SIGNED / SETTLED so we don't
    /// replay stale reasoning into a different lifecycle phase.
    public func forgetSignature(for shipmentId: String) async {
        await signatureCache.forget(shipmentId)
    }
}
