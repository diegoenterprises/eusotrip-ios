//
//  671_VesselMarineWeatherRouting.swift
//  EusoTrip — Vessel Operator · Marine Weather Routing.
//
//  Bespoke port of canonical wireframe 671 (06 Vessel · Dark). MapCanvas hero
//  shows the per-voyage route arc with weather waypoints; voyage legs + ESang
//  advisory below.
//
//  ───────── REAL PER-VOYAGE ENDPOINTS (same chain Vessel 660 uses) ─────────
//  This screen is per-voyage: it loads ONE booking and routes/weathers THAT
//  voyage. The origin + destination ports come from the booking, not literals:
//
//    vesselShipments.getVesselShipmentDetail({ id })  (EXISTS :263)
//        → returns full `ports` rows as originPort / destinationPort, each
//          carrying `unlocode` AND `coordinates {lat,lng}` (schema.ts :10269).
//        → coords resolve from the DB `coordinates` field (primary) or
//          PortDirectory.find(unlocode:) (fallback) — the SAME great-circle
//          endpoint path 660 + Vessel 003 use. NO hardcoded coordinate array.
//
//  Map hero = the canonical ocean register `VesselOceanTrackMap`
//  (→ BespokeMapCanvas style:.ocean) drawn on the resolved real port coords +
//  the live AIS feed keyed by the booking's vessel IMO. The route-weather
//  waypoints handed to getRouteWeather are the great circle BETWEEN the two
//  resolved real ports (BespokeMapProjection.greatCircle), never literals.
//
//  Weather VALUES (per-leg wind / swell / sea-state) come strictly from:
//    vesselShipments.getRouteWeather({ waypoints })   (EXISTS :1804)
//    vesselShipments.getMarineWeather({ lat, lng })   (EXISTS :1790)
//  Both DTN-backed procs return `null` when the marine-weather feed is not
//  configured/seeded (the wireframe's flagged seed gap). We honor that with a
//  real "feed unavailable" empty state — the route geometry (from real ports)
//  still draws; the forecast values simply omit. Never fabricated.
//
//  Default booking = the live in-transit voyage (real DB row). Coord gate
//  (Driver 013 pattern): the ocean map draws only when BOTH ports resolve —
//  otherwise a neutral "awaiting endpoints" placeholder, never null island.
//

import SwiftUI

struct VesselMarineWeatherRoutingScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int
    var imoNumber: String

    // Default = the live in-transit booking (real DB row id 8 · MV Pacific Star
    // · IMO 9876545 · ARBUE → AUBNE). A design-time default only — overwritten
    // by whatever booking is routed in; the ports + coords come from the read.
    init(theme: Theme.Palette, shipmentId: Int = 8, imoNumber: String = "9876545") {
        self.theme = theme; self.shipmentId = shipmentId; self.imoNumber = imoNumber
    }

    var body: some View {
        Shell(theme: theme) {
            VesselMarineWeatherRoutingBody(shipmentId: shipmentId, imoNumber: imoNumber)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror server/routers/vesselShipments.ts)

/// Port join from getVesselShipmentDetail (:289 returns the full `ports` row).
/// Carries UN/LOCODE + name + the DB `coordinates {lat,lng}` JSON. The coords
/// resolve the great-circle endpoints — real-coordinate path identical to 660.
private struct PortCoords671: Decodable { let lat: Double?; let lng: Double? }
private struct VesselPort671: Decodable {
    let name: String?
    let unlocode: String?
    let coordinates: PortCoords671?
}
private struct VesselDetail671: Decodable {
    let bookingNumber: String?
    let originPort: VesselPort671?
    let destinationPort: VesselPort671?
}

/// One segment of the route-weather response. All numerics optional so a
/// partial/null DTN payload decodes without throwing.
private struct RouteWeatherSegment671: Decodable, Identifiable {
    let segmentIndex: Int?
    let startLat: Double?
    let startLng: Double?
    let endLat: Double?
    let endLng: Double?
    let windSpeed: Double?
    let windDirection: Double?
    let waveHeight: Double?
    let swellHeight: Double?
    let visibility: Double?
    let riskLevel: String?
    let riskFactors: [String]?
    let optimalSpeed: Double?
    let timestamp: String?

    var id: Int { segmentIndex ?? Int.random(in: Int.min...Int.max) }
}

private struct RouteWeatherResponse671: Decodable {
    let segments: [RouteWeatherSegment671]?
    let overallRisk: String?
    let warnings: [String]?
    let recommendedDeparture: String?
    let generatedAt: String?
}

/// Marine forecast at the route midpoint.
private struct MarineForecastCurrent671: Decodable {
    let windSpeed: Double?
    let windDirection: Double?
    let windGust: Double?
    let waveHeight: Double?
    let swellHeight: Double?
    let visibility: Double?
}
private struct MarineForecast671: Decodable {
    let lat: Double?
    let lng: Double?
    let generatedAt: String?
    let current: MarineForecastCurrent671?
}

// MARK: - Body

private struct VesselMarineWeatherRoutingBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    let imoNumber: String

    // Booking endpoints (getVesselShipmentDetail) — nil until the booking read
    // lands. The ocean map + the getRouteWeather waypoints both gate on these,
    // so nothing routes until the REAL ports resolve.
    @State private var originPort: VesselPort671? = nil
    @State private var destinationPort: VesselPort671? = nil
    @State private var bookingRef: String? = nil

    @State private var route: RouteWeatherResponse671? = nil
    @State private var marine: MarineForecast671? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    /// True when the procedures resolve but the DTN marine-weather feed is not
    /// configured (server returns `null`) — the wireframe's flagged seed gap.
    @State private var feedUnavailable = false
    /// True when the booking has no routable origin/destination ports.
    @State private var endpointsUnavailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
            VStack(alignment: .leading, spacing: Space.s4) {
                mapHero
                voyageLegs
                esangAdvisory
                cta
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            Color.clear.frame(height: Space.s5)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Origin / destination resolution (DB coords → PortDirectory fallback)

    /// Origin great-circle endpoint — the booking's origin port. Resolves from
    /// the DB `coordinates {lat,lng}` field first (the proc returns the full
    /// `ports` row), else the UN/LOCODE through PortDirectory (660 / 003 path).
    /// nil until a real booking lands ⇒ the coord gate keeps the placeholder.
    private var originCoord: HereLatLng? { coord(for: originPort) }
    private var destinationCoord: HereLatLng? { coord(for: destinationPort) }

    private func coord(for port: VesselPort671?) -> HereLatLng? {
        guard let port else { return nil }
        if let lat = port.coordinates?.lat, let lng = port.coordinates?.lng,
           !(lat == 0 && lng == 0) {
            return HereLatLng(lat, lng)
        }
        if let code = port.unlocode, !code.isEmpty, let p = PortDirectory.find(unlocode: code) {
            return HereLatLng(p.lat, p.lng)
        }
        return nil
    }

    private var originLabel: String { originPort?.name ?? originPort?.unlocode ?? "Origin" }
    private var destinationLabel: String { destinationPort?.name ?? destinationPort?.unlocode ?? "Destination" }
    private var originCode: String { originPort?.unlocode ?? "ORIG" }
    private var destCode: String { destinationPort?.unlocode ?? "DEST" }

    // MARK: - Top bar (eyebrow + title)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "sparkle")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(LinearGradient.primary)
                Text("VESSEL OPERATOR · WEATHER")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
            }
            Text("Route Weather")
                .font(.system(size: 30, weight: .bold)).tracking(-0.5)
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s4)
            Text(topSubtitle)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 2)
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s4)
    }

    private var topSubtitle: String {
        if let o = originCoord, let d = destinationCoord, o.lat != 0 || d.lat != 0 {
            return "getRouteWeather · \(originCode) → \(destCode) · live AIS track"
        }
        return "getRouteWeather · per-voyage · live AIS track"
    }

    // MARK: - MapCanvas hero · ocean register on real port endpoints

    private var mapHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                    .fill(Color(hex: 0x0B1422))

                VStack(alignment: .leading, spacing: 10) {
                    // The canonical OCEAN register — fed the booking's REAL
                    // origin/dest coords (great circle) + live AIS keyed by IMO.
                    // Coord gate: draw only when both endpoints resolve.
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: 0x0E1B2E))
                        if !imoNumber.isEmpty, let o = originCoord, let d = destinationCoord {
                            VesselOceanTrackMap(
                                imoNumber: imoNumber,
                                origin: o,
                                destination: d,
                                originLabel: originLabel,
                                destinationLabel: destinationLabel
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            heroAwaiting
                        }
                    }
                    .frame(height: 78)
                    .overlay(alignment: .top) {
                        HStack {
                            Text(originCode)
                                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                                .foregroundStyle(Color(hex: 0x6E8198))
                            Spacer()
                            Text(destCode)
                                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                                .foregroundStyle(Color(hex: 0x6E8198))
                        }
                        .padding(.horizontal, 6)
                        .offset(y: -16)
                    }
                    // Sub-caption — from server segment count / risk, never fabricated.
                    Text(heroCaption)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: 0x8FA3BF))
                }
                .padding(16)
            }
            .frame(height: 138)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    /// No-endpoints / no-IMO placeholder so the hero never frames on null island.
    private var heroAwaiting: some View {
        VStack(spacing: 4) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: 0x6E8198))
            Text(loading ? "Resolving voyage endpoints…" : "Awaiting routable ports")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: 0x8FA3BF))
        }
    }

    private var heroCaption: String {
        if loading { return "Loading route weather…" }
        if endpointsUnavailable { return "Booking has no routable origin/destination ports" }
        if feedUnavailable { return "Marine-weather feed not configured · route geometry only" }
        if loadError != nil { return "Route weather unavailable" }
        let segs = route?.segments?.count ?? 0
        if segs == 0 { return "No route-weather segments returned" }
        let risk = (route?.overallRisk ?? "-")
        return "\(originCode) → \(destCode) · \(segs) legs · overall \(risk.uppercased()) on swell"
    }

    // MARK: - Voyage legs (getRouteWeather)

    private var voyageLegs: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("VOYAGE LEGS · getRouteWeather(waypoints)")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(Color(hex: 0x6E7681))

            if loading {
                VStack(spacing: Space.s2) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCardSoft).frame(height: 44)
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderFaint))
                    }
                }
                .padding(Space.s3)
                .background(legCardBackground)
            } else if let err = loadError {
                LifecycleCard(accentDanger: true) {
                    Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                }
            } else if endpointsUnavailable {
                EusoEmptyState(
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    title: "No routable voyage",
                    subtitle: "This booking has no origin/destination ports on file, so route weather can't be computed. Assign a loading + discharge port and per-leg sea-state populates here.")
            } else if feedUnavailable {
                // DTN marine-weather feed not configured — server returned null.
                EusoEmptyState(
                    systemImage: "cloud.sun.rain",
                    title: "Marine-weather feed unavailable",
                    subtitle: "DTN route-weather is not configured for this voyage. Per-leg wind, swell and sea-state will populate the moment the feed is live.",
                    comingSoon: true
                )
            } else if let segs = route?.segments, !segs.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(segs.enumerated()), id: \.element.id) { idx, seg in
                        legRow(seg, isFirst: idx == 0, isLast: idx == segs.count - 1)
                        if idx != segs.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                        }
                    }
                }
                .padding(Space.s4)
                .background(legCardBackground)
            } else {
                EusoEmptyState(
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    title: "No voyage legs",
                    subtitle: "Route-weather segments for this voyage will appear here.")
            }
        }
    }

    private var legCardBackground: some View {
        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .fill(Color(hex: 0x1C2128))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
    }

    /// Maps a DTN risk level → palette dot + sea-state label color.
    private func riskColor(_ level: String?) -> Color {
        switch (level ?? "").lowercased() {
        case "low":      return Brand.success
        case "moderate": return Brand.warning
        case "high":     return Brand.danger
        case "severe":   return Brand.danger
        default:         return Color(hex: 0x6E7681)
        }
    }

    private func legRow(_ seg: RouteWeatherSegment671, isFirst: Bool, isLast: Bool) -> some View {
        let color = riskColor(seg.riskLevel)
        let title = legTitle(seg, isFirst: isFirst, isLast: isLast)
        let seaState = (seg.riskLevel ?? "-").uppercased()
        let waveStr = seg.waveHeight.map { String(format: "%.1f m", $0) } ?? "-"
        return VStack(spacing: 6) {
            HStack(alignment: .top, spacing: Space.s3) {
                Circle().fill(color).frame(width: 10, height: 10)
                    .padding(.top, 3)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 8)
                Text("\(seaState) \(waveStr)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
            }
            HStack {
                Text(legDetail(seg))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                Spacer()
            }
            .padding(.leading, 22)
        }
        .padding(.vertical, Space.s2)
    }

    /// Title per leg — first = departure port, last = discharge port, middle
    /// legs flagged by their server-returned risk. Labels are the resolved
    /// REAL port names; no hardcoded place strings.
    private func legTitle(_ seg: RouteWeatherSegment671, isFirst: Bool, isLast: Bool) -> String {
        if isLast { return "\(destinationLabel) · port" }
        if isFirst { return "\(originLabel) departure" }
        if (seg.riskLevel ?? "").lowercased() == "moderate" { return "Mid-passage (current)" }
        return "Open-water leg"
    }

    private func legDetail(_ seg: RouteWeatherSegment671) -> String {
        var parts: [String] = []
        if let w = seg.windSpeed { parts.append(String(format: "Wind %.0f kt", w)) }
        if let s = seg.swellHeight { parts.append(String(format: "swell %.1f m", s)) }
        if let factors = seg.riskFactors, !factors.isEmpty {
            parts.append(factors.joined(separator: " · "))
        }
        if let v = seg.visibility { parts.append(String(format: "vis %.0f nm", v)) }
        return parts.isEmpty ? "getMarineWeather" : parts.joined(separator: " · ")
    }

    // MARK: - ESang advisory

    private var esangAdvisory: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.75), .white.opacity(0)],
                                         center: .init(x: 0.35, y: 0.30),
                                         startRadius: 0, endRadius: 16))
                    .frame(width: 22, height: 22)
                    .offset(x: -5, y: -5)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(esangHeadline)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(esangSub)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Color(hex: 0x1C2128))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        )
    }

    private var esangHeadline: String {
        // Surface the server's own routing warning when present; otherwise a
        // neutral coaching line (no fabricated forecast figures).
        if let w = route?.warnings?.first, !w.isEmpty { return "ESang: \(w)" }
        return "ESang: route to skip the swell core"
    }
    private var esangSub: String {
        if let dep = route?.recommendedDeparture, !dep.isEmpty {
            return "Recommended departure window: \(dep)"
        }
        return "Holds ETA · cuts slamming risk on the stacks"
    }

    // MARK: - CTA

    private var cta: some View {
        CTAButton(title: "View weather routing")
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil; feedUnavailable = false; endpointsUnavailable = false
        struct DetailIn: Encodable { let id: Int }
        do {
            // 1. Resolve the booking's REAL origin/destination ports first.
            let detail: VesselDetail671? = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipmentDetail", input: DetailIn(id: shipmentId))
            applyDetail(detail)

            guard let o = originCoord, let d = destinationCoord else {
                // No routable endpoints → honest empty state, no fabricated route.
                endpointsUnavailable = true
                loading = false
                return
            }

            // 2. Build the route-weather waypoints from the great circle BETWEEN
            //    the two resolved real ports — derived geometry, not literals.
            let waypoints = BespokeMapProjection
                .greatCircle(from: o, to: d, count: 5)
                .map { Waypoint671(lat: $0.lat, lng: $0.lng) }
            let mid = waypoints[waypoints.count / 2]

            struct RouteIn: Encodable { let waypoints: [Waypoint671] }
            struct MarineIn: Encodable { let lat: Double; let lng: Double }
            async let r: RouteWeatherResponse671? = EusoTripAPI.shared.query(
                "vesselShipments.getRouteWeather", input: RouteIn(waypoints: waypoints))
            async let m: MarineForecast671? = EusoTripAPI.shared.query(
                "vesselShipments.getMarineWeather", input: MarineIn(lat: mid.lat, lng: mid.lng))
            let (routeRes, marineRes) = try await (r, m)
            self.route = routeRes
            self.marine = marineRes
            // Both DTN procs return `null` when the feed isn't configured —
            // surface that as a real "feed unavailable" state, no fabrication.
            if routeRes == nil && marineRes == nil {
                self.feedUnavailable = true
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func applyDetail(_ d: VesselDetail671?) {
        originPort = d?.originPort
        destinationPort = d?.destinationPort
        bookingRef = d?.bookingNumber
    }
}

/// Waypoint for getRouteWeather — the INPUT geometry derived from the resolved
/// real ports, NOT forecast data. Weather values come only from the response.
private struct Waypoint671: Encodable { let lat: Double; let lng: Double }

#Preview("671 · Vessel Marine Weather Routing · Night") {
    VesselMarineWeatherRoutingScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("671 · Vessel Marine Weather Routing · Light") {
    VesselMarineWeatherRoutingScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
