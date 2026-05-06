//
//  RoleTabHost.swift
//  EusoTrip Pulse Watch App
//
//  Resolves each `WatchTab` case to a real server-backed view.
//  Every branch either returns a purpose-built view that already
//  has live tRPC wiring (HomeView, HOSView, InboxView, WalletView,
//  RouteOverviewView, DispatcherBoardView, BrokerAuctionsView,
//  ShipperShipmentsView, HazmatEscortView, WristSafetyCoachView),
//  or a `DynamicBoardView` configured with a verified live endpoint
//  from `BoardFactory`.
//
//  Zero placeholders. Zero stubs. Zero fixtures. Every tab the
//  wrist ever shows is backed by real data from the same platform
//  the iPhone + web clients read.
//

import SwiftUI

struct RoleTabHost: View {
    let tab: WatchTab
    let roleLabel: String
    var vertical: PulseVertical = .truck

    var body: some View {
        switch tab {

        // MARK: Dedicated views (already server-wired)
        case .home:           HomeView()
        case .hos:            HOSView()
        case .inbox:          InboxView()
        case .wallet:         WalletView()
        case .route:          RouteOverviewView()
        case .safetyCoach:    WristSafetyCoachView()
        case .dispatchBoard:  DispatcherBoardView()
        case .brokerAuctions: BrokerAuctionsView()
        case .shipperBoard:   ShipperShipmentsView()
        case .hazmatEscort:   HazmatEscortView()

        // MARK: DynamicBoardView — each bound to a real tRPC endpoint
        case .compliance:
            DynamicBoardView(
                title: "Compliance",
                regulator: vertical.primaryRegulator,
                emptyMessage: "No open violations.",
                store: BoardFactory.compliance()
            )
        case .maintenance:
            DynamicBoardView(
                title: "Maintenance",
                regulator: "49 CFR 396",
                emptyMessage: "Fleet clear — no open maintenance flags.",
                store: BoardFactory.maintenance()
            )
        case .fuel:
            DynamicBoardView(
                title: "Fuel",
                regulator: "IFTA",
                emptyMessage: "No recent fuel transactions.",
                store: BoardFactory.fuel()
            )
        case .factoring:
            DynamicBoardView(
                title: "Factoring",
                regulator: "BSA / AML",
                emptyMessage: "No open factoring items.",
                store: BoardFactory.factoring()
            )
        case .adminPlatform:
            DynamicBoardView(
                title: "Platform Ops",
                regulator: vertical.primaryRegulator,
                emptyMessage: "No recent platform activity.",
                store: BoardFactory.adminPlatform()
            )
        case .safetyOps:
            DynamicBoardView(
                title: "Safety Ops",
                regulator: "49 CFR 385",
                emptyMessage: "No recent incidents.",
                store: BoardFactory.safetyOps()
            )
        case .railShipmentBoard:
            DynamicBoardView(
                title: "Rail Shipments",
                regulator: "49 CFR 174",
                emptyMessage: "No active rail shipments.",
                store: BoardFactory.railShipmentBoard()
            )
        case .trainConsist:
            DynamicBoardView(
                title: "Consist",
                regulator: "49 CFR 172.600",
                emptyMessage: "No railcars on current consist.",
                store: BoardFactory.trainConsist()
            )
        case .vesselShipmentBoard:
            DynamicBoardView(
                title: "Vessel Shipments",
                regulator: "46 CFR 515",
                emptyMessage: "No active vessel shipments.",
                store: BoardFactory.vesselShipmentBoard()
            )
        case .customs:
            DynamicBoardView(
                title: "Customs",
                regulator: "19 CFR 111",
                emptyMessage: "No pending BOLs.",
                store: BoardFactory.customs()
            )
        case .intermodal:
            DynamicBoardView(
                title: "Intermodal",
                regulator: "49 CFR 392",
                emptyMessage: "No intermodal moves.",
                store: BoardFactory.intermodal()
            )
        case .portOps:
            DynamicBoardView(
                title: "Port Ops",
                regulator: "33 CFR 160",
                emptyMessage: "No port exceptions.",
                store: BoardFactory.portOps()
            )
        case .insurance:
            DynamicBoardView(
                title: "Claims",
                regulator: "49 CFR 387",
                emptyMessage: "No open claims.",
                store: BoardFactory.insurance()
            )
        case .dataqs:
            // FMCSA Request for Data Review tracker — reform-aware
            // 21d initial-review SLA shown as "5d left" / "OVERDUE"
            // accessory chips per row. 49 CFR §386 governs the RDR
            // process; the 2026 reform placed burden of proof on the
            // requestor and barred officers from deciding their own.
            DynamicBoardView(
                title: "DataQs RDR",
                regulator: "49 CFR §386",
                emptyMessage: "No filed RDRs. Tap a violation on the iPhone to file one.",
                store: BoardFactory.dataqs()
            )
        }
    }
}
