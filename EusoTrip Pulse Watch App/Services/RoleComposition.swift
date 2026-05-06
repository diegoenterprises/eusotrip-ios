//
//  RoleComposition.swift
//  EusoTrip Pulse Watch App
//
//  Single source of truth for the 24-role × 3-vertical tab layout.
//  Every layout here consists ONLY of tabs that are backed by a
//  live server endpoint (truly dynamic, like the app + web
//  platform). Zero placeholder tabs. If a role domain is not yet
//  covered by a server endpoint, the wrist surfaces whichever of
//  that role's tabs ARE server-backed — it never shows a fake tab.
//
//  Canonical roles (drizzle/schema.ts:51-74, UPPERCASE):
//
//    Truck (12)  SHIPPER · CATALYST · BROKER · DRIVER · DISPATCH ·
//                ESCORT · TERMINAL_MANAGER · COMPLIANCE_OFFICER ·
//                SAFETY_MANAGER · FACTORING · ADMIN · SUPER_ADMIN
//    Rail (6)    RAIL_SHIPPER · RAIL_CATALYST · RAIL_DISPATCHER ·
//                RAIL_ENGINEER · RAIL_CONDUCTOR · RAIL_BROKER
//    Vessel (6)  VESSEL_SHIPPER · VESSEL_OPERATOR · PORT_MASTER ·
//                SHIP_CAPTAIN · VESSEL_BROKER · CUSTOMS_BROKER
//
//  Endpoint backing for every tab rendered below — verified against
//  `eusoronetechnologiesinc/frontend/server/routers/*`:
//
//    home            — HomeView + AuthStore/LoadStore/HOSStore live
//    hos             — HOSView + hos.getStatus
//    inbox           — InboxView + messages.listThreads
//    wallet          — WalletView + wallet.getBalance + wallet.getTransactions
//    route           — RouteOverviewView + CoreLocation + navigation
//    safetyCoach     — WristSafetyCoachView + esangCoach.forDriver
//    dispatchBoard   — DispatcherBoardView + dispatch.getExceptions
//    brokerAuctions  — BrokerAuctionsView + loadBidding.getReceivedBids
//    shipperBoard    — ShipperShipmentsView + shipments.listActive
//    hazmatEscort    — HazmatEscortView + hazmatEscort.getStatus
//    compliance      — DynamicBoardView + compliance.getViolations
//    maintenance     — DynamicBoardView + equipment.list
//    fuel            — DynamicBoardView + fuel.getTransactions
//    factoring       — DynamicBoardView + factoring.getOverview
//    adminPlatform   — DynamicBoardView + admin.getRecentActivity
//    safetyOps       — DynamicBoardView + safety.getRecentIncidents
//    railShipmentBoard — DynamicBoardView + railShipments.getRailShipments
//    trainConsist    — DynamicBoardView + railShipments.getRailcars
//    vesselShipmentBoard — DynamicBoardView + vesselShipments.getVesselShipments
//    customs         — DynamicBoardView + vesselShipments.listBOLs
//    intermodal      — DynamicBoardView + intermodal.getIntermodalShipments
//    portOps         — DynamicBoardView + controlTower.exceptions
//    insurance       — DynamicBoardView + claims.list
//
//  Tabs that previously existed but were cut here because no real
//  server endpoint backs them yet (would have required fabricating
//  data on the wrist, violating the no-stubs doctrine):
//    ptcBoard · cargoStowage · portClearance · locomotiveHOS ·
//    bridgeWatch · terminalOps · escortConvoy · consigneeDock ·
//    warehouseOps
//
//  Rail/vessel engineers + captains surface HOS through the generic
//  .hos tab (the server's hos router is the single source of duty
//  truth). When the backend ships rail-HOS (49 CFR 228) or marine-
//  rest-hours (STCW A-VIII/1) endpoints, dedicated views go here.
//

import Foundation

// MARK: - WatchTab

/// Tab identifiers the wrist can render. Every case here maps to
/// a real, server-backed view. If a case is added, its backing
/// endpoint lives in `DynamicBoardView.swift` or a dedicated view
/// file.
enum WatchTab: String, Codable, CaseIterable {
    // Core (cross-vertical)
    case home
    case hos
    case inbox
    case wallet
    case route
    case safetyCoach

    // Dashboards with dedicated views
    case dispatchBoard
    case brokerAuctions
    case shipperBoard
    case hazmatEscort

    // Dashboards rendered through DynamicBoardView (tRPC-backed)
    case compliance
    case maintenance
    case fuel
    case factoring
    case adminPlatform
    case safetyOps
    case railShipmentBoard
    case trainConsist
    case vesselShipmentBoard
    case customs
    case intermodal
    case portOps
    case insurance

    /// FMCSA Request for Data Review (RDR) tracking. Backed by the
    /// `dataqs.listMine` proc deployed 2026-05-05. Reform-aware:
    /// `expectedReplyBy` is the 21d FMCSA initial-review SLA; the wrist
    /// surfaces "5d left" so Compliance Officer / Safety Manager /
    /// Driver / Catalyst can glance at which RDRs are about to lapse.
    case dataqs
}

// MARK: - RoleComposition

enum RoleComposition {

    static func tabs(for role: String?) -> [WatchTab] {
        let raw = (role ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return defaultTabs }
        if let explicit = canonicalLayouts[raw.uppercased()] { return explicit }
        if let legacy = legacyLayouts[raw.lowercased()] { return legacy }
        return softMatch(raw) ?? defaultTabs
    }

    static func label(for role: String?) -> String {
        let raw = (role ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let canonical = canonicalLabels[raw.uppercased()] { return canonical }
        if let legacy = legacyLabels[raw.lowercased()] { return legacy }
        return "Pulse"
    }

    static func vertical(for role: String?) -> PulseVertical {
        let r = (role ?? "").uppercased()
        if r.hasPrefix("RAIL_") { return .rail }
        if r.hasPrefix("VESSEL_") || r == "PORT_MASTER" || r == "SHIP_CAPTAIN" || r == "CUSTOMS_BROKER" {
            return .vessel
        }
        return .truck
    }

    static var allCanonicalRoles: [String] { Array(canonicalLayouts.keys).sorted() }

    // MARK: - Canonical 24-role layouts

    private static let canonicalLayouts: [String: [WatchTab]] = [
        // ── Truck (12) ────────────────────────────────────────────
        // DataQs RDR added to roles that own FMCSA record correction
        // (Compliance Officer, Safety Manager, Driver, Catalyst,
        // Admin/Super Admin). Shipper/Broker/Factoring don't file
        // DataQs against their own carrier records, so the tab is
        // omitted from their layouts to keep wrist real estate tight.
        "SHIPPER":             [.home, .shipperBoard, .inbox, .wallet, .compliance],
        "CATALYST":            [.home, .dispatchBoard, .brokerAuctions, .dataqs, .inbox, .wallet],
        "BROKER":              [.home, .brokerAuctions, .dispatchBoard, .inbox, .wallet],
        "DRIVER":              [.home, .hos, .route, .inbox, .wallet, .safetyCoach, .dataqs],
        "DISPATCH":            [.home, .dispatchBoard, .inbox, .hos, .maintenance],
        "ESCORT":              [.home, .hazmatEscort, .route, .inbox, .compliance],
        "TERMINAL_MANAGER":    [.home, .dispatchBoard, .compliance, .maintenance, .inbox],
        "COMPLIANCE_OFFICER":  [.home, .compliance, .dataqs, .hos, .safetyOps, .inbox],
        "SAFETY_MANAGER":      [.home, .safetyOps, .compliance, .dataqs, .hos, .inbox],
        "FACTORING":           [.home, .factoring, .wallet, .inbox, .dispatchBoard],
        "ADMIN":               [.home, .adminPlatform, .dispatchBoard, .compliance, .dataqs, .inbox],
        "SUPER_ADMIN":         [.home, .adminPlatform, .dispatchBoard, .compliance, .dataqs, .safetyOps],

        // ── Rail (6) ─────────────────────────────────────────────
        "RAIL_SHIPPER":        [.home, .railShipmentBoard, .inbox, .wallet, .customs],
        "RAIL_CATALYST":       [.home, .railShipmentBoard, .dispatchBoard, .inbox, .wallet],
        "RAIL_DISPATCHER":     [.home, .dispatchBoard, .railShipmentBoard, .inbox, .compliance],
        "RAIL_ENGINEER":       [.home, .hos, .trainConsist, .inbox, .safetyCoach],
        "RAIL_CONDUCTOR":      [.home, .trainConsist, .hos, .compliance, .inbox],
        "RAIL_BROKER":         [.home, .brokerAuctions, .railShipmentBoard, .inbox, .wallet],

        // ── Vessel (6) ───────────────────────────────────────────
        "VESSEL_SHIPPER":      [.home, .vesselShipmentBoard, .inbox, .wallet, .customs],
        "VESSEL_OPERATOR":     [.home, .vesselShipmentBoard, .portOps, .customs, .inbox],
        "PORT_MASTER":         [.home, .portOps, .customs, .intermodal, .inbox],
        "SHIP_CAPTAIN":        [.home, .hos, .vesselShipmentBoard, .inbox, .safetyCoach],
        "VESSEL_BROKER":       [.home, .brokerAuctions, .vesselShipmentBoard, .inbox, .wallet],
        "CUSTOMS_BROKER":      [.home, .customs, .intermodal, .inbox, .wallet],
    ]

    // MARK: - Canonical labels

    private static let canonicalLabels: [String: String] = [
        // Truck
        "SHIPPER":             "Shipper",
        "CATALYST":            "Catalyst",
        "BROKER":              "Broker",
        "DRIVER":              "Driver",
        "DISPATCH":            "Dispatch",
        "ESCORT":              "Hazmat Escort",
        "TERMINAL_MANAGER":    "Terminal Mgr",
        "COMPLIANCE_OFFICER":  "Compliance",
        "SAFETY_MANAGER":      "Safety Mgr",
        "FACTORING":           "Factoring",
        "ADMIN":               "Admin",
        "SUPER_ADMIN":         "Super Admin",
        // Rail
        "RAIL_SHIPPER":        "Rail Shipper",
        "RAIL_CATALYST":       "Rail Catalyst",
        "RAIL_DISPATCHER":     "Rail Dispatch",
        "RAIL_ENGINEER":       "Engineer",
        "RAIL_CONDUCTOR":      "Conductor",
        "RAIL_BROKER":         "Rail Broker",
        // Vessel
        "VESSEL_SHIPPER":      "Vessel Shipper",
        "VESSEL_OPERATOR":     "Vessel Operator",
        "PORT_MASTER":         "Port Master",
        "SHIP_CAPTAIN":        "Captain",
        "VESSEL_BROKER":       "Vessel Broker",
        "CUSTOMS_BROKER":      "Customs",
    ]

    // MARK: - Legacy aliases (lowercase pre-refactor Pulse keys)
    //
    // Every legacy layout reuses tabs that are still server-backed.
    // Pre-refactor tabs that had no real endpoint (consigneeDock,
    // warehouseOps, terminalOps, etc.) are remapped here to the
    // closest real-data tab for that role.

    private static let legacyLayouts: [String: [WatchTab]] = [
        "driver_ownerop":              [.home, .hos, .wallet, .route, .inbox, .dataqs],
        "driver_company":              [.home, .hos, .route, .inbox, .wallet, .dataqs],
        "driver_team":                 [.home, .hos, .route, .inbox, .wallet, .dataqs],
        "driver":                      [.home, .hos, .route, .inbox, .wallet, .dataqs],

        "dispatcher_independent":      [.home, .dispatchBoard, .inbox, .hos, .wallet],
        "dispatcher_inhouse":          [.home, .dispatchBoard, .inbox, .hos, .maintenance],
        "dispatcher":                  [.home, .dispatchBoard, .inbox, .hos, .maintenance],

        "carrier_owner_small":         [.home, .dispatchBoard, .wallet, .hos, .factoring],
        "carrier_owner_mid":           [.home, .dispatchBoard, .maintenance, .fuel, .wallet],
        "carrier_owner_large":         [.home, .dispatchBoard, .compliance, .fuel, .maintenance],

        "broker_3pl":                  [.home, .brokerAuctions, .dispatchBoard, .inbox, .wallet],
        "broker_agent":                [.home, .brokerAuctions, .inbox, .wallet, .dispatchBoard],
        "broker":                      [.home, .brokerAuctions, .dispatchBoard, .inbox, .wallet],

        "shipper_ftl":                 [.home, .shipperBoard, .inbox, .compliance, .wallet],
        "shipper_ltl":                 [.home, .shipperBoard, .inbox, .wallet, .compliance],
        "shipper":                     [.home, .shipperBoard, .inbox, .compliance, .wallet],
        "consignee":                   [.home, .shipperBoard, .inbox, .wallet, .compliance],

        "warehouse_manager":           [.home, .maintenance, .dispatchBoard, .inbox, .compliance],
        "dock_supervisor":             [.home, .dispatchBoard, .compliance, .inbox, .hos],

        "hazmat_specialist":           [.home, .hazmatEscort, .compliance, .route, .inbox, .dataqs],
        "fmcsa_auditor":               [.home, .compliance, .dataqs, .hos, .inbox, .maintenance],

        "maintenance_manager":         [.home, .maintenance, .dispatchBoard, .inbox, .fuel],
        "fuel_backoffice":             [.home, .fuel, .wallet, .dispatchBoard, .inbox],
        "factoring_underwriter":       [.home, .factoring, .wallet, .inbox, .dispatchBoard],
        "port_ops":                    [.home, .portOps, .intermodal, .customs, .inbox],
        "customs_broker":              [.home, .customs, .intermodal, .inbox, .wallet],
        "intermodal_coordinator":      [.home, .intermodal, .portOps, .route, .inbox],
        "insurance_adjuster":          [.home, .insurance, .inbox, .compliance, .wallet],
    ]

    private static let legacyLabels: [String: String] = [
        "driver_ownerop":         "Owner-Operator",
        "driver_company":         "Company Driver",
        "driver_team":            "Team Driver",
        "driver":                 "Driver",
        "dispatcher_independent": "Dispatcher",
        "dispatcher_inhouse":     "Dispatcher",
        "dispatcher":             "Dispatcher",
        "carrier_owner_small":    "Carrier Owner",
        "carrier_owner_mid":      "Fleet Manager",
        "carrier_owner_large":    "Fleet Ops",
        "broker_3pl":             "3PL Broker",
        "broker_agent":           "Broker Agent",
        "broker":                 "Broker",
        "shipper_ftl":            "FTL Shipper",
        "shipper_ltl":            "LTL Shipper",
        "shipper":                "Shipper",
        "consignee":              "Consignee",
        "warehouse_manager":      "Warehouse Mgr",
        "dock_supervisor":        "Dock Supervisor",
        "hazmat_specialist":      "Hazmat Specialist",
        "fmcsa_auditor":          "FMCSA Auditor",
        "maintenance_manager":    "Maintenance Mgr",
        "fuel_backoffice":        "Fuel Ops",
        "factoring_underwriter":  "Factoring",
        "port_ops":               "Port Ops",
        "customs_broker":         "Customs",
        "intermodal_coordinator": "Intermodal",
        "insurance_adjuster":     "Insurance",
    ]

    // MARK: - Fallbacks

    private static func softMatch(_ raw: String) -> [WatchTab]? {
        let r = raw.uppercased()
        if r.contains("RAIL")       { return canonicalLayouts["RAIL_DISPATCHER"] }
        if r.contains("VESSEL") || r.contains("SHIP") || r.contains("PORT") {
            return canonicalLayouts["VESSEL_OPERATOR"]
        }
        if r.contains("CUSTOMS")    { return canonicalLayouts["CUSTOMS_BROKER"] }
        if r.contains("SHIPPER")    { return canonicalLayouts["SHIPPER"] }
        if r.contains("BROKER")     { return canonicalLayouts["BROKER"] }
        if r.contains("DISPATCH")   { return canonicalLayouts["DISPATCH"] }
        if r.contains("ESCORT")     { return canonicalLayouts["ESCORT"] }
        if r.contains("COMPLIANCE") { return canonicalLayouts["COMPLIANCE_OFFICER"] }
        if r.contains("SAFETY")     { return canonicalLayouts["SAFETY_MANAGER"] }
        if r.contains("FACTOR")     { return canonicalLayouts["FACTORING"] }
        if r.contains("ADMIN")      { return canonicalLayouts["ADMIN"] }
        if r.contains("DRIVER")     { return canonicalLayouts["DRIVER"] }
        return nil
    }

    private static let defaultTabs: [WatchTab] = [
        .home, .hos, .route, .inbox, .wallet
    ]
}

// MARK: - PulseVertical

public enum PulseVertical: String, Codable {
    case truck
    case rail
    case vessel

    public var label: String {
        switch self {
        case .truck:  return "Truck"
        case .rail:   return "Rail"
        case .vessel: return "Vessel"
        }
    }

    public var primaryRegulator: String {
        switch self {
        case .truck:  return "FMCSA"
        case .rail:   return "FRA / STB"
        case .vessel: return "USCG / IMO"
        }
    }
}
