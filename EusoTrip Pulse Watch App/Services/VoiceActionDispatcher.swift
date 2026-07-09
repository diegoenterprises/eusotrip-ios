//
//  VoiceActionDispatcher.swift
//  EusoTrip Watch App
//
//  Turns structured `VoiceAction`s returned from the backend into
//  concrete watch-side side effects: navigation hops, HOS state
//  changes, load acceptance, SOS escalation, etc. The backend remains
//  the canonical decision-maker — this file just maps intent types to
//  the wrist view or system call that fulfils them.
//
//  Catalog (spec §5.3) — watch-side routing:
//    open_load_details        → push WatchLoadDetailView
//    accept_load              → confirm + loads.accept via LoadStore
//    decline_load             → drivers.declineLoad
//    log_arrival              → loads.updateLoadStatus(at_pickup|at_delivery)
//    change_hos               → HOSStore.changeStatus(to:)
//    find_rest_stop           → open Maps via handoff
//    call_dispatch            → phone call or Walkie-Talkie
//    emergency_sos            → EmergencyController.trigger
//    message_reply            → inbox quick-reply flow
//    wallet_overview          → push WalletSummaryView
//    open_load_auction        → broker persona view
//    escort_check             → hazmat persona view
//

import Foundation
import Combine

@MainActor
final class VoiceActionDispatcher: ObservableObject {
    static let shared = VoiceActionDispatcher()

    @Published var currentRoute: WatchRoute?

    /// Pending confirmation slots — keyed by the `confirmId` we hand
    /// to the route so the sheet can look up the deferred actions on
    /// tap. The slot is removed as soon as the user confirms or
    /// cancels, so the memory profile stays O(1) in practice.
    ///
    /// Why confirmId instead of carrying actions in the enum: the
    /// WatchRoute enum has to be Equatable + Identifiable for the
    /// SwiftUI sheet wiring, and VoiceAction is Codable-only. The
    /// confirmId indirection keeps the route enum tidy.
    private struct ConfirmSlot {
        let label: String
        let actions: [VoiceAction]
        let auth: AuthStore
        let connectivity: WatchConnectivityManager
    }
    private var confirmSlots: [String: ConfirmSlot] = [:]

    /// Intents whose side effects are hard to undo (dispatches a load,
    /// wakes E911, rejects work). Any voice action whose `type` lands
    /// in this set is held back for confirmation on the offline path
    /// where there's no server-side guardrail. When the backend
    /// returned the action itself (online path), we assume it was
    /// already confirmed upstream.
    private let destructiveActionTypes: Set<String> = [
        "emergency_sos",
        "accept_load",
        "decline_load",
    ]

    func dispatch(
        _ actions: [VoiceAction],
        auth: AuthStore,
        connectivity: WatchConnectivityManager
    ) async {
        for action in actions {
            await dispatchOne(action, auth: auth, connectivity: connectivity)
        }
    }

    /// Offline variant of `dispatch(...)`: destructive actions (SOS,
    /// accept, decline) are held behind a confirmation sheet before
    /// the wrist executes them. Non-destructive actions (change_hos,
    /// log_arrival, message_reply, read-only queries) dispatch
    /// immediately — they're either idempotent, already enqueue in a
    /// retry lane, or mirror local state only.
    ///
    /// The offline grammar (`VoiceDispatch.resolve`) is the primary
    /// caller. The online grammar leaves confirmation to the server,
    /// so it continues to use `dispatch(...)` directly.
    func dispatchOffline(
        _ actions: [VoiceAction],
        prompt: String,
        auth: AuthStore,
        connectivity: WatchConnectivityManager
    ) async {
        var deferred: [VoiceAction] = []
        for action in actions {
            if destructiveActionTypes.contains(action.type) {
                deferred.append(action)
            } else {
                await dispatchOne(action, auth: auth, connectivity: connectivity)
            }
        }
        guard !deferred.isEmpty else { return }

        // Park deferred actions behind a confirmation slot. The sheet
        // reads the prompt from the route, taps Confirm → we fire the
        // deferred action set through the standard dispatch path.
        let confirmId = UUID().uuidString
        confirmSlots[confirmId] = ConfirmSlot(
            label: prompt,
            actions: deferred,
            auth: auth,
            connectivity: connectivity
        )
        currentRoute = .voiceConfirm(prompt: prompt, confirmId: confirmId)
    }

    /// Called by `VoiceConfirmSheet` when the driver taps Confirm.
    /// Fires every deferred action through the normal dispatch path
    /// and clears the slot. A subsequent Cancel is a no-op.
    func confirmVoiceAction(_ confirmId: String) async {
        guard let slot = confirmSlots.removeValue(forKey: confirmId) else { return }
        for action in slot.actions {
            await dispatchOne(action, auth: slot.auth, connectivity: slot.connectivity)
        }
    }

    /// Called by `VoiceConfirmSheet` when the driver taps Cancel or
    /// the sheet is dismissed by a swipe-down. We drop the slot so
    /// the memory profile stays bounded + so a stale confirmId can't
    /// later be used to fire an action out of band.
    func cancelVoiceAction(_ confirmId: String) {
        confirmSlots.removeValue(forKey: confirmId)
    }

    private func dispatchOne(
        _ action: VoiceAction,
        auth: AuthStore,
        connectivity: WatchConnectivityManager
    ) async {
        switch action.type {
        case "open_load_details":
            if let loadId = action.payload?.dictValue?["loadId"] as? String {
                currentRoute = .loadDetail(loadId: loadId)
            } else {
                currentRoute = .loadDetail(loadId: LoadStore.shared.active?.id ?? "")
            }

        case "accept_load":
            if let loadId = action.payload?.dictValue?["loadId"] as? String {
                let bidId = action.payload?.dictValue?["bidId"] as? String
                // Honest ack: only claim "accepted" once the outbox
                // entry actually drained; a still-queued entry gets
                // the truthful "queued" toast instead of a fabricated
                // "Dispatch notified."
                let key = OfflineQueue.shared.enqueueAcceptLoad(loadId: loadId, bidId: bidId)
                await OfflineQueue.shared.flush(auth: auth)
                currentRoute = OfflineQueue.shared.isPending(key)
                    ? .toast(message: "Accept queued — sends when you're back online.")
                    : .toast(message: "Accepted \(loadId). Dispatch notified.")
            }

        case "decline_load":
            if let loadId = action.payload?.dictValue?["loadId"] as? String {
                // Real driver-side decline proc (drivers.ts:1326) — the
                // previously called `loads.decline` does not exist. The
                // toast now waits for the mutation instead of preceding
                // a guaranteed 404.
                do {
                    _ = try await EsangClient(auth: auth).mutateJSON(
                        "drivers.declineLoad",
                        input: ["loadId": loadId, "reason": "Declined from EusoTrip Pulse"]
                    )
                    currentRoute = .toast(message: "Declined \(loadId).")
                } catch {
                    currentRoute = .toast(message: "Couldn't decline \(loadId) — try from your iPhone.")
                }
            }

        case "log_arrival":
            if let loadId = action.payload?.dictValue?["loadId"] as? String,
               let kind = action.payload?.dictValue?["kind"] as? String {
                let key = OfflineQueue.shared.enqueueArrived(loadId: loadId, kind: kind, at: Date())
                await OfflineQueue.shared.flush(auth: auth)
                currentRoute = OfflineQueue.shared.isPending(key)
                    ? .toast(message: "Arrival queued — sends when you're back online.")
                    : .toast(message: "Arrived at \(kind). ✓")
            }

        case "change_hos":
            if let newStatusRaw = action.payload?.dictValue?["status"] as? String,
               let newStatus = HOSStatus(rawValue: newStatusRaw) {
                await HOSStore.shared.changeStatus(
                    to: newStatus,
                    auth: auth,
                    connectivity: connectivity
                )
                currentRoute = .toast(message: "\(newStatus.label) logged.")
            }

        case "find_rest_stop", "navigate_to":
            // Ask phone to resolve and open Maps so we're not consuming
            // the wrist battery running a MapKit scene.
            connectivity.requestPhoneActivation(
                transcript: action.payload?.dictValue?["prompt"] as? String,
                reply: "Opening Maps on your iPhone."
            )
            currentRoute = .toast(message: "Opening on iPhone…")

        case "call_dispatch":
            currentRoute = .dispatchCall

        case "emergency_sos":
            await EmergencyController.shared.activate(
                reason: action.payload?.dictValue?["reason"] as? String ?? "driver-initiated",
                auth: auth,
                connectivity: connectivity
            )
            currentRoute = .emergency

        case "message_reply":
            if let threadId = action.payload?.dictValue?["threadId"] as? String,
               let text = action.payload?.dictValue?["text"] as? String {
                let loadId = action.payload?.dictValue?["loadId"] as? String
                do {
                    // Real sender proc + real input shape
                    // (messages.ts:337): { conversationId, content,
                    // type } — the old messages.send {threadId, text}
                    // was a zod BAD_REQUEST on every reply.
                    _ = try await EsangClient(auth: auth).mutateJSON(
                        "messages.sendMessage",
                        input: [
                            "conversationId": threadId,
                            "content": text,
                            "type": "text",
                            "idempotencyKey": UUID().uuidString
                        ]
                    )
                    currentRoute = .toast(message: "Sent ✓")
                } catch {
                    // Drop into the Message lane so the outbox retries when
                    // coverage returns. Without this, a voice-dispatched
                    // "text dispatch we're stuck at the scales" would
                    // evaporate the moment cellular was down.
                    OfflineQueue.shared.enqueueMessage(
                        loadId: loadId,
                        to: threadId,
                        text: text
                    )
                    currentRoute = .toast(message: "Queued — will send when online.")
                }
            }

        case "wallet_overview":
            currentRoute = .wallet

        case "open_load_auction":
            if let loadId = action.payload?.dictValue?["loadId"] as? String {
                currentRoute = .loadAuction(loadId: loadId)
            }

        case "escort_check":
            currentRoute = .hazmatEscort

        case "scan_bol", "scan_placard", "bol_copilot":
            // F15 — BOL/placard copilot. The view existed but was
            // reachable only from its own #Preview; ESANG ("scan the
            // placard") now routes to it like every other surface.
            currentRoute = .bolCopilot

        case "show_convoy":
            // F13 — surfaces the convoy detail sheet from Esang.
            // The coordinator self-gates on `EusoTripConfig.convoyEnabled`,
            // so the sheet will render "No peers in range" + the signing
            // pill even when the feature flag is off. That's intentional:
            // the driver sees the same UI state whether the convoy
            // subsystem is disabled OR there just aren't any peers yet.
            currentRoute = .convoy

        case "handoff", "proximity_handoff", "broadcast_handoff":
            // F16 — surface the Proximity Handoff sheet from Esang
            // ("handoff the load", "broadcast handoff").
            // ProximityHandoffView self-gates on the feature flag +
            // auth/active-load state, so we don't second-guess the
            // trigger here — we just route.
            currentRoute = .proximityHandoff

        default:
            // Unknown action types are silently ignored on the wrist —
            // the backend may have routed a phone-only intent.
            break
        }
    }
}

/// All possible wrist routes that voice actions or complications can
/// request. The ContentView/RootView observes this and pushes.
enum WatchRoute: Equatable {
    case home
    case loadDetail(loadId: String)
    case hos
    case inbox
    case wallet
    case dispatchCall
    case emergency
    case toast(message: String)
    case loadAuction(loadId: String)
    case hazmatEscort
    case ergLookup
    case dispatcherBoard
    case shipperBoard
    case brokerBoard
    /// F13 — Convoy detail surface. Reachable from Esang
    /// ("show convoy"), from the home-screen overflow, and from any
    /// upstream that dispatches a "show_convoy" voice action.
    case convoy
    /// F16 — Proximity Handoff surface. Reachable from Esang
    /// ("handoff the load", "broadcast handoff") + from the home-screen
    /// overflow menu. The sheet presents the broadcast/capture UI
    /// without interrupting the current tab.
    case proximityHandoff
    /// F15 — BOL/placard scan copilot. Reachable from Esang ("scan the
    /// placard", "scan the BOL"); the phone does the camera capture and
    /// mirrors the parsed result to the wrist.
    case bolCopilot
    /// F04 offline path — a destructive voice intent is pending the
    /// driver's explicit confirmation. `prompt` is shown verbatim
    /// inside the sheet; `confirmId` indexes into
    /// `VoiceActionDispatcher.confirmSlots` for the deferred action
    /// set. Tap Confirm → dispatcher fires the actions; Cancel →
    /// dispatcher drops the slot. The slot is keyed by UUID so a
    /// second voice prompt coming in while the sheet is up can't
    /// hijack the first one's actions.
    case voiceConfirm(prompt: String, confirmId: String)
}
