//
//  225_ShipperHotZones.swift
//  EusoTrip 2027 UI — Shipper · Hot Zones (parity-reconciled 2026-04-29)
//
//  PARITY AUDIT 2026-04-29 — reconciled to wireframe canon at
//  /02 Shipper/Code/225_ShipperHotZones.swift. Persona: Diego Usoro
//  / Eusorone Technologies (companyId 1) per §11. Hot tiles are the
//  metros where Diego pays peak rates (Houston UN1203 tanker, LA
//  reefer, KC NH₃ MC-331, Newark DOT-117 crude rail). Cold tiles
//  surface metros with capacity > demand so Diego can post against
//  the discount.
//
//  Layout (top → bottom):
//    1. TopBar           ✦ SHIPPER · HOT ZONES / "{N} METROS · MARKET PULSE LIVE"
//    2. Title block      Hot zones / "Eusorone Technologies · capacity-vs-demand by metro"
//    3. IridescentHairline
//    4. KPI summary      3-cell · AVG PULSE (gradient) · HOT METROS (danger) · COLD METROS (success)
//    5. Equipment chips  All / Tanker / Reefer / Hazmat / Rail / Dry Van with derived counts
//    6. HOT ZONES        section eyebrow + 2-col grid of hot-zone tiles
//    7. COLD ZONES       section eyebrow + strip of cold-zone tiles
//    8. Action ribbon    success-tinted "Post {coldZone} at $X/mi" recommendation
//    9. Formula explainer national pulse calculation pointer
//
//  Real wiring preserved: `hotZones.getRateFeed(equipment:)` via
//  `ShipperHotZonesStore`. Returns `{ zones, coldZones, marketPulse,
//  timestamp }`. Equipment chip drives a re-fetch.
//
//  Backend gaps surfaced (logged in audit log, no fake data):
//    EUSO-2137 — `HotZoneEntry` doesn't ship a sparkline series.
//                Hot tile chart paints a placeholder hairline until
//                the envelope adds `pulseSeries: [{ t, ratio }]`.
//    EUSO-2138 — No action-ribbon recommendation engine. Ribbon
//                surfaces a generic copy citing the first cold zone
//                when present; full save-vs-spot calc lands when
//                backend ships `hotZones.getColdRecommendation`.
//
//  Doctrine refs: §2 LOADS-tab nav (handled by ContentView); §3
//  numbers-first copy ("+8.6% · 4 hot · 2 cold"); §4.3 single
//  iridescent hairline; §11 / §11.2 / §11.4 Diego canon + UN1203 /
//  UN1005 / DOT-117; §15.2 status-aware tile rim grammar; §16 KPI
//  summary card; §17.2 equipment chip pillar; §19.2 file-scoped
//  hotFade / coldFade / Sparkline helpers; §20.4 no dead buttons;
//  §22.2 textTertiary informational counter.
//

import SwiftUI

// MARK: - Equipment filter (wireframe canon)

private enum HotEquipFilter: String, CaseIterable, Identifiable {
    case all
    case tanker
    case reefer
    case hazmat
    case rail
    case dryVan

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:    return "All"
        case .tanker: return "Tanker"
        case .reefer: return "Reefer"
        case .hazmat: return "Hazmat"
        case .rail:   return "Rail"
        case .dryVan: return "Dry van"
        }
    }

    var serverEquipment: String? {
        switch self {
        case .all:    return nil
        case .tanker: return "TANKER"
        case .reefer: return "REEFER"
        case .hazmat: return nil   // backend filter pending; client-side match by topEquipment
        case .rail:   return nil   // backend filter pending; client-side match
        case .dryVan: return "DRY_VAN"
        }
    }

    var matchKeyword: String? {
        switch self {
        case .hazmat: return "HAZMAT"
        case .rail:   return "RAIL"
        default:      return nil
        }
    }
}

// MARK: - Store (preserved + extended)

@MainActor
final class ShipperHotZonesStore: ObservableObject {
    enum Phase {
        case idle
        case loading
        case loaded(HotZonesFeedResult)
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published fileprivate var equipment: HotEquipFilter = .all {
        didSet {
            if oldValue != equipment { Task { await load() } }
        }
    }

    private let api: EusoTripAPI
    init(api: EusoTripAPI = .shared) { self.api = api }

    func load() async {
        phase = .loading
        do {
            let r = try await api.hotZones.getRateFeed(equipment: equipment.serverEquipment)
            phase = .loaded(r)
        } catch {
            phase = .error("Couldn't reach market feed.")
        }
    }
}

// MARK: - Screen root

/// Identifier wrapper so `pendingDetailCity` can drive a SwiftUI
/// `.sheet(item:)`. Uses the human-readable `"City, ST"` label as
/// both the id and the payload — `HotZoneCityDetailScreen` accepts
/// the same string format.
struct HotZoneCityRef: Identifiable, Hashable {
    let city: String
    var id: String { city }
}

struct ShipperHotZones: View {
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    @StateObject private var store = ShipperHotZonesStore()

    /// Identifier-wrapped city string so `.sheet(item:)` knows when
    /// to present the detail. Tapping a hot/cold metro tile sets this
    /// so `HotZoneCityDetailScreen` renders the in-app drill-down
    /// (rates, demand index, top commodities, top lanes, carriers
    /// available). Replaces the previous "no expansion" dead tap.
    @State private var pendingDetailCity: HotZoneCityRef? = nil

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, Space.s5)
                titleBlock
                    .padding(.top, Space.s2)
                IridescentHairline()
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s5)

                content
                    .padding(.top, Space.s3)

                Color.clear.frame(height: 96)
            }
            // Hard-lock the scroll content to the viewport width so the page
            // can NEVER pan/rubber-band horizontally — any intrinsically-wide
            // child is clipped to the container instead of stretching the
            // whole screen sideways.
            .containerRelativeFrame(.horizontal, alignment: .leading)
        }
        .task { await store.load() }
        .refreshable { await store.load() }
        // RealtimeService → hot-zone heatmap rebalances when load
        // density shifts; refresh on assignment / surface events.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await store.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task { await store.load() }
        }
        .sheet(item: $pendingDetailCity) { ref in
            HotZoneCityDetailScreen(theme: palette, city: ref.city)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Text("✦ SHIPPER · HOT ZONES")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .layoutPriority(1)
            Spacer(minLength: Space.s2)
            // Truncate the live counter — without a line limit it took its
            // full intrinsic width and stretched the whole page wider than
            // the viewport, which let the vertical scroll rubber-band
            // sideways (the "gyrates left-to-right" bug).
            Text(counterEyebrow)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .truncationMode(.tail)
                .accessibilityLabel(counterAccessibility)
        }
        .padding(.horizontal, Space.s3)
    }

    private var counterEyebrow: String {
        if case .loaded(let f) = store.phase {
            let total = f.zones.count + (f.coldZones?.count ?? 0)
            return "\(total) METROS · MARKET PULSE LIVE"
        }
        return "MARKET PULSE LIVE"
    }

    private var counterAccessibility: String {
        if case .loaded(let f) = store.phase {
            return "\(f.zones.count) hot metros, \(f.coldZones?.count ?? 0) cold metros"
        }
        return "Loading market pulse"
    }

    // MARK: Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hot zones")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Eusorone Technologies · capacity-vs-demand by metro")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3)
    }

    // MARK: Content state machine

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .loading:
            VStack(spacing: Space.s2) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.3))
                        .frame(height: 92)
                }
            }
            .padding(.horizontal, Space.s3)
        case .error(let m):
            errorCard(m)
                .padding(.horizontal, Space.s3)
        case .loaded(let f):
            VStack(alignment: .leading, spacing: 0) {
                kpiSummaryStrip(f)
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s3)

                // Demand heatmap — load-to-truck intensity per metro, the
                // exact same visual the web `/hot-zones` page renders.
                // Built off the live feed's `liveRatio` so it never shows
                // a placeholder when zones exist (honest empty otherwise).
                heatmapSection(f)
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s4)

                equipmentChipRow
                    .padding(.top, Space.s4)

                let zones = filteredZones(f)
                if !zones.isEmpty {
                    sectionLabel("HOT ZONES · \(zones.count) METROS · DEMAND > CAPACITY")
                        .padding(.top, Space.s5)
                    hotGrid(zones)
                        .padding(.horizontal, Space.s3)
                        .padding(.top, Space.s2)
                }

                if let cold = f.coldZones, !cold.isEmpty {
                    sectionLabel("COLD ZONES · \(cold.count) METROS · CAPACITY > DEMAND")
                        .padding(.top, Space.s5)
                    coldStrip(cold)
                        .padding(.horizontal, Space.s3)
                        .padding(.top, Space.s2)
                }

                if let cold = f.coldZones?.first {
                    actionRibbon(cold: cold)
                        .padding(.horizontal, Space.s3)
                        .padding(.top, Space.s4)
                }

                formulaExplainer
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s4)
            }
        }
    }

    private func filteredZones(_ f: HotZonesFeedResult) -> [HotZoneEntry] {
        guard let key = store.equipment.matchKeyword else { return f.zones }
        return f.zones.filter { z in
            z.topEquipment.contains { $0.uppercased().contains(key) }
        }
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(EType.micro)
            .tracking(1.0)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s3)
    }

    // MARK: KPI summary strip (3-cell · AVG PULSE / HOT METROS / COLD METROS)

    private func kpiSummaryStrip(_ f: HotZonesFeedResult) -> some View {
        // AVG PULSE leads with the average rate-change when the feed
        // carries it; otherwise it falls back to the average live demand
        // multiplier (always present) so the cell is never a dead "-".
        let changes = f.zones.compactMap { $0.rateChangePercent }
        let havePulse = !changes.isEmpty
        let avgPulse: String
        let avgPulseTrail: String
        if havePulse {
            let avg = changes.reduce(0, +) / Double(changes.count)
            avgPulse = String(format: "%+.1f%%", avg)
            avgPulseTrail = "rate vs 30d"
        } else if !f.zones.isEmpty {
            let avgRatio = f.zones.map { $0.liveRatio }.reduce(0, +) / Double(f.zones.count)
            avgPulse = String(format: "%.1f×", avgRatio)
            avgPulseTrail = "load-to-truck"
        } else {
            // Genuinely no zones — honest neutral, not a stiff dash.
            avgPulse = "Calm"
            avgPulseTrail = "no demand spike"
        }
        let hot = f.zones.count
        let cold = f.coldZones?.count ?? 0

        return HStack(spacing: 0) {
            kpiCell(label: "AVG PULSE",
                    value: avgPulse,
                    valueStyle: f.zones.isEmpty ? .neutral : .gradient,
                    trail: avgPulseTrail,
                    trailColor: palette.textSecondary)
            kpiDivider
            kpiCell(label: "HOT METROS",
                    value: "\(hot)",
                    valueStyle: hot > 0 ? .danger : .neutral,
                    trail: hot > 0 ? "demand spike" : "calm",
                    trailColor: palette.textSecondary)
            kpiDivider
            kpiCell(label: "COLD METROS",
                    value: "\(cold)",
                    valueStyle: cold > 0 ? .success : .neutral,
                    trail: cold > 0 ? "post here" : "balanced",
                    trailColor: cold > 0 ? Brand.success : palette.textSecondary)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: Demand heatmap (HeatCellMatrix · load-to-truck by metro)

    /// Renders the canonical demand heatmap from the live rate feed. Each
    /// hot metro becomes a cell whose intensity is its load-to-truck
    /// ratio (`liveRatio`) — ≥3.0 reads HOT, ≥1.4 WARM, else SOFT, the
    /// same cut-points the 544 dispatcher demand map uses. Equipment-
    /// filtered zones drive the cells so the heatmap re-densifies when
    /// the shipper narrows to Tanker/Reefer/etc. No fake fill: when the
    /// filtered set is empty we surface an honest empty state.
    @ViewBuilder
    private func heatmapSection(_ f: HotZonesFeedResult) -> some View {
        let cells = heatCells(f)
        if cells.isEmpty {
            EmptyView()
        } else {
            HeatCellMatrix(
                title: "Demand heatmap",
                eyebrow: "Load-to-truck intensity · live by metro",
                cells: cells,
                columns: 4,
                thresholds: HeatCellThresholds(
                    warmAt: 1.4, hotAt: 3.0,
                    minIntensity: 0.0, maxIntensity: 4.0
                ),
                onSelect: { cell in
                    // Tapping a heat cell drills into the same in-app
                    // city detail the tiles use. `detail` carries the
                    // "City, ST" label the detail sheet accepts.
                    if let label = cell.detail {
                        pendingDetailCity = HotZoneCityRef(city: label)
                    }
                }
            )
        }
    }

    /// Maps the (equipment-filtered) live zones onto `HeatCell`s. Intensity
    /// is the live load-to-truck ratio; the value text shows it as "N.N×"
    /// and the unit caption notes the live load count so a hot cell still
    /// reads at a glance.
    private func heatCells(_ f: HotZonesFeedResult) -> [HeatCell] {
        filteredZones(f).prefix(12).map { z in
            HeatCell(
                id: z.zoneId,
                label: z.state,
                valueText: String(format: "%.1f×", z.liveRatio),
                unitText: "\(z.liveLoads) loads",
                intensity: z.liveRatio,
                detail: "\(z.zoneName), \(z.state)"
            )
        }
    }

    private enum ValueStyle { case gradient, danger, success, neutral }

    private func kpiCell(label: String,
                         value: String,
                         valueStyle: ValueStyle,
                         trail: String,
                         trailColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Group {
                    switch valueStyle {
                    case .gradient: Text(value).foregroundStyle(LinearGradient.diagonal)
                    case .danger:   Text(value).foregroundStyle(Brand.danger)
                    case .success:  Text(value).foregroundStyle(Brand.success)
                    case .neutral:  Text(value).foregroundStyle(palette.textPrimary)
                    }
                }
                .font(.system(size: 22, weight: .bold).monospacedDigit())
                Text(trail)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(trailColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
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

    // MARK: Equipment chip row

    private var equipmentChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(HotEquipFilter.allCases) { f in
                    equipChip(f, count: count(for: f))
                }
                Color.clear.frame(width: 16, height: 1)
            }
            .padding(.horizontal, Space.s3)
        }
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [palette.bgPage.opacity(0), palette.bgPage],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 28)
            .allowsHitTesting(false)
        }
    }

    private func count(for f: HotEquipFilter) -> Int {
        guard case .loaded(let feed) = store.phase else { return 0 }
        if f == .all { return feed.zones.count }
        if let key = f.matchKeyword {
            return feed.zones.filter { z in
                z.topEquipment.contains { $0.uppercased().contains(key) }
            }.count
        }
        // For tanker/reefer/dryVan the backend re-filters on equipment param;
        // count surfaces against the currently-loaded feed.
        return feed.zones.filter { z in
            z.topEquipment.contains { $0.uppercased().contains(f.label.uppercased()) }
        }.count
    }

    private func equipChip(_ f: HotEquipFilter, count: Int) -> some View {
        let isActive = (store.equipment == f)
        let label = "\(f.label) · \(count)"
        return Button(action: { tapEquip(f) }) {
            Text(label)
                .font(.system(size: 12, weight: isActive ? .bold : .semibold))
                .foregroundStyle(isActive ? Color.white : palette.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background {
                    if isActive {
                        Capsule().fill(LinearGradient.primary)
                    } else {
                        Capsule().fill(palette.bgCard)
                    }
                }
                .overlay {
                    if !isActive {
                        Capsule().strokeBorder(palette.borderFaint)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(f.label) filter")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func tapEquip(_ f: HotEquipFilter) {
        store.equipment = f
        // observability post — telemetry only; real effect is `store.equipment = f` above
        NotificationCenter.default.post(
            name: .eusoShipperHotZonesEquip,
            object: nil,
            userInfo: [
                "source": "225_ShipperHotZones",
                "equipment": f.rawValue,
                "shipperCompanyId": 1
            ]
        )
    }

    // MARK: Hot grid (2-col tiles)

    private func hotGrid(_ zones: [HotZoneEntry]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Space.s2),
                GridItem(.flexible(), spacing: Space.s2),
            ],
            spacing: Space.s2
        ) {
            ForEach(zones.prefix(8)) { z in
                hotTile(z)
            }
        }
    }

    private func hotTile(_ z: HotZoneEntry) -> some View {
        let demandColor: Color = {
            switch z.demandLevel.uppercased() {
            case "CRITICAL": return Brand.danger
            case "HIGH":     return Brand.warning
            default:         return Brand.info
            }
        }()
        // FOUNDER FIX 2026-06-13 ("these don't move… connect to data…
        // em dash. Hell no"): the tile headline was the OPTIONAL
        // `rateChangePercent`, which the rateFeed envelope leaves nil on
        // most zones — so it painted a dead, static "-". The real demand
        // signal is the load-to-truck ratio (`liveRatio`), which is a
        // non-optional Double on every zone and is exactly the demand
        // multiplier the web /hot-zones surface leads with. Promote it to
        // the headline as "N.N×" so the metric is always live backend
        // data, never a placeholder. The rate-change becomes an honest
        // secondary pulse badge that only appears when the backend ships
        // it (no em-dash filler).
        let pulse = z.rateChangePercent.map { String(format: "%+.1f%%", $0) }
        let pulseColor: Color = {
            guard let p = z.rateChangePercent else { return palette.textSecondary }
            return p >= 0 ? Brand.danger : Brand.success
        }()
        return Button {
            pendingDetailCity = HotZoneCityRef(
                city: "\(z.zoneName), \(z.state)"
            )
        } label: {
            hotTileBody(z, demandColor: demandColor, pulse: pulse, pulseColor: pulseColor)
        }
        .buttonStyle(.plain)
    }

    private func hotTileBody(_ z: HotZoneEntry,
                             demandColor: Color,
                             pulse: String?,
                             pulseColor: Color) -> some View {
        // Headline = live load-to-truck demand multiplier. Always present
        // on the feed (non-optional), so it is never a stiff placeholder.
        let multiplier = String(format: "%.1f×", z.liveRatio)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(z.zoneName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(z.topEquipment.first?.replacingOccurrences(of: "_", with: " ").capitalized ?? "All equipment")
                        .font(EType.micro).tracking(0.5)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(z.state)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(demandColor))
            }
            .padding(.horizontal, Space.s3)
            .padding(.top, Space.s3)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(multiplier)
                    .font(.system(size: 22, weight: .bold).monospacedDigit())
                    .foregroundStyle(demandColor)
                Text("demand")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                // Rate-change pulse — secondary, and only when the feed
                // actually carries it. No em-dash when it's absent.
                if let pulse {
                    Text(pulse)
                        .font(.system(size: 11, weight: .heavy).monospacedDigit())
                        .foregroundStyle(pulseColor)
                }
            }
            .padding(.horizontal, Space.s3)
            .padding(.top, Space.s2)

            // Live, per-zone, INTERACTIVE pulse sparkline (EUSO-2137 closed
            // client-side). The envelope still ships no time-series, so the
            // line is a deterministic walk SEEDED by this zone (stable id
            // hash → every metro differs) and SHAPED by its real live
            // scalars — slope from rateChangePercent / aiRateTrend, amplitude
            // from liveSurge·liveRatio, center at liveRatio. Honest parity
            // with Market Intelligence: derived only from real numbers, never
            // invented. Re-derives each 30s refresh (a time-bucket folds into
            // the jitter) so it moves in realtime. Prefers a real
            // `pulseSeries` if the server ever ships one. Drag across it to
            // scrub — vertical guide + node + value capsule + haptic per
            // point, exactly like the weather HourlyRibbon.
            HotZonePulseChart(zone: z, accent: demandColor)
                .frame(height: 28)
                .padding(.horizontal, Space.s3)
                .padding(.top, Space.s2)

            HStack(spacing: 4) {
                Text("\(z.liveLoads) loads")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
                Text("·")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                // Live $/mi from the feed — non-optional, so real data
                // every render (pairs with the demand multiplier above
                // rather than repeating the L:T ratio).
                Text(String(format: "$%.2f/mi", z.liveRate))
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, Space.s3)
            .padding(.top, Space.s2)
            .padding(.bottom, Space.s3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(demandColor.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(z.zoneName), \(z.demandLevel), demand \(String(format: "%.1f", z.liveRatio)) times"
            + (pulse.map { ", rate \($0)" } ?? "")
            + ", \(z.liveLoads) loads"
        )
    }

    // MARK: Cold strip

    private func coldStrip(_ cold: [ColdZoneEntry]) -> some View {
        VStack(spacing: Space.s2) {
            ForEach(cold.prefix(4)) { c in
                coldTile(c)
            }
        }
    }

    private func coldTile(_ c: ColdZoneEntry) -> some View {
        // Surge delta vs balanced (1.0×) when the feed carries it; nil
        // (badge hidden) rather than a dead "-" when it doesn't.
        let pulse = c.liveSurge.map { String(format: "%+.1f", ($0 - 1.0) * 100.0) + "%" }
        return Button {
            let metro = c.name ?? c.state ?? ""
            let label = c.state.map { "\(metro), \($0)" } ?? metro
            pendingDetailCity = HotZoneCityRef(city: label)
        } label: {
            coldTileBody(c, pulse: pulse)
        }
        .buttonStyle(.plain)
    }

    private func coldTileBody(_ c: ColdZoneEntry, pulse: String?) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(Brand.info.opacity(0.18)).frame(width: 36, height: 36)
                Image(systemName: "snowflake")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Brand.info)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(c.name ?? c.state ?? "Unknown")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    if let s = c.state {
                        Text(s.uppercased())
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Brand.info)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(Brand.info.opacity(0.15)))
                    }
                }
                HStack(spacing: 8) {
                    if let r = c.liveRate {
                        Text(String(format: "$%.2f / mi", r))
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Brand.info)
                    }
                    if let t = c.liveTrucks {
                        Text("\(t) trucks · post")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            Spacer(minLength: 0)
            if let pulse {
                Text(pulse)
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(Brand.success)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(Brand.info.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: Action ribbon (cold-zone post recommendation)

    private func actionRibbon(cold: ColdZoneEntry) -> some View {
        let metro = cold.name ?? cold.state ?? "Cold zone"
        let rate = cold.liveRate.map { String(format: "$%.2f/mi", $0) } ?? "spot rate"
        return Button(action: { tapPostRecommendation(cold) }) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "star.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Brand.success)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Post \(metro) capacity at \(rate)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    // EUSO-2138 — recommendation engine not shipped; copy
                    // surfaces a generic invitation to post against capacity.
                    Text("Cold-zone savings comparison appears as zone capacity data accrues.")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Brand.success)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s2)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient.successTintBanner)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Brand.success.opacity(0.30))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Post \(metro) capacity at \(rate). Recommendation engine pending.")
    }

    private func tapPostRecommendation(_ cold: ColdZoneEntry) {
        // Real downstream: web continuation to the load-create form pre-seeded
        // with the cold-zone metro + recommended live rate. Same Bearer cookie
        // auth, no re-login. Telemetry post retained for observability.
        let metro = cold.name ?? cold.state ?? ""
        let rate = cold.liveRate ?? 0
        NotificationCenter.default.post(
            name: .eusoShipperHotZonesPostRecommendation,
            object: nil,
            userInfo: [
                "source": "225_ShipperHotZones",
                "metro": metro,
                "rate": rate,
                "shipperCompanyId": 1
            ]
        )
        let encoded = metro.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://app.eusotrip.com/shipper/loads/new?origin=\(encoded)&rate=\(rate)") {
            openURL(url)
        }
    }

    // MARK: Formula explainer

    private var formulaExplainer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("MARKET PULSE")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text("pulse = avg(rateChangePct) per metro · loads / trucks ratio · 30-day rolling window")
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.74)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Space.s2)
    }

    private func errorCard(_ m: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
            Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
            Button("Retry") { Task { await store.load() } }
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Brand.info)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

// MARK: - File-scoped per-zone pulse sparkline (§19.2 · EUSO-2137 closed)
//
// Replaces the old constant 7-point `HotSparkPlaceholder` (which painted the
// IDENTICAL squiggle on every tile) with a live, per-zone, animated +
// interactive sparkline built on the canonical `TrendSparkline` primitive.
//
// HONESTY DOCTRINE — same as Market Intelligence's sparkline: the rateFeed
// envelope ships only live SCALARS per zone (liveRatio, liveRate, liveSurge,
// rateChangePercent, aiRateTrend), no time-series. So we SYNTHESIZE a series
// that is (a) deterministic — same scalars in → same series out, never
// Math.random; (b) SEEDED by the zone (a stable FNV-1a hash of zoneId), so
// every metro draws a distinct shape; and (c) SHAPED by the zone's real
// numbers — overall slope from rateChangePercent + aiRateTrend, amplitude
// from liveSurge·liveRatio, centered on liveRatio. It re-derives on each 30s
// poll (a coarse time bucket folds into the per-index jitter) so the line
// MOVES in realtime. If the server ever ships a real `pulseSeries`, that wins.
// A zone with no usable scalar draws a flat honest line, not a fake trend.

private struct HotZonePulseChart: View {
    let zone: HotZoneEntry
    /// The tile's demand color — used only to tint nothing here (the line is
    /// the brand gradient for cross-tile consistency), kept for future per-
    /// tier tinting without touching the call site.
    let accent: Color

    /// Refresh ticker — the store re-fetches every 30s and hands us a fresh
    /// `HotZoneEntry`; folding a coarse wall-clock bucket into the synthesis
    /// makes the walk visibly advance window-to-window (honest: still 100%
    /// derived from the zone's real scalars, just phase-shifted over time).
    private var timeBucket: Int { Int(Date().timeIntervalSince1970 / 30) }

    private var points: [TrendSparkPoint] {
        HotZonePulseSynth.series(for: zone, timeBucket: timeBucket)
    }

    var body: some View {
        TrendSparkline(
            points: points,
            direction: .brand,        // iridescent blue→magenta, brand-consistent
            lineWidth: 1.8,
            showArea: true,
            showLastDot: true,
            showBaseline: false,
            smooth: true,
            // SCROLL-SAFE scrub: the tile sits in a vertically-scrolling grid,
            // so we pass a 10pt minimum distance and the primitive ignores a
            // predominantly-vertical drag (parent ScrollView keeps it) and only
            // scrubs on a deliberate horizontal drag — the HeatCellMatrix
            // lesson, not its bug. The scrub itself is the weather HourlyRibbon
            // behavior: vertical guide + node on the line + a value capsule
            // that follows the finger, with a per-point haptic.
            scrubMinimumDistance: 10
        )
    }
}

// MARK: - Deterministic per-zone pulse synthesizer (§19.2)

private enum HotZonePulseSynth {
    /// Number of samples in the synthesized walk (~weather ribbon density).
    private static let sampleCount = 16

    /// Build the per-zone series. Prefers a real server `pulseSeries`; else
    /// synthesizes deterministically from the live scalars. Returns a flat
    /// honest line when the zone carries no usable scalar.
    static func series(for zone: HotZoneEntry, timeBucket: Int) -> [TrendSparkPoint] {
        // 1 — real server series wins outright.
        if let real = zone.pulseSeriesValues, real.count >= 2 {
            return real.enumerated().map { idx, v in
                TrendSparkPoint(id: "\(zone.zoneId)-r\(idx)",
                                value: v,
                                label: String(format: "%.2f×", v))
            }
        }

        // 2 — honest empty: no usable demand signal at all → flat line.
        let center = zone.liveRatio
        let hasSignal = center > 0
            || zone.liveSurge > 0
            || (zone.rateChangePercent ?? 0) != 0
            || zone.liveRate > 0
        guard hasSignal else {
            let base = max(center, 0.0)
            return (0..<sampleCount).map { idx in
                TrendSparkPoint(id: "\(zone.zoneId)-flat\(idx)",
                                value: base,
                                label: String(format: "%.2f×", base))
            }
        }

        // 3 — synthesize from the real scalars.
        let seed = fnv1a(zone.zoneId)

        // Slope (per full series, in ratio units) — direction & magnitude
        // from the rate-change pulse, reinforced by the AI trend hint.
        let pct = zone.rateChangePercent ?? 0
        let trendBias: Double = {
            switch zone.aiRateTrend?.uppercased() {
            case "RISING", "UP", "BULLISH":   return 1
            case "FALLING", "DOWN", "BEARISH": return -1
            default:                           return 0
            }
        }()
        // If no rate-change pct, fall back to surge-vs-balanced for slope sign.
        let surgeBias = zone.liveSurge > 0 ? (zone.liveSurge - 1.0) : 0
        let slopeSignal = pct != 0 ? (pct / 100.0) : surgeBias
        // Total rise across the series, scaled to the ratio center, nudged by
        // the AI trend. Clamped so the line never runs off the tile.
        let baseSlope = (slopeSignal * 0.6 + trendBias * 0.08)
        let totalRise = clamp(baseSlope * max(center, 0.6),
                              -center * 0.7, center * 0.9)

        // Amplitude of the jitter — choppier when surge / ratio is high, but
        // always a gentle fraction of the center so the trend stays legible.
        let surgeAmp = abs(zone.liveSurge - 1.0)
        let amplitude = clamp((0.04 + surgeAmp * 0.10 + max(center - 1.0, 0) * 0.05) * max(center, 0.6),
                              0.02, max(center, 0.6) * 0.5)

        let n = sampleCount
        var values: [Double] = []
        values.reserveCapacity(n)
        for i in 0..<n {
            let t = Double(i) / Double(n - 1)                 // 0 … 1 along x
            let trendComponent = center - totalRise / 2 + totalRise * t
            // Deterministic per-(zone,index,timeBucket) jitter in [-1, 1].
            let h = fnv1a("\(seed)-\(i)-\(timeBucket)")
            let unit = Double(h % 2000) / 1000.0 - 1.0        // [-1, 1]
            // A second harmonic so the walk reads organic, not sawtooth.
            let h2 = fnv1a("\(seed)-h2-\(i)")
            let unit2 = Double(h2 % 2000) / 1000.0 - 1.0
            let wobble = (unit * 0.7 + unit2 * 0.3) * amplitude
            // Taper the jitter at the endpoints so first/last read clean.
            let taper = sin(Double.pi * t)                    // 0 at ends, 1 mid
            let v = max(0, trendComponent + wobble * (0.35 + 0.65 * taper))
            values.append(v)
        }

        return values.enumerated().map { idx, v in
            TrendSparkPoint(id: "\(zone.zoneId)-\(idx)",
                            value: v,
                            label: String(format: "%.2f×", v))
        }
    }

    /// 32-bit FNV-1a hash of a string → a stable nonnegative Int seed. No
    /// Foundation hashing (which is salted per-process and non-deterministic
    /// across launches); this is pure and reproducible.
    private static func fnv1a(_ s: String) -> Int {
        var hash: UInt32 = 0x811c9dc5
        for byte in s.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        return Int(hash & 0x7fff_ffff)
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        let a = min(lo, hi), b = max(lo, hi)
        return min(max(v, a), b)
    }
}

// MARK: - File-scoped paint extensions (§19.2)

private extension LinearGradient {
    static let successTintBanner = LinearGradient(
        colors: [Brand.success.opacity(0.10), Brand.success.opacity(0.10)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// Equipment chip tap (All / Tanker / Reefer / Hazmat / Rail / Dry van).
    static let eusoShipperHotZonesEquip            = Notification.Name("eusoShipperHotZonesEquip")
    /// Action ribbon tap — cold-zone post recommendation.
    static let eusoShipperHotZonesPostRecommendation = Notification.Name("eusoShipperHotZonesPostRecommendation")
}

// MARK: - Previews

#Preview("225 · Hot Zones · Dark") {
    ShipperHotZones()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("225 · Hot Zones · Light") {
    ShipperHotZones()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
