//
//  559_RailYardOperations.swift
//  EusoTrip — Rail Engineer · Yard Operations (BOARD archetype).
//
//  Verbatim port of "559 Rail Yard Operations · Dark" (05 Rail).
//  Status swim-lanes (ON ROUTE · STAGING/USMCA · RAMP) of full-width yard
//  rows, each carrying a relative-capacity bar (slot capacity scaled to the
//  largest yard on the route) + track counts + status pill + railroad disc.
//  Board scope is whatever getRailYards returns — no route, carrier or
//  corridor is asserted anywhere on this screen.
//
//  Web parity: app/(rail)/yards/page.tsx.
//  tRPC (server/routers/railShipments.ts):
//    Lanes ← railShipments.getRailYards (railShipments.ts:1512; capacity,
//      totalTracks, status, hasHazmat). RBAC: railReadProcedure.
//    "Yard directory" CTA → the SAME procedure at the directory limit, which
//      lifts the board's 50-row cap (`limit` is z.number().default(50) with no
//      max — railShipments.ts:1519) and flips the board into a labelled
//      DIRECTORY state. Not a re-run of the query already on screen.
//    "Map" CTA → Rail560 (rail tracking map).
//
//  SCOPE, STATED HONESTLY: getRailYards takes railroadId / state / country /
//    yardType / hasIntermodal / limit — there is NO route or shipment
//    parameter. This board is therefore NOT route-filtered, and it no longer
//    claims to be.
//
//  §W OFFLINE: READ_CACHED(none) — a read-only board with no commit on it. It
//    holds no local cache, so offline it shows its real load error rather than
//    a stale yard list. Nothing here is queued.
//
//  PORT-GAP: RAMP shelf / per-facility staging detail wants
//    railShipments.getFacilityStatus(railroad, facilityCode) — a per-facility
//    call with no batch wrapper and no Swift API shim; the ramp shelf is
//    derived from the intermodal yards returned by getRailYards instead.
//  NAMED GAP · esang-screen-enum-rail: esangCoach.forScreen EXISTS
//    (esangCoach.ts:264) but its SCREEN_ENUM (esangCoach.ts:112-125) carries no
//    rail or yard key and its system prompt is an in-cab DRIVER coach speaking
//    HOS/DVIR. Calling it with a driver key would return the wrong entity, so
//    the 559 spec's ESANG routing note is NOT wired and NOT faked. Same call
//    the sibling yard screen 665 made (665:95).
//

import SwiftUI
import CoreLocation

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

    var coordinate: CLLocationCoordinate2D? {
        LatLongParser.validatedCoordinate(latitude: lat, longitude: lng)
    }
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

/// Lane taxonomy. `.unknown` is a first-class state, not a fallback: a yard
/// whose `yardType` is absent, or a classification yard whose `hasHazmat` is
/// absent, cannot be classified and must never be painted green ACTIVE.
private enum YardPill {
    case active, hazmat, ramp, staging, unknown

    var label: String {
        switch self {
        case .active:  return "ACTIVE"
        case .hazmat:  return "HAZMAT"
        case .ramp:    return "RAMP"
        case .staging: return "STAGING"
        case .unknown: return "UNKNOWN"
        }
    }
    var color: Color {
        switch self {
        case .active:  return Brand.success
        case .hazmat:  return Brand.warning
        case .ramp:    return Brand.blue
        case .staging: return Color(hex: 0x90A4AE)
        case .unknown: return Brand.warning
        }
    }
    var disc: Color {
        switch self {
        case .active:  return Color(hex: 0x2BD9A4)
        case .hazmat:  return Brand.warning
        case .ramp:    return Color(hex: 0x4FB0FF)
        case .staging: return Color(hex: 0x90A4AE)
        case .unknown: return Brand.warning
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
    /// True while the board is showing the FULL yard directory (the board's own
    /// 50-row cap lifted) rather than the default board load. The CTA's effect
    /// is visible precisely because this drives a labelled on-screen state.
    @State private var directoryMode = false
    @State private var directoryLoading = false

    /// The board load cap, and the directory ceiling the "Yard directory" CTA
    /// raises it to. `getRailYards.limit` is `z.number().default(50)` with no
    /// max (railShipments.ts:1519), so both are legal inputs.
    private static let boardLimit = 50
    private static let directoryLimit = 200

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
        let type = (y.yardType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // No yard type on the row ⇒ the lane cannot be classified. That is
        // UNKNOWN. It used to fall through to a green ACTIVE pill.
        guard !type.isEmpty else { return .unknown }
        if type == "classification" {
            // `hasHazmat` is `boolean(...).default(true)` (drizzle/schema.ts:11163),
            // so coalescing it to false inverted the column's own default and
            // painted a hazmat-capable classification yard as plain green
            // ACTIVE. Absent ⇒ UNKNOWN, never "not hazmat".
            guard let hazmat = y.hasHazmat else { return .unknown }
            return hazmat ? .hazmat : .active
        }
        switch type {
        case "staging":         return .staging
        case "intermodal_ramp": return .ramp
        default:                return .active
        }
    }

    /// `rail_yards.status` is an operational-record enum
    /// (active | inactive | maintenance — drizzle/schema.ts:11165). It does NOT
    /// model gate acceptance, so nothing here says "accepting". An absent value
    /// renders as not reported, never as "open".
    private func yardStatusLine(_ y: RailYard559) -> String {
        guard let raw = y.status?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return "status not reported" }
        switch raw.lowercased() {
        case "active":      return "listed active"
        case "inactive":    return "listed inactive"
        case "maintenance": return "in maintenance"
        default:            return "status \(raw)"
        }
    }

    // Route map ---------------------------------------------------------------

    /// Yards that carry a real geocode (rail_yards.coordinates) — the only ones
    /// the route-overview map can plot. Driven entirely by live data; if none
    /// are geocoded the map card is simply omitted.
    private var mappedYards: [RailYard559] {
        yards.filter { $0.coordinates?.coordinate != nil }
    }

    /// Camera anchor = centroid of the plotted yard fixes.
    private var mapCenter: HereLatLng? {
        let pts = mappedYards.compactMap { $0.coordinates?.coordinate }
        guard let first = pts.first else { return nil }
        let latitude = pts.map(\.latitude).reduce(0, +) / Double(pts.count)
        let longitude = pts.map(\.longitude).reduce(0, +) / Double(pts.count)
        let center = LatLongParser.validatedCoordinate(
            latitude: latitude,
            longitude: longitude
        ) ?? first
        return HereLatLng(center)
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
        // An unclassifiable yard gets the attention glyph, never the live puck.
        case .unknown: return .alert
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

                    if directoryMode {
                        directoryModeBanner
                            .padding(.horizontal, 20).padding(.top, 12)
                    }

                    // Route map — yard fixes plotted at their real geocodes
                    // (rail_yards.coordinates). Lane-colored pins; tap → ramp.
                    if let mapCenter {
                        routeMapCard(center: mapCenter)
                            .padding(.horizontal, 20).padding(.top, 16)
                    }

                    // Lane 1 · OPERATING (non-staging). This lane is
                    // `yardType != "staging"` — it is NOT a route membership
                    // test, and no longer claims to be.
                    laneHeader(title: "OPERATING · \(onRouteYards.count)", color: Color(hex: 0x2BD9A4))
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
        .eusoRefreshable { await load() }
    }

    // MARK: - Top bar (route-scoped)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    EusoTripBrandMark(size: 12)
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("RAIL ENGINEER · YARD OPS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                // The board scope, not a route id. getRailYards has no route
                // parameter, so a route reference here would attribute this
                // list to a route the query never asked for.
                Text(directoryMode ? "FULL DIRECTORY" : "YARD BOARD")
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
        // This used to join three arbitrary yard names with arrows, presenting
        // an ORDERED ROUTE that getRailYards cannot know: the procedure takes
        // railroadId / state / country / yardType / hasIntermodal / limit and
        // applies no route filter and no route ordering
        // (railShipments.ts:1513-1532). We state the real scope instead.
        let n = yards.count
        let unit = "yard\(n == 1 ? "" : "s")"
        return directoryMode
            ? "Full yard directory · \(n) \(unit) · not route-filtered"
            : "Yard board · \(n) \(unit) · not route-filtered"
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        let hazmatCount = onRouteYards.filter { pill(for: $0) == .hazmat }.count
        // Unclassifiable yards get their own visible count instead of being
        // absorbed into the green "operating" tally.
        let unknownCount = yards.filter { pill(for: $0) == .unknown }.count
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(text: "All · \(yards.count)", fg: .white, active: true)
                chip(text: "Operating · \(onRouteYards.count)", fg: Color(hex: 0x2BD9A4), active: false)
                chip(text: "Hazmat · \(hazmatCount)", fg: Brand.warning, active: false)
                chip(text: "Staging · \(stagingYards.count)", fg: Color(hex: 0x90A4AE), active: false)
                if unknownCount > 0 {
                    chip(text: "Unclassified · \(unknownCount)", fg: Brand.warning, active: false)
                }
            }
        }
    }

    /// The directory state made visible. Without an on-screen change the
    /// "Yard directory" CTA would still be a no-op affordance, whatever it
    /// queried.
    private var directoryModeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.blue)
            Text("FULL DIRECTORY · \(yards.count) YARDS · NO ROUTE FILTER")
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                .foregroundStyle(Brand.blue)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Brand.blue.opacity(0.10))
        .overlay(Capsule().strokeBorder(Brand.blue.opacity(0.30)))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Full yard directory")
        .accessibilityValue("\(yards.count) yards listed. No route filter is applied.")
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
    private func routeMapCard(center: HereLatLng) -> some View {
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
                center: center,
                zoom: 4,
                interactive: true,
                tilt: 0,
                layers: [
                    .markers(mappedYards.compactMap { y in
                        guard let coordinate = y.coordinates?.coordinate else { return nil }
                        return HereMarker(
                            at: HereLatLng(coordinate),
                            kind: markerKind(for: y),
                            label: y.name,
                            id: String(y.id))
                    })
                ],
                mapModeContext: .primary(.rail),
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

        // UNKNOWN CAPACITY stays nil the whole way to the bar. The old
        // `capacity ?? 0` fed a `max(0.04, …)` floor, so a yard whose capacity
        // column is empty still drew a visible sliver that read as "it has
        // some". Nil now draws NO fill at all.
        let nominalCap: Int? = y.capacity
        // Throttled slot count: nominal × the REAL visibility factor (floored).
        // Only a present, degraded reading discounts; otherwise == nominal.
        let throttledCap: Int? = {
            guard let cap = nominalCap else { return nil }
            guard let f = wx?.capacityFactor else { return cap }
            return Int((Double(cap) * f).rounded(.down))
        }()
        // Bar saturation reflects the THROTTLED throughput so the discount
        // reads at a glance; still scaled against the board's nominal max.
        // Nil ⇒ the bar renders as a dashed unknown rail, never a fill.
        let frac: Double? = throttledCap.map { min(1.0, max(0, Double($0) / maxCapacity)) }

        let metaParts: [String] = [
            [y.city, y.state].compactMap { $0 }.joined(separator: " "),
            railroadName(y.railroadId),
            // A yard with no track count used to render "0 tracks".
            stagingMeta(y) ?? (y.totalTracks.map { "\($0) tracks" } ?? "tracks not reported")
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
                            if let frac {
                                Capsule().fill(Color.white.opacity(0.14))
                                    .frame(height: 6)
                                Capsule().fill(barTint)
                                    .frame(width: max(0, geo.size.width * frac), height: 6)
                            } else {
                                // Capacity not reported — a dashed empty rail,
                                // visibly distinct from a yard at zero slots.
                                Capsule()
                                    .strokeBorder(Brand.warning.opacity(0.55),
                                                  style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                    .frame(height: 6)
                            }
                        }
                    }
                    .frame(height: 6)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(capacityString(degraded ? throttledCap : y.capacity))
                            .font(.system(size: 14, weight: .bold)).monospacedDigit()
                            .foregroundStyle(y.capacity == nil ? Brand.warning
                                             : (degraded ? Brand.warning : palette.textPrimary))
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
        // Every state string on this row reaches VoiceOver — the UNKNOWN pill,
        // the not-reported capacity and the throttle are states, not colours.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(y.name ?? "Yard, name not reported")
        .accessibilityValue(yardRowAccessibility(y, kind: kind, degraded: degraded,
                                                 throttledCap: throttledCap, meta: meta))
    }

    /// The spoken equivalent of the row. Nothing here is derived from a
    /// default: an absent field is spoken as not reported.
    private func yardRowAccessibility(_ y: RailYard559,
                                      kind: YardPill,
                                      degraded: Bool,
                                      throttledCap: Int?,
                                      meta: String) -> String {
        var parts: [String] = [kind.label, yardStatusLine(y)]
        if kind == .unknown {
            parts.append(y.yardType == nil
                         ? "Yard type not reported, so the lane cannot be classified"
                         : "Hazmat capability not reported, so this classification yard cannot be ruled in or out")
        }
        if let cap = y.capacity {
            parts.append(degraded
                         ? "\(capacityString(throttledCap)) car slots, throttled from \(capacityString(cap))"
                         : "\(capacityString(cap)) car slots")
        } else {
            parts.append("Capacity not reported")
        }
        parts.append(y.totalTracks.map { "\($0) tracks" } ?? "Track count not reported")
        if degraded, let v = weather(for: y)?.visibilityMi {
            parts.append("Degraded, \(v.formatted(.number.precision(.fractionLength(0...1)))) miles visibility")
        }
        if !meta.isEmpty { parts.append(meta) }
        return parts.joined(separator: ". ")
    }

    /// The capacity sublabel — nominal-vs-throttled when low vis discounts the
    /// yard, else the unchanged slot/track unit. Never invents a number; the
    /// "of N" is the yard's own real nominal capacity.
    private func throttleSublabel(kind: YardPill, y: RailYard559, degraded: Bool) -> String {
        if degraded, let nominal = y.capacity {
            return "of \(capacityString(nominal)) · throttled"
        }
        if kind == .staging {
            return y.totalTracks.map { "\($0) tracks" } ?? "track count not reported"
        }
        return y.capacity == nil ? "capacity not reported" : "car slots"
    }

    /// Em-dash for an absent capacity — never a zero, and never a formatted 0.
    private func capacityString(_ cap: Int?) -> String {
        guard let cap = cap else { return "—" }
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
        let kind = pill(for: y)
        let dot: Color = {
            switch kind {
            case .hazmat:  return Brand.warning
            case .ramp:    return Brand.blue
            case .staging: return Color(hex: 0x90A4AE)
            case .active:  return Color(hex: 0x00C48C)
            case .unknown: return Brand.warning
            }
        }()
        // Both branches of the old ternary rendered "open · accepting", so a
        // yard of UNKNOWN status was shown to the dispatcher as open and taking
        // cars. `rail_yards.status` is active | inactive | maintenance
        // (drizzle/schema.ts:11165) — an operational-record enum that models no
        // gate-acceptance state at all — so nothing here claims "accepting".
        let line2 = yardStatusLine(y)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(shortName(y.name)) ramp")
        .accessibilityValue([kind.label, line2, line3].filter { !$0.isEmpty }.joined(separator: ". "))
    }

    private func shortName(_ name: String?) -> String {
        guard let name = name else { return "Yard" }
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: 8) {
            Button(action: {
                Task {
                    if directoryMode { await load() } else { await loadDirectory() }
                }
            }) {
                HStack(spacing: 8) {
                    if directoryLoading {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: directoryMode ? "arrow.uturn.backward" : "rectangle.split.1x2")
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text(directoryMode ? "Back to yard board" : "Yard directory")
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient.primary)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(directoryLoading)
            .opacity(directoryLoading ? 0.6 : 1)
            .accessibilityLabel(directoryMode ? "Back to yard board" : "Open yard directory")
            .accessibilityValue(directoryMode
                ? "Showing the full directory, \(yards.count) yards. Activates to return to the \(Self.boardLimit) yard board."
                : "Showing the \(Self.boardLimit) yard board, \(yards.count) listed. Activates to load the full directory.")

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
            .accessibilityLabel("Open rail tracking map")
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

    /// The default board load, capped at `boardLimit`.
    private func load() async {
        loading = true; loadError = nil
        do {
            let rows: [RailYard559] = try await EusoTripAPI.shared.query(
                "railShipments.getRailYards", input: YardsIn(country: nil, limit: Self.boardLimit))
            self.yards = rows
            self.directoryMode = false
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
        // Fan out the visibility throttle AFTER the board is up so yards paint
        // immediately; the throttle tints/discounts in as readings arrive.
        await hydrateYardWeather()
    }

    /// "Yard directory" CTA — genuinely distinct from `load()`, which it used to
    /// duplicate byte for byte (same procedure, same `limit: 50`, same nil
    /// country) so that tapping it changed nothing on screen. It now lifts the
    /// board's own cap to the directory ceiling and flips the board into a
    /// labelled DIRECTORY state, so both the query AND the render differ.
    private func loadDirectory() async {
        directoryLoading = true
        loadError = nil
        defer { directoryLoading = false }
        do {
            let rows: [RailYard559] = try await EusoTripAPI.shared.query(
                "railShipments.getRailYards", input: YardsIn(country: nil, limit: Self.directoryLimit))
            self.yards = rows
            self.directoryMode = true
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
        let geocoded = yards.compactMap { y -> (Int, CLLocationCoordinate2D)? in
            guard let coordinate = y.coordinates?.coordinate else { return nil }
            return (y.id, coordinate)
        }
        guard !geocoded.isEmpty else { return }
        let readings = await withTaskGroup(of: (Int, YardWeather559?).self) { group in
            for (id, c) in geocoded {
                group.addTask {
                    let wx: YardWeather559? = try? await EusoTripAPI.shared.query(
                        "weather.realtime",
                        input: RealtimeIn(lat: c.latitude, lon: c.longitude)
                    )
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
