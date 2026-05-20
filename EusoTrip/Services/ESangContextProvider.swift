//
//  ESangContextProvider.swift
//  Always-on context surface that follows the user across every screen.
//
//  2026-05-20 · IO 2026 founder directive ("ESang AI everywhere always
//  knowing whats going on with the user"). Every screen that hosts an
//  ESang affordance — phone home, load detail, day close, watch,
//  CarPlay, Siri shortcut — reads from `ESangContext.current` so the
//  same conversation thread + the same shipment binding follows the
//  user without re-prompting for context on every turn.
//
//  The context is a lightweight observable struct: active shipmentId,
//  active vertical, last role-aware FSM state, current screen
//  identifier. Updating any of these is cheap; updating the whole
//  struct is what causes ESang's next voice reply to re-bind to the
//  new context. The view-model never sends a request to ESang
//  without checking this first.
//
//  Drop into: EusoTrip/Services/ESangContextProvider.swift
//

import Foundation
import Combine

/// One snapshot of what ESang should know about the user right now.
public struct ESangContext: Equatable, Hashable, Sendable {
    /// The shipment the user is currently looking at / driving on.
    /// Drives the thought-signature cache key + the server-side load
    /// row binding (so the model doesn't have to look it up).
    public var activeShipmentId: String?

    /// Active vertical — propagated to `ESangIntent.thinkingLevel(forVertical:)`
    /// so hazmat / tanker / heavy-haul lanes escalate medium intents
    /// up to high without any client-side branching.
    public var activeVertical: Vertical?

    /// Most recent canonical FSM state seen for the active shipment.
    /// Used to gate which intents are valid (you can't `.actionConfirmDelivery`
    /// from `.posted`).
    public var lastFsmState: LoadState?

    /// Screen the user is currently on — surfaces to ESang so it can
    /// say "I see you're on Load Detail for L-2026-001234, want me to
    /// pull the BOL?" instead of asking "which load?".
    public var screenId: String?

    /// User's preferred voice dialect (P0-4). Server uses this to pick
    /// the TTS voice; client uses it for transcription locale + STT
    /// language. Defaults to system locale.
    public var voiceDialect: String = Locale.current.identifier

    /// Server-mirrored feature flag — true when prod env has
    /// `GEMINI_MODEL` set to a 3.5-flavored model. Updated by polling
    /// `esang.getFlags` on app launch and whenever the user returns
    /// from the background (handled by `ESangContextProvider`).
    public var flashVoiceFlagOn: Bool = false

    public static let empty = ESangContext()

    public init(
        activeShipmentId: String? = nil,
        activeVertical: Vertical? = nil,
        lastFsmState: LoadState? = nil,
        screenId: String? = nil,
        voiceDialect: String = Locale.current.identifier,
        flashVoiceFlagOn: Bool = false
    ) {
        self.activeShipmentId = activeShipmentId
        self.activeVertical = activeVertical
        self.lastFsmState = lastFsmState
        self.screenId = screenId
        self.voiceDialect = voiceDialect
        self.flashVoiceFlagOn = flashVoiceFlagOn
    }
}

/// The single observable context every iOS surface reads from. Use
/// `@StateObject private var ctx = ESangContextProvider.shared` in
/// any view-model that owns the conversation; use
/// `@ObservedObject var ctx = ESangContextProvider.shared` in views
/// that just read the current shipment / vertical / FSM state.
@MainActor
public final class ESangContextProvider: ObservableObject {
    public static let shared = ESangContextProvider()

    @Published public private(set) var current: ESangContext = .empty

    public init() {}

    // MARK: - Mutators

    /// Bind ESang to a new shipment. Drops the previous shipment's
    /// thought-signature cache so the next voice turn doesn't replay
    /// stale reasoning across loads. (Watch + phone both call this.)
    public func enterShipment(
        _ shipmentId: String,
        vertical: Vertical? = nil,
        fsmState: LoadState? = nil
    ) async {
        if let prev = current.activeShipmentId, prev != shipmentId {
            await ESangVoiceClient.shared.forgetSignature(for: prev)
        }
        current.activeShipmentId = shipmentId
        if let vertical { current.activeVertical = vertical }
        if let fsmState { current.lastFsmState = fsmState }
    }

    public func exitShipment() async {
        if let id = current.activeShipmentId {
            await ESangVoiceClient.shared.forgetSignature(for: id)
        }
        current.activeShipmentId = nil
        current.activeVertical = nil
        current.lastFsmState = nil
    }

    public func setScreen(_ screenId: String) {
        current.screenId = screenId
    }

    public func updateFsmState(_ state: LoadState) {
        current.lastFsmState = state
    }

    public func setVoiceDialect(_ dialect: String) {
        current.voiceDialect = dialect
    }

    public func setFlashVoiceFlag(_ on: Bool) {
        current.flashVoiceFlagOn = on
    }

    // MARK: - Convenience accessors for callers

    /// Convenience — fire one voice turn with the current ambient
    /// context already plumbed in. Most screens use this instead of
    /// `ESangVoiceClient.shared.dispatch(...)` directly.
    public func ask(_ utterance: String, intent: ESangIntent? = nil) async throws -> ESangVoiceReply {
        try await ESangVoiceClient.shared.dispatch(
            utterance: utterance,
            intent: intent,
            shipmentId: current.activeShipmentId,
            vertical: current.activeVertical,
            fsmTarget: nil
        )
    }

    /// Convenience — fire an FSM-transitioning turn (confirm pickup,
    /// confirm delivery, reroute, customs filing, HOS override). The
    /// `fsmTarget` is required so the server can verify the suggested
    /// action lands on a valid LoadState before applying it.
    public func askWithFsmTransition(
        _ utterance: String,
        intent: ESangIntent,
        fsmTarget: LoadState
    ) async throws -> ESangVoiceReply {
        try await ESangVoiceClient.shared.dispatch(
            utterance: utterance,
            intent: intent,
            shipmentId: current.activeShipmentId,
            vertical: current.activeVertical,
            fsmTarget: fsmTarget
        )
    }
}
