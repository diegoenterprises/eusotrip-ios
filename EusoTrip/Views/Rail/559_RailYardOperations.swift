//
//  559_RailYardOperations.swift
//  EusoTrip — Rail Engineer · Yard Operations (BOARD archetype).
//
//  Verbatim port of "559 Rail Yard Operations · Dark" (05 Rail).
//  Status swim-lanes (ON ROUTE · STAGING/USMCA · RAMP) of full-width yard
//  rows, each carrying a relative-capacity bar (slot capacity scaled to the
//  largest yard on the route) + track counts + status pill + railroad disc.
//  Route RAIL-260523-7C3A0B12D4 · BNSF transcon · Corwith → Argentine → LPC.
//
//  Web parity: app/(rail)/yards/page.tsx.
//  tRPC (server/routers/railShipments.ts):
//    ON ROUTE + STAGING lanes ← railShipments.getRailYards (yards; country
//      filter; capacity=carSlots, totalTracks). RBAC: railProcedure.
//    "Yard directory" CTA → railShipments.getRailYards (full list).
//    "Map" CTA → railShipments.getRailTracking (yard pins on the map).
//  PORT-GAP: RAMP shelf / per-facility staging detail wants
//    railShipments.getFacilityStatus(railroad, facilityCode) — a per-facility
//    call with no batch wrapper and no Swift API shim; the ramp shelf is
//    derived from the intermodal yards returned by getRailYards instead.
//

import SwiftUI

struct RailYardOperationsScreen: View {
    let theme: Theme.Palette
    var id: String = ""
    var body: some View {
        Shell(theme: theme) { RailYardOperationsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (railShipments.getRailYards → rail_yards rows)

private struct RailYard559: Decodable, Identifiable {
    let id: Int
    let name: String?
    let splcCode: String?
    let railroadId: Int?
    let city: String?
    let state: String?
    let country: String?
    let yardType: String?
    let totalTracks: Int?
    let capacity: Int?
    let hasIntermodal: Bool?
    let hasHazmat: Bool?
    let status: String?
    /// Real yard fix (rail_yards.coordinates JSON {lat,lng}) — keys the
    /// route-overview map. Optional: a yard row may predate geocoding.
    let coordinates: YardCoord559?
}

/// {lat,lng} payload from the rail_yards.coordinates JSON column.
private struct YardCoord559: Decodable, Hashable {
    let lat: Double
    let lng: Double
}

// MARK: - Visibility throttle (weather.realtime at the yard coordinate)

/// Point conditions read at one yard's `rail_yards.coordinates` via
/// `weather.realtime({lat,lon})` — the same realtime envelope the v3 widget
/// consumes (mirrors `WeatherForLoad.Realtime`). EVERY field is optional and
/// stays nil/`available:false` while the Apple WeatherKit feed is enterprise-gated,
/// so the throttle reads HONEST: no data ⇒ no tint, full slot capacity, no
/// chip — and lights up the moment the key lands. We never fabricate a
/// visibility mileage or a "degraded" verdict.
private struct YardWeather559: Decodable {
    let available: Bool?
    let weatherCode: Int?
    let condition: String?
    let visibilityMi: Double?

    // The realtime envelope names visibility `visibilityMi` (Apple WeatherKit v3
    // shape, matching WeatherForLoad.Realtime); legacy NWS-flavored points key
    // it `visibility`. Accept both so the throttle lights up whichever the
    // live proc emits — but only ever from a REAL field, never a default.
    enum CodingKeys: String, CodingKey {
        case available, weatherCode, condition, visibilityMi, visibility
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        available    = try c.decodeIfPresent(Bool.self,   forKey: .available)
        weatherCode  = try c.decodeIfPresent(Int.self,    forKey: .weatherCode)
        condition    = try c.decodeIfPresent(String.self, forKey: .condition)
        visibilityMi = try c.decodeIfPresent(Double.self, forKey: .visibilityMi)
            ?? c.decodeIfPresent(Double.self, forKey: .visibility)
    }

    /// Rail-yard low-visibility floor. Below ~1 mi, switching/humping crews
    /// throttle ladder moves and the yard's effective slot throughput drops —
    /// this is the corridor signal, NOT a fabricated capacity. We only ever
    /// DISCOUNT a real, enterprise-fed reading; we never invent the number.
    static let lowVisFloorMi: Double = 1.0

    /// REAL low-visibility state: a present mileage below the floor (and the
    /// feed not explicitly dark). Absent mileage / `available:false` ⇒ false,
    /// so the yard renders at full capacity with no tint.
    var isDegraded: Bool {
        if available == false { return false }
        guard let v = visibilityMi else { return false }
        return v < Self.lowVisFloorMi
    }

    /// Throughput discount (0…1 of nominal) derived from how far below the
    /// floor the REAL reading sits — 0.5 mi vis ⇒ ~0.5×, clamped to [0.35, 1].
    /// Nil (full capacity) whenever there's no degraded reading to discount.
    var capacityFactor: Double? {
        guard isDegraded, let v = visibilityMi else { return nil }
        return min(1.0, max(0.35, v / Self.lowVisFloorMi))
    }
}

// MARK: - Lane model

private enum YardPill {
    case active, hazmat, ramp, staging

    var label: String {
        switch self {
        case .active:  return "ACTIVE"
        case .hazmat:  return "HAZMAT"
        case .ramp:    return "RAMP"
        case .staging: return "STAGING"
        }
    }
    var color: Color {
        switch self {
        case .active:  return Brand.success
        case .hazmat:  return Brand.warning
        case .ramp:    return Brand.blue
        case .staging: return Color(hex: 0x90A4AE)
        }
    }
    var disc: Color {
        switch self {
        case .active:  return Color(hex: 0x2BD9A4)
        case .hazmat:  return Brand.warning
        case .ramp:    return Color(hex: 0x4FB0FF)
        case .staging: return Color(hex: 0x90A4AE)
        }
    }
}

// MARK: - Body

private struct RailYardOperationsBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @State private var yards: [RailYard559] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    /// Visibility throttle — point conditions per yard (keyed by yard id),
    /// hydrated best-effort from `weather.realtime` at each geocoded yard's
    /// coordinate. Empty until the fan-out lands; a yard with no entry (no
    /// geocode / no data / good vis) renders un-throttled at full capacity.
    @State private var yardWeather: [Int: YardWeather559] = [:]

    private let routeId = "RAIL-260523-7C3A0B12D4"

    /// The throttle reading for a yard, if any — only present when the feed
    /// returned REAL point conditions for that yard's coordinate.
    private func weather(for y: RailYard559) -> YardWeather559? { yardWeather[y.id] }

    // Lane partitions ---------------------------------------------------------

    private var stagingYards: [RailYard559] {
        yards.filter { ($0.yardType ?? "").lowercased() == "staging" }
    }
    private var onRouteYards: [RailYard559] {
        yards.filter { ($0.yardType ?? "").lowercased() != "staging" }
    }
    private var rampYards: [RailYard559] {
        yards.filter { ($0.hasIntermodal ?? false) || ($0.yardType ?? "").lowercased() == "intermodal_ramp" }
    }

    /// Largest car-slot capacity on the board — the relative-capacity bars
    /// scale every row against this so saturation reads at a glance.
    private var maxCapacity: Double {
        let cap = yards.compactMap { $0.capacity }.map(Double.init).max() ?? 0
        return cap > 0 ? cap : 1
    }

    private func pill(for y: RailYard559) -> YardPill {
        if (y.hasHazmat ?? false) && ((y.yardType ?? "").lowercased() == "classification") { return .hazmat }
        switch (y.yardType ?? "").lowercased() {
        case "staging":         return .staging
        case "intermodal_ramp": return .ramp
        default:                return .active
        }
    }

    // Route map ---------------------------------------------------------------

    /// Yards that carry a real geocode (rail_yards.coordinates) — the only ones
    /// the route-overview map can plot. Driven entirely by live data; if none
    /// are geocoded the map card is simply omitted.
    private var mappedYards: [RailYard559] {
        yards.filter { $0.coordinates != nil }
    }

    /// Camera anchor = centroid of the plotted yard fixes.
    private var mapCenter: HereLatLng {
        let pts = mappedYards.compactMap { $0.coordinates }
        guard !pts.isEmpty else { return HereLatLng(39.0, -98.0) } // CONUS fallback (unused: card hidden when empty)
        let lat = pts.map { $0.lat }.reduce(0, +) / Double(pts.count)
        let lng = pts.map { $0.lng }.reduce(0, +) / Double(pts.count)
        return HereLatLng(lat, lng)
    }

    /// Lane glyph → map marker kind (`.truck` puck for live on-route yards,
    /// endpoint glyphs for staging/ramp/hazmat), so the map reads the same
    /// status taxonomy as the swim-lanes below it.
    private func markerKind(for y: RailYard559) -> HereMarker.Kind {
        switch pill(for: y) {
        case .active:  return .truck
        case .ramp:    return .delivery
        case .staging: return .stop
        case .hazmat:  return .alert
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                if loading {
                    loadingBlock
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    .padding(.horizontal, 20).padding(.top, 16)
                } else if yards.isEmpty {
                    EusoEmptyState(systemImage: "square.stack.3d.up",
                                   title: "No yards on this route",
                                   subtitle: "Yards the consist will touch will appear here.")
                        .padding(.horizontal, 20).padding(.top, 24)
                } else {
                    filterChips
                        .padding(.horizontal, 20).padding(.top, 14)

                    // Route map — yard fixes plotted at their real geocodes
                    // (rail_yards.coordinates). Lane-colored pins; tap → ramp.
                    if !mappedYards.isEmpty {
                        routeMapCard
                            .padding(.horizontal, 20).padding(.top, 16)
                    }

                    // Lane 1 · ON ROUTE
                    laneHeader(title: "ON ROUTE · \(onRouteYards.count)", color: Color(hex: 0x2BD9A4))
                    onRouteCard
                        .padding(.horizontal, 20).padding(.top, 8)

                    // Lane 2 · STAGING · USMCA
                    if !stagingYards.isEmpty {
                        laneHeader(title: "STAGING · USMCA · \(stagingYards.count)", color: Color(hex: 0x90A4AE))
                        stagingCard
                            .padding(.horizontal, 20).padding(.top, 8)
                    }

                    // Lane 3 · RAMP · intermodal shelf
                    if !rampYards.isEmpty {
                        laneHeader(title: "RAMP · \(rampYards.count) INTERMODAL", color: palette.textTertiary)
                        rampShelf
                            .padding(.horizontal, 20).padding(.top, 8)
                    }

                    ctaPair
                        .padding(.horizontal, 20).padding(.top, 20)
                }

                Color.clear.frame(height: 96)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Top bar (route-scoped)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("RAIL ENGINEER · YARD OPS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text(routeId)
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Yard operations")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 8)
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .rotationEffect(.degrees(90))
            }
            .padding(.top, Space.s4)
            Text(routeSubtitle)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.leading, 24)
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, Space.s5)
    }

    private var routeSubtitle: String {
        // "BNSF transcon · Corwith → Argentine → LPC" — derived from the
        // on-route yards in railroad order; falls back to the route name.
        let names = onRouteYards.compactMap { $0.name }
        if names.count >= 2 {
            return names.prefix(3).joined(separator: " → ")
        }
        return "Yards on route \(routeId)"
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        let hazmatCount = onRouteYards.filter { pill(for: $0) == .hazmat }.count
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(text: "All · \(yards.count)", fg: .white, active: true)
                chip(text: "On route · \(onRouteYards.count)", fg: Color(hex: 0x2BD9A4), active: false)
                chip(text: "Hazmat · \(hazmatCount)", fg: Brand.warning, active: false)
                chip(text: "Staging · \(stagingYards.count)", fg: Color(hex: 0x90A4AE), active: false)
            }
        }
    }

    private func chip(text: String, fg: Color, active: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy)).tracking(0.4)
            .foregroundStyle(active ? .white : fg)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .frame(height: 26)
            .background(
                Group {
                    if active { AnyView(LinearGradient.primary) }
                    else      { AnyView(palette.bgCardSoft) }
                }
            )
            .overlay(
                Capsule().strokeBorder(active ? Color.clear : palette.borderSoft, lineWidth: 1)
            )
            .clipShape(Capsule())
    }

    // MARK: - Lane header

    private func laneHeader(title: String, color: Color) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(color)
                Spacer()
                Text("see all ›")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    // MARK: - Route map (in-house HERE · BespokeMapCanvas · standard register)

    /// A bespoke yard-positions board: every geocoded yard plotted at its real
    /// rail_yards.coordinates fix, colored by the same lane taxonomy as the
    /// swim-lanes (active=puck, ramp=delivery, staging=stop, hazmat=alert).
    /// RAIL has no dedicated style ⇒ flat `.standard` register (tilt 0, no
    /// ocean hint). Tapping a pin swaps to the rail tracking map (Rail560).
    private var routeMapCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ROUTE MAP · \(mappedYards.count) PLOTTED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("tap a yard ›")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            HereVectorMapView(
                center: mapCenter,
                zoom: 4,
                interactive: true,
                tilt: 0,
                layers: [
                    .markers(mappedYards.compactMap { y in
                        guard let c = y.coordinates else { return nil }
                        return HereMarker(
                            at: HereLatLng(c.lat, c.lng),
                            kind: markerKind(for: y),
                            label: y.name,
                            id: String(y.id))
                    })
                ],
                onSelectMarker: { _ in
                    NotificationCenter.default.post(
                        name: .eusoRailNavSwap, object: nil,
                        userInfo: ["screenId": "Rail560"])
                }
            )
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Lane 1 · ON ROUTE card (yard rows w/ relative-capacity bars)

    private var onRouteCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(onRouteYards.enumerated()), id: \.element.id) { idx, y in
                yardRow(y)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                if idx < onRouteYards.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                        .padding(.horizontal, 16)
                }
            }
        }
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Lane 2 · STAGING card

    private var stagingCard: some View {
        VStack(spacing: 0) {
            ForEach(stagingYards) { y in
                yardRow(y)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
            }
        }
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Yard row (icon disc · name · meta · capacity bar · pill · count)

    private func yardRow(_ y: RailYard559) -> some View {
        let kind = pill(for: y)
        // Visibility throttle: a REAL low-vis reading at this yard's geocode
        // tints the row DEGRADED and discounts its effective slot capacity.
        // No reading (no geocode / no data / good vis) ⇒ wx == nil ⇒ the row
        // renders exactly as before (full capacity, no tint, no chip).
        let wx = weather(for: y)
        let degraded = wx?.isDegraded ?? false
        // Effective disc/bar tint — amber throttle signal when degraded, else
        // the lane's own status color (unchanged).
        let barTint: Color = degraded ? Brand.warning : kind.disc

        let nominalCap = y.capacity ?? 0
        // Throttled slot count: nominal × the REAL visibility factor (floored).
        // Only a present, degraded reading discounts; otherwise == nominal.
        let throttledCap: Int = {
            guard let f = wx?.capacityFactor else { return nominalCap }
            return Int((Double(nominalCap) * f).rounded(.down))
        }()
        // Bar saturation reflects the THROTTLED throughput so the discount
        // reads at a glance; still scaled against the board's nominal max.
        let frac = max(0.04, min(1.0, Double(throttledCap) / maxCapacity))

        let metaParts: [String] = [
            [y.city, y.state].compactMap { $0 }.joined(separator: " "),
            railroadName(y.railroadId),
            stagingMeta(y) ?? "\(y.totalTracks ?? 0) tracks"
        ].filter { !$0.isEmpty }
        let meta = metaParts.joined(separator: " · ")

        return HStack(alignment: .top, spacing: 0) {
            // Icon disc — amber wash + bespoke eye glyph overlay when throttled.
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill((degraded ? Brand.warning : kind.color).opacity(0.14))
                    .frame(width: 40, height: 40)
                if degraded {
                    WeatherIcons.utility(.eye, size: 19, tint: Brand.warning)
                } else {
                    Image(systemName: "rectangle.split.1x2")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(kind.disc)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    Text(y.name ?? "Yard")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 8)
                    // DEGRADED throttle pill — only when a real low-vis reading
                    // discounts this yard. Sits left of the lane status pill.
                    if degraded {
                        Text("DEGRADED")
                            .font(.system(size: 10.5, weight: .bold)).tracking(0.4)
                            .foregroundStyle(Brand.warning)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(Capsule().fill(Brand.warning.opacity(0.16)))
                    }
                    // Status pill
                    Text(kind.label)
                        .font(.system(size: 10.5, weight: .bold)).tracking(0.4)
                        .foregroundStyle(kind.disc)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(kind.color.opacity(0.16)))
                }
                Text(meta)
                    .font(EType.mono(.caption)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, 4)
                    .lineLimit(1).minimumScaleFactor(0.7)

                // Visibility chip — bespoke WeatherIcons.eye + the REAL mileage
                // from the throttle reading. Only rendered when degraded; never
                // a fabricated value (no chip when the feed is dark / vis good).
                if degraded, let v = wx?.visibilityMi {
                    HStack(spacing: 5) {
                        WeatherIcons.utility(.eye, size: 12, tint: Brand.warning)
                        Text("\(v.formatted(.number.precision(.fractionLength(0...1)))) mi visibility")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Brand.warning)
                            .lineLimit(1)
                    }
                    .padding(.top, 6)
                }

                // Capacity bar + slot count row
                HStack(alignment: .bottom, spacing: 12) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.14))
                                .frame(height: 6)
                            Capsule().fill(barTint)
                                .frame(width: max(6, geo.size.width * frac), height: 6)
                        }
                    }
                    .frame(height: 6)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(capacityString(degraded ? throttledCap : y.capacity))
                            .font(.system(size: 14, weight: .bold)).monospacedDigit()
                            .foregroundStyle(degraded ? Brand.warning : palette.textPrimary)
                        // When throttled, label the discount honestly against
                        // the nominal (e.g. "of 1,800 · throttled"); otherwise
                        // the unchanged slot/track unit.
                        Text(throttleSublabel(kind: kind, y: y, degraded: degraded))
                            .font(.system(size: 9, weight: .regular))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .fixedSize()
                }
                .padding(.top, 12)
            }
            .padding(.leading, 12)
        }
    }

    /// The capacity sublabel — nominal-vs-throttled when low vis discounts the
    /// yard, else the unchanged slot/track unit. Never invents a number; the
    /// "of N" is the yard's own real nominal capacity.
    private func throttleSublabel(kind: YardPill, y: RailYard559, degraded: Bool) -> String {
        if degraded, let nominal = y.capacity {
            return "of \(capacityString(nominal)) · throttled"
        }
        return kind == .staging ? "\(y.totalTracks ?? 0) tracks" : "car slots"
    }

    private func capacityString(_ cap: Int?) -> String {
        guard let cap = cap else { return "-" }
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        return fmt.string(from: NSNumber(value: cap)) ?? "\(cap)"
    }

    /// Staging rows surface the SPLC + interchange instead of a city.
    private func stagingMeta(_ y: RailYard559) -> String? {
        guard (y.yardType ?? "").lowercased() == "staging" else { return nil }
        var parts: [String] = []
        if let splc = y.splcCode, !splc.isEmpty { parts.append("SPLC \(splc)") }
        parts.append(railroadName(y.railroadId))
        parts.append("USMCA interchange")
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Map railroadId → reporting mark. We don't have a railroad-name join in
    /// this query, so render the AAR mark from the id where known and fall
    /// back to the raw id. // PORT-GAP: railShipments.getRailYards does not
    /// join rail_carriers — no reporting mark is returned with the yard row.
    private func railroadName(_ id: Int?) -> String {
        guard let id = id else { return "" }
        return "RR-\(id)"
    }

    // MARK: - Lane 3 · RAMP intermodal shelf (facility cards)

    private var rampShelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(rampYards.prefix(3)) { y in
                    rampCard(y)
                }
            }
        }
    }

    private func rampCard(_ y: RailYard559) -> some View {
        let dot: Color = {
            switch pill(for: y) {
            case .hazmat:  return Brand.warning
            case .ramp:    return Brand.blue
            case .staging: return Color(hex: 0x90A4AE)
            case .active:  return Color(hex: 0x00C48C)
            }
        }()
        let line2: String = (y.status ?? "open").lowercased() == "active" ? "open · accepting" : (y.status ?? "open · accepting")
        let line3 = [railroadName(y.railroadId), y.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Circle().fill(dot).frame(width: 7, height: 7)
                Text("\(shortName(y.name)) ramp")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.leading, 8)
                    .lineLimit(1)
            }
            Text(line2)
                .font(.system(size: 9.5, weight: .regular))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 16)
                .lineLimit(1)
            Text(line3)
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 4)
                .lineLimit(1)
        }
        .padding(14)
        .frame(width: 124, height: 64, alignment: .topLeading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func shortName(_ name: String?) -> String {
        guard let name = name else { return "Yard" }
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: 8) {
            Button(action: { Task { await loadDirectory() } }) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.split.1x2")
                        .font(.system(size: 14, weight: .bold))
                    Text("Yard directory")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient.primary)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: { NotificationCenter.default.post(name: .eusoRailNavSwap, object: nil, userInfo: ["screenId": "Rail560"]) }) {
                Text("Map")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading skeleton

    private var loadingBlock: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 88)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
        }
        .padding(.horizontal, 20).padding(.top, 16)
    }

    // MARK: - Load

    private struct YardsIn: Encodable {
        let country: String?
        let limit: Int
    }

    /// `weather.realtime` input — point conditions at a yard's geocode.
    private struct RealtimeIn: Encodable {
        let lat: Double
        let lon: Double
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let rows: [RailYard559] = try await EusoTripAPI.shared.query(
                "railShipments.getRailYards", input: YardsIn(country: nil, limit: 50))
            self.yards = rows
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
        // Fan out the visibility throttle AFTER the board is up so yards paint
        // immediately; the throttle tints/discounts in as readings arrive.
        await hydrateYardWeather()
    }

    /// "Yard directory" CTA — full list, no route filter (getRailYards).
    private func loadDirectory() async {
        do {
            let rows: [RailYard559] = try await EusoTripAPI.shared.query(
                "railShipments.getRailYards", input: YardsIn(country: nil, limit: 50))
            self.yards = rows
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        await hydrateYardWeather()
    }

    /// Visibility throttle — read point conditions at each GEOCODED yard's
    /// `rail_yards.coordinates` via `weather.realtime({lat,lon})`. Best-effort:
    /// a miss on any yard just leaves it un-throttled (full capacity, no tint).
    /// Everything is enterprise-gated server-side, so today these resolve to
    /// `available:false` / nil visibility and NO yard tints — the honest empty
    /// state — and they light up the moment the Apple WeatherKit key lands. We never
    /// fabricate a visibility reading or a "degraded" verdict.
    private func hydrateYardWeather() async {
        let geocoded = yards.compactMap { y -> (Int, YardCoord559)? in
            guard let c = y.coordinates else { return nil }
            return (y.id, c)
        }
        guard !geocoded.isEmpty else { return }
        let readings = await withTaskGroup(of: (Int, YardWeather559?).self) { group in
            for (id, c) in geocoded {
                group.addTask {
                    let wx: YardWeather559? = try? await EusoTripAPI.shared.query(
                        "weather.realtime", input: RealtimeIn(lat: c.lat, lon: c.lng))
                    return (id, wx)
                }
            }
            var acc: [Int: YardWeather559] = [:]
            for await (id, wx) in group {
                if let wx { acc[id] = wx }
            }
            return acc
        }
        self.yardWeather = readings
    }
}

#Preview("559 · Rail Yard Operations · Night") { RailYardOperationsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("559 · Rail Yard Operations · Light") { RailYardOperationsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
