//
//  WeatherCard.swift
//  EusoTrip — freight-grade weather card (Driver/Shipper/Catalyst/Carrier homes)
//
//  Level-100 rebuild (2026-06-11). Renders a live, route-aware freight
//  weather surface on top of an animated, scene-aware sky backdrop:
//
//    • Current conditions  — temp, feels-like, wind (+gusts), visibility,
//      humidity, precip chance. Every value live or em-dash.
//    • Severe alert ribbon — real NWS CAP severity (Minor/Moderate/
//      Severe/Extreme) from WeatherKit alerts, api.weather.gov, or HERE
//      Destination Weather nwsAlerts. Color = severity, never invented.
//    • Hourly band         — next 12 hours, horizontal strip.
//    • Lane strip          — the ACTIVE load's pickup → delivery weather
//      (HERE Destination Weather v3) + freight flags derived strictly
//      from live readings: high-profile wind, ice/snow chain-law risk,
//      low visibility, reefer ambient extremes.
//    • Flip side           — 6-day look-ahead + full alert detail.
//
//  Backdrop changes by time of day (stars + moon vs sun + atmosphere)
//  and condition (clear / cloudy / rain / thunder / snow / fog). All
//  motion is TimelineView + Canvas over pre-seeded particle arrays —
//  no per-frame allocation — and every animated layer collapses to a
//  single static frame under Reduce Motion.
//
//  Size tiers: `.full` (hero card, flip-enabled) and `.compact`
//  (single-row glance for half-tier widget slots).
//
//  The card is driven by `WeatherSnapshot` (+ optional `LaneWeather`).
//  No fabricated values anywhere — absent data renders "—" or collapses.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct WeatherCard: View {
    let snapshot: WeatherSnapshot
    /// Route-aware lane weather for the active load. Nil → the lane
    /// strip collapses (between loads, or HERE unavailable).
    var lane: LaneWeather? = nil
    /// `.full` = the v2 two-state card (collapsed dashboard ↔ expanded
    /// full view); `.compact` = one-row glance for half-tier slots.
    var style: Style = .full
    /// Start the `.full` card expanded (e.g. when pushed as its own
    /// screen). Default collapsed for the dashboard tile.
    var startExpanded: Bool = false

    enum Style { case full, compact }

    @Environment(\.palette) var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// v2 two-state. `false` = collapsed dashboard card; `true` =
    /// expanded full view. Tapping the collapsed card expands it; the
    /// expanded header's chevron collapses it back. Replaces the prior
    /// flip-card (the 6-day forecast now lives inline in the expanded
    /// view as the v2 7-day chip row).
    @State private var expanded: Bool

    init(snapshot: WeatherSnapshot,
         lane: LaneWeather? = nil,
         style: Style = .full,
         startExpanded: Bool = false) {
        self.snapshot = snapshot
        self.lane = lane
        self.style = style
        self.startExpanded = startExpanded
        _expanded = State(initialValue: startExpanded)
    }

    private var isNight: Bool {
        // Local clock is the *primary* night gate. The previous order
        // ("symbol first, clock fallback") was wrong because the NWS +
        // Open-Meteo fallback paths in WeatherService return day-only
        // SF Symbols (sun.max, cloud.rain.fill, etc.) regardless of
        // local hour — only WeatherKit emits a night-specific symbol.
        let h = Calendar.current.component(.hour, from: Date())
        let clockSaysNight = h >= 20 || h < 6
        if clockSaysNight { return true }
        if snapshot.symbol.contains("moon") || snapshot.symbol.contains("night") {
            return true
        }
        return false
    }

    private var condition: SkyCondition {
        let s = snapshot.condition.lowercased()
        let sym = snapshot.symbol.lowercased()
        if s.contains("thunder") || sym.contains("bolt") { return .thunder }
        if s.contains("snow") || sym.contains("snow") || sym.contains("snowflake") { return .snow }
        if s.contains("rain") || s.contains("shower") || s.contains("drizzle") || sym.contains("rain") { return .rain }
        if s.contains("fog") || s.contains("haze") || s.contains("smoke") || sym.contains("fog") { return .fog }
        if s.contains("cloud") || sym.contains("cloud") { return .cloudy }
        return .clear
    }

    var body: some View {
        switch style {
        case .compact: compactBody
        case .full:    fullBody
        }
    }

    // MARK: Full — v2 two-state (collapsed dashboard ↔ expanded full view)

    private var fullBody: some View {
        Group {
            if expanded {
                expandedView
            } else {
                collapsedCard
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    private func toggleExpanded() {
        if reduceMotion {
            expanded.toggle()
        } else {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) {
                expanded.toggle()
            }
        }
    }

    private var accessibilitySummary: String {
        var parts: [String] = [
            "Weather, \(snapshot.city), \(snapshot.condition), \(snapshot.tempDisplay)",
            "feels like \(snapshot.feelsLikeDisplay)",
            "wind \(snapshot.windDisplay), visibility \(snapshot.visibilityMi) miles"
        ]
        if let a = snapshot.heroAlert {
            parts.append("Active alert: \(a.title), severity \(a.severity.label)")
        }
        if let segs = snapshot.laneImpact, !segs.isEmpty {
            parts.append("\(segs.count) loads in this cell")
            for s in segs {
                parts.append("\(s.loadId), \(s.route), ETA risk \(s.etaDelayDisplay)")
            }
        }
        parts.append(expanded ? "Tap the chevron to collapse." : "Tap to expand the full forecast.")
        return parts.joined(separator: ", ")
    }

    // MARK: Collapsed — dashboard card

    /// The v2 COLLAPSED state: sky gradient · icon + location + condition
    /// + temp · H/L + alert pill · lane strip · EXPAND chevron. Tapping
    /// anywhere expands. Every line is live or hidden — the alert pill
    /// only renders with a real `heroAlert`, the lane strip only with
    /// real `laneImpact`.
    private var collapsedCard: some View {
        ZStack(alignment: .topLeading) {
            SkyStageHero(weatherCode: snapshot.weatherCode, compact: true)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 11) {
                // top: glyph · location/condition · temp
                HStack(alignment: .center, spacing: 13) {
                    WeatherIcons.symbolView(for: snapshot.weatherCode, size: 46)
                        .shadow(color: WeatherV3.sun.opacity(0.25), radius: 6, y: 4)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            WeatherIcons.utility(.pin, size: 12, tint: WeatherV3.nodeOrigin)
                            Text(snapshot.city.uppercased())
                                .font(.system(size: 12, weight: .heavy)).tracking(0.6)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        Text(collapsedConditionLine)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    Spacer(minLength: Space.s2)
                    superscriptTemp(snapshot.tempF, size: 42, supSize: 18)
                }

                // meta: H/L + alert pill
                HStack(spacing: 8) {
                    if let today = snapshot.daily.first {
                        Text("H \(today.highF)° · L \(today.lowF)°")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    if let a = snapshot.heroAlert {
                        alertPill(a)
                    }
                    Spacer(minLength: 0)
                }

                if let next = snapshot.nextWeatherDisplay {
                    nextWeatherPill(next)
                }

                // lane strip — N loads in this cell · LD-xxx · +Nm
                if let strip = snapshot.collapsedLaneStrip {
                    HStack(spacing: 9) {
                        WeatherIcons.utility(.route, size: 18, tint: Color(red: 0.80, green: 0.74, blue: 1.0))
                        (Text(strip.text + " · ")
                            .foregroundStyle(Color(red: 0.93, green: 0.92, blue: 0.96))
                         + Text(strip.loadId)
                            .foregroundStyle(.white).bold())
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(strip.delay)
                            .font(.system(size: 12, weight: .heavy))
                            .monospacedDigit()
                            .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.80))
                    }
                    .padding(.horizontal, 11).padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.06)))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
                }

                // EXPAND chevron
                HStack(spacing: 6) {
                    Spacer()
                    Text("EXPAND")
                        .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    WeatherIcons.utility(.chev, size: 13, tint: .white.opacity(0.6))
                    Spacer()
                }
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 1)
            }
            .padding(.horizontal, 16).padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isNight ? 0.35 : 0.18), radius: 18, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture { toggleExpanded() }
        .accessibilityAddTraits(.isButton)
        .transition(.opacity)
    }

    /// "Partly cloudy · feels 91°" — drops the feels clause when absent.
    private var collapsedConditionLine: String {
        if let f = snapshot.feelsLikeF {
            return "\(snapshot.condition) · feels \(f)°"
        }
        return snapshot.condition
    }

    /// Collapsed alert pill — gradient danger fill, real severity.
    private func alertPill(_ alert: WeatherSnapshot.ActiveAlert) -> some View {
        HStack(spacing: 5) {
            WeatherIcons.utility(.alert, size: 13, tint: .white)
            Text(alert.title.uppercased())
                .font(.system(size: 11, weight: .heavy)).tracking(0.2)
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(
            Capsule().fill(
                LinearGradient(colors: [alert.severity.color.opacity(0.95),
                                        alert.severity.color.opacity(0.66)],
                               startPoint: .leading, endPoint: .trailing)
            )
        )
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
    }

    private func nextWeatherPill(_ text: String) -> some View {
        HStack(spacing: 8) {
            WeatherIcons.utility(.precip, size: 14, tint: .white)
            Text(text)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.black.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
        )
    }

    // MARK: Expanded — full view

    /// The v2 EXPANDED state: hero · gov ALERT bar · 4 metrics · 8h
    /// hourly (peak highlighted) · LANE IMPACT panel · 6-day chips ·
    /// "Conditions · Apple Weather · Partly cloudy · updated Nm ago".
    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 13) {
            heroBlock
            // §D.1.5 — exactly one iridescent hairline per screen, set
            // between the hero stage and the operational Lane Impact.
            hairline.padding(.horizontal, 16)
            laneImpactPanel
            dayChips
            sourceLine
        }
        .transition(.opacity)
    }

    /// The v3 sky-stage hero — the bespoke `SkyStageHero` (aurora ribbon
    /// + cloud forms + route motif) BEHIND the readout: location/condition
    /// + superscript-degree temp/feels/H-L + hero glyph, gov alert bar,
    /// 4 metric tiles, the hourly ribbon. The stage mood is driven by the
    /// live `weatherCode`.
    private var heroBlock: some View {
        ZStack(alignment: .topLeading) {
            SkyStageHero(weatherCode: snapshot.weatherCode)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                // hero top: text column + collapse chevron + hero glyph
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            WeatherIcons.utility(.pin, size: 13, tint: WeatherV3.nodeOrigin)
                            Text(snapshot.city.uppercased())
                                .font(.system(size: 13, weight: .heavy)).tracking(0.6)
                                .foregroundStyle(.white)
                        }
                        Text(snapshot.condition)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.84))
                        superscriptTemp(snapshot.tempF, size: 60, supSize: 22)
                            .padding(.top, 6)
                        Text("Feels like \(snapshot.feelsLikeDisplay)")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.top, 2)
                        if let today = snapshot.daily.first {
                            Text("Today · H \(today.highF)° · L \(today.lowF)°")
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 11).padding(.vertical, 5)
                                .background(Capsule().fill(Color.white.opacity(0.14)))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                                .padding(.top, 10)
                        }
                    }
                    Spacer(minLength: Space.s2)
                    VStack(spacing: 10) {
                        // collapse affordance (chevron up)
                        Button(action: toggleExpanded) {
                            WeatherIcons.utility(.chev, size: 16, tint: .white.opacity(0.85))
                                .rotationEffect(.degrees(180))
                                .padding(7)
                                .background(Circle().fill(Color.white.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Collapse weather")
                        WeatherIcons.symbolView(for: snapshot.weatherCode, size: 64)
                            .shadow(color: WeatherV3.sun.opacity(0.25), radius: 8, y: 6)
                    }
                }

                // gov ALERT bar
                if let a = snapshot.heroAlert {
                    alertBar(a).padding(.top, 13)
                }

                if let next = snapshot.nextWeatherDisplay {
                    nextWeatherPill(next)
                        .padding(.top, snapshot.heroAlert == nil ? 13 : 8)
                }

                // 4 metrics
                metricsGrid.padding(.top, 13)

                // hourly ribbon — the v3 temp polyline over a precip area
                if snapshot.hourly.count >= 2 {
                    HourlyRibbon(hours: snapshot.hourly, peakIndex: snapshot.peakHourIndex)
                        .padding(.top, 14)
                        .padding(.horizontal, -16)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 18, y: 10)
    }

    /// The §D.1.5 superscript-degree readout — the big temp with a small
    /// raised "°" and `monospacedDigit`. White on the sky stage.
    private func superscriptTemp(_ value: Int, size: CGFloat, supSize: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 1) {
            Text("\(value)")
                .font(.system(size: size, weight: .ultraLight))
                .monospacedDigit()
            Text("°")
                .font(.system(size: supSize, weight: .light))
                .padding(.top, size * 0.12)
        }
        .foregroundStyle(.white)
    }

    /// Government ALERT bar — gradient danger fill, real CAP severity +
    /// expiry. Only shown when `heroAlert` is non-nil (honest).
    private func alertBar(_ alert: WeatherSnapshot.ActiveAlert) -> some View {
        HStack(spacing: 9) {
            WeatherIcons.utility(.alert, size: 18, tint: .white)
            Text(alert.title)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: Space.s1)
            Text([alert.severity.label, alert.untilDisplay].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 11, weight: .heavy)).tracking(0.3)
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(LinearGradient(colors: [alert.severity.color.opacity(0.95),
                                              alert.severity.color.opacity(0.6)],
                                     startPoint: .leading, endPoint: .trailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }

    /// 4 glass metric tiles: wind · visibility · humidity · precip.
    /// Each renders the v2 utility glyph + live value (em-dash if absent)
    /// + uppercase key. Wind/visibility pick up a hazard tint when their
    /// live value crosses a freight threshold.
    private var metricsGrid: some View {
        HStack(spacing: 8) {
            metricTile(.wind,   value: snapshot.windDisplay,           key: "WIND",       hazard: snapshot.windHazard)
            metricTile(.eye,    value: snapshot.visibilityDisplay,     key: "VISIBILITY", hazard: snapshot.visibilityHazard)
            metricTile(.humid,  value: snapshot.humidityDisplay,       key: "HUMIDITY",   hazard: false)
            metricTile(.precip, value: snapshot.precipChanceDisplay,   key: "PRECIP",     hazard: false)
        }
    }

    private func metricTile(_ glyph: WeatherIcons.Utility, value: String, key: String, hazard: Bool) -> some View {
        WeatherMetricTile(glyph: glyph, value: value, key: key,
                          hazard: hazard, reduceMotion: reduceMotion)
    }

    /// The single iridescent hairline (§D.1.5) — the v3 aurora stops
    /// (blue→magenta→pink), fading at both ends.
    private var hairline: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [.clear, WeatherV3.auroraA.opacity(0.7), WeatherV3.auroraB.opacity(0.95),
                         WeatherV3.auroraC.opacity(0.7), .clear],
                startPoint: .leading, endPoint: .trailing))
            .frame(height: 1)
    }

    // MARK: Expanded — LANE IMPACT panel

    /// The differentiator: per-load route-cell diagram (weather drawn
    /// crossing the actual lane) + the §3 footer + the mode-specific
    /// driver tiles + the ESang recommendation. Renders ONLY when
    /// `laneImpact` has real segments — collapses entirely between loads
    /// or when the route tier is absent.
    @ViewBuilder
    private var laneImpactPanel: some View {
        if let segs = snapshot.laneImpact, !segs.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // header: route glyph · LANE IMPACT · N-loads pill
                HStack(spacing: 8) {
                    WeatherIcons.utility(.route, size: 15, tint: WeatherV3.nodeOrigin)
                    Text(laneHeaderTitle(segs))
                        .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text("\(segs.count) LOAD\(segs.count == 1 ? "" : "S") IN THIS CELL")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(WeatherV3.danger.opacity(0.18)))
                        .overlay(Capsule().strokeBorder(WeatherV3.danger.opacity(0.46), lineWidth: 1))
                }

                ForEach(Array(segs.enumerated()), id: \.element.id) { idx, seg in
                    if idx > 0 {
                        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                            .padding(.vertical, 13)
                    }
                    laneSegment(seg).padding(.top, idx == 0 ? 13 : 0)
                }
            }
            .padding(15)
            .background(
                // Dark-glass ink (not adaptive palette.bgCard) so the panel's
                // white text stays readable in light mode too, matching the
                // always-dark hero stage above it.
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(WeatherV3.cardInk)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(modeAccent(segs.first?.mode).opacity(0.35), lineWidth: 1)
            )
        }
    }

    /// "LANE IMPACT" (truck/default) · "CORRIDOR IMPACT" (rail) ·
    /// "VOYAGE + BERTH IMPACT" (vessel) — from the tri-modal HTML headers.
    private func laneHeaderTitle(_ segs: [WeatherSnapshot.LaneImpactSegment]) -> String {
        switch segs.first?.mode {
        case .rail:   return "CORRIDOR IMPACT"
        case .vessel: return "VOYAGE + BERTH IMPACT"
        default:      return "LANE IMPACT"
        }
    }

    /// One full segment block: the route-cell diagram, the footer
    /// (mode chip · id/route/pickup · headline), the mode-specific driver
    /// tiles, and the ESang recommendation.
    @ViewBuilder
    private func laneSegment(_ seg: WeatherSnapshot.LaneImpactSegment) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // route-cell diagram + footer, inside a rounded "routebox"
            VStack(spacing: 0) {
                RouteCellDiagram(segment: seg)
                routeFooter(seg)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 0x17 / 255, green: 0x1A / 255, blue: 0x24 / 255),
                                 Color(red: 0x12 / 255, green: 0x14 / 255, blue: 0x1C / 255)],
                        startPoint: .top, endPoint: .bottom)))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // §3 drivers — the 3 mode-specific metric tiles
            if !seg.drivers.isEmpty {
                driverTiles(seg).padding(.top, 11)
            }

            // §3 recommendation — ESang orb line
            if let rec = seg.recommendation {
                esangRecommendation(rec).padding(.top, 12)
            } else if let suggestion = seg.esangSuggestion {
                esangFlat(suggestion).padding(.top, 12)
            }
        }
    }

    /// The route-box footer: mode chip · id + route/pickup · headline.
    private func routeFooter(_ seg: WeatherSnapshot.LaneImpactSegment) -> some View {
        HStack(alignment: .center, spacing: 11) {
            WeatherIcons.utility(modeGlyph(seg.mode), size: 18,
                                 tint: modeAccent(seg.mode).opacity(0.95))
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(modeAccent(seg.mode).opacity(0.16)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(modeAccent(seg.mode).opacity(0.45), lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(seg.loadId)
                    .font(.system(size: 12, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(footerSubtitle(seg))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 1) {
                Text(seg.headlineDisplay)
                    .font(.system(size: 15, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(seg.riskTier.color)
                    .lineLimit(1)
                Text(riskTierLabel(seg))
                    .font(.system(size: 9.5)).tracking(0.2)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
    }

    /// "I-35 · pickup 3:30 PM" / "BNSF consist · Kansas City" — the route
    /// + pickup line, honest dash-joined and only the parts we have.
    private func footerSubtitle(_ seg: WeatherSnapshot.LaneImpactSegment) -> String {
        let route = seg.route.trimmingCharacters(in: .whitespaces)
        let parts = [route.isEmpty ? nil : route, seg.pickupDisplay].compactMap { $0 }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    /// The footer risk label — "ETA RISK" (truck) · "DWELL ADD" (rail) ·
    /// "BERTH WINDOW" (vessel). When the headline already carries a window
    /// (vessel "Crane hold …") the label is the descriptor only.
    private func riskTierLabel(_ seg: WeatherSnapshot.LaneImpactSegment) -> String {
        switch seg.mode {
        case .truck:  return "ETA RISK"
        case .rail:   return "DWELL ADD"
        case .vessel: return "BERTH WINDOW"
        }
    }

    /// The §3 `drivers` tiles — 3 equal glass cells, each a mode-specific
    /// worst-case field. The glyph is chosen from the field name so the
    /// shipped UI stays on the in-house glyph set (no SF Symbols).
    private func driverTiles(_ seg: WeatherSnapshot.LaneImpactSegment) -> some View {
        HStack(spacing: 8) {
            ForEach(seg.drivers) { d in
                VStack(spacing: 3) {
                    WeatherIcons.utility(driverGlyph(d.field), size: 17,
                                         tint: driverTint(d.field))
                    Text(d.value)
                        .font(.system(size: 13, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(d.field.uppercased())
                        .font(.system(size: 9)).tracking(0.2)
                        .foregroundStyle(.white.opacity(0.64))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9).padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.white.opacity(0.09)))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
            }
        }
    }

    /// Map a §3 driver field name → an in-house glyph. Falls back to the
    /// precip glyph for anything unrecognised (never an SF Symbol).
    private func driverGlyph(_ field: String) -> WeatherIcons.Utility {
        let f = field.lowercased()
        if f.contains("wave") || f.contains("swell")  { return .wave }
        if f.contains("wind") || f.contains("gust") || f.contains("crosswind") { return .wind }
        if f.contains("vis")                          { return .eye }
        if f.contains("stream") || f.contains("flow") || f.contains("flood") { return .precip }
        if f.contains("precip") || f.contains("rain") { return .precip }
        return .precip
    }

    private func driverTint(_ field: String) -> Color {
        let f = field.lowercased()
        if f.contains("precip") || f.contains("wave") { return .white }
        return WeatherIcons.hatch
    }

    /// The §3 recommendation — ESang conic orb + framed text/action/
    /// protects. `action` is highlighted; the framing text + protected
    /// outcome read as one sentence. Verbatim from the v3 `.esang`.
    private func esangRecommendation(_ rec: WeatherSnapshot.Recommendation) -> some View {
        HStack(alignment: .top, spacing: 11) {
            esangOrb
            esangText(rec).font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(esangBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(WeatherV3.auroraB.opacity(0.34), lineWidth: 1))
    }

    /// Compose "ESang — {text}. {action} — protects {protects}." with the
    /// action in the brand highlight. Each clause is omitted when empty.
    private func esangText(_ rec: WeatherSnapshot.Recommendation) -> Text {
        var t = Text("ESang").bold().foregroundColor(.white)
        let framing = rec.text.trimmingCharacters(in: .whitespaces)
        if !framing.isEmpty {
            t = t + Text(" — \(framing). ").foregroundColor(Color(red: 0.93, green: 0.92, blue: 0.96))
        } else {
            t = t + Text(" — ").foregroundColor(Color(red: 0.93, green: 0.92, blue: 0.96))
        }
        t = t + Text(rec.action).bold().foregroundColor(Color(red: 0.78, green: 0.70, blue: 1.0))
        let protects = rec.protects.trimmingCharacters(in: .whitespaces)
        if !protects.isEmpty {
            t = t + Text(" — protects \(protects).").foregroundColor(Color(red: 0.93, green: 0.92, blue: 0.96))
        }
        return t
    }

    /// Legacy flat ESang line (older payloads with only `esangSuggestion`).
    private func esangFlat(_ suggestion: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            esangOrb
            (Text("ESang").bold().foregroundStyle(.white)
             + Text(" — \(suggestion)").foregroundStyle(Color(red: 0.93, green: 0.92, blue: 0.96)))
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(esangBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(WeatherV3.auroraB.opacity(0.34), lineWidth: 1))
    }

    /// The ESang conic-gradient orb brand mark (§D.1.5).
    private var esangOrb: some View {
        Circle()
            .fill(AngularGradient(
                gradient: Gradient(colors: [WeatherV3.auroraA, WeatherV3.auroraB,
                                            WeatherV3.auroraC, WeatherV3.auroraA]),
                center: .center, angle: .degrees(200)))
            .frame(width: 26, height: 26)
            .shadow(color: WeatherV3.auroraB.opacity(0.6), radius: 8)
    }

    private var esangBackground: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(LinearGradient(colors: [WeatherV3.auroraA.opacity(0.15), WeatherV3.auroraB.opacity(0.12)],
                                 startPoint: .leading, endPoint: .trailing))
    }

    private func modeGlyph(_ mode: WeatherSnapshot.LaneMode) -> WeatherIcons.Utility {
        switch mode {
        case .truck:  return .truck
        case .rail:   return .rail
        case .vessel: return .vessel
        }
    }

    /// The v3 mode accent (truck = aurora indigo · rail = slate ·
    /// vessel = cyan) — the accent-only mode tint.
    private func modeAccent(_ mode: WeatherSnapshot.LaneMode?) -> Color {
        switch mode {
        case .rail:   return WeatherV3.rail
        case .vessel: return WeatherV3.vessel
        default:      return WeatherV3.truck
        }
    }

    // MARK: Expanded — 6-day chips

    /// 6-day chip row — each chip = weekday · v3 glyph · hi→lo RANGE BAR ·
    /// hi/lo. The first day is the selected chip (magenta-tinted). The bar
    /// is sized to the day's temperatureMin/Max within the week's overall
    /// range (§D.1.4). Collapses when the upstream returned no daily data.
    @ViewBuilder
    private var dayChips: some View {
        if !snapshot.daily.isEmpty {
            // Show up to 6 days and FILL the row evenly — no trailing gap.
            // (Founder feedback: "fix the last slot's gap and add one more so
            // it is complete.") The 6th day appears whenever the upstream
            // forecast carries it; NWS often returns 5, WeatherKit returns more.
            let week = Array(snapshot.daily.prefix(6))
            let weekLow = week.map(\.lowF).min() ?? 0
            let weekHigh = week.map(\.highF).max() ?? 1
            HStack(spacing: 6) {
                ForEach(Array(week.enumerated()), id: \.element.id) { idx, day in
                    dayChip(day, isToday: idx == 0, weekLow: weekLow, weekHigh: weekHigh, flex: true)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// One day chip — weekday · v3 glyph · hi→lo range bar · hi/lo. The
    /// "today" chip carries the magenta-tinted selected style.
    private func dayChip(_ day: WeatherSnapshot.DailyForecast,
                         isToday: Bool, weekLow: Int, weekHigh: Int, flex: Bool = false) -> some View {
        // Dark-glass ink (not the adaptive palette.bgCard, which went white
        // in light mode and hid the white chip text). The widget is an
        // always-dark sky surface, so the chips stay dark in both schemes.
        let fill: AnyShapeStyle = isToday
            ? AnyShapeStyle(LinearGradient(
                colors: [WeatherV3.auroraB.opacity(0.30), WeatherV3.cardInk],
                startPoint: .top, endPoint: .bottom))
            : AnyShapeStyle(WeatherV3.cardInk)
        let stroke = isToday ? WeatherV3.auroraB.opacity(0.55) : Color.white.opacity(0.10)
        return VStack(spacing: 6) {
            Text(day.weekdayLabel == "Today" ? "Today" : day.weekdayLabel)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white.opacity(0.84))
            WeatherIcons.symbolView(for: dayCode(day), size: 20)
                .padding(.vertical, 1)
            DayRangeBar(lowF: day.lowF, highF: day.highF,
                        weekLow: weekLow, weekHigh: weekHigh)
                .padding(.horizontal, 12)
            HStack(spacing: 4) {
                Text(day.highDisplay)
                    .font(.system(size: 11, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(day.lowDisplay)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: flex ? nil : 62)
        .frame(maxWidth: flex ? .infinity : nil)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(stroke, lineWidth: isToday ? 1 : 0.5)
        )
    }

    /// A day chip's weatherCode — uses the day's own code if the upstream
    /// supplied one (Tomorrow.io path), else infers from its SF symbol.
    private func dayCode(_ day: WeatherSnapshot.DailyForecast) -> Int {
        WeatherIcons.code(forSymbol: day.symbol)
    }

    // MARK: Expanded — source line

    /// "Conditions · Apple Weather · Partly cloudy · updated Nm ago".
    /// Built from `snapshot.attributionLine` so it names the REAL data
    /// source (Tomorrow.io only when Tomorrow.io produced the data) and
    /// omits condition/updated clauses when their data is absent.
    private var sourceLine: some View {
        // Adaptive — this line sits directly on the page (no card), so
        // white-on-light was invisible in light mode. Palette tertiary
        // contrasts in both schemes.
        Group {
            if snapshot.dataSource == .weatherKit {
                // Apple WeatherKit legal terms REQUIRE a visible "Apple Weather"
                // mark (already in attributionLine) PLUS a tappable link to the
                // attribution page on any surface showing WeatherKit data —
                // omitting it is an App Review rejection. Only rendered when
                // WeatherKit actually produced the data (honest attribution).
                HStack(spacing: 4) {
                    Text(snapshot.attributionLine)
                    Link("Legal", destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!)
                        .underline()
                }
                .font(.system(size: 11))
                .foregroundStyle(palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 1)
            } else {
                Text(snapshot.attributionLine)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 1)
            }
        }
    }

    // MARK: Compact — one-row glance (half-tier widget slots)

    private var compactBody: some View {
        ZStack(alignment: .leading) {
            SkyBackdrop(isNight: isNight,
                        condition: condition,
                        accent: snapshot.accent.color,
                        animated: !reduceMotion)
                .allowsHitTesting(false)

            HStack(spacing: Space.s2) {
                glyphBadge(size: 32, glyphSize: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.city.uppercased())
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(contentSecondary)
                        .lineLimit(1)
                    Text(snapshot.condition)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(contentPrimary)
                        .lineLimit(1)
                    Text("\(snapshot.windDisplay) · \(snapshot.visibilityMi) mi")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(contentSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.s1)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(snapshot.tempDisplay)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(contentPrimary)
                    if let alert = snapshot.topAlert {
                        HStack(spacing: 3) {
                            Circle().fill(alert.severity.color).frame(width: 5, height: 5)
                            Text(alert.severity.label)
                                .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.30)))
                    } else {
                        Text("Feels \(snapshot.feelsLikeDisplay)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(contentSecondary)
                    }
                }
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
        }
        .frame(minHeight: 64)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.white.opacity(0.06)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
        )
        .shadow(color: Color.black.opacity(isNight ? 0.30 : 0.14), radius: 10, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Weather, \(snapshot.city), \(snapshot.condition), \(snapshot.tempDisplay)"
            + (snapshot.topAlert.map { ", alert \($0.event)" } ?? "")
        )
    }

    // MARK: - Foreground chrome

    private var contentPrimary: Color {
        // Always white-on-sky — the backdrop is deep enough in both schemes.
        .white
    }

    private var contentSecondary: Color {
        Color.white.opacity(0.75)
    }

    private func glyphBadge(size: CGFloat, glyphSize: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(snapshot.accent.color.opacity(0.25))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
                )
            // Bespoke vector glyph (no SF Symbol on any weather surface).
            WeatherIcons.symbolView(for: snapshot.weatherCode, size: glyphSize)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Animated metric tile (wind / visibility / humidity / precip)

/// A live metric tile: the v2 utility glyph carries a CONTINUOUS,
/// characteristic motion (wind sways, the eye breathes, humidity bobs, a
/// precip drop drips) and the whole tile springs on press. Nothing here is
/// static. Motion pauses under Reduce Motion; the press feedback stays.
private struct WeatherMetricTile: View {
    let glyph: WeatherIcons.Utility
    let value: String
    let key: String
    let hazard: Bool
    var reduceMotion: Bool

    @State private var pressed = false

    private let tint = Color(red: 0.81, green: 0.88, blue: 1.0)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            let m = motion(t)
            VStack(spacing: 3) {
                WeatherIcons.utility(glyph, size: 17, tint: tint)
                    .offset(x: m.x, y: m.y)
                    .rotationEffect(.degrees(m.rot))
                    .scaleEffect(m.scale)
                Text(value)
                    .font(.system(size: 13, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Text(key)
                    .font(.system(size: 9.5)).tracking(0.3)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9).padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(hazard ? Brand.warning.opacity(0.30) : Color.white.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.white.opacity(hazard ? 0.40 : 0.18), lineWidth: 0.5)
            )
            .scaleEffect(pressed ? 0.93 : 1)
            .animation(.spring(response: 0.32, dampingFraction: 0.6), value: pressed)
        }
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .onTapGesture { tapPulse() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(key) \(value)")
    }

    /// Per-metric continuous motion: (xOffset, yOffset, rotationDeg, scale).
    private func motion(_ t: Double) -> (x: CGFloat, y: CGFloat, rot: Double, scale: CGFloat) {
        guard !reduceMotion else { return (0, 0, 0, 1) }
        switch glyph {
        case .wind:
            // gust sway: drift right-left with a little lean.
            return (CGFloat(sin(t * 2.1) * 1.8), 0, sin(t * 2.1) * 5, 1)
        case .eye:
            // slow "breathing" pulse, like a blink that never quite closes.
            return (0, 0, 0, CGFloat(1 + 0.07 * sin(t * 1.5)))
        case .humid:
            // droplet bob up/down.
            return (0, CGFloat(sin(t * 1.7) * 1.4), 0, 1)
        case .precip:
            // a falling-drip cadence: ease down, snap back.
            let p = (sin(t * 2.6) * 0.5 + 0.5)
            return (0, CGFloat(p * 2.4 - 1.2), 0, CGFloat(1 + 0.05 * p))
        default:
            return (0, 0, 0, CGFloat(1 + 0.04 * sin(t * 1.6)))
        }
    }

    private func tapPulse() {
        pressed = true
        #if canImport(UIKit)
        if !reduceMotion { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6) }
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { pressed = false }
    }
}

// MARK: - Sky scene

enum SkyCondition {
    case clear
    case cloudy
    case rain
    case thunder
    case snow
    case fog
}

/// Animated sky backdrop. A stack of:
///   • atmosphere gradient (night vs day, tinted by condition)
///   • celestial body (moon + stars, or sun + haze)
///   • drifting clouds (condition-dependent density)
///   • precipitation particles (rain / snow / thunder flashes)
///
/// `animated == false` (Reduce Motion) renders each layer as a single
/// static frame — same composition, zero TimelineView ticks.
private struct SkyBackdrop: View {
    let isNight: Bool
    let condition: SkyCondition
    let accent: Color
    var animated: Bool = true

    var body: some View {
        ZStack {
            atmosphereGradient
            celestialLayer
            cloudLayer
            precipitationLayer
            // Subtle vignette so the top reads sky and the bottom reads horizon.
            LinearGradient(
                colors: [
                    Color.black.opacity(isNight ? 0.0 : 0.0),
                    Color.black.opacity(isNight ? 0.25 : 0.15)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .blendMode(.multiply)
        }
    }

    // MARK: Atmosphere gradient

    private var atmosphereGradient: some View {
        let colors: [Color]
        switch (isNight, condition) {
        case (true, .clear):
            colors = [
                Color(red: 0.04, green: 0.06, blue: 0.20),   // deep navy
                Color(red: 0.10, green: 0.09, blue: 0.32),   // indigo
                Color(red: 0.20, green: 0.12, blue: 0.40)    // plum twilight
            ]
        case (true, .cloudy), (true, .fog):
            colors = [
                Color(red: 0.06, green: 0.08, blue: 0.17),
                Color(red: 0.12, green: 0.14, blue: 0.23),
                Color(red: 0.22, green: 0.22, blue: 0.32)
            ]
        case (true, .rain), (true, .thunder):
            colors = [
                Color(red: 0.03, green: 0.05, blue: 0.13),
                Color(red: 0.08, green: 0.10, blue: 0.22),
                Color(red: 0.15, green: 0.18, blue: 0.35)
            ]
        case (true, .snow):
            colors = [
                Color(red: 0.08, green: 0.12, blue: 0.28),
                Color(red: 0.18, green: 0.22, blue: 0.42),
                Color(red: 0.34, green: 0.38, blue: 0.58)
            ]
        case (false, .clear):
            colors = [
                Color(red: 0.14, green: 0.55, blue: 0.92),   // sky blue
                Color(red: 0.40, green: 0.74, blue: 0.98),
                Color(red: 0.78, green: 0.89, blue: 0.99)    // soft horizon
            ]
        case (false, .cloudy), (false, .fog):
            colors = [
                Color(red: 0.40, green: 0.52, blue: 0.66),
                Color(red: 0.62, green: 0.72, blue: 0.82),
                Color(red: 0.82, green: 0.86, blue: 0.90)
            ]
        case (false, .rain), (false, .thunder):
            colors = [
                Color(red: 0.22, green: 0.30, blue: 0.42),
                Color(red: 0.36, green: 0.46, blue: 0.58),
                Color(red: 0.56, green: 0.64, blue: 0.72)
            ]
        case (false, .snow):
            colors = [
                Color(red: 0.66, green: 0.74, blue: 0.85),
                Color(red: 0.82, green: 0.88, blue: 0.94),
                Color(red: 0.94, green: 0.96, blue: 0.99)
            ]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    // MARK: Celestial layer (moon + stars, or sun + halo)

    @ViewBuilder
    private var celestialLayer: some View {
        if isNight {
            StarsField(density: condition == .clear ? 1.0 : (condition == .cloudy || condition == .fog ? 0.25 : 0.55),
                       animated: animated)
            if condition == .clear || condition == .snow {
                Moon()
            }
        } else {
            if condition == .clear || condition == .snow {
                Sun(accent: accent, animated: animated)
            }
        }
    }

    // MARK: Clouds

    @ViewBuilder
    private var cloudLayer: some View {
        switch condition {
        case .clear:
            DriftingClouds(density: isNight ? 0.16 : 0.22, tint: Color.white.opacity(isNight ? 0.08 : 0.30), animated: animated)
        case .cloudy, .fog:
            DriftingClouds(density: 0.48, tint: Color.white.opacity(isNight ? 0.16 : 0.36), animated: animated)
        case .rain, .thunder:
            DriftingClouds(density: 0.46, tint: Color.white.opacity(isNight ? 0.14 : 0.32), animated: animated)
        case .snow:
            DriftingClouds(density: 0.42, tint: Color.white.opacity(isNight ? 0.18 : 0.38), animated: animated)
        }
    }

    // MARK: Precipitation

    @ViewBuilder
    private var precipitationLayer: some View {
        switch condition {
        case .rain:
            RainStreaks(intensity: 0.85, animated: animated)
        case .thunder:
            ZStack {
                RainStreaks(intensity: 1.0, animated: animated)
                if animated {
                    LightningFlash()
                }
            }
        case .snow:
            SnowField(intensity: 0.8, animated: animated)
        default:
            EmptyView()
        }
    }
}

// MARK: Star field — twinkling points rendered in Canvas.

private struct StarsField: View {
    let density: Double  // 0…1
    var animated: Bool = true

    // Pre-seeded star positions so layout is stable across frames.
    private let stars: [Star] = (0..<70).map { i in
        var rng = SeededRNG(seed: UInt64(0x5EED + i * 17))
        return Star(
            x: rng.next01(),
            y: rng.next01() * 0.72,       // bias upward
            radius: 0.4 + rng.next01() * 1.6,
            phase: rng.next01() * .pi * 2,
            speed: 0.8 + rng.next01() * 1.6
        )
    }

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                frame(t: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            frame(t: 0)
        }
    }

    private func frame(t: TimeInterval) -> some View {
        Canvas { ctx, size in
            let keepCount = Int(Double(stars.count) * density)
            for star in stars.prefix(keepCount) {
                let twinkle = (sin(t * star.speed + star.phase) + 1) / 2     // 0…1
                let alpha = 0.35 + twinkle * 0.65
                let r = star.radius * (0.85 + 0.3 * twinkle)
                let cx = star.x * size.width
                let cy = star.y * size.height
                let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
                // Crisp cross glint on the 3 largest stars for a little magic.
                if r > 1.4 {
                    var cross = Path()
                    cross.move(to: CGPoint(x: cx - r * 3, y: cy))
                    cross.addLine(to: CGPoint(x: cx + r * 3, y: cy))
                    cross.move(to: CGPoint(x: cx, y: cy - r * 3))
                    cross.addLine(to: CGPoint(x: cx, y: cy + r * 3))
                    ctx.stroke(cross, with: .color(.white.opacity(alpha * 0.35)), lineWidth: 0.4)
                }
            }
        }
    }

    private struct Star {
        let x: Double
        let y: Double
        let radius: Double
        let phase: Double
        let speed: Double
    }
}

// MARK: Moon — subtle disc with halo.

private struct Moon: View {
    var body: some View {
        GeometryReader { geo in
            let r: CGFloat = 22
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.18), Color.white.opacity(0.0)],
                            center: .center, startRadius: 0, endRadius: r * 2.8
                        )
                    )
                    .frame(width: r * 5.6, height: r * 5.6)
                    .blur(radius: 6)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.95), Color(red: 0.92, green: 0.93, blue: 0.99)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: r * 2, height: r * 2)
                    .overlay(
                        Circle()
                            .fill(Color.black.opacity(0.08))
                            .frame(width: r * 0.7, height: r * 0.7)
                            .offset(x: 4, y: -3)
                            .blur(radius: 2)
                    )
                    .shadow(color: .white.opacity(0.4), radius: 8)
            }
            .position(x: geo.size.width * 0.82, y: geo.size.height * 0.38)
        }
    }
}

// MARK: Sun — warm disc with breathing halo.

private struct Sun: View {
    let accent: Color
    var animated: Bool = true

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                disc(t: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            disc(t: 0)
        }
    }

    private func disc(t: TimeInterval) -> some View {
        let pulse = 1 + 0.05 * sin(t * 1.6)
        return GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.55),
                                Color(red: 1.0, green: 0.86, blue: 0.45).opacity(0.25),
                                Color.clear
                            ],
                            center: .center, startRadius: 0, endRadius: 90
                        )
                    )
                    .frame(width: 180, height: 180)
                    .blur(radius: 8)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.98, blue: 0.82),
                                Color(red: 1.0, green: 0.84, blue: 0.42)
                            ],
                            center: .center, startRadius: 0, endRadius: 28
                        )
                    )
                    .frame(width: 44 * pulse, height: 44 * pulse)
                    .shadow(color: Color(red: 1.0, green: 0.84, blue: 0.42).opacity(0.55), radius: 14)
            }
            .position(x: geo.size.width * 0.82, y: geo.size.height * 0.38)
        }
    }
}

// MARK: Drifting clouds — soft blobs moving horizontally.

private struct DriftingClouds: View {
    let density: Double
    let tint: Color
    var animated: Bool = true

    private let clouds: [CloudPuff] = (0..<5).map { i in
        var rng = SeededRNG(seed: UInt64(0xC100 + i * 31))
        return CloudPuff(
            y: 0.12 + rng.next01() * 0.46,
            width: 0.24 + rng.next01() * 0.34,
            speed: 0.008 + rng.next01() * 0.012,
            phase: rng.next01(),
            opacity: 0.45 + rng.next01() * 0.28
        )
    }

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                frame(t: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            frame(t: 0)
        }
    }

    private func frame(t: TimeInterval) -> some View {
        let visible = max(1, Int(Double(clouds.count) * density))
        return Canvas { ctx, size in
            for puff in clouds.prefix(visible) {
                let travel = (t * puff.speed + puff.phase).truncatingRemainder(dividingBy: 1.2) - 0.1
                let cx = CGFloat(travel) * size.width
                let cy = CGFloat(puff.y) * size.height
                let w = CGFloat(puff.width) * size.width
                drawCloud(ctx: ctx, center: CGPoint(x: cx, y: cy), width: w, tint: tint.opacity(puff.opacity))
            }
        }
    }

    private func drawCloud(ctx: GraphicsContext, center: CGPoint, width: CGFloat, tint: Color) {
        let h = width * 0.28
        let base = CGRect(x: center.x - width / 2, y: center.y - h / 2, width: width, height: h)
        // 3-lobe blob.
        let r1 = h * 0.9
        let r2 = h * 1.1
        let r3 = h * 0.8
        var path = Path()
        path.addEllipse(in: CGRect(x: base.minX, y: base.midY - r1, width: r1 * 2, height: r1 * 2))
        path.addEllipse(in: CGRect(x: base.midX - r2, y: base.midY - r2 * 1.15, width: r2 * 2, height: r2 * 2))
        path.addEllipse(in: CGRect(x: base.maxX - r3 * 2, y: base.midY - r3, width: r3 * 2, height: r3 * 2))
        ctx.fill(path, with: .color(tint))
    }

    private struct CloudPuff {
        let y: Double
        let width: Double
        let speed: Double
        let phase: Double
        let opacity: Double
    }
}

// MARK: Rain streaks.

private struct RainStreaks: View {
    let intensity: Double
    var animated: Bool = true

    private let drops: [Drop] = (0..<60).map { i in
        var rng = SeededRNG(seed: UInt64(0xDEAD + i * 23))
        return Drop(
            x: rng.next01(),
            len: 8 + rng.next01() * 14,
            speed: 140 + rng.next01() * 120,
            phase: rng.next01()
        )
    }

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 45.0)) { context in
                frame(t: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            frame(t: 0)
        }
    }

    private func frame(t: TimeInterval) -> some View {
        let count = Int(Double(drops.count) * intensity)
        return Canvas { ctx, size in
            for drop in drops.prefix(count) {
                let travel = (t * drop.speed / Double(size.height) + drop.phase).truncatingRemainder(dividingBy: 1.0)
                let y = CGFloat(travel) * size.height
                let x = CGFloat(drop.x) * size.width
                var p = Path()
                p.move(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: x + 2, y: y + drop.len))
                ctx.stroke(p, with: .color(.white.opacity(0.55)), lineWidth: 1.1)
            }
        }
    }

    private struct Drop {
        let x: Double
        let len: Double
        let speed: Double
        let phase: Double
    }
}

// MARK: Snow field.

private struct SnowField: View {
    let intensity: Double
    var animated: Bool = true

    private let flakes: [Flake] = (0..<55).map { i in
        var rng = SeededRNG(seed: UInt64(0xF10A + i * 19))
        return Flake(
            x: rng.next01(),
            size: 1.2 + rng.next01() * 2.4,
            speed: 18 + rng.next01() * 30,
            sway: 4 + rng.next01() * 10,
            phase: rng.next01()
        )
    }

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                frame(t: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            frame(t: 0)
        }
    }

    private func frame(t: TimeInterval) -> some View {
        let count = Int(Double(flakes.count) * intensity)
        return Canvas { ctx, size in
            for flake in flakes.prefix(count) {
                let travel = (t * flake.speed / Double(size.height) + flake.phase).truncatingRemainder(dividingBy: 1.0)
                let y = CGFloat(travel) * size.height
                let sway = sin(t * 1.2 + flake.phase * .pi * 2) * flake.sway
                let x = CGFloat(flake.x) * size.width + CGFloat(sway)
                let r = CGFloat(flake.size)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)),
                    with: .color(.white.opacity(0.85))
                )
            }
        }
    }

    private struct Flake {
        let x: Double
        let size: Double
        let speed: Double
        let sway: Double
        let phase: Double
    }
}

// MARK: Lightning flash — slow deterministic strobe (animated paths only).

private struct LightningFlash: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // Deterministic strobe: fire a flash every 3.2 s, 120 ms wide.
            let cycle = t.truncatingRemainder(dividingBy: 3.2)
            let intensity: Double = cycle < 0.12 ? (1 - cycle / 0.12) : 0
            Rectangle()
                .fill(Color.white.opacity(intensity * 0.5))
                .blendMode(.plusLighter)
        }
    }
}

// MARK: - Tiny seeded RNG so star/cloud layouts are stable.

private struct SeededRNG {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xDEADBEEF : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
    mutating func next01() -> Double {
        Double(next() & 0xFFFFFFFF) / Double(UInt32.max)
    }
}

// MARK: - Previews

/// The Austin example from the v2 HTML, end to end — Tomorrow.io source,
/// weatherCode 1101, a flood-watch alert, the 8h band with a 4 PM storm
/// peak, and the LD-260615 lane-impact segment + ESang suggestion.
private func austinPreviewSnapshot() -> WeatherSnapshot {
    let hourCodes = [1101, 4000, 4001, 4001, 8000, 8000, 4001, 4201]
    let hourTemps = [88, 89, 90, 89, 87, 85, 84, 83]
    let hourPrecip = [18, 20, 30, 39, 50, 44, 40, 61]
    var snap = WeatherSnapshot(
        city: "Austin, TX",
        tempF: 88,
        windMph: 5,
        visibilityMi: 10,
        condition: "Partly cloudy",
        symbol: "cloud.sun.fill",
        nextAlert: nil,
        accent: .watch,
        daily: [
            .init(date: Date(),                                    weekdayLabel: "Today", highF: 91, lowF: 74, symbol: "cloud.bolt.rain", condition: "Storms", precipChance: 0.5),
            .init(date: Date().addingTimeInterval(86400),          weekdayLabel: "Mon",   highF: 77, lowF: 74, symbol: "cloud.bolt.rain", condition: "Storms", precipChance: 0.6),
            .init(date: Date().addingTimeInterval(86400 * 2),      weekdayLabel: "Tue",   highF: 86, lowF: 74, symbol: "cloud.rain.fill", condition: "Rain",   precipChance: 0.4),
            .init(date: Date().addingTimeInterval(86400 * 3),      weekdayLabel: "Wed",   highF: 94, lowF: 74, symbol: "cloud.rain.fill", condition: "Rain",   precipChance: 0.3),
            .init(date: Date().addingTimeInterval(86400 * 4),      weekdayLabel: "Thu",   highF: 97, lowF: 79, symbol: "cloud.bolt.rain", condition: "Storms", precipChance: 0.5),
            .init(date: Date().addingTimeInterval(86400 * 5),      weekdayLabel: "Fri",   highF: 92, lowF: 78, symbol: "cloud.sun.fill",  condition: "Partly", precipChance: nil),
        ],
        feelsLikeF: 99,
        humidityPct: 79,
        windGustMph: 9,
        precipChancePct: 18,
        hourly: (0..<8).map { i in
            .init(date: Date().addingTimeInterval(Double(i) * 3600),
                  tempF: hourTemps[i], symbol: "cloud.sun.fill",
                  precipChancePct: hourPrecip[i], windMph: 5, weatherCode: hourCodes[i])
        }
    )
    snap.weatherCode = 1101
    snap.dataSource = .tomorrowIO
    snap.uvIndex = 7
    snap.observedAt = Date().addingTimeInterval(-120)
    snap.alert = .init(title: "Flood watch", severity: .severe, until: Date().addingTimeInterval(6 * 3600))
    snap.laneImpact = [
        .init(loadId: "LD-260615", mode: .truck,
              riskTier: .severe,
              headline: "+40 min ETA risk",
              peakLeg: .init(label: "I-35", time: "4 PM"),
              drivers: [
                .init(field: "PRECIP", value: "0.4 in/h"),
                .init(field: "CROSSWIND", value: "31 mph"),
                .init(field: "VISIBILITY", value: "2.0 mi")
              ],
              recommendation: .init(
                text: "the cell crosses the I-35 leg head-on at 4 PM",
                action: "Move pickup to 1:30 PM",
                protects: "the Dallas appointment"),
              computedAt: Date().addingTimeInterval(-120),
              route: "Austin → Dallas · I-35",
              pickupTime: Date().addingTimeInterval(2 * 3600),
              etaDelayMin: 40,
              esangSuggestion: nil)
    ]
    return snap
}

#Preview("v2 Collapsed · dashboard card") {
    WeatherCard(snapshot: austinPreviewSnapshot())
        .padding()
        .background(Color(red: 0.08, green: 0.09, blue: 0.12))
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("v2 Expanded · full view") {
    ScrollView {
        WeatherCard(snapshot: austinPreviewSnapshot(), startExpanded: true)
            .padding()
    }
    .background(Color(red: 0.04, green: 0.04, blue: 0.06))
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("v2 Compact · Day · Clear") {
    WeatherCard(
        snapshot: {
            var s = WeatherSnapshot(
                city: "Phoenix, AZ", tempF: 96, windMph: 6, visibilityMi: 10,
                condition: "Sunny", symbol: "sun.max.fill",
                nextAlert: nil, accent: .calm,
                feelsLikeF: 99, humidityPct: 12
            )
            s.weatherCode = 1000
            s.dataSource = .tomorrowIO
            return s
        }(),
        style: .compact
    )
    .padding()
    .background(Theme.light.bgPage)
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
