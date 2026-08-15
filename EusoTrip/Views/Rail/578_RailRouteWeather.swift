//
//  578_RailRouteWeather.swift
//  EusoTrip — Rail Engineer · Route Weather (per-route weather conditions).
//
//  Verbatim port of "578 Rail Route Weather.svg" (Light + Dark).
//  Live WeatherKit alerts + impacted-loads count for the active route.
//  Map hero rendered via SwiftUI Canvas (no MapKit): gradient bg, dotted bezier
//  route line, origin/dest circles, snow/wind marker circles, ETA pill.
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME).
//
//  Data:
//    weather.getAlerts         (EXISTS weather.ts:437)  → [{id,eventType,severity,headline,states,onsetAt,…}]
//    weather.getImpactedLoads  (EXISTS weather.ts:481)  → [{loadId,loadNumber,origin,destination,alertSeverity,…}]
//    weather.getRouteConditions(EXISTS weather.ts:392)  → {available?,origin,destination,
//        overallRisk, segments:[{from,to,risk,condition,weatherCode,windGust,visibility,
//        precipitationIntensity,floods[],overallRisk}], advisories:[{eventType,severity,
//        headline,expiresAt}]}  — HERE route weather first, with an explicitly
//        attributed WeatherKit fallback and honest unavailable state.
//        Input: {origin:{city,state}, destination:{city,state}} — derived from the first
//        REAL impacted load's "City, ST" endpoints; never invented.
//

import SwiftUI

struct RailRouteWeatherScreen: View {
    let theme: Theme.Palette
    let railId: String

    var body: some View {
        Shell(theme: theme) { RailRouteWeatherBody(railId: railId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct WeatherAlert578: Decodable, Identifiable {
    let id: String
    let eventType: String?
    let severity: String?
    let urgency: String?
    let headline: String?
    let states: [String]?
    let counties: [String]?
    let onsetAt: String?
    let expiresAt: String?
    let detailsUrl: String?
    let issuingSource: String?
    let source: String?
}

private struct ImpactedLoad578: Decodable, Identifiable {
    let loadId: String
    var id: String { loadId }
    let loadNumber: String?
    let status: String?
    let origin: String?
    let destination: String?
    let alertSeverity: String?

    private enum CodingKeys: String, CodingKey {
        case loadId, loadNumber, status, origin, destination, alertSeverity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? c.decode(String.self, forKey: .loadId) {
            loadId = value
        } else if let value = try? c.decode(Int.self, forKey: .loadId) {
            loadId = String(value)
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.loadId,
                .init(codingPath: c.codingPath, debugDescription: "Missing loadId")
            )
        }
        loadNumber = try c.decodeIfPresent(String.self, forKey: .loadNumber)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        origin = try c.decodeIfPresent(String.self, forKey: .origin)
        destination = try c.decodeIfPresent(String.self, forKey: .destination)
        alertSeverity = try c.decodeIfPresent(String.self, forKey: .alertSeverity)
    }
}

/// `weather.getRouteConditions` — the HERE-first corridor envelope with an
/// explicitly attributed WeatherKit fallback. Every field remains optional;
/// `available == false`, missing source, or missing content is an honest empty.
private struct RouteConditions578: Decodable {
    let available: Bool?
    let source: String?
    let overallRisk: String?           // "low"|"moderate"|"high"|"extreme"|"unknown"
    let segments: [RouteSegment578]?
    let advisories: [RouteAdvisory578]?
    // origin/destination are echoed back as {city,state} — kept for the
    // corridor caption so we label the REAL endpoints, never invented cities.
    let origin: RoutePlace578?
    let destination: RoutePlace578?
}

private struct RoutePlace578: Decodable {
    let city: String?
    let state: String?
    var label: String {
        switch (city, state) {
        case let (c?, s?): return "\(c), \(s)"
        case let (c?, nil): return c
        case let (nil, s?): return s
        default: return "—"
        }
    }
}

/// Corridor advisory OBJECT (server changed [String] → [{…}]). Every field
/// optional so a partial row still decodes.
private struct RouteAdvisory578: Decodable, Identifiable {
    let eventType: String?
    let severity: String?
    let headline: String?
    let expiresAt: String?
    // Stable identity for ForEach (server carries no id on advisories).
    var id: String { (headline ?? eventType ?? "advisory") + (expiresAt ?? "") }
}

/// A corridor segment with normalized provider weather. EVERY
/// field is optional → `Decodable` synthesizes cleanly and the row collapses
/// to its honest endpoints when the enterprise feed is dark. (ForEach keys on
/// the enumerated offset, so no `Identifiable`/synthetic id is needed.)
private struct RouteSegment578: Decodable {
    let from: String?
    let to: String?
    let risk: String?                   // per-segment riskTier ladder
    let condition: String?
    // Provider per-segment metrics (nil when the route feed omitted them).
    let weatherCode: Int?
    let windGust: Double?               // mph
    let visibility: Double?             // mi
    let precipitationIntensity: Double? // in/hr
    let floods: [RouteFlood578]?
    let overallRisk: String?            // per-segment envelope echo
}

private struct RouteFlood578: Decodable {
    let severity: String?
    let headline: String?
}

// MARK: - Body

private struct RailRouteWeatherBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    let railId: String

    @State private var alerts: [WeatherAlert578] = []
    @State private var impacted: [ImpactedLoad578] = []
    @State private var route: RouteConditions578? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // MARK: Derived

    private var impactedCount: Int { impacted.count }
    private var rerouteCount: Int  { impacted.filter { ($0.alertSeverity ?? "").lowercased() == "severe" || ($0.alertSeverity ?? "").lowercased() == "extreme" }.count }
    private var overallRisk: String {
        if alerts.contains(where: { ($0.severity ?? "").lowercased() == "extreme" }) { return "EXTREME" }
        if alerts.contains(where: { ($0.severity ?? "").lowercased() == "severe"  }) { return "SEVERE"  }
        if alerts.contains(where: { ($0.severity ?? "").lowercased() == "moderate" }) { return "MODERATE" }
        return "CLEAR"
    }

    /// Real lifecycle fraction (0…1) of the corridor that has been *traveled* by the
    /// shipments routed on it, averaged over `getImpactedLoads`. Each load's status maps
    /// to its position along the route arc (en_route_pickup → at_delivery). This is the
    /// completed segment of the route — bound to live load lifecycle, never decorative.
    /// With no impacted loads, the corridor reads "departed" (small head) so the dash flow
    /// still communicates an active, monitored route.
    private var routeProgress: Double {
        guard !impacted.isEmpty else { return 0.06 }
        let frac = impacted.map { lifecycleFraction($0.status) }.reduce(0, +) / Double(impacted.count)
        return min(0.97, max(0.04, frac))
    }

    private func lifecycleFraction(_ status: String?) -> Double {
        switch (status ?? "").lowercased() {
        case "en_route_pickup": return 0.08
        case "at_pickup":       return 0.18
        case "in_transit":      return 0.58
        case "at_delivery":     return 0.95
        case "delivered":       return 1.0
        default:                return 0.40
        }
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading weather…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    mapHero
                    corridorSection
                    alertsList
                    if impactedCount > 0 { impactedFooter }
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("RAIL ENGINEER · ROUTE WEATHER")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text(String(railId.prefix(20)))
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Route weather")
                    .font(.system(size: 28, weight: .heavy))
                    .kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            IridescentHairline()
        }
    }

    // MARK: - Map hero

    private var mapHero: some View {
        let riskColor: Color = overallRisk == "SEVERE" || overallRisk == "EXTREME" ? Brand.danger
            : overallRisk == "MODERATE" ? Brand.warning : Brand.success
        let progress = routeProgress
        return ZStack(alignment: .topLeading) {
            // Continuous 60fps clock for the route dash flow. LINEAR is correct here:
            // the marching-ants dash on the *remaining* corridor is a perpetual loop, not
            // a one-shot UI beat. `paused: reduceMotion` freezes the phase to a static state.
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
              Canvas { ctx, size in
                let w = size.width; let h = size.height
                // Seconds since reference; one full dash cycle (period = dash+gap = 8pt) every ~1.1s.
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let dashPeriod = 8.0
                let phase = CGFloat((t / 1.1 * dashPeriod).truncatingRemainder(dividingBy: dashPeriod))

                // Background
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(
                            Gradient(colors: [Color(red: 0.957, green: 0.961, blue: 0.969),
                                              Color(red: 0.914, green: 0.925, blue: 0.941)]),
                            startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))

                // Subtle grid
                var grid = Path()
                for fx in [0.25, 0.50, 0.75] {
                    grid.move(to: CGPoint(x: w * fx, y: 0)); grid.addLine(to: CGPoint(x: w * fx, y: h))
                }
                grid.move(to: CGPoint(x: 0, y: h * 0.5)); grid.addLine(to: CGPoint(x: w, y: h * 0.5))
                ctx.stroke(grid, with: .color(.black.opacity(0.06)), lineWidth: 0.8)

                // Stylized corridor arc (abstract origin→destination backdrop;
                // the route-conditions contract carries no real coordinates)
                let ox = w * 0.095; let oy = h * 0.85
                let dx = w * 0.940; let dy = h * 0.24
                let route = Self.routePath(in: size)
                let routeGrad: GraphicsContext.Shading = .linearGradient(
                    Gradient(colors: [Color(red: 0.082, green: 0.451, blue: 1.0),
                                      Color(red: 0.745, green: 0.004, blue: 1.0)]),
                    startPoint: CGPoint(x: ox, y: oy), endPoint: CGPoint(x: dx, y: dy))

                // Remaining (not-yet-traveled) corridor: flowing dashes toward the destination.
                // dashPhase decreases with time so the ants march origin→dest (travel direction).
                if progress < 0.999 {
                    let remaining = route.trimmedPath(from: progress, to: 1)
                    ctx.stroke(remaining,
                               with: .color(Color(red: 0.082, green: 0.451, blue: 1.0).opacity(0.30)),
                               style: StrokeStyle(lineWidth: 3.5, lineCap: .round,
                                                  dash: [1, 7], dashPhase: -phase))
                }
                // Traveled segment = REAL load-lifecycle progress along the corridor (solid).
                let traveled = route.trimmedPath(from: 0, to: progress)
                if progress > 0.001 {
                    ctx.stroke(traveled, with: routeGrad,
                               style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                }

                // Live position marker — current fleet position at the real progress fraction.
                // Anchored to the traveled-trim endpoint (length-parameterized) so it lands
                // exactly on the solid/dashed boundary. Soft pulse ring breathes only when
                // motion is allowed; static dot otherwise.
                let pos = traveled.currentPoint ?? Self.pointOnRoute(progress, in: size)
                if !reduceMotion {
                    let pulse = 0.5 + 0.5 * sin(t * 2.2)              // 0…1, ~2.85s breath
                    let ringR = 7.0 + pulse * 5.0
                    ctx.stroke(Circle().path(in: CGRect(x: pos.x - ringR, y: pos.y - ringR,
                                                        width: ringR * 2, height: ringR * 2)),
                               with: .color(Color(red: 0.745, green: 0.004, blue: 1.0)
                                                .opacity(0.45 * (1 - pulse))),
                               lineWidth: 1.6)
                }
                ctx.fill(Circle().path(in: CGRect(x: pos.x - 6, y: pos.y - 6, width: 12, height: 12)),
                         with: .color(.white))
                ctx.fill(Circle().path(in: CGRect(x: pos.x - 4, y: pos.y - 4, width: 8, height: 8)),
                         with: routeGrad)

                // Origin circle (gradient filled)
                let origPt = CGPoint(x: ox, y: oy)
                ctx.fill(Circle().path(in: CGRect(x: origPt.x-8, y: origPt.y-8, width: 16, height: 16)),
                         with: .color(.white))
                ctx.fill(Circle().path(in: CGRect(x: origPt.x-5, y: origPt.y-5, width: 10, height: 10)),
                         with: .linearGradient(
                            Gradient(colors: [Color(red: 0.082, green: 0.451, blue: 1.0),
                                              Color(red: 0.745, green: 0.004, blue: 1.0)]),
                            startPoint: CGPoint(x: origPt.x-5, y: origPt.y),
                            endPoint: CGPoint(x: origPt.x+5, y: origPt.y)))

                // Destination circle (purple)
                let destPt = CGPoint(x: dx, y: dy)
                ctx.fill(Circle().path(in: CGRect(x: destPt.x-8, y: destPt.y-8, width: 16, height: 16)),
                         with: .color(.white))
                ctx.fill(Circle().path(in: CGRect(x: destPt.x-5, y: destPt.y-5, width: 10, height: 10)),
                         with: .color(Color(red: 0.745, green: 0.004, blue: 1.0)))

                // Snow marker (stylized corridor position)
                let snowPt = CGPoint(x: w * 0.52, y: h * 0.44)
                ctx.fill(Circle().path(in: CGRect(x: snowPt.x-13, y: snowPt.y-13, width: 26, height: 26)),
                         with: .color(.white))
                ctx.stroke(Circle().path(in: CGRect(x: snowPt.x-13, y: snowPt.y-13, width: 26, height: 26)),
                           with: .color(Color(red: 0.129, green: 0.588, blue: 0.953, opacity: 0.4)), lineWidth: 1)
                let sBlue = Color(red: 0.071, green: 0.463, blue: 0.690)
                for deg in stride(from: 0.0, to: 360.0, by: 45.0) {
                    let r = deg * Double.pi / 180
                    var seg = Path()
                    seg.move(to: CGPoint(x: snowPt.x - cos(r) * 5, y: snowPt.y - sin(r) * 5))
                    seg.addLine(to: CGPoint(x: snowPt.x + cos(r) * 5, y: snowPt.y + sin(r) * 5))
                    ctx.stroke(seg, with: .color(sBlue), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                }

                // Wind marker (stylized corridor position)
                let windPt = CGPoint(x: w * 0.775, y: h * 0.33)
                ctx.fill(Circle().path(in: CGRect(x: windPt.x-12, y: windPt.y-12, width: 24, height: 24)),
                         with: .color(.white))
                ctx.stroke(Circle().path(in: CGRect(x: windPt.x-12, y: windPt.y-12, width: 24, height: 24)),
                           with: .color(Color(red: 1.0, green: 0.655, blue: 0.149, opacity: 0.5)), lineWidth: 1)
                let wAmber = Color(red: 0.698, green: 0.451, blue: 0.000)
                for (dy2, len) in [(-3.0, 8.0), (1.0, 10.0)] {
                    var wl = Path()
                    wl.move(to: CGPoint(x: windPt.x - len/2, y: windPt.y + dy2))
                    wl.addLine(to: CGPoint(x: windPt.x + len/2, y: windPt.y + dy2))
                    ctx.stroke(wl, with: .color(wAmber), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                }

                // ETA pill
                let pillCx = w * 0.67; let pillY = h * 0.07
                let pillW = 130.0; let pillH = 22.0
                let pillRect = CGRect(x: pillCx - pillW/2, y: pillY, width: pillW, height: pillH)
                ctx.fill(RoundedRectangle(cornerRadius: 11).path(in: pillRect), with: .color(.white))
                ctx.stroke(RoundedRectangle(cornerRadius: 11).path(in: pillRect),
                           with: .color(.black.opacity(0.10)), lineWidth: 1)
                // Real weather signal (from getAlerts severity), never a
                // fabricated ETA — the corridor carries no coordinates or ETA.
                ctx.draw(Text(overallRisk == "CLEAR"
                              ? "Clear corridor"
                              : "\(overallRisk.capitalized) weather risk")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black),
                         at: CGPoint(x: pillCx, y: pillY + pillH / 2), anchor: .center)

                // Origin / destination role labels — the route-conditions
                // contract carries no coordinates and no canonical corridor,
                // so we never paint specific invented cities on this stylized
                // arc. The arc is an honest abstract weather backdrop.
                ctx.draw(Text("ORIGIN")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundColor(Color(red: 0.051, green: 0.067, blue: 0.090)),
                         at: CGPoint(x: ox + 2, y: oy + 16), anchor: .center)
                ctx.draw(Text("DESTINATION")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundColor(Color(red: 0.051, green: 0.067, blue: 0.090)),
                         at: CGPoint(x: dx - 24, y: dy - 14), anchor: .center)
              }
            }
            .frame(height: 130)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint))

            // Overall risk chip (top-left overlay)
            Text(overallRisk)
                .font(.system(size: 10, weight: .bold)).kerning(0.5)
                .foregroundStyle(riskColor)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(riskColor.opacity(0.16).blendMode(.normal)))
                .padding(10)
        }
    }

    // MARK: - Corridor weather (weather.getRouteConditions)

    /// riskTier ladder → Brand color (none/low → info, watch/moderate →
    /// warning, elevated/high/severe/extreme → danger). Bound to the real
    /// server string, never a hardcoded severity.
    private func corridorRiskColor(_ raw: String?) -> Color {
        switch (raw ?? "").lowercased() {
        case "extreme", "severe", "high", "elevated": return Brand.danger
        case "moderate", "watch":                     return Brand.warning
        case "low", "none", "clear":                  return Brand.success
        default:                                       return palette.textTertiary
        }
    }

    /// Render the corridor card only when there's REAL content AND the feed
    /// hasn't explicitly reported itself dark. The enterprise gate is honored
    /// two ways: an explicit `available == false` always collapses to the
    /// empty state; absent/`true` falls through to "show whatever real
    /// segments/advisories the server returned" (so live advisory objects on
    /// the current server still surface). No content → empty state.
    private var corridorAvailable: Bool {
        guard let r = route else { return false }
        if r.available == false { return false }
        guard routeSourceAttribution != nil else { return false }
        return !(r.segments?.isEmpty ?? true) || !(r.advisories?.isEmpty ?? true)
    }

    private var routeSourceAttribution: String? {
        let normalized = (route?.source ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized.contains("here") { return "HERE ROUTE WEATHER" }
        if normalized.contains("weatherkit") || normalized.contains("apple weather") {
            return "APPLE WEATHERKIT FALLBACK"
        }
        return nil
    }

    private var corridorSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("CORRIDOR WEATHER")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(routeSourceAttribution ?? "route source pending")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }

            if !corridorAvailable {
                corridorEmpty
            } else {
                let segs = route?.segments ?? []
                let advs = route?.advisories ?? []
                VStack(spacing: 0) {
                    if let cap = corridorCaption {
                        corridorHeaderRow(cap)
                        if !segs.isEmpty || !advs.isEmpty {
                            Divider().overlay(palette.borderFaint)
                        }
                    }
                    ForEach(Array(segs.enumerated()), id: \.offset) { idx, seg in
                        segmentRow(seg)
                        if idx < segs.count - 1 || !advs.isEmpty {
                            Divider().padding(.leading, 52).overlay(palette.borderFaint)
                        }
                    }
                    ForEach(Array(advs.enumerated()), id: \.offset) { idx, adv in
                        advisoryRow(adv)
                        if idx < advs.count - 1 {
                            Divider().padding(.leading, 52).overlay(palette.borderFaint)
                        }
                    }
                }
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            }
        }
    }

    /// "Austin, TX → Dallas, TX · overall HIGH" — REAL echoed endpoints.
    private var corridorCaption: String? {
        guard let r = route, let o = r.origin, let d = r.destination else { return nil }
        let oL = o.label, dL = d.label
        guard oL != "—" || dL != "—" else { return nil }
        let risk = (r.overallRisk ?? "").lowercased()
        let riskStr = risk.isEmpty || risk == "unknown" ? "" : " · overall \(risk.uppercased())"
        return "\(oL) → \(dL)\(riskStr)"
    }

    private func corridorHeaderRow(_ caption: String) -> some View {
        HStack(spacing: 10) {
            WeatherIcons.utility(.route, size: 16, tint: corridorRiskColor(route?.overallRisk))
            Text(caption)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    /// One corridor leg: normalized condition glyph + the
    /// endpoints + a riskTier dot, with the gated metrics (gust · vis ·
    /// precip) shown only when present.
    private func segmentRow(_ seg: RouteSegment578) -> some View {
        let risk = seg.risk ?? seg.overallRisk
        let color = corridorRiskColor(risk)
        let title: String = {
            switch (seg.from, seg.to) {
            case let (f?, t?): return "\(f) → \(t)"
            case let (f?, nil): return f
            case let (nil, t?): return t
            default:           return seg.condition ?? "Segment"
            }
        }()
        return HStack(alignment: .top, spacing: 12) {
            // Provider-normalized condition glyph (honest unknown-cloud at code 0).
            WeatherIcons.symbolView(for: seg.weatherCode ?? 0, size: 28)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    if let c = seg.condition, !c.isEmpty,
                       title != c {
                        Text(c)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                let metrics = segmentMetrics(seg)
                if !metrics.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(metrics) { metric in
                            HStack(spacing: 4) {
                                WeatherIcons.utility(metric.glyph, size: 13, tint: palette.textTertiary)
                                Text(metric.value)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                    }
                }
                ForEach(Array((seg.floods ?? []).enumerated()), id: \.offset) { _, flood in
                    HStack(spacing: 5) {
                        WeatherIcons.utility(.alert, size: 12, tint: Brand.danger)
                        Text(flood.headline ?? "Flood advisory")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Brand.danger)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            if let risk, !risk.isEmpty {
                Text(risk.uppercased())
                    .font(.system(size: 10, weight: .bold)).kerning(0.4)
                    .foregroundStyle(color)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(color.opacity(0.12)))
            }
        }
        .padding(14)
    }

    /// One gated per-segment metric chip (glyph + value). Identifiable on its
    /// glyph kind (each kind appears at most once per segment).
    private struct SegMetric578: Identifiable {
        let glyph: WeatherIcons.Utility
        let value: String
        var id: WeatherIcons.Utility { glyph }
    }

    /// The gated per-segment metrics (gust · visibility · precip). Each is
    /// shown ONLY when its field is present → honest collapse otherwise.
    private func segmentMetrics(_ seg: RouteSegment578) -> [SegMetric578] {
        var out: [SegMetric578] = []
        if let gust = WeatherNumeric.roundedInt(seg.windGust, allowed: WeatherNumeric.windMph) {
            out.append(.init(glyph: .wind, value: "\(gust) mph"))
        }
        if let v = seg.visibility {
            out.append(.init(glyph: .eye, value: "\(v.formatted(.number.precision(.fractionLength(0...1)))) mi"))
        }
        if let p = seg.precipitationIntensity {
            out.append(.init(glyph: .precip, value: "\(p.formatted(.number.precision(.fractionLength(0...2)))) in/h"))
        }
        return out
    }

    /// Corridor advisory OBJECT row (eventType/severity/headline/expiresAt).
    private func advisoryRow(_ adv: RouteAdvisory578) -> some View {
        let color = corridorRiskColor(adv.severity)
        let title = adv.headline ?? adv.eventType ?? "Advisory"
        let exp = adv.expiresAt.flatMap(relativeExpiry)
        return HStack(alignment: .top, spacing: 12) {
            WeatherIcons.utility(.alert, size: 18, tint: color)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let et = adv.eventType, !et.isEmpty {
                        Text(et)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(palette.textSecondary)
                    }
                    if let exp { Text("· \(exp)").font(.system(size: 11)).foregroundStyle(palette.textTertiary) }
                }
            }
            Spacer(minLength: 8)
            if let sev = adv.severity, !sev.isEmpty {
                Text(sev.uppercased())
                    .font(.system(size: 10, weight: .bold)).kerning(0.4)
                    .foregroundStyle(color)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(color.opacity(0.12)))
            }
        }
        .padding(14)
    }

    private func relativeExpiry(_ iso: String) -> String? {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return nil }
        let secs = Int(date.timeIntervalSinceNow)
        if secs <= 0 { return "expired" }
        if secs < 3600 { return "expires \(secs / 60)m" }
        if secs < 86400 { return "expires \(secs / 3600)h" }
        return "expires \(secs / 86400)d"
    }

    /// Honest empty corridor — enterprise-gated weather feed is dark, so we
    /// read well NOW and light up the moment the key lands. Bespoke glyph
    /// (WeatherIcons.route), not an SF Symbol.
    private var corridorEmpty: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(palette.textTertiary.opacity(0.10))
                    .frame(width: 40, height: 40)
                WeatherIcons.utility(.route, size: 20, tint: palette.textTertiary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("No corridor weather")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(impacted.isEmpty
                     ? "No active shipment on this corridor — per-segment gusts, visibility and precip populate once a load is in transit."
                     : "Per-segment weather is enterprise-gated. Gusts, visibility, precip and flood advisories light up the moment the feed is configured.")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint))
    }

    // MARK: - Alerts list

    private var alertsList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("ACTIVE ALERTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("weather alert feed")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            if alerts.isEmpty {
                EusoEmptyState(systemImage: "cloud.sun.fill",
                               title: "No active alerts",
                               subtitle: "Route conditions are clear along this corridor.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(alerts.prefix(8).enumerated()), id: \.element.id) { idx, alert in
                        alertRow(alert)
                        if idx < min(alerts.count, 8) - 1 {
                            Divider().padding(.leading, 68).overlay(palette.borderFaint)
                        }
                    }
                }
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            }
        }
    }

    private func alertRow(_ alert: WeatherAlert578) -> some View {
        let chipColor = alertChipInfo(alert.eventType ?? "").0
        let (pillLabel, pillColor) = severityPillInfo(alert.severity ?? "")
        let title = alert.headline.map { String($0.prefix(48)) } ?? (alert.eventType ?? "-")
        let stateSub = statesLabel(alert.states)
        let timeSub  = alert.onsetAt.map { " · \($0.prefix(16))" } ?? ""
        let sourceSub = alert.issuingSource.map { " · \($0)" } ?? ""
        let sub = stateSub + timeSub + sourceSub

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(chipColor.opacity(0.14))
                    .frame(width: 40, height: 40)
                alertGlyph(alert.eventType ?? "", size: 22)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(sub)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(pillLabel)
                .font(.system(size: 10, weight: .bold)).kerning(0.4)
                .foregroundStyle(pillColor)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(pillColor.opacity(0.12)))
            if alert.detailsUrl.flatMap(URL.init(string:)) != nil {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(16)
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = alert.detailsUrl.flatMap(URL.init(string:)) {
                openURL(url)
            }
        }
    }

    private func alertChipInfo(_ eventType: String) -> (Color, String) {
        let et = eventType.lowercased()
        if et.contains("snow") || et.contains("winter") || et.contains("blizzard") || et.contains("ice") {
            return (Brand.info, "cloud.snow.fill")
        }
        if et.contains("wind") { return (Brand.warning, "wind") }
        if et.contains("flood") { return (Brand.info, "drop.fill") }
        if et.contains("tornado") || et.contains("hurricane") { return (Brand.danger, "hurricane") }
        if et.contains("thunder") || et.contains("storm") { return (Brand.warning, "cloud.bolt.fill") }
        if et.contains("clear") || et.contains("sun") { return (Brand.success, "sun.max.fill") }
        if et.contains("fog")  { return (palette.textSecondary, "cloud.fog.fill") }
        return (palette.textSecondary, "cloud.fill")
    }

    /// Bespoke condition glyph for an NWS alert type — WeatherIcons, never an SF Symbol.
    @ViewBuilder private func alertGlyph(_ eventType: String, size: CGFloat) -> some View {
        let et = eventType.lowercased()
        if et.contains("ice") || et.contains("freez") {
            WeatherIcons.symbolView(for: 6201, size: size)
        } else if et.contains("snow") || et.contains("winter") || et.contains("blizzard") {
            WeatherIcons.symbolView(for: 5101, size: size)
        } else if et.contains("wind") {
            WeatherIcons.utility(.wind, size: size, tint: Brand.warning)
        } else if et.contains("flood") {
            WeatherIcons.utility(.precip, size: size, tint: Brand.info)
        } else if et.contains("tornado") || et.contains("hurricane") || et.contains("thunder") || et.contains("storm") {
            WeatherIcons.symbolView(for: 8000, size: size)
        } else if et.contains("clear") || et.contains("sun") {
            WeatherIcons.symbolView(for: 1000, size: size)
        } else if et.contains("fog") {
            WeatherIcons.symbolView(for: 2000, size: size)
        } else {
            WeatherIcons.symbolView(for: 1102, size: size)
        }
    }

    private func severityPillInfo(_ severity: String) -> (String, Color) {
        switch severity.lowercased() {
        case "extreme":  return ("EXTREME",  Brand.danger)
        case "severe":   return ("SEVERE",   Brand.danger)
        case "moderate": return ("WATCH",    Brand.warning)
        case "minor":    return ("ADVISORY", Brand.info)
        default:         return ("ACTIVE",   palette.textSecondary)
        }
    }

    private func statesLabel(_ states: [String]?) -> String {
        guard let s = states, !s.isEmpty else { return "-" }
        return s.prefix(3).joined(separator: ", ")
    }

    // MARK: - Impacted footer

    private var impactedFooter: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(impactedCount) active shipment\(impactedCount == 1 ? "" : "s") impacted")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("Impacted loads · \(rerouteCount) reroute candidate\(rerouteCount == 1 ? "" : "s")")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint))
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            RailSecondaryActionButton(
                title: "Reroute review",
                sheetTitle: "Route weather reroute context",
                lines: rerouteReviewLines,
                width: 176,
                systemImage: "arrow.triangle.branch"
            )
            RailSecondaryActionButton(
                title: "Notify review",
                sheetTitle: "Shipper weather notification context",
                lines: notifyReviewLines,
                systemImage: "paperplane.fill"
            )
        }
    }

    private var rerouteReviewLines: [String] {
        var lines = [
            "Risk \(overallRisk.uppercased()) · impacted \(impactedCount) · reroute candidates \(rerouteCount)",
            corridorCaption ?? "Corridor endpoints pending"
        ]
        lines.append(contentsOf: (route?.segments ?? []).prefix(6).map { seg in
            "\(seg.from ?? "origin") → \(seg.to ?? "destination") · \(seg.risk ?? seg.overallRisk ?? "risk pending") · \(seg.condition ?? "condition pending")"
        })
        lines.append(contentsOf: alerts.prefix(4).map { alert in
            "\(alert.headline ?? alert.eventType ?? "Alert") · \(alert.severity ?? "severity pending") · \(statesLabel(alert.states))"
        })
        return lines
    }

    private var notifyReviewLines: [String] {
        var lines = [
            "\(impactedCount) impacted load\(impactedCount == 1 ? "" : "s") · corridor \(overallRisk)",
            "Alerts \(alerts.count) · route feed \(corridorAvailable ? "available" : "unavailable")"
        ]
        lines.append(contentsOf: impacted.prefix(6).map { load in
            "\(load.loadNumber ?? "Load") · \(load.origin ?? "origin") → \(load.destination ?? "destination") · \(load.alertSeverity ?? "severity pending")"
        })
        return lines
    }

    // MARK: - Load

    /// Input for `weather.getRouteConditions` — origin/destination as
    /// {city,state}. We never invent these: they're parsed from a REAL
    /// impacted load's "City, ST" endpoints (the only corridor on file for
    /// this surface). No load → no call → honest empty corridor.
    private struct RouteConditionsInput: Encodable {
        struct Place: Encodable { let city: String; let state: String }
        let origin: Place
        let destination: Place
    }

    /// Parse a server "City, ST" endpoint string into {city,state}; nil when
    /// the string is "Unknown"/empty/malformed (so we never query garbage).
    private func parsePlace(_ s: String?) -> RouteConditionsInput.Place? {
        guard let raw = s?.trimmingCharacters(in: .whitespaces), !raw.isEmpty,
              raw.lowercased() != "unknown" else { return nil }
        let parts = raw.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return .init(city: parts[0], state: parts[1])
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            async let alertsResult: [WeatherAlert578] = EusoTripAPI.shared.queryNoInput("weather.getAlerts")
            async let impactedResult: [ImpactedLoad578] = EusoTripAPI.shared.queryNoInput("weather.getImpactedLoads")
            let (a, i) = try await (alertsResult, impactedResult)
            self.alerts   = a.filter { approvedAmbientAlertSource($0.source) }
            self.impacted = i

            // Corridor conditions are computed for the first REAL impacted
            // load's origin→destination. No impacted load (or unparseable
            // endpoints) → leave `route` nil → honest "No corridor weather".
            if let first = i.first,
               let o = parsePlace(first.origin),
               let d = parsePlace(first.destination) {
                self.route = try? await EusoTripAPI.shared.query(
                    "weather.getRouteConditions",
                    input: RouteConditionsInput(origin: o, destination: d))
            } else {
                self.route = nil
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func approvedAmbientAlertSource(_ raw: String?) -> Bool {
        switch (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "weatherkit", "openweather":
            return true
        default:
            return false
        }
    }

    // MARK: - Route geometry (single source of truth for line + position dot)

    /// The stylized corridor arc as two cubic Béziers. Built once per draw so
    /// the traveled/remaining trims and the live-position dot all share identical control points.
    private static func routePath(in size: CGSize) -> Path {
        let w = size.width; let h = size.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.095, y: h * 0.85))
        p.addCurve(to: CGPoint(x: w * 0.45, y: h * 0.44),
                   control1: CGPoint(x: w * 0.30, y: h * 0.72),
                   control2: CGPoint(x: w * 0.38, y: h * 0.56))
        p.addCurve(to: CGPoint(x: w * 0.940, y: h * 0.24),
                   control1: CGPoint(x: w * 0.72, y: h * 0.34),
                   control2: CGPoint(x: w * 0.83, y: h * 0.34))
        return p
    }

    /// Point on the composite route at fraction `f` (0…1), split evenly across the two
    /// cubic segments. Mirrors `routePath` exactly so the position marker sits on the line.
    private static func pointOnRoute(_ f: Double, in size: CGSize) -> CGPoint {
        let w = size.width; let h = size.height
        let p0 = CGPoint(x: w * 0.095, y: h * 0.85)
        let p1 = CGPoint(x: w * 0.45,  y: h * 0.44)
        let p2 = CGPoint(x: w * 0.940, y: h * 0.24)
        let c1a = CGPoint(x: w * 0.30, y: h * 0.72), c1b = CGPoint(x: w * 0.38, y: h * 0.56)
        let c2a = CGPoint(x: w * 0.72, y: h * 0.34), c2b = CGPoint(x: w * 0.83, y: h * 0.34)
        let clamped = min(1, max(0, f))
        if clamped <= 0.5 {
            return cubic(p0, c1a, c1b, p1, clamped / 0.5)
        } else {
            return cubic(p1, c2a, c2b, p2, (clamped - 0.5) / 0.5)
        }
    }

    private static func cubic(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint, _ t: Double) -> CGPoint {
        let mt = 1 - t
        let w0 = mt * mt * mt, w1 = 3 * mt * mt * t, w2 = 3 * mt * t * t, w3 = t * t * t
        return CGPoint(x: w0 * a.x + w1 * b.x + w2 * c.x + w3 * d.x,
                       y: w0 * a.y + w1 * b.y + w2 * c.y + w3 * d.y)
    }
}

#Preview("578 · Rail Route Weather · Night") { RailRouteWeatherScreen(theme: Theme.dark, railId: "RAIL-260518-48217A1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("578 · Rail Route Weather · Light") { RailRouteWeatherScreen(theme: Theme.light, railId: "RAIL-260518-48217A1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
