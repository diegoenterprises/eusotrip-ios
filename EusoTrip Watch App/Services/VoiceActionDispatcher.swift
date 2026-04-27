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
//    decline_load             → loads.decline
//    log_arrival              → loads.logArrival(kind: pickup|delivery)
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

@MainActor
final class VoiceActionDispatcher: ObservableObject {
    static let shared = VoiceActionDispatcher()

    @Published var currentRoute: WatchRoute?

    func dispatch(
        _ actions: [VoiceAction],
        auth: AuthStore,
        connectivity: WatchConnectivityManager
    ) async {
        for action in actions {
            await dispatchOne(action, auth: auth, connectivity: connectivity)
        }
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
                OfflineQueue.shared.enqueueAcceptLoad(loadId: loadId, bidId: bidId)
                await OfflineQueue.shared.flush(auth: auth)
                currentRoute = .toast(message: "Accepted \(loadId). Dispatch notified.")
            }

        case "decline_load":
            if let loadId = action.payload?.dictValue?["loadId"] as? String {
                currentRoute = .toast(message: "Declined \(loadId).")
                _ = try? await EsangClient(auth: auth).mutateJSON(
                    "loads.decline",
                    input: ["loadId": loadId, "source": "watch"]
                )
            }

        case "log_arrival":
            if let loadId = action.payload?.dictValue?["loadId"] as? String,
               let kind = action.payload?.dictValue?["kind"] as? String {
                OfflineQueue.shared.enqueueArrived(loadId: loadId, kind: kind, at: Date())
                await OfflineQueue.shared.flush(auth: auth)
                currentRoute = .toast(message: "Arrived at \(kind). ✓")
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
                _ = try? await EsangClient(auth: auth).mutateJSON(
                    "messages.send",
                    input: ["threadId": threadId, "text": text]
                )
                currentRoute = .toast(message: "Sent ✓")
            }

        case "wallet_overview":
            currentRoute = .wallet

        case "open_load_auction":
            if let loadId = action.payload?.dictValue?["loadId"] as? String {
                currentRoute = .loadAuction(loadId: loadId)
            }

        case "escort_check":
            currentRoute = .hazmatEscort

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
}
