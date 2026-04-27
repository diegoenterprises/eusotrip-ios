//
//  VoiceDispatch.swift
//  EusoTrip Pulse Watch App
//
//  F04 — Voice Dispatch offline fallback (Q2 2026).
//
//  When EsangClient.processVoiceCommand can't reach the server, we don't
//  want the driver to be stuck with "No connection — queued." for every
//  utterance. This file runs a tiny grammar over the transcript and, if
//  there's a high-confidence match, executes the intent locally AND
//  still enqueues the server round-trip for later canonicalization.
//
//  The offline grammar covers the ten or so intents that are truly
//  wrist-actionable without the server:
//
//    • "log {on|off|driving|sleeper} duty"        → HOSStore + enqueue
//    • "accept load"                               → enqueue loads.accept
//    • "mark arrived at {pickup|delivery}"         → enqueue logArrival
//    • "what's my remaining drive time?"           → read HOSStore
//    • "what's my active load?"                    → read LoadStore
//    • "start break / end break"                   → enqueue + HOS swap
//    • "sos" / "emergency"                         → EmergencyController
//    • "text dispatch {message}"                   → outbox messaging
//    • "what's my battery?"                        → WKInterfaceDevice
//    • "repeat"                                    → replay last reply
//
//  The server still sees every utterance (for training + audit), but the
//  driver gets a low-latency spoken confirmation + correct offline
//  behavior instead of a dead end.
//

import Foundation
import WatchKit

// Convenience initializers for the offline grammar. All roads lead to
// the full (type, label, payload) designated init — these just keep
// VoiceDispatch call sites readable without having to wrap AnyCodable
// at every line.
extension VoiceAction {
    init(type: String, label: String?) {
        self.init(type: type, label: label, payload: nil)
    }

    /// Pack a `[String: Any]` dict into the payload via AnyCodable.
    /// Mirrors the shape VoiceActionDispatcher reads (`payload?.dictValue`).
    init(type: String, label: String?, dict: [String: Any]) {
        self.init(type: type, label: label, payload: AnyCodable(dict))
    }
}

struct OfflineIntent {
    let label: String            // human-readable intent name
    let reply: String            // spoken confirmation
    let actions: [VoiceAction]   // structured actions dispatched locally
    let enqueueOnline: Bool      // whether we still hit the server later

    init(label: String, reply: String, actions: [VoiceAction], enqueueOnline: Bool) {
        self.label = label
        self.reply = reply
        self.actions = actions
        self.enqueueOnline = enqueueOnline
    }
}

enum VoiceDispatch {
    /// Attempt to resolve `text` against the offline grammar. Returns
    /// nil if no confident match — caller should fall through to the
    /// standard offline-queue path.
    ///
    /// IMPORTANT: action `type` strings MUST match cases that
    /// `VoiceActionDispatcher` handles (change_hos / accept_load /
    /// log_arrival / emergency_sos / message_reply). Anything else
    /// silently no-ops on the wrist — the driver would hear the
    /// confirmation but local state wouldn't update.
    ///
    /// Annotated `@MainActor` because the read-only query helpers reach
    /// into HOSStore / LoadStore / WKInterfaceDevice which are all main-
    /// actor-isolated.
    @MainActor
    static func resolve(_ text: String, loadId: String?) -> OfflineIntent? {
        let t = text.lowercased()

        // --- HOS status swap -----------------------------------------
        // `status` raw values must match HOSStatus: off / sleeper /
        // driving / on_duty.
        if match(t, any: ["log off duty", "off duty", "going off duty"]) {
            return OfflineIntent(
                label: "hos.offDuty",
                reply: "Off duty logged. I'll sync when you're back online.",
                actions: [VoiceAction(type: "change_hos", label: "Off Duty",
                                      dict: ["status": "off"])],
                enqueueOnline: true
            )
        }
        if match(t, any: ["log on duty", "on duty", "going on duty"]) {
            return OfflineIntent(
                label: "hos.onDuty",
                reply: "On duty logged.",
                actions: [VoiceAction(type: "change_hos", label: "On Duty",
                                      dict: ["status": "on_duty"])],
                enqueueOnline: true
            )
        }
        if match(t, any: ["start driving", "log driving"]) {
            return OfflineIntent(
                label: "hos.driving",
                reply: "Driving started.",
                actions: [VoiceAction(type: "change_hos", label: "Driving",
                                      dict: ["status": "driving"])],
                enqueueOnline: true
            )
        }
        if match(t, any: ["sleeper berth", "going to sleep", "sleeper"]) {
            return OfflineIntent(
                label: "hos.sleeper",
                reply: "Sleeper berth logged. Rest well.",
                actions: [VoiceAction(type: "change_hos", label: "Sleeper",
                                      dict: ["status": "sleeper"])],
                enqueueOnline: true
            )
        }

        // --- Load lifecycle -------------------------------------------
        //
        // NOTE on outbox: VoiceActionDispatcher's "accept_load" and
        // "log_arrival" cases already enqueue to OfflineQueue (with
        // an immediate best-effort flush). We don't need a second
        // typed-outbox hint here — the dispatcher owns that lane.
        if match(t, any: ["accept load", "accept this load", "take it"]), let id = loadId {
            return OfflineIntent(
                label: "load.accept",
                reply: "Load accepted. Dispatch will see it when you reconnect.",
                actions: [VoiceAction(type: "accept_load", label: id,
                                      dict: ["loadId": id])],
                enqueueOnline: true
            )
        }
        if match(t, any: ["arrived at pickup", "arrived pickup", "i'm at pickup"]), let id = loadId {
            return OfflineIntent(
                label: "load.arrived.pickup",
                reply: "Pickup arrival logged.",
                actions: [VoiceAction(type: "log_arrival", label: "pickup",
                                      dict: ["loadId": id, "kind": "pickup"])],
                enqueueOnline: true
            )
        }
        if match(t, any: ["arrived at delivery", "arrived delivery", "i'm at the consignee"]), let id = loadId {
            return OfflineIntent(
                label: "load.arrived.delivery",
                reply: "Delivery arrival logged.",
                actions: [VoiceAction(type: "log_arrival", label: "delivery",
                                      dict: ["loadId": id, "kind": "delivery"])],
                enqueueOnline: true
            )
        }

        // --- Read-only queries (no server round-trip needed) ----------
        // These synthesize the reply right here from local stores so
        // the driver gets an answer without waiting on the network.
        if match(t, any: ["remaining drive", "how much drive time", "drive clock"]) {
            return OfflineIntent(
                label: "hos.query.drive",
                reply: replyForDriveClock(),
                actions: [],
                enqueueOnline: false
            )
        }
        if match(t, any: ["active load", "current load", "what load"]) {
            return OfflineIntent(
                label: "load.query.active",
                reply: replyForActiveLoad(),
                actions: [],
                enqueueOnline: false
            )
        }
        if match(t, any: ["battery", "watch battery"]) {
            return OfflineIntent(
                label: "watch.battery",
                reply: replyForBattery(),
                actions: [],
                enqueueOnline: false
            )
        }

        // --- Emergency ------------------------------------------------
        // NOTE on outbox: EmergencyController.activate() (invoked by the
        // dispatcher's "emergency_sos" case) already enqueues to the
        // SOS lane on network failure, so we just emit the action.
        if match(t, any: ["sos", "emergency", "mayday", "help me"]) {
            return OfflineIntent(
                label: "sos",
                reply: "SOS armed. Confirm on screen to dispatch.",
                actions: [VoiceAction(type: "emergency_sos", label: "voice",
                                      dict: ["reason": "voice-command"])],
                enqueueOnline: true
            )
        }

        // --- Dispatcher messaging ------------------------------------
        if let msg = extractAfter(t, prefixes: ["text dispatch", "message dispatch", "tell dispatch"]) {
            return OfflineIntent(
                label: "message.dispatch",
                reply: "Message queued for dispatch.",
                actions: [VoiceAction(type: "message_reply", label: "dispatch",
                                      dict: ["threadId": "dispatch", "text": msg])],
                enqueueOnline: true
            )
        }

        return nil
    }

    // MARK: - Read-only query replies (synthesized from local stores)

    @MainActor
    private static func replyForDriveClock() -> String {
        // HOSClockSwap carries a live-ticking extrapolation; fall back
        // to HOSStore if it hasn't been started yet.
        let swapSeconds = HOSClockSwap.shared.liveDriveRemaining
        let minutes: Int
        if swapSeconds > 0 {
            minutes = swapSeconds / 60
        } else {
            minutes = HOSStore.shared.current.driveRemainingMinutes
        }
        guard minutes > 0 else { return "No drive time remaining. You're on break." }
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m) minutes of drive time remaining." }
        if m == 0 { return "\(h) hours of drive time remaining." }
        return "\(h) hours \(m) minutes of drive time remaining."
    }

    @MainActor
    private static func replyForActiveLoad() -> String {
        guard let load = LoadStore.shared.active else {
            return "You don't have an active load right now."
        }
        let id = load.id
        return "Active load is \(id)."
    }

    @MainActor
    private static func replyForBattery() -> String {
        // Battery monitoring is off by default on watchOS — flip it on
        // just-in-time, read, and leave it on. watchOS doesn't document
        // a cost and enabling it idempotently is fine. Keeping it on
        // also means Complications can surface battery status later
        // without another cold-enable round-trip.
        let device = WKInterfaceDevice.current()
        if !device.isBatteryMonitoringEnabled {
            device.isBatteryMonitoringEnabled = true
        }
        let level = device.batteryLevel
        guard level >= 0 else { return "Watch battery level unavailable." }
        let pct = Int(level * 100)
        return "Watch battery is at \(pct) percent."
    }

    // MARK: - Matching helpers

    private static func match(_ text: String, any phrases: [String]) -> Bool {
        for p in phrases where text.contains(p) { return true }
        return false
    }

    private static func extractAfter(_ text: String, prefixes: [String]) -> String? {
        for p in prefixes {
            if let range = text.range(of: p) {
                let tail = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if !tail.isEmpty { return tail }
            }
        }
        return nil
    }
}
