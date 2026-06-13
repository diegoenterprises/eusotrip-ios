//
//  212_ShipperControlTower.swift
//  EusoTrip 2027 UI — Shipper · Control Tower (parity-reconciled 2026-04-29)
//
//  PARITY AUDIT 2026-04-29 — reconciled to wireframe canon at
//  /02 Shipper/Code/212_ShipperControlTower.swift. Persona: Diego
//  Usoro / Eusorone Technologies (companyId 1) per §11. Map hero
//  uses the real HERE basemap (HereMapView raster overlay) instead
//  of the wireframe's illustrative SVG sketch — production fidelity
//  beats canvas fidelity for the flagship visibility surface.
//
//  Layout (top → bottom):
//    1. TopBar           ✦ SHIPPER · CONTROL TOWER · LIVE / "{N} EXCEPTIONS · {N} IN TRANSIT" (danger)
//    2. Title block      Control Tower / "{X} active · {N} MATRIX loads · live HERE basemap"
//    3. IridescentHairline
//    4. Map hero (380pt) HereMapView (live HERE tiles) + mode chip overlay + KPI strip overlay
//    5. Exception peek   Bottom sheet handle + danger wash + 2 exception chips
//    6. BY MODE cards    EXTRA-OK supplemental — truck/ocean/rail breakdown
//    7. EXCEPTIONS detail EXTRA-OK supplemental — full merged list (truck + vessel)
//    8. RECENT ACTIVITY  EXTRA-OK supplemental — last 30 events feed
//
//  Real wiring preserved: `controlTower.overview` (mode counts + totals),
//  `controlTower.exceptions(limit:50)` (truck + vessel + totalExceptions),
//  `controlTower.recentActivity(limit:30)` (per-mode activity feed).
//  Mode filter chip selects the BY MODE breakdown without re-fetching.
//
//  Backend gaps surfaced (logged in audit log, no fake data):
//    EUSO-2108 — `controlTower.overview` doesn't ship `onTimeRate` /
//                `onTimeTrail`. KPI strip ON-TIME cell paints "-"
//                placeholder until backend exposes the metric.
//
//  Doctrine refs: §2 ME nav (handled by ContentView); §3 numbers-first
//  copy ("12 active · 50 MATRIX loads"); §4.3 single iridescent
//  hairline; §6 single full-bleed map hero (HERE basemap canon);
//  §7 breathe density; §11 / §11.2 / §11.4 Diego canon + MATRIX-50;
//  §17.2 chip + KPI tile width-locked grammar; §22.2 textTertiary
//  counter color (here red-tinted because exception count drives
//  attention); §20.4 no dead buttons (mode chip taps post
//  `eusoShipperControlTowerMode`, exception chips post
//  `eusoShipperControlTowerException`).
//

import SwiftUI

// MARK: - Store (preserved verbatim — real backend wiring)

@MainActor
final class ControlTowerStore: ObservableObject {
    enum LoadState {
        case loading
        case empty
        case error(String)
        case loaded(
            overview: ControlTowerAPI.Overview,
            exceptions: ControlTowerAPI.ExceptionsResponse,
            activity: [ControlTowerAPI.ActivityRow]
        )
    }

    @Published private(set) var state: LoadState = .loading

    /// Per-load pickup positions for the hero map. Sourced from the
    /// real `controlTower.getActivePositions` proc, which surfaces the
    /// `loads.pickupLocation` lat/lng JSON column already persisted in
    /// the DB (the SAME coords `loads.list` ships to the Catalyst
    /// dispatch board). The `overview` proc only returns COUNTS, so
    /// before this the hero map had no markers to draw. Null-island
    /// loads are gated out server-side AND below.
    @Published private(set) var positions: [ActiveLoadPosition] = []

    /// One active-load map position. Mirrors the
    /// `controlTower.getActivePositions` row shape. `lat`/`lng` come
    /// straight off `loads.pickupLocation` (real geocoded DB coords).
    struct ActiveLoadPosition: Decodable, Identifiable, Hashable {
        let id: Int
        let loadNumber: String?
        let status: String?
        let mode: String?
        let lat: Double
        let lng: Double

        /// Null-island gate (013:427 doctrine) — a load whose pickup is
        /// (0,0) is un-geocoded; drop it rather than frame the Atlantic.
        var fix: HereLatLng? {
            guard !(lat == 0 && lng == 0) else { return nil }
            return HereLatLng(lat, lng)
        }
    }

    private struct ActivePositionsEnvelope: Decodable {
        let positions: [ActiveLoadPosition]
        let total: Int
    }

    private let api: EusoTripAPI

    init(api: EusoTripAPI = .shared) {
        self.api = api
    }

    func refresh() async {
        if case .loaded = state {} else { state = .loading }
        do {
            struct PositionsInput: Encodable { let limit: Int }
            async let o   = api.controlTower.overview()
            async let exc = api.controlTower.exceptions(limit: 50)
            async let act = api.controlTower.recentActivity(limit: 30)
            // Per-load map coords from the real getActivePositions proc
            // (loads.pickupLocation lat/lng). Failure here must NOT take
            // down the whole dashboard — the counts/exceptions/activity
            // remain the source of truth, so we degrade the map to its
            // CONUS-framed empty state instead of erroring the screen.
            async let pos = (try? api.query(
                "controlTower.getActivePositions",
                input: PositionsInput(limit: 200)
            ) as ActivePositionsEnvelope)
            let (overview, exceptions, activity, envelope) = try await (o, exc, act, pos)

            positions = (envelope?.positions ?? []).filter { $0.fix != nil }

            let allZero =
                overview.total.active == 0 &&
                overview.total.inTransit == 0 &&
                exceptions.totalExceptions == 0 &&
                activity.isEmpty
            if allZero {
                state = .empty
            } else {
                state = .loaded(overview: overview, exceptions: exceptions, activity: activity)
            }
        } catch {
            state = .error("Couldn't reach control tower service.")
        }
    }
}

// MARK: - Mode filter

private enum ModeFilter: String, CaseIterable, Identifiable {
    case all, truck, rail, vessel
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:    return "All"
        case .truck:  return "Truck"
        case .rail:   return "Rail"
        case .vessel: return "Vessel"
        }
    }
}

// MARK: - Screen root

struct ShipperControlTower: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var store = ControlTowerStore()
    @State private var modeFilter: ModeFilter = .all

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, Space.s5)
                titleBlock
                    .padding(.top, Space.s2)
                IridescentHairline()
                    .padding(.top, Space.s3)

                content
                    .padding(.top, Space.s4)

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        // RealtimeService → ControlTower is the operational dashboard
        // par excellence; every load event refreshes the exception
        // counts, ETA distributions, and on-time scoring live.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await store.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task { await store.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadReassigned)) { _ in
            Task { await store.refresh() }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.18),
            value: storeStateKey
        )
    }

    /// Stable string used as the animation key so SwiftUI re-runs
    /// the cross-fade only when the load state actually flips.
    private var storeStateKey: String {
        switch store.state {
        case .loading: return "loading"
        case .empty:   return "empty"
        case .error:   return "error"
        case .loaded(let o, let e, let a):
            return "loaded-\(o.total.active)-\(o.total.inTransit)-\(e.totalExceptions)-\(a.count)"
        }
    }

    // MARK: TopBar (gradient eyebrow + danger-tinted exception+transit counter)

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · CONTROL TOWER · LIVE")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text(counterEyebrow)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(counterTint)
                .accessibilityLabel(counterAccessibility)
        }
        .padding(.horizontal, Space.s3)
    }

    private var counterEyebrow: String {
        if case .loaded(let o, let e, _) = store.state {
            return "\(e.totalExceptions) EXCEPTIONS · \(o.total.inTransit) IN TRANSIT"
        }
        return "-"
    }

    private var counterTint: Color {
        if case .loaded(_, let e, _) = store.state, e.totalExceptions > 0 {
            return Brand.danger
        }
        return palette.textTertiary
    }

    private var counterAccessibility: String {
        if case .loaded(let o, let e, _) = store.state {
            return "\(e.totalExceptions) exceptions, \(o.total.inTransit) in transit"
        }
        return "Loading control tower"
    }

    // MARK: Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Control Tower")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text(titleSubtitle)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3)
    }

    private var titleSubtitle: String {
        if case .loaded(let o, _, _) = store.state {
            return "\(o.total.active) active · \(o.total.inTransit) in transit · all modes"
        }
        return "Truck · rail · vessel — every load, every mode, one command view."
    }

    // MARK: Content state machine

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .loading:
            loadingShell
                .padding(.horizontal, Space.s3)
        case .empty:
            EusoEmptyState(
                systemImage: "eye",
                title: "Nothing in flight yet",
                subtitle: "Once you post your first load, the control tower lights up with live mode counts, exceptions and activity.",
                comingSoon: false
            )
            .padding(.horizontal, Space.s3)
        case .error(let msg):
            inlineError(msg) { Task { await store.refresh() } }
                .padding(.horizontal, Space.s3)
        case .loaded(let o, let e, let a):
            VStack(spacing: 0) {
                mapHero(overview: o, exceptionCount: e.totalExceptions)
                exceptionPeek(e)
                supplementalSections(overview: o, exceptions: e, activity: a)
            }
        }
    }

    // MARK: Map hero — HereMapView basemap + chip overlay + KPI strip overlay

    private func mapHero(overview: ControlTowerAPI.Overview, exceptionCount: Int) -> some View {
        ZStack(alignment: .top) {
            // §6 — single full-bleed HERE basemap. 2026-05-21: swapped the
            // raster HereMapView (Maps Tile v3 — empty grid, plan doesn't
            // serve raster) for the OMV vector renderer the web platform
            // uses + the plan DOES serve. Light tiles in light mode, dark
            // in dark.
            // 2026-06-01 (D-maps-basemap): the bespoke canvas now paints an
            // abstract land basemap UNDER any data, so this CONUS situational
            // view reads as a real map instead of a blank panel.
            // 2026-06-05 (D-maps-positions): the hero map is now FED real
            // per-load markers. `controlTower.getActivePositions` returns
            // the active loads' pickup lat/lng straight off the
            // `loads.pickupLocation` JSON column (the SAME coords the
            // Catalyst dispatch board draws from `loads.list`). Null-island
            // (0,0) loads are gated out server-side AND in the store, so
            // every pin is a real geocoded pickup. Pins carry the load `id`
            // so a tap routes through `onSelectMarker` → opens load detail.
            // When there are genuinely no geocoded active loads the map
            // honestly frames CONUS with zero pins (no fabricated points).
            HereLiveMapView(
                center: mapCenter,
                zoom: mapZoom,
                route: [],
                baseLayers: loadMarkerLayers,
                addOns: .shipperTracking,
                onSelectMarker: { loadId in openLoad(loadId) }
            )
                .frame(height: 380)
                .clipped()
                .accessibilityLabel("Live load map, \(overview.total.active) active loads, \(store.positions.count) plotted")

            VStack(alignment: .leading, spacing: Space.s3) {
                modeFilterChips(overview: overview)
                kpiStrip(overview: overview, exceptionCount: exceptionCount)
            }
            .padding(.horizontal, Space.s3)
            .padding(.top, 10)
        }
    }

    // MARK: Map data plumbing (real loads.pickupLocation coords)

    /// The base-layer markers fed into the hero map — one `.pickup` pin
    /// per active load, positioned by the real `loads.pickupLocation`
    /// lat/lng (`controlTower.getActivePositions`). Each pin carries the
    /// load `id` so its tap routes through `onSelectMarker` → load detail.
    /// Empty array ⇒ the map honestly frames CONUS with no pins.
    private var loadMarkerLayers: [HereMapLayer] {
        let markers: [HereMarker] = store.positions.compactMap { p in
            guard let fix = p.fix else { return nil }
            return HereMarker(
                at: fix,
                kind: .pickup,
                label: p.loadNumber ?? "LD-\(p.id)",
                id: String(p.id)
            )
        }
        guard !markers.isEmpty else { return [] }
        return [.markers(markers)]
    }

    /// Frame the lane spread: centroid of the plotted pickups when we
    /// have real coords, else honest CONUS center. No fabricated points
    /// ever feed this — an empty `positions` list keeps the wide view.
    private var mapCenter: HereLatLng {
        let fixes = store.positions.compactMap { $0.fix }
        guard !fixes.isEmpty else { return HereLatLng(39.5, -98.35) }
        let lat = fixes.map(\.lat).reduce(0, +) / Double(fixes.count)
        let lng = fixes.map(\.lng).reduce(0, +) / Double(fixes.count)
        return HereLatLng(lat, lng)
    }

    /// Tighten the zoom once there are pins to look at; stay wide (CONUS)
    /// when the board is empty so the situational view still reads as a map.
    private var mapZoom: Int {
        store.positions.isEmpty ? 4 : 5
    }

    /// Tap on a load pin → open that load's detail (205), mirroring the
    /// exception-row hand-off. `id` is the loads.id String the marker carries.
    private func openLoad(_ loadId: String) {
        guard let rowId = Int(loadId) else { return }
        NotificationCenter.default.post(
            name: .eusoShipperLoadOpen, object: nil,
            userInfo: ["loadId": rowId]
        )
    }

    @ViewBuilder
    private func modeFilterChips(overview: ControlTowerAPI.Overview) -> some View {
        let totalActive = overview.total.active
        let chips: [(ModeFilter, Int)] = [
            (.all,    totalActive),
            (.truck,  overview.truck.active + overview.truck.inTransit),
            (.rail,   overview.rail.active + overview.rail.inTransit),
            (.vessel, overview.vessel.active + overview.vessel.inTransit)
        ]
        HStack(spacing: 6) {
            ForEach(chips, id: \.0) { (mode, count) in
                modeChip(mode: mode, count: count)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func modeChip(mode: ModeFilter, count: Int) -> some View {
        let isActive = (mode == modeFilter)
        let label = "\(mode.label) · \(count)"
        Button(action: { tapModeChip(mode) }) {
            if isActive {
                Text(label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(LinearGradient.primary))
            } else {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
            }
        }
        .buttonStyle(.plain)
    }

    private func kpiStrip(overview: ControlTowerAPI.Overview, exceptionCount: Int) -> some View {
        HStack(spacing: 0) {
            kpiCell(label: "IN TRANSIT",
                    value: "\(overview.total.inTransit)",
                    valueStyle: .gradient,
                    trail: nil,
                    trailColor: nil)
            kpiDivider
            kpiCell(label: "EXCEPTIONS",
                    value: "\(exceptionCount)",
                    valueStyle: exceptionCount > 0 ? .danger : .neutral,
                    trail: exceptionCount > 0 ? "detention · late" : nil,
                    trailColor: palette.textSecondary)
            kpiDivider
            // EUSO-2108 — backend doesn't ship onTimeRate yet.
            kpiCell(label: "ON-TIME",
                    value: "-",
                    valueStyle: .neutral,
                    trail: "data pending",
                    trailColor: palette.textTertiary)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private enum ValueStyle { case gradient, danger, neutral }

    private func kpiCell(label: String,
                         value: String,
                         valueStyle: ValueStyle,
                         trail: String?,
                         trailColor: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Group {
                    switch valueStyle {
                    case .gradient: Text(value).foregroundStyle(LinearGradient.diagonal)
                    case .danger:   Text(value).foregroundStyle(Brand.danger)
                    case .neutral:  Text(value).foregroundStyle(palette.textPrimary)
                    }
                }
                .font(.system(size: 22, weight: .bold).monospacedDigit())
                if let trail, let trailColor {
                    Text(trail)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(trailColor)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kpiDivider: some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(width: 1, height: 36)
            .padding(.horizontal, 4)
    }

    // MARK: Exception peek — bottom sheet handle + danger wash + chips

    @ViewBuilder
    private func exceptionPeek(_ e: ControlTowerAPI.ExceptionsResponse) -> some View {
        let merged = e.truckExceptions + e.vesselExceptions
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(palette.textTertiary.opacity(0.32))
                .frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(merged.isEmpty ? palette.textTertiary : Brand.danger)
                    Text("Exceptions · \(e.totalExceptions)")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Button(action: tapViewAllExceptions) {
                        Text("View all")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View all exceptions")
                }
                if merged.isEmpty {
                    Text("No exceptions across modes.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                } else {
                    HStack(spacing: Space.s2) {
                        ForEach(merged.prefix(2)) { ex in
                            exceptionChip(ex)
                        }
                    }
                }
            }
            .padding(.horizontal, Space.s3)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s4)
        }
        .background(
            ZStack {
                palette.bgCard
                LinearGradient(colors: [Brand.danger.opacity(0.10),
                                        Brand.warning.opacity(0.10)],
                               startPoint: .leading, endPoint: .trailing)
            }
        )
        .overlay(alignment: .top) {
            Rectangle().fill(palette.borderFaint).frame(height: 1)
        }
    }

    private func exceptionChip(_ ex: ControlTowerAPI.ExceptionRow) -> some View {
        let badge = exceptionBadge(ex)
        let lane = exceptionLane(ex)
        return Button(action: { tapException(ex) }) {
            VStack(alignment: .leading, spacing: 4) {
                Text(badge)
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(Brand.danger)
                    .lineLimit(1)
                Text(lane)
                    .font(EType.caption)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Exception, \(badge), \(lane), load \(ex.id)")
    }

    private func exceptionBadge(_ ex: ControlTowerAPI.ExceptionRow) -> String {
        let kind = ex.exceptionType
            .replacingOccurrences(of: "_", with: " ")
            .uppercased()
        if let load = ex.loadNumber, load.uppercased().contains("UN") || kind.contains("HAZMAT") {
            return load
        }
        return kind
    }

    private func exceptionLane(_ ex: ControlTowerAPI.ExceptionRow) -> String {
        switch ex.mode {
        case "truck":
            let p = ex.pickupLocation
            let d = ex.deliveryLocation
            let lhs = [p?.city, p?.state].compactMap { $0 }.joined(separator: ", ")
            let rhs = [d?.city, d?.state].compactMap { $0 }.joined(separator: ", ")
            if lhs.isEmpty || rhs.isEmpty { return ex.loadNumber ?? "Truck #\(ex.rowId)" }
            return "\(lhs) → \(rhs)"
        case "vessel":
            return ex.bookingNumber ?? "Booking #\(ex.rowId)"
        default:
            return "Exception #\(ex.rowId)"
        }
    }

    // MARK: Supplemental sections (EXTRA-OK — preserved drilldown)

    private func supplementalSections(
        overview: ControlTowerAPI.Overview,
        exceptions: ControlTowerAPI.ExceptionsResponse,
        activity: [ControlTowerAPI.ActivityRow]
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            modeCardGrid(overview: overview)
            exceptionsCard(exceptions)
            activityCard(activity)
        }
        .padding(.horizontal, Space.s3)
        .padding(.top, Space.s5)
    }

    // MARK: BY MODE cards (truck / ocean / rail breakdown)

    private func modeCardGrid(overview o: ControlTowerAPI.Overview) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionEyebrow("BY MODE")
            VStack(spacing: Space.s2) {
                if modeFilter == .all || modeFilter == .truck {
                    modeCard(icon: "truck.box.fill", label: "Truck", counts: o.truck)
                }
                if modeFilter == .all || modeFilter == .vessel {
                    modeCard(icon: "ferry.fill", label: "Ocean", counts: o.vessel)
                }
                if modeFilter == .all || modeFilter == .rail {
                    modeCard(icon: "tram.fill", label: "Rail", counts: o.rail)
                }
            }
        }
    }

    private func modeCard(icon: String, label: String, counts: ControlTowerAPI.ModeCounts) -> some View {
        let total = counts.active + counts.inTransit + (counts.delivered ?? 0)
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(LinearGradient.diagonal.opacity(0.18))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    Text(label)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("\(total) total")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(palette.bgCardSoft))
                }
                HStack(spacing: 12) {
                    countCell(value: counts.active,    label: "ACTIVE",     color: Brand.info)
                    countCell(value: counts.inTransit, label: "IN TRANSIT", color: Brand.success)
                    if let d = counts.delivered {
                        countCell(value: d, label: "DELIVERED", color: palette.textTertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func countCell(value: Int, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Exceptions card (full merged list)

    private func exceptionsCard(_ e: ControlTowerAPI.ExceptionsResponse) -> some View {
        let merged = e.truckExceptions + e.vesselExceptions
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(merged.isEmpty ? palette.textTertiary : Brand.danger)
                Text("EXCEPTIONS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if !merged.isEmpty {
                    Text("\(merged.count)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(Brand.danger)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Brand.danger.opacity(0.15)))
                }
            }
            if merged.isEmpty {
                Text("No exceptions across modes.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Space.s4)
            } else {
                VStack(spacing: 6) {
                    ForEach(merged.prefix(8)) { ex in exceptionRow(ex) }
                }
                if merged.count > 8 {
                    Text("\(merged.count - 8) more · pull to refresh for the latest")
                        .font(EType.micro).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.top, 4)
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(merged.isEmpty
                              ? palette.borderFaint
                              : Brand.danger.opacity(0.4),
                              lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func exceptionRow(_ ex: ControlTowerAPI.ExceptionRow) -> some View {
        let modeIcon: String = (ex.mode == "truck") ? "truck.box.fill" : "ferry.fill"
        let title = exceptionLane(ex)
        let typeLabel = ex.exceptionType
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        return Button(action: { tapException(ex) }) {
            HStack(spacing: Space.s2) {
                Image(systemName: modeIcon)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 24)
                Text(title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Space.s2)
                Text(typeLabel)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Brand.danger))
            }
            .padding(Space.s2)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Brand.danger.opacity(0.08))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Activity card (recent updates across modes)

    private func activityCard(_ rows: [ControlTowerAPI.ActivityRow]) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("RECENT ACTIVITY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(rows.count)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            if rows.isEmpty {
                Text("No recent updates.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Space.s4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.prefix(15).enumerated()), id: \.element.id) { idx, r in
                        activityRow(r)
                        if idx < min(rows.count, 15) - 1 {
                            Divider().overlay(palette.borderFaint).padding(.leading, 32)
                        }
                    }
                }
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

    private func activityRow(_ r: ControlTowerAPI.ActivityRow) -> some View {
        let icon = r.mode == "truck" ? "truck.box.fill" : "ferry.fill"
        let status = (r.status ?? "")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        return HStack(spacing: Space.s2) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 20)
            Text(r.label ?? "-")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Space.s2)
            if !status.isEmpty {
                Text(status)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(palette.bgCardSoft))
                    .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 0.75))
            }
        }
        .padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Loading + error shells

    private var loadingShell: some View {
        VStack(spacing: Space.s3) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.3))
                    .frame(height: 80)
            }
        }
    }

    private func inlineError(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Control tower offline")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Text("Retry")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func sectionEyebrow(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.9)
            .foregroundStyle(palette.textTertiary)
    }

    // MARK: - Notification posts (§20.4 no dead buttons)

    private func tapModeChip(_ mode: ModeFilter) {
        withAnimation(.easeOut(duration: 0.18)) {
            modeFilter = mode
        }
        // observability post — telemetry only; real local effect is the
        // modeFilter mutation above which drives the BY MODE breakdown.
        NotificationCenter.default.post(
            name: .eusoShipperControlTowerMode,
            object: nil,
            userInfo: [
                "source": "212_ShipperControlTower",
                "mode": mode.rawValue,
                "shipperCompanyId": 1
            ]
        )
    }

    private func tapViewAllExceptions() {
        // Real action: jump to 201 ShipperLoads with "exception" as
        // the search query so the row list narrows to the actual
        // exception loads. Replaces openURL("…/control-tower/
        // exceptions") which 404'd. Telemetry post retained.
        NotificationCenter.default.post(
            name: .eusoShipperControlTowerViewAllExceptions,
            object: nil,
            userInfo: [
                "source": "212_ShipperControlTower",
                "shipperCompanyId": 1
            ]
        )
        // Park the SMART-back hand-off BEFORE posting the swap. 201 mounts
        // AFTER the surface consumes this post (the surface re-renders
        // `screenStack` first), so 201 can't catch a live notification —
        // it reads the parked origin on `.onAppear` instead and paints a
        // BespokeBackBar aimed at Control Tower ("212"). Routing into My
        // Loads from here is a PUSH from a Me-section surface, not a tab
        // tap, so the user must be able to get back to where they came
        // from. Without it, landing on My Loads stranded the driver
        // (founder 2026-06-02: "will irritate a truck driver to the max").
        // The bottom-nav "Loads" tab never sets this, so it stays
        // correctly back-button-free. `backTo` is also passed in userInfo
        // for the already-mounted case.
        ShipperLoadsNavContext.setPush(origin: "212", query: "exception")
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap, object: nil,
            userInfo: ["screenId": "201", "query": "exception", "backTo": "212"]
        )
    }

    private func tapException(_ ex: ControlTowerAPI.ExceptionRow) {
        // Real action: open the load detail (205) for this exception
        // row so the user lands on the load that's in trouble and can
        // act on it directly. Replaces openURL("…/exceptions/{id}")
        // which 404'd. Telemetry post retained.
        NotificationCenter.default.post(
            name: .eusoShipperControlTowerException,
            object: nil,
            userInfo: [
                "source": "212_ShipperControlTower",
                "mode": ex.mode,
                "rowId": ex.rowId,
                "exceptionType": ex.exceptionType,
                "shipperCompanyId": 1
            ]
        )
        NotificationCenter.default.post(
            name: .eusoShipperLoadOpen, object: nil,
            userInfo: ["loadId": ex.rowId]
        )
    }
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// Mode filter chip tap — switches the BY MODE breakdown.
    static let eusoShipperControlTowerMode               = Notification.Name("eusoShipperControlTowerMode")
    /// "View all" exceptions CTA tap — opens the full exceptions sheet.
    static let eusoShipperControlTowerViewAllExceptions  = Notification.Name("eusoShipperControlTowerViewAllExceptions")
    /// Per-exception chip / row tap — opens the exception detail sheet.
    static let eusoShipperControlTowerException          = Notification.Name("eusoShipperControlTowerException")
}

// MARK: - Previews

#Preview("212 · Shipper Control Tower · Dark") {
    ShipperControlTower()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("212 · Shipper Control Tower · Light") {
    ShipperControlTower()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
