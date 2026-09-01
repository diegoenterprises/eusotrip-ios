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
    @State private var selectedTab: Int

    init() {
        #if targetEnvironment(simulator)
        let visualState = ProcessInfo.processInfo.environment["EUSOTRIP_PULSE_VISUAL_STATE"]
        if visualState?.hasPrefix("route") == true {
            _selectedTab = State(initialValue: 2)
        } else if visualState?.hasPrefix("inbox") == true {
            _selectedTab = State(initialValue: 3)
        } else if visualState?.hasPrefix("wallet") == true {
            _selectedTab = State(initialValue: 4)
        } else if visualState?.hasPrefix("safety-") == true {
            _selectedTab = State(initialValue: 5)
        } else {
            _selectedTab = State(initialValue: 0)
        }
        #else
        _selectedTab = State(initialValue: 0)
        #endif
    }

    private var tabs: [WatchTab] {
        #if targetEnvironment(simulator)
        let visualState = ProcessInfo.processInfo.environment["EUSOTRIP_PULSE_VISUAL_STATE"]
        if visualState?.hasPrefix("route") == true
            || visualState?.hasPrefix("inbox") == true
            || visualState?.hasPrefix("wallet") == true
            || visualState?.hasPrefix("safety-") == true {
            return RoleComposition.tabs(for: "DRIVER")
        }
        #endif
        return RoleComposition.tabs(for: auth.role)
    }

    var body: some View {
        // Role-aware tab composition — see RoleComposition.swift for the
        // 24-persona layout table. Falls back to the legacy 5-tab
        // driver layout when role is nil/unrecognized.
        let roleLabel = RoleComposition.label(for: auth.role)
        let vertical = RoleComposition.vertical(for: auth.role)
        TabView(selection: $selectedTab) {
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
            handle(newRoute)
        }
        .onChange(of: auth.role) { _, _ in
            selectedTab = 0
        }
    }

    private func handle(_ route: WatchRoute?) {
        guard let route else { return }
        switch route {
        case .home:
            select(.home, fallback: route)
        case .hos:
            select(.hos, fallback: route)
        case .inbox:
            select(.inbox, fallback: route)
        case .wallet:
            select(.wallet, fallback: route)
        case .dispatcherBoard:
            select(.dispatchBoard, fallback: route)
        case .shipperBoard:
            select(.shipperBoard, fallback: route)
        case .brokerBoard:
            select(.brokerAuctions, fallback: route)
        case .emergency:
            dispatcher.currentRoute = nil
        default:
            sheetRoute = route
            dispatcher.currentRoute = nil
        }
    }

    private func select(_ tab: WatchTab, fallback route: WatchRoute) {
        if let index = tabs.firstIndex(of: tab) {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = index
            }
        } else if route == .home {
            selectedTab = 0
        } else {
            sheetRoute = route
        }
        dispatcher.currentRoute = nil
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
        case .bolCopilot:
            BOLCopilotView()
        case .voiceConfirm(let prompt, let confirmId):
            VoiceConfirmSheet(prompt: prompt, confirmId: confirmId)
        case .hos:
            HOSView()
        case .inbox:
            InboxView()
        case .wallet:
            WalletView()
        case .dispatcherBoard:
            DispatcherBoardView()
        case .shipperBoard:
            ShipperShipmentsView()
        case .brokerBoard:
            BrokerAuctionsView()
        case .home, .emergency:
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
        case .bolCopilot: return "bolCopilot"
        case .voiceConfirm(_, let cid): return "voiceConfirm-\(cid)"
        }
    }
}
