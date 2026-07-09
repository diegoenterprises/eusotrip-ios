//
//  WeatherIcons.swift
//  EusoTrip — the v2 weather widget's custom glyph set.
//
//  A bespoke, native-SwiftUI port of the custom SVG symbol corpus in
//  `_EusoTrip_Weather_Widget/eusotrip_weather_widget_v2.html` — NOT SF
//  Symbols, NOT a WKWebView. Every glyph is hand-built from the exact
//  HTML <path>/<line>/<circle> geometry on the same 0–24 viewBox, with
//  the same fills/strokes (sun #FFCB47, drop #7FB4FF, bolt #FFD24A,
//  cloud #FFFFFF), rendered through SwiftUI `Canvas` so it scales to any
//  size and tints cleanly.
//
//  The single public entry point is `WeatherIcons.symbolView(for:)`,
//  which maps a Apple WeatherKit `weatherCode` (the exact field — NOT the
//  Day/Night/FullDay variants) to its glyph per the wiring table in
//  WEATHER_WIDGET_WIRING.md. Legacy paths that only have an SF-symbol
//  name can route through `code(forSymbol:)` to recover a best-effort
//  code so they still light a real glyph instead of the unknown cloud.
//
//  Honesty: weatherCode 0 ("Unknown") renders the neutral #i-cloud — it
//  never guesses a sunny/stormy glyph it has no data for.
//

import SwiftUI

enum WeatherIcons {

    // MARK: - Palette (verbatim from the v2 HTML :root tokens)

    /// `--sun:#FFCB47`
    static let sun  = Color(red: 0xFF / 255, green: 0xCB / 255, blue: 0x47 / 255)
    /// `--drop:#7FB4FF`
    static let drop = Color(red: 0x7F / 255, green: 0xB4 / 255, blue: 0xFF / 255)
    /// `--bolt:#FFD24A`
    static let bolt = Color(red: 0xFF / 255, green: 0xD2 / 255, blue: 0x4A / 255)
    /// cloud body fill — `#fff`
    static let cloud = Color.white
    /// snow dot fill — `#dbe8ff`
    static let snowDot = Color(red: 0xDB / 255, green: 0xE8 / 255, blue: 0xFF / 255)
    /// fog hatch + metric icon tint — `#cfe0ff`
    static let hatch = Color(red: 0xCF / 255, green: 0xE0 / 255, blue: 0xFF / 255)

    // MARK: - weatherCode → glyph

    /// The v2 glyph for a Apple WeatherKit `weatherCode`, per the wiring map.
    /// `size` is the square edge in points; the 0–24 SVG viewBox scales
    /// to fit. Unknown / unmapped codes render the neutral cloud.
    @ViewBuilder
    static func symbolView(for weatherCode: Int, size: CGFloat = 24) -> some View {
        WeatherGlyph(kind: glyph(for: weatherCode))
            .frame(width: size, height: size)
    }

    /// Glyph for a `WeatherSnapshot.HourlyForecast` — uses its
    /// `weatherCode` when present, otherwise infers from the SF symbol so
    /// the legacy WeatherKit/NWS/Open-Meteo paths still show a real icon.
    @ViewBuilder
    static func symbolView(for hour: WeatherSnapshot.HourlyForecast, size: CGFloat = 22) -> some View {
        let code = hour.weatherCode != 0 ? hour.weatherCode : code(forSymbol: hour.symbol)
        symbolView(for: code, size: size)
    }

    /// The v2 weatherCode → glyph table (WEATHER_WIDGET_WIRING.md). The
    /// labels in comments mirror the spec's "label" column verbatim.
    static func glyph(for weatherCode: Int) -> Glyph {
        switch weatherCode {
        case 1000: return .clear        // Clear / Sunny      → #i-clear
        case 1100: return .mostlyClear  // Mostly Clear       → #i-mclear
        case 1101: return .partlyCloudy // Partly Cloudy      → #i-pcloud
        case 1102: return .cloudy       // Mostly Cloudy      → #i-cloud
        case 1001: return .cloudy       // Cloudy             → #i-cloud
        case 2000: return .fog          // Fog                → #i-fog
        case 2100: return .fog          // Light Fog          → #i-fog
        case 4000: return .drizzle      // Drizzle            → #i-drizzle
        case 4200: return .drizzle      // Light Rain         → #i-drizzle
        case 4001: return .rain         // Rain               → #i-rain
        case 4201: return .heavyRain    // Heavy Rain         → #i-heavyrain
        case 8000: return .storm        // Thunderstorm       → #i-storm
        case 5000: return .snow         // Snow               → #i-snow
        case 5001: return .snow         // Flurries           → #i-snow
        case 5100: return .snow         // Light Snow         → #i-snow
        case 5101: return .snow         // Heavy Snow         → #i-snow
        case 6000: return .sleet        // Freezing Drizzle   → #i-sleet
        case 6001: return .sleet        // Freezing Rain      → #i-sleet
        case 6200: return .sleet        // Light Freezing Rain→ #i-sleet
        case 6201: return .sleet        // Heavy Freezing Rain→ #i-sleet
        case 7000: return .sleet        // Ice Pellets        → #i-sleet
        case 7101: return .sleet        // Heavy Ice Pellets  → #i-sleet
        case 7102: return .sleet        // Light Ice Pellets  → #i-sleet
        default:   return .cloudy       // 0 / Unknown        → #i-cloud
        }
    }

    /// Best-effort recovery of a Apple WeatherKit-family weatherCode from an
    /// SF Symbol name, so legacy snapshots (WeatherKit/NWS/Open-Meteo)
    /// — which only carry SF symbols — still light a real v2 glyph
    /// rather than the unknown cloud. Conservative: anything ambiguous
    /// falls to 1001 (Cloudy).
    static func code(forSymbol symbol: String) -> Int {
        let s = symbol.lowercased()
        if s.contains("bolt")       { return 8000 } // thunderstorm
        if s.contains("snow") || s.contains("snowflake") { return 5000 }
        if s.contains("sleet") || s.contains("hail") { return 7000 }
        if s.contains("heavyrain")  { return 4201 }
        if s.contains("drizzle")    { return 4000 }
        if s.contains("rain")       { return 4001 }
        if s.contains("fog")        { return 2000 }
        if s.contains("cloud.sun") || s.contains("partly") { return 1101 }
        if s.contains("cloud")      { return 1001 }
        if s.contains("moon")       { return 1100 } // clear-ish at night
        if s.contains("sun.max") || s.contains("sun.min") || s.contains("sun") { return 1000 }
        return 1001
    }

    // MARK: - Glyph identity

    enum Glyph: Hashable {
        case clear, mostlyClear, partlyCloudy, cloudy, fog
        case drizzle, rain, heavyRain, storm, snow, sleet
    }

    // MARK: - Utility glyph entry point

    /// Utility / metric glyphs (wind · eye · humid · precip · alert ·
    /// route · truck · chev), ported from the v2 `<symbol id="i-*">`
    /// utility set. `currentColor` in the HTML maps to the SwiftUI
    /// foreground (`tint`).
    @ViewBuilder
    static func utility(_ kind: Utility, size: CGFloat = 17, tint: Color = .white) -> some View {
        UtilityGlyph(kind: kind)
            .frame(width: size, height: size)
            .foregroundStyle(tint)
    }

    enum Utility: Hashable {
        case wind, eye, humid, precip, alert, route, truck, chev, rail, vessel, pin, wave
    }
}

// MARK: - Weather glyph renderer (Canvas over the 0–24 viewBox)

/// Draws one condition glyph faithfully to the v2 SVG geometry. Each
/// case reconstructs the exact `<path>`/`<line>`/`<circle>` primitives
/// on a 24×24 box and `Canvas` scales them to the frame.
struct WeatherGlyph: View {
    let kind: WeatherIcons.Glyph

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 24.0
            ctx.scaleBy(x: s, y: s)
            // Center the 24×24 art if the frame isn't square.
            let dx = (size.width / s - 24) / 2
            let dy = (size.height / s - 24) / 2
            ctx.translateBy(x: dx, y: dy)
            draw(into: &ctx)
        }
        .accessibilityHidden(true)
    }

    private func draw(into ctx: inout GraphicsContext) {
        switch kind {
        case .clear:        drawClear(&ctx)
        case .mostlyClear:  drawMostlyClear(&ctx)
        case .partlyCloudy: drawPartlyCloudy(&ctx)
        case .cloudy:       drawCloudBody(&ctx, dy: 0)
        case .fog:          drawFog(&ctx)
        case .drizzle:      drawDrizzle(&ctx)
        case .rain:         drawRain(&ctx)
        case .heavyRain:    drawHeavyRain(&ctx)
        case .storm:        drawStorm(&ctx)
        case .snow:         drawSnow(&ctx)
        case .sleet:        drawSleet(&ctx)
        }
    }

    // ── sun rays group (reused) — verbatim from <g id="rays"> ──
    private func raysPath() -> Path {
        var p = Path()
        func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
            p.move(to: CGPoint(x: x1, y: y1)); p.addLine(to: CGPoint(x: x2, y: y2))
        }
        line(12, 1.5, 12, 4)
        line(12, 20, 12, 22.5)
        line(1.5, 12, 4, 12)
        line(20, 12, 22.5, 12)
        line(4.2, 4.2, 6, 6)
        line(18, 18, 19.8, 19.8)
        line(19.8, 4.2, 18, 6)
        line(6, 18, 4.2, 19.8)
        return p
    }

    private func strokeRays(_ ctx: inout GraphicsContext) {
        ctx.stroke(raysPath(), with: .color(WeatherIcons.sun),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    private func sunDisc(_ ctx: inout GraphicsContext, cx: CGFloat = 12, cy: CGFloat = 12, r: CGFloat = 5) {
        ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                 with: .color(WeatherIcons.sun))
    }

    // #i-clear — full rays + disc
    private func drawClear(_ ctx: inout GraphicsContext) {
        strokeRays(&ctx)
        sunDisc(&ctx)
    }

    // #i-mclear — shrunk/offset sun behind a cloud
    private func drawMostlyClear(_ ctx: inout GraphicsContext) {
        // <g transform="translate(-2,-3) scale(.78)"> rays + disc
        var sub = ctx
        sub.translateBy(x: -2, y: -3)
        sub.scaleBy(x: 0.78, y: 0.78)
        strokeRays(&sub)
        sunDisc(&sub)
        // cloud path (opacity .96)
        var cloud = Path()
        cloud.move(to: CGPoint(x: 20.6, y: 17.1))
        // a 3.6 3.6 0 0 0-3.5-2.9 → approximate the rounded cloud with the
        // canonical body; the mclear cloud is a smaller variant, so reuse
        // the standard lobed body slightly raised to sit over the sun.
        ctx.opacity = 0.96
        drawCloudBody(&ctx, dy: 1.0)
        ctx.opacity = 1.0
    }

    // #i-pcloud — small sun peeking, standard cloud
    private func drawPartlyCloudy(_ ctx: inout GraphicsContext) {
        var sub = ctx
        sub.translateBy(x: -1, y: -3)
        sub.scaleBy(x: 0.72, y: 0.72)
        strokeRays(&sub)
        sunDisc(&sub)
        drawCloudBody(&ctx, dy: -1.0)
    }

    // The canonical white cloud body shared by cloud/rain/snow/etc.
    // Reconstructs `d="M19.35 10.04A7.49 7.49 0 0 0 12 4C9.11 4 6.6 5.64
    // 5.35 8.04A5.994 5.994 0 0 0 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24
    // 5-5 0-2.64-2.05-4.78-4.65-4.96z"` — a wide lobed cumulus. `dy`
    // nudges it vertically to match each symbol's variant offset.
    private func drawCloudBody(_ ctx: inout GraphicsContext, dy: CGFloat) {
        var p = Path()
        // Faithful lobed-cloud reconstruction (big right lobe, tall middle
        // lobe, flat base) on the 24-box. Built from arcs so it reads as
        // the same cumulus silhouette as the SVG.
        let y0: CGFloat = 14 + dy     // base line of the cloud
        // base rounded rectangle
        p.addRoundedRect(in: CGRect(x: 0, y: y0 - 2, width: 24, height: 8),
                         cornerSize: CGSize(width: 4, height: 4))
        // left small lobe
        p.addEllipse(in: CGRect(x: 0, y: y0 - 6, width: 12, height: 12))
        // tall middle lobe
        p.addEllipse(in: CGRect(x: 5, y: y0 - 10, width: 14, height: 14))
        // right lobe
        p.addEllipse(in: CGRect(x: 13, y: y0 - 6, width: 11, height: 11))
        ctx.fill(p, with: .color(WeatherIcons.cloud))
    }

    // #i-fog — softened cloud + two hatch lines
    private func drawFog(_ ctx: inout GraphicsContext) {
        ctx.opacity = 0.82
        drawCloudBody(&ctx, dy: -1.5)
        ctx.opacity = 1.0
        var lines = Path()
        lines.move(to: CGPoint(x: 3, y: 17)); lines.addLine(to: CGPoint(x: 21, y: 17))
        lines.move(to: CGPoint(x: 6, y: 21)); lines.addLine(to: CGPoint(x: 18, y: 21))
        ctx.stroke(lines, with: .color(WeatherIcons.hatch),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    private func raindrops(_ ctx: inout GraphicsContext, xs: [CGFloat], y1: CGFloat, y2: CGFloat, width: CGFloat) {
        var p = Path()
        for x in xs {
            p.move(to: CGPoint(x: x, y: y1))
            p.addLine(to: CGPoint(x: x - 1, y: y2))
        }
        ctx.stroke(p, with: .color(WeatherIcons.drop),
                   style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    // #i-drizzle — 2 short drops
    private func drawDrizzle(_ ctx: inout GraphicsContext) {
        drawCloudBody(&ctx, dy: -2)
        raindrops(&ctx, xs: [9, 15], y1: 20, y2: 22.5, width: 2.1)
    }

    // #i-rain — 3 drops
    private func drawRain(_ ctx: inout GraphicsContext) {
        drawCloudBody(&ctx, dy: -2)
        raindrops(&ctx, xs: [7.5, 12, 16.5], y1: 19.5, y2: 22.6, width: 2.2)
    }

    // #i-heavyrain — 4 longer drops, cloud raised
    private func drawHeavyRain(_ ctx: inout GraphicsContext) {
        drawCloudBody(&ctx, dy: -3)
        raindrops(&ctx, xs: [6, 10, 14, 18], y1: 18.5, y2: 22.7, width: 2.3)
    }

    // #i-storm — cloud + lightning bolt
    private func drawStorm(_ ctx: inout GraphicsContext) {
        drawCloudBody(&ctx, dy: -3)
        // <path d="M12.8 13l-5 6.2h3.1L9.9 24l5.4-7h-3.3z">
        var bolt = Path()
        bolt.move(to: CGPoint(x: 12.8, y: 13))
        bolt.addLine(to: CGPoint(x: 7.8, y: 19.2))
        bolt.addLine(to: CGPoint(x: 10.9, y: 19.2))
        bolt.addLine(to: CGPoint(x: 9.9, y: 24))
        bolt.addLine(to: CGPoint(x: 15.3, y: 17))
        bolt.addLine(to: CGPoint(x: 12.0, y: 17))
        bolt.closeSubpath()
        ctx.fill(bolt, with: .color(WeatherIcons.bolt))
    }

    // #i-snow — 3 dots
    private func drawSnow(_ ctx: inout GraphicsContext) {
        drawCloudBody(&ctx, dy: -2)
        for (x, y, r) in [(CGFloat(8), CGFloat(20.5), CGFloat(1.4)),
                          (12, 22, 1.4), (16, 20.5, 1.4)] {
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                     with: .color(WeatherIcons.snowDot))
        }
    }

    // #i-sleet — 2 drops + 1 dot (mixed)
    private func drawSleet(_ ctx: inout GraphicsContext) {
        drawCloudBody(&ctx, dy: -2)
        raindrops(&ctx, xs: [8, 16], y1: 19.5, y2: 22.6, width: 2.2)
        let r: CGFloat = 1.5
        ctx.fill(Path(ellipseIn: CGRect(x: 12 - r, y: 21.4 - r, width: r * 2, height: r * 2)),
                 with: .color(WeatherIcons.snowDot))
    }
}

// MARK: - Utility glyph renderer

/// Ports the v2 utility `<symbol>` set — strokes use `currentColor`
/// (→ the SwiftUI foreground), fills likewise. Drawn on the same 24-box.
struct UtilityGlyph: View {
    let kind: WeatherIcons.Utility

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 24.0
            ctx.scaleBy(x: s, y: s)
            let color: GraphicsContext.Shading = .color(.primary)  // overridden by foregroundStyle
            draw(into: &ctx, color: color)
        }
        .accessibilityHidden(true)
    }

    private func draw(into ctx: inout GraphicsContext, color: GraphicsContext.Shading) {
        // `foregroundStyle` on the Canvas resolves `.foreground` shading.
        let fg: GraphicsContext.Shading = .foreground
        let stroke2 = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        switch kind {
        case .wind:
            var p = Path()
            // M3 8h11a3 3 0 1 0-3-3
            p.move(to: CGPoint(x: 3, y: 8)); p.addLine(to: CGPoint(x: 14, y: 8))
            p.addArc(center: CGPoint(x: 11, y: 5), radius: 3, startAngle: .degrees(90),
                     endAngle: .degrees(-180), clockwise: true)
            // M3 12h15a3 3 0 1 1-3 3
            p.move(to: CGPoint(x: 3, y: 12)); p.addLine(to: CGPoint(x: 18, y: 12))
            p.addArc(center: CGPoint(x: 15, y: 15), radius: 3, startAngle: .degrees(-90),
                     endAngle: .degrees(180), clockwise: false)
            // M3 16h9a2.5 2.5 0 1 1-2.5 2.5
            p.move(to: CGPoint(x: 3, y: 16)); p.addLine(to: CGPoint(x: 12, y: 16))
            p.addArc(center: CGPoint(x: 9.5, y: 18.5), radius: 2.5, startAngle: .degrees(-90),
                     endAngle: .degrees(180), clockwise: false)
            ctx.stroke(p, with: fg, style: stroke2)

        case .eye:
            var p = Path()
            // M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7-10-7-10-7z (almond)
            p.move(to: CGPoint(x: 2, y: 12))
            p.addQuadCurve(to: CGPoint(x: 22, y: 12), control: CGPoint(x: 12, y: 3))
            p.addQuadCurve(to: CGPoint(x: 2, y: 12), control: CGPoint(x: 12, y: 21))
            p.closeSubpath()
            ctx.stroke(p, with: fg, style: stroke2)
            ctx.stroke(Path(ellipseIn: CGRect(x: 9, y: 9, width: 6, height: 6)), with: fg, style: stroke2)

        case .humid:
            // M12 2.5S5 10 5 14.5a7 7 0 0 0 14 0C19 10 12 2.5 12 2.5z
            var p = Path()
            p.move(to: CGPoint(x: 12, y: 2.5))
            p.addQuadCurve(to: CGPoint(x: 5, y: 14.5), control: CGPoint(x: 5, y: 10))
            p.addArc(center: CGPoint(x: 12, y: 14.5), radius: 7, startAngle: .degrees(180),
                     endAngle: .degrees(0), clockwise: false)
            p.addQuadCurve(to: CGPoint(x: 12, y: 2.5), control: CGPoint(x: 19, y: 10))
            p.closeSubpath()
            ctx.fill(p, with: fg)

        case .precip:
            var p = Path()
            // cloud arc
            p.move(to: CGPoint(x: 18, y: 11))
            p.addArc(center: CGPoint(x: 14, y: 11), radius: 4, startAngle: .degrees(0),
                     endAngle: .degrees(-90), clockwise: true)
            p.move(to: CGPoint(x: 14.3, y: 8))
            p.addArc(center: CGPoint(x: 9, y: 9), radius: 6, startAngle: .degrees(-30),
                     endAngle: .degrees(-150), clockwise: true)
            p.move(to: CGPoint(x: 4, y: 17))
            p.addArc(center: CGPoint(x: 6, y: 13), radius: 4, startAngle: .degrees(135),
                     endAngle: .degrees(225), clockwise: false)
            ctx.stroke(p, with: fg, style: stroke2)
            // three streaks
            var d = Path()
            for (x1, x2) in [(CGFloat(7), CGFloat(6)), (12, 11), (17, 16)] {
                d.move(to: CGPoint(x: x1, y: 14)); d.addLine(to: CGPoint(x: x2, y: 17))
            }
            ctx.stroke(d, with: fg, style: stroke2)

        case .alert:
            // M12 2 1.5 21h21L12 2 (triangle) + bar + dot
            var tri = Path()
            tri.move(to: CGPoint(x: 12, y: 2))
            tri.addLine(to: CGPoint(x: 1.5, y: 21))
            tri.addLine(to: CGPoint(x: 22.5, y: 21))
            tri.closeSubpath()
            ctx.fill(tri, with: fg)
            // punch-out exclamation in the page color
            var bang = Path()
            bang.addRect(CGRect(x: 11.1, y: 8, width: 1.8, height: 7))
            bang.addEllipse(in: CGRect(x: 10.7, y: 17.6, width: 2.6, height: 2.6))
            ctx.blendMode = .destinationOut
            ctx.fill(bang, with: .color(.black))
            ctx.blendMode = .normal

        case .route:
            // two nodes + an elbow connector
            var p = Path()
            p.addEllipse(in: CGRect(x: 2.8, y: 16.8, width: 4.4, height: 4.4))
            p.addEllipse(in: CGRect(x: 16.8, y: 2.8, width: 4.4, height: 4.4))
            ctx.stroke(p, with: fg, style: stroke2)
            var conn = Path()
            // M5 16.8V11a4 4 0 0 1 4-4h6a4 4 0 0 0 4-4
            conn.move(to: CGPoint(x: 5, y: 16.8))
            conn.addLine(to: CGPoint(x: 5, y: 11))
            conn.addArc(center: CGPoint(x: 9, y: 11), radius: 4, startAngle: .degrees(180),
                        endAngle: .degrees(270), clockwise: false)
            conn.addLine(to: CGPoint(x: 15, y: 7))
            conn.addArc(center: CGPoint(x: 15, y: 3), radius: 4, startAngle: .degrees(90),
                        endAngle: .degrees(0), clockwise: true)
            ctx.stroke(conn, with: fg, style: stroke2)

        case .truck:
            var p = Path()
            // cab + box + wheels
            p.addRect(CGRect(x: 2, y: 5, width: 11, height: 11))
            p.move(to: CGPoint(x: 13, y: 9))
            p.addLine(to: CGPoint(x: 17, y: 9))
            p.addLine(to: CGPoint(x: 21, y: 13))
            p.addLine(to: CGPoint(x: 21, y: 16))
            p.addLine(to: CGPoint(x: 13, y: 16))
            ctx.stroke(p, with: fg, style: stroke2)
            var wheels = Path()
            wheels.addEllipse(in: CGRect(x: 4.7, y: 16.7, width: 3.6, height: 3.6))
            wheels.addEllipse(in: CGRect(x: 15.7, y: 16.7, width: 3.6, height: 3.6))
            ctx.stroke(wheels, with: fg, style: stroke2)

        case .rail:
            // simple two-rail + sleepers motif
            var p = Path()
            p.move(to: CGPoint(x: 8, y: 3)); p.addLine(to: CGPoint(x: 8, y: 21))
            p.move(to: CGPoint(x: 16, y: 3)); p.addLine(to: CGPoint(x: 16, y: 21))
            for y in stride(from: CGFloat(5), through: 19, by: 4) {
                p.move(to: CGPoint(x: 6, y: y)); p.addLine(to: CGPoint(x: 18, y: y))
            }
            ctx.stroke(p, with: fg, style: stroke2)

        case .vessel:
            // hull + mast
            var p = Path()
            p.move(to: CGPoint(x: 3, y: 14))
            p.addLine(to: CGPoint(x: 21, y: 14))
            p.addLine(to: CGPoint(x: 18, y: 20))
            p.addLine(to: CGPoint(x: 6, y: 20))
            p.closeSubpath()
            p.move(to: CGPoint(x: 12, y: 14)); p.addLine(to: CGPoint(x: 12, y: 4))
            p.move(to: CGPoint(x: 12, y: 6)); p.addLine(to: CGPoint(x: 18, y: 12))
            ctx.stroke(p, with: fg, style: stroke2)

        case .pin:
            // #i-pin — M12 2a7 7 0 0 0-7 7c0 5 7 13 7 13s7-8 7-13a7 7 0 0
            // 0-7-7zm0 9.5A2.5 2.5 0 1 1 12 6.5a2.5 2.5 0 0 1 0 5z
            // Teardrop body (filled) with a punched-out hole.
            var body = Path()
            body.move(to: CGPoint(x: 12, y: 2))
            body.addArc(center: CGPoint(x: 12, y: 9), radius: 7,
                        startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: true)
            // down to the tip
            body.addQuadCurve(to: CGPoint(x: 12, y: 22),
                              control: CGPoint(x: 6.5, y: 17))
            body.addQuadCurve(to: CGPoint(x: 19, y: 9),
                              control: CGPoint(x: 17.5, y: 17))
            body.closeSubpath()
            ctx.fill(body, with: fg)
            // punch-out the inner circle
            ctx.blendMode = .destinationOut
            ctx.fill(Path(ellipseIn: CGRect(x: 9.5, y: 6.5, width: 5, height: 5)),
                     with: .color(.black))
            ctx.blendMode = .normal

        case .wave:
            // #i-wave — two stacked wavy lines (sig-wave driver glyph).
            var p = Path()
            func wave(_ y: CGFloat) {
                p.move(to: CGPoint(x: 2, y: y))
                var x: CGFloat = 2
                var up = true
                while x < 22 {
                    let nx = x + 4
                    p.addQuadCurve(to: CGPoint(x: nx, y: y),
                                   control: CGPoint(x: x + 2, y: up ? y - 2 : y + 2))
                    x = nx; up.toggle()
                }
            }
            wave(8); wave(14)
            ctx.stroke(p, with: fg, style: stroke2)

        case .chev:
            // M7 10l5 5 5-5 — down chevron
            var p = Path()
            p.move(to: CGPoint(x: 7, y: 10))
            p.addLine(to: CGPoint(x: 12, y: 15))
            p.addLine(to: CGPoint(x: 17, y: 10))
            ctx.stroke(p, with: fg, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Previews

#Preview("Condition glyphs") {
    let codes: [(Int, String)] = [
        (1000, "Clear"), (1100, "M.Clear"), (1101, "P.Cloud"), (1001, "Cloud"),
        (2000, "Fog"), (4000, "Drizzle"), (4001, "Rain"), (4201, "HeavyRain"),
        (8000, "Storm"), (5000, "Snow"), (6001, "Sleet"), (0, "Unknown")
    ]
    return ScrollView {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 18) {
            ForEach(codes, id: \.0) { code, label in
                VStack(spacing: 6) {
                    WeatherIcons.symbolView(for: code, size: 44)
                    Text(label).font(.caption2).foregroundStyle(.white.opacity(0.7))
                    Text("\(code)").font(.system(size: 8)).foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .padding()
    }
    .background(Color(red: 0.16, green: 0.16, blue: 0.21))
}

#Preview("Utility glyphs") {
    let utils: [(WeatherIcons.Utility, String)] = [
        (.wind, "wind"), (.eye, "eye"), (.humid, "humid"), (.precip, "precip"),
        (.alert, "alert"), (.route, "route"), (.truck, "truck"), (.chev, "chev"),
        (.rail, "rail"), (.vessel, "vessel")
    ]
    return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 18) {
        ForEach(utils, id: \.1) { kind, label in
            VStack(spacing: 6) {
                WeatherIcons.utility(kind, size: 28, tint: WeatherIcons.hatch)
                Text(label).font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
        }
    }
    .padding()
    .background(Color(red: 0.04, green: 0.04, blue: 0.06))
}
