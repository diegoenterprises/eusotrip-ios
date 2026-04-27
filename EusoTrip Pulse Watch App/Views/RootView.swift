//
//  RootView.swift
//  EusoTrip Watch App
//
//  Top-level TabView — rotates the Digital Crown between:
//    1. Home (push-to-talk + active load card)
//    2. HOS (drive/window/cycle rings + status change)
//    3. Inbox (recent threads)
//    4. Wallet (balance + last 3 payouts)
//    5. Persona-specific tab (driver → Route, dispatcher → Board,
//       broker → Auctions, shipper → Shipments)
//
//  VoiceActionDispatcher writes to `currentRoute` — when it becomes
//  non-nil we present the corresponding sheet on top of the selected
//  tab so voice commands work from any tab.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var esang: EsangSession
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @EnvironmentObject var hos: HOSStore
    @EnvironmentObject var loads: LoadStore
    // Singletons are injected via .environmentObject in EusoTripWatchApp —
    // but VoiceActionDispatcher and EmergencyController are consumed only
    // by RootView, so they sit here as @ObservedObject rather than
    // @EnvironmentObject. We deliberately avoid @StateObject here: under
    // watchOS 26.4's tightened concurrency checking, @StateObject wrapping
    // a `.shared` singleton fights SwiftUI's lifecycle tracking and
    // contributes to the main-thread launch hang.
    @ObservedObject private var dispatcher = VoiceActionDispatcher.shared
    @ObservedObject private var emergency = EmergencyController.shared
    @State private var sheetRoute: WatchRoute?

    var body: some View {
        // Role-aware tab composition — see RoleComposition.swift for the
        // 24-persona layout table. Falls back to the legacy 5-tab
        // driver layout when role is nil/unrecognized.
        let tabs = RoleComposition.tabs(for: auth.role)
        let roleLabel = RoleComposition.label(for: auth.role)
        let vertical = RoleComposition.vertical(for: auth.role)
        TabView {
            ForEach(Array(tabs.enumerated()), id: \.offset) { idx, tab in
                RoleTabHost(tab: tab, roleLabel: roleLabel, vertical: vertical)
                    .tag(idx)
            }
        }
        .tabViewStyle(.verticalPage)
        .overlay {
            if emergency.isActive {
                EmergencyView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .sheet(item: Binding(get: {
            sheetRoute
        }, set: { sheetRoute = $0 })) { route in
            sheetContent(route)
        }
        .onChange(of: dispatcher.currentRoute) { _, newRoute in
            switch newRoute {
            case .none, .home:
                break
            case .emergency:
                break // overlay already shown
            default:
                sheetRoute = newRoute
                dispatcher.currentRoute = nil
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ route: WatchRoute) -> some View {
        switch route {
        case .loadDetail(let loadId):
            WatchLoadDetailView(loadId: loadId)
        case .toast(let message):
            ToastView(message: message)
        case .dispatchCall:
            DispatchCallView()
        case .loadAuction(let loadId):
            LoadAuctionView(loadId: loadId)
        case .hazmatEscort:
            HazmatEscortView()
        case .ergLookup:
            ErgLookupView()
        case .convoy:
            ConvoyView()
        case .proximityHandoff:
            ProximityHandoffView()
        case .voiceConfirm(let prompt, let confirmId):
            VoiceConfirmSheet(prompt: prompt, confirmId: confirmId)
        case .hos, .home, .inbox, .wallet, .emergency,
             .dispatcherBoard, .shipperBoard, .brokerBoard:
            EmptyView()
        }
    }
}

extension WatchRoute: Identifiable {
    var id: String {
        switch self {
        case .home: return "home"
        case .loadDetail(let id): return "load-\(id)"
        case .hos: return "hos"
        case .inbox: return "inbox"
        case .wallet: return "wallet"
        case .dispatchCall: return "dispatchCall"
        case .emergency: return "emergency"
        case .toast(let msg): return "toast-\(msg)"
        case .loadAuction(let id): return "auction-\(id)"
        case .hazmatEscort: return "hazmat-escort"
        case .ergLookup: return "erg"
        case .dispatcherBoard: return "dispatch"
        case .shipperBoard: return "shipper"
        case .brokerBoard: return "broker"
        case .convoy: return "convoy"
        case .proximityHandoff: return "proximityHandoff"
        case .voiceConfirm(_, let cid): return "voiceConfirm-\(cid)"
        }
    }
}
