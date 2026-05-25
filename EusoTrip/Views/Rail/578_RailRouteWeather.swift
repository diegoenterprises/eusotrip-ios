//
//  578_RailRouteWeather.swift
//  EusoTrip — Rail Engineer · Route Weather (per-route weather conditions).
//
//  Verbatim port of "578 Rail Route Weather.svg" (Light + Dark).
//  Live NWS weather alerts + impacted-loads count for the active transcon route.
//  Map hero rendered via SwiftUI Canvas (no MapKit): gradient bg, dotted bezier
//  route line, origin/dest circles, snow/wind marker circles, ETA pill.
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME).
//
//  Data:
//    weather.getAlerts         (EXISTS weather.ts:437)  → [{id,eventType,severity,headline,states,onsetAt,…}]
//    weather.getImpactedLoads  (EXISTS weather.ts:481)  → [{loadId,loadNumber,origin,destination,alertSeverity,…}]
//    weather.getRouteConditions(EXISTS weather.ts:392)  → {origin,destination,overallRisk,segments,advisories}
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
    let id: Int
    let eventType: String?
    let severity: String?
    let urgency: String?
    let headline: String?
    let states: [String]?
    let counties: [String]?
    let onsetAt: String?
    let expiresAt: String?
}

private struct ImpactedLoad578: Decodable, Identifiable {
    let loadId: Int
    var id: Int { loadId }
    let loadNumber: String?
    let status: String?
    let origin: String?
    let destination: String?
    let alertSeverity: String?
}

private struct RouteConditions578: Decodable {
    let overallRisk: String?
    let segments: [RouteSegment578]?
    let advisories: [String]?
}

private struct RouteSegment578: Decodable, Identifiable {
    let id: Int
    let from: String?
    let to: String?
    let risk: String?
    let condition: String?
}

// MARK: - Body

private struct RailRouteWeatherBody: View {
    @Environment(\.palette) private var palette
    let railId: String

    @State private var alerts: [WeatherAlert578] = []
    @State private var impacted: [ImpactedLoad578] = []
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
                    mapHero
                    alertsList
                    if impactedCount > 0 { impactedFooter }
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
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
        return ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                let w = size.width; let h = size.height

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

                // Route bezier (Long Beach → Chicago, W→E transcon arc)
                let ox = w * 0.095; let oy = h * 0.85
                let dx = w * 0.940; let dy = h * 0.24
                var route = Path()
                route.move(to: CGPoint(x: ox, y: oy))
                route.addCurve(to: CGPoint(x: w * 0.45, y: h * 0.44),
                               control1: CGPoint(x: w * 0.30, y: h * 0.72),
                               control2: CGPoint(x: w * 0.38, y: h * 0.56))
                route.addCurve(to: CGPoint(x: dx, y: dy),
                               control1: CGPoint(x: w * 0.72, y: h * 0.34),
                               control2: CGPoint(x: w * 0.83, y: h * 0.34))
                ctx.stroke(route,
                           with: .linearGradient(
                            Gradient(colors: [Color(red: 0.082, green: 0.451, blue: 1.0),
                                              Color(red: 0.745, green: 0.004, blue: 1.0)]),
                            startPoint: CGPoint(x: ox, y: oy), endPoint: CGPoint(x: dx, y: dy)),
                           style: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: [1, 7]))

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

                // Snow marker (Rockies)
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

                // Wind marker (plains)
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
                ctx.draw(Text("ETA +14h · weather hold")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black),
                         at: CGPoint(x: pillCx, y: pillY + pillH / 2), anchor: .center)

                // Origin / destination labels
                ctx.draw(Text("LONG BEACH")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundColor(Color(red: 0.051, green: 0.067, blue: 0.090)),
                         at: CGPoint(x: ox + 2, y: oy + 16), anchor: .center)
                ctx.draw(Text("CHICAGO")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundColor(Color(red: 0.051, green: 0.067, blue: 0.090)),
                         at: CGPoint(x: dx - 24, y: dy - 14), anchor: .center)
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

    // MARK: - Alerts list

    private var alertsList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("ROUTE CONDITIONS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getRouteConditions")
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
        let (chipColor, chipIcon) = alertChipInfo(alert.eventType ?? "")
        let (pillLabel, pillColor) = severityPillInfo(alert.severity ?? "")
        let title = alert.headline.map { String($0.prefix(48)) } ?? (alert.eventType ?? "—")
        let stateSub = statesLabel(alert.states)
        let timeSub  = alert.onsetAt.map { " · \($0.prefix(16))" } ?? ""
        let sub = stateSub + timeSub

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(chipColor.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: chipIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(chipColor)
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
        }
        .padding(16)
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
        guard let s = states, !s.isEmpty else { return "—" }
        return s.prefix(3).joined(separator: ", ")
    }

    // MARK: - Impacted footer

    private var impactedFooter: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(impactedCount) active shipment\(impactedCount == 1 ? "" : "s") impacted")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("getImpactedLoads · \(rerouteCount) reroute candidate\(rerouteCount == 1 ? "" : "s")")
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
            CTAButton(title: "Reroute advisory", action: {}, leadingIcon: "arrow.triangle.branch")
            Button {} label: {
                Text("Notify shipper")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(palette.bgCard)
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        do {
            async let alertsResult: [WeatherAlert578] = EusoTripAPI.shared.queryNoInput("weather.getAlerts")
            async let impactedResult: [ImpactedLoad578] = EusoTripAPI.shared.queryNoInput("weather.getImpactedLoads")
            let (a, i) = try await (alertsResult, impactedResult)
            self.alerts   = a
            self.impacted = i
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("578 · Rail Route Weather · Night") { RailRouteWeatherScreen(theme: Theme.dark, railId: "RAIL-260518-48217A1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("578 · Rail Route Weather · Light") { RailRouteWeatherScreen(theme: Theme.light, railId: "RAIL-260518-48217A1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
