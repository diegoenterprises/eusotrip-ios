//
//  578_RailRouteWeather.swift
//  EusoTrip — Rail Engineer · Route Weather (per-route weather conditions).
//
//  Verbatim port of "578 Rail Route Weather.svg" (Light + Dark).
//  Live WeatherKit alerts + impacted-loads count for the active route.
//  Corridor evidence hero: real endpoint labels, source, and weather risk.
//  No track line is painted until canonical rail geometry is supplied.
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
                    corridorEvidenceHero
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

    // MARK: - Corridor evidence hero

    /// `weather.getRouteConditions` returns named corridor segments and risk,
    /// not canonical track geometry. This deliberately reads as evidence, not
    /// a map: no authored curve, inferred car position, or weather pin is
    /// allowed to masquerade as rail topology.
    private var corridorEvidenceHero: some View {
        let riskColor: Color = overallRisk == "SEVERE" || overallRisk == "EXTREME" ? Brand.danger
            : overallRisk == "MODERATE" ? Brand.warning : Brand.success
        let origin = route?.origin?.label ?? impacted.first?.origin ?? "Origin pending"
        let destination = route?.destination?.label ?? impacted.first?.destination ?? "Destination pending"
        let source = routeSourceAttribution ?? "SOURCE PENDING"
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "cloud.sun.rain.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(riskColor)
                Text("CORRIDOR WEATHER EVIDENCE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 8)
                Text(overallRisk)
                    .font(.system(size: 10, weight: .bold)).kerning(0.5)
                    .foregroundStyle(riskColor)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(riskColor.opacity(0.16)))
            }

            HStack(spacing: 10) {
                weatherEndpoint(role: "ORIGIN", label: origin, tint: Brand.blue)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                    .accessibilityHidden(true)
                VStack(spacing: 4) {
                    Image(systemName: overallRisk == "CLEAR" ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(riskColor)
                    Text(source)
                        .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                    .accessibilityHidden(true)
                weatherEndpoint(role: "DESTINATION", label: destination, tint: Brand.magenta)
            }

            Label("Canonical rail geometry is not included in this weather response.",
                  systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Corridor weather evidence from \(origin) to \(destination). Risk \(overallRisk). \(source). Canonical rail geometry is not available.")
    }

    private func weatherEndpoint(role: String, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Circle().fill(tint).frame(width: 10, height: 10)
            Text(role)
                .font(.system(size: 7, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.65)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
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

}

#Preview("578 · Rail Route Weather · Night") { RailRouteWeatherScreen(theme: Theme.dark, railId: "RAIL-260518-48217A1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("578 · Rail Route Weather · Light") { RailRouteWeatherScreen(theme: Theme.light, railId: "RAIL-260518-48217A1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
