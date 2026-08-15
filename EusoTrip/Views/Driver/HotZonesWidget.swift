//
//  HotZonesWidget.swift
//  EusoTrip — Driver Home Hot Zones widget.
//
//  Twin of the web platform's `/hot-zones` page (frontend/client/src/pages/
//  HotZones.tsx). The web surface is a full-page heatmap + rate feed; this
//  widget condenses the same intelligence into a glanceable tile that sits
//  under the Recent activity card on DriverHome.
//
//  Pulls live data from the same tRPC procedure (`hotZones.getRateFeed`)
//  so drivers see the exact same load-to-truck ratios, live $/mile rates,
//  surge multipliers, and demand levels that dispatch sees on the web.
//
//  Composition:
//    • Header           — gradient flame glyph + "HOT ZONES" micro label +
//                         pulsing live dot + "See all" link.
//    • Pulse strip      — market avgRate · critical-zone count · avgRatio.
//    • Demand map       — the in-house OMV vector `HereLiveMapView`
//                         with each live hot zone as a tappable brand
//                         pin (W13 hygiene 2026-06-10: the WKWebView
//                         HERE-JS heatmap and the MKMapView blob
//                         workaround are both deleted — the vector
//                         pin map is the only engine).
//    • Zone chips       — horizontal carousel of the top 3-5 zones, each
//                         with rank dot, zone name/state, demand badge,
//                         live rate + delta, and surge bar.
//    • Tap any zone     — presents `HotZonesDetailSheet` with the full
//                         breakdown mirroring the web detail panel.
//
//  Design: matches DriverHome's ActiveCard rhythm (Radius.xl, gradient
//  border, paired brand shadows). No stock iconography — all glyphs are
//  SF Symbols hand-picked to read well at 10-12pt against the brand
//  gradient.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - HotZonesStore

/// ObservableObject that hydrates `hotZones.getRateFeed` and exposes the
/// feed + market pulse to the widget. Mirrors the web page's
/// stale-while-revalidate pattern — first paint from the last cached
/// feed, then a background refresh on widget appear.
@MainActor
final class HotZonesStore: ObservableObject {
    @Published var zones: [HotZoneEntry] = []
    /// Cold metros (capacity > demand) the same `getRateFeed` envelope ships.
    /// Surfaced so the demand map can include them as the BLUE end of the
    /// geothermal ramp (low-weight heat points). Empty when the feed carries
    /// no cold zones — honest, never synthesized.
    @Published var coldZones: [ColdZoneEntry] = []
    @Published var marketPulse: HotZonesMarketPulse?
    @Published var feedSource: String?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var lastLoadedAt: Date?

    /// Equipment filter applied to the feed. When set, only zones whose
    /// `topEquipment` contains this code are returned by the server.
    @Published var equipmentFilter: String?

    /// How long a cached feed is considered fresh before a background
    /// refresh kicks in on `.onAppear`. Matches the web page's 5-min TTL.
    private let staleAfter: TimeInterval = 300
    private static let refreshTimeoutNanoseconds: UInt64 = 10_000_000_000
    private var refreshGeneration = 0

    /// True stale-while-revalidate: when there's already cached data,
    /// surface it immediately AND fire a background refresh so the next
    /// frame paints with fresh server values. The previous behavior
    /// short-circuited inside the 5-minute TTL window, which froze the
    /// widget on the first feed snapshot for any tab away & back within
    /// that window — exactly the "old stale data" the driver was seeing.
    func bootstrap() async {
        async let fuel: Void = refreshFuel()
        await refresh()
        _ = await fuel
    }

    /// Force a full refresh regardless of cache state.
    ///
    /// Why no in-flight short-circuit: the previous version had
    /// `if isLoading { return }` which made every concurrent caller
    /// (.task firing alongside .onAppear, or rapid tab-back) silently
    /// no-op and the widget froze on whichever fetch happened to be
    /// in flight at the moment. The driver experience was "data
    /// reverts to old stale data" — actually, the new fetch was
    /// being skipped entirely and the prior load's values stayed.
    /// Now we let concurrent refreshes overlap: last-write-wins on
    /// `zones` / `marketPulse`, which is fine because `getRateFeed`
    /// is idempotent.
    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let requestedEquipment = equipmentFilter
        isLoading = true
        errorMessage = nil
        defer {
            if generation == refreshGeneration {
                isLoading = false
            }
        }

        let result: Result<HotZonesFeedResult, Error> = await withTaskGroup(
            of: Result<HotZonesFeedResult, Error>.self
        ) { group in
            group.addTask {
                do {
                    let feed = try await EusoTripAPI.shared.hotZones
                        .getRateFeed(equipment: requestedEquipment)
                    return .success(feed)
                } catch {
                    return .failure(error)
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: Self.refreshTimeoutNanoseconds)
                return .failure(URLError(.timedOut))
            }
            let first = await group.next() ?? .failure(URLError(.unknown))
            group.cancelAll()
            return first
        }

        guard generation == refreshGeneration else { return }

        switch result {
        case .success(let feed):
            // Sort by live ratio (load-to-truck pressure) desc so the
            // tightest markets rise to the top of the widget carousel.
            self.zones = feed.zones.sorted { $0.liveRatio > $1.liveRatio }
            // Cold metros from the same envelope (capacity > demand) — the
            // blue end of the demand map's geothermal ramp. Nil/absent → [].
            self.coldZones = feed.coldZones ?? []
            // Preserve the last good marketPulse if the server didn't
            // include one this round — without this guard the strip
            // briefly read "AVG RATE $0.00 / CRITICAL 0 zones / L/T
            // 0.0x" between fetches, which is what the driver was
            // perceiving as "old stale data".
            if let pulse = feed.marketPulse {
                self.marketPulse = pulse
            }
            self.feedSource = feed.feedSource
            self.lastLoadedAt = Date()
            self.errorMessage = nil
        case .failure(let error):
            self.errorMessage = (error as? LocalizedError)?.errorDescription
                ?? String(describing: error)
        }
    }

    /// Top-N slice rendered in the carousel. Web hides the long tail too —
    /// 5 is enough to give the driver a sense of where demand is hot
    /// without pushing too much beneath the card's fold.
    func topZones(_ limit: Int = 5) -> [HotZoneEntry] {
        Array(zones.prefix(limit))
    }

    // MARK: - HERE Fuel Prices layer
    //
    // Folded into the HotZones widget at the user's direction
    // (2026-04-24): "fuel prices nearby should go in the hotzones
    // widget. it is already here map so it would be seamless."
    //
    // The widget doesn't care about the rate-feed API for this — it
    // calls HERE Fuel Prices v3 directly with a proximity query
    // centered on the driver's current CoreLocation fix. Refreshes
    // piggyback on the same `bootstrap()` call the heatmap uses, so
    // one `.task { await store.bootstrap() }` hydrates both layers.
    //
    // Empty result + error both fall through to `fuelStations = []`
    // so the widget's fuel strip silently hides when there's no
    // data (matches the §3 "no fake data" doctrine).

    /// Stations returned by `HereFuelPricesClient.nearby` for the
    /// driver's current fix. Sorted ascending by cheapest diesel
    /// price so the first element is the best deal nearby.
    @Published private(set) var fuelStations: [HereFuelStation] = []

    /// Timestamp of the most recent successful fuel fetch. Reused
    /// by the existing `staleAfter` cache gate — refreshes piggy
    /// on the heatmap's TTL so we don't double-poll.
    private var fuelLoadedAt: Date?

    /// Cheapest diesel price at any of the fetched stations. nil
    /// when HERE returned no diesel-bearing stations.
    var cheapestDieselStation: HereFuelStation? {
        fuelStations
            .compactMap { station -> (HereFuelStation, HereFuelPrice)? in
                guard let price = station.cheapestDieselPrice else { return nil }
                return (station, price)
            }
            .min { $0.1.price < $1.1.price }?
            .0
    }

    /// Fetches up to 20 diesel-bearing stations within 40 km of the
    /// driver's current fix. Silently no-ops when CoreLocation is
    /// denied / unavailable — the UI hides its fuel strip in that
    /// case instead of flashing an error banner.
    func refreshFuel() async {
        guard let coord = await DriverLocationResolver.shared.currentCoordinate() else {
            return
        }
        do {
            let stations = try await HereFuelPricesClient.shared.nearby(
                center: coord,
                radiusMeters: 40_000
            )
            self.fuelStations = stations
                .sorted { lhs, rhs in
                    let l = lhs.cheapestDieselPrice?.price ?? .infinity
                    let r = rhs.cheapestDieselPrice?.price ?? .infinity
                    return l < r
                }
            self.fuelLoadedAt = Date()
        } catch {
            // Don't clobber the main `errorMessage` — fuel is
            // ancillary to the heatmap hero. Leave prior stations
            // in place so a transient HERE outage doesn't blank
            // the strip mid-scroll.
        }
    }
}

// MARK: - Demand level helpers

/// Shared style tokens for the three demand tiers the backend emits.
/// Pulled out of the widget + detail sheet so the badge, chip accent,
/// and heatmap overlay all read the same colour for the same tier.
enum HotZoneDemand {
    case critical, high, elevated, unknown

    init(_ raw: String) {
        switch raw.uppercased() {
        case "CRITICAL": self = .critical
        case "HIGH":     self = .high
        case "ELEVATED": self = .elevated
        default:         self = .unknown
        }
    }

    var color: Color {
        switch self {
        case .critical: return Brand.danger
        case .high:     return Brand.warning
        case .elevated: return Color(red: 1.0, green: 0.76, blue: 0.20) // amber
        case .unknown:  return Brand.info
        }
    }

    var label: String {
        switch self {
        case .critical: return "CRITICAL"
        case .high:     return "HIGH"
        case .elevated: return "ELEVATED"
        case .unknown:  return "-"
        }
    }

    /// Patch #2 — map the demand tier onto the unified `EusoBadgeKind`.
    /// `critical` → `.hot` (gradient fill reads as "red-hot" demand),
    /// `high` / `elevated` → `.warning` (amber tint), `.unknown` → `.neutral`.
    var eusoBadgeKind: EusoBadgeKind {
        switch self {
        case .critical: return .hot
        case .high:     return .warning
        case .elevated: return .warning
        case .unknown:  return .neutral
        }
    }
}

// W13 hygiene (E2E audit §4 maps · 2026-06-10): two dead map engines
// (~900 lines) deleted — the `#if false` MKMapView heat-blob stack
// (HeatBlobOverlay/HeatBlobRenderer/USAOutlineOverlay/USAOutlineRenderer +
// the MKMapView UIViewRepresentable) and the never-instantiated
// HotZonesHeatmapWebView (HERE Maps JS v3.1 in a WKWebView) together with
// its HotZonesHeatmapPoint feed type. The live engine is the OMV vector
// HereLiveMapView pin map in the shim below; git history holds the
// reference implementations.

// MARK: - HotZonesHeatMapView (live map)

/// The widget's demand map: the OMV vector `HereLiveMapView` with each hot
/// zone painted as a tappable brand pin (tap routes onSelectMarker →
/// onSelectZone → the detail sheet). The gradient card renders as the
/// honest empty state when there are no zones to plot. (W13 hygiene
/// 2026-06-10: the legacy WKWebView/MKMapView engines this shim once
/// fronted are deleted — this IS the engine now.)
struct HotZonesHeatMapView: View {
    var zones: [HotZoneEntry]
    /// Cold metros (capacity > demand) from the same feed. Included as the
    /// BLUE end of the geothermal ramp via low-weight heat points. Default []
    /// keeps every existing caller compiling; a screen with no cold-zone data
    /// simply passes nothing (honest hot-only field).
    var coldZones: [ColdZoneEntry] = []
    var selectedZoneId: String? = nil
    var onSelectZone: ((HotZoneEntry) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.palette) private var palette

    /// The continuous geothermal heat field, fed to `BespokeMapCanvas` via the
    /// `.geothermal` style hint. Each point's `weight` = load-to-truck ratio
    /// (the engine's fixed domain: 0.5→cold/blue, 1.4→mid, 3.0+→hot/red).
    ///   • HOT zones  → weight = `zone.liveRatio` (real demand pressure).
    ///   • COLD zones → low-weight blue end: a derived sub-balance ratio from
    ///     `liveSurge` when present (clamped ≤ 1.0 so cold always reads cool),
    ///     else the constant 0.6. ZERO fabrication: only real store zones with
    ///     a real coordinate become points; a (0,0) center is dropped.
    private var heatPoints: [HereLatLng] {
        var pts: [HereLatLng] = []
        for z in zones where !(z.center.lat == 0 && z.center.lng == 0) {
            pts.append(HereLatLng(z.center.lat, z.center.lng, weight: z.liveRatio))
        }
        for c in coldZones {
            guard let ctr = c.center, !(ctr.lat == 0 && ctr.lng == 0) else { continue }
            // Cold weight: when the feed ships a surge multiplier, fold it into
            // a sub-balance ratio (≤ 1.0 so it stays on the cool half of the
            // ramp); otherwise a low constant that lands at the blue end.
            let coldWeight: Double = {
                guard let s = c.liveSurge, s > 0 else { return 0.6 }
                return min(1.0, max(0.3, s * 0.6))
            }()
            pts.append(HereLatLng(ctr.lat, ctr.lng, weight: coldWeight))
        }
        return pts
    }

    var body: some View {
        // Render the canonical native HERE map (`HereMapView`) with
        // each hot zone painted as a brand-coloured pin. Was forced
        // to a SwiftUI gradient fallback because the HERE JS WebView
        // was timing out tile auth — but the native OAuth tile path
        // is rock-solid (same one shipper Live Tracking + load
        // detail use), so we use that instead and ditch the
        // WebView entirely. Fallback to the gradient card stays as
        // the empty state when there are no zones to plot.
        // Founder report 2026-05-06: "on homescreen driver the
        // hotzones map doesnt show at all."
        if zones.isEmpty && coldZones.isEmpty {
            zeroZonesEmptyState
        } else {
            // 2026-05-22: migrated off the legacy raster HereMapView (and the
            // private timing-out HERE JS WebView) onto the OMV vector renderer
            // via HereLiveMapView. Each hot zone is a tappable pin carrying its
            // zoneId, so tap-to-open-detail routes through onSelectMarker →
            // onSelectZone exactly as before. addOns are intentionally empty:
            // this is a demand-zone picker, so amenity/traffic pins would be
            // clutter (matches the driver load-board picker treatment).
            //
            // 2026-06-20 GEOTHERMAL: the demand map now LIGHTS UP — alongside
            // the tappable per-zone pins, it emits a `.heatmap(points:)` layer
            // (weight = load-to-truck ratio per point) and requests the
            // `.geothermal` style hint, so the in-house engine paints the
            // continuous blue→red demand field UNDER the pins. Cold zones ride
            // in as the cool/blue end (see `heatPoints`). Pins stay tappable —
            // the detail-sheet flow is unchanged.
            HereLiveMapView(
                center: mapCenter,
                zoom: 5,
                baseLayers: [
                    .heatmap(points: heatPoints),
                    .markers(zones.map { z in
                        HereMarker(
                            at: .init(z.center.lat, z.center.lng),
                            kind: .hotZone,
                            label: z.zoneName,
                            id: z.zoneId
                        )
                    })
                ],
                addOns: [],
                showLegend: false,
                showTicker: false,
                styleHint: .geothermal,
                onSelectMarker: { id in
                    if let z = zones.first(where: { $0.zoneId == id }) {
                        onSelectZone?(z)
                    }
                }
            )
        }
    }

    /// Average of the live zone centers (hot + cold) — a stable map anchor (the
    /// vector view has no fit-to-bounds API; zoom 5 ≈ regional spread). Cold
    /// centers are folded in so a cold-heavy field stays framed.
    private var mapCenter: HereLatLng {
        var lats: [Double] = []
        var lngs: [Double] = []
        for z in zones where !(z.center.lat == 0 && z.center.lng == 0) {
            lats.append(z.center.lat); lngs.append(z.center.lng)
        }
        for c in coldZones {
            if let ctr = c.center, !(ctr.lat == 0 && ctr.lng == 0) {
                lats.append(ctr.lat); lngs.append(ctr.lng)
            }
        }
        guard !lats.isEmpty else { return .init(39.5, -98.35) }
        return .init(lats.reduce(0, +) / Double(lats.count),
                     lngs.reduce(0, +) / Double(lngs.count))
    }

    /// Honest empty state when the live feed has zero zones to plot —
    /// renamed from `jsKeyMissingFallback` (W13 hygiene 2026-06-10): the
    /// HERE-JS key it referenced is gone with the deleted WebView engine.
    private var zeroZonesEmptyState: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Brand.blue.opacity(0.35),
                    Brand.magenta.opacity(0.35),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                Color.black.opacity(0.35)
            )
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("DEMAND HEATMAP")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Text("\(zones.count) live \(zones.count == 1 ? "zone" : "zones")")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
                Text("Tap a zone below for the detail breakdown.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
        }
    }

}

// MARK: - HotZonesWidget

struct HotZonesWidget: View {
    @Environment(\.palette) var palette
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var store = HotZonesStore()

    @State private var pulse: Bool = false
    @State private var selectedZone: HotZoneEntry? = nil
    @State private var showDetailSheet: Bool = false

    var body: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                pulseStrip
                // HERE Fuel Prices strip — silent when the driver
                // hasn't authorized location or HERE returned nothing.
                if !store.fuelStations.isEmpty {
                    fuelStrip
                }
                heatMap
                zoneChipsScroller
                if store.zones.isEmpty && store.isLoading {
                    loadingPlaceholder
                }
                if let msg = store.errorMessage, store.zones.isEmpty {
                    errorPlaceholder(msg)
                }
                footerMeta
            }
        }
        .task { await store.bootstrap() }
        .onAppear {
            // Kick off the infinite "live" pulse on the header dot.
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse.toggle()
            }
            // Re-fetch on every reappear (NOT just first mount). `.task`
            // attaches to the view's lifetime — when this widget is
            // inside a TabView page that stays alive across tab swaps,
            // `.task` does NOT re-fire on tab-back, so the heat-feed
            // froze at the values from first appear and the user saw
            // 2-month-old "stale" data on every navigation. `.onAppear`
            // fires every time the view enters the hierarchy, which is
            // the right cadence for "always show fresh data when the
            // driver looks at the widget".
            Task { await store.refresh() }
        }
        .sheet(item: $selectedZone) { zone in
            HotZonesDetailSheet(zone: zone, marketPulse: store.marketPulse)
                .environment(\.palette, palette)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDetailSheet) {
            HotZonesListSheet(store: store)
                .environment(\.palette, palette)
                .eusoSheetX()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Space.s2) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient.diagonal)
                    .frame(width: 24, height: 24)
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white)
            }

            Text("HOT ZONES")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            // Pulsing LIVE dot.
            HStack(spacing: 4) {
                Circle()
                    .fill(Brand.danger)
                    .frame(width: 6, height: 6)
                    .scaleEffect(pulse ? 1.25 : 0.85)
                    .opacity(pulse ? 1.0 : 0.55)
                Text("LIVE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(Brand.danger)
            }

            Spacer(minLength: 0)

            Button { showDetailSheet = true } label: {
                HStack(spacing: 3) {
                    Text("See all")
                        .font(EType.caption)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(palette.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Market Pulse strip

    private var pulseStrip: some View {
        let pulse = store.marketPulse
        return HStack(spacing: Space.s3) {
            pulseChip(
                label: "AVG RATE",
                value: pulse?.avgRate.map { String(format: "$%.2f", $0) } ?? "-",
                trailing: "/mi",
                tint: Brand.success
            )
            pulseChip(
                label: "CRITICAL",
                value: pulse?.criticalZones.map(String.init) ?? "0",
                trailing: "zones",
                tint: Brand.danger
            )
            pulseChip(
                label: "L/T RATIO",
                value: pulse?.avgRatio.map { String(format: "%.1fx", $0) } ?? "-",
                trailing: "",
                tint: Brand.warning
            )
        }
    }

    private func pulseChip(label: String, value: String, trailing: String, tint: Color) -> some View {
        // Each chip wears its own brand tint as a soft fill +
        // saturated stroke instead of the slate `bgCardSoft` washout.
        // Reads as a deliberate market-signal pill, not a placeholder.
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.micro).tracking(0.5)
                .foregroundStyle(tint.opacity(0.85))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .heavy, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !trailing.isEmpty {
                    Text(trailing)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(tint.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(tint.opacity(0.45), lineWidth: 1)
        )
    }

    // MARK: Fuel strip (HERE Fuel Prices)

    /// Horizontal strip surfaced between the market pulse and the
    /// heatmap. Leads with the cheapest diesel station near the
    /// driver + a scrollable rail of the next best deals. Every row
    /// is a live HERE Fuel Prices v3 result — brand, distance, $/gal,
    /// currency, and the lastUpdate timestamp flow straight from the
    /// API.
    private var fuelStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "fuelpump.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("FUEL NEAR YOU")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("EUSOTRIP · \(store.fuelStations.count) stations")
                    .font(EType.micro).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }

            // Hero chip — cheapest diesel nearby.
            if let best = store.cheapestDieselStation,
               let price = best.cheapestDieselPrice {
                HStack(spacing: Space.s3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CHEAPEST DIESEL")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(palette.textTertiary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(formatPrice(price))
                                .font(.system(size: 22, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(LinearGradient.diagonal)
                            Text(price.currency)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(palette.textTertiary)
                        }
                        Text(bestStationLine(best))
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .padding(Space.s3)
                .background(palette.bgCardSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }

            // Horizontal rail of the next best stations.
            if store.fuelStations.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.s2) {
                        ForEach(store.fuelStations.prefix(8)) { station in
                            fuelRailChip(station: station)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private func fuelRailChip(station: HereFuelStation) -> some View {
        let price = station.cheapestDieselPrice
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "fuelpump")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text(station.brand?.uppercased() ?? station.name?.uppercased() ?? "STATION")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Text(price.map(formatPrice) ?? "-")
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
            if let m = station.distance {
                Text(formatDistanceMiles(meters: m))
                    .font(EType.micro).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 8)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func formatPrice(_ price: HereFuelPrice) -> String {
        let symbol: String = {
            switch price.currency.uppercased() {
            case "USD": return "$"
            case "EUR": return "€"
            case "GBP": return "£"
            case "CAD": return "$"
            default:    return ""
            }
        }()
        return String(format: "%@%.3f", symbol, price.price)
    }

    private func bestStationLine(_ station: HereFuelStation) -> String {
        var parts: [String] = []
        if let b = station.brand, !b.isEmpty { parts.append(b) }
        else if let n = station.name, !n.isEmpty { parts.append(n) }
        if let a = station.address?.oneLine, !a.isEmpty { parts.append(a) }
        if let m = station.distance {
            parts.append(formatDistanceMiles(meters: m))
        }
        return parts.joined(separator: " · ")
    }

    private func formatDistanceMiles(meters: Int) -> String {
        let miles = Double(meters) / 1609.344
        if miles < 10 {
            return String(format: "%.1f mi", miles)
        }
        return String(format: "%.0f mi", miles)
    }

    // MARK: Heatmap

    private var heatMap: some View {
        ZStack(alignment: .topLeading) {
            HotZonesHeatMapView(
                zones: store.zones,
                coldZones: store.coldZones,
                onSelectZone: { zone in selectedZone = zone }
            )
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            // Corner glyph so the widget reads as a "heatmap" even when
            // zoomed out and the circles are small.
            HStack(spacing: 4) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 10, weight: .bold))
                Text("HEATMAP")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.55))
            )
            .padding(Space.s2)

            // W13 hygiene (E2E audit §4 maps · 2026-06-10): the 3-color
            // severity legend (CRITICAL/HIGH/ELEVATED) is dropped — the pin
            // layer renders uniform `.hotZone` markers, so the legend
            // advertised a color ramp the map never painted (zero-fallback
            // doctrine: no fabricated semantics). Demand tier lives on each
            // zone chip's badge below. Re-add only if/when HereMarker grows
            // a per-pin tint and the pins actually carry the tier colors.
        }
        .frame(height: 190)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.25)
                .allowsHitTesting(false)
        )
    }

    // MARK: Zone chips carousel

    private var zoneChipsScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s3) {
                ForEach(Array(store.topZones().enumerated()), id: \.element.zoneId) { pair in
                    let rank = pair.offset + 1
                    let zone = pair.element
                    Button {
                        selectedZone = zone
                    } label: {
                        zoneChip(zone: zone, rank: rank)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)   // so gradient borders don't clip
            .padding(.vertical, 2)
        }
    }

    private func zoneChip(zone: HotZoneEntry, rank: Int) -> some View {
        let demand = HotZoneDemand(zone.demandLevel)
        let rateDelta = zone.rateChangePercent ?? 0
        let deltaPositive = rateDelta >= 0

        return VStack(alignment: .leading, spacing: Space.s2) {
            // Rank badge + demand pill
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: 18, height: 18)
                    Text("\(rank)")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color.white)
                }
                Text(demand.label)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(demand.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(demand.color.opacity(0.16))
                    )
                Spacer(minLength: 0)
            }

            // Zone name + state
            VStack(alignment: .leading, spacing: 1) {
                Text(zone.zoneName)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(zone.state)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.textTertiary)
            }

            // Rate + delta
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "$%.2f", zone.liveRate))
                    .font(.system(size: 15, weight: .heavy, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text("/mi")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 2)
                if abs(rateDelta) >= 0.1 {
                    HStack(spacing: 1) {
                        Image(systemName: deltaPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 8, weight: .heavy))
                        Text(String(format: "%.1f%%", abs(rateDelta)))
                            .font(.system(size: 9, weight: .heavy))
                            .monospacedDigit()
                    }
                    .foregroundStyle(deltaPositive ? Brand.success : Brand.danger)
                }
            }

            // Surge + load-to-truck meter
            surgeMeter(ratio: zone.liveRatio, surge: zone.liveSurge, tint: demand.color)

            // Volume strip
            HStack(spacing: Space.s2) {
                volumePill(glyph: "shippingbox.fill",
                           value: "\(zone.liveLoads)",
                           tint: Brand.blue)
                volumePill(glyph: "box.truck.fill",
                           value: "\(zone.liveTrucks)",
                           tint: Brand.magenta)
            }
        }
        .padding(Space.s3)
        .frame(width: 210, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            demand.color.opacity(0.16),
                            palette.bgCard
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            demand.color.opacity(0.95),
                            demand.color.opacity(0.40)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
                )
        )
    }

    /// Bar meter showing liveRatio (filled portion) with the surge
    /// multiplier read out on the right. Full bar maps to ratio 3.0
    /// (above that the bar stays clamped but still reads "pegged").
    private func surgeMeter(ratio: Double, surge: Double, tint: Color) -> some View {
        let normalized = max(0, min(ratio / 3.0, 1.0))
        return HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.borderFaint)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.6), tint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * normalized, 6))
                }
            }
            .frame(height: 4)

            Text(String(format: "%.1fx", surge))
                .font(.system(size: 9, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }

    private func volumePill(glyph: String, value: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: glyph)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 10, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }

    // MARK: Footer

    private var footerMeta: some View {
        // Branding-only footer — the server-returned `feedSource`
        // string ("EusoTrip Intelligence (0 carriers) + 27 Gov
        // Sources") leaked the engineering detail about which data
        // sources feed the rate model. Drivers don't need to see
        // that; they need to know one thing: this is EusoTrip's
        // number. The label stays constant regardless of what the
        // backend reports as its source composition, so whether the
        // rate came from FMCSA ingestion, platform settlements, or
        // the market-intel blend, the driver reads it as
        // authoritative "EusoTrip Intelligence."
        HStack(spacing: Space.s2) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("EusoTrip Intelligence")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let at = store.lastLoadedAt {
                Text("Updated " + HotZonesTime.shortAgo(from: at))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(palette.textTertiary)
            }
            if store.isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .tint(palette.textSecondary)
            }
        }
    }

    // MARK: States

    private var loadingPlaceholder: some View {
        HStack(spacing: Space.s2) {
            ProgressView().tint(palette.textSecondary)
            Text("Scanning national freight intelligence…")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.s2)
    }

    /// Graceful placeholder shown when the feed is temporarily
    /// unreachable. Replaces the old "exclamationmark.triangle.fill +
    /// bold red headline + Cannot-read-properties trace" design, which
    /// read like a crash report and alarmed drivers unnecessarily.
    ///
    /// New behavior:
    ///   • No warning icon or alarm copy in the header — it's a neutral
    ///     "Updating" line with a small shimmer.
    ///   • The raw error `message` (e.g. "Cannot read properties of
    ///     undefined (reading 'CA')") is NEVER surfaced to the driver;
    ///     it's useful to engineers, not to someone at the wheel.
    ///   • Retry is a quiet chevron button, not a hero CTA.
    ///   • The widget still auto-retries on every pull-to-refresh from
    ///     the parent, so most drivers will never even see this state.
    private func errorPlaceholder(_ message: String) -> some View {
        #if DEBUG
        // Keep the raw server message available to engineers in
        // development builds so we can diagnose outages without the
        // driver UX taking the hit in production.
        let _ = message
        #endif
        return HStack(spacing: Space.s2) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(palette.textTertiary)
                .symbolEffect(.pulse, options: .repeating)
            VStack(alignment: .leading, spacing: 2) {
                Text("Updating live market data")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Text("We'll refresh automatically.")
                    .font(EType.micro)
                    .tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: Space.s2)
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .padding(8)
                    .background(
                        Circle().fill(palette.bgCard.opacity(0.6))
                    )
                    .overlay(
                        Circle().strokeBorder(palette.borderFaint.opacity(0.6), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry market data refresh")
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - HotZonesDetailSheet

/// Tap-through detail sheet for a single hot zone. Mirrors the web
/// detail panel — full demand breakdown, rate + surge meters, volume,
/// top equipment, fuel, weather risk, compliance risk.
struct HotZonesDetailSheet: View {
    let zone: HotZoneEntry
    let marketPulse: HotZonesMarketPulse?
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let demand = HotZoneDemand(zone.demandLevel)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    hero(demand: demand)
                    metricGrid
                    if let reasons = zone.reasons, !reasons.isEmpty {
                        reasonsSection(reasons)
                    }
                    if let eq = topEquipment, !eq.isEmpty {
                        equipmentSection(eq)
                    }
                    riskSection
                    if let fmcsa = zone.fmcsa {
                        fmcsaSection(fmcsa)
                    }
                    if let alerts = zone.weatherAlerts, !alerts.isEmpty {
                        weatherAlertsSection(alerts)
                    }
                    // Footer context
                    Text("Live intelligence from hz_zone_intelligence · FMCSA · NWS · EIA. Refreshes every 5 min.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Space.s5)
            }
            .background(palette.bgPage.ignoresSafeArea())
            .navigationTitle("Zone Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    // MARK: Hero

    private func hero(demand: HotZoneDemand) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    Text(demand.label)
                        .font(.system(size: 10, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(demand.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(demand.color.opacity(0.18))
                        )
                    if let trend = zone.demandTrend {
                        HStack(spacing: 3) {
                            Image(systemName: trendGlyph(trend))
                                .font(.system(size: 10, weight: .bold))
                            Text(trend)
                                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        }
                        .foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                Text(zone.zoneName)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(zone.state)
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "$%.2f", zone.liveRate))
                        .font(EType.numeric)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("/mi")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                    Spacer(minLength: 0)
                    if let pct = zone.rateChangePercent, abs(pct) >= 0.1 {
                        HStack(spacing: 2) {
                            Image(systemName: pct >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .heavy))
                            Text(String(format: "%.1f%%", abs(pct)))
                                .font(.system(size: 12, weight: .heavy))
                                .monospacedDigit()
                        }
                        .foregroundStyle(pct >= 0 ? Brand.success : Brand.danger)
                    }
                }
            }
        }
    }

    private func trendGlyph(_ raw: String) -> String {
        switch raw.uppercased() {
        case "RISING":  return "arrow.up.right.circle.fill"
        case "FALLING": return "arrow.down.right.circle.fill"
        default:        return "minus.circle.fill"
        }
    }

    // MARK: Metric grid

    private var metricGrid: some View {
        // Accent each tile with its semantic color so the grid reads
        // as a real spatial-intel dashboard instead of a stack of
        // slate cards. Live volumes get brand blue/magenta, ratios +
        // surges get gradient numerals (already on-brand), fuel +
        // safety speak in their own commodity tints.
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Space.s3),
                      GridItem(.flexible(), spacing: Space.s3)],
            spacing: Space.s3
        ) {
            MetricTile(label: "Live Loads",
                       value: "\(zone.liveLoads)",
                       accent: Brand.blue)
            MetricTile(label: "Live Trucks",
                       value: "\(zone.liveTrucks)",
                       accent: Brand.magenta)
            MetricTile(label: "L/T Ratio",
                       value: String(format: "%.1fx", zone.liveRatio),
                       gradientNumeral: true)
            MetricTile(label: "Surge",
                       value: String(format: "%.2fx", zone.liveSurge),
                       gradientNumeral: true)
            if let fuel = zone.fuelPrice {
                MetricTile(label: "Diesel",
                           value: String(format: "$%.2f", fuel),
                           accent: Brand.warning)
            }
            if let peak = zone.peakHours, !peak.isEmpty {
                MetricTile(label: "Peak Hours",
                           value: peak,
                           accent: Brand.info)
            }
            if let safety = zone.safetyScore {
                MetricTile(label: "Safety Score",
                           value: String(format: "%.0f/100", safety),
                           gradientNumeral: true,
                           accent: safety >= 80 ? Brand.success : (safety >= 60 ? Brand.warning : Brand.danger))
            }
            if let platform = zone.platformLoads {
                MetricTile(label: "Platform Loads",
                           value: "\(platform)",
                           accent: Brand.success)
            }
        }
    }

    // MARK: Equipment

    private var topEquipment: [String]? {
        zone.topEquipment.isEmpty ? nil : zone.topEquipment
    }

    private func equipmentSection(_ equipment: [String]) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("TOP EQUIPMENT")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                // Wrap equipment codes in chips.
                FlowChips(items: equipment.map { prettify($0) })
            }
        }
    }

    private func prettify(_ code: String) -> String {
        code.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: Risk

    private var riskSection: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("RISK SIGNALS")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                VStack(alignment: .leading, spacing: 6) {
                    riskRow(glyph: "cloud.bolt.fill",
                            label: "Weather Risk",
                            value: zone.weatherRiskLevel ?? "LOW")
                    if let comp = zone.complianceRiskScore {
                        riskRow(glyph: "checkmark.seal.fill",
                                label: "Compliance Risk",
                                value: "\(comp)/100")
                    }
                    if let hz = zone.hazmatClasses, !hz.isEmpty {
                        riskRow(glyph: "exclamationmark.shield.fill",
                                label: "Hazmat Classes",
                                value: hz.joined(separator: ", "))
                    }
                    if let fires = zone.activeWildfires, fires > 0 {
                        riskRow(glyph: "flame.circle.fill",
                                label: "Active Wildfires",
                                value: "\(fires)")
                    }
                    if let fema = zone.femaDisasterActive, fema {
                        riskRow(glyph: "house.lodge.fill",
                                label: "FEMA Disaster",
                                value: "ACTIVE")
                    }
                    if let seismic = zone.seismicRiskLevel,
                       seismic.uppercased() != "LOW" {
                        riskRow(glyph: "waveform.path.ecg",
                                label: "Seismic Risk",
                                value: seismic.uppercased())
                    }
                    if let hazmatInc = zone.recentHazmatIncidents, hazmatInc > 0 {
                        riskRow(glyph: "drop.triangle.fill",
                                label: "Hazmat Incidents",
                                value: "\(hazmatInc)")
                    }
                    if let epa = zone.epaFacilitiesCount, epa > 0 {
                        riskRow(glyph: "leaf.fill",
                                label: "EPA Facilities",
                                value: "\(epa)")
                    }
                    if let aiTrend = zone.aiRateTrend {
                        riskRow(glyph: "cpu",
                                label: "ESANG Rate Trend",
                                value: aiTrend.uppercased())
                    }
                }
            }
        }
    }

    // MARK: Reasons

    private func reasonsSection(_ reasons: [String]) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("WHY THIS ZONE IS HOT")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(reasons, id: \.self) { reason in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(LinearGradient.diagonal)
                                .padding(.top, 3)
                            Text(reason)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let forecast = zone.nextWeekForecast, !forecast.isEmpty {
                    Divider().overlay(palette.borderFaint)
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("Next week: ")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)
                        Text(forecast)
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                    }
                }
            }
        }
    }

    // MARK: FMCSA

    private func fmcsaSection(_ fmcsa: HotZoneFMCSA) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: 4) {
                    // Founder report 2026-05-06: "fmcsa 9.8 m just
                    // needs to say fmcsa" — the 9.8M was the source
                    // database row count, not a per-zone metric, so
                    // it read as confusing trivia in the zone detail.
                    Text("FMCSA")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                }
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: Space.s3),
                              GridItem(.flexible(), spacing: Space.s3)],
                    spacing: Space.s3
                ) {
                    if let c = fmcsa.carriers { MetricTile(label: "Carriers", value: "\(c)") }
                    if let p = fmcsa.powerUnits { MetricTile(label: "Power Units", value: "\(p)") }
                    if let d = fmcsa.drivers { MetricTile(label: "Drivers", value: "\(d)") }
                    if let hz = fmcsa.hazmatCarriers { MetricTile(label: "Hazmat Carriers", value: "\(hz)") }
                    if let crashes = fmcsa.crashes90d {
                        MetricTile(label: "Crashes (90d)", value: "\(crashes)",
                                   gradientNumeral: crashes > 0)
                    }
                    if let fat = fmcsa.crashFatalities, fat > 0 {
                        MetricTile(label: "Fatalities", value: "\(fat)")
                    }
                    if let insp = fmcsa.inspections30d {
                        MetricTile(label: "Inspections (30d)", value: "\(insp)")
                    }
                    if let oos = fmcsa.oosRate {
                        MetricTile(label: "OOS Rate",
                                   value: String(format: "%.1f%%", oos),
                                   gradientNumeral: oos >= 5)
                    }
                }
            }
        }
    }

    // MARK: Weather alerts

    private func weatherAlertsSection(_ alerts: [HotZoneWeatherAlert]) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("ACTIVE WEATHER ALERTS")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(alerts.enumerated()), id: \.offset) { pair in
                        let alert = pair.element
                        let severity = (alert.severity ?? "").uppercased()
                        let tint: Color = {
                            switch severity {
                            case "EXTREME", "SEVERE": return Brand.danger
                            case "MODERATE":          return Brand.warning
                            default:                  return Brand.info
                            }
                        }()
                        HStack(alignment: .top, spacing: Space.s2) {
                            Image(systemName: "cloud.bolt.rain.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(tint)
                                .frame(width: 18, alignment: .center)
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Text((alert.event ?? "Alert").uppercased())
                                        .font(.system(size: 11, weight: .heavy))
                                        .foregroundStyle(palette.textPrimary)
                                    if !severity.isEmpty {
                                        Text(severity)
                                            .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                                            .foregroundStyle(tint)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1.5)
                                            .background(
                                                Capsule(style: .continuous)
                                                    .fill(tint.opacity(0.16))
                                            )
                                    }
                                }
                                if let headline = alert.headline, !headline.isEmpty {
                                    Text(headline)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(palette.textSecondary)
                                        .lineLimit(3)
                                }
                                if let area = alert.areaDesc, !area.isEmpty {
                                    Text(area)
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundStyle(palette.textTertiary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func riskRow(glyph: String, label: String, value: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: glyph)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

// MARK: - HotZonesListSheet

/// "See all" sheet — every zone the driver's role surfaces, sorted by
/// liveRatio desc. Replaces the web /hot-zones full-page list on mobile.
struct HotZonesListSheet: View {
    @ObservedObject var store: HotZonesStore
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    @State private var selectedZone: HotZoneEntry? = nil

    var body: some View {
        // Patch #1: EusoHeader replaces the inline iOS-default
        // `navigationTitle("Hot Zones")` / `.inline` combo so this sheet
        // reads in the 28pt gradient-hero language the rest of the app
        // uses. The Done button is folded into the header's trailing
        // accessory slot so the toolbar goes away entirely.
        VStack(alignment: .leading, spacing: 0) {
            EusoHeader(title: "Hot Zones",
                       subtitle: "Live demand, rate & L/T",
                       size: .sheet) {
                Button { dismiss() } label: {
                    Text("Done")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Hot Zones")
            }
            IridescentHairline()
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s3) {
                    if let pulse = store.marketPulse {
                        summaryStrip(pulse)
                    }
                    ForEach(store.zones) { zone in
                        Button { selectedZone = zone } label: {
                            listRow(zone)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Space.s5)
            }
            .eusoRefreshable { await store.refresh() }
        }
        .background(palette.bgPage.ignoresSafeArea())
        .sheet(item: $selectedZone) { zone in
            HotZonesDetailSheet(zone: zone, marketPulse: store.marketPulse)
                .environment(\.palette, palette)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func summaryStrip(_ pulse: HotZonesMarketPulse) -> some View {
        HStack(spacing: Space.s2) {
            summaryTile(label: "AVG RATE",
                        value: pulse.avgRate.map { String(format: "$%.2f", $0) } ?? "-",
                        tint: Brand.success)
            summaryTile(label: "CRITICAL",
                        value: pulse.criticalZones.map(String.init) ?? "0",
                        tint: Brand.danger)
            summaryTile(label: "L/T",
                        value: pulse.avgRatio.map { String(format: "%.1fx", $0) } ?? "-",
                        tint: Brand.warning)
        }
    }

    private func summaryTile(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.micro).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }

    private func listRow(_ zone: HotZoneEntry) -> some View {
        let demand = HotZoneDemand(zone.demandLevel)
        let delta = zone.rateChangePercent ?? 0
        return HStack(spacing: Space.s3) {
            ZStack {
                Circle()
                    .fill(demand.color.opacity(0.18))
                    .frame(width: 38, height: 38)
                Image(systemName: "flame.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(demand.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(zone.zoneName)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(zone.state)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textTertiary)
                }
                HStack(spacing: 6) {
                    // Patch #2: EusoBadge replaces the bespoke flame-in-circle
                    // ELEVATED marker. `.hot` for CRITICAL (red-hot demand),
                    // `.warning` for HIGH / ELEVATED (amber), `.neutral` for
                    // unknown. The flame glyph is carried inline.
                    EusoBadge(label: demand.label,
                              kind: demand.eusoBadgeKind,
                              icon: Image(systemName: "flame.fill"))
                    Text("· \(zone.liveLoads) loads · \(zone.liveTrucks) trucks")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "$%.2f", zone.liveRate))
                    .font(.system(size: 14, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                if abs(delta) >= 0.1 {
                    HStack(spacing: 1) {
                        Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 8, weight: .heavy))
                        Text(String(format: "%.1f%%", abs(delta)))
                            .font(.system(size: 10, weight: .heavy))
                            .monospacedDigit()
                    }
                    .foregroundStyle(delta >= 0 ? Brand.success : Brand.danger)
                }
            }
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }
}

// MARK: - FlowChips

/// Minimal wrap layout — renders equipment codes as chips that flow onto
/// additional rows when they overflow. Avoids bringing in a 3rd-party
/// FlowLayout dependency.
private struct FlowChips: View {
    let items: [String]
    @Environment(\.palette) var palette

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 92), spacing: 6)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(palette.tintNeutral)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
            }
        }
    }
}

// MARK: - Time helpers

enum HotZonesTime {
    static func shortAgo(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86_400)d ago"
    }
}
