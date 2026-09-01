//
//  671_VesselMarineWeatherRouting.swift
//  EusoTrip — Vessel Operator · Marine Weather Routing.
//
//  Bespoke port of canonical wireframe 671 (06 Vessel · Dark). MapCanvas hero
//  shows the exact current EusoMarine route plan with provider weather sampled
//  only at its authored vertices; voyage legs + provider-authored guidance sit
//  below.
//
//  The phone sends exactly `{shipmentId}` to
//  `vesselShipments.getCanonicalRouteWeather`. The server resolves the
//  authorized shipment, assigned vessel/IMO, exact current checksum-bound
//  route.plan, ports, source rights/freshness, and weather-provider calls. It
//  samples existing vertices independently for every LineString member; the
//  client never sends waypoints, interpolates a great circle, joins disjoint
//  geometry, or substitutes endpoint chords. When no shipment is supplied by
//  navigation, the newest authorized non-terminal shipment is selected from
//  the tenant-scoped list—never a hardcoded demo row.
//

import SwiftUI

struct VesselMarineWeatherRoutingScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int

    init(theme: Theme.Palette, shipmentId: Int = 0) {
        self.theme = theme
        self.shipmentId = shipmentId
    }

    var body: some View {
        Shell(theme: theme) {
            VesselMarineWeatherRoutingBody(shipmentId: shipmentId)
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

/// Server-resolved canonical shipment/route-weather contract. Unused server
/// evidence fields are intentionally ignored by Decodable, while every field
/// that releases map/weather UI is required and rechecked below.
private struct PortCoords671: Decodable { let lat: Double?; let lng: Double? }
private struct VesselPort671: Decodable {
    let name: String?
    let unlocode: String?
    let coordinates: PortCoords671?
}
private struct CanonicalWeatherShipment671: Decodable {
    let id: Int
    let bookingNumber: String?
    let status: String?
}
private struct CanonicalWeatherVessel671: Decodable {
    let id: Int
    let name: String
    let imoNumber: String?
    let mmsiNumber: String?
}
private struct CanonicalWeatherRoutePlan671: Decodable {
    let version: Int
    let purpose: String
    let operational: Bool
    let rightsState: String
    let freshnessState: String
}

/// One segment of the route-weather response. All numerics optional so a
/// partial/null DTN payload decodes without throwing.
private struct RouteWeatherSegment671: Decodable {
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

private struct CanonicalRouteWarning671: Decodable {
    let lineIndex: Int
    let message: String
}
private struct CanonicalRouteDeparture671: Decodable {
    let lineIndex: Int
    let value: String
}
private struct CanonicalRouteWeatherLine671: Decodable, Identifiable {
    let lineIndex: Int
    let authoredVertexCount: Int
    let sampledVertexCount: Int
    let weather: RouteWeatherResponse671?
    var id: Int { lineIndex }
}
private struct CanonicalRouteWeatherAuthority671: Decodable {
    let availability: String
    let overallRisk: String?
    let warnings: [CanonicalRouteWarning671]
    let recommendedDepartures: [CanonicalRouteDeparture671]
    let lines: [CanonicalRouteWeatherLine671]
}
private struct CanonicalMarineForecastAuthority671: Decodable {
    let forecast: MarineForecast671?
}
private struct CanonicalRouteWeatherEnvelope671: Decodable {
    let shipment: CanonicalWeatherShipment671
    let assignedVessel: CanonicalWeatherVessel671
    let originPort: VesselPort671?
    let destinationPort: VesselPort671?
    let routePlan: CanonicalWeatherRoutePlan671
    let routeWeather: CanonicalRouteWeatherAuthority671
    let marineForecast: CanonicalMarineForecastAuthority671
}

private struct VesselShipmentListRow671: Decodable {
    let id: Int
    let status: String?
}
private struct VesselShipmentListEnvelope671: Decodable {
    let shipments: [VesselShipmentListRow671]
}

/// Per-port berthing conditions from getPortWeather → DTNMarineWeatherService
/// `PortConditions` (vesselShipments.ts :2119 / DTNMarineWeatherService.ts :101).
/// `berthingSafety` is the published Safe/Caution/Restricted/Closed assessment
/// the server measures against; `windGust` is the gust AT THE BERTH (kt). All
/// optional so a partial/null enterprise-gated payload decodes without throwing.
/// Server returns `null` until the DTN marine key is configured — honored as a
/// hidden chip, never fabricated.
private struct PortConditions671: Decodable {
    let portName: String?
    let windGust: Double?
    let windSpeed: Double?
    let berthingSafety: String?
    let restrictions: [String]?
}

// MARK: - Body

private struct VesselMarineWeatherRoutingBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int

    // Exact identities and endpoints resolved by the server authority.
    @State private var resolvedShipmentId: Int? = nil
    @State private var resolvedImoNumber: String? = nil
    @State private var canonicalRouteVersion: Int? = nil
    @State private var canonicalRoutePurpose: CanonicalRoutePlanClient.Purpose = .activeJob
    @State private var originPort: VesselPort671? = nil
    @State private var destinationPort: VesselPort671? = nil
    @State private var bookingRef: String? = nil

    @State private var route: RouteWeatherResponse671? = nil
    @State private var routeWeatherLines: [CanonicalRouteWeatherLine671] = []
    @State private var marine: MarineForecast671? = nil
    // Per-port berthing conditions (getPortWeather, keyed by the port UN/LOCODE).
    // nil until the enterprise marine key lands (server returns null today) — the
    // berthing-safety chip stays hidden, never fabricated.
    @State private var originBerth: PortConditions671? = nil
    @State private var destinationBerth: PortConditions671? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    /// True when the procedures resolve but the DTN marine-weather feed is not
    /// configured (server returns `null`) — the wireframe's flagged seed gap.
    @State private var feedUnavailable = false
    /// True when the booking has no routable origin/destination ports.
    @State private var endpointsUnavailable = false
    @State private var subjectUnavailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
            VStack(alignment: .leading, spacing: Space.s4) {
                mapHero
                marineConditions
                berthingSafetySection
                voyageLegs
                routeGuidance
                cta
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            Color.clear.frame(height: Space.s5)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - Server-resolved origin / destination coordinates

    /// Display pins come only from the authorized server response. Missing
    /// coordinates fail closed; the client does not repair route endpoints from
    /// a bundled directory or use them to create geometry.
    private var originCoord: HereLatLng? { coord(for: originPort) }
    private var destinationCoord: HereLatLng? { coord(for: destinationPort) }

    private func coord(for port: VesselPort671?) -> HereLatLng? {
        guard let port else { return nil }
        if let coordinate = LatLongParser.validatedCoordinate(
            latitude: port.coordinates?.lat,
            longitude: port.coordinates?.lng
        ) {
            return HereLatLng(coordinate.latitude, coordinate.longitude)
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
                // Bespoke marine glyph (WeatherIcons .wave) — never an SF Symbol.
                WeatherIcons.utility(.wave, size: 10, tint: Brand.magenta)
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
        if originCoord != nil, destinationCoord != nil {
            return "Canonical route weather · \(originCode) → \(destCode) · authorized vessel observations"
        }
        return "Canonical route weather · per-voyage authority"
    }

    // MARK: - MapCanvas hero · ocean register on real port endpoints

    private var mapHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                    .fill(Color(hex: 0x0B1422))

                VStack(alignment: .leading, spacing: 10) {
                    // The canonical OCEAN register. Route geometry comes from
                    // route.plan; ports are markers and AIS remains observation
                    // evidence. No client geometry crosses this boundary.
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: 0x0E1B2E))
                        if let subjectId = resolvedShipmentId,
                           let o = originCoord,
                           let d = destinationCoord {
                            VesselOceanTrackMap(
                                imoNumber: resolvedImoNumber ?? "",
                                vesselShipmentId: subjectId,
                                routePurpose: canonicalRoutePurpose,
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

    // MARK: - Marine conditions strip (server-chosen authored route vertex)

    /// The marine forecast at the exact authored route vertex selected by the
    /// server — significant wave / wind gust / visibility from the provider,
    /// rendered through the canonical metric-tile idiom with the bespoke
    /// WeatherIcons `.wave` / `.wind` / `.eye` glyphs (the PerLoadWeatherCard
    /// metricsGrid pattern). Honest: hidden entirely until the feed resolves
    /// (current == nil / feed unavailable) — never a fabricated reading.
    @ViewBuilder
    private var marineConditions: some View {
        if let c = marine?.current, marineHasAnyValue(c) {
            let gust = marineWind(c.windGust)
            let sustainedWind = marineWind(c.windSpeed)
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("MARINE CONDITIONS · mid-voyage")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(Color(hex: 0x6E7681))
                HStack(spacing: 8) {
                    // Significant wave height (sig wave) — .wave glyph.
                    marineTile(.wave,
                               value: marineWave(c.waveHeight).map { String(format: "%.1f m", $0) },
                               key: "SIG WAVE")
                    // Wind gust — .wind glyph (gust preferred, sustained fallback).
                    marineTile(.wind,
                               value: (gust ?? sustainedWind).map { String(format: "%.0f kt", $0) },
                               key: gust != nil ? "GUST" : "WIND")
                    // Visibility — .eye glyph.
                    marineTile(.eye,
                               value: marineVisibility(c.visibility).map { String(format: "%.0f nm", $0) },
                               key: "VIS")
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
            )
        }
    }

    /// True when the marine current carries at least one of the three fields
    /// we surface — so the strip never frames on an all-"—" payload.
    private func marineHasAnyValue(_ c: MarineForecastCurrent671) -> Bool {
        marineWave(c.waveHeight) != nil ||
        marineWind(c.windGust) != nil ||
        marineWind(c.windSpeed) != nil ||
        marineVisibility(c.visibility) != nil
    }

    private func marineWave(_ value: Double?) -> Double? {
        WeatherNumeric.finite(value, allowed: 0...100)
    }

    private func marineWind(_ value: Double?) -> Double? {
        WeatherNumeric.finite(value, allowed: 0...500)
    }

    private func marineVisibility(_ value: Double?) -> Double? {
        WeatherNumeric.finite(value, allowed: 0...1_000)
    }

    /// One marine metric tile — the PerLoadWeatherCard.metricTile idiom:
    /// bespoke glyph over a monospaced value + key in a translucent chip.
    /// Honest "—" when the field is nil.
    private func marineTile(_ glyph: WeatherIcons.Utility, value: String?, key: String) -> some View {
        VStack(spacing: 3) {
            WeatherIcons.utility(glyph, size: 17, tint: Color(red: 0.81, green: 0.88, blue: 1.0))
            Text(value ?? "—")
                .font(.system(size: 13, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(key)
                .font(.system(size: 9.5)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9).padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
        )
    }

    // MARK: - Berthing safety (getPortWeather · per-port)

    /// Per-port BERTHING-SAFETY chips. Canonical route weather is route-centric
    /// (open-water sea-state); the Safe/Caution/Restricted/Closed
    /// berthing assessment + gust AT THE BERTH live on getPortWeather keyed by
    /// the port UN/LOCODE — so this screen calls it for the resolved origin AND
    /// destination ports. Honest: the whole section is HIDDEN until at least one
    /// port returns berthing data (enterprise marine key lands → server null →
    /// nil today), never a fabricated verdict.
    @ViewBuilder
    private var berthingSafetySection: some View {
        let chips = berthingChips
        if !chips.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("BERTHING SAFETY · port weather")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(Color(hex: 0x6E7681))
                VStack(spacing: Space.s2) {
                    ForEach(chips, id: \.code) { chip in
                        berthingChip(chip)
                    }
                }
            }
        }
    }

    /// One resolved berthing row: which port (origin/dest) + its conditions.
    private struct BerthChip671 {
        let code: String
        let role: String
        let portLabel: String
        let conditions: PortConditions671
    }

    /// Only ports that returned a real berthing verdict survive — that keeps the
    /// section hidden when the feed is gated (null) and lights it the moment a
    /// port reports.
    private var berthingChips: [BerthChip671] {
        var out: [BerthChip671] = []
        if let c = originBerth, berthingHasValue(c) {
            out.append(BerthChip671(code: originCode, role: "LOADING",
                                    portLabel: c.portName ?? originLabel, conditions: c))
        }
        if let c = destinationBerth, berthingHasValue(c) {
            out.append(BerthChip671(code: destCode, role: "DISCHARGE",
                                    portLabel: c.portName ?? destinationLabel, conditions: c))
        }
        return out
    }

    /// A berthing payload counts only when it carries the verdict OR a gust —
    /// so an all-empty enterprise-gated row never frames the chip.
    private func berthingHasValue(_ c: PortConditions671) -> Bool {
        (c.berthingSafety?.isEmpty == false) ||
        marineWind(c.windGust) != nil ||
        marineWind(c.windSpeed) != nil
    }

    /// Maps the published berthing verdict → palette accent + StatusPill kind.
    /// Unknown/empty stays neutral (no fabricated severity).
    private func berthingTone(_ verdict: String?) -> (Color, StatusPill.Kind) {
        switch (verdict ?? "").lowercased() {
        case "safe":       return (Brand.success, .success)
        case "caution":    return (Brand.warning, .warning)
        case "restricted": return (Brand.danger,  .danger)
        case "closed":     return (Brand.danger,  .danger)
        default:           return (Brand.neutral, .neutral)
        }
    }

    /// Bespoke berthing chip — the WeatherIcons .pin port glyph leads, the
    /// published Safe/Caution/Restricted/Closed verdict renders as a StatusPill,
    /// and the gust at berth (.alert glyph) sits beneath. ZERO SF Symbols.
    private func berthingChip(_ chip: BerthChip671) -> some View {
        let (accent, pillKind) = berthingTone(chip.conditions.berthingSafety)
        let verdict = (chip.conditions.berthingSafety?.isEmpty == false)
            ? chip.conditions.berthingSafety! : nil
        let gust = (marineWind(chip.conditions.windGust) ?? marineWind(chip.conditions.windSpeed))
            .map { String(format: "%.0f kt", $0) }
        return HStack(alignment: .top, spacing: Space.s3) {
            // Bespoke port pin in an accent-tinted chip (never an SF Symbol).
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(accent.opacity(0.16))
                    .frame(width: 38, height: 38)
                WeatherIcons.utility(.pin, size: 18, tint: accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(chip.role)
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textSecondary)
                    Text(chip.code)
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(Color(hex: 0x6E8198))
                }
                Text(chip.portLabel)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                // Gust at berth — bespoke .alert glyph + monospaced value. Only
                // rendered when the port reports a gust (honest, no "—" fill).
                if let gust {
                    HStack(spacing: 4) {
                        WeatherIcons.utility(.alert, size: 11, tint: accent)
                        Text("Gust at berth \(gust)")
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                // Server restrictions, if the port lists any (e.g. "Pilotage hold").
                if let r = chip.conditions.restrictions, !r.isEmpty {
                    Text(r.joined(separator: " · "))
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            // The published Safe/Caution/Restricted/Closed verdict.
            if let verdict {
                StatusPill(text: verdict, kind: pillKind)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Color(hex: 0x1C2128))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(accent.opacity(0.30), lineWidth: 1))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(chip.role) port \(chip.portLabel). Berthing \(chip.conditions.berthingSafety ?? "unknown").")
    }

    /// Honest subject/endpoints seam so the hero never frames on invalid data.
    private var heroAwaiting: some View {
        VStack(spacing: 4) {
            // Bespoke route glyph — never an SF Symbol.
            WeatherIcons.utility(.route, size: 18, tint: Color(hex: 0x6E8198))
            Text(loading
                 ? "Resolving canonical voyage authority…"
                 : subjectUnavailable
                    ? "Select an authorized vessel shipment"
                    : "Awaiting server-resolved ports")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: 0x8FA3BF))
        }
    }

    private var heroCaption: String {
        if loading { return "Resolving exact route and weather authority…" }
        if subjectUnavailable { return "No authorized non-terminal vessel shipment was returned" }
        if endpointsUnavailable { return "Shipment is missing verified port coordinates" }
        if feedUnavailable {
            return "Canonical EusoMarine route shown · provider returned no current marine conditions"
        }
        if let loadError { return loadError }
        let segs = route?.segments?.count ?? 0
        let version = canonicalRouteVersion.map { "v\($0) · " } ?? ""
        if segs == 0 { return "EusoMarine \(version)no route-weather segments returned" }
        let risk = (route?.overallRisk ?? "-")
        return "EusoMarine \(version)\(originCode) → \(destCode) · \(segs) sampled legs · \(risk.uppercased())"
    }

    // MARK: - Voyage legs (independent canonical route members)

    private var voyageLegs: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("VOYAGE LEGS · route weather")
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
            } else if let loadError {
                marineEmptyPane(
                    glyph: .route,
                    title: "Route weather not released",
                    subtitle: loadError)
            } else if subjectUnavailable {
                marineEmptyPane(
                    glyph: .route,
                    title: "No authorized voyage selected",
                    subtitle: "Open an active vessel shipment or create one with an assigned vessel. No demo shipment is substituted.")
            } else if endpointsUnavailable {
                marineEmptyPane(
                    glyph: .route,
                    title: "No routable voyage",
                    subtitle: "This booking has no origin/destination ports on file, so route weather can't be computed. Assign a loading + discharge port and per-leg sea-state populates here.")
            } else if feedUnavailable {
                marineEmptyPane(
                    glyph: .wave,
                    title: "No current provider conditions",
                    subtitle: "The exact EusoMarine route remains visible. Weather stays empty until the licensed provider returns current conditions for its authored route vertices."
                )
            } else if routeWeatherLines.contains(where: { !($0.weather?.segments?.isEmpty ?? true) }) {
                VStack(spacing: 0) {
                    ForEach(routeWeatherLines) { line in
                        if let segments = line.weather?.segments, !segments.isEmpty {
                            HStack {
                                Text("ROUTE MEMBER \(line.lineIndex + 1)")
                                    .font(EType.micro)
                                    .tracking(0.8)
                                    .foregroundStyle(LinearGradient.primary)
                                Spacer()
                                Text("\(line.sampledVertexCount)/\(line.authoredVertexCount) authored vertices sampled")
                                    .font(EType.caption)
                                    .foregroundStyle(palette.textTertiary)
                            }
                            .padding(.vertical, Space.s2)
                            ForEach(Array(segments.enumerated()), id: \.offset) { idx, segment in
                                legRow(
                                    segment,
                                    isFirst: idx == 0,
                                    isLast: idx == segments.count - 1
                                )
                                if idx != segments.count - 1 {
                                    Rectangle().fill(palette.borderFaint).frame(height: 1)
                                }
                            }
                        }
                    }
                }
                .padding(Space.s4)
                .background(legCardBackground)
            } else {
                marineEmptyPane(
                    glyph: .route,
                    title: "No voyage legs",
                    subtitle: "Route-weather segments for this voyage will appear here.")
            }
        }
    }

    /// Bespoke empty pane — the EusoEmptyState aesthetic with a real
    /// WeatherIcons glyph in the gradient chip (ZERO SF Symbols). Used for
    /// the no-route / feed-unavailable honest states so the screen reads
    /// well now and lights up the moment the marine key lands.
    private func marineEmptyPane(glyph: WeatherIcons.Utility, title: String, subtitle: String) -> some View {
        VStack(alignment: .center, spacing: Space.s4) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral)
                    .frame(width: 56, height: 56)
                WeatherIcons.utility(glyph, size: 24, tint: Brand.magenta)
            }
            VStack(spacing: Space.s2) {
                Text(title)
                    .font(EType.h2)
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(EType.body)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s6)
        .padding(.horizontal, Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Color(hex: 0x1C2128))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Empty. \(title). \(subtitle)")
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
        let waveStr = marineWave(seg.waveHeight).map { String(format: "%.1f m", $0) } ?? "-"
        return VStack(spacing: 6) {
            HStack(alignment: .top, spacing: Space.s3) {
                Circle().fill(color).frame(width: 10, height: 10)
                    .padding(.top, 3)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 8)
                // Sea-state risk + significant wave, led by the bespoke
                // .wave glyph (never an SF Symbol).
                HStack(spacing: 4) {
                    WeatherIcons.utility(.wave, size: 13, tint: color)
                    Text("\(seaState) \(waveStr)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(color)
                }
            }
            // Per-leg marine metrics — each value led by its bespoke
            // WeatherIcons glyph (.wind / .wave / .eye), bound to the real
            // segment fields. Hidden when the segment carries no readings.
            legMetrics(seg)
                .padding(.leading, 22)
        }
        .padding(.vertical, Space.s2)
    }

    /// The per-leg metric row: wind (.wind), swell (.wave), visibility
    /// (.eye) — each glyph + value rendered only when its field is present,
    /// then any server risk factors as supporting text. A value-less provider
    /// segment remains explicit rather than receiving a client estimate.
    @ViewBuilder
    private func legMetrics(_ seg: RouteWeatherSegment671) -> some View {
        let glyphTint = Color(red: 0.81, green: 0.88, blue: 1.0)
        let wind = marineWind(seg.windSpeed)
        let swell = marineWave(seg.swellHeight)
        let visibility = marineVisibility(seg.visibility)
        HStack(spacing: 10) {
            if let w = wind {
                metricInline(.wind, String(format: "%.0f kt", w), tint: glyphTint)
            }
            if let s = swell {
                metricInline(.wave, String(format: "swell %.1f m", s), tint: glyphTint)
            }
            if let v = visibility {
                metricInline(.eye, String(format: "%.0f nm", v), tint: glyphTint)
            }
            if wind == nil && swell == nil && visibility == nil,
               (seg.riskFactors?.isEmpty ?? true) {
                Text("no marine weather reported for this leg")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        if let factors = seg.riskFactors, !factors.isEmpty {
            HStack(spacing: 6) {
                WeatherIcons.utility(.alert, size: 11, tint: Brand.warning)
                Text(factors.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
            }
        }
    }

    /// One inline metric: bespoke glyph + monospaced value.
    private func metricInline(_ glyph: WeatherIcons.Utility, _ value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            WeatherIcons.utility(glyph, size: 12, tint: tint)
            Text(value)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(palette.textSecondary)
        }
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

    // MARK: - Provider route guidance

    @ViewBuilder
    private var routeGuidance: some View {
        if routeWarning != nil || routeDeparture != nil {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    WeatherIcons.utility(.alert, size: 14, tint: Brand.warning)
                    Text("ROUTE GUIDANCE")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                }
                if let warning = routeWarning {
                    Text(warning)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                if let departure = routeDeparture {
                    Text("Recommended departure window: \(departure)")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(Color(hex: 0x1C2128))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
            )
        }
    }

    private var routeWarning: String? {
        route?.warnings?
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private var routeDeparture: String? {
        guard let value = route?.recommendedDeparture?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    // MARK: - CTA

    private var cta: some View {
        CTAButton(title: "View weather routing", action: { openVesselScreen("Vesl660") })
    }

    private func openVesselScreen(_ screenId: String) {
        NotificationCenter.default.post(
            name: .eusoVesselNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }

    // MARK: - Load

    private func load() async {
        loading = true
        loadError = nil
        feedUnavailable = false
        endpointsUnavailable = false
        subjectUnavailable = false
        resolvedShipmentId = nil
        resolvedImoNumber = nil
        canonicalRouteVersion = nil
        canonicalRoutePurpose = .activeJob
        originPort = nil
        destinationPort = nil
        bookingRef = nil
        route = nil
        routeWeatherLines = []
        marine = nil
        originBerth = nil
        destinationBerth = nil

        do {
            guard let subjectId = try await resolveShipmentSubject() else {
                subjectUnavailable = true
                loading = false
                return
            }
            struct CanonicalInput: Encodable { let shipmentId: Int }
            let authority: CanonicalRouteWeatherEnvelope671 = try await EusoTripAPI.shared.query(
                "vesselShipments.getCanonicalRouteWeather",
                input: CanonicalInput(shipmentId: subjectId)
            )
            guard authority.shipment.id == subjectId,
                  authority.assignedVessel.id > 0,
                  authority.routePlan.version > 0,
                  authority.routePlan.operational,
                  authority.routePlan.rightsState == "valid",
                  authority.routePlan.freshnessState == "current",
                  let routePurpose = CanonicalRoutePlanClient.Purpose(
                    rawValue: authority.routePlan.purpose
                  ),
                  routePurpose != .posting else {
                loadError = "The canonical voyage response did not retain its exact operational route authority. No route weather was released."
                loading = false
                return
            }
            applyCanonicalAuthority(authority, routePurpose: routePurpose)

            // Berth conditions are requested only from server-authorized port
            // identities returned above; they never influence route geometry.
            async let ob: PortConditions671? = portWeather(for: originPort?.unlocode)
            async let db: PortConditions671? = portWeather(for: destinationPort?.unlocode)
            let (originRes, destRes) = await (ob, db)
            self.originBerth = originRes
            self.destinationBerth = destRes
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    /// Uses the explicit navigation subject when supplied. The registry entry
    /// has no subject, so it selects from the authenticated tenant-scoped list,
    /// preferring active voyages and never substituting a demo identity.
    private func resolveShipmentSubject() async throws -> Int? {
        if shipmentId > 0 { return shipmentId }
        struct ListInput: Encodable { let limit: Int; let offset: Int }
        let envelope: VesselShipmentListEnvelope671 = try await EusoTripAPI.shared.query(
            "vesselShipments.getVesselShipments",
            input: ListInput(limit: 50, offset: 0)
        )
        let terminal: Set<String> = [
            "cancelled", "canceled", "delivered", "gate_out", "invoiced",
            "settled", "paid", "closed"
        ]
        let activePriority: [String] = [
            "in_transit", "at_sea", "sailing", "departed", "loaded",
            "at_port", "arrived"
        ]
        let candidates = envelope.shipments.filter {
            !terminal.contains(normalizedStatus($0.status))
        }
        for status in activePriority {
            if let shipment = candidates.first(where: {
                normalizedStatus($0.status) == status
            }) {
                return shipment.id
            }
        }
        return candidates.first?.id
    }

    private func normalizedStatus(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private func applyCanonicalAuthority(
        _ authority: CanonicalRouteWeatherEnvelope671,
        routePurpose: CanonicalRoutePlanClient.Purpose
    ) {
        resolvedShipmentId = authority.shipment.id
        resolvedImoNumber = normalizedImo(authority.assignedVessel.imoNumber)
        canonicalRouteVersion = authority.routePlan.version
        canonicalRoutePurpose = routePurpose
        originPort = authority.originPort
        destinationPort = authority.destinationPort
        bookingRef = authority.shipment.bookingNumber
        routeWeatherLines = authority.routeWeather.lines
        marine = authority.marineForecast.forecast

        let weatherResponses = authority.routeWeather.lines.compactMap(\.weather)
        let segments = weatherResponses.flatMap { $0.segments ?? [] }
        let authorityWarnings = authority.routeWeather.warnings.map {
            "Route member \($0.lineIndex + 1): \($0.message)"
        }
        let providerWarnings = authority.routeWeather.lines.flatMap { line in
            (line.weather?.warnings ?? []).map {
                "Route member \(line.lineIndex + 1): \($0)"
            }
        }
        let departure = authority.routeWeather.recommendedDepartures
            .sorted { $0.lineIndex < $1.lineIndex }
            .lazy
            .map(\.value)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        route = RouteWeatherResponse671(
            segments: segments,
            overallRisk: authority.routeWeather.overallRisk,
            warnings: authorityWarnings + providerWarnings,
            recommendedDeparture: departure,
            generatedAt: weatherResponses.compactMap(\.generatedAt).first
        )
        endpointsUnavailable = originCoord == nil || destinationCoord == nil
        let hasWeather = !segments.isEmpty || marine?.current != nil
        feedUnavailable = authority.routeWeather.availability == "unavailable" || !hasWeather
    }

    private func normalizedImo(_ value: String?) -> String? {
        let digits = (value ?? "").filter(\.isNumber)
        return digits.count == 7 ? digits : nil
    }

    /// getPortWeather for one port, keyed by its UN/LOCODE (the canonical port
    /// id the DTN /ports/{id}/conditions endpoint expects). nil when the booking
    /// port has no code OR the enterprise feed isn't configured (server null) —
    /// the berthing chip simply stays hidden, never fabricated.
    private func portWeather(for unlocode: String?) async -> PortConditions671? {
        guard let code = unlocode, !code.isEmpty else { return nil }
        struct PortIn: Encodable { let portId: String }
        return try? await EusoTripAPI.shared.query(
            "vesselShipments.getPortWeather", input: PortIn(portId: code))
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
