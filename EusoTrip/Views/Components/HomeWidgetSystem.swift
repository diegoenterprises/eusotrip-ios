//
//  HomeWidgetSystem.swift
//  EusoTrip
//
//  Shared, server-backed in-app Home widget system. This is intentionally
//  separate from WidgetKit: these widgets compose each role's signed-in Home.
//

import SwiftUI

enum HomeWidgetCategory: String, Codable, CaseIterable {
    case analytics, operations, financial, communication
    case productivity, safety, compliance, performance
    case planning, tracking, reporting, management
}

enum HomeWidgetSpan: String, Codable, CaseIterable, Hashable {
    case compact, half, full

    var grid: (w: Int, h: Int) {
        switch self {
        case .compact: return (12, 4)
        case .half: return (6, 6)
        case .full: return (12, 8)
        }
    }

    static func from(w: Int, h: Int) -> HomeWidgetSpan {
        if w <= 6 { return .half }
        return h <= 4 ? .compact : .full
    }

    var menuLabel: String {
        switch self {
        case .compact: return "Compact"
        case .half: return "Half width"
        case .full: return "Full width"
        }
    }

    var menuIcon: String {
        switch self {
        case .compact: return "rectangle.compress.vertical"
        case .half: return "rectangle.split.2x1"
        case .full: return "rectangle"
        }
    }

    func stepped(_ direction: AccessibilityAdjustmentDirection) -> HomeWidgetSpan {
        let values = Self.allCases
        guard let index = values.firstIndex(of: self) else { return self }
        switch direction {
        case .increment: return values[min(index + 1, values.count - 1)]
        case .decrement: return values[max(index - 1, 0)]
        @unknown default: return self
        }
    }
}

private struct HomeWidgetSpanKey: EnvironmentKey {
    static let defaultValue: HomeWidgetSpan = .full
}

extension EnvironmentValues {
    var homeWidgetSpan: HomeWidgetSpan {
        get { self[HomeWidgetSpanKey.self] }
        set { self[HomeWidgetSpanKey.self] = newValue }
    }
}

struct HomeWidgetDef: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let icon: String
    let category: HomeWidgetCategory
    let roles: Set<String>
    let availableSizes: [HomeWidgetSpan]

    var defaultSpan: HomeWidgetSpan { availableSizes.last ?? .full }
}

struct HomeWidgetManifest: Identifiable, Hashable {
    let role: String
    let defaultWidgetIDs: [String]
    let roleWidgetIDs: [String]
    var id: String { role }
}

/// Product catalog for all 25 signed-in personas. A manifest describes the
/// purpose of a role Home even when that role still routes through a web
/// continuation today; only IDs the native host can render enter its picker.
enum HomeWidgetCatalog {
    static let roleIDs: [String] = [
        "DRIVER", "SHIPPER", "CATALYST", "BROKER", "DISPATCH", "ESCORT",
        "TERMINAL_MANAGER", "COMPLIANCE_OFFICER", "SAFETY_MANAGER", "ADMIN",
        "SUPER_ADMIN", "FACTORING", "RAIL_SHIPPER", "RAIL_CATALYST",
        "RAIL_DISPATCHER", "RAIL_ENGINEER", "RAIL_CONDUCTOR", "RAIL_BROKER",
        "VESSEL_SHIPPER", "VESSEL_OPERATOR", "PORT_MASTER", "SHIP_CAPTAIN",
        "VESSEL_BROKER", "CUSTOMS_BROKER", "SERVICE_PROVIDER"
    ]

    private static let universalRoles = Set(roleIDs)

    static let universal: [HomeWidgetDef] = [
        def("weather", "Weather", "Local and route conditions, including unavailable states", "cloud.sun.fill", .planning, universalRoles),
        def("notifications", "Notifications", "Recent platform alerts", "bell.fill", .communication, universalRoles),
        def("messages", "Messages", "Unread and active conversations", "message.fill", .communication, universalRoles),
        def("news", "Freight news", "Headlines from the EusoTrip news feed", "newspaper.fill", .reporting, universalRoles),
        def("recent", "Recent activity", "Latest movements and events", "clock.arrow.circlepath", .reporting, universalRoles),
    ]

    static let manifests: [String: HomeWidgetManifest] = {
        let entries: [(String, [String])] = [
            ("DRIVER", ["current_route", "next_delivery", "hos_tracker", "earnings_summary", "haul", "compliance"]),
            ("SHIPPER", ["shipper_actions", "shipper_summary", "activeLoads", "esang", "spend_summary", "attention_alerts"]),
            ("CATALYST", ["activeMatches", "gmv_summary", "catalyst_alerts"]),
            ("BROKER", ["openTenders", "margin_summary", "broker_alerts"]),
            ("DISPATCH", ["priority", "dispatch_summary", "tender_queue", "dispatch_esang", "hosWatch", "exceptions_list"]),
            ("ESCORT", ["activeAssignments", "escort_revenue", "escort_alerts"]),
            ("TERMINAL_MANAGER", ["activeMovements", "throughput_summary", "terminal_alerts"]),
            ("COMPLIANCE_OFFICER", ["expiringDocs", "violations_overview", "driver_compliance"]),
            ("SAFETY_MANAGER", ["open_incidents", "csa_watchlist", "corrective_actions"]),
            ("ADMIN", ["openTickets", "system_health", "pending_approvals"]),
            ("SUPER_ADMIN", ["openTickets", "system_health", "pending_approvals"]),
            ("FACTORING", ["pending_invoices", "funded_invoices", "receivables_aging"]),
            ("RAIL_SHIPPER", ["rail_eusocard", "rail_actions", "rail_attention", "rail_eta_watch", "rail_shipments", "rail_demurrage"]),
            ("RAIL_CATALYST", ["rail_yard_operations", "railcar_health", "rail_capacity"]),
            ("RAIL_DISPATCHER", ["rail_consists", "rail_yard_queue", "rail_exceptions"]),
            ("RAIL_ENGINEER", ["rail_overview", "asset_availability", "shipments_overview", "compliance_status", "crew_hos"]),
            ("RAIL_CONDUCTOR", ["crew_duty", "consist_manifest", "slow_orders"]),
            ("RAIL_BROKER", ["rail_tenders", "rail_rates", "interchange_risk"]),
            ("VESSEL_SHIPPER", ["vessel_eusocard", "vessel_actions", "demurrage_watch", "vessel_eta_watch", "vessel_ready_to_book", "vessel_bookings", "vessel_esang"]),
            ("VESSEL_OPERATOR", ["vessel_overview", "asset_availability", "bookings_overview", "compliance_status", "crew_roster"]),
            ("PORT_MASTER", ["port_lineup", "berth_schedule", "port_exceptions"]),
            ("SHIP_CAPTAIN", ["vessel_position", "crew_rest", "marine_conditions"]),
            ("VESSEL_BROKER", ["vessel_tenders", "booking_pipeline", "port_rates"]),
            ("CUSTOMS_BROKER", ["customs_entries", "customs_holds", "filing_deadlines"]),
            ("SERVICE_PROVIDER", ["zeun_work_orders", "zeun_team", "zeun_sla"]),
        ]
        return Dictionary(uniqueKeysWithValues: entries.map { role, ids in
            (role, HomeWidgetManifest(role: role, defaultWidgetIDs: ["weather"] + ids + ["news"], roleWidgetIDs: ids))
        })
    }()

    /// Definitions used by native role homes today, plus the 25-role manifest
    /// vocabulary. Names are intentional operational labels, not placeholder
    /// card numbers; the host still gates the library to views it really owns.
    static let all: [String: HomeWidgetDef] = {
        var definitions = Dictionary(uniqueKeysWithValues: universal.map { ($0.id, $0) })
        for manifest in manifests.values {
            for id in manifest.roleWidgetIDs where definitions[id] == nil {
                definitions[id] = inferredDefinition(id, role: manifest.role)
            }
        }
        let driverExtras = [
            "weather_alerts", "near_me_intel", "performance_score", "vehicle_health",
            "mileage_tracker", "fuel_economy", "wallet_activity", "fuel_stations",
            "rest_areas", "hotZones"
        ]
        for id in driverExtras { definitions[id] = inferredDefinition(id, role: "DRIVER") }
        let carrierExtras = ["activeLoads", "revenue_summary", "carrier_alerts"]
        for id in carrierExtras { definitions[id] = inferredDefinition(id, role: "CATALYST") }
        definitions["asset_availability"] = def(
            "asset_availability",
            "Asset availability",
            "Publish and manage mode-native capacity only when readiness evidence is complete",
            "shippingbox.and.arrow.backward.fill",
            .operations,
            ["RAIL_ENGINEER", "VESSEL_OPERATOR"]
        )
        return definitions
    }()

    static func manifest(for role: String) -> HomeWidgetManifest {
        manifests[role] ?? HomeWidgetManifest(role: role, defaultWidgetIDs: ["weather", "news"], roleWidgetIDs: [])
    }

    static func definition(for id: String, role: String) -> HomeWidgetDef {
        all[id] ?? inferredDefinition(id, role: role)
    }

    static func contractViolations() -> [String] {
        var violations: [String] = []
        if manifests.count != 25 { violations.append("Expected 25 role manifests; found \(manifests.count)") }
        for role in roleIDs {
            guard let manifest = manifests[role] else {
                violations.append("Missing manifest for \(role)")
                continue
            }
            if manifest.defaultWidgetIDs.first != "weather" { violations.append("\(role) does not start with weather") }
            if manifest.roleWidgetIDs.isEmpty { violations.append("\(role) has no role-specific widgets") }
            if Set(manifest.defaultWidgetIDs).count != manifest.defaultWidgetIDs.count { violations.append("\(role) has duplicate defaults") }
        }
        return violations
    }

    private static func def(
        _ id: String, _ name: String, _ summary: String, _ icon: String,
        _ category: HomeWidgetCategory, _ roles: Set<String>
    ) -> HomeWidgetDef {
        HomeWidgetDef(
            id: id, name: name, summary: summary, icon: icon, category: category,
            roles: roles, availableSizes: [.compact, .half, .full]
        )
    }

    private static func inferredDefinition(_ id: String, role: String) -> HomeWidgetDef {
        let explicit: [String: (String, String, HomeWidgetCategory)] = [
            "current_route": ("Current route", "Active route and arrival intelligence", .tracking),
            "next_delivery": ("Next delivery", "Upcoming stop and appointment", .operations),
            "hos_tracker": ("HOS tracker", "Driving and duty clocks", .compliance),
            "earnings_summary": ("Earnings", "Pay, bonuses and settlement trend", .financial),
            "haul": ("The Haul", "Weekly missions, streaks and driver progress", .performance),
            "compliance": ("Compliance countdown", "Driver requirements approaching action dates", .compliance),
            "activeLoads": ("Active loads", "Loads moving through pickup, transit and delivery", .tracking),
            "shipper_actions": ("Shipper actions", "Post freight or find qualified capacity", .operations),
            "shipper_summary": ("Shipment summary", "Current load, bid, service and rate evidence", .reporting),
            "esang": ("ESANG brief", "Counsel grounded in the shipper's current work", .planning),
            "spend_summary": ("Freight spend", "Committed freight cost and recent variance", .financial),
            "attention_alerts": ("Shipment attention", "Loads, documents and appointments needing action", .operations),
            "activeMatches": ("Capacity matches", "Shipper demand matched to available capacity", .operations),
            "gmv_summary": ("Network value", "Freight value moving through the catalyst network", .financial),
            "catalyst_alerts": ("Fleet attention", "Driver, vehicle and load exceptions needing action", .safety),
            "openTenders": ("Open tenders", "Tenders awaiting carrier response or award", .operations),
            "margin_summary": ("Margin bridge", "Expected buy, sell and gross-margin position", .financial),
            "broker_alerts": ("Broker exceptions", "Tender, carrier and appointment risks needing action", .operations),
            "priority": ("Priority queue", "The dispatch desk's most urgent work", .operations),
            "dispatch_summary": ("Dispatch summary", "Tender, haul, driver and service evidence", .reporting),
            "tender_queue": ("Tender queue", "Tenders awaiting review, acceptance or assignment", .operations),
            "dispatch_esang": ("ESANG dispatch counsel", "Grounded dispatch recommendations and their evidence", .planning),
            "hosWatch": ("HOS watchlist", "Drivers approaching duty limits", .compliance),
            "exceptions_list": ("Exceptions", "Open dispatch exceptions by severity", .safety),
            "activeAssignments": ("Escort assignments", "Permitted moves and upcoming escort handoffs", .tracking),
            "escort_revenue": ("Assignment earnings", "Completed work, pending settlement and payout", .financial),
            "escort_alerts": ("Route requirements", "Permit, equipment and jurisdiction actions", .compliance),
            "activeMovements": ("Gate movements", "Equipment moving through gate and yard", .operations),
            "throughput_summary": ("Terminal throughput", "Arrivals, releases and dwell by operating window", .performance),
            "terminal_alerts": ("Yard exceptions", "Congestion, holds and appointments needing action", .operations),
            "expiringDocs": ("Expiring documents", "Credentials and policies approaching expiration", .compliance),
            "violations_overview": ("Violation register", "Open violations by authority and deadline", .compliance),
            "driver_compliance": ("Driver readiness", "Drivers blocked or at risk by requirement", .compliance),
            "open_incidents": ("Incident register", "Open safety events awaiting review or evidence", .safety),
            "csa_watchlist": ("CSA watchlist", "BASIC categories and carriers needing review", .safety),
            "corrective_actions": ("Corrective actions", "Assigned remedies, owners and due dates", .management),
            "openTickets": ("Open support tickets", "Unresolved platform cases by urgency", .operations),
            "system_health": ("Platform health", "Service checks and degraded dependencies", .management),
            "pending_approvals": ("Approval queue", "Tenant and operating requests awaiting decision", .management),
            "pending_invoices": ("Invoices to review", "Purchased receivables awaiting a funding decision", .financial),
            "funded_invoices": ("Funded invoices", "Advances, reserves and settlement status", .financial),
            "receivables_aging": ("Receivables aging", "Open balances grouped by due window", .financial),
            "rail_shipments": ("Rail movements", "Rail shipments by origin, interchange and destination", .tracking),
            "rail_eusocard": ("Rail EusoCard", "Rail accessorial, claim and exception spend controls", .financial),
            "rail_actions": ("Rail actions", "Create shipment context or open authorized car tracking", .operations),
            "rail_attention": ("Rail attention", "Rail movements requiring operational review", .operations),
            "rail_eta_watch": ("Rail ETA watch", "Interchange and destination arrival exposure", .tracking),
            "rail_demurrage": ("Rail demurrage", "Free-time deadlines and accruing rail charges", .financial),
            "rail_yard_operations": ("Yard operations", "Railcars awaiting pull, placement or release", .operations),
            "railcar_health": ("Railcar health", "Equipment defects, inspections and shop holds", .safety),
            "rail_capacity": ("Rail capacity", "Available cars, slots and constrained lanes", .planning),
            "rail_consists": ("Consist board", "Train consists, blocks and planned departures", .operations),
            "rail_yard_queue": ("Yard move queue", "Prioritized pulls, spots and switches", .operations),
            "rail_exceptions": ("Rail exceptions", "Interchange, equipment and clearance blockers", .safety),
            "shipments_overview": ("Rail shipments", "Active rail movements", .tracking),
            "rail_overview": ("Rail operations", "Current cars, movements and transit evidence", .tracking),
            "compliance_status": ("Compliance status", "Documents and operating readiness", .compliance),
            "crew_hos": ("Crew HOS", "Rail crew duty availability", .safety),
            "crew_duty": ("Crew duty board", "Called crews, on-duty windows and relief risk", .safety),
            "consist_manifest": ("Consist manifest", "Cars, blocks, hazmat and placement order", .operations),
            "slow_orders": ("Slow orders", "Speed restrictions affecting the assigned route", .safety),
            "rail_tenders": ("Rail tenders", "Offers awaiting quote, award or acceptance", .operations),
            "rail_rates": ("Rail rate desk", "Contract, tariff and spot-rate comparisons", .financial),
            "interchange_risk": ("Interchange risk", "Connections exposed to missed handoff", .planning),
            "vessel_bookings": ("Ocean bookings", "Bookings by vessel, voyage and lifecycle state", .tracking),
            "vessel_eusocard": ("Vessel EusoCard", "Booking, claim and demurrage spend controls", .financial),
            "vessel_actions": ("Vessel actions", "Create a booking or open authorized cargo tracking", .operations),
            "vessel_eta_watch": ("Vessel ETA watch", "Port calls and transshipment connection exposure", .tracking),
            "demurrage_watch": ("Container free time", "Last-free-day and demurrage exposure", .financial),
            "vessel_ready_to_book": ("Ready to book", "Vessel and barge loads eligible for booking promotion", .operations),
            "vessel_esang": ("ESANG vessel counsel", "Grounded booking, filing and demurrage counsel", .planning),
            "bookings_overview": ("Vessel bookings", "Active ocean bookings", .tracking),
            "vessel_overview": ("Vessel operations", "Current bookings, containers and voyage evidence", .tracking),
            "crew_roster": ("Crew roster", "Vessel crew readiness", .operations),
            "port_lineup": ("Port lineup", "Expected arrivals, departures and anchorage order", .operations),
            "berth_schedule": ("Berth schedule", "Berth windows, conflicts and turnaround", .planning),
            "port_exceptions": ("Port exceptions", "Weather, clearance and terminal constraints", .safety),
            "vessel_position": ("Vessel position", "Course, speed and next navigational milestone", .tracking),
            "crew_rest": ("Crew rest", "Watchkeeping rest and relief exposure", .safety),
            "marine_conditions": ("Marine conditions", "Wind, sea and port conditions for the voyage", .planning),
            "vessel_tenders": ("Ocean tenders", "Requests awaiting quote, award or booking", .operations),
            "booking_pipeline": ("Booking pipeline", "Space requests progressing toward confirmation", .operations),
            "port_rates": ("Port rate desk", "Ocean, terminal and accessorial cost basis", .financial),
            "customs_entries": ("Customs entries", "Entries by filing, review and release state", .compliance),
            "customs_holds": ("Customs holds", "Agency holds and evidence needed for release", .compliance),
            "filing_deadlines": ("Filing deadlines", "Entry and manifest submissions approaching cutoff", .compliance),
            "zeun_work_orders": ("Work orders", "Open Zeun service work", .operations),
            "zeun_team": ("Field team", "Technician availability and assignment", .management),
            "zeun_sla": ("SLA watch", "Response and resolution commitments", .performance),
            "weather_alerts": ("Route weather alerts", "Conditions affecting the driver's active lane", .safety),
            "near_me_intel": ("Nearby load intelligence", "Available freight near the driver's position", .planning),
            "performance_score": ("Driver performance", "Safety, service and efficiency measures", .performance),
            "vehicle_health": ("Vehicle health", "Inspection, diagnostic and maintenance attention", .safety),
            "mileage_tracker": ("Mileage tracker", "Load, route and settlement miles", .tracking),
            "fuel_economy": ("Fuel economy", "Consumption and efficiency by operating period", .performance),
            "wallet_activity": ("Wallet activity", "Recent driver credits, debits and payouts", .financial),
            "fuel_stations": ("Fuel stops", "Nearby fuel options for the current route", .planning),
            "rest_areas": ("Rest areas", "Parking and rest options along the route", .planning),
            "hotZones": ("Freight hot zones", "Nearby demand and market activity", .planning),
            "revenue_summary": ("Fleet revenue", "Completed, in-transit and unsettled freight value", .financial),
            "carrier_alerts": ("Carrier attention", "Driver, equipment and load exceptions", .operations),
        ]
        let tuple = explicit[id]
        let name = tuple?.0 ?? humanize(id)
        let summary = tuple?.1 ?? "\(name) for this role"
        let category = tuple?.2 ?? .operations
        return def(id, name, summary, icon(for: id, category: category), category, [role])
    }

    private static func humanize(_ id: String) -> String {
        id.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "hos", with: "HOS", options: .caseInsensitive)
            .split(separator: " ")
            .map { word in
                let value = String(word)
                return value == value.uppercased() ? value : value.prefix(1).uppercased() + String(value.dropFirst())
            }
            .joined(separator: " ")
    }

    private static func icon(for id: String, category: HomeWidgetCategory) -> String {
        if id.localizedCaseInsensitiveContains("weather") || id.localizedCaseInsensitiveContains("marine") { return "cloud.sun.fill" }
        if id.localizedCaseInsensitiveContains("hos") || id.localizedCaseInsensitiveContains("deadline") { return "clock.fill" }
        if id.localizedCaseInsensitiveContains("revenue") || id.localizedCaseInsensitiveContains("invoice") || id.localizedCaseInsensitiveContains("rate") { return "dollarsign.circle.fill" }
        switch category {
        case .compliance, .safety: return "checkmark.shield.fill"
        case .tracking: return "location.fill"
        case .financial: return "chart.line.uptrend.xyaxis"
        case .communication: return "message.fill"
        case .management: return "person.3.fill"
        default: return "rectangle.grid.1x2.fill"
        }
    }
}

struct HomeWidgetSlot: Codable, Hashable, Identifiable {
    let widgetId: String
    var x: Int
    var y: Int
    var w: Int
    var h: Int
    var id: String { widgetId }

    var span: HomeWidgetSpan { HomeWidgetSpan.from(w: w, h: h) }
}

@MainActor
final class HomeWidgetLayoutStore: ObservableObject {
    enum SyncState: Equatable {
        case idle, loading, saving, synced(Date), saved(Date), failed(String), blocked(String)
    }

    @Published private(set) var layout: [HomeWidgetSlot] = []
    @Published private(set) var syncState: SyncState = .idle
    /// A device cache is display context, not layout authority. Editing stays
    /// locked until the authenticated server read has succeeded for this exact
    /// user + role. This prevents an offline launch from overwriting a newer
    /// cloud arrangement when connectivity returns.
    @Published private(set) var cloudAuthorityReady = false
    /// A saved server layout may contain a widget introduced by a newer app.
    /// Silently deleting it and saving the supported subset would destroy the
    /// user's layout. Keep the visible subset read-only until this client can
    /// render every saved slot.
    @Published private(set) var unavailableWidgetIDs: [String] = []

    let role: String
    let defaults: [String]
    let renderableIDs: Set<String>

    private var userID = ""
    private var configuredIdentity = ""
    private var revision = 0
    private var savedRevision = 0
    private var saveTask: Task<Void, Never>?
    private var loadFailed = false

    var canEdit: Bool {
        cloudAuthorityReady && unavailableWidgetIDs.isEmpty
    }

    init(role: String, defaults: [String], renderableIDs: Set<String>) {
        self.role = role
        self.defaults = Self.unique(defaults.filter(renderableIDs.contains))
        self.renderableIDs = renderableIDs
    }

    deinit { saveTask?.cancel() }

    func configure(userID: String) async {
        let identity = "\(userID)|\(role)"
        guard identity != configuredIdentity else { return }
        saveTask?.cancel()
        saveTask = nil
        revision = 0
        savedRevision = 0
        self.userID = userID
        configuredIdentity = identity
        syncState = .loading
        loadFailed = false
        cloudAuthorityReady = false
        unavailableWidgetIDs = []

        let cached = loadCache()
        if let cached { layout = sanitize(cached) }
        else { layout = slots(from: defaults) }
        cache()
        let requestIdentity = identity
        let requestRevision = revision

        struct Input: Encodable { let role: String }
        struct RemoteSlot: Decodable { let widgetId: String; let x: Int?; let y: Int?; let w: Int?; let h: Int? }
        struct Output: Decodable { let layout: [RemoteSlot]?; let updatedAt: String? }
        do {
            let output: Output = try await EusoTripAPI.shared.query(
                "users.getDashboardLayout", input: Input(role: role)
            )
            guard configuredIdentity == requestIdentity, !Task.isCancelled else { return }
            // A user edit made while the GET was in flight is newer than the
            // fetched snapshot. Its serialized save loop owns the next state.
            guard revision == requestRevision else { return }
            // nil = never customized. [] = explicitly removed everything.
            if let remote = output.layout {
                let remoteSlots = remote.map {
                    HomeWidgetSlot(widgetId: $0.widgetId, x: $0.x ?? 0, y: $0.y ?? 0, w: $0.w ?? 12, h: $0.h ?? 8)
                }
                let unsupported = Self.unique(
                    remoteSlots.map(\.widgetId).filter { !renderableIDs.contains($0) }
                )
                layout = sanitize(remoteSlots)
                if !unsupported.isEmpty {
                    unavailableWidgetIDs = unsupported
                    syncState = .blocked(
                        unsupported.count == 1
                            ? "Update EusoTrip to edit this layout; one saved widget is unavailable in this build."
                            : "Update EusoTrip to edit this layout; \(unsupported.count) saved widgets are unavailable in this build."
                    )
                    // Do not cache the sanitized subset. A later save from an
                    // older client must never erase newer widget identifiers.
                    return
                }
                cache()
            }
            cloudAuthorityReady = true
            syncState = .synced(Date())
        } catch {
            guard configuredIdentity == requestIdentity, !Task.isCancelled,
                  revision == requestRevision else { return }
            loadFailed = true
            cloudAuthorityReady = false
            syncState = .failed("Saved layout could not be verified. Widgets are read-only until cloud sync succeeds.")
        }
    }

    func add(_ id: String) {
        guard canEdit, renderableIDs.contains(id), !layout.contains(where: { $0.widgetId == id }) else { return }
        let span = HomeWidgetCatalog.definition(for: id, role: role).defaultSpan
        let grid = span.grid
        layout.append(HomeWidgetSlot(widgetId: id, x: 0, y: 0, w: grid.w, h: grid.h))
        changed()
    }

    func remove(_ id: String) {
        guard canEdit else { return }
        layout.removeAll { $0.widgetId == id }
        changed()
    }

    func move(_ id: String, before target: String) {
        guard canEdit, id != target, let from = layout.firstIndex(where: { $0.widgetId == id }),
              let to = layout.firstIndex(where: { $0.widgetId == target }) else { return }
        let destination = from < to ? to - 1 : to
        guard from != destination else { return }
        let slot = layout.remove(at: from)
        layout.insert(slot, at: min(destination, layout.count))
        changed()
    }

    func move(_ id: String, delta: Int) {
        guard canEdit, let from = layout.firstIndex(where: { $0.widgetId == id }) else { return }
        let to = min(max(0, from + delta), layout.count - 1)
        guard from != to else { return }
        let slot = layout.remove(at: from)
        layout.insert(slot, at: to)
        changed()
    }

    func resize(_ id: String, to span: HomeWidgetSpan) {
        guard canEdit, let index = layout.firstIndex(where: { $0.widgetId == id }) else { return }
        let grid = span.grid
        layout[index].w = grid.w
        layout[index].h = grid.h
        changed()
    }

    func reset() {
        guard canEdit else { return }
        layout = slots(from: defaults)
        changed()
    }

    func retry() {
        if loadFailed || !unavailableWidgetIDs.isEmpty || !cloudAuthorityReady {
            configuredIdentity = ""
            let currentUserID = userID
            Task { await configure(userID: currentUserID) }
            return
        }
        savedRevision = min(savedRevision, revision - 1)
        startSaveLoopIfNeeded(force: true)
    }

    func flush() {
        guard canEdit else { return }
        startSaveLoopIfNeeded(force: true)
    }

    private func changed() {
        guard canEdit else { return }
        revision += 1
        layout = repacked(layout)
        cache()
        startSaveLoopIfNeeded(force: false)
    }

    private func startSaveLoopIfNeeded(force: Bool) {
        guard canEdit, !userID.isEmpty else { return }
        if revision == 0 && force { revision = 1 }
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in await self?.saveLoop(skipDelay: force) }
    }

    private func saveLoop(skipDelay: Bool) async {
        var first = true
        while savedRevision < revision, !Task.isCancelled {
            guard canEdit else { break }
            if !(skipDelay && first) {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
            first = false
            guard !Task.isCancelled else { break }
            let targetRevision = revision
            let payload = repacked(layout)
            syncState = .saving

            struct Input: Encodable { let role: String; let layout: [HomeWidgetSlot] }
            struct Output: Decodable { let success: Bool?; let role: String?; let count: Int?; let updatedAt: String? }
            do {
                let output: Output = try await EusoTripAPI.shared.mutation(
                    "users.saveDashboardLayout", input: Input(role: role, layout: payload)
                )
                guard output.success != false else { throw LayoutSyncError.rejected }
                savedRevision = targetRevision
                syncState = .saved(Date())
            } catch {
                syncState = .failed("Could not save this layout. Your on-device copy is safe.")
                break
            }
        }
        saveTask = nil
    }

    private enum LayoutSyncError: Error { case rejected }
    private struct CacheEnvelope: Codable { let version: Int; let layout: [HomeWidgetSlot] }

    private var cacheKey: String { "euso.home.widgets.v3.\(userID).\(role)" }

    private func loadCache() -> [HomeWidgetSlot]? {
        guard !userID.isEmpty,
              let data = UserDefaults.standard.data(forKey: cacheKey),
              let envelope = try? JSONDecoder().decode(CacheEnvelope.self, from: data),
              envelope.version == 3 else { return nil }
        return envelope.layout
    }

    private func cache() {
        guard !userID.isEmpty,
              let data = try? JSONEncoder().encode(CacheEnvelope(version: 3, layout: repacked(layout))) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    private func slots(from ids: [String]) -> [HomeWidgetSlot] {
        repacked(ids.map { id in
            let grid = HomeWidgetCatalog.definition(for: id, role: role).defaultSpan.grid
            return HomeWidgetSlot(widgetId: id, x: 0, y: 0, w: grid.w, h: grid.h)
        })
    }

    private func sanitize(_ slots: [HomeWidgetSlot]) -> [HomeWidgetSlot] {
        var seen = Set<String>()
        let clean = slots.compactMap { slot -> HomeWidgetSlot? in
            guard renderableIDs.contains(slot.widgetId), seen.insert(slot.widgetId).inserted else { return nil }
            let span = HomeWidgetSpan.from(w: slot.w, h: slot.h)
            let grid = span.grid
            return HomeWidgetSlot(widgetId: slot.widgetId, x: 0, y: 0, w: grid.w, h: grid.h)
        }
        return repacked(clean)
    }

    private func repacked(_ slots: [HomeWidgetSlot]) -> [HomeWidgetSlot] {
        var result: [HomeWidgetSlot] = []
        var cursorX = 0
        var rowY = 0
        var rowHeight = 0
        for var slot in slots {
            let grid = HomeWidgetSpan.from(w: slot.w, h: slot.h).grid
            slot.w = grid.w
            slot.h = grid.h
            if grid.w == 12 {
                if cursorX > 0 { rowY += rowHeight; cursorX = 0; rowHeight = 0 }
                slot.x = 0
                slot.y = rowY
                rowY += grid.h
            } else {
                if cursorX + grid.w > 12 { rowY += rowHeight; cursorX = 0; rowHeight = 0 }
                slot.x = cursorX
                slot.y = rowY
                cursorX += grid.w
                rowHeight = max(rowHeight, grid.h)
                if cursorX == 12 { rowY += rowHeight; cursorX = 0; rowHeight = 0 }
            }
            result.append(slot)
        }
        return result
    }

    private static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }
}

struct HomeWidgetGrid: View {
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var session: EusoTripSession

    let role: String
    private let renderer: (String, HomeWidgetSpan) -> AnyView
    private let weatherRenderer: (() -> AnyView)?
    @StateObject private var store: HomeWidgetLayoutStore
    @State private var editing = false
    @State private var showLibrary = false
    @State private var hoverID: String?
    private static let nativeUniversalIDs: Set<String> = ["weather", "messages", "notifications", "news"]

    init(
        canonicalOrder: [String], role: String, storageKey _: String,
        weather: (() -> AnyView)? = nil,
        render: @escaping (String) -> AnyView
    ) {
        let defaults = Self.weatherFirst(canonicalOrder)
        self.role = role
        self.weatherRenderer = weather
        self.renderer = { id, _ in render(id) }
        _store = StateObject(wrappedValue: HomeWidgetLayoutStore(
            role: role, defaults: defaults, renderableIDs: Set(defaults).union(Self.nativeUniversalIDs)
        ))
    }

    init(
        canonicalOrder: [String], role: String, storageKey _: String,
        weather: (() -> AnyView)? = nil,
        renderWithSpan: @escaping (String, HomeWidgetSpan) -> AnyView
    ) {
        let defaults = Self.weatherFirst(canonicalOrder)
        self.role = role
        self.weatherRenderer = weather
        self.renderer = renderWithSpan
        _store = StateObject(wrappedValue: HomeWidgetLayoutStore(
            role: role, defaults: defaults, renderableIDs: Set(defaults).union(Self.nativeUniversalIDs)
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            toolbar
            syncBanner
            if store.layout.isEmpty {
                emptyState
            } else {
                ForEach(Array(packedRows.enumerated()), id: \.offset) { _, row in
                    if row.count == 2 {
                        HStack(alignment: .top, spacing: Space.s3) {
                            slotView(row[0]).frame(maxWidth: .infinity, alignment: .topLeading)
                            slotView(row[1]).frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else if let slot = row.first {
                        if slot.span == .half, !singleColumn {
                            HStack(alignment: .top, spacing: Space.s3) {
                                slotView(slot).frame(maxWidth: .infinity, alignment: .topLeading)
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        } else {
                            slotView(slot).frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                }
            }
        }
        .task(id: identity) { await store.configure(userID: session.user?.id ?? "signed-out") }
        .onChange(of: store.canEdit) { _, canEdit in
            if !canEdit {
                editing = false
                showLibrary = false
            }
        }
        .sheet(isPresented: $showLibrary) { library }
    }

    private var identity: String { "\(session.user?.id ?? "signed-out")|\(role)" }
    private var singleColumn: Bool { dynamicTypeSize.isAccessibilitySize }

    private var packedRows: [[HomeWidgetSlot]] {
        guard !singleColumn else { return store.layout.map { [$0] } }
        var rows: [[HomeWidgetSlot]] = []
        var index = 0
        while index < store.layout.count {
            let slot = store.layout[index]
            if slot.span == .half, index + 1 < store.layout.count, store.layout[index + 1].span == .half {
                rows.append([slot, store.layout[index + 1]])
                index += 2
            } else {
                rows.append([slot])
                index += 1
            }
        }
        return rows
    }

    private var toolbar: some View {
        HStack(spacing: Space.s2) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { editing.toggle() }
                if !editing { store.flush() }
            } label: {
                Label(editing ? "Done" : "Customize widgets", systemImage: editing ? "checkmark.circle.fill" : "rectangle.3.group")
                    .font(EType.caption.weight(.semibold))
                    .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                    .frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(editing ? Brand.blue : palette.borderFaint))
            }
            .buttonStyle(.plain)
            .disabled(!store.canEdit)
            .accessibilityHint(editing ? "Ends editing and saves the layout" : "Shows move, resize, remove, and add controls")

            if editing {
                Button { showLibrary = true } label: { Image(systemName: "plus").frame(width: 44, height: 44).background(palette.bgCard, in: RoundedRectangle(cornerRadius: Radius.md)).overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint)) }
                    .buttonStyle(.plain).accessibilityLabel("Add widget")
                Button { withAnimation(.easeOut(duration: 0.18)) { store.reset() } } label: { Text("Reset").font(EType.caption.weight(.semibold)).frame(minWidth: 44, minHeight: 44) }
                    .buttonStyle(.plain).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var syncBanner: some View {
        Group {
            switch store.syncState {
            case .loading:
                Label("Loading saved layout…", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(palette.textTertiary)
            case .saving:
                Label("Saving layout…", systemImage: "icloud.and.arrow.up").foregroundStyle(palette.textSecondary)
            case .synced(let date):
                Label("Cloud layout checked · \(date.formatted(date: .omitted, time: .shortened))", systemImage: "icloud")
                    .foregroundStyle(palette.textSecondary)
            case .saved(let date):
                Label("Saved to EusoTrip · \(date.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.icloud.fill")
                    .foregroundStyle(Brand.success)
            case .failed(let message):
                HStack { Label(message, systemImage: "exclamationmark.icloud"); Spacer(); Button("Retry") { store.retry() }.fontWeight(.bold).frame(minWidth: 44, minHeight: 44) }
                    .foregroundStyle(Brand.warning)
            case .blocked(let message):
                HStack { Label(message, systemImage: "exclamationmark.arrow.triangle.2.circlepath"); Spacer(); Button("Check again") { store.retry() }.fontWeight(.bold).frame(minWidth: 44, minHeight: 44) }
                    .foregroundStyle(Brand.warning)
            case .idle:
                EmptyView()
            }
        }
        .font(EType.caption)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Label("Your Home is clear", systemImage: "rectangle.grid.1x2")
                .font(EType.body.weight(.semibold)).foregroundStyle(palette.textPrimary)
            Text("Add weather, shared tools, or role widgets whenever you need them.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
            Button("Open widget library") { showLibrary = true }
                .font(EType.caption.weight(.bold))
                .frame(minHeight: 44)
                .disabled(!store.canEdit)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).eusoCard()
    }

    private func slotView(_ slot: HomeWidgetSlot) -> some View {
        let definition = HomeWidgetCatalog.definition(for: slot.widgetId, role: role)
        let content = Group {
            switch slot.widgetId {
            case "weather": weatherRenderer?() ?? AnyView(HomeWeatherWidget())
            case "messages": AnyView(MessagesWidget())
            case "notifications": AnyView(NotificationsWidget())
            case "news": AnyView(NewsCarouselWidget())
            default: renderer(slot.widgetId, slot.span)
            }
        }
        .environment(\.homeWidgetSpan, slot.span)
        .frame(maxWidth: .infinity, alignment: .topLeading)

        return content
            .overlay(alignment: .topTrailing) {
                if editing {
                    HStack(spacing: 5) {
                        Menu {
                            ForEach(HomeWidgetSpan.allCases, id: \.self) { span in
                                Button { withAnimation { store.resize(slot.widgetId, to: span) } } label: { Label(span.menuLabel, systemImage: span.menuIcon) }
                            }
                        } label: {
                            Label(slot.span.menuLabel, systemImage: slot.span.menuIcon).labelStyle(.iconOnly)
                                .frame(width: 44, height: 44)
                                .background(palette.bgCard, in: RoundedRectangle(cornerRadius: Radius.md))
                                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
                        }
                        Button { withAnimation { store.remove(slot.widgetId) } } label: {
                            Image(systemName: "minus.circle.fill").font(.system(size: 22)).symbolRenderingMode(.multicolor)
                                .frame(width: 44, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel("Remove \(definition.name)")
                    }.padding(6)
                }
            }
            .overlay {
                if editing {
                    RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(
                        hoverID == slot.widgetId ? AnyShapeStyle(Brand.blue) : AnyShapeStyle(palette.borderFaint),
                        lineWidth: hoverID == slot.widgetId ? 2 : 1
                    )
                }
            }
            .draggable(slot.widgetId) { Text(definition.name).padding(8).background(palette.bgCard, in: Capsule()) }
            .dropDestination(for: String.self) { values, _ in
                guard editing, let id = values.first else { return false }
                withAnimation { store.move(id, before: slot.widgetId) }
                return true
            } isTargeted: { hoverID = $0 ? slot.widgetId : nil }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(definition.name) widget, \(slot.span.menuLabel)")
            .accessibilityAction(named: "Move up") { store.move(slot.widgetId, delta: -1) }
            .accessibilityAction(named: "Move down") { store.move(slot.widgetId, delta: 1) }
            .accessibilityAction(named: "Remove") { store.remove(slot.widgetId) }
            .accessibilityAdjustableAction { direction in store.resize(slot.widgetId, to: slot.span.stepped(direction)) }
    }

    private var library: some View {
        NavigationStack {
            List {
                let universal = available.filter { HomeWidgetCatalog.universal.map(\.id).contains($0.id) }
                let roleSpecific = available.filter { !HomeWidgetCatalog.universal.map(\.id).contains($0.id) }
                if !universal.isEmpty { Section("Shared widgets") { ForEach(universal) { libraryRow($0) } } }
                if !roleSpecific.isEmpty { Section("For \(roleDisplayName)") { ForEach(roleSpecific) { libraryRow($0) } } }
                if available.isEmpty {
                    ContentUnavailableView("All widgets added", systemImage: "checkmark.circle.fill", description: Text("Remove a widget to make it available here again."))
                }
            }
            .navigationTitle("Widget Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showLibrary = false } } }
        }
        .presentationDetents([.medium, .large])
        .environment(\.palette, palette)
    }

    private var available: [HomeWidgetDef] {
        store.renderableIDs.subtracting(Set(store.layout.map(\.widgetId)))
            .map { HomeWidgetCatalog.definition(for: $0, role: role) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func libraryRow(_ definition: HomeWidgetDef) -> some View {
        Button {
            withAnimation { store.add(definition.id) }
            if available.count <= 1 { showLibrary = false }
        } label: {
            HStack(spacing: Space.s3) {
                Image(systemName: definition.icon).foregroundStyle(palette.textSecondary).frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(definition.name).font(EType.body.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text(definition.summary).font(EType.micro).foregroundStyle(palette.textSecondary)
                }
                Spacer(); Image(systemName: "plus.circle.fill").foregroundStyle(Brand.blue)
            }
        }.buttonStyle(.plain).disabled(!store.canEdit)
    }

    private var roleDisplayName: String {
        role.replacingOccurrences(of: "_", with: " ").lowercased().capitalized
    }

    private static func weatherFirst(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return (["weather"] + ids.filter { $0 != "weather" }).filter { seen.insert($0).inserted }
    }
}
