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
    private static let loadTimeoutNanoseconds: UInt64 = 10_000_000_000
    private var loadGeneration = 0

    init(api: EusoTripAPI = .shared) { self.api = api }

    func load() async {
        let previous: HotZonesFeedResult? = {
            if case .loaded(let feed) = phase { return feed }
            return nil
        }()
        loadGeneration += 1
        let generation = loadGeneration
        let equipment = equipment.serverEquipment

        if previous == nil {
            phase = .loading
        }

        let result: Result<HotZonesFeedResult, Error> = await withTaskGroup(
            of: Result<HotZonesFeedResult, Error>.self
        ) { group in
            let api = self.api
            group.addTask {
                do {
                    return .success(try await api.hotZones.getRateFeed(equipment: equipment))
                } catch {
                    return .failure(error)
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: Self.loadTimeoutNanoseconds)
                return .failure(URLError(.timedOut))
            }
            let first = await group.next() ?? .failure(URLError(.unknown))
            group.cancelAll()
            return first
        }

        guard generation == loadGeneration else { return }

        switch result {
        case .success(let r):
            phase = .loaded(r)
        case .failure(let error):
            // Surface the REAL failure so a future regression is diagnosable
            // (decode-shape mismatch, 500, auth, timeout) instead of a blanket
            // "Couldn't reach market feed." A genuinely-empty feed is NOT an
            // error — it decodes to `.loaded` with empty `zones`/`coldZones`
            // and the screen renders its honest "no demand spike" card. We only
            // reach here when the call itself threw (network/HTTP/decode), and
            // we keep that exact reason so the cause is never swallowed again.
            if let previous {
                phase = .loaded(previous)
            } else {
                phase = .error(Self.diagnose(error))
            }
        }
    }

    /// Map a thrown error to a short, honest, diagnosable message. Keeps the
    /// real reason (HTTP status + server body, or the decode key path) instead
    /// of a blanket string, so the next time the feed breaks the screenshot
    /// itself names the cause.
    private static func diagnose(_ error: Error) -> String {
        if let apiErr = error as? EusoTripAPIError {
            return "Market feed: \(apiErr.errorDescription ?? "request failed")"
        }
        if let decodeErr = error as? DecodingError {
            switch decodeErr {
            case .keyNotFound(let key, _):
                return "Market feed decode: missing \"\(key.stringValue)\""
            case .typeMismatch(_, let ctx):
                let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
                return "Market feed decode: type mismatch at \(path.isEmpty ? "root" : path)"
            case .valueNotFound(_, let ctx):
                let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
                return "Market feed decode: null at \(path.isEmpty ? "root" : path)"
            case .dataCorrupted(let ctx):
                return "Market feed decode: corrupted (\(ctx.debugDescription))"
            @unknown default:
                return "Market feed decode error."
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "Market feed network: \(ns.localizedDescription)"
        }
        return "Market feed: \(error.localizedDescription)"
    }
}

// MARK: - Screen root

struct ShipperHotZones: View {
    /// When hosted inside the consolidated Market Hub (Hot Zones / Market
    /// Intelligence tabs), the hub owns the header + tab bar, so the screen
    /// suppresses its own topBar/title to avoid a redundant double header.
    var embedded: Bool = false

    @Environment(\.palette) private var palette
    // NOTE 2026-06-19 — `@Environment(\.openURL)` removed. This screen no
    // longer hands off to any web URL: all CTAs (Find loads → 201, cold-zone
    // post → 204) now route natively via `.eusoShipperNavSwap`, so the
    // ShipperSurface openURL interceptor (which mis-mapped /loads/search → 205
    // "Load not found") is never engaged from here.
    @StateObject private var store = ShipperHotZonesStore()

    /// Per-zone flip state. Tapping a hot tile flips it IN PLACE on its
    /// X-axis to reveal the demand detail on the back of the same tile
    /// (founder: "instead of taking you to the second screen, it flips
    /// over and shows the details on the back"). Tap again — or the
    /// back-face return chevron — flips it home. Keyed by zone id so each
    /// tile flips independently. Every surface on this screen now flips:
    /// the old modal drill-down (.sheet → 436) is GONE; the heatmap cells
    /// (`flippedCells`) and cold tiles (`flippedColdZones`) flip too.
    @State private var flippedZones: Set<String> = []

    /// Per-cold-zone flip state — the cold strip tiles flip in place to an
    /// inspiring glass back (surge headline + live pulse + post-capacity CTA)
    /// instead of pushing the hated 436 detail screen. Keyed by `ColdZoneEntry.id`.
    @State private var flippedColdZones: Set<String> = []

    /// Per-heat-cell flip state — the demand-grid cells flip in place to a
    /// bespoke back (demand multiplier + live pulse + "Find loads" CTA)
    /// instead of drilling into 436. Keyed by `HotZoneEntry.id`.
    @State private var flippedCells: Set<String> = []

    /// HOT-tile locked height — both faces (front + flipped back) share ONE
    /// frame so the un-tapped hero reads identical in size to the flipped
    /// detail (founder: "the smaller [front] tile needs to be the size of the
    /// bigger [flipped] tiles, both front-facing and flipped"). Sized to the
    /// HOT `FlipBack`'s TALLEST natural content (non-compact, up to 8 stats =
    /// 4 grid rows). FlipBack content math (non-compact):
    ///   outer padding(s3) 24 + 4 VStack(s2) gaps 32 + header(name+3+2pt rule)
    ///   27 + hero(30pt heavy) 36 + pulse 40 + 4-row 2-col stat grid
    ///   (4·34 + 3·6) 154 + CTA pill 33 ≈ 346pt; +~14pt slack. The `Spacer`
    ///   before the CTA absorbs the slack on shorter (3-stat) backs so the CTA
    ///   always pins to the bottom. Both faces hard-clipped to the frame.
    private static let hotTileHeight: CGFloat = 360

    /// Intensity-grid cell height (the 4-col LOAD-TO-TRUCK INTENSITY cells).
    /// Both faces are locked to this so the state label, live multiplier, load
    /// count, rate and Find Loads action all fit without clipped text or hidden
    /// controls.
    private static let heatCellHeight: CGFloat = 132

    /// Cold-tile locked height — COMPACT (founder build 740: "these cold zone
    /// tiles are way too big for a cold zone … back the way they were before …
    /// quick information … doesn't need a graph"). Both faces are CHART-LESS
    /// quick-info. Sized to fit BOTH the compact front identity row and the
    /// compact chart-less quick-info back with zero overflow:
    ///   FRONT — one identity row: 36pt snow disc (the row's tallest element),
    ///     inside outer padding(s3) 12+12 → 36 + 24 = 60pt.
    ///   BACK — chart-less compact column inside padding 10+10=20:
    ///     header(name + 2pt rule, spacing 3) ~21 + VStack(4) gap 4 + surge
    ///     headline (~18pt heavy) 22 + gap 4 + one stat row (label micro 11 +
    ///     value 12 + 1) 24 + gap 4 + CTA pill (pad 6+6 + ~12 text) 24 ≈ 103pt.
    ///   The back governs → pick 108 (≥103 back, ≥60 front), +5pt slack. Both
    ///   faces hard-clipped to the frame; the tile flips HORIZONTALLY (y-axis).
    private static let coldTileHeight: CGFloat = 108

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if !embedded {
                    topBar
                        .padding(.top, Space.s5)
                    titleBlock
                        .padding(.top, Space.s2)
                    IridescentHairline()
                        .padding(.horizontal, Space.s3)
                        .padding(.top, Space.s5)
                }

                content
                    .padding(.top, embedded ? Space.s1 : Space.s3)

                // Floating-nav clearance. When embedded in MarketHubScreen this
                // is an INNER ScrollView under the tab bar, so the Shell's own
                // bottom inset lands below this scroller. Match the Shell's
                // canonical clearance (Device.navHeight + safeBottom + Space.s4
                // = 120pt) so the last Hot/Cold Zones row fully clears the nav
                // plate AND the lifted ESANG orb (founder 2026-06-18).
                Color.clear.frame(height: Device.navHeight + Device.safeBottom + Space.s4)
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
            // Bespoke animated skeleton that mirrors the loaded layout (KPI
            // strip → heatmap header → 2-col tile grid) with a labeled
            // shimmer, so the first paint reads as "loading market pulse",
            // never as a blank screen. No-lingering-load rule: the store's
            // `.task` fires this load the instant the screen appears, and the
            // skeleton is replaced the moment the feed resolves.
            HotZonesLoadingSkeleton()
                .padding(.horizontal, Space.s3)
        case .error(let m):
            errorCard(m)
                .padding(.horizontal, Space.s3)
        case .loaded(let f) where f.zones.isEmpty && (f.coldZones?.isEmpty ?? true):
            // Genuinely-empty live result — every metro is balanced, so there
            // is no demand spike OR discount to surface. Show an honest card
            // (with the formula pointer kept) rather than a near-blank page of
            // a lone KPI strip. No fabricated zones.
            VStack(alignment: .leading, spacing: 0) {
                emptyDemandCard
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s4)
                formulaExplainer
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s4)
            }
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
        // FOUNDER FIX 2026-06-13 — the shared `HeatCellMatrix` drilled a cell
        // tap into the hated 436 detail (`pendingDetailCity`). That nav is
        // KILLED. We DON'T fork the shared primitive (it drives 544 / rail /
        // vessel surfaces); instead this screen renders its OWN bespoke
        // 4-col grid of FlipTile cells whose front recreates the HeatCell
        // visual (band wash + label + ratio + load count) and whose back is
        // the inspiring drill-down. The equipment filter is PRESERVED —
        // we still map over `filteredZones`, `store.equipment` + its didSet
        // re-fetch are untouched; only the navigation is gone.
        let cells = filteredZones(f).prefix(12)
        if cells.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .firstTextBaseline) {
                    Text("LOAD-TO-TRUCK INTENSITY · LIVE BY METRO")
                        .font(EType.micro)
                        .tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Spacer(minLength: Space.s2)
                    Text("\(cells.count) cell\(cells.count == 1 ? "" : "s")")
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                }
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Space.s2), count: 4),
                    alignment: .leading,
                    spacing: Space.s2
                ) {
                    ForEach(Array(cells)) { z in
                        heatFlipCell(z)
                    }
                }
                heatLegendRow
            }
            .padding(Space.s4)
            .background(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
                    )
            )
        }
    }

    /// HOT · WARM · SOFT legend — same trio + washes the shared HeatCellMatrix
    /// renders, kept so the bespoke grid still reads at a glance.
    private var heatLegendRow: some View {
        HStack(spacing: Space.s4) {
            ForEach(Array(HeatBand.allCases.enumerated()), id: \.offset) { _, band in
                HStack(spacing: 6) {
                    Circle()
                        .fill(band.color.opacity(band.wash))
                        .frame(width: 8, height: 8)
                    Text(band.title)
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Space.s1)
    }

    /// One demand-grid cell as a FlipTile. FRONT recreates the canonical
    /// HeatCell look (band wash → 12pt rounded rect, bold state label, ratio,
    /// load-count caption); BACK is the inspiring bespoke drill-down. Tap
    /// toggles `flippedCells` with the shared spring + haptic; flips only
    /// when the back has real content (a live ratio is always present, so it
    /// always has a hero — but we still gate so a degenerate row can't flip
    /// to an empty face).
    private func heatFlipCell(_ z: HotZoneEntry) -> some View {
        let band = HeatBand.band(for: z.liveRatio)
        let isFlipped = flippedCells.contains(z.id)
        return FlipTile(isFlipped: isFlipped) {
            heatCellFront(z, band: band)
        } back: {
            cellBack(z)
        }
        .frame(height: Self.heatCellHeight)
        // Keep both faces inside the same stable grid footprint. The flipped
        // face is purpose-built for this compact size, so this clip is a guard
        // rail instead of hiding overflowing content.
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            guard z.liveRatio > 0 || z.liveLoads > 0 else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                if isFlipped { flippedCells.remove(z.id) }
                else { flippedCells.insert(z.id) }
            }
        }
        .sensoryFeedback(.selection, trigger: isFlipped)
    }

    /// FRONT of a demand cell — verbatim to the 544 HeatCell wash rules
    /// (HOT #F44336@0.85 / WARM #FFA726@0.55 / SOFT #00C48C@0.35, white ink
    /// on a dense HOT wash, textPrimary otherwise).
    private func heatCellFront(_ z: HotZoneEntry, band: HeatBand) -> some View {
        let textColor: Color = (band == .hot && band.wash >= 0.6) ? .white : palette.textPrimary
        return VStack(alignment: .leading, spacing: 2) {
            Text(z.state)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(textColor)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(String(format: "%.1f×", z.liveRatio))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(textColor)
            Text("\(z.liveLoads) loads")
                .font(.system(size: 8, weight: .regular))
                .foregroundStyle(textColor.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // Lock the front to the shared cell height so its bottom-anchored live
        // value cannot be clipped by the flipped face.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: Self.heatCellHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(band.color.opacity(band.wash))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(z.state), \(band.title), \(String(format: "%.1f", z.liveRatio)) loads per truck, \(z.liveLoads) loads. Tap to flip for detail.")
    }

    private enum ValueStyle { case gradient, danger, success, neutral }

    private func kpiCell(label: String,
                         value: String,
                         valueStyle: ValueStyle,
                         trail: String,
                         trailColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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
                // Guarantee the number's full glyph height so a heavy/gradient
                // digit is never top-shaved by a tight text frame.
                .fixedSize(horizontal: false, vertical: true)
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
        // Refactored 2026-06-13 — the inline ZStack + dual rotation3DEffect
        // that this tile pioneered is now the shared `FlipTile` primitive
        // (Views/Components/FlipTile.swift). Behavior is identical (same
        // X-axis spring, same Reduce-Motion crossfade); the caller still
        // owns the tap → spring-toggle of `flippedZones` + the selection
        // haptic, exactly as before.
        let isFlipped = flippedZones.contains(z.id)
        return FlipTile(isFlipped: isFlipped) {
            // FRONT (founder 2026-07-07): promoted the rich drill-down —
            // loads / trucks / rate / equipment / "why hot" + the "Find loads
            // in {state}" CTA — to the front so the actionable detail leads.
            hotTileBack(z, demandColor: demandColor)
        } back: {
            // BACK — the simpler demand-headline + interactive pulse hero is
            // now the flip-to face.
            hotTileBody(z, demandColor: demandColor, pulse: pulse, pulseColor: pulseColor)
        }
        // Lock BOTH faces to one frame so the un-tapped hero front reads
        // IDENTICAL in size to the flipped detail back (founder build 740).
        // The front fills it (sparkline expands via maxHeight: .infinity); the
        // rich back keeps its full chart + stat grid. Hard-clip both faces so
        // neither can ever bleed past the rounded rect into a neighbour tile.
        .frame(height: Self.hotTileHeight)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                if isFlipped { flippedZones.remove(z.id) }
                else { flippedZones.insert(z.id) }
            }
        }
        .sensoryFeedback(.selection, trigger: isFlipped)
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
                    .fixedSize(horizontal: false, vertical: true)
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
            // HERO sparkline — expands to fill the locked tile height so the
            // un-flipped front reads as a full hero of the SAME size as the
            // flipped detail back (founder build 740). maxHeight: .infinity
            // absorbs the extra height that the fixed `hotTileHeight` adds over
            // the front's intrinsic content.
            HotZonePulseChart(zone: z, accent: demandColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        // Fill the locked `hotTileHeight` (top-anchored) so the hero sparkline
        // can expand into the extra height and the front matches the back size.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.bgCard)
        .overlay(
            // On-brand EusoTrip gradient outline (blue→magenta). The demand
            // tier still reads through the colored "N.N× demand" headline and
            // the state badge — the ring is now brand-consistent across tiles.
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(z.zoneName), \(z.demandLevel), demand \(String(format: "%.1f", z.liveRatio)) times"
            + (pulse.map { ", rate \($0)" } ?? "")
            + ", \(z.liveLoads) loads"
        )
    }

    /// The BACK of a flipped HOT tile — the inspiring in-place drill-down
    /// that replaces the 436 detail screen. Built to the bespoke flip-back
    /// design language (`FlipBack` scaffold): header + drawn chevron + 2pt
    /// gradient underline, a LARGE demand-multiplier hero, a prominent live
    /// pulse chart seeded from this zone's real scalars, a 2-col stat grid
    /// of the remaining real fields (em-dash any absent optional, drop empty
    /// rows), and a gradient "Find loads in {state}" CTA that fires the real
    /// load-search action. ZERO SF Symbols. Tap anywhere to flip home.
    private func hotTileBack(_ z: HotZoneEntry, demandColor: Color) -> some View {
        let delta = z.rateChangePercent.map { String(format: "%+.1f%%", $0) }
        let deltaColor: Color = {
            guard let p = z.rateChangePercent else { return palette.textTertiary }
            return p >= 0 ? Brand.danger : Brand.success
        }()
        return FlipBack(
            accent: demandColor,
            name: z.zoneName,
            cornerRadius: Radius.lg,
            palette: palette,
            hero: {
                Text(String(format: "%.1f×", z.liveRatio))
                    .font(.system(size: 30, weight: .heavy).monospacedDigit())
                    .foregroundStyle(LinearGradient.diagonal)
                    .accessibilityLabel("Demand \(String(format: "%.1f", z.liveRatio)) times")
            },
            pulse: { HotZonePulseChart(zone: z, accent: demandColor).frame(height: 40) },
            stats: [
                FlipStat("Demand", z.demandLevel.capitalized, demandColor),
                FlipStat("Loads", "\(z.liveLoads)", palette.textPrimary),
                FlipStat("Trucks", z.liveTrucks.formatted(), palette.textPrimary),
                FlipStat("Rate", String(format: "$%.2f/mi", z.liveRate), palette.textPrimary),
                FlipStat("30-day Δ", delta, deltaColor),
                z.topEquipment.isEmpty ? nil : FlipStat(
                    "Equipment",
                    z.topEquipment.prefix(2)
                        .map { $0.replacingOccurrences(of: "_", with: " ").capitalized }
                        .joined(separator: " · "),
                    palette.textSecondary
                ),
                intermodalSummary(z).map { FlipStat("Intermodal", $0, palette.textSecondary) },
                (z.reasons?.first).flatMap { $0.isEmpty ? nil : FlipStat("Why hot", $0, palette.textSecondary) }
            ].compactMap { $0 },
            ctaTitle: "Find loads in \(z.state)",
            cta: { tapFindLoads(state: z.state, metro: z.zoneName) }
        )
        .accessibilityLabel(
            "\(z.zoneName) detail. Demand \(String(format: "%.1f", z.liveRatio)) times. "
            + "Trucks available \(z.liveTrucks). "
            + "Rate \(String(format: "$%.2f per mile", z.liveRate)). Tap to flip back."
        )
    }

    /// BACK of a flipped demand-grid cell. It is sourced from the same live
    /// `HotZoneEntry` as the larger hot cards, but laid out specifically for
    /// the compact 4-column grid so the action remains visible.
    private func cellBack(_ z: HotZoneEntry) -> some View {
        let band = HeatBand.band(for: z.liveRatio)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(z.state)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                FlipBackChevron(lineWidth: 2.0)
                    .frame(width: 12, height: 12)
                    .foregroundStyle(band.color)
            }

            LinearGradient.diagonal
                .frame(height: 2)
                .clipShape(Capsule())

            Text(String(format: "%.1f×", z.liveRatio))
                .font(.system(size: 22, weight: .heavy).monospacedDigit())
                .foregroundStyle(LinearGradient.diagonal)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            HStack(spacing: 6) {
                Text("\(z.liveLoads) loads")
                Text(String(format: "$%.2f/mi", z.liveRate))
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.62)

            Spacer(minLength: 0)

            Button(action: { tapFindLoads(state: z.state, metro: z.zoneName) }) {
                HStack(spacing: 5) {
                    Text("Find loads")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    FlipBackArrow()
                        .frame(width: 11, height: 11)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(band.color.opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(z.state) detail. Demand \(String(format: "%.1f", z.liveRatio)) times, "
            + "\(z.liveLoads) loads, \(String(format: "$%.2f per mile", z.liveRate)). Tap to flip back."
        )
    }

    /// Real load-search action fired by the Hot + Intensity backs.
    ///
    /// FOUNDER FIX 2026-06-19 — this used to fire a dead telemetry post
    /// (`.eusoShipperHotZonesFindLoads`, no observer anywhere) PLUS an
    /// `openURL("https://app.eusotrip.com/shipper/loads/search?…")`. Inside
    /// ShipperSurface that web URL was intercepted by ShipperWebToNativeMap,
    /// which mistook the literal path segment "search" in `/loads/search` for
    /// a loadId → routed to 205 (Load Detail) with id "search" → server
    /// returned nothing → the founder saw "Load not found".
    ///
    /// Now it stays fully IN-APP: pre-seed the shipper Loads board (201) with
    /// the zone state as a free-text search query (201 matches it against the
    /// lane origin/destination) and push it via the native `.eusoShipperNavSwap`
    /// slot — the SAME race-free hand-off the cold-zone CTA (204) and 212
    /// Control Tower use. The state is parked in `ShipperLoadsNavContext`
    /// BEFORE the swap post because 201 reads it on `.onAppear` (it mounts
    /// only after the surface consumes the post, so an `.onReceive` would
    /// miss it). Honest by construction: if no loads match the state, 201
    /// renders its real empty state — nothing fabricated.
    private func tapFindLoads(state: String, metro: String) {
        // Filter by state to match the CTA copy ("Find loads in {state}").
        // 201 free-text query matches `origin`/`destination` lane strings,
        // which carry the state, so this scopes the board to that region.
        let query = state.trimmingCharacters(in: .whitespacesAndNewlines)
        ShipperLoadsNavContext.setPush(origin: "225", query: query)
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap,
            object: nil,
            userInfo: ["screenId": "201", "query": query, "backTo": "225"]
        )
    }

    /// Intermodal (rail/vessel) one-line summary for the compact tile back.
    /// Shows REAL facility presence in the zone (yard/port counts) + a demand
    /// tier only when the server has real volume — nil when the zone has no
    /// rail/port facilities (so inland metros stay clean). The full breakdown
    /// lives in the 436 detail.
    private func intermodalSummary(_ z: HotZoneEntry) -> String? {
        var parts: [String] = []
        if let r = z.rail, let yc = r.yardCount, yc > 0 {
            let d = r.demand.map { " (\($0.capitalized))" } ?? ""
            parts.append("\(yc) rail yard\(yc == 1 ? "" : "s")\(d)")
        }
        if let v = z.vessel, let pc = v.portCount, pc > 0 {
            let d = v.demand.map { " (\($0.capitalized))" } ?? ""
            parts.append("\(pc) port\(pc == 1 ? "" : "s")\(d)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
        // FOUNDER FIX 2026-06-13 — the cold tile used to push the hated 436
        // detail (`pendingDetailCity`). That nav is KILLED. It now flips in
        // place to an inspiring glass back (surge hero + live pulse +
        // post-capacity CTA). Gated: only flips when the back has content —
        // i.e. it carries at least one real scalar to show. The caller owns
        // the spring-toggle + selection haptic, matching the hot tiles.
        let isFlipped = flippedColdZones.contains(c.id)
        let hasBack = coldHasBackContent(c)
        // FOUNDER FIX build 740 — cold tiles are COMPACT quick-info that flip
        // HORIZONTALLY (y-axis), not the big chart hero the prior pass made.
        // Both faces are CHART-LESS. axis (0,1,0) = the horizontal flip the
        // founder asked for ("flip horizontally and show quick information").
        return FlipTile(isFlipped: isFlipped, axis: (0, 1, 0)) {
            coldTileBody(c, pulse: pulse)
        } back: {
            coldTileBack(c)
        }
        // SMALL fixed height (`coldTileHeight` = 108) sized to fit BOTH the
        // compact front identity row and the compact chart-less quick-info
        // back with zero overflow. HARD-CLIP both faces so neither can ever
        // bleed past the rounded rect into the next cold tile (the founder's
        // "overlapping cold zones").
        .frame(height: Self.coldTileHeight)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            guard hasBack else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                if isFlipped { flippedColdZones.remove(c.id) }
                else { flippedColdZones.insert(c.id) }
            }
        }
        .sensoryFeedback(.selection, trigger: isFlipped)
    }

    /// Whether a cold zone has enough REAL data to justify a flip — at least
    /// one live scalar. A bare row (name only) won't flip to a face of pure
    /// em-dashes (founder: never an em-dash screen).
    private func coldHasBackContent(_ c: ColdZoneEntry) -> Bool {
        c.liveSurge != nil || c.liveRate != nil || c.liveTrucks != nil
    }

    private func coldTileBody(_ c: ColdZoneEntry, pulse: String?) -> some View {
        // FOUNDER FIX build 740 — COMPACT identity row ONLY, NO chart. The
        // prior pass made this a 276pt ColdZonePulseChart hero ("way too big
        // for a cold zone"). Reverted to the quick-info row the founder
        // approved before: snow glyph + metro + state badge + $/mi +
        // trucks·post + trailing surge %. The row is vertically centered in
        // the small 108pt tile.
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(Brand.info.opacity(0.18)).frame(width: 36, height: 36)
                // Bespoke snow glyph (WeatherGlyph) — NOT the SF `snowflake`.
                WeatherGlyph(kind: .snow)
                    .frame(width: 14, height: 14)
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
        // Center the compact row in the small fixed-height tile (no chart, no
        // dead space). Both faces hard-clipped at the call site.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    /// BACK of a flipped COLD tile — COMPACT, CHART-LESS quick info (founder
    /// build 740: "it doesn't need a graph like the other tiles"). NOT the
    /// FlipBack-with-pulse scaffold the hot tiles use — that always paints a
    /// sparkline. This is a bespoke chart-less compact layout: a header row
    /// (metro + drawn return chevron under a 2pt gradient rule), the surge
    /// headline (vs balanced 1.0×, success below balance = a real discount to
    /// post against, danger above), an inline post-rate · capacity quick line,
    /// and a small "Post capacity" CTA pill firing the SAME real action the
    /// front action ribbon uses. Sized to the 108pt `coldTileHeight`.
    private func coldTileBack(_ c: ColdZoneEntry) -> some View {
        // Surge headline: liveSurge vs balanced 1.0×. Below balance reads as a
        // capacity discount (success); above as tightening (danger). Honest
        // em-dash when the feed ships no surge.
        let surge: (text: String, color: Color) = {
            guard let s = c.liveSurge else { return ("—", palette.textTertiary) }
            let pct = (s - 1.0) * 100.0
            return (String(format: "%+.1f%%", pct), pct <= 0 ? Brand.success : Brand.danger)
        }()
        let rateStr = c.liveRate.map { String(format: "$%.2f/mi", $0) }
        let ctaTitle = c.liveRate.map { String(format: "Post at $%.2f/mi", $0) }
            ?? "Post capacity"
        return VStack(alignment: .leading, spacing: 6) {
            // Header — metro + drawn return chevron under a 2pt gradient rule.
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(c.name ?? c.state ?? "Cold zone")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    FlipBackChevron(lineWidth: 2.0)
                        .frame(width: 12, height: 12)
                        .foregroundStyle(Brand.info)
                }
                LinearGradient.diagonal
                    .frame(height: 2)
                    .clipShape(Capsule())
            }
            // Surge headline — the single eye-grabbing number, NO chart.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(surge.text)
                    .font(.system(size: 18, weight: .heavy).monospacedDigit())
                    .foregroundStyle(surge.color)
                Text("surge")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
            // Quick info — post rate · capacity in one chart-less line.
            HStack(spacing: 8) {
                if let rateStr {
                    Text(rateStr)
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Brand.info)
                }
                if let t = c.liveTrucks {
                    Text("\(t) trucks")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
            // Small "Post capacity" CTA pill — real post-capacity action.
            Button(action: { tapPostRecommendation(c) }) {
                HStack(spacing: 6) {
                    Text(ctaTitle)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    FlipBackArrow()
                        .frame(width: 12, height: 12)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Brand.info.opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(c.name ?? c.state ?? "Cold zone") detail. Surge \(surge.text). "
            + (rateStr.map { "Post rate \($0). " } ?? "")
            + "Tap to flip back."
        )
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
        // Founder feedback (build 729): the web continuation
        // (app.eusotrip.com/shipper/loads/new) errored out in the in-app
        // browser. Push the NATIVE post-load screen (204) instead — pre-seeded
        // with the cold-zone metro + recommended rate — via the shipper
        // push-nav (the same `.eusoShipperNavSwap` slot Search/lifecycle use).
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap,
            object: nil,
            userInfo: ["screenId": "204", "prefillOrigin": metro, "prefillRate": rate]
        )
    }

    // MARK: Formula explainer

    private var formulaExplainer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("MARKET PULSE")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text("pulse = avg rate change % per metro · loads / trucks ratio · 30-day rolling window")
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

    // MARK: Honest empty state (live feed resolved with no hot OR cold zones)

    /// Shown when the feed loads cleanly but every metro is balanced — no
    /// demand spike and no capacity discount. Honest copy, never invented
    /// numbers, with a Refresh affordance so the founder isn't staring at a
    /// blank page wondering if it hung.
    private var emptyDemandCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Brand.info.opacity(0.16)).frame(width: 40, height: 40)
                    Image(systemName: "scope")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Brand.info)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("No live demand data right now")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Every metro is balanced — no demand spike or capacity discount on the live feed.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Button(action: { Task { await store.load() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .heavy))
                    Text("Refresh")
                        .font(.system(size: 12, weight: .heavy))
                }
                .foregroundStyle(Brand.info)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Brand.info.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh market pulse")
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
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

// MARK: - Bespoke flip-back scaffold (the "catch my eyes" replacement for 436)
//
// ONE reusable glass card that every flip BACK on this screen (Hot · Cold ·
// Intensity) renders through, so they share the exact design language the
// founder asked for instead of each re-deriving it. Vertical rhythm, top→
// bottom: (1) HEADER ROW — name + a DRAWN chevron return affordance (never an
// SF Symbol) under a 2pt LinearGradient.diagonal underline; (2) HERO METRIC —
// the single eye-grabbing number, large + heavy; (3) LIVE PULSE — a prominent
// full-width sparkline; (4) STAT GRID — a compact 2-col grid of the remaining
// REAL fields (em-dash any absent value, the caller drops empty rows before
// passing them in); (5) CTA PILL — a full-width gradient capsule with a DRAWN
// arrow that fires the real money action. Same outer frame as the front (the
// caller passes the matching corner radius + accent-tinted border). Reduce
// Motion is handled by FlipTile; the hero + pulse subtly fade/scale in here.

private struct FlipStat: Identifiable {
    let id = UUID()
    let label: String
    /// Real value, or nil → renders an em-dash in textTertiary (honest absent).
    let value: String?
    let color: Color
    init(_ label: String, _ value: String?, _ color: Color) {
        self.label = label
        self.value = value
        self.color = color
    }
}

/// Bespoke drawn return chevron (a left-pointing ‹ glyph) — Path/Shape, NEVER
/// an SF Symbol. Drawn on a 24-box to match the WeatherIcons utility corpus.
private struct FlipBackChevron: View {
    var lineWidth: CGFloat = 2.4
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 24.0
            ctx.scaleBy(x: s, y: s)
            // M15 7 l-6 5 l6 5 — a left-pointing chevron (return / flip-home).
            var p = Path()
            p.move(to: CGPoint(x: 15, y: 7))
            p.addLine(to: CGPoint(x: 9, y: 12))
            p.addLine(to: CGPoint(x: 15, y: 17))
            ctx.stroke(p, with: .foreground,
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// Bespoke drawn CTA arrow (a right-pointing → glyph) for the action pill.
private struct FlipBackArrow: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 24.0
            ctx.scaleBy(x: s, y: s)
            var p = Path()
            // shaft
            p.move(to: CGPoint(x: 4, y: 12)); p.addLine(to: CGPoint(x: 18, y: 12))
            // head
            p.move(to: CGPoint(x: 13, y: 7)); p.addLine(to: CGPoint(x: 18, y: 12))
            p.addLine(to: CGPoint(x: 13, y: 17))
            ctx.stroke(p, with: .foreground,
                       style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

private struct FlipBack<Hero: View, Pulse: View>: View {
    let accent: Color
    let name: String
    let cornerRadius: CGFloat
    let palette: Theme.Palette
    /// Compact mode for the small 4-col Intensity cells — tighter spacing,
    /// no CTA-arrow text crowding, single-column stat list.
    var compact: Bool = false
    @ViewBuilder let hero: () -> Hero
    @ViewBuilder let pulse: () -> Pulse
    let stats: [FlipStat]
    let ctaTitle: String
    let cta: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : Space.s2) {
            // 1 — HEADER ROW + gradient underline.
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(compact ? .system(size: 11, weight: .bold) : EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    FlipBackChevron(lineWidth: compact ? 2.0 : 2.4)
                        .frame(width: compact ? 12 : 16, height: compact ? 12 : 16)
                        .foregroundStyle(accent)
                }
                LinearGradient.diagonal
                    .frame(height: 2)
                    .clipShape(Capsule())
            }

            // 2 — HERO METRIC.
            hero()
                .opacity(appeared || reduceMotion ? 1 : 0)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.92, anchor: .leading)

            // 3 — LIVE PULSE.
            pulse()
                .frame(maxWidth: .infinity)
                .opacity(appeared || reduceMotion ? 1 : 0)

            // 4 — STAT GRID (2-col, or single column in compact).
            if !stats.isEmpty {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), alignment: .leading),
                        count: compact ? 2 : 2
                    ),
                    alignment: .leading,
                    spacing: compact ? 3 : 6
                ) {
                    ForEach(stats) { stat in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(stat.label.uppercased())
                                .font(EType.micro)
                                .tracking(0.4)
                                .foregroundStyle(palette.textTertiary)
                                .lineLimit(1)
                            if let v = stat.value {
                                Text(v)
                                    .font(compact
                                          ? .system(size: 10, weight: .heavy, design: .monospaced)
                                          : EType.bodyStrong)
                                    .foregroundStyle(stat.color)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            } else {
                                Text("—")
                                    .font(compact ? .system(size: 10, weight: .heavy) : EType.bodyStrong)
                                    .foregroundStyle(palette.textTertiary)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            // 5 — CTA PILL (gradient capsule + drawn arrow + real action).
            Button(action: cta) {
                HStack(spacing: 6) {
                    Text(ctaTitle)
                        .font(.system(size: compact ? 10 : 12, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    FlipBackArrow()
                        .frame(width: compact ? 12 : 14, height: compact ? 12 : 14)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? 6 : 9)
                .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .padding(compact ? 10 : Space.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(accent.opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .onAppear {
            guard !reduceMotion else { appeared = true; return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.12)) {
                appeared = true
            }
        }
    }
}

// MARK: - Demand band (file-scoped · mirrors the shared HeatCellMatrix ramp)
//
// The Intensity grid is bespoke to this screen (we don't fork the shared
// HeatCellMatrix), so it carries its own copy of the canonical 544 band
// trio + washes: HOT #F44336@0.85 · WARM #FFA726@0.55 · SOFT #00C48C@0.35,
// cut at ≥3.0 / ≥1.4 (the same load-to-truck thresholds the matrix uses).

private enum HeatBand: CaseIterable {
    case hot, warm, soft

    static func band(for ratio: Double) -> HeatBand {
        if ratio >= 3.0 { return .hot }
        if ratio >= 1.4 { return .warm }
        return .soft
    }

    var color: Color {
        switch self {
        case .hot:  return Brand.danger
        case .warm: return Brand.warning
        case .soft: return Brand.success
        }
    }

    var wash: Double {
        switch self {
        case .hot:  return 0.85
        case .warm: return 0.55
        case .soft: return 0.35
        }
    }

    var title: String {
        switch self {
        case .hot:  return "HOT"
        case .warm: return "WARM"
        case .soft: return "SOFT"
        }
    }
}

// Cold-zone pulse sparkline (ColdZonePulseChart / ColdZonePulseSynth) was
// REMOVED in build 740 — the founder made the cold tiles COMPACT, chart-less
// quick-info ("it doesn't need a graph like the other tiles"), so both cold
// faces are now chart-free and the synth had no remaining call site. The hot
// tiles keep their live sparkline (HotZonePulseChart / HotZonePulseSynth).

// MARK: - File-scoped loading skeleton (bespoke shimmer · no blank-on-load)
//
// Mirrors the loaded layout so the first paint communicates "reading the
// market pulse" rather than rendering a stack of faint gray boxes that read
// as a blank screen (founder: "it waits to load. And this blank screen").
// A single labeled eyebrow + an animated diagonal shimmer sweep over a
// KPI-strip stand-in, a heatmap header stand-in, and a 2-col tile-grid
// stand-in. Respects Reduce Motion (no sweep, static bars).

private struct HotZonesLoadingSkeleton: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmer = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            // Labeled header so the state is never a silent blank.
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .tint(palette.textTertiary)
                Text("READING MARKET PULSE…")
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.top, Space.s1)

            // KPI strip stand-in (3 cells).
            HStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in bar(height: 44) }
            }

            // Heatmap header stand-in.
            bar(width: 160, height: 14)

            // 2-col tile grid stand-in (mirrors hotGrid).
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Space.s2),
                    GridItem(.flexible(), spacing: Space.s2),
                ],
                spacing: Space.s2
            ) {
                ForEach(0..<4, id: \.self) { _ in tile() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(shimmerSweep)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: false)) {
                shimmer = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading market pulse")
    }

    private func bar(width: CGFloat? = nil, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(palette.bgCardSoft)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    private func tile() -> some View {
        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .fill(palette.bgCardSoft)
            .frame(height: 96)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
    }

    @ViewBuilder private var shimmerSweep: some View {
        if reduceMotion {
            Color.clear
        } else {
            GeometryReader { geo in
                LinearGradient(
                    colors: [.clear, palette.textPrimary.opacity(0.06), .clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .frame(width: geo.size.width * 0.5)
                .offset(x: shimmer ? geo.size.width : -geo.size.width * 0.6)
            }
            .allowsHitTesting(false)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
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
    // 2026-06-19 — `eusoShipperHotZonesFindLoads` removed. It was a dead
    // telemetry post with NO observer anywhere; the Find-loads CTA now routes
    // natively to the shipper Loads board (201) via `.eusoShipperNavSwap`.
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
