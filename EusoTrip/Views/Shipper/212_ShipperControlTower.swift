//
//  212_ShipperControlTower.swift
//  EusoTrip 2027 UI — Shipper · Control Tower (parity-reconciled 2026-04-29)
//
//  PARITY AUDIT 2026-04-29. Reconciled to wireframe canon at
//  /02 Shipper/Code/212_ShipperControlTower.swift. The map hero
//  uses the live HERE renderer and real load pickup positions for
//  the flagship visibility surface.
//
//  Layout (top → bottom):
//    1. TopBar           ✦ SHIPPER · CONTROL TOWER · LIVE / "{N} EXCEPTIONS · {N} IN TRANSIT" (danger)
//    2. Title block      Control Tower / "{X} active · {N} in transit · all modes"
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
//  Doctrine refs: ME nav handled by ContentView; numbers-first
//  production copy; single full-bleed map hero; width-locked chip +
//  KPI grammar; no dead buttons.
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

    /// Count of caller loads currently inside active weather, surfaced by
    /// the same `getActivePositions` proc (Waves 1-3b-server). This is the
    /// real `weatherAffected` field — honest 0 when the weather feeds are
    /// enterprise-gated (the WEATHER KPI cell reads "0" not a fabrication).
    @Published private(set) var weatherAffected: Int = 0

    /// One active-load map position. Mirrors the
    /// `controlTower.getActivePositions` row shape. `lat`/`lng` come
    /// straight off `loads.pickupLocation` (real geocoded DB coords).
    ///
    /// 2026-06-14 (Waves 1-3b-server LIVE): the proc now decorates each
    /// position with the weather feeds' per-load read —
    /// `riskTier` (the §3 none/watch/elevated/severe ladder),
    /// `weatherHeadline` (the active corridor advisory headline), and
    /// `weatherAvailable` (enterprise gate). All three are OPTIONAL: the
    /// weather feeds are enterprise-gated, so today they decode `nil` /
    /// `available:false` and the screen reads honestly (no pins, KPI 0).
    struct ActiveLoadPosition: Decodable, Identifiable, Hashable {
        let id: Int
        let loadNumber: String?
        let status: String?
        let mode: String?
        let lat: Double
        let lng: Double
        // Weather decoration (Waves 1-3b-server). Absent today (gated).
        let riskTierRaw: String?
        let weatherHeadline: String?
        let weatherAvailable: Bool?

        enum CodingKeys: String, CodingKey {
            case id, loadNumber, status, mode, lat, lng
            case riskTierRaw = "riskTier"
            case weatherHeadline, weatherAvailable
        }

        /// Null-island gate (013:427 doctrine) — a load whose pickup is
        /// (0,0) is un-geocoded; drop it rather than frame the Atlantic.
        var fix: HereLatLng? {
            guard let coordinate = LatLongParser.validatedCoordinate(
                latitude: lat,
                longitude: lng
            ) else { return nil }
            return HereLatLng(coordinate.latitude, coordinate.longitude)
        }

        /// The §3 risk ladder resolved off the wire string. Honest `.none`
        /// when the key is absent (gated) — never a fabricated severity.
        var riskTier: LaneRiskTier { LaneRiskTier(server: riskTierRaw) }

        /// A storm-grade pickup: only elevated/severe earns a map pin so
        /// the control-tower map flags genuine weather exposure, not noise.
        /// `watch`/`none` (and the gated `nil` case) draw no pin.
        var isStormPin: Bool {
            riskTier == .elevated || riskTier == .severe
        }
    }

    private struct ActivePositionsEnvelope: Decodable {
        let positions: [ActiveLoadPosition]
        let total: Int
        /// Caller's in-flight loads currently inside active weather, from
        /// the same proc (Waves 1-3b-server). Optional → honest 0 today.
        let weatherAffected: Int?
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
            // Real weatherAffected count off the same proc. Gated → 0.
            weatherAffected = envelope?.weatherAffected ?? 0

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
        .eusoRefreshable { await store.refresh() }
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
            return "loaded-\(o.total.active)-\(o.total.inTransit)-\(e.totalExceptions)-\(a.count)-wx\(store.weatherAffected)-st\(stormPositions.count)"
        }
    }

    // MARK: TopBar (gradient eyebrow + danger-tinted exception+transit counter)

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            EusoTripEyebrow(verbatim: "SHIPPER · CONTROL TOWER · LIVE")
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
                addOns: modeFilter == .truck ? .shipperTracking : .weather,
                mapModeContext: {
                    switch modeFilter {
                    case .truck: return .primary(.truck)
                    case .rail: return .primary(.rail)
                    case .vessel: return .primary(.vessel)
                    case .all: return .intermodal(activeSegment: nil)
                    }
                }(),
                // `getActivePositions` currently returns geocoded pickup
                // anchors, not asset observations. Keep Live Operations
                // honest until an authorized telemetry feed is wired.
                liveOperationsStatus: .noAuthorizedFeed,
                onSelectMarker: { loadId in openLoad(loadId) }
            )
                .frame(height: 380)
                .clipped()
                .accessibilityLabel("Active load pickup map, \(overview.total.active) active loads, \(visibleMapPositions.count) plotted, no authorized live feed")

            VStack(alignment: .leading, spacing: Space.s3) {
                modeFilterChips(overview: overview)
                kpiStrip(overview: overview, exceptionCount: exceptionCount)
            }
            .padding(.horizontal, Space.s3)
            .padding(.top, 10)
        }
        // Bespoke on-map storm legend — the WeatherIcons storm glyph + a
        // real count of elevated/severe pickups now pinned on the map.
        // Honestly absent when no position is storm-grade (gated today).
        .overlay(alignment: .bottomTrailing) {
            if !stormPositions.isEmpty {
                stormMapLegend(count: stormPositions.count)
                    .padding(.trailing, Space.s3)
                    .padding(.bottom, Space.s3)
            }
        }
    }

    /// Bespoke storm-legend chip pinned to the map — the WeatherIcons
    /// `.storm` condition glyph + the count of storm-grade pickups now on
    /// the map. Width-locked chip grammar (§17.2). Never shown at count 0.
    private func stormMapLegend(count: Int) -> some View {
        HStack(spacing: 6) {
            WeatherIcons.symbolView(for: 8000, size: 16)
            Text("\(count) storm")
                .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(
            Capsule().fill(Brand.danger.opacity(0.92))
        )
        .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.75))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) pickups in elevated or severe weather, pinned on the map")
    }

    // MARK: Map data plumbing (real loads.pickupLocation coords)

    /// Mode chips filter pickup anchors using the row's explicit mode. Barge
    /// participates only after the user explicitly selects the Vessel product;
    /// unknown rows stay visible only in the unresolved All view.
    private var visibleMapPositions: [ControlTowerStore.ActiveLoadPosition] {
        store.positions.filter { position in
            let mode = EusoTripMapTransportMode(canonicalValue: position.mode)
            switch modeFilter {
            case .all: return true
            case .truck: return mode == .truck
            case .rail: return mode == .rail
            case .vessel: return mode == .vessel || mode == .barge
            }
        }
    }

    /// The base-layer markers fed into the hero map — one `.pickup` pin
    /// per active load, positioned by the real `loads.pickupLocation`
    /// lat/lng (`controlTower.getActivePositions`). Each pin carries the
    /// load `id` so its tap routes through `onSelectMarker` → load detail.
    /// Empty array ⇒ the map honestly frames CONUS with no pins.
    ///
    /// 2026-06-14 (Waves 1-3b-server): a SECOND, weather-grade layer is
    /// appended — one `.weather` pin per pickup whose §3 `riskTier` is
    /// elevated/severe (`isStormPin`), positioned at the SAME real
    /// geocoded coords. These ride the canonical native weather-disc
    /// marker (coordinate-accurate; the renderer projects them). When the
    /// weather feeds are gated (no riskTier on any position), this layer
    /// is empty → no storm pins, exactly as honest as the KPI 0.
    private var loadMarkerLayers: [HereMapLayer] {
        let markers: [HereMarker] = visibleMapPositions.compactMap { p in
            guard let fix = p.fix else { return nil }
            return HereMarker(
                at: fix,
                kind: .pickup,
                label: p.loadNumber ?? "LD-\(p.id)",
                id: String(p.id)
            )
        }
        let storms: [HereMarker] = stormPositions.compactMap { p in
            guard let fix = p.fix else { return nil }
            return HereMarker(
                at: fix,
                kind: .weather,
                label: p.weatherHeadline ?? p.loadNumber ?? "LD-\(p.id)",
                id: String(p.id)
            )
        }
        var layers: [HereMapLayer] = []
        if !markers.isEmpty { layers.append(.markers(markers)) }
        if !storms.isEmpty { layers.append(.markers(storms)) }
        return layers
    }

    /// Active positions flagged elevated/severe by the §3 risk ladder —
    /// the storm-grade pickups. Empty when the weather feeds are gated.
    private var stormPositions: [ControlTowerStore.ActiveLoadPosition] {
        visibleMapPositions.filter { $0.isStormPin }
    }

    /// Frame the lane spread: centroid of the plotted pickups when we
    /// have real coords, else honest CONUS center. No fabricated points
    /// ever feed this — an empty `positions` list keeps the wide view.
    private var mapCenter: HereLatLng {
        let fixes = visibleMapPositions.compactMap { $0.fix }
        guard !fixes.isEmpty else { return HereLatLng(39.5, -98.35) }
        let lat = fixes.map(\.lat).reduce(0, +) / Double(fixes.count)
        let lng = fixes.map(\.lng).reduce(0, +) / Double(fixes.count)
        return HereLatLng(lat, lng)
    }

    /// Tighten the zoom once there are pins to look at; stay wide (CONUS)
    /// when the board is empty so the situational view still reads as a map.
    private var mapZoom: Int {
        visibleMapPositions.isEmpty ? 4 : 5
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
        // Horizontally scrollable. As a plain HStack the four chips
        // ("All · N", "Truck · N", "Rail · N", "Vessel · N") exceed the width
        // this row actually gets — it is overlaid on the map inside a padded
        // VStack — so SwiftUI squeezed them into each other and the labels
        // collided. A Spacer cannot help once the content is already too wide;
        // it only donates space it does not have. Scrolling also keeps the row
        // correct if a mode is added later.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(chips, id: \.0) { (mode, count) in
                    modeChip(mode: mode, count: count)
                }
            }
            .padding(.trailing, Space.s3)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
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
            // WEATHER: real `weatherAffected` count from getActivePositions.
            // Bespoke WeatherIcons storm glyph leads the value; honest 0
            // (neutral) when none/gated.
            kpiCell(label: "WEATHER",
                    value: "\(store.weatherAffected)",
                    valueStyle: store.weatherAffected > 0 ? .danger : .neutral,
                    trail: store.weatherAffected > 0 ? "in active wx" : nil,
                    trailColor: palette.textSecondary,
                    glyphCode: store.weatherAffected > 0 ? 8000 : nil)
            kpiDivider
            kpiCell(label: "PINS",
                    value: "\(store.positions.count)",
                    valueStyle: store.positions.isEmpty ? .neutral : .gradient,
                    trail: "on map",
                    trailColor: palette.textSecondary)
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
                         trailColor: Color?,
                         glyphCode: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let glyphCode {
                    WeatherIcons.symbolView(for: glyphCode, size: 16)
                        .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 3 }
                }
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
                if merged.isEmpty && stormWeatherExceptions.isEmpty {
                    Text("No exceptions across modes.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                } else {
                    if !merged.isEmpty {
                        HStack(spacing: Space.s2) {
                            ForEach(merged.prefix(2)) { ex in
                                exceptionChip(ex)
                            }
                        }
                    }
                    // Weather loads as exception chips — the elevated/severe
                    // pickups from getActivePositions (Waves 1-3b-server),
                    // surfaced alongside the ETA/late exceptions. Bespoke
                    // WeatherIcons storm glyph; honestly absent when gated.
                    if !stormWeatherExceptions.isEmpty {
                        HStack(spacing: Space.s2) {
                            ForEach(stormWeatherExceptions.prefix(2)) { p in
                                weatherExceptionChip(p)
                            }
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

    /// Weather-grade pickups surfaced as exception entries — elevated/
    /// severe §3 riskTier off `getActivePositions`. Empty when the feeds
    /// are gated, so the weather-chip row honestly disappears.
    private var stormWeatherExceptions: [ControlTowerStore.ActiveLoadPosition] {
        stormPositions
    }

    /// Bespoke weather exception chip — WeatherIcons storm glyph + the
    /// risk tier badge + the live corridor headline (or the load lane).
    /// Taps open that load's detail, mirroring the ETA-exception chip.
    private func weatherExceptionChip(_ p: ControlTowerStore.ActiveLoadPosition) -> some View {
        let tier = p.riskTier
        let badge = tier.rawValue.uppercased()
        let headline = (p.weatherHeadline?.isEmpty == false)
            ? p.weatherHeadline!
            : (p.loadNumber ?? "LD-\(p.id)")
        return Button(action: { openLoad(String(p.id)) }) {
            HStack(spacing: 6) {
                WeatherIcons.symbolView(for: 8000, size: 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text(badge)
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.4)
                        .foregroundStyle(tier.color)
                        .lineLimit(1)
                    Text(headline)
                        .font(EType.caption)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(tier.color.opacity(0.45))
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Weather exception, \(badge), \(headline), load \(p.id)")
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
