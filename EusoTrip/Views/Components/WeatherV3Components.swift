//
//  WeatherV3Components.swift
//  EusoTrip — the v3 bespoke weather signature components.
//
//  A 1:1 native-SwiftUI port (Canvas / Path / ZStack — NOT WKWebView,
//  NOT a chart library, NOT an icon pack) of the five "seen by no other"
//  signatures defined in WEATHER_WIDGET_WIRING.md §D.1 and drawn in
//  `eusotrip_weather_widget_v3_bespoke.html` +
//  `eusotrip_lane_impact_tri_modal_v2_bespoke.html`:
//
//    1. SkyStageHero       — iridescent aurora ribbon + bespoke clouds +
//                            dashed route motif behind the readout.
//    2. HourlyRibbon       — temp polyline over a precip gradient area,
//                            peak node + danger column.
//    3. RouteCellDiagram   — the operational showpiece: a curved route
//                            with the weather hazard drawn crossing the
//                            peak leg. Tri-modal (truck / rail / vessel).
//    4. DayRangeBar        — a thin hi→lo gradient bar per day chip.
//    5. (Detail signatures live inline in WeatherCard — superscript
//       degree, monospacedDigit, pin glyph, ESang conic orb, one
//       iridescent hairline.)
//
//  Every value is bound to a real WeatherSnapshot field. When a field is
//  nil/empty the element renders its honest empty state or collapses —
//  the mockup numbers (88°, +40 min, AUSTIN, LD-260615) are DESIGN
//  placeholders, never shipped. 0 STUBS · 0 MOCK · 0 PLACEHOLDERS.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - v3 iridescent palette (verbatim from the v3 HTML :root tokens)

/// The v3 mockup uses its own bluemagenta stops (`--brandA #5B6CFF`,
/// `--brandB #B14BFF`, `--brandC #FF55A6`) that are warmer/brighter than
/// the app's `Brand.blue/magenta`. The weather screen is its own
/// archetype, so it carries these tokens locally for a faithful aurora —
/// the brand identity (eyebrow, orb, hero rim) stays constant; mode is
/// the accent only.
enum WeatherV3 {
    /// `--brandA:#5B6CFF`
    static let auroraA = Color(red: 0x5B / 255, green: 0x6C / 255, blue: 0xFF / 255)
    /// `--brandB:#B14BFF`
    static let auroraB = Color(red: 0xB1 / 255, green: 0x4B / 255, blue: 0xFF / 255)
    /// `--brandC:#FF55A6`
    static let auroraC = Color(red: 0xFF / 255, green: 0x55 / 255, blue: 0xA6 / 255)
    /// `--danger:#FF5A4D`
    static let danger  = Color(red: 0xFF / 255, green: 0x5A / 255, blue: 0x4D / 255)
    /// `--sun:#FFCB47`
    static let sun     = Color(red: 0xFF / 255, green: 0xCB / 255, blue: 0x47 / 255)
    /// `--drop:#82B7FF`
    static let drop    = Color(red: 0x82 / 255, green: 0xB7 / 255, blue: 0xFF / 255)
    /// temp-polyline warm end — `#FF7E6B`
    static let tempWarm = Color(red: 0xFF / 255, green: 0x7E / 255, blue: 0x6B / 255)
    /// route-origin node — `#cdbcff`
    static let nodeOrigin = Color(red: 0xCD / 255, green: 0xBC / 255, blue: 0xFF / 255)
    /// route-dest node — `--brandC`
    static let nodeDest = auroraC

    /// Dark-glass card ink for the expanded view's ON-PAGE sections (day
    /// chips + lane-impact panel). The weather widget is a "dark sky"
    /// surface by design — the hero stage is always dark in both color
    /// schemes — so its sibling cards stay dark too (matching iOS Weather)
    /// instead of using the adaptive `palette.bgCard`, which went white in
    /// light mode and left the hardcoded-white chip text invisible. Fixed,
    /// non-adaptive: readable white text in BOTH light and dark mode.
    static let cardInk = Color(red: 0x18 / 255, green: 0x19 / 255, blue: 0x2C / 255)
    /// Slightly lighter ink for a nested chip/tile on top of `cardInk`.
    static let cardInkRaised = Color(red: 0x20 / 255, green: 0x22 / 255, blue: 0x38 / 255)

    /// mode accents (tri-modal HTML `--truck/--rail/--vessel`)
    static let truck  = auroraA
    static let rail   = Color(red: 0x9A / 255, green: 0xA8 / 255, blue: 0xBE / 255)
    static let vessel = Color(red: 0x41 / 255, green: 0xD6 / 255, blue: 0xE3 / 255)

    /// `url(#aurora)` — the brand blue→magenta→pink LinearGradient.
    static let auroraGradient = LinearGradient(
        colors: [auroraA, auroraB, auroraC],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// `url(#templine)` — `#FFCB47 → #FF7E6B`.
    static let tempLine = LinearGradient(
        colors: [sun, tempWarm], startPoint: .leading, endPoint: .trailing
    )
}

// MARK: - 1 · SKY STAGE HERO

/// The brand moment — a layered stage drawn BEHIND the readout: an
/// iridescent aurora ribbon (blurred wide stroke + thin bright stroke),
/// two soft bespoke cloud forms (low-opacity blurred ellipses), and a
/// faint dashed route motif with origin/destination nodes embedded in
/// the sky. Mood is driven by `weatherCode`: clear widens the aurora and
/// lights a sun halo; storm darkens the stage and densifies the cloud.
/// Not a flat gradient.
struct SkyStageHero: View {
    /// Apple WeatherKit weatherCode — drives the mood (aurora width / halo /
    /// cloud density / stage tint). 0 (unknown) renders the neutral mood.
    let weatherCode: Int
    /// Collapsed state uses a slightly smaller composition (matches the
    /// v3 collapsed stage viewBox 360×150 vs expanded 360×220).
    var compact: Bool = false

    private var mood: SkyMood { SkyMood(weatherCode: weatherCode) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // stage base gradient — `linear-gradient(177deg,#3b3c6b,#2b2b51,#191a30)`,
                // darkened for storm moods.
                LinearGradient(
                    colors: mood.stageColors,
                    startPoint: .top, endPoint: .bottom
                )

                Canvas { ctx, size in
                    drawStage(ctx: &ctx, size: size)
                }
                .blendMode(.plusLighter)
                .opacity(0.95)

                // route-motif nodes (crisp, drawn over the blurred sky)
                Canvas { ctx, size in
                    drawRouteMotif(ctx: &ctx, size: size)
                }

                // sun halo for clear/mostly-clear moods (a soft radial,
                // top-right — the "wider aurora + sun halo" clear mood).
                if mood.showsSunHalo {
                    RadialGradient(
                        colors: [WeatherV3.sun.opacity(0.30), .clear],
                        center: .topTrailing, startRadius: 0, endRadius: w * 0.55
                    )
                    .blendMode(.plusLighter)
                }
            }
            .frame(width: w, height: h)
        }
        .accessibilityHidden(true)
    }

    /// Aurora ribbon (blurred wide + thin bright) + two cloud ellipses.
    private func drawStage(ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let sx = w / 360.0          // the HTML stage is authored at 360 wide
        let sy = h / (compact ? 150.0 : 220.0)
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }

        // ── aurora — wide blurred stroke (opacity .30) ──
        // path: M-20 54 C 90 14, 220 86, 390 30  (expanded) /
        //       M-20 40 C 90 8, 230 70, 390 24   (collapsed)
        var wide = Path()
        if compact {
            wide.move(to: P(-20, 40))
            wide.addCurve(to: P(390, 24), control1: P(90, 8), control2: P(230, 70))
        } else {
            wide.move(to: P(-20, 54))
            wide.addCurve(to: P(390, 30), control1: P(90, 14), control2: P(220, 86))
        }
        var blurredCtx = ctx
        blurredCtx.addFilter(.blur(radius: 7 * sx))
        blurredCtx.stroke(
            wide, with: .linearGradient(
                Gradient(colors: [WeatherV3.auroraA, WeatherV3.auroraB, WeatherV3.auroraC]),
                startPoint: .zero, endPoint: CGPoint(x: w, y: h)),
            style: StrokeStyle(lineWidth: mood.auroraWide * sx, lineCap: .round)
        )

        // ── aurora — thin bright stroke (expanded only; opacity .55) ──
        if !compact {
            var thin = Path()
            thin.move(to: P(-20, 70))
            thin.addCurve(to: P(390, 46), control1: P(90, 30), control2: P(230, 96))
            ctx.stroke(
                thin, with: .linearGradient(
                    Gradient(colors: [WeatherV3.auroraA, WeatherV3.auroraB, WeatherV3.auroraC]),
                    startPoint: .zero, endPoint: CGPoint(x: w, y: h)),
                style: StrokeStyle(lineWidth: 3 * sx, lineCap: .round)
            )
        }

        // ── two soft bespoke cloud forms (blurred ellipses) ──
        // expanded: ellipse 300,70 rx70 ry26 op.10 + 70,150 rx90 ry30 op.06
        // collapsed: ellipse 300,54 rx64 ry22 op.10
        var cloudCtx = ctx
        cloudCtx.addFilter(.blur(radius: 7 * sx))
        let cloudOp = mood.cloudOpacityBoost
        func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ op: Double) {
            let rect = CGRect(x: (cx - rx) * sx, y: (cy - ry) * sy, width: rx * 2 * sx, height: ry * 2 * sy)
            cloudCtx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(op + cloudOp)))
        }
        if compact {
            ellipse(300, 54, 64, 22, 0.10)
        } else {
            ellipse(300, 70, 70, 26, 0.10)
            ellipse(70, 150, 90, 30, 0.06)
        }
    }

    /// The dashed route motif + origin (#cdbcff) / dest (#FF55A6) nodes.
    private func drawRouteMotif(ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let sx = w / 360.0
        let sy = h / (compact ? 150.0 : 220.0)
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }

        var route = Path()
        let o: CGPoint
        let d: CGPoint
        if compact {
            // M36 128 C 130 100, 210 146, 326 112
            o = P(36, 128); d = P(326, 112)
            route.move(to: o)
            route.addCurve(to: d, control1: P(130, 100), control2: P(210, 146))
        } else {
            // M40 188 C 130 150, 210 210, 322 168
            o = P(40, 188); d = P(322, 168)
            route.move(to: o)
            route.addCurve(to: d, control1: P(130, 150), control2: P(210, 210))
        }
        ctx.stroke(
            route, with: .color(WeatherV3.nodeOrigin.opacity(0.5)),
            style: StrokeStyle(lineWidth: 1.4 * sx, lineCap: .round, dash: [2 * sx, 5 * sx])
        )
        let r: CGFloat = (compact ? 3 : 3.2) * sx
        ctx.fill(Path(ellipseIn: CGRect(x: o.x - r, y: o.y - r, width: r * 2, height: r * 2)),
                 with: .color(WeatherV3.nodeOrigin.opacity(0.7)))
        ctx.fill(Path(ellipseIn: CGRect(x: d.x - r, y: d.y - r, width: r * 2, height: r * 2)),
                 with: .color(WeatherV3.nodeDest.opacity(0.8)))
    }
}

// MARK: - 1b · SKY STAGE HERO (live engine overload)

/// The build-751 upgrade of the brand hero: the SAME iridescent route-motif
/// signature drawn OVER a full `WeatherSkyView` continuous scene (drifting
/// clouds, intensity-scaled precipitation, lightning + bolt, moon-with-phase,
/// stars, sun + rays + flare, fog drift, wind shear) — every layer bound to
/// the live `WeatherSnapshot`. This is the engine fan-out: every weather
/// surface that already hosts a `SkyStageHero` gains the continuous animated
/// sky by passing the snapshot instead of just the bare `weatherCode`.
///
/// The legacy `SkyStageHero(weatherCode:)` (static aurora-only stage) is
/// retained for callers that genuinely hold only a code; new wiring should
/// prefer this snapshot overload so the whole app shares one engine.
///
/// `animated == false` (Reduce Motion) passes straight through to the
/// engine's single static frame — the route motif is drawn once either way.
struct SkyStageHeroLive: View {
    let snapshot: WeatherSnapshot
    var animated: Bool = true
    /// Collapsed state uses the smaller route-motif composition (matches the
    /// v3 collapsed stage viewBox 360×150 vs expanded 360×220).
    var compact: Bool = false

    var body: some View {
        ZStack {
            // ── Base: the full Apple-Weather-grade continuous sky engine ──
            WeatherSkyView(snapshot: snapshot, animated: animated)

            // ── Brand signature on top: the dashed route motif + nodes ──
            // (the operational "lane drawn through the sky" identity the raw
            // engine doesn't carry — kept so every surface reads as EusoTrip).
            Canvas { ctx, size in
                drawRouteMotif(ctx: &ctx, size: size)
            }
            .allowsHitTesting(false)
        }
        .accessibilityHidden(true)
    }

    /// The dashed route motif + origin (#cdbcff) / dest (#FF55A6) nodes —
    /// identical geometry to the legacy `SkyStageHero` so the two render the
    /// same brand mark at both stage sizes.
    private func drawRouteMotif(ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let sx = w / 360.0
        let sy = h / (compact ? 150.0 : 220.0)
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }

        var route = Path()
        let o: CGPoint
        let d: CGPoint
        if compact {
            o = P(36, 128); d = P(326, 112)
            route.move(to: o)
            route.addCurve(to: d, control1: P(130, 100), control2: P(210, 146))
        } else {
            o = P(40, 188); d = P(322, 168)
            route.move(to: o)
            route.addCurve(to: d, control1: P(130, 150), control2: P(210, 210))
        }
        ctx.stroke(
            route, with: .color(WeatherV3.nodeOrigin.opacity(0.5)),
            style: StrokeStyle(lineWidth: 1.4 * sx, lineCap: .round, dash: [2 * sx, 5 * sx])
        )
        let r: CGFloat = (compact ? 3 : 3.2) * sx
        ctx.fill(Path(ellipseIn: CGRect(x: o.x - r, y: o.y - r, width: r * 2, height: r * 2)),
                 with: .color(WeatherV3.nodeOrigin.opacity(0.7)))
        ctx.fill(Path(ellipseIn: CGRect(x: d.x - r, y: d.y - r, width: r * 2, height: r * 2)),
                 with: .color(WeatherV3.nodeDest.opacity(0.8)))
    }
}

/// The stage mood resolved from an Apple WeatherKit weatherCode — clear widens
/// the aurora and lights a sun halo; storm darkens the stage tint and
/// densifies the cloud. Strictly derived from the live code; an unknown
/// code (0) renders the neutral default.
private struct SkyMood {
    let weatherCode: Int

    private var family: Family {
        switch weatherCode {
        case 1000, 1100:                   return .clear
        case 1101:                         return .partly
        case 1102, 1001:                   return .cloudy
        case 2000, 2100:                   return .fog
        case 4000, 4200, 4001, 4201,
             5000, 5001, 5100, 5101,
             6000, 6001, 6200, 6201,
             7000, 7101, 7102:             return .wet
        case 8000:                         return .storm
        default:                           return .neutral
        }
    }
    private enum Family { case clear, partly, cloudy, fog, wet, storm, neutral }

    /// Wide aurora stroke width — clear is widest (34), storm narrowest.
    var auroraWide: CGFloat {
        switch family {
        case .clear:   return 38
        case .partly:  return 34
        case .neutral: return 32
        case .cloudy, .fog: return 28
        case .wet:     return 26
        case .storm:   return 22
        }
    }

    var showsSunHalo: Bool { family == .clear || family == .partly }

    /// Extra white-ellipse opacity for denser-cloud moods.
    var cloudOpacityBoost: Double {
        switch family {
        case .cloudy, .fog: return 0.06
        case .wet:          return 0.08
        case .storm:        return 0.12
        default:            return 0.0
        }
    }

    /// Stage base gradient — the brand stage, darkened for storm/wet.
    var stageColors: [Color] {
        switch family {
        case .storm:
            return [Color(red: 0x24 / 255, green: 0x24 / 255, blue: 0x40 / 255),
                    Color(red: 0x18 / 255, green: 0x18 / 255, blue: 0x30 / 255),
                    Color(red: 0x0E / 255, green: 0x0E / 255, blue: 0x1E / 255)]
        case .wet, .cloudy, .fog:
            return [Color(red: 0x32 / 255, green: 0x33 / 255, blue: 0x5C / 255),
                    Color(red: 0x24 / 255, green: 0x24 / 255, blue: 0x44 / 255),
                    Color(red: 0x15 / 255, green: 0x16 / 255, blue: 0x2A / 255)]
        default:
            // verbatim --hero base #3b3c6b → #2b2b51 → #191a30
            return [Color(red: 0x3B / 255, green: 0x3C / 255, blue: 0x6B / 255),
                    Color(red: 0x2B / 255, green: 0x2B / 255, blue: 0x51 / 255),
                    Color(red: 0x19 / 255, green: 0x1A / 255, blue: 0x30 / 255)]
        }
    }
}

// MARK: - 2 · HOURLY RIBBON

/// A temp polyline (gradient `#FFCB47→#FF7E6B`) over a precip-gradient
/// area (`#82B7FF` fade), plotted from the 8 hourly `temperature` +
/// `precipitationProbability` values. The peak/risk hour gets a node + a
/// faint danger column; a thin row of hour labels + micro condition
/// glyphs + precip % sits beneath. Path-based, real series, rounded.
/// Collapses entirely when `hours` is empty.
struct HourlyRibbon: View {
    let hours: [WeatherSnapshot.HourlyForecast]
    /// The peak/risk hour index in `hours` (snapshot.peakHourIndex).
    let peakIndex: Int?

    /// The hour the user is actively scrubbing to (drag your finger across
    /// the chart — the indicator + readout follow). Nil when not touching.
    @State private var scrubIndex: Int? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var series: [WeatherSnapshot.HourlyForecast] { Array(hours.prefix(8)) }

    var body: some View {
        if series.count >= 2 {
            VStack(spacing: 0) {
                ribbonChart
                    .frame(height: 116)
                labelRow
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
            }
        }
    }

    private var ribbonChart: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pts = nodePoints(width: w)
            let temps = series.map(\.tempF)
            let tMin = CGFloat(temps.min() ?? 0)
            let tMax = CGFloat(temps.max() ?? 1)
            let tps = tempPoints(width: w, height: h, tMin: tMin, tMax: tMax)

            ZStack {
            Canvas { ctx, size in
                // ── precip area (filled, #82B7FF fade) ──
                // height of the area at each x is driven by precip prob.
                var area = Path()
                let baseY = size.height - 4
                area.move(to: CGPoint(x: pts.first!.x, y: baseY))
                for (i, p) in pts.enumerated() {
                    let prob = CGFloat(series[i].precipChancePct ?? 0) / 100.0
                    // map 0…100% to a band rising from baseY (more precip
                    // = taller blue area). Capped so the fill never eats
                    // the whole stage.
                    let top = baseY - (10 + prob * (size.height * 0.62))
                    area.addLine(to: CGPoint(x: p.x, y: top))
                }
                area.addLine(to: CGPoint(x: pts.last!.x, y: baseY))
                area.closeSubpath()
                ctx.fill(area, with: .linearGradient(
                    Gradient(stops: [
                        .init(color: WeatherV3.drop.opacity(0.55), location: 0),
                        .init(color: WeatherV3.drop.opacity(0.0), location: 1)
                    ]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)))

                // ── faint danger column at the peak hour ──
                if let peak = peakIndex, series.indices.contains(peak) {
                    let px = pts[peak].x
                    let colW: CGFloat = max(14, w / CGFloat(series.count) * 0.42)
                    ctx.fill(
                        Path(CGRect(x: px - colW / 2, y: 0, width: colW, height: size.height)),
                        with: .color(WeatherV3.danger.opacity(0.10)))
                }

                // ── temp polyline (gradient #FFCB47→#FF7E6B, rounded) ──
                var line = Path()
                for (i, p) in tempPoints(width: w, height: h, tMin: tMin, tMax: tMax).enumerated() {
                    if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
                }
                ctx.stroke(line, with: .linearGradient(
                    Gradient(colors: [WeatherV3.sun, WeatherV3.tempWarm]),
                    startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                // ── nodes: white dots on min/max/last, danger node on peak ──
                let tps = tempPoints(width: w, height: h, tMin: tMin, tMax: tMax)
                func dot(_ p: CGPoint, _ r: CGFloat, _ c: Color, ring: Bool = false) {
                    let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(c))
                    if ring {
                        ctx.stroke(Path(ellipseIn: rect), with: .color(.white),
                                   style: StrokeStyle(lineWidth: 1.5))
                    }
                }
                if let hiIdx = temps.firstIndex(of: temps.max() ?? 0) { dot(tps[hiIdx], 2.6, .white) }
                if let loIdx = temps.firstIndex(of: temps.min() ?? 0) { dot(tps[loIdx], 2.6, .white) }
                dot(tps[0], 2.6, .white)
                dot(tps[tps.count - 1], 2.6, .white)
                if let peak = peakIndex, series.indices.contains(peak) {
                    dot(tps[peak], 4.5, WeatherV3.danger, ring: true)
                }

                // ── temp labels over the key nodes ──
                func label(_ idx: Int, _ color: Color) {
                    guard tps.indices.contains(idx) else { return }
                    let t = Text("\(series[idx].tempF)°")
                        .font(.system(size: 12, weight: .heavy)).monospacedDigit()
                        .foregroundColor(color)
                    ctx.draw(t, at: CGPoint(x: tps[idx].x, y: tps[idx].y - 12), anchor: .center)
                }
                if let hiIdx = temps.firstIndex(of: temps.max() ?? 0) { label(hiIdx, .white) }
                label(0, .white)
                label(tps.count - 1, .white)
                if let peak = peakIndex { label(peak, Color(red: 1.0, green: 0.84, blue: 0.82)) }
            }
            // ── scrub overlay: a vertical guide + node + a live readout
            //    that follow the finger across the chart (drag left↔right
            //    to inspect every hour). ──
            if let si = scrubIndex, tps.indices.contains(si) {
                scrubOverlay(index: si, point: tps[si], width: w, height: h)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            }
            .contentShape(Rectangle())
            // simultaneousGesture (not .gesture): a plain child DragGesture
            // still CAPTURES the touch from the home ScrollView once it passes
            // its minimum distance — the vertical-intent `return` below can't
            // hand the drag back, so scrolling died over the widget. Running it
            // simultaneously lets the ScrollView keep vertical pans while a
            // deliberate horizontal drag still scrubs the hourly ribbon.
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { v in
                        guard abs(v.translation.width) >= abs(v.translation.height) else { return }
                        let idx = nearestIndex(toX: v.location.x, points: tps)
                        if idx != scrubIndex {
                            scrubIndex = idx
                            scrubHaptic()
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.22)) { scrubIndex = nil }
                    }
            )
        }
    }

    /// The live scrub indicator drawn over the chart at the selected hour:
    /// a brand-gradient vertical guide, a ringed node on the temp line, and
    /// a floating readout capsule (time · temp · precip) that stays inside
    /// the chart bounds.
    @ViewBuilder
    private func scrubOverlay(index: Int, point: CGPoint, width: CGFloat, height: CGFloat) -> some View {
        let hour = series[index]
        ZStack(alignment: .topLeading) {
            // vertical guide
            Rectangle()
                .fill(LinearGradient(
                    colors: [WeatherV3.auroraB.opacity(0), WeatherV3.auroraB.opacity(0.6), WeatherV3.auroraB.opacity(0)],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: 2)
                .position(x: point.x, y: height / 2)
            // node on the temp line
            Circle()
                .fill(.white)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(WeatherV3.auroraB, lineWidth: 2.5))
                .shadow(color: WeatherV3.auroraB.opacity(0.6), radius: 5)
                .position(point)
            // floating readout capsule — clamped within the chart width
            HStack(spacing: 5) {
                Text(index == 0 ? "Now" : hour.hourLabel)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.7))
                Text("\(hour.tempF)°")
                    .font(.system(size: 12, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(.white)
                if let p = hour.precipDisplay {
                    WeatherIcons.utility(.precip, size: 9, tint: WeatherV3.drop)
                    Text(p)
                        .font(.system(size: 10, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(WeatherV3.drop)
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(WeatherV3.cardInkRaised))
            .overlay(Capsule().strokeBorder(WeatherV3.auroraB.opacity(0.5), lineWidth: 1))
            .fixedSize()
            .position(x: min(max(46, point.x), width - 46), y: max(14, point.y - 30))
        }
    }

    /// Index of the hour whose node is horizontally nearest the touch x.
    private func nearestIndex(toX x: CGFloat, points: [CGPoint]) -> Int {
        guard !points.isEmpty else { return 0 }
        var best = 0
        var bestD = CGFloat.greatestFiniteMagnitude
        for (i, p) in points.enumerated() {
            let d = abs(p.x - x)
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    /// A light tick as the scrub crosses into a new hour (skipped under
    /// Reduce Motion to respect the accessibility preference).
    private func scrubHaptic() {
        guard !reduceMotion else { return }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
        #endif
    }

    /// Evenly-spaced x positions across the chart (one per hour).
    private func nodePoints(width: CGFloat) -> [CGPoint] {
        let inset: CGFloat = 20
        let usable = max(1, width - inset * 2)
        let step = usable / CGFloat(max(1, series.count - 1))
        return series.indices.map { CGPoint(x: inset + CGFloat($0) * step, y: 0) }
    }

    /// Temp polyline points — x evenly spaced, y inverted-normalised into
    /// the upper band of the chart (so the precip area sits below it).
    private func tempPoints(width: CGFloat, height: CGFloat, tMin: CGFloat, tMax: CGFloat) -> [CGPoint] {
        let inset: CGFloat = 20
        let usable = max(1, width - inset * 2)
        let step = usable / CGFloat(max(1, series.count - 1))
        let top: CGFloat = 26       // leave room for labels
        let bottom: CGFloat = height * 0.62
        let range = max(1, tMax - tMin)
        return series.indices.map { i in
            let t = CGFloat(series[i].tempF)
            let norm = (t - tMin) / range          // 0 (cold) … 1 (hot)
            let y = bottom - norm * (bottom - top)  // hot = higher
            return CGPoint(x: inset + CGFloat(i) * step, y: y)
        }
    }

    /// Hour labels + micro condition glyph + precip % beneath the chart.
    private var labelRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(series.enumerated()), id: \.element.id) { idx, hour in
                let isPeak = idx == peakIndex
                let isScrubbed = idx == scrubIndex
                VStack(spacing: 4) {
                    Text(idx == 0 ? "Now" : hour.hourLabel)
                        .font(.system(size: 10, weight: isScrubbed ? .heavy : .regular))
                        .foregroundStyle(isScrubbed
                            ? AnyShapeStyle(.white)
                            : (isPeak
                                ? AnyShapeStyle(Color(red: 1.0, green: 0.84, blue: 0.82))
                                : AnyShapeStyle(.white.opacity(0.62))))
                    WeatherIcons.symbolView(for: hour, size: 15)
                        .scaleEffect(isScrubbed ? 1.22 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isScrubbed)
                    if let p = hour.precipDisplay {
                        Text(p)
                            .font(.system(size: 9.5, weight: .heavy))
                            .monospacedDigit()
                            .foregroundStyle(WeatherV3.drop)
                    } else {
                        Text(" ").font(.system(size: 9.5, weight: .heavy))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - 3 · ROUTE-CELL DIAGRAM (the operational showpiece)

/// The thing no consumer weather app does: the weather hazard drawn
/// crossing the actual lane. A curved route Path from origin → dest with
/// a translucent hazard band over the peak segment + a marker at the
/// peak. Mode-specific rendering per §D.1.3 + the tri-modal HTML:
///   • truck  — single road curve + red cell band.
///   • rail   — double-line track + cross-ties + slate crosswind zone +
///              streamflow wave + fog haze over the yard node.
///   • vessel — wavy sea band + dashed voyage path + cyan gust/swell zone
///              at the berth + wave glyphs.
/// Geometry is the load's lane (origin/destination labels) + the peak
/// leg; the band position tracks the risk tier (severe sits mid-lane).
struct RouteCellDiagram: View {
    let segment: WeatherSnapshot.LaneImpactSegment

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Canvas { ctx, size in
                    switch segment.mode {
                    case .truck:  drawTruck(ctx: &ctx, size: size)
                    case .rail:   drawRail(ctx: &ctx, size: size)
                    case .vessel: drawVessel(ctx: &ctx, size: size)
                    }
                    drawEndpointLabels(ctx: &ctx, size: size)
                    drawPeakLabel(ctx: &ctx, size: size)
                }
            }
            .frame(width: w, height: h)
        }
        .frame(height: 92)
        .accessibilityHidden(true)
    }

    // Authored against the tri-modal HTML viewBox 340×92.
    private func sx(_ size: CGSize) -> CGFloat { size.width / 340.0 }
    private func sy(_ size: CGSize) -> CGFloat { size.height / 92.0 }
    private func P(_ x: CGFloat, _ y: CGFloat, _ size: CGSize) -> CGPoint {
        CGPoint(x: x * sx(size), y: y * sy(size))
    }

    /// The band's center x (in 340-space). severe = mid-lane, lesser
    /// tiers shift toward the destination so the marker reads "later".
    private var bandCenterX: CGFloat {
        switch segment.riskTier {
        case .severe:   return 211
        case .elevated: return 240
        case .watch:    return 268
        case .none:     return 290
        }
    }

    // ── TRUCK: road curve + red cell band ──
    private func drawTruck(ctx: inout GraphicsContext, size: CGSize) {
        let bx = bandCenterX
        // red cell band (url(#bandRed)) — a soft vertical column.
        fillBand(ctx: &ctx, size: size, centerX: bx, width: 42,
                 colors: [WeatherV3.danger.opacity(0), WeatherV3.danger.opacity(0.5), WeatherV3.danger.opacity(0)])

        // road curve: M26 66 C 118 34, 168 74, 314 38
        var road = Path()
        road.move(to: P(26, 66, size))
        road.addCurve(to: P(314, 38, size), control1: P(118, 34, size), control2: P(168, 74, size))
        ctx.stroke(road, with: .color(Color(red: 0x34 / 255, green: 0x38 / 255, blue: 0x4F / 255)),
                   style: StrokeStyle(lineWidth: 6 * sy(size), lineCap: .round))
        ctx.stroke(road, with: .color(WeatherV3.auroraA),
                   style: StrokeStyle(lineWidth: 2.5 * sy(size), lineCap: .round, dash: [1 * sx(size), 7 * sx(size)]))

        drawNodes(ctx: &ctx, size: size, origin: P(26, 66, size), dest: P(314, 38, size),
                  destFill: WeatherV3.auroraC)
        // peak marker on the band
        marker(ctx: &ctx, size: size, at: P(bx, 55, size))
    }

    // ── RAIL: double track + ties + slate crosswind + streamflow + fog ──
    private func drawRail(ctx: inout GraphicsContext, size: CGSize) {
        // fog haze over the yard (origin) node
        var fogCtx = ctx
        fogCtx.addFilter(.blur(radius: 5 * sx(size)))
        let fogRect = CGRect(x: (44 - 40) * sx(size), y: (64 - 16) * sy(size),
                             width: 80 * sx(size), height: 32 * sy(size))
        fogCtx.fill(Path(ellipseIn: fogRect), with: .color(WeatherV3.drop.opacity(0.14)))

        // slate crosswind zone — a diagonal band (rotated ~-18°).
        drawDiagonalBand(ctx: &ctx, size: size, centerX: bandCenterX,
                         color: WeatherV3.rail.opacity(0.42), angle: -18)

        // double-line track: two parallel curves
        let railColor = Color(red: 0x3A / 255, green: 0x41 / 255, blue: 0x50 / 255)
        var top = Path()
        top.move(to: P(24, 60, size)); top.addCurve(to: P(318, 44, size), control1: P(120, 40, size), control2: P(200, 66, size))
        var bot = Path()
        bot.move(to: P(24, 66, size)); bot.addCurve(to: P(318, 50, size), control1: P(120, 46, size), control2: P(200, 72, size))
        ctx.stroke(top, with: .color(railColor), style: StrokeStyle(lineWidth: 6 * sy(size), lineCap: .round))
        ctx.stroke(bot, with: .color(railColor), style: StrokeStyle(lineWidth: 6 * sy(size), lineCap: .round))

        // cross-ties
        var ties = Path()
        for (x, y) in [(CGFloat(60), CGFloat(55)), (110, 50), (160, 50), (210, 53), (260, 50), (300, 47)] {
            ties.move(to: P(x, y, size)); ties.addLine(to: P(x, y + 8, size))
        }
        ctx.stroke(ties, with: .color(WeatherV3.rail), style: StrokeStyle(lineWidth: 1.6 * sx(size)))

        // streamflow wave near the at-risk crossing
        var wave = Path()
        wave.move(to: P(280, 70, size))
        wave.addCurve(to: P(292, 70, size), control1: P(284, 66, size), control2: P(288, 74, size))
        wave.addCurve(to: P(304, 70, size), control1: P(296, 66, size), control2: P(300, 74, size))
        ctx.stroke(wave, with: .color(WeatherV3.drop), style: StrokeStyle(lineWidth: 2 * sx(size), lineCap: .round))

        // yard node (origin) + slate ring
        drawNode(ctx: &ctx, size: size, at: P(44, 62, size), fill: Color(red: 0x12 / 255, green: 0x14 / 255, blue: 0x1C / 255),
                 ring: Color(red: 0xC6 / 255, green: 0xD0 / 255, blue: 0xDE / 255))
        marker(ctx: &ctx, size: size, at: P(bandCenterX, 56, size), color: WeatherV3.rail)
    }

    // ── VESSEL: sea band + dashed voyage + cyan gust/swell + wave glyphs ──
    private func drawVessel(ctx: inout GraphicsContext, size: CGSize) {
        // subtle sea band (wavy fill) along the bottom
        var sea = Path()
        sea.move(to: P(0, 64, size))
        var x: CGFloat = 0
        var up = true
        while x < 340 {
            let nx = x + 30
            sea.addCurve(to: P(nx, 64, size),
                         control1: P(x + 15, up ? 56 : 72, size),
                         control2: P(x + 15, up ? 56 : 72, size))
            x = nx; up.toggle()
        }
        sea.addLine(to: P(340, 92, size)); sea.addLine(to: P(0, 92, size)); sea.closeSubpath()
        ctx.fill(sea, with: .linearGradient(
            Gradient(colors: [Color(red: 0x1B / 255, green: 0x6F / 255, blue: 0x8A / 255).opacity(0.5),
                              Color(red: 0x0E / 255, green: 0x3A / 255, blue: 0x49 / 255).opacity(0.2)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

        // cyan gust/swell zone at the berth
        fillBand(ctx: &ctx, size: size, centerX: 263, width: 50,
                 colors: [WeatherV3.vessel.opacity(0), WeatherV3.vessel.opacity(0.4), WeatherV3.vessel.opacity(0)])

        // dashed voyage path: M22 58 C 110 44, 180 60, 300 50
        var voyage = Path()
        voyage.move(to: P(22, 58, size))
        voyage.addCurve(to: P(300, 50, size), control1: P(110, 44, size), control2: P(180, 60, size))
        ctx.stroke(voyage, with: .color(WeatherV3.vessel),
                   style: StrokeStyle(lineWidth: 2.4 * sy(size), lineCap: .round, dash: [2 * sx(size), 6 * sx(size)]))

        // origin (gulf) node + berth marker (rounded rect, magenta ring)
        drawNode(ctx: &ctx, size: size, at: P(22, 58, size), fill: Color(red: 0x12 / 255, green: 0x14 / 255, blue: 0x1C / 255),
                 ring: Color(red: 0x7F / 255, green: 0xE6 / 255, blue: 0xEF / 255))
        let berthRect = CGRect(x: 296 * sx(size) - 8 * sx(size), y: 42 * sy(size),
                               width: 16 * sx(size), height: 16 * sy(size))
        let berthPath = Path(roundedRect: berthRect, cornerRadius: 3 * sx(size))
        ctx.fill(berthPath, with: .color(Color(red: 0x12 / 255, green: 0x14 / 255, blue: 0x1C / 255)))
        ctx.stroke(berthPath, with: .color(WeatherV3.auroraC), style: StrokeStyle(lineWidth: 2 * sx(size)))

        // wave glyphs in the swell zone
        var glyph = Path()
        glyph.move(to: P(250, 60, size))
        glyph.addCurve(to: P(259, 60, size), control1: P(253, 57, size), control2: P(256, 63, size))
        glyph.addCurve(to: P(268, 60, size), control1: P(262, 57, size), control2: P(265, 63, size))
        ctx.stroke(glyph, with: .color(Color(red: 0x9A / 255, green: 0xEE / 255, blue: 0xF4 / 255).opacity(0.9)),
                   style: StrokeStyle(lineWidth: 1.8 * sx(size), lineCap: .round))
    }

    // ── shared helpers ──

    /// A soft vertical hazard column (the `url(#band*)` gradients are
    /// horizontal fade-in/out; here drawn as a left→right gradient over a
    /// rect so the band glows in the middle).
    private func fillBand(ctx: inout GraphicsContext, size: CGSize, centerX: CGFloat, width: CGFloat, colors: [Color]) {
        let rect = CGRect(x: (centerX - width / 2) * sx(size), y: 0,
                          width: width * sx(size), height: size.height)
        ctx.fill(Path(rect), with: .linearGradient(
            Gradient(colors: colors),
            startPoint: CGPoint(x: rect.minX, y: 0),
            endPoint: CGPoint(x: rect.maxX, y: 0)))
    }

    /// A diagonal slate crosswind band (rail).
    private func drawDiagonalBand(ctx: inout GraphicsContext, size: CGSize, centerX: CGFloat, color: Color, angle: Double) {
        var sub = ctx
        let pivot = P(centerX, 46, size)
        sub.translateBy(x: pivot.x, y: pivot.y)
        sub.rotate(by: .degrees(angle))
        let w: CGFloat = 40 * sx(size)
        let rect = CGRect(x: -w / 2, y: -size.height, width: w, height: size.height * 2)
        sub.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [color.opacity(0), color, color.opacity(0)]),
            startPoint: CGPoint(x: -w / 2, y: 0), endPoint: CGPoint(x: w / 2, y: 0)))
    }

    private func drawNodes(ctx: inout GraphicsContext, size: CGSize, origin: CGPoint, dest: CGPoint, destFill: Color) {
        drawNode(ctx: &ctx, size: size, at: origin,
                 fill: Color(red: 0x12 / 255, green: 0x14 / 255, blue: 0x1C / 255),
                 ring: Color(red: 0x8F / 255, green: 0xA0 / 255, blue: 0xFF / 255))
        let r: CGFloat = 5 * sx(size)
        ctx.fill(Path(ellipseIn: CGRect(x: dest.x - r, y: dest.y - r, width: r * 2, height: r * 2)),
                 with: .color(destFill))
    }

    private func drawNode(ctx: inout GraphicsContext, size: CGSize, at p: CGPoint, fill: Color, ring: Color) {
        let r: CGFloat = 5 * sx(size)
        let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: rect), with: .color(fill))
        ctx.stroke(Path(ellipseIn: rect), with: .color(ring), style: StrokeStyle(lineWidth: 2.5 * sx(size)))
    }

    private func marker(ctx: inout GraphicsContext, size: CGSize, at p: CGPoint, color: Color = WeatherV3.danger) {
        let r: CGFloat = 5.5 * sx(size)
        let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: rect), with: .color(color))
        ctx.stroke(Path(ellipseIn: rect), with: .color(.white), style: StrokeStyle(lineWidth: 1.6 * sx(size)))
    }

    /// Origin / destination labels under the route — from the real lane
    /// string. Honest: drawn only when the label is non-empty.
    private func drawEndpointLabels(ctx: inout GraphicsContext, size: CGSize) {
        let labelColor = Color(red: 0xAE / 255, green: 0xB6 / 255, blue: 0xC6 / 255)
        let o = segment.originLabel
        let d = segment.destinationLabel
        if !o.isEmpty {
            ctx.draw(Text(o).font(.system(size: 10, weight: .bold)).foregroundColor(labelColor),
                     at: P(segment.mode == .rail ? 30 : 26, 84, size), anchor: .leading)
        }
        if !d.isEmpty {
            ctx.draw(Text(d).font(.system(size: 10, weight: .bold)).foregroundColor(labelColor),
                     at: P(314, 84, size), anchor: .trailing)
        }
    }

    /// The peak-leg label over the hazard band ("4 PM CELL" /
    /// "CROSSWIND" / "GUST + SWELL") — from the real peakLeg, never
    /// fabricated. Drawn only when a peakLeg exists.
    private func drawPeakLabel(ctx: inout GraphicsContext, size: CGSize) {
        guard let peak = segment.peakLeg else { return }
        let text = peak.time.isEmpty ? peak.label.uppercased() : peak.time.uppercased()
        let color: Color = {
            switch segment.mode {
            case .truck:  return Color(red: 1.0, green: 0.70, blue: 0.67)
            case .rail:   return Color(red: 0xCF / 255, green: 0xD7 / 255, blue: 0xE3 / 255)
            case .vessel: return Color(red: 0x9A / 255, green: 0xEE / 255, blue: 0xF4 / 255)
            }
        }()
        let cx = segment.mode == .vessel ? 263 : bandCenterX
        ctx.draw(Text(text).font(.system(size: 10, weight: .heavy)).foregroundColor(color),
                 at: P(cx, 15, size), anchor: .center)
    }
}

// MARK: - 4 · 7-DAY RANGE BAR

/// A thin hi→lo gradient bar (`#82B7FF → #FFCB47`, drop→sun) sized to the
/// day's `temperatureMin/Max` within the week's overall range — the
/// bespoke alternative to plain hi/lo text. The bar's left inset + width
/// are proportional to where this day's lo→hi sits inside the week band,
/// so a cold day's bar starts further left and a hot day's reaches
/// further right (a real visual range, not a fixed pill).
struct DayRangeBar: View {
    /// This day's low / high in °F.
    let lowF: Int
    let highF: Int
    /// The week's overall min low / max high — for proportional sizing.
    let weekLow: Int
    let weekHigh: Int

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let range = max(1, CGFloat(weekHigh - weekLow))
            let left = CGFloat(lowF - weekLow) / range
            let right = CGFloat(highF - weekLow) / range
            let x0 = left * w
            let barW = max(6, (right - left) * w)
            Capsule()
                .fill(LinearGradient(colors: [WeatherV3.drop, WeatherV3.sun],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: barW, height: 4)
                .offset(x: x0)
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}
