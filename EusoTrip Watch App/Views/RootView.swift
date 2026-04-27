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
    @StateObject private var dispatcher = VoiceActionDispatcher.shared
    @StateObject private var emergency = EmergencyController.shared
    @State private var sheetRoute: WatchRoute?

    var body: some View {
        TabView {
            HomeView()
                .tag(0)
            HOSView()
                .tag(1)
            InboxView()
                .tag(2)
            WalletView()
                .tag(3)
            personaTab()
                .tag(4)
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
    private func personaTab() -> some View {
        switch auth.role {
        case "dispatcher":   DispatcherBoardView()
        case "broker":       BrokerAuctionsView()
        case "shipper":      ShipperShipmentsView()
        default:             RouteOverviewView()
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
        }
    }
}
