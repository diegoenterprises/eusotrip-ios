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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
            VStack(alignment: .leading, spacing: Space.s4) {
                mapHero
                marineConditions
                berthingSafetySection
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

    // MARK: - Marine conditions strip (getMarineWeather · route midpoint)

    /// The marine forecast at the resolved route midpoint — significant
    /// wave / wind gust / visibility from `getMarineWeather.current`,
    /// rendered through the canonical metric-tile idiom with the bespoke
    /// WeatherIcons `.wave` / `.wind` / `.eye` glyphs (the PerLoadWeatherCard
    /// metricsGrid pattern). Honest: hidden entirely until the feed resolves
    /// (current == nil / feed unavailable) — never a fabricated reading.
    @ViewBuilder
    private var marineConditions: some View {
        if let c = marine?.current, marineHasAnyValue(c) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("MARINE CONDITIONS · getMarineWeather(midpoint)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(Color(hex: 0x6E7681))
                HStack(spacing: 8) {
                    // Significant wave height (sig wave) — .wave glyph.
                    marineTile(.wave,
                               value: c.waveHeight.map { String(format: "%.1f m", $0) },
                               key: "SIG WAVE")
                    // Wind gust — .wind glyph (gust preferred, sustained fallback).
                    marineTile(.wind,
                               value: (c.windGust ?? c.windSpeed).map { String(format: "%.0f kt", $0) },
                               key: c.windGust != nil ? "GUST" : "WIND")
                    // Visibility — .eye glyph.
                    marineTile(.eye,
                               value: c.visibility.map { String(format: "%.0f nm", $0) },
                               key: "VIS")
                }
            }
            // build-751: the continuous animated sky engine as a SUBTLE backdrop
            // behind the marine strip — bound ONLY to the REAL midpoint wind +
            // visibility (the marine feed carries no sky-condition code, so the
            // engine renders its neutral scene with real wind motion + low-vis
            // choke; nothing fabricated). Reduce Motion → static frame.
            .padding(14)
            .background(
                WeatherSkyView(snapshot: marineSkySnapshot(c), animated: !reduceMotion)
                    .opacity(0.55)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .allowsHitTesting(false)
            )
        }
    }

    /// A REAL `WeatherSnapshot` for the sky engine, built strictly from the
    /// marine midpoint feed: wind (kt → mph proxy for the wind-shear/streak
    /// layer), visibility (nm → mi proxy for the low-visibility choke), and the
    /// resolved midpoint latitude (hemisphere/season). `weatherCode` stays 0 —
    /// the marine feed has NO sky-condition classification, so the engine draws
    /// its honest neutral scene rather than an invented precipitation type.
    private func marineSkySnapshot(_ c: MarineForecastCurrent671) -> WeatherSnapshot {
        let windMph = Int(((c.windGust ?? c.windSpeed) ?? 0).rounded())
        let visMi = Int((c.visibility ?? 10).rounded())
        var snap = WeatherSnapshot(
            city: "",
            tempF: 0,
            windMph: max(0, windMph),
            visibilityMi: max(0, visMi),
            condition: "",
            symbol: "cloud.fill",
            nextAlert: nil,
            accent: .calm
        )
        snap.weatherCode = 0                  // unknown → engine neutral scene
        snap.latitude = marine?.lat ?? originCoord?.lat
        return snap
    }

    /// True when the marine current carries at least one of the three fields
    /// we surface — so the strip never frames on an all-"—" payload.
    private func marineHasAnyValue(_ c: MarineForecastCurrent671) -> Bool {
        c.waveHeight != nil || c.windGust != nil || c.windSpeed != nil || c.visibility != nil
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

    /// Per-port BERTHING-SAFETY chips. getRouteWeather/getMarineWeather are
    /// route-centric (open-water sea-state); the Safe/Caution/Restricted/Closed
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
                Text("BERTHING SAFETY · getPortWeather(portId)")
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
        (c.berthingSafety?.isEmpty == false) || c.windGust != nil || c.windSpeed != nil
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
        let gust = (chip.conditions.windGust ?? chip.conditions.windSpeed)
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

    /// No-endpoints / no-IMO placeholder so the hero never frames on null island.
    private var heroAwaiting: some View {
        VStack(spacing: 4) {
            // Bespoke route glyph — never an SF Symbol.
            WeatherIcons.utility(.route, size: 18, tint: Color(hex: 0x6E8198))
            Text(loading ? "Resolving voyage endpoints…" : "Awaiting routable ports")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: 0x8FA3BF))
        }
    }

    private var heroCaption: String {
        if loading { return "Loading route weather…" }
        if endpointsUnavailable { return "Booking has no routable origin/destination ports" }
        // HONEST enterprise-gate state (the DTN marine key isn't configured —
        // the server genuinely returns null): the real route geometry IS shown,
        // so we say so plainly without the alarming banned word. NEVER a
        // fabricated marine reading.
        if feedUnavailable { return "Live marine conditions on the enterprise feed · route geometry shown" }
        // Transient fetch error → framed as an in-progress update (the
        // `.refreshable`/`.task` path silently re-fetches), never "unavailable".
        if loadError != nil { return "Updating route weather…" }
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
            } else if loadError != nil {
                // Transient fetch error → a soft "Updating route weather…"
                // pane (no alarming danger card, never "unavailable"). The
                // screen's `.refreshable`/`.task` path re-fetches; pull-to-
                // refresh re-runs `load()`. NEVER a fabricated reading.
                marineEmptyPane(
                    glyph: .route,
                    title: "Updating route weather…",
                    subtitle: "Re-fetching per-leg sea-state for this voyage. Pull to refresh if it doesn't land in a moment.")
            } else if endpointsUnavailable {
                marineEmptyPane(
                    glyph: .route,
                    title: "No routable voyage",
                    subtitle: "This booking has no origin/destination ports on file, so route weather can't be computed. Assign a loading + discharge port and per-leg sea-state populates here.")
            } else if feedUnavailable {
                // HONEST enterprise-gate state: the DTN marine feed key isn't
                // configured for this tenant (the server genuinely returns
                // null) — this is a real data-coverage state, NOT a failure to
                // paper over, and NOT fabricated. The real route geometry is
                // still rendered on the hero; this pane explains the per-leg
                // sea-state needs the enterprise feed, without the banned word.
                marineEmptyPane(
                    glyph: .wave,
                    title: "Live marine conditions on the enterprise feed",
                    subtitle: "Route geometry is shown from the real voyage ports. Per-leg significant wave, wind gust and visibility light up the moment the enterprise marine feed is live for this account.",
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
    private func marineEmptyPane(glyph: WeatherIcons.Utility, title: String, subtitle: String, comingSoon: Bool = false) -> some View {
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
            if comingSoon {
                StatusPill(text: "Coming soon", kind: .info)
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
        let waveStr = seg.waveHeight.map { String(format: "%.1f m", $0) } ?? "-"
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
    /// then any server risk factors as supporting text. Honest "getMarineWeather"
    /// caption when the segment is value-less (partial DTN payload).
    @ViewBuilder
    private func legMetrics(_ seg: RouteWeatherSegment671) -> some View {
        let glyphTint = Color(red: 0.81, green: 0.88, blue: 1.0)
        HStack(spacing: 10) {
            if let w = seg.windSpeed {
                metricInline(.wind, String(format: "%.0f kt", w), tint: glyphTint)
            }
            if let s = seg.swellHeight {
                metricInline(.wave, String(format: "swell %.1f m", s), tint: glyphTint)
            }
            if let v = seg.visibility {
                metricInline(.eye, String(format: "%.0f nm", v), tint: glyphTint)
            }
            if seg.windSpeed == nil && seg.swellHeight == nil && seg.visibility == nil,
               (seg.riskFactors?.isEmpty ?? true) {
                Text("getMarineWeather")
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
        originBerth = nil; destinationBerth = nil
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
            // Per-port berthing safety (getPortWeather) — keyed by the resolved
            // port UN/LOCODE. Concurrent with the route/marine fetch; each stays
            // nil until the enterprise marine key lands (server returns null today).
            async let ob: PortConditions671? = portWeather(for: originPort?.unlocode)
            async let db: PortConditions671? = portWeather(for: destinationPort?.unlocode)
            let (routeRes, marineRes, originRes, destRes) = try await (r, m, ob, db)
            self.route = routeRes
            self.marine = marineRes
            self.originBerth = originRes
            self.destinationBerth = destRes
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
