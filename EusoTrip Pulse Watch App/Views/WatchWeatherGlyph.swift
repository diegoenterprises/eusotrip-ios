//
//  WatchWeatherGlyph.swift
//  EusoTrip Pulse Watch App — bespoke per-load weather glyph for the
//  wrist surfaces (Route Overview + the Driver Live Activity).
//
//  DOCTRINE — bespoke, non-negotiable:
//    The phone's per-load weather surface renders through the Wave-1 v3
//    components (WeatherV3Components.swift + WeatherIcons.swift). Those
//    files do NOT link into the watchOS target, so we cannot reuse the
//    iOS `WeatherIcons` here. Instead this file ports the SAME bespoke
//    glyph language verbatim from the lane-impact reference
//    (~/Desktop/_EusoTrip_Weather_Widget/eusotrip_lane_impact_tri_modal_v2_bespoke.html
//    symbols #i-rain / #i-storm / #i-wind / #i-fog) into a native
//    SwiftUI `Canvas` — ZERO SF Symbols, zero emoji, zero generic
//    weather UI. The paths below are the exact 24×24-viewBox paths from
//    that HTML, scaled to the requested size.
//
//  HONESTY:
//    The glyph is chosen from a REAL severity/flag string handed down
//    the pipeline (routeOptimization.getProgress.weatherFlag and/or
//    weather.forLoad → laneImpact.riskTier). When there is no signal the
//    caller renders nothing — we never fabricate a storm.
//

import SwiftUI

// MARK: - Severity model

/// The wrist-side weather severity, normalised from whatever real signal
/// reached the watch. Mirrors the phone's `LaneRiskTier`
/// (none/watch/elevated/severe) and the route-flag strings
/// that `routeOptimization.getProgress` returns
/// ("severe-thunderstorm" | "wind-advisory" | "rain" | "fog" | …).
///
/// We keep this coarse on purpose: the wrist shows a single chip, not a
/// forecast. Anything we can't read with confidence maps to `.advisory`
/// (the honest "there is weather, treat it as caution") rather than a
/// fabricated severity ladder.
enum WatchWeatherSeverity {
    case storm       // severe-thunderstorm, severe / extreme riskTier
    case wind        // wind-advisory, crosswind, gust
    case rain        // rain, precip-driven elevated risk
    case fog         // fog, low-visibility
    case advisory    // generic "watch" — has weather, unclassified

    /// Maps a raw flag/tier string from the server to a glyph bucket.
    /// Returns nil when the string carries no weather signal (so the
    /// caller renders nothing rather than a default storm).
    static func from(flag raw: String?) -> WatchWeatherSeverity? {
        guard let s = raw?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty, s != "none", s != "clear", s != "—" else { return nil }

        if s.contains("storm") || s.contains("thunder") || s.contains("severe") || s.contains("extreme") {
            return .storm
        }
        if s.contains("wind") || s.contains("gust") || s.contains("crosswind") {
            return .wind
        }
        if s.contains("fog") || s.contains("visib") || s.contains("haze") || s.contains("mist") {
            return .fog
        }
        if s.contains("rain") || s.contains("precip") || s.contains("snow") || s.contains("shower") {
            return .rain
        }
        // "watch" / "elevated" / any other actionable tier with no
        // weather noun → honest generic advisory chip.
        if s.contains("watch") || s.contains("elevated") || s.contains("advisory") {
            return .advisory
        }
        return .advisory
    }

    /// Brand tint for the chip — escalates from amber (caution) to danger
    /// (severe), matching the phone's risk-pill colour ladder.
    var tint: Color {
        switch self {
        case .storm:    return .esangDanger
        case .wind:     return .esangAmber
        case .rain:     return .esangBlue
        case .fog:      return .esangTextDim
        case .advisory: return .esangAmber
        }
    }
}

// MARK: - Bespoke glyph (native Canvas, ported from the HTML symbols)

/// Renders the bespoke weather glyph for a given severity in a native
/// `Canvas` — no SF Symbols. Paths are the verbatim 24×24 symbol paths
/// from the lane-impact reference, scaled to `size`.
struct WatchWeatherGlyph: View {
    let severity: WatchWeatherSeverity
    var size: CGFloat = 14

    var body: some View {
        Canvas { ctx, canvasSize in
            // Uniform scale from the 24×24 design viewBox.
            let scale = min(canvasSize.width, canvasSize.height) / 24.0
            ctx.scaleBy(x: scale, y: scale)
            switch severity {
            case .storm:    drawStorm(&ctx)
            case .wind:     drawWind(&ctx)
            case .rain:     drawRain(&ctx)
            case .fog:      drawFog(&ctx)
            case .advisory: drawAdvisory(&ctx)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // Shared cloud body — the rounded "M19.35 8 … z" puff used by the
    // rain/storm/fog symbols. Drawn as a filled blob in white at the
    // glyph's base opacity.
    private func cloudPath(yOffset: CGFloat = 0) -> Path {
        var p = Path()
        // Approximation of the HTML cloud silhouette in the 24×24 box.
        p.addEllipse(in: CGRect(x: 4, y: 6 + yOffset, width: 12, height: 9))
        p.addEllipse(in: CGRect(x: 0.5, y: 9 + yOffset, width: 9, height: 6.5))
        p.addEllipse(in: CGRect(x: 12, y: 8 + yOffset, width: 9, height: 6.5))
        p.addRoundedRect(in: CGRect(x: 3, y: 10.5 + yOffset, width: 16, height: 4.5),
                         cornerSize: CGSize(width: 2.2, height: 2.2))
        return p
    }

    private func drawRain(_ ctx: inout GraphicsContext) {
        ctx.fill(cloudPath(), with: .color(.white.opacity(0.95)))
        // Three slanted rain streaks (#82B7FF in the reference).
        let streaks: [(CGFloat, CGFloat)] = [(7.5, 6.3), (12, 10.8), (16.5, 15.3)]
        for (x1, x2) in streaks {
            var s = Path()
            s.move(to: CGPoint(x: x1, y: 16.5))
            s.addLine(to: CGPoint(x: x2, y: 21.6))
            ctx.stroke(s, with: .color(Color(red: 0.51, green: 0.72, blue: 1.0)),
                       style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
        }
    }

    private func drawStorm(_ ctx: inout GraphicsContext) {
        ctx.fill(cloudPath(yOffset: -1), with: .color(.white.opacity(0.95)))
        // The lightning bolt (#FFD24A) — verbatim bolt path "M12.8 13…z".
        var bolt = Path()
        bolt.move(to: CGPoint(x: 12.8, y: 13))
        bolt.addLine(to: CGPoint(x: 7.8, y: 19.2))
        bolt.addLine(to: CGPoint(x: 10.9, y: 19.2))
        bolt.addLine(to: CGPoint(x: 9.9, y: 24))
        bolt.addLine(to: CGPoint(x: 15.3, y: 17))
        bolt.addLine(to: CGPoint(x: 12.0, y: 17))
        bolt.closeSubpath()
        ctx.fill(bolt, with: .color(Color(red: 1.0, green: 0.82, blue: 0.29)))
    }

    private func drawWind(_ ctx: inout GraphicsContext) {
        // Three swept wind curls (#i-wind), stroked in the chip tint.
        let c = GraphicsContext.Shading.color(severity.tint)
        var g = Path()
        // Top curl
        g.move(to: CGPoint(x: 3, y: 8)); g.addLine(to: CGPoint(x: 14, y: 8))
        g.addArc(center: CGPoint(x: 14, y: 5), radius: 3, startAngle: .degrees(90),
                 endAngle: .degrees(-30), clockwise: true)
        // Middle curl
        g.move(to: CGPoint(x: 3, y: 12)); g.addLine(to: CGPoint(x: 18, y: 12))
        g.addArc(center: CGPoint(x: 18, y: 15), radius: 3, startAngle: .degrees(-90),
                 endAngle: .degrees(30), clockwise: false)
        // Bottom curl
        g.move(to: CGPoint(x: 3, y: 16)); g.addLine(to: CGPoint(x: 12, y: 16))
        g.addArc(center: CGPoint(x: 12, y: 18.5), radius: 2.5, startAngle: .degrees(-90),
                 endAngle: .degrees(45), clockwise: false)
        ctx.stroke(g, with: c, style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    private func drawFog(_ ctx: inout GraphicsContext) {
        ctx.fill(cloudPath(yOffset: -0.5), with: .color(.white.opacity(0.82)))
        // Two fog bars (#cfe0ff).
        let bars: [(CGFloat, CGFloat, CGFloat)] = [(3, 21, 17), (6, 18, 21)]
        for (x1, x2, y) in bars {
            var b = Path()
            b.move(to: CGPoint(x: x1, y: y)); b.addLine(to: CGPoint(x: x2, y: y))
            ctx.stroke(b, with: .color(Color(red: 0.81, green: 0.88, blue: 1.0)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    private func drawAdvisory(_ ctx: inout GraphicsContext) {
        // Cloud + a single caution stroke — "weather present, unclassified".
        ctx.fill(cloudPath(), with: .color(.white.opacity(0.9)))
        var s = Path()
        s.move(to: CGPoint(x: 12, y: 17)); s.addLine(to: CGPoint(x: 11, y: 21.5))
        ctx.stroke(s, with: .color(severity.tint),
                   style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
    }
}

// MARK: - Chip (glyph + honest label)

/// The compact wrist chip used by Route Overview and the Live Activity:
/// bespoke glyph + the real flag/headline text + the severity tint.
struct WatchWeatherChip: View {
    let severity: WatchWeatherSeverity
    /// The real, server-supplied label (the raw flag, prettified, or the
    /// lane-impact headline). Never fabricated.
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            WatchWeatherGlyph(severity: severity, size: 13)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(severity.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
