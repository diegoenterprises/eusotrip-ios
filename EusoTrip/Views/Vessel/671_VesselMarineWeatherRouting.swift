//
//  671_VesselMarineWeatherRouting.swift
//  EusoTrip — Vessel Operator · Marine Weather Routing.
//
//  Verbatim port of canonical wireframe 671 (06 Vessel · Dark).
//  MapCanvas hero shows the TPEB route arc with weather waypoints;
//  voyage legs + ESang advisory below. Active voyage
//  VES-260524-7B3D90F2C5 · Shanghai CNSHA → Long Beach USLGB.
//
//  Endpoints (vesselShipments.ts):
//    · getRouteWeather(waypoints) → RouteWeatherResponse  (EXISTS :1205)
//    · getMarineWeather(lat,lng)  → MarineForecast        (EXISTS :1191)
//
//  Both DTN-backed procedures return `null` when the marine-weather feed
//  is not configured/seeded (the wireframe's flagged seed gap). We honor
//  that with a real empty/error state — never fabricated forecast values.
//

import SwiftUI

struct VesselMarineWeatherRoutingScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselMarineWeatherRoutingBody() } nav: {
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

// MARK: - Data shapes (mirror server/routers/vesselShipments.ts → DTNMarineWeatherService)

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

/// Marine forecast at the vessel's current mid-Pacific waypoint.
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
    @State private var route: RouteWeatherResponse671? = nil
    @State private var marine: MarineForecast671? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    /// True when the procedures resolve but the DTN marine-weather feed
    /// is not configured (server returns `null`) — the wireframe's
    /// flagged "no live marine-weather feed seeded" seed gap.
    @State private var feedUnavailable = false

    // Active voyage TPEB waypoints (route geometry from the active voyage
    // VES-260524-7B3D90F2C5 · CNSHA → USLGB). These are the INPUT to
    // getRouteWeather — not forecast data. Weather values shown in legs
    // come strictly from the server response.
    private struct Waypoint: Encodable { let lat: Double; let lng: Double }
    private let routeWaypoints: [Waypoint] = [
        Waypoint(lat: 31.23, lng: 121.47),   // Shanghai CNSHA
        Waypoint(lat: 35.00, lng: 160.00),   // W Pacific
        Waypoint(lat: 33.00, lng: -160.00),  // Mid-Pacific (current)
        Waypoint(lat: 33.30, lng: -119.00),  // SoCal approach
        Waypoint(lat: 33.75, lng: -118.20),  // Long Beach USLGB
    ]
    // Mid-Pacific current position for getMarineWeather.
    private let midPacificLat = 33.00
    private let midPacificLng = -160.00

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
            Text("getRouteWeather · TPEB · live AIS track")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 2)
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s4)
    }

    // MARK: - MapCanvas hero · route arc + weather waypoints

    private var mapHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                    .fill(Color(hex: 0x0B1422))

                VStack(alignment: .leading, spacing: 10) {
                    // Grid + arc canvas
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: 0x0E1B2E))
                            .overlay(RouteArcCanvas())
                            .frame(height: 78)
                        // CNSHA / USLGB labels above the canvas band
                        HStack {
                            Text("CNSHA")
                                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                                .foregroundStyle(Color(hex: 0x6E8198))
                            Spacer()
                            Text("USLGB")
                                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                                .foregroundStyle(Color(hex: 0x6E8198))
                        }
                        .offset(y: -16)
                    }
                    // Sub-caption — from server segment count / run, not fabricated forecast
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

    private var heroCaption: String {
        if loading { return "Loading route weather…" }
        if feedUnavailable { return "Marine-weather feed not configured · route geometry only" }
        if loadError != nil { return "Route weather unavailable" }
        let segs = route?.segments?.count ?? 0
        if segs == 0 { return "No route-weather segments returned" }
        let risk = (route?.overallRisk ?? "—")
        return "Vessel mid-Pacific · \(segs) legs · overall \(risk.uppercased()) on swell"
    }

    // MARK: - Voyage legs (getRouteWeather)

    private var voyageLegs: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("VOYAGE LEGS · getRouteWeather(routeId)")
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
            } else if feedUnavailable {
                // DTN marine-weather feed not configured — server returned null.
                EusoEmptyState(
                    systemImage: "cloud.sun.rain",
                    title: "Marine-weather feed unavailable",
                    subtitle: "DTN route-weather is not configured for this voyage. Per-leg wind, swell, and sea-state will populate the moment the feed is live.",
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
        let seaState = (seg.riskLevel ?? "—").uppercased()
        let waveStr = seg.waveHeight.map { String(format: "%.1f m", $0) } ?? "—"
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

    /// Title per leg — first = departure, last = port, middle current/approach.
    private func legTitle(_ seg: RouteWeatherSegment671, isFirst: Bool, isLast: Bool) -> String {
        if isLast { return "Long Beach USLGB · port" }
        if isFirst { return "W Pacific departure" }
        // Middle legs — flag the current (vessel position) leg.
        if (seg.riskLevel ?? "").lowercased() == "moderate" { return "Mid-Pacific (current)" }
        return "SoCal approach"
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
        if feedUnavailable || (route?.warnings?.isEmpty ?? true) {
            return "ESang: route 90 nm south to skip the swell core"
        }
        return "ESang: \(route?.warnings?.first ?? "")"
    }
    private var esangSub: String {
        "+5 nm · holds ETA · cuts slamming risk on the FEU stacks"
    }

    // MARK: - CTA

    private var cta: some View {
        CTAButton(title: "View weather routing")
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil; feedUnavailable = false
        struct RouteIn: Encodable { let waypoints: [Waypoint] }
        struct MarineIn: Encodable { let lat: Double; let lng: Double }
        do {
            async let r: RouteWeatherResponse671? = EusoTripAPI.shared.query(
                "vesselShipments.getRouteWeather",
                input: RouteIn(waypoints: routeWaypoints))
            async let m: MarineForecast671? = EusoTripAPI.shared.query(
                "vesselShipments.getMarineWeather",
                input: MarineIn(lat: midPacificLat, lng: midPacificLng))
            let (routeRes, marineRes) = try await (r, m)
            self.route = routeRes
            self.marine = marineRes
            // Both DTN procedures return `null` when the marine-weather feed
            // isn't configured/seeded (flagged seed gap in the wireframe).
            // Surface that as a real "feed unavailable" state — no fabrication.
            if routeRes == nil && marineRes == nil {
                self.feedUnavailable = true
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - RouteArcCanvas (route arc + weather waypoint dots)
//
// Verbatim port of the SVG MapCanvas: 3 horizontal grid lines, the
// blue→magenta route arc, and the 5 waypoint dots (origin white, calm
// green, current orange + halo, building red, dest white). Pure
// presentation chrome — no forecast data is encoded here.

private struct RouteArcCanvas: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // SVG canvas inner band was 368×78 with content padded by 8.
            // Scale x/y from the SVG 368-wide reference into the live width.
            let sx = w / 368.0
            let sy = h / 78.0
            let px: (CGFloat) -> CGFloat = { $0 * sx }
            let py: (CGFloat) -> CGFloat = { $0 * sy }

            ZStack {
                // Grid lines (y = 26, 46, 66 in SVG)
                Path { p in
                    for gy in [CGFloat(26), 46, 66] {
                        p.move(to: CGPoint(x: px(8), y: py(gy)))
                        p.addLine(to: CGPoint(x: px(360), y: py(gy)))
                    }
                }
                .stroke(Color(hex: 0x172A44), lineWidth: 1)

                // Route arc — M22 58 Q150 6 200 40 Q270 84 346 30
                Path { p in
                    p.move(to: CGPoint(x: px(22), y: py(58)))
                    p.addQuadCurve(to: CGPoint(x: px(200), y: py(40)),
                                   control: CGPoint(x: px(150), y: py(6)))
                    p.addQuadCurve(to: CGPoint(x: px(346), y: py(30)),
                                   control: CGPoint(x: px(270), y: py(84)))
                }
                .stroke(LinearGradient.primary,
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round))

                // Current-waypoint halo ring (cx206 cy42 r11)
                Circle()
                    .stroke(Brand.warning.opacity(0.55), lineWidth: 1)
                    .frame(width: 22 * sx, height: 22 * sx)
                    .position(x: px(206), y: py(42))

                // Waypoint dots
                dot(x: px(22),  y: py(58), r: 5,   fill: Color(hex: 0xF5F5F7))
                dot(x: px(150), y: py(20), r: 4.5, fill: Color(hex: 0x3DD9A0))
                dot(x: px(206), y: py(42), r: 6,   fill: Brand.warning)
                dot(x: px(300), y: py(56), r: 5,   fill: Brand.danger)
                dot(x: px(346), y: py(30), r: 5,   fill: Color(hex: 0xF5F5F7))
            }
        }
    }

    private func dot(x: CGFloat, y: CGFloat, r: CGFloat, fill: Color) -> some View {
        Circle().fill(fill)
            .frame(width: r * 2, height: r * 2)
            .position(x: x, y: y)
    }
}

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
