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
//    - Multi-turn continuity is keyed by `sessionId`; the server owns
//      persisted visible-turn history and provider/model selection.
//    - The server's `GEMINI_MODEL` configuration can change the model
//      without an iOS rebuild, and the reply reports the model that
//      actually answered.
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
    /// Legacy compatibility field. Current continuity uses `sessionId`;
    /// no hidden model reasoning is sent across this boundary.
    public let prevThoughtSignature: String?
    /// Optional FSM target — required when `intent.triggersFsmTransition`
    /// is true. Server uses this to verify the suggested action lands
    /// on a valid LoadState (T-014 ECPO chain).
    public let fsmTarget: LoadState?
    /// Stable conversation key. Keeps two voice threads for the same user
    /// from sharing model history on the server.
    public let sessionId: String?

    public init(
        utterance: String,
        intent: ESangIntent,
        thinkingLevel: ThinkingLevel? = nil,
        shipmentId: String? = nil,
        vertical: Vertical? = nil,
        prevThoughtSignature: String? = nil,
        fsmTarget: LoadState? = nil,
        sessionId: String? = nil
    ) {
        self.utterance = utterance
        self.intent = intent
        self.thinkingLevel = thinkingLevel ?? intent.thinkingLevel(forVertical: vertical)
        self.shipmentId = shipmentId
        self.vertical = vertical
        self.prevThoughtSignature = prevThoughtSignature
        self.fsmTarget = fsmTarget
        self.sessionId = sessionId
    }
}

/// One server reply. Mirrors the server's `VoiceActionReply` shape.
public struct ESangVoiceReply: Decodable, Hashable, Sendable {
    public let textReply: String
    /// Legacy compatibility field. Nil unless an older server supplies it.
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
    /// Model that actually answered. Nil means no model generated a reply.
    public let modelUsed: String?
    public let available: Bool?
    public let provider: String?
    public let fallbackUsed: Bool?
    public let generatedAt: String?
    public let unavailableReason: String?
    /// Latency observed server-side (model time + tRPC overhead).
    public let serverLatencyMs: Int?

    public init(
        textReply: String,
        thoughtSignature: String? = nil,
        confidence: Double? = nil,
        resultingFsmState: LoadState? = nil,
        modelUsed: String? = nil,
        available: Bool? = nil,
        provider: String? = nil,
        fallbackUsed: Bool? = nil,
        generatedAt: String? = nil,
        unavailableReason: String? = nil,
        serverLatencyMs: Int? = nil
    ) {
        self.textReply = textReply
        self.thoughtSignature = thoughtSignature
        self.confidence = confidence
        self.resultingFsmState = resultingFsmState
        self.modelUsed = modelUsed
        self.available = available
        self.provider = provider
        self.fallbackUsed = fallbackUsed
        self.generatedAt = generatedAt
        self.unavailableReason = unavailableReason
        self.serverLatencyMs = serverLatencyMs
    }
}

/// The canonical ESang voice client. Use `ESangVoiceClient.shared` from
/// any iOS surface (phone view-models, Pulse Watch bridge, CarPlay
/// shortcut, Siri intent). Pulse Watch has its own thin wrapper that
/// forwards to the phone client via WatchConnectivity — but the
/// transport contract is owned here.
public final class ESangVoiceClient: @unchecked Sendable {
    public static let shared = ESangVoiceClient()

    public init() {}

    /// Dispatch one voice turn to the server. The intent + vertical
    /// determine the server-side thinking_level + model thinking budget.
    /// Caller doesn't pick the model; the server resolves it from its
    /// current provider configuration and reports the actual responder.
    public func dispatch(
        utterance: String,
        intent: ESangIntent? = nil,
        shipmentId: String? = nil,
        vertical: Vertical? = nil,
        fsmTarget: LoadState? = nil
    ) async throws -> ESangVoiceReply {
        let resolvedIntent = intent ?? ESangIntent.bestGuess(from: utterance)
        let req = ESangVoiceRequest(
            utterance: utterance,
            intent: resolvedIntent,
            shipmentId: shipmentId,
            vertical: vertical,
            prevThoughtSignature: nil,
            fsmTarget: fsmTarget,
            sessionId: shipmentId.map { "shipment:\($0)" }
        )
        let reply: ESangVoiceReply = try await EusoTripAPI.shared.mutation(
            "esang.voice.dispatch",
            input: req
        )
        return reply
    }
}
