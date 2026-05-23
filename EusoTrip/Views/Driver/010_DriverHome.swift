//
//  010_DriverHome.swift
//  EusoTrip — LIVE production screen (A→Z, screen 010)
//
//  Pulls real data from the EusoTrip tRPC backend via EusoTripAPI:
//    • loads.search(status: "assigned", limit: 1)
//    • hos.getStatus()
//    • loads.getById(<id>)   (hydrates pickup/delivery detail)
//
//  Preserves doctrine:
//    §2 nav + orb invariants, §3 numbers-first copy, §4.3 iridescent hairline,
//    §7 breathe density, §8 Driver rhythm (ActiveCard + 2 metrics + list),
//    §12 DONE criteria.
//
//  Twin of:  02_html/dark/010_driver_home.html
//            02_html/light/010_driver_home.html
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Home Widget Catalog (mirrors web `client/src/lib/widgetLibrary.ts`)
//
// Single iOS-side source of truth for the home-widget customization
// surface. Widget IDs are kept identical to the web catalog so a
// layout saved via `users.saveDashboardLayout` on iOS hydrates
// correctly on web and vice versa.
//
// iosRenderable=true means an iOS tile-view exists for this widget
// id and the home screen's render closure will map to it. false
// means it shows in the catalog (gated by role) but iOS has no tile
// view yet — the picker can still surface it as "Coming on iOS"
// when we wire the per-role widget picker in a follow-up.

/// Mirrors web's `WidgetCategory`.
enum HomeWidgetCategory: String, Codable, CaseIterable {
    case analytics, operations, financial, communication
    case productivity, safety, compliance, performance
    case planning, tracking, reporting, management
}

/// Mirrors web's `WidgetDefinition`. `id` is the cross-platform key.
struct HomeWidgetDef: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let icon: String                    // SF Symbol
    let category: HomeWidgetCategory
    let roles: Set<String>              // role enum strings — RBAC
    let defaultSize: (w: Int, h: Int)   // matches web grid (12-col)
    let iosRenderable: Bool

    /// Equatable + Hashable manual (defaultSize tuple isn't auto-hashable).
    static func == (lhs: HomeWidgetDef, rhs: HomeWidgetDef) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Static catalog of all known iOS home widgets — UNIVERSAL + every
/// active iOS role's slate. Web's full 379-widget catalog is the
/// long-term ceiling; iOS catalog grows as tile-views ship.
enum HomeWidgetCatalog {

    /// Universal widgets — available to every role. Mirrors web's
    /// `UNIVERSAL_WIDGETS` (client/src/lib/widgetLibrary.ts:57).
    static let universal: [HomeWidgetDef] = [
        .init(id: "weather",            name: "Weather",            summary: "Live weather with 5-day forecast",     icon: "sun.max.fill",            category: .productivity,   roles: allRoles, defaultSize: (6, 6), iosRenderable: true),
        .init(id: "calendar",           name: "Calendar",           summary: "Schedule and appointments",            icon: "calendar",                category: .productivity,   roles: allRoles, defaultSize: (12, 8), iosRenderable: false),
        .init(id: "notes",              name: "Quick Notes",        summary: "Sticky notes and reminders",           icon: "note.text",               category: .productivity,   roles: allRoles, defaultSize: (6, 6), iosRenderable: false),
        .init(id: "tasks",              name: "Tasks",              summary: "Personal to-dos",                      icon: "checklist",               category: .productivity,   roles: allRoles, defaultSize: (6, 6), iosRenderable: false),
        .init(id: "notifications",      name: "Notifications",      summary: "Recent platform alerts",               icon: "bell.fill",               category: .communication,  roles: allRoles, defaultSize: (12, 6), iosRenderable: true),
        .init(id: "messages",           name: "Messages",           summary: "Unread + active threads",              icon: "message.fill",            category: .communication,  roles: allRoles, defaultSize: (12, 6), iosRenderable: true),
        .init(id: "quick_actions",      name: "Quick Actions",      summary: "Role-aware shortcuts",                 icon: "bolt.fill",               category: .productivity,   roles: allRoles, defaultSize: (12, 4), iosRenderable: false),
        .init(id: "search",             name: "Search",             summary: "Loads / docs / contacts",              icon: "magnifyingglass",         category: .productivity,   roles: allRoles, defaultSize: (12, 4), iosRenderable: false),
        .init(id: "recent_activity",    name: "Recent activity",    summary: "Latest movements + events",            icon: "list.bullet.rectangle",   category: .reporting,      roles: allRoles, defaultSize: (12, 8), iosRenderable: true),
        .init(id: "performance_summary", name: "Performance",       summary: "Score / rank / trend",                 icon: "chart.line.uptrend.xyaxis", category: .performance, roles: allRoles, defaultSize: (8, 6), iosRenderable: false),
        .init(id: "live_map",           name: "Live map",           summary: "Fleet / assets / loads on map",        icon: "map.fill",                category: .tracking,       roles: allRoles, defaultSize: (12, 10), iosRenderable: false),
        .init(id: "news",               name: "Intel feed",         summary: "Role-prioritized rotating headlines",  icon: "newspaper.fill",          category: .reporting,      roles: allRoles, defaultSize: (12, 6), iosRenderable: true),
        .init(id: "spectra_match",      name: "Spectra match",      summary: "Cross-role lane/carrier match score",  icon: "sparkles",                category: .analytics,      roles: allRoles, defaultSize: (12, 6), iosRenderable: false),
    ]

    /// Driver-specific widgets (mirrors web DRIVER_WIDGETS:240). iOS
    /// tile views ship incrementally — current renderables are the
    /// 5 originally wired in 010_DriverHome.
    static let driver: [HomeWidgetDef] = [
        .init(id: "current_route",      name: "Current route",      summary: "Active route navigation",              icon: "location.north.line.fill", category: .operations,    roles: ["DRIVER"], defaultSize: (12, 10), iosRenderable: true),
        .init(id: "hos_tracker",        name: "HOS tracker",        summary: "Hours of service compliance",          icon: "clock.fill",              category: .compliance,     roles: ["DRIVER"], defaultSize: (12, 6),  iosRenderable: true),
        .init(id: "earnings_summary",   name: "Earnings",           summary: "Pay and bonuses",                      icon: "dollarsign.circle.fill",  category: .financial,      roles: ["DRIVER"], defaultSize: (10, 6),  iosRenderable: true),
        .init(id: "next_delivery",      name: "Next delivery",      summary: "Upcoming delivery details",            icon: "mappin.circle.fill",      category: .operations,     roles: ["DRIVER"], defaultSize: (12, 6),  iosRenderable: true),
        .init(id: "fuel_stations",      name: "Fuel stations",      summary: "Nearby fuel stops",                    icon: "fuelpump.fill",           category: .planning,       roles: ["DRIVER"], defaultSize: (10, 6),  iosRenderable: false),
        .init(id: "rest_areas",         name: "Rest areas",         summary: "Nearby rest stops",                    icon: "bed.double.fill",         category: .planning,       roles: ["DRIVER"], defaultSize: (10, 6),  iosRenderable: false),
        .init(id: "vehicle_health",     name: "Vehicle health",     summary: "Truck diagnostics",                    icon: "wrench.and.screwdriver.fill", category: .operations,  roles: ["DRIVER"], defaultSize: (10, 6),  iosRenderable: true),
        .init(id: "weather_alerts",     name: "Weather alerts",     summary: "Route weather conditions",             icon: "cloud.rain.fill",         category: .safety,         roles: ["DRIVER"], defaultSize: (10, 6),  iosRenderable: true),
        .init(id: "haul",               name: "The Haul weekly",    summary: "XP ring + missions + rank",            icon: "rosette",                 category: .performance,    roles: ["DRIVER"], defaultSize: (12, 6),  iosRenderable: true),
        .init(id: "compliance",         name: "Compliance countdown", summary: "CDL / medical / hazmat / TWIC expiry", icon: "checkmark.shield.fill", category: .compliance,    roles: ["DRIVER"], defaultSize: (12, 4),  iosRenderable: true),
        .init(id: "hotZones",           name: "Hot zones",          summary: "Live load-to-truck ratios + surges",   icon: "flame.fill",              category: .analytics,      roles: ["DRIVER"], defaultSize: (12, 8),  iosRenderable: true),
        .init(id: "performance_score",  name: "Performance score",  summary: "Safety · on-time rate · fleet rank",   icon: "chart.line.uptrend.xyaxis", category: .performance,  roles: ["DRIVER"], defaultSize: (10, 6),  iosRenderable: true),
        .init(id: "mileage_tracker",    name: "Mileage tracker",    summary: "Monthly miles + current load distance", icon: "road.lanes",                 category: .analytics,    roles: ["DRIVER"], defaultSize: (10, 6),  iosRenderable: true),
    ]

    /// Shipper-specific widgets.
    static let shipper: [HomeWidgetDef] = [
        .init(id: "activeLoads",        name: "Active loads",       summary: "Live load board",                      icon: "shippingbox.fill",        category: .operations,     roles: ["SHIPPER"], defaultSize: (12, 8), iosRenderable: true),
        .init(id: "esang",              name: "ESANG strip",        summary: "AI live signals",                      icon: "sparkles",                category: .analytics,      roles: ["SHIPPER"], defaultSize: (12, 6), iosRenderable: true),
    ]

    /// Catalyst-specific widgets.
    static let catalyst: [HomeWidgetDef] = [
        .init(id: "activeMatches",      name: "Active matches",     summary: "Match board + bid landscape",          icon: "person.line.dotted.person.fill", category: .operations, roles: ["CATALYST"], defaultSize: (12, 8), iosRenderable: true),
    ]

    /// Broker-specific widgets.
    static let broker: [HomeWidgetDef] = [
        .init(id: "openTenders",        name: "Open tenders",       summary: "Pending tender pile",                  icon: "tray.full.fill",          category: .operations,     roles: ["BROKER"], defaultSize: (12, 8), iosRenderable: true),
    ]

    /// Dispatch-specific widgets.
    static let dispatch: [HomeWidgetDef] = [
        .init(id: "priority",           name: "Priority queue",     summary: "Top exception driving the day",        icon: "exclamationmark.triangle.fill", category: .operations, roles: ["DISPATCH"], defaultSize: (12, 6), iosRenderable: true),
        .init(id: "hosWatch",           name: "HOS watchlist",      summary: "Drivers approaching HOS limits",       icon: "clock.badge.exclamationmark.fill", category: .compliance, roles: ["DISPATCH"], defaultSize: (12, 6), iosRenderable: true),
    ]

    /// Carrier-specific widgets (CATALYST + DISPATCH role overlap on web).
    static let carrier: [HomeWidgetDef] = [
        .init(id: "carrierActiveLoads", name: "Active loads",       summary: "Loads under this carrier",             icon: "shippingbox.fill",        category: .operations,     roles: ["CATALYST", "DISPATCH"], defaultSize: (12, 8), iosRenderable: true),
    ]

    /// Terminal-specific widgets.
    static let terminal: [HomeWidgetDef] = [
        .init(id: "activeMovements",    name: "Active movements",   summary: "Yard arrivals / departures live",      icon: "arrow.triangle.swap",     category: .operations,     roles: ["TERMINAL_MANAGER"], defaultSize: (12, 8), iosRenderable: true),
    ]

    /// Escort-specific widgets.
    static let escort: [HomeWidgetDef] = [
        .init(id: "activeAssignments",  name: "Active assignments", summary: "Live escort jobs",                     icon: "car.2.fill",              category: .operations,     roles: ["ESCORT"], defaultSize: (12, 8), iosRenderable: true),
    ]

    /// Admin-specific widgets.
    static let admin: [HomeWidgetDef] = [
        .init(id: "openTickets",        name: "Open tickets",       summary: "Support queue + status",               icon: "ticket.fill",             category: .management,     roles: ["ADMIN", "SUPER_ADMIN"], defaultSize: (12, 8), iosRenderable: true),
    ]

    /// Compliance-specific widgets.
    static let compliance: [HomeWidgetDef] = [
        .init(id: "expiringDocs",       name: "Expiring docs",      summary: "60-day rolling expiry watch",          icon: "doc.badge.clock.fill",    category: .compliance,     roles: ["COMPLIANCE_OFFICER"], defaultSize: (12, 6), iosRenderable: true),
    ]

    /// All widgets across every role bucket.
    static let all: [String: HomeWidgetDef] = {
        var dict: [String: HomeWidgetDef] = [:]
        for set in [universal, driver, shipper, catalyst, broker, dispatch, carrier, terminal, escort, admin, compliance] {
            for w in set { dict[w.id] = w }
        }
        return dict
    }()

    /// Widgets a given role is allowed to surface (RBAC).
    static func allowed(for role: String) -> [HomeWidgetDef] {
        all.values.filter { $0.roles.contains(role) }.sorted { $0.name < $1.name }
    }

    /// Widgets a given role is allowed to surface AND have an iOS
    /// tile-view shipped for. The picker shows allowed-but-not-yet-
    /// renderable as a "Coming on iOS" stub in a follow-up.
    static func renderable(for role: String) -> [HomeWidgetDef] {
        allowed(for: role).filter { $0.iosRenderable }
    }

    /// All 24 canonical role strings (web extended role set). Used by
    /// the universal-widget RBAC.
    static let allRoles: Set<String> = [
        "SHIPPER","CATALYST","BROKER","DRIVER","DISPATCH","ESCORT",
        "TERMINAL_MANAGER","COMPLIANCE_OFFICER","SAFETY_MANAGER","FACTORING",
        "ADMIN","SUPER_ADMIN",
        "RAIL_SHIPPER","RAIL_CATALYST","RAIL_DISPATCHER","RAIL_ENGINEER","RAIL_CONDUCTOR","RAIL_BROKER",
        "VESSEL_SHIPPER","VESSEL_OPERATOR","PORT_MASTER","SHIP_CAPTAIN","VESSEL_BROKER","CUSTOMS_BROKER",
    ]
}

// MARK: - Shared HomeWidgetGrid (DnD reorder, edit toggle, save/load)
//
// Single canonical component for every role home's reorderable
// secondary widget zone. Consumers pass their canonical ordered
// widget id list + a render closure mapping id → tile view. The
// grid owns: edit-mode toggle, drag/drop reorder, hover-stroke
// feedback, RESET button, hydrate from `users.getDashboardLayout`
// + UserDefaults cache, persist on edit exit, slot-set reconciliation.
//
// Replaces the per-home enum + toolbar + secondaryWidget(for:) +
// hydrate/persist/reconcile duplication that originally shipped in
// the 10 home screens. Migrations land file-by-file; the original
// per-home helpers stay alive until each home is moved over.

struct HomeWidgetGrid: View {
    @Environment(\.palette) private var palette

    /// Canonical default order for this role's home — used when no
    /// saved layout exists and as the universe-of-slots reference
    /// for `reconcile()` (so widgets shipped after a layout save
    /// still appear).
    let canonicalOrder: [String]
    /// Role string for the save/load endpoint (`users.saveDashboardLayout`).
    let role: String
    /// Per-user storage key (UserDefaults cache mirror).
    let storageKey: String
    /// Render closure: widget id → tile view. Returns EmptyView when
    /// the host doesn't recognize the id (e.g. a stale saved layout
    /// references a widget that's since been removed). The grid skips
    /// rendering when EmptyView is returned.
    let render: (String) -> AnyView

    @State private var order: [String] = []
    @State private var editing: Bool = false
    @State private var hoverSlot: String? = nil
    @State private var hydrated: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toolbar
            ForEach(order, id: \.self) { slotId in
                slotView(slotId)
            }
        }
        .task {
            guard !hydrated else { return }
            hydrated = true
            order = canonicalOrder
            await hydrate()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: editing ? "checkmark.circle.fill" : "rectangle.3.group.bubble")
                .font(.system(size: 11, weight: .heavy))
            Text(editing ? "DONE · Tap to save layout" : "CUSTOMIZE WIDGETS")
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
            Spacer(minLength: 0)
            if editing {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { order = canonicalOrder }
                } label: {
                    Text("RESET")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(palette.bgCard, in: Capsule())
                }.buttonStyle(.plain)
            }
        }
        .foregroundStyle(editing ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            Capsule().strokeBorder(
                editing ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint),
                lineWidth: 1
            )
        )
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.18)) {
                if editing { editing = false; Task { await persist() } }
                else { editing = true }
            }
        }
    }

    @ViewBuilder
    private func slotView(_ id: String) -> some View {
        let inner = render(id)
        if editing {
            let isHover = hoverSlot == id
            let label = HomeWidgetCatalog.all[id]?.name ?? id
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .padding(.top, 10)
                inner
            }
            .overlay(alignment: .topTrailing) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
                    .padding(6)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isHover ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint),
                        lineWidth: isHover ? 2 : 1
                    )
                    .animation(.easeOut(duration: 0.12), value: hoverSlot)
            )
            .draggable(id) {
                Text(label)
                    .font(.system(size: 13, weight: .heavy))
                    .padding(10)
                    .background(palette.surface, in: Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
            }
            .dropDestination(for: String.self) { droppedIds, _ in
                guard let dropped = droppedIds.first,
                      dropped != id,
                      let fromIdx = order.firstIndex(of: dropped),
                      let toIdx = order.firstIndex(of: id)
                else { return false }
                withAnimation(.easeOut(duration: 0.18)) {
                    let item = order.remove(at: fromIdx)
                    order.insert(item, at: min(toIdx, order.count))
                }
                return true
            } isTargeted: { hovering in
                hoverSlot = hovering ? id : (hoverSlot == id ? nil : hoverSlot)
            }
        } else {
            inner
        }
    }

    private func hydrate() async {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let cached = try? JSONDecoder().decode([String].self, from: data),
           !cached.isEmpty {
            order = reconcile(cached)
        }
        struct In: Encodable { let role: String }
        struct Slot: Decodable { let widgetId: String }
        struct Out: Decodable { let layout: [Slot]?; let updatedAt: String? }
        do {
            let r: Out = try await EusoTripAPI.shared.query("users.getDashboardLayout", input: In(role: role))
            if let server = r.layout, !server.isEmpty {
                let parsed = server.map { $0.widgetId }
                let merged = reconcile(parsed)
                await MainActor.run { order = merged }
                if let data = try? JSONEncoder().encode(merged) {
                    UserDefaults.standard.set(data, forKey: storageKey)
                }
            }
        } catch { /* offline / unauth — local cache or canonical default holds */ }
    }

    private func persist() async {
        if let data = try? JSONEncoder().encode(order) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        struct Slot: Encodable { let widgetId: String; let x: Int; let y: Int; let w: Int; let h: Int }
        struct In: Encodable { let role: String; let layout: [Slot] }
        struct Out: Decodable { let success: Bool? }
        let payload = order.enumerated().map { idx, id -> Slot in
            let def = HomeWidgetCatalog.all[id]
            return Slot(widgetId: id, x: 0, y: idx, w: def?.defaultSize.w ?? 12, h: def?.defaultSize.h ?? 4)
        }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "users.saveDashboardLayout",
                input: In(role: role, layout: payload)
            )
        } catch { /* server unreachable — local cache holds */ }
    }

    private func reconcile(_ saved: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for s in saved where !seen.contains(s) && canonicalOrder.contains(s) {
            out.append(s); seen.insert(s)
        }
        for s in canonicalOrder where !seen.contains(s) {
            out.append(s)
        }
        return out
    }
}

// MARK: - Screen

struct DriverHome: View {
    @Environment(\.palette) var palette
    @EnvironmentObject private var profile: DriverProfileStore
    @StateObject private var vm = DriverHomeViewModel()
    @State private var showMessages: Bool = false
    /// True when the driver has tapped the active-load card's "Details"
    /// button. Presents `LoadDetailSheet` over the Home surface with the
    /// same rich load/route/broker detail as the Eusoboards flow. Wired
    /// per user direction (2026-04-20):
    ///
    ///   > same thing for this screen when you click on details
    @State private var showAssignedLoadDetail: Bool = false
    /// Presents the full HOS Duty Status surface (019_HosDutyStatus) over
    /// Home when the driver taps the HOS DRIVE LEFT metric tile. Wired per
    /// user direction (2026-04-20):
    ///
    ///   > clicking on hos should take you to your hos port screen with
    ///   > HOS data and meters per the figma
    @State private var showHosSheet: Bool = false
    /// Presents the full EusoWallet (DriverWalletPane) surface over Home
    /// when the driver taps the WALLET AVAILABLE metric tile. Wired per
    /// user direction (2026-04-20):
    ///
    ///   > clicking on wallet available should take you to eusowallet
    @State private var showWalletSheet: Bool = false
    /// Selected `AvailableLoad` from the home carousel of suggested
    /// freight shown when the driver is between loads. Drives
    /// `LoadDetailSheet` so tapping a card surfaces the same rich detail
    /// (route · permits · rate breakdown · broker) the Eusoboards
    /// surface renders. Wired per user direction (2026-04-21):
    ///
    ///   > that module should be a carousel of available loads and
    ///   > when you press it it takes you to the load details when you
    ///   > arent in an active load.
    @State private var selectedSuggestedLoad: AvailableLoad? = nil
    /// Presents the notifications inbox sheet over Home when the
    /// `NotificationsWidget` tile is tapped (or any other surface posts
    /// `.eusoOpenNotificationsRequested`). Wraps the existing
    /// `MeNotificationsView` body so the inbox surface stays in sync
    /// with what the Me sub-route renders.
    @State private var showNotificationsSheet: Bool = false

    // ── Home-widget customization (2026-05-23 founder ask) ──────
    // Migrated to shared HomeWidgetGrid + HomeWidgetCatalog
    // (defined at file scope above). This struct just declares the
    // canonical slot order + the render mapping for this role's
    // tiles. The grid handles edit mode, drag/drop, RESET, hydrate
    // / persist via users.saveDashboardLayout("DRIVER", …),
    // reconciliation, and the UserDefaults offline cache.
    private let widgetLayoutKey = "driver.home.widgetOrder"
    private let driverHomeCanonicalOrder: [String] = [
        "current_route", "next_delivery", "hos_tracker", "earnings_summary", "weather_alerts",
        "messages", "notifications", "haul", "compliance", "news", "recent", "hotZones",
        "performance_score", "vehicle_health", "mileage_tracker",
    ]

    /// Maps a catalog widget id → the concrete iOS tile view this
    /// driver-home wires today. Future widget ports just add a case;
    /// the grid + catalog handle the rest.
    @ViewBuilder
    private func driverHomeRender(_ id: String) -> AnyView {
        switch id {
        case "current_route":   AnyView(CurrentRouteWidget(load: vm.activeLoad))
        case "next_delivery":   AnyView(NextDeliveryWidget(summary: vm.activeLoadSummary))
        case "hos_tracker":     AnyView(HosTrackerWidget())
        case "earnings_summary":AnyView(EarningsSummaryWidget(available: vm.walletAvailable, availableDisplay: vm.walletAvailableDisplay))
        case "weather_alerts":  AnyView(WeatherAlertsWidget(snapshot: vm.weather))
        case "messages":        AnyView(MessagesWidget())
        case "notifications":   AnyView(NotificationsWidget())
        case "haul":            AnyView(TheHaulWeeklyTile())
        case "compliance":      AnyView(ComplianceCountdownStrip())
        case "news":            AnyView(NewsCarouselWidget())
        case "recent":          AnyView(recentSection)
        case "hotZones":        AnyView(HotZonesWidget())
        case "performance_score": AnyView(PerformanceScoreWidget())
        case "vehicle_health":  AnyView(VehicleHealthWidget())
        case "mileage_tracker": AnyView(MileageTrackerWidget(currentLoadMiles: vm.activeLoad?.distanceValue))
        default:                AnyView(EmptyView())
        }
    }

    /// Live suggestions feed — `loads.search(status:"available")` via
    /// `LoadBoardStore`. Every seeded `[AvailableLoad]` literal that
    /// used to live here (PACCO, ColdChain, Sunbelt, Heartland, etc.)
    /// is gone — the store calls the real tRPC procedure and projects
    /// `[LoadSummary]` onto the existing `AvailableLoad` shape via
    /// `AvailableLoad.from(_:)` in the adapters file.
    @StateObject private var suggestedLoadsStore = LoadBoardStore()
    private var suggestedLoads: [AvailableLoad] {
        suggestedLoadsStore.items.map(AvailableLoad.from)
    }

    /// Greeting name — reads from the shared `DriverProfileStore` so the
    /// moment a driver saves a new first name in ProfileEditView the Home
    /// banner picks it up without a reload. Falls back to the VM's stored
    /// name (which is itself seeded from the auth payload) only while the
    /// profile store is still hydrating from UserDefaults on cold launch.
    private var greetingFirstName: String {
        let name = profile.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? vm.driverFirstName : name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
            // Home content wrapped in a ScrollView so `.refreshable`
            // binds to a live drag-down gesture. On shorter devices the
            // metric row + recent section also needs to scroll — the
            // previous flat VStack clipped everything below the fold.
            ScrollView {
                // TileStack wraps Home's hero sections so each one fades
                // and lifts into place in source order (weather → active
                // card → metric row → recent section) — matches the web
                // platform's tile load-in on /driver/home.
                TileStack(alignment: .leading, spacing: Space.s5) {
                    switch vm.phase {
                    case .idle, .loading:
                        loadingState
                    case .loaded:
                        if vm.isOffline { offlineBanner }
                        // ESANG Morning Brief — top coaching card from
                        // the driver's role+vertical+hazmat-aware feed.
                        eSangMorningBriefCard()
                        // 75th firing (2026-04-24, hygiene + fallback C):
                        // render live WeatherCard ONLY when WeatherKit
                        // resolved a real snapshot for the driver's real
                        // coordinate. When location is denied/restricted
                        // we render a neutral gradient CTA to open
                        // Settings — no fabricated tempF/windMph/visibility.
                        // When WeatherKit is authorized but momentarily
                        // unavailable, we silently omit the card rather
                        // than flash an error — matches the §13 "neutral
                        // empty state on the client, no fake data" rule.
                        if let w = vm.weather {
                            WeatherCard(snapshot: w)
                        } else if vm.weatherAvailability == .needsLocation {
                            enableLocationCard
                        }
                        // Pre-trip DVIR status — 49 CFR 396.11. Only
                        // surfaces when the driver actually has an
                        // upcoming / active load assigned, since a
                        // pre-trip outside of that window isn't
                        // actionable from the Home glance. Silent
                        // otherwise (returns EmptyView from body).
                        if vm.activeLoadSummary != nil || vm.activeLoad != nil {
                            PreTripDVIRStatusPill()
                        }
                        if vm.activeLoadSummary != nil || vm.activeLoad != nil {
                            activeLoadCard
                        } else {
                            noActiveLoadCard
                        }
                        metricRow
                        // Reorderable secondary-widget zone via the
                        // shared HomeWidgetGrid. Canonical order +
                        // RBAC + persistence all flow through the
                        // single component; the render closure maps
                        // catalog widget IDs to the concrete iOS
                        // tile views this screen wires.
                        HomeWidgetGrid(
                            canonicalOrder: driverHomeCanonicalOrder,
                            role: "DRIVER",
                            storageKey: widgetLayoutKey,
                            render: { id in driverHomeRender(id) }
                        )
                    case .error(let message):
                        errorState(message)
                        metricRow
                        HomeWidgetGrid(
                            canonicalOrder: driverHomeCanonicalOrder,
                            role: "DRIVER",
                            storageKey: widgetLayoutKey,
                            render: { id in driverHomeRender(id) }
                        )
                    }
                    // Reserve clearance under the floating BottomNav
                    // pill so the recent section doesn't tuck behind it.
                    Color.clear
                        .frame(height: Device.navHeight + Device.safeBottom + Space.s4)
                }
                .padding(Space.s5)
                .animation(.easeOut(duration: 0.18), value: vm.phase)
            }
            .scrollIndicators(.hidden)
            // Drag-down refreshes the home dashboard — weather, active
            // load card, metric tiles, and recent section. `vm.load()`
            // is the same async loader used on first appearance, so the
            // refresh is a real reload, not a stub.
            .refreshable {
                await vm.load()
                await suggestedLoadsStore.refresh()
            }
        }
        .task {
            await vm.load()
            await suggestedLoadsStore.refresh()
        }
        // RealtimeService → live updates from the driver's load
        // assignments / reassignments / surface refresh events trigger
        // an immediate dashboard reload so a brand-new load shows up
        // without waiting for the next pull-to-refresh.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task {
                await vm.load()
                await suggestedLoadsStore.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task {
                await vm.load()
                await suggestedLoadsStore.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadReassigned)) { _ in
            Task {
                await vm.load()
                await suggestedLoadsStore.refresh()
            }
        }
        // Home-widget tap routing — closes the dead-tap gap on the
        // MessagesWidget + NotificationsWidget tiles (they fire these
        // names with no other local effect, so without a listener the
        // taps would be true dead-taps per the observability-vs-dead
        // doctrine).
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("eusoOpenMessagesRequested"))) { _ in
            showMessages = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("eusoOpenNotificationsRequested"))) { _ in
            showNotificationsSheet = true
        }
        // Load Details sheet for the active/assigned load. Reuses the
        // canonical LoadDetailSheet the Eusoboards surface renders so
        // drivers get the same route map, rate breakdown, and broker
        // card regardless of which surface opened it.
        .sheet(isPresented: $showAssignedLoadDetail) {
            if let load = vm.activeLoad {
                LoadDetailSheet(
                    load: AvailableLoad.from(
                        load,
                        originCity: vm.originCity,
                        destCity: vm.destCity
                    )
                )
                .environment(\.palette, palette)
                .eusoSheetX()
            } else {
                // Summary-only fallback — builds a thinner AvailableLoad
                // from the LoadSummary projection so the detail sheet
                // still has enough to render while getById is in flight.
                LoadDetailSheet(
                    load: AvailableLoad(
                        id: vm.loadIDDisplay,
                        origin: vm.originCity,
                        destination: vm.destCity,
                        miles: 0,
                        equipment: "—",
                        rate: 0,
                        rpm: 0,
                        pickupWindow: vm.pickupStatusPill,
                        broker: "Dispatch",
                        hazmat: false,
                        weight: "—",
                        hotScore: 0,
                        originLat: 39.8283, originLng: -98.5795,
                        destLat: 39.8283, destLng: -98.5795
                    )
                )
                .environment(\.palette, palette)
                .eusoSheetX()
            }
        }
        // HOS port — full 019 surface with banks / 24h timeline / 3-meter
        // strip. Picks the `.afternoon` register so the live status reads
        // as an in-shift break state instead of the night scenario.
        .sheet(isPresented: $showHosSheet) {
            HosDutyStatus(register: .afternoon)
                .environment(\.palette, palette)
                .eusoSheetX()
        }
        // EusoWallet — full DriverWalletPane surface with settlements,
        // payouts, and linked-account CTAs.
        .sheet(isPresented: $showWalletSheet) {
            DriverWalletPane()
                .environment(\.palette, palette)
                .eusoSheetX()
        }
        // Home suggested-loads carousel — tapping a card surfaces the
        // same LoadDetailSheet the Eusoboards tab presents so the detail
        // UI stays consistent across entry points. Wired per user
        // direction (2026-04-21):
        //
        //   > when you press it it takes you to the load details
        .sheet(item: $selectedSuggestedLoad) { load in
            LoadDetailSheet(load: load)
                .environment(\.palette, palette)
                .eusoSheetX()
        }
        // Notifications inbox surfaced from the home NotificationsWidget
        // tile (and any other tile that posts the same name in future).
        // Wraps the body-only MeNotificationsView with a header + scroll
        // chrome so it stands alone — the MeDetailContainer normally
        // owns chrome for this view inside the Me sub-route.
        .sheet(isPresented: $showNotificationsSheet) {
            DriverHomeNotificationsSheet()
                .environment(\.palette, palette)
                .eusoSheetX()
        }
    }

    // MARK: TopBar

    // Figma 212:444 — two-line display greeting left, uppercase right-column label,
    // chat round button with magenta iridescent badge dot.
    private var topBar: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Text(greetingFirstName.isEmpty ? "Welcome back" : "Hey, \(greetingFirstName)")
                .font(.system(size: 40, weight: .heavy))
                // Brand gradient on the name reads as EusoTrip-native in
                // both Night and Afternoon. In light mode the prior
                // palette.textPrimary (near-black) flattened the hero line;
                // gradient restores the identity without a color flip.
                .foregroundStyle(LinearGradient.diagonal)
                .lineSpacing(-4)
                .lineLimit(2)
                // Without minimumScaleFactor a long first name (e.g.
                // "Christopherson") forced a 3-line wrap inside the
                // 180pt frame and spilled over the IridescentHairline.
                // With it the text shrinks gracefully so "Hey, Long"
                // and "Welcome back" both fit on two lines without
                // overlapping the right-rail location/time block.
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 180, alignment: .leading)

            Spacer(minLength: 0)

            // Right-rail greeting + location — two tight lines, no mid-dot,
            // with a small gradient pin glyph under a clean caps "GOOD
            // AFTERNOON". Prior single-line mid-dot layout forced a 3-line
            // wrap in a 110pt frame that read as cramped.
            VStack(alignment: .trailing, spacing: 4) {
                Text(timeOfDayGreeting.uppercased())
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(vm.locationCity)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: 140, alignment: .trailing)
            .padding(.top, Space.s3)

            // Chat glyph + live unread badge. `UnreadMessageStore` is the
            // single source of truth for the badge; it seeds from the
            // `messages.getUnreadCount` tRPC call on app start and
            // increments on `message:new` WebSocket fan-outs.
            MessagesBadgeButton(showMessages: $showMessages, palette: palette)
                .padding(.top, 2)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
        // Founder mandate 2026-05-05: replace the bottom-sheet pull-up
        // with a real full-screen messaging page (mirrors the web
        // platform). `MessagesScreen` owns the inbox + push-to-
        // conversation + new-message compose + back chevron.
        .fullScreenCover(isPresented: $showMessages) {
            MessagesScreen()
                .environment(\.palette, palette)
        }
    }

    private var timeOfDayGreeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Good night"
        }
    }

    // MARK: Loading / empty / error states

    /// Driver Home loading state. Previously leaked backend plumbing
    /// ("Contacting EusoTrip tRPC · loads.search · hos.getStatus") into
    /// production. The rebuilt state shows a dense ambient particle field
    /// inside the active-load card footprint — no diagnostic text, just
    /// brand-identity motion. Matches the user direction (2026-04-20):
    ///
    ///   > when screens are loading it shows this. is there a way to
    ///   > hide that from being seen. maybe make is particles floating
    ///   > in the box like thousands of them …
    private var loadingState: some View {
        ActiveCard {
            LoadingParticleField(count: 160, height: 180)
                .frame(maxWidth: .infinity)
        }
    }

    /// Subtle strip shown above the active-load card when the live backend
    /// was unreachable and the view fell back to the on-device demo state.
    /// Keeps the dashboard fully usable while being honest about the state.
    private var offlineBanner: some View {
        HStack(spacing: Space.s2) {
            Circle()
                .fill(Brand.warning)
                .frame(width: 6, height: 6)
            Text("Offline preview")
                .font(EType.micro).tracking(0.8)
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Button {
                Task { await vm.load() }
            } label: {
                Text("Retry")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    /// Renders a neutral gradient CTA in place of the WeatherCard when
    /// the driver has denied (or restricted) CoreLocation access. Tapping
    /// the card opens iOS Settings for the app so the driver can toggle
    /// location on — at which point the dashboard's next `.refreshable`
    /// pass will populate `vm.weather` with live WeatherKit data.
    ///
    /// 75th firing (2026-04-24, eusotrip-killers hygiene + fallback C):
    /// introduced so we can honor the "no fake data" doctrine while
    /// still communicating state to the driver. Replaces the old
    /// fabricated `"Enable location for live weather"` WeatherSnapshot
    /// placeholder that rendered a fake 72°/8 mph/10 mi snapshot.
    private var enableLocationCard: some View {
        Button {
            // Three states funnel through this CTA:
            //   • .notDetermined → fire the iOS "Allow location?"
            //     prompt (no Settings detour). After the user taps
            //     Allow, the next `.refreshable` pass populates
            //     `vm.weather` with live data.
            //   • .denied / .restricted → open Settings since iOS
            //     won't re-prompt; the founder needs the kill-switch
            //     in Settings to flip back on.
            // Founder report 2026-05-05 — "the app doesn't ask for
            // my location" — caused by the prior unconditional
            // Settings-deep-link path firing even when the system
            // had never asked.
            let status = WeatherService.shared.authorizationStatus
            if status == .notDetermined {
                WeatherService.shared.requestPermissionIfNeeded()
                Task {
                    // Re-poll the dashboard once the user responds so
                    // the card flips from the CTA into the live
                    // WeatherCard automatically.
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await vm.load()
                }
            } else if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(alignment: .center, spacing: Space.s3) {
                ZStack {
                    Circle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: 48, height: 48)
                    Image(systemName: "location.circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable location for live weather")
                        .font(EType.body.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Grant location access to see local conditions, visibility, and route weather alerts.")
                        .font(EType.micro)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
        .buttonStyle(.plain)
    }

    /// Shown when the driver has no active assignment. Replaces the
    /// previous "No active load assigned" dead-end card with a horizontal
    /// carousel of suggested freight — tapping a card opens
    /// `LoadDetailSheet`; the "Browse available loads" button switches
    /// to the Eusoboards tab for the full board. Driver direction
    /// (2026-04-21):
    ///
    ///   > that module should be a carousel of available loads and when
    ///   > you press it it takes you to the load details when you arent
    ///   > in an active load. … the carousel of course should have
    ///   > scroll left to right capability.
    private var noActiveLoadCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("AVAILABLE NEAR YOU")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Brand.success).frame(width: 6, height: 6)
                    Text("Live · \(suggestedLoads.count) loads")
                        .font(EType.micro).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }

            // Horizontal scroller — snap-paged so each card settles
            // center-of-screen. `.scrollTargetBehavior(.viewAligned)`
            // gives the natural deck feel the driver asked for. When
            // the live store returns zero loads we fall through to the
            // branded EusoEmptyState instead of rendering a mock card.
            if suggestedLoads.isEmpty {
                // Ambient empty state — no truck icon, no "Live · 0 loads"
                // drama. A single muted line that reads like a status,
                // not a card-sized void. The driver's intent from here
                // is to tap "Browse available loads" below; this row
                // just acknowledges the board is quiet right now.
                HStack(spacing: Space.s2) {
                    Circle()
                        .fill(palette.textTertiary.opacity(0.5))
                        .frame(width: 5, height: 5)
                    Text("Quiet on your lane — we'll let you know the moment tenders land.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.vertical, Space.s2)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Space.s3) {
                        ForEach(suggestedLoads) { load in
                            Button {
                                selectedSuggestedLoad = load
                            } label: {
                                SuggestedLoadCard(load: load)
                                    .frame(width: suggestedCardWidth)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Available load \(load.id), \(load.origin) to \(load.destination)")
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 2)
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
            }

            Button {
                // Switch the BottomNav to the Trips tab where the full
                // Eusoboards board lives. DriverHome doesn't own the
                // tab state — DriverHomeScreen does — so we fan out a
                // NotificationCenter event it listens for.
                NotificationCenter.default.post(
                    name: .eusoSwitchToTripsTab,
                    object: nil
                )
            } label: {
                HStack {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Browse available loads")
                        .font(EType.bodyStrong)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the Eusoboards load board")
        }
    }

    /// Target width for each card in the available-loads carousel.
    /// Uses the shell width minus the Home padding so one card sits flush
    /// with the screen and the next card peeks in by ~20% — the classic
    /// "peek-ahead carousel" rhythm from the Figma.
    private var suggestedCardWidth: CGFloat {
        // DriverHome is inside a TileStack padded by Space.s5 (20) on
        // each side. Target: full card = contentWidth - 48 (leaves a
        // 48pt peek for card[n+1] so the driver gets the swipe affordance).
        max(260, Device.width - (Space.s5 * 2) - 48)
    }

    private func errorState(_ message: String) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Brand.warning)
                    Text("Backend unavailable")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                }
                Text(message)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Button {
                    Task { await vm.load() }
                } label: {
                    Text("Retry")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(palette.bgCardSoft)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderSoft)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .padding(.top, Space.s3)
            }
        }
    }

    // MARK: Active load — live

    private var activeLoadCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: 0) {
                // head row
                HStack {
                    HStack(spacing: Space.s2) {
                        StatusPill(text: vm.pickupStatusPill, kind: .info)
                        if vm.cargoWeightPill != "—" {
                            StatusPill(text: vm.cargoWeightPill, kind: .neutral)
                        }
                        // 2026-05-17 — Driver Home active-load mode
                        // badge. Hidden for the default truck-single-
                        // vehicle case so the home screen stays clean.
                        // The driver is the role most likely to be
                        // *wrong* about mode (a rail engineer assigned
                        // a vessel charter is a disaster), so a single
                        // glance on Home surfaces the truth.
                        LoadModeBadge(modeRaw: vm.activeLoadSummary?.transportMode,
                                      multiVehicleCount: vm.activeLoadSummary?.multiVehicleCount,
                                      compact: true)
                    }
                    Spacer()
                    Text(vm.loadIDDisplay)
                        .font(.system(size: 12, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(palette.textSecondary)
                }

                // Figma 212:444 — amount on its own line (big gradient),
                // caption (linehaul · $/mi · total miles) on a line below.
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.amountDisplay)
                        .font(.system(size: 52, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(vm.rpmDisplay)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.top, Space.s4)

                // route row
                HStack(alignment: .top, spacing: Space.s3) {
                    routeNode(timeLabel: vm.originTimeLabel,
                              city: vm.originCity,
                              addr: vm.originAddr,
                              trail: "")
                    gradientArrow
                    routeNode(timeLabel: vm.destTimeLabel,
                              city: vm.destCity,
                              addr: vm.destAddr,
                              trail: "")
                }
                .padding(.top, Space.s4)

                // PNG canon (`01 Driver/{Light,Dark}/010 Driver Home.png`):
                // primary "Continue pre-trip" + outlined "Review load brief".
                // "Continue" honors the in-progress DVIR state surfaced by
                // PreTripDVIRStatusPill above; "Review load brief" routes to
                // the rich LoadDetailSheet (route map + rate breakdown +
                // broker card + permits) rather than a generic metadata pane.
                // PNG canon shows the two CTAs at roughly equal width
                // (50/50). "Review load brief" is wider than the legacy
                // "Details" copy, so the outlined CTA expands with
                // `maxWidth: .infinity` instead of the prior 110pt fixed
                // frame to keep the label on a single line at all device
                // widths.
                HStack(spacing: Space.s2) {
                    LifecycleCTAButton(title: "Continue pre-trip")
                        .frame(maxWidth: .infinity)
                    Button("Review load brief") { showAssignedLoadDetail = true }
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(palette.bgCardSoft)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderSoft)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .padding(.top, Space.s5)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Active load \(vm.loadIDDisplay), \(vm.amountDisplay) \(vm.rpmDisplay)")
    }

    private func routeNode(timeLabel: String, city: String, addr: String, trail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(timeLabel).font(EType.caption).foregroundStyle(palette.textSecondary)
            Text(city).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(2)
            Text(addr).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
            if !trail.isEmpty {
                Text(trail).font(EType.caption).foregroundStyle(palette.textPrimary).monospacedDigit()
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gradientArrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(LinearGradient.diagonal)
            .frame(width: 24)
    }

    // MARK: Metric row — Figma 212:444 two tiles
    // HOS uses split-gradient numeral (7h blue / 22m magenta) with mini unit suffixes.
    // Wallet shows plain white bold numeral ($4,118 when wired).

    private var metricRow: some View {
        // 3-meter §395.3 HOS strip per the Light/Dark PNG canon
        // (`01 Driver/{Light,Dark}/010 Driver Home.png`):
        //   DRIVE     · §395.3(a)(3)(i) 11-hour drive limit
        //   ON-DUTY   · §395.3(a)(2) 14-hour on-duty window
        //   CYCLE     · §395.3(b) 70-hour/8-day or 60-hour/7-day cycle
        // The full row tap-target opens the HOS Duty Status port screen
        // (019_HosDutyStatus) where the same three meters render with live
        // banks + 24h timeline + per-segment log entries. Wallet moved off
        // the Home metric row — still reachable via bottom-nav Wallet tab
        // and from per-row deep-links in the Recent activity card below.
        Button {
            showHosSheet = true
        } label: {
            HStack(spacing: Space.s3) {
                HosTile(value: vm.hosDriveLeftDisplay, label: "DRIVE")
                HosTile(value: vm.hosOnDutyDisplay,    label: "ON-DUTY")
                HosTile(value: vm.hosCycleDisplay,     label: "CYCLE")
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hours of service. Drive \(vm.hosDriveLeftDisplay). On-duty \(vm.hosOnDutyDisplay). Cycle \(vm.hosCycleDisplay).")
        .accessibilityHint("Opens the HOS duty status port")
    }

    // MARK: Recent — three activity rows (Figma 212:444)
    //
    // Each row is a live Button that deep-links into the right surface:
    //   · POD filed / settlement preview  → EusoWallet (settlement detail)
    //   · Detention claim approved        → EusoWallet (accessorials)
    //   · Fuel transaction                → EusoWallet (fuel log)
    //
    // Data is sourced from vm.recentActivity (settlements.recentByDriver
    // + fuel.recentByDriver tRPC endpoints). Falls back to on-device demo
    // rows if those endpoints haven't populated yet so the UI keeps its
    // shape during cold-start — the underlying action is always live.
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("Recent".uppercased())
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                // "See all" routes into the full Wallet sheet (settlements,
                // detentions, fuel — same surface as the Wallet tile above).
                Button("See all") { showWalletSheet = true }
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .underline()
            }

            VStack(spacing: 0) {
                if vm.recentActivity.isEmpty {
                    // Empty state — shown when the driver has no active
                    // load, no duty events, no unread messages, and no
                    // wallet balance fetched yet. Keeps the card's shape
                    // without faking placeholder rows.
                    HStack(spacing: Space.s3) {
                        ZStack {
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(palette.bgCardSoft)
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(palette.textTertiary)
                        }
                        .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No recent activity yet")
                                .font(EType.bodyStrong)
                                .foregroundStyle(palette.textPrimary)
                            Text("Assignments, duty changes, and payouts will show up here.")
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s3)
                } else {
                    ForEach(Array(vm.recentActivity.enumerated()), id: \.element.id) { idx, item in
                        Button {
                            // Row routing by kind. HOS opens the duty-status
                            // port, messages open the inbox sheet, everything
                            // else (load lifecycle, POD, settlements) opens
                            // the EusoWallet pane — the canonical surface
                            // for settlements, accessorial claims, and fuel.
                            switch item.kind {
                            case .hos:
                                showHosSheet = true
                            case .message:
                                showMessages = true
                            case .load, .document, .payment:
                                showWalletSheet = true
                            }
                        } label: {
                            activityRow(item: item)
                        }
                        .buttonStyle(ActivityRowButtonStyle())
                        .accessibilityLabel(item.title)
                        .accessibilityHint(accessibilityHint(for: item.kind))

                        if idx < vm.recentActivity.count - 1 {
                            Divider().overlay(palette.borderFaint).padding(.leading, 68)
                        }
                    }
                }
            }
            .eusoCard(radius: Radius.lg)
        }
    }

    /// VoiceOver hint for a recent-activity row. Matches the kind-based
    /// routing above so the announcement actually matches what the tap
    /// will open.
    private func accessibilityHint(for kind: RecentActivityKind) -> String {
        switch kind {
        case .hos:      return "Opens HOS duty status"
        case .message:  return "Opens your inbox"
        case .load, .document, .payment:
            return "Opens in EusoWallet"
        }
    }

    private func activityRow(item: RecentActivityItem) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(item.glyphTint)
                Image(systemName: item.glyph)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(item.glyphColor)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.subtitle)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.trail)
                    .font(EType.bodyStrong)
                    .monospacedDigit()
                    .foregroundStyle(item.trailColor)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .contentShape(Rectangle())
    }

    // Reorderable secondary-widget zone moved to the shared
    // HomeWidgetGrid component (defined at file scope above).
    // canonicalOrder + render closure are declared at the top of
    // this struct; nothing else lives here.
}

// MARK: - MessagesWidget (catalog widget id: "messages" · UNIVERSAL)
//
// Universal across all 24 roles. Reads the canonical
// UnreadMessageStore.shared total. Tap dispatches the same
// eusoLogoutRequested-pattern notification every role's topbar
// chat glyph fires, so the universal MessagesScreen surfaces from
// the same path regardless of role context.

struct MessagesWidget: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var unread = UnreadMessageStore.shared

    var body: some View {
        Button {
            NotificationCenter.default.post(
                name: Notification.Name("eusoOpenMessagesRequested"),
                object: nil
            )
        } label: {
            HStack(spacing: Space.s3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                        .frame(width: 44, height: 44)
                        .background(palette.bgCardSoft, in: Circle())
                    if unread.total > 0 {
                        Text(unread.total > 99 ? "99+" : "\(unread.total)")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Brand.danger, in: Capsule())
                            .offset(x: 6, y: -4)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("MESSAGES")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(unread.total == 0 ? "Inbox clean" : "\(unread.total) unread thread\(unread.total == 1 ? "" : "s")")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("Tap to open inbox")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - DriverHomeNotificationsSheet (wraps MeNotificationsView)
//
// MeNotificationsView is body-only (the MeDetailContainer normally
// supplies the title bar + xmark). This wrapper adds a header strip
// + ScrollView so the same surface stands on its own when presented
// directly from Home.

struct DriverHomeNotificationsSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("NOTIFICATIONS")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(palette.textSecondary)
                        .padding(8)
                        .background(palette.bgCard, in: Circle())
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            IridescentHairline()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    MeNotificationsView()
                    Color.clear.frame(height: 32)
                }
                .padding(.horizontal, 14)
                .padding(.top, Space.s3)
            }
        }
        .background(palette.bg.ignoresSafeArea())
    }
}

// MARK: - NotificationsWidget (catalog widget id: "notifications")
//
// Universal tile — top 3 platform alerts via `notifications.list(limit: 5)`
// with an unread-count badge. Tap posts `eusoOpenNotificationsRequested`
// so each role's shell can route to its own notifications screen.

struct NotificationsWidget: View {
    @Environment(\.palette) private var palette

    private struct AlertItem: Decodable, Identifiable, Hashable {
        let id: String
        let title: String
        let message: String?
        let timeAgo: String?
        let isRead: Bool?
    }
    private struct Page: Decodable {
        let notifications: [AlertItem]
        let total: Int?
    }
    private struct In: Encodable { let limit: Int; let archived: Bool }

    @State private var items: [AlertItem] = []
    @State private var totalUnread: Int = 0
    @State private var loading: Bool = true
    @State private var loadError: String? = nil

    var body: some View {
        Button {
            NotificationCenter.default.post(
                name: Notification.Name("eusoOpenNotificationsRequested"),
                object: nil
            )
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("NOTIFICATIONS")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(LinearGradient.diagonal)
                    Spacer(minLength: 0)
                    if totalUnread > 0 {
                        Text(totalUnread > 99 ? "99+ NEW" : "\(totalUnread) NEW")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Brand.danger, in: Capsule())
                    } else if !loading && loadError == nil {
                        Text("ALL READ")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                if loading {
                    Text("Loading alerts…")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else if let err = loadError {
                    Text(err)
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                        .lineLimit(2)
                } else if items.isEmpty {
                    Text("Inbox clean. No platform alerts.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(items.prefix(3)) { n in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill((n.isRead ?? true) ? palette.borderFaint : Brand.danger)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 6)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(n.title)
                                        .font(EType.bodyStrong)
                                        .foregroundStyle(palette.textPrimary)
                                        .lineLimit(1)
                                    if let m = n.message, !m.isEmpty {
                                        Text(m)
                                            .font(EType.caption)
                                            .foregroundStyle(palette.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                                if let t = n.timeAgo, !t.isEmpty {
                                    Text(t.uppercased())
                                        .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                                        .foregroundStyle(palette.textTertiary)
                                }
                            }
                        }
                    }
                }
                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    Text("OPEN INBOX")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .task { await load() }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let page: Page = try await EusoTripAPI.shared.query(
                "notifications.list",
                input: In(limit: 5, archived: false)
            )
            await MainActor.run {
                self.items = page.notifications
                self.totalUnread = page.notifications.filter { !($0.isRead ?? true) }.count
                self.loading = false
            }
        } catch {
            await MainActor.run {
                self.loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
                self.loading = false
            }
        }
    }
}

// MARK: - WeatherAlertsWidget (catalog widget id: "weather_alerts")
//
// Tight route-relevant weather card — surfaces the next actionable
// alert (e.g. "Light rain in 5h around pickup window") + visibility
// + wind gust risk. Reads from the same WeatherSnapshot the hero
// WeatherCard renders — composable, no second fetch.

struct WeatherAlertsWidget: View {
    @Environment(\.palette) private var palette
    let snapshot: WeatherSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: snapshot?.symbol ?? "cloud.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("WEATHER · ROUTE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                if let s = snapshot { Text(s.city).font(.system(size: 9, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textTertiary) }
            }
            if let s = snapshot {
                if let alert = s.nextAlert, !alert.isEmpty {
                    Text(alert)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                } else {
                    Text("\(s.tempF)°F · \(s.condition)")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                }
                HStack(spacing: 12) {
                    Label("\(s.windMph) mph", systemImage: "wind")
                    Label("\(s.visibilityMi) mi", systemImage: "eye")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            } else {
                Text("Enable location for live route weather.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

// MARK: - EarningsSummaryWidget (catalog widget id: "earnings_summary")
//
// Snapshot of wallet available + pending + last payout. Reads the
// live wallet snapshot the home VM already polls (vm.walletAvailable
// + sibling fields). Tap routes to EusoWallet via the existing
// notification path.

struct EarningsSummaryWidget: View {
    @Environment(\.palette) private var palette
    let available: Double?
    let availableDisplay: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("EARNINGS · WALLET")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                Text("EUSOWALLET")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("AVAILABLE")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text(availableDisplay)
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
            }
            if available == nil {
                Text("Sign in or wait for first sync. EusoWallet shows here once a balance lands.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

// MARK: - NextDeliveryWidget (catalog widget id: "next_delivery")
//
// Glanceable next-delivery tile pulled from the same LoadSummary the
// home's hero activeLoadCard renders. Composes a tight 3-line card:
// load number + lane + pickup date so the driver has the destination
// + ETA at the top of the customizable widget zone without the full
// hero card weight.

struct NextDeliveryWidget: View {
    @Environment(\.palette) private var palette
    let summary: LoadSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("NEXT DELIVERY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                if let s = summary {
                    Text(s.status.uppercased())
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            if let s = summary {
                Text(s.loadNumber)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("\(s.origin)  →  \(s.destination)")
                    .font(EType.body)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                    Text(s.pickupDate)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                    Spacer(minLength: 0)
                    if s.rate > 0 {
                        Text("$\(Int(s.rate).formatted())")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                            .monospacedDigit()
                    }
                }
            } else {
                Text("No load assigned. Accept a tender to populate.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

// MARK: - HosTrackerWidget (catalog widget id: "hos_tracker")
//
// First port of a web-catalog widget to an iOS tile-card. Wraps the
// existing HosTile primitive with a card shell + tap-to-open the
// full 019_HosDutyStatus surface. Reads live data from
// HOSClockService.shared (already booted by EusoTripApp).

struct HosTrackerWidget: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var hos = HOSClockService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("HOS · LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                if let s = hos.status {
                    Text(s.canDrive ? "CAN DRIVE" : "BREAK DUE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(s.canDrive ? Color.green.opacity(0.85) : Brand.danger)
                        .clipShape(Capsule())
                }
            }
            if let s = hos.status {
                HStack(spacing: Space.s2) {
                    HosTile(value: s.drivingRemainingDisplay, label: "DRIVE")
                    HosTile(value: s.onDutyRemainingDisplay, label: "ON-DUTY")
                    HosTile(value: s.cycleRemainingDisplay, label: "CYCLE")
                }
            } else {
                Text("Loading HOS…")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

/// Tapped-state styling for activity rows — soft scale + flash so the
/// tap feedback reads without pulling the whole row off the card. Keeps
/// the EusoCard hairline intact underneath.
private struct ActivityRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - HosTile (Figma 212:444)
/// Split-gradient HOS drive-left tile — hours in Brand.blue, minutes in Brand.magenta,
/// with tiny lowercase "h" / "m" unit suffixes baselined under the numerals.
private struct HosTile: View {
    let value: String
    /// Override the eyebrow label. Default keeps the original
    /// `HOS DRIVE LEFT` rendering for legacy callers; the 3-meter strip
    /// passes `DRIVE` / `ON-DUTY` / `CYCLE` to mirror the §395.3 PNG
    /// canon (49 CFR 395.3(a)(3)(i) drive · §395.3(a)(2) on-duty ·
    /// §395.3(b) cycle).
    var label: String = "HOS DRIVE LEFT"
    @Environment(\.palette) var palette

    /// Parse "7h 22m" → (hours, minutes). Falls back gracefully on "—" / bad input.
    private var parts: (hours: String, minutes: String)? {
        let s = value.replacingOccurrences(of: " ", with: "")
        guard let hIdx = s.firstIndex(of: "h") else { return nil }
        let h = String(s[..<hIdx])
        let after = s.index(after: hIdx)
        let rest = String(s[after...]).replacingOccurrences(of: "m", with: "")
        guard !h.isEmpty else { return nil }
        return (h, rest)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Group {
                if let p = parts {
                    // Numeric duotone — both hours and minutes read
                    // through the brand gradient so the whole clock
                    // value reads as a single gradient numeric per the
                    // doctrine ("gradient, not blue"). The blue→magenta
                    // split is already carried by LinearGradient.diagonal
                    // (topLeading → bottomTrailing).
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(p.hours)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("h")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(LinearGradient.diagonal)
                            .padding(.trailing, 4)
                        Text(p.minutes)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("m")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    .monospacedDigit()
                } else {
                    Text(value)
                        .font(EType.numeric)
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }
}

// MARK: - MileageTrackerWidget (catalog widget id: "mileage_tracker")
//
// Monthly miles tile. Pulls `totalMiles` from `drivers.getPerformanceMetrics`
// for the month-to-date figure. Also surfaces the active load's distance
// (passed from the home VM) so the driver can see their current-haul
// mileage at a glance alongside the rolling monthly total.

struct MileageTrackerWidget: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    /// Miles on the current active load — nil when the driver is between loads.
    let currentLoadMiles: Double?

    @State private var monthlyMiles: Double? = nil
    @State private var totalLoads: Int? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    private static let miFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    private func fmt(_ miles: Double) -> String {
        Self.miFormatter.string(from: NSNumber(value: miles)) ?? String(Int(miles))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "road.lanes")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("MILEAGE · THIS MONTH")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                if let loads = totalLoads {
                    Text("\(loads) LOADS")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            if loading {
                Text("Loading mileage…")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else if let err = loadError {
                Text(err)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .lineLimit(2)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(monthlyMiles.map { fmt($0) } ?? "—")
                        .font(.system(size: 36, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                    Text("mi")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
                if let loadMi = currentLoadMiles, loadMi > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("Current haul: \(fmt(loadMi)) mi")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                } else if monthlyMiles == nil {
                    Text("No mileage data yet for this period.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.top, 2)
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .task { await load() }
    }

    private func load() async {
        loading = true; loadError = nil
        let userId = session.user?.id ?? ""
        guard !userId.isEmpty else { loading = false; return }
        do {
            let sc = try await EusoTripAPI.shared.drivers.getPerformanceMetrics(
                driverId: userId, period: .month
            )
            monthlyMiles = sc.metrics.totalMiles
            totalLoads = sc.metrics.totalLoads
            loading = false
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            loading = false
        }
    }
}

// MARK: - VehicleHealthWidget (catalog widget id: "vehicle_health")
//
// Driver's assigned-truck glance card. Reads `vehicle.getAssigned` for
// unit number, year/make/model, fuel level, odometer, and status.
// Odometer + fuelLevel are 0 until the telematics ELD integration ships
// (vehicle.ts:138) — the view surfaces a disclosure row when both are
// zero rather than printing "0 mi / 0%". No fake data.

struct VehicleHealthWidget: View {
    @Environment(\.palette) private var palette

    private typealias Vehicle = VehicleAPI.AssignedVehicle

    @State private var vehicle: Vehicle? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    private var statusColor: Color {
        switch vehicle?.status.lowercased() {
        case "active":       return .green
        case "maintenance":  return Brand.warning
        case "out_of_service": return Brand.danger
        default:             return palette.textTertiary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("VEHICLE · HEALTH")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                if let v = vehicle, !v.isUnassigned {
                    Text(v.status.uppercased().replacingOccurrences(of: "_", with: " "))
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(statusColor, in: Capsule())
                }
            }
            if loading {
                Text("Loading vehicle…")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else if let err = loadError {
                Text(err)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .lineLimit(2)
            } else if let v = vehicle, !v.isUnassigned {
                Text("\(v.year) \(v.make) \(v.model)")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("Unit \(v.unitNumber)  ·  \(v.licensePlate)")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                if v.fuelLevel > 0 || v.odometer > 0 {
                    HStack(spacing: 12) {
                        if v.fuelLevel > 0 {
                            Label(String(format: "%.0f%% fuel", v.fuelLevel * 100), systemImage: "fuelpump.fill")
                        }
                        if v.odometer > 0 {
                            Label("\(v.odometer.formatted()) mi", systemImage: "gauge.with.dots.needle.33percent")
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                } else {
                    Text("Telematics pending — ELD sync not yet active.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.top, 2)
                }
            } else {
                Text("No vehicle assigned.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .task { await load() }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let v = try await EusoTripAPI.shared.vehicle.getAssigned()
            vehicle = v
            loading = false
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            loading = false
        }
    }
}

// MARK: - PerformanceScoreWidget (catalog widget id: "performance_score")
//
// Monthly driver scorecard tile. Reads safetyScore + onTimeDeliveryRate
// + fleet rank from `drivers.getPerformanceMetrics`. Self-fetches on
// appear using the signed-in user's id from the session environment.

struct PerformanceScoreWidget: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    private struct Snapshot {
        let safetyScore: Double
        let onTimeRate: Double
        let rank: Int
        let totalDrivers: Int
    }

    @State private var snap: Snapshot? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("PERFORMANCE · MONTHLY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                if let s = snap {
                    Text("#\(s.rank) of \(s.totalDrivers)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            if loading {
                Text("Loading score…")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else if let err = loadError {
                Text(err)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .lineLimit(2)
            } else if let s = snap {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.0f", s.safetyScore))
                        .font(.system(size: 36, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                    Text("/ 100")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                    Text("SAFETY SCORE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
                HStack(spacing: 12) {
                    Label(String(format: "%.0f%%", s.onTimeRate), systemImage: "checkmark.circle.fill")
                    Text("on-time")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            } else {
                Text("No performance data yet for this period.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .task { await load() }
    }

    private func load() async {
        loading = true; loadError = nil
        let userId = session.user?.id ?? ""
        guard !userId.isEmpty else { loading = false; return }
        do {
            let sc = try await EusoTripAPI.shared.drivers.getPerformanceMetrics(
                driverId: userId, period: .month
            )
            snap = Snapshot(
                safetyScore: sc.metrics.safetyScore,
                onTimeRate: sc.metrics.onTimeDeliveryRate,
                rank: sc.rankings.overall,
                totalDrivers: sc.rankings.totalDrivers
            )
            loading = false
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            loading = false
        }
    }
}

// MARK: - CurrentRouteWidget (catalog widget id: "current_route")
//
// Active-route glance: origin → destination lane, distance, and pickup
// date sourced from the Load the home VM already fetched. No extra
// network call — pure display of vm.activeLoad.

struct CurrentRouteWidget: View {
    @Environment(\.palette) private var palette
    let load: Load?

    private var statusColor: Color {
        switch load?.status.lowercased() {
        case "in_transit":  return .green
        case "assigned":    return Brand.warning
        case "delivered":   return palette.textTertiary
        default:            return palette.textTertiary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "location.north.line.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CURRENT ROUTE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                if let l = load {
                    Text(l.status.uppercased().replacingOccurrences(of: "_", with: " "))
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(statusColor)
                }
            }
            if let l = load {
                Text(l.loadNumber)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                HStack(alignment: .center, spacing: 4) {
                    Text(l.pickupLocation?.cityState ?? "—")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(l.deliveryLocation?.cityState ?? "—")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 4) {
                    Image(systemName: "road.lanes")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                    Text(l.distanceValue > 0 ? "\(Int(l.distanceValue)) mi" : "— mi")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                    Image(systemName: "calendar")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                    Text(l.pickupDate ?? "—")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
            } else {
                Text("No active route. Accept a tender to populate.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

// MARK: - Screen wrapped in Shell + Driver nav

/// Which tab is currently selected from the BottomNav. The Driver nav has
/// four slots (home/trips/wallet/me) with the center slot reserved for the
/// ESANG orb, which opens the ESANG chat rather than switching tabs.
/// SINGLE SOURCE OF TRUTH for the Driver bottom-nav tabs (label + SF Symbol).
/// Screens MUST build their nav slots from these computed properties, e.g.
///   NavSlot(label: DriverTab.wallet.label, systemImage: DriverTab.wallet.systemImage, isCurrent: …)
/// Do NOT hardcode nav labels/icons inside a screen — that caused the
/// Wallet→Loads label drift and the Trips icon drift (swept 2026-05-22).
/// Renaming a tab here now propagates to every screen automatically.
enum DriverTab: String, CaseIterable, Identifiable {
    case home, trips, wallet, me
    var id: String { rawValue }

    var label: String {
        switch self {
        case .home:   return "Home"
        case .trips:  return "Trips"
        case .wallet: return "Loads"   // case kept as .wallet for back-compat;
                                        // slot 3 is now the My Loads surface.
        case .me:     return "Me"
        }
    }
    var systemImage: String {
        switch self {
        case .home:   return "house"
        case .trips:  return "truck.box"
        case .wallet: return "shippingbox.fill"  // was "creditcard"; routes to DriverLoadsPane.
        case .me:     return "person"
        }
    }
}

struct DriverHomeScreen: View {
    let theme: Theme.Palette

    @State private var currentTab: DriverTab = .home
    @State private var orbState: OrbeSang.State = .idle
    /// The ESANG coach is presented as a custom overlay (not a system sheet)
    /// so we can drive a unified dissolve-to-orb transform on close — the
    /// sheet shrinks + blurs toward the orb while a single particle field
    /// converges on the same point. Web-parity behavior from the
    /// eSangChatWidget dissolve pattern.
    @State private var showeSang: Bool = false
    /// Drives the dissolve animation on close. While true, the sheet is
    /// scaling + blurring toward the orb anchor and particles are flying
    /// inward. Flips back to false after the burst clears.
    @State private var esangDissolving: Bool = false
    /// Particles spawn from this rect (the sheet's visual bounds). Captured
    /// once when the dissolve starts so the particle overlay can outlive the
    /// collapsing sheet.
    @State private var esangSheetRect: CGRect = .zero
    /// Orb anchor in screen space. Recomputed by `GeometryReader` so the
    /// dissolve always converges on the real orb position.
    @State private var orbAnchor: CGPoint = .zero
    /// True while the particle burst is actively rendering.
    @State private var esangBurstActive: Bool = false

    private func leadingSlots() -> [NavSlot] {
        [
            NavSlot(
                label: DriverTab.home.label,
                systemImage: DriverTab.home.systemImage,
                isCurrent: currentTab == .home,
                onTap: { currentTab = .home }
            ),
            NavSlot(
                label: DriverTab.trips.label,
                systemImage: DriverTab.trips.systemImage,
                isCurrent: currentTab == .trips,
                onTap: { currentTab = .trips }
            )
        ]
    }
    private func trailingSlots() -> [NavSlot] {
        [
            NavSlot(
                label: DriverTab.wallet.label,
                systemImage: DriverTab.wallet.systemImage,
                isCurrent: currentTab == .wallet,
                onTap: { currentTab = .wallet }
            ),
            NavSlot(
                label: DriverTab.me.label,
                systemImage: DriverTab.me.systemImage,
                isCurrent: currentTab == .me,
                onTap: { currentTab = .me }
            )
        ]
    }

    var body: some View {
        ZStack {
            Shell(theme: theme) {
                Group {
                    switch currentTab {
                    case .home:   DriverHome()
                    case .trips:  DriverTripsPane()
                    case .wallet: DriverLoadsPane()
                    case .me:     DriverMePane()
                    }
                }
                .transition(.opacity)
                .animation(.easeOut(duration: 0.18), value: currentTab)
            } nav: {
                BottomNav(leading: leadingSlots(),
                          trailing: trailingSlots(),
                          orbState: orbState,
                          onTapOrb: { openeSang() })
            }

            // ESANG coach sheet — presented as a custom overlay so we can
            // animate the sheet itself shrinking + blurring toward the orb
            // on close, with particles that converge on the same point.
            if showeSang {
                esangBackdrop
                    .transition(.opacity)
                    .zIndex(90)

                esangSheet
                    .zIndex(91)
            }

            // Particle dissolve — spawns from the sheet's visual bounds
            // and converges on the orb, timed to land with the sheet's
            // shrink/blur collapse. NO transition: particles must be
            // fully opaque from the instant they spawn, otherwise the
            // view fades in while particles are already mid-flight and
            // the burst reads as empty.
            if esangBurstActive {
                eSangParticleBurst(
                    sourceRect: esangSheetRect,
                    anchor: orbAnchor,
                    duration: 0.65,
                    onDone: { esangBurstActive = false }
                )
                .frame(width: Device.width, height: Device.height)
                .allowsHitTesting(false)
                .zIndex(100)
            }
        }
        .onAppear { updateOrbAnchor() }
        // DriverHome's "Browse available loads" button fans out this
        // event when the driver is between loads and wants the full
        // Eusoboards view. The home pane doesn't own tab state, so we
        // listen here and swap the BottomNav selection.
        .onReceive(NotificationCenter.default.publisher(for: .eusoSwitchToTripsTab)) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                currentTab = .trips
            }
        }
    }

    // MARK: - ESANG orchestration

    private func openeSang() {
        let impact = UIImpactFeedbackGenerator(style: .soft)
        impact.impactOccurred()
        orbState = .thinking
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.35)) {
            showeSang = true
        }
    }

    /// Kicks off the dissolve: the sheet's in-place scale+blur collapse and
    /// the particle burst start on the SAME frame so the motion reads as
    /// one graceful transform. Matches the web twin's 0.5s collapse with a
    /// 0.15s particle tail (total 0.65s window).
    private func dissolveeSang() {
        guard showeSang, !esangDissolving else { return }
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        // Recapture the anchor + sheet rect right now so the burst is
        // guaranteed to have non-zero coordinates, even if onAppear
        // hadn't fired yet or the device metrics changed.
        updateOrbAnchor()
        // Particles must render fully opaque from frame zero — so flip
        // the burst flag OUTSIDE withAnimation (no fade-in transition).
        // The sheet's scale+blur+opacity collapse animates alongside.
        // Both state changes commit on the same render tick because
        // SwiftUI batches state updates within one function body.
        esangBurstActive = true
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.5)) {
            esangDissolving = true
        }
        // Unmount the sheet after the particle tail lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            showeSang = false
            esangDissolving = false
            orbState = .idle
        }
    }

    private func updateOrbAnchor() {
        // The Shell is a fixed-size device frame centered in its parent —
        // the orb sits horizontally centered and just above the bottom
        // safe-area/nav plate. We compute the anchor in the Shell's local
        // space, which is also the ZStack's space (same parent).
        orbAnchor = CGPoint(
            x: Device.width / 2,
            y: Device.height - Device.safeBottom - Device.navHeight / 2 - Space.s2
        )
        // The sheet's bounds equal the Shell bounds minus the top and bottom
        // insets that the sheet itself will pad. For particle seeding we use
        // roughly the sheet's visible chrome area so particles spawn "from
        // the chat box" rather than from safe-area padding.
        esangSheetRect = CGRect(
            x: 0,
            y: Device.safeTop,
            width: Device.width,
            height: Device.height - Device.safeTop - Device.safeBottom - Device.navHeight
        )
    }

    // MARK: - ESANG overlay subviews

    private var esangBackdrop: some View {
        // Dim layer behind the sheet. Tapping outside starts the dissolve —
        // matches the web "tap out to close" affordance.
        Color.black
            .opacity(esangDissolving ? 0 : 0.45)
            .frame(width: Device.width, height: Device.height)
            .onTapGesture { dissolveeSang() }
            .animation(.easeOut(duration: 0.5), value: esangDissolving)
    }

    private var esangSheet: some View {
        // Match the web twin (eSangChatWidget.tsx line 717–720):
        //   animate: { opacity: 0, scale: 0.15, filter: 'blur(12px)', y: 0 }
        //
        // The sheet shrinks + blurs in place — it does NOT translate toward
        // the orb. The particle burst carries the visual motion so there's
        // one coherent transform, not two competing motions.
        return DrivereSangCoachSheet(onClose: dissolveeSang)
            .environment(\.palette, theme)
            .frame(width: Device.width, height: Device.height)
            .background(theme.bgPage)
            .clipShape(RoundedRectangle(cornerRadius: 55, style: .continuous))
            .scaleEffect(esangDissolving ? 0.15 : 1.0)
            .blur(radius: esangDissolving ? 12 : 0)
            .opacity(esangDissolving ? 0 : 1)
            .transition(
                .asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                )
            )
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted by DriverHome's "Browse available loads" CTA and caught by
    /// DriverHomeScreen to swap the BottomNav selection to the Trips
    /// tab (which hosts the Eusoboards board).
    static let eusoSwitchToTripsTab = Notification.Name("eusoSwitchToTripsTab")
}

// MARK: - SuggestedLoadCard

/// Compact card used by the Home carousel of available freight shown
/// when the driver has no active assignment. Smaller than the full
/// Eusoboards `LoadBoardCard` — the driver has to be able to swipe
/// through a stack of them at a glance, so we show the lane, rate, and
/// one meta line (equipment + pickup window) and hide the broker row
/// + action buttons. Tapping the card routes the selection to
/// `LoadDetailSheet` for the full breakdown.
struct SuggestedLoadCard: View {
    let load: AvailableLoad
    @Environment(\.palette) var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            // Top meta — equipment + hot chip + ID tag
            HStack(spacing: Space.s2) {
                StatusPill(text: load.equipment,
                           kind: load.hazmat ? .hazmat : .info)
                if load.hotScore >= 4 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("HOT")
                            .font(EType.micro).tracking(0.6)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(LinearGradient.diagonal))
                }
                Spacer(minLength: 0)
                Text(load.id)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }

            // Lane
            HStack(alignment: .top, spacing: Space.s2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PICKUP")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(load.origin)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                }
                VStack(spacing: 2) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("\(load.miles) mi")
                        .font(EType.micro).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("DROP")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(load.destination)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                }
            }

            Divider().overlay(palette.borderFaint)

            // Rate + window
            HStack(alignment: .firstTextBaseline) {
                Text("$\(Int(load.rate).formatted())")
                    .font(.system(size: 22, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text(String(format: "$%.2f/mi", load.rpm))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
            }

            HStack(spacing: Space.s2) {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text(load.pickupWindow)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
        .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

// MARK: - Previews (both themes)

#Preview("Driver Home · Dark") {
    DriverHomeScreen(theme: Theme.dark)
        .environmentObject(DriverProfileStore())
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
        .padding(24)
        .background(Theme.dark.bgPage)
}

#Preview("Driver Home · Light") {
    DriverHomeScreen(theme: Theme.light)
        .environmentObject(DriverProfileStore())
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
        .padding(24)
        .background(Theme.light.bgPage)
}
