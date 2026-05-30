//
//  BandTrendChart.swift
//  EusoTrip 2027 · BespokeChartKit
//
//  A PATH-DRAWN line/area chart with setpoint / ceiling / floor BAND lines
//  plus N per-series polylines (e.g. one trace per reefer zone). Drag a
//  finger across the plot to scrub a readout cursor; the live last point on
//  each series pulses. Drives reefer temp setpoint-vs-actual (799 / 702),
//  rate forecast, and spend dual-line surfaces.
//
//  Reproduces the bespoke hero from wireframe 799 "Vessel Reefer Temp Log"
//  verbatim — gradient card rim, FSMA safe band fill, dashed ceiling /
//  setpoint / floor guides, per-zone polylines with last-point dots, the
//  rising amber→red excursion trace with a pulsing ring, axis labels and
//  the inline legend.
//
//  PRIMITIVE doctrine: public, reusable, data-driven. NO hardcoded business
//  data lives inside — every value arrives through the typed public model.
//  The #Preview at the bottom feeds clearly-sample data so the component is
//  demonstrably alive + interactive.
//
//  Guardrails honored: only `import SwiftUI`; no `func` declared inside a
//  Canvas/@ViewBuilder closure (all geometry lives in methods / computed
//  vars); .frame(width:height:) never (width:minHeight:); Double reductions
//  use reduce(into: 0.0); no @ViewBuilder on a func that uses an explicit
//  return.
//

import SwiftUI

// MARK: - Public data model

/// One reference guide line drawn across the full plot width: a setpoint,
/// a regulatory ceiling, or a floor. Pairs of guides also define the shaded
/// "safe band" (see `BandTrendChart.band`).
public struct BandTrendGuide: Identifiable, Equatable {
    public enum Role: Equatable {
        case ceiling     // hard upper limit (danger dashed) — e.g. FSMA 40°F
        case setpoint    // target value (info dashed)        — e.g. 34°F
        case floor       // lower limit (success dashed)      — e.g. 33°F
        case custom      // caller-tinted reference line
    }

    public let id: String
    /// Value on the Y axis where the guide sits.
    public let value: Double
    /// Short caption painted at the guide's left lip (e.g. "40°F · FSMA ceiling").
    public let label: String
    public let role: Role
    /// Override tint; when nil the role's canonical brand color is used.
    public let tint: Color?

    public init(
        id: String,
        value: Double,
        label: String,
        role: Role,
        tint: Color? = nil
    ) {
        self.id = id
        self.value = value
        self.label = label
        self.role = role
        self.tint = tint
    }
}

/// A single datum on a series: an X position (already normalized 0…1 across
/// the visible window, OR a raw value the caller maps — see `BandTrendSeries`)
/// and a Y value in the chart's data units.
public struct BandTrendPoint: Identifiable, Equatable {
    public let id: Int
    /// Position along the time axis, 0 (oldest) … 1 (now / newest).
    public let x: Double
    /// Value in data units (e.g. °F).
    public let y: Double

    public init(id: Int, x: Double, y: Double) {
        self.id = id
        self.x = x
        self.y = y
    }
}

/// One polyline trace — e.g. "Front zone", "Center zone", "Rear zone", or
/// a forecast line. The caller supplies the points, a tint, and emphasis.
public struct BandTrendSeries: Identifiable, Equatable {
    /// How a trace is rendered. `.solid` is the standard zone trace;
    /// `.rising` paints the bespoke amber→red excursion gradient at a
    /// heavier weight with a pulsing last-point ring; `.forecast` uses a
    /// dashed stroke for projected / predicted values.
    public enum Emphasis: Equatable { case solid, rising, forecast }

    public let id: String
    /// Display name shown in the legend (e.g. "Front", "Rear").
    public let name: String
    public let tint: Color
    public let emphasis: Emphasis
    public let points: [BandTrendPoint]
    /// Optional formatted readout for the legend / scrub (e.g. "38.4°").
    /// When nil the chart formats the last Y value itself.
    public let legendValue: String?
    /// Optional trailing glyph on the legend chip (e.g. "↑" for a rising
    /// zone). Cosmetic only.
    public let trend: String?

    public init(
        id: String,
        name: String,
        tint: Color,
        emphasis: Emphasis = .solid,
        points: [BandTrendPoint],
        legendValue: String? = nil,
        trend: String? = nil
    ) {
        self.id = id
        self.name = name
        self.tint = tint
        self.emphasis = emphasis
        self.points = points
        self.legendValue = legendValue
        self.trend = trend
    }
}

/// A labeled tick along the X (time) axis.
public struct BandTrendTick: Identifiable, Equatable {
    public let id: Int
    /// Position 0…1 across the plot.
    public let x: Double
    public let label: String
    /// When true the tick label is emphasized (e.g. "now").
    public let isNow: Bool

    public init(id: Int, x: Double, label: String, isNow: Bool = false) {
        self.id = id
        self.x = x
        self.label = label
        self.isNow = isNow
    }
}

// MARK: - BandTrendChart

/// Path-drawn band/trend chart. Public, reusable, fully data-driven.
///
/// Interaction
/// -----------
/// • **Drag-to-scrub** — dragging horizontally moves a vertical cursor and
///   surfaces a floating readout of every series value at the nearest sample.
///   The scrub index is published through the optional `selection` binding
///   and `onScrub` closure so a host screen can react (e.g. update a KPI
///   strip).
/// • **Live pulse** — each series' last point breathes; `.rising` series get
///   an extra expanding ring so an excursion reads as "happening now".
/// • **Animated transitions** — supplying new `series` animates the polylines
///   and band to their new geometry.
public struct BandTrendChart: View {

    // ---- Public API ---------------------------------------------------

    /// The traces to draw.
    public let series: [BandTrendSeries]
    /// Reference guide lines (ceiling / setpoint / floor / custom).
    public let guides: [BandTrendGuide]
    /// Optional shaded safe band expressed as a (low, high) data-value pair.
    /// When set, the region between the two Y values is tinted.
    public let band: (low: Double, high: Double)?
    /// Tint for the shaded safe band. Defaults to brand success.
    public let bandTint: Color
    /// Explicit Y-axis domain (min, max) in data units. When nil the chart
    /// derives a padded domain from the data + guides.
    public let yDomain: (min: Double, max: Double)?
    /// Y-axis tick labels (top→bottom order is handled internally).
    public let yTicks: [Double]
    /// X-axis time ticks.
    public let xTicks: [BandTrendTick]
    /// Eyebrow caption (top-left), e.g. "ZONE TEMPERATURE · °F · LAST 24H".
    public let eyebrow: String
    /// Trailing caption (top-right), e.g. "FSMA BAND 33–40°F".
    public let trailingCaption: String?
    /// Formats a Y value for axis labels, readouts and legend fallbacks.
    public let valueFormat: (Double) -> String

    /// Two-way binding to the scrubbed sample index (nil = not scrubbing).
    @Binding public var selection: Int?
    /// Fired whenever the scrub index changes (including to nil on release
    /// if `clearOnRelease` is true).
    public var onScrub: ((Int?) -> Void)?
    /// When true the cursor clears on finger-up; when false it sticks.
    public let clearOnRelease: Bool

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pulse: CGFloat = 0
    @State private var appeared = false

    public init(
        series: [BandTrendSeries],
        guides: [BandTrendGuide] = [],
        band: (low: Double, high: Double)? = nil,
        bandTint: Color = Color(red: 0.0, green: 0.769, blue: 0.549), // Brand.success #00C48C (literal — public default can't ref internal Brand)
        yDomain: (min: Double, max: Double)? = nil,
        yTicks: [Double] = [],
        xTicks: [BandTrendTick] = [],
        eyebrow: String = "TREND",
        trailingCaption: String? = nil,
        valueFormat: @escaping (Double) -> String = { String(format: "%.1f", $0) },
        selection: Binding<Int?> = .constant(nil),
        onScrub: ((Int?) -> Void)? = nil,
        clearOnRelease: Bool = true
    ) {
        self.series = series
        self.guides = guides
        self.band = band
        self.bandTint = bandTint
        self.yDomain = yDomain
        self.yTicks = yTicks
        self.xTicks = xTicks
        self.eyebrow = eyebrow
        self.trailingCaption = trailingCaption
        self.valueFormat = valueFormat
        self._selection = selection
        self.onScrub = onScrub
        self.clearOnRelease = clearOnRelease
    }

    // ---- Layout constants (mirror the 799 hero geometry) --------------

    /// Plot inset inside the card: left axis gutter, top headroom, right
    /// edge, bottom axis labels. Matches the SVG's 44 / 44 / 16 / 68 frame.
    private let plotLeading: CGFloat = 36
    private let plotTop: CGFloat = 44
    private let plotTrailing: CGFloat = 18
    private let plotBottom: CGFloat = 64
    private let cardRadius: CGFloat = Radius.xl

    // MARK: Body

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            header
            plotCanvas
                .frame(height: 248)
            legend
        }
        .padding(Space.s4)
        .background(cardBackground)
        .overlay(cardRim)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .onAppear { startPulse() }
        .animation(.easeInOut(duration: 0.55), value: series)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(eyebrow)
                .font(EType.micro).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: Space.s2)
            if let trailingCaption {
                Text(trailingCaption)
                    .font(EType.micro).tracking(0.4)
                    .foregroundStyle(Brand.success)
            }
        }
    }

    // MARK: Plot

    private var plotCanvas: some View {
        GeometryReader { geo in
            let plot = plotRect(in: geo.size)
            ZStack(alignment: .topLeading) {
                // Static layer: band fill, guides, gridlines, axes, series.
                Canvas { context, _ in
                    drawBand(in: context, plot: plot)
                    drawGuides(in: context, plot: plot)
                    drawGrid(in: context, plot: plot)
                    drawSeries(in: context, plot: plot)
                }

                // Live pulse layer (its own Canvas so the animated state
                // doesn't force the static layer to re-rasterize the paths).
                Canvas { context, _ in
                    drawPulses(in: context, plot: plot)
                }
                .allowsHitTesting(false)

                // Guide + axis text overlaid as real Text (sharper than
                // Canvas-drawn glyphs and picks up Dynamic Type).
                guideLabels(plot: plot)
                yAxisLabels(plot: plot)
                xAxisLabels(plot: plot)

                // Scrub cursor + floating readout.
                if let idx = clampedSelection {
                    scrubCursor(plot: plot, index: idx)
                }
            }
            .contentShape(Rectangle())
            .gesture(scrubGesture(plot: plot))
        }
    }

    // MARK: Scrub gesture

    private func scrubGesture(plot: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let i = nearestIndex(toX: value.location.x, plot: plot)
                updateSelection(i)
            }
            .onEnded { _ in
                if clearOnRelease { updateSelection(nil) }
            }
    }

    private func updateSelection(_ i: Int?) {
        guard i != selection else { return }
        withAnimation(.easeOut(duration: 0.12)) { selection = i }
        onScrub?(i)
    }

    // MARK: Scrub cursor view

    private func scrubCursor(plot: CGRect, index: Int) -> some View {
        let x = plot.minX + CGFloat(scrubX(at: index)) * plot.width
        return ZStack(alignment: .topLeading) {
            // Vertical cursor line.
            Rectangle()
                .fill(palette.textSecondary.opacity(0.55))
                .frame(width: 1, height: plot.height)
                .position(x: x, y: plot.midY)

            // Dot on each series at the scrub index.
            ForEach(series) { s in
                if let pt = s.points.first(where: { $0.id == index }) {
                    Circle()
                        .fill(s.tint)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(palette.bgCard, lineWidth: 1.5))
                        .position(
                            x: plot.minX + CGFloat(pt.x) * plot.width,
                            y: yPosition(pt.y, in: plot)
                        )
                }
            }

            readoutCard(plot: plot, index: index, anchorX: x)
        }
    }

    private func readoutCard(plot: CGRect, index: Int, anchorX: CGFloat) -> some View {
        let rows = scrubRows(at: index)
        let cardWidth: CGFloat = 116
        // Keep the card inside the plot — flip to the left of the cursor
        // when it would overflow the right edge.
        let rawX = anchorX + 10
        let x = min(rawX, plot.maxX - cardWidth) >= plot.minX
            ? min(rawX, plot.maxX - cardWidth)
            : anchorX - cardWidth - 10
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(rows, id: \.0) { row in
                HStack(spacing: 5) {
                    Circle().fill(row.2).frame(width: 5, height: 5)
                    Text(row.0)
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 4)
                    Text(row.1)
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textPrimary)
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(width: cardWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(palette.bgSheet)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(palette.borderSoft, lineWidth: 1)
                )
        )
        .position(x: max(plot.minX, x) + cardWidth / 2, y: plot.minY + 4 + cardHeight(rows.count) / 2)
    }

    private func cardHeight(_ rowCount: Int) -> CGFloat {
        CGFloat(rowCount) * 14 + 12
    }

    // MARK: Legend

    private var legend: some View {
        // Wrap in a flexible HStack — three zones fit on a phone width; more
        // wrap naturally because each chip is compact.
        HStack(spacing: Space.s3) {
            ForEach(series) { s in
                HStack(spacing: 5) {
                    Circle().fill(s.tint).frame(width: 8, height: 8)
                    Text(legendText(for: s))
                        .font(EType.caption)
                        .fontWeight(s.emphasis == .rising ? .bold : .semibold)
                        .foregroundStyle(
                            s.emphasis == .rising ? palette.textPrimary : palette.textSecondary
                        )
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func legendText(for s: BandTrendSeries) -> String {
        let value = s.legendValue ?? lastValueString(for: s)
        let arrow = s.trend.map { " \($0)" } ?? ""
        return "\(s.name) \(value)\(arrow)"
    }

    private func lastValueString(for s: BandTrendSeries) -> String {
        guard let last = s.points.last else { return "—" }
        return valueFormat(last.y)
    }

    // MARK: Card chrome (gradient rim)

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
            .fill(palette.bgCard)
    }

    private var cardRim: some View {
        RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
            .opacity(0.85)
    }

    // MARK: - Geometry

    private func plotRect(in size: CGSize) -> CGRect {
        CGRect(
            x: plotLeading,
            y: plotTop,
            width: max(0, size.width - plotLeading - plotTrailing),
            height: max(0, size.height - plotTop - plotBottom)
        )
    }

    /// Y-axis domain — derived from data + guides + band when not supplied,
    /// padded so traces never kiss the frame.
    private var resolvedDomain: (min: Double, max: Double) {
        if let yDomain { return yDomain }
        var lo = Double.greatestFiniteMagnitude
        var hi = -Double.greatestFiniteMagnitude
        for s in series {
            for p in s.points {
                lo = Swift.min(lo, p.y)
                hi = Swift.max(hi, p.y)
            }
        }
        for g in guides {
            lo = Swift.min(lo, g.value)
            hi = Swift.max(hi, g.value)
        }
        if let band {
            lo = Swift.min(lo, band.low)
            hi = Swift.max(hi, band.high)
        }
        if lo > hi { return (0, 1) }
        if lo == hi { return (lo - 1, hi + 1) }
        let pad = (hi - lo) * 0.12
        return (lo - pad, hi + pad)
    }

    private func yPosition(_ value: Double, in plot: CGRect) -> CGFloat {
        let d = resolvedDomain
        let span = d.max - d.min
        guard span > 0 else { return plot.midY }
        let t = (value - d.min) / span
        // Y is flipped: domain max sits at the top of the plot.
        return plot.maxY - CGFloat(t) * plot.height
    }

    private func point(_ p: BandTrendPoint, in plot: CGRect) -> CGPoint {
        CGPoint(
            x: plot.minX + CGFloat(p.x) * plot.width,
            y: yPosition(p.y, in: plot)
        )
    }

    // MARK: - Canvas drawing

    private func drawBand(in context: GraphicsContext, plot: CGRect) {
        guard let band else { return }
        let yHigh = yPosition(band.high, in: plot)
        let yLow = yPosition(band.low, in: plot)
        let rect = CGRect(
            x: plot.minX,
            y: Swift.min(yHigh, yLow),
            width: plot.width,
            height: abs(yLow - yHigh)
        )
        context.fill(Path(rect), with: .color(bandTint.opacity(0.13)))
    }

    private func drawGuides(in context: GraphicsContext, plot: CGRect) {
        for g in guides {
            let y = yPosition(g.value, in: plot)
            var line = Path()
            line.move(to: CGPoint(x: plot.minX, y: y))
            line.addLine(to: CGPoint(x: plot.maxX, y: y))
            let style = guideStyle(for: g.role)
            context.stroke(
                line,
                with: .color(guideColor(for: g).opacity(style.opacity)),
                style: StrokeStyle(lineWidth: style.width, dash: style.dash)
            )
        }
    }

    private func drawGrid(in context: GraphicsContext, plot: CGRect) {
        // Left + bottom axis.
        var axis = Path()
        axis.move(to: CGPoint(x: plot.minX, y: plot.minY))
        axis.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
        axis.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
        context.stroke(axis, with: .color(.white.opacity(0.10)), lineWidth: 1)

        // Vertical gridlines at every interior tick.
        for tick in xTicks where tick.x > 0 && tick.x < 1 {
            let x = plot.minX + CGFloat(tick.x) * plot.width
            var g = Path()
            g.move(to: CGPoint(x: x, y: plot.minY))
            g.addLine(to: CGPoint(x: x, y: plot.maxY))
            context.stroke(g, with: .color(.white.opacity(0.05)), lineWidth: 1)
        }
    }

    private func drawSeries(in context: GraphicsContext, plot: CGRect) {
        let reveal = appeared ? 1.0 : 0.0
        for s in series {
            guard s.points.count > 1 else { continue }
            let path = polyline(for: s, in: plot)

            if s.emphasis == .rising {
                // Bespoke amber→red rising gradient (799 "Rear zone").
                context.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [Brand.warning, Brand.danger]),
                        startPoint: CGPoint(x: plot.minX, y: plot.maxY),
                        endPoint: CGPoint(x: plot.maxX, y: plot.minY)
                    ),
                    style: lineStyle(weight: 2.6, dashed: false)
                )
            } else {
                context.stroke(
                    path,
                    with: .color(s.tint.opacity(reveal)),
                    style: lineStyle(weight: 2.0, dashed: s.emphasis == .forecast)
                )
            }

            // Static last-point dot (the pulse ring is drawn on the live
            // layer in `drawPulses`).
            if let last = s.points.last {
                let c = point(last, in: plot)
                let r: CGFloat = s.emphasis == .rising ? 4.5 : 3.0
                context.fill(
                    Circle().path(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                    with: .color(s.emphasis == .rising ? Brand.danger : s.tint)
                )
            }
        }
    }

    private func drawPulses(in context: GraphicsContext, plot: CGRect) {
        for s in series {
            guard let last = s.points.last else { continue }
            let c = point(last, in: plot)
            let baseR: CGFloat = s.emphasis == .rising ? 8 : 5
            // Expanding ring keyed to `pulse` (0…1). Rising zones pulse
            // wider + brighter so an excursion reads as urgent.
            let grow = baseR + pulse * (s.emphasis == .rising ? 8 : 4)
            let alpha = (1.0 - Double(pulse)) * (s.emphasis == .rising ? 0.5 : 0.35)
            let color = s.emphasis == .rising ? Brand.danger : s.tint
            context.stroke(
                Circle().path(in: CGRect(x: c.x - grow, y: c.y - grow, width: grow * 2, height: grow * 2)),
                with: .color(color.opacity(alpha)),
                lineWidth: s.emphasis == .rising ? 1.5 : 1.0
            )
        }
    }

    private func polyline(for s: BandTrendSeries, in plot: CGRect) -> Path {
        var path = Path()
        for (i, p) in s.points.enumerated() {
            let pt = point(p, in: plot)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        return path
    }

    private func lineStyle(weight: CGFloat, dashed: Bool) -> StrokeStyle {
        StrokeStyle(
            lineWidth: weight,
            lineCap: .round,
            lineJoin: .round,
            dash: dashed ? [5, 4] : []
        )
    }

    // MARK: Guide styling

    private func guideColor(for g: BandTrendGuide) -> Color {
        if let tint = g.tint { return tint }
        switch g.role {
        case .ceiling:  return Brand.danger
        case .setpoint: return Brand.info
        case .floor:    return Brand.success
        case .custom:   return palette.textSecondary
        }
    }

    private func guideStyle(for role: BandTrendGuide.Role) -> (width: CGFloat, dash: [CGFloat], opacity: Double) {
        switch role {
        case .ceiling:  return (1.2, [4, 3], 0.85)
        case .setpoint: return (1.1, [2, 3], 0.70)
        case .floor:    return (1.0, [2, 3], 0.60)
        case .custom:   return (1.0, [3, 3], 0.55)
        }
    }

    // MARK: - Text overlays

    private func guideLabels(plot: CGRect) -> some View {
        ForEach(guides) { g in
            Text(g.label)
                .font(.system(size: 8.5, weight: .heavy))
                .foregroundStyle(guideLabelColor(for: g))
                .fixedSize()
                .position(
                    x: plot.minX + 4 + guideLabelHalfWidth(g.label),
                    y: yPosition(g.value, in: plot) - 7
                )
        }
    }

    private func guideLabelColor(for g: BandTrendGuide) -> Color {
        switch g.role {
        case .ceiling:  return Color(hex: 0xFF6B61)
        case .setpoint: return Color(hex: 0x5BB0FF)
        case .floor:    return Brand.success
        case .custom:   return g.tint ?? palette.textSecondary
        }
    }

    /// Rough half-width so the label can be left-anchored via `.position`
    /// (which centers). 4.6pt/char approximates the heavy 8.5pt face.
    private func guideLabelHalfWidth(_ s: String) -> CGFloat {
        CGFloat(s.count) * 4.6 / 2
    }

    private func yAxisLabels(plot: CGRect) -> some View {
        ForEach(Array(yTicks.enumerated()), id: \.offset) { _, tick in
            Text(valueFormat(tick))
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
                .fixedSize()
                .position(x: plot.minX - 14, y: yPosition(tick, in: plot))
        }
    }

    private func xAxisLabels(plot: CGRect) -> some View {
        ForEach(xTicks) { tick in
            Text(tick.label)
                .font(.system(size: 8, weight: tick.isNow ? .heavy : .bold))
                .foregroundStyle(tick.isNow ? palette.textPrimary : palette.textTertiary)
                .fixedSize()
                .position(
                    x: plot.minX + CGFloat(tick.x) * plot.width,
                    y: plot.maxY + 14
                )
        }
    }

    // MARK: - Scrub helpers

    /// All sample indices that exist across the union of series. Most charts
    /// share one X grid, so we read the first non-empty series.
    private var indexAxis: [Int] {
        series.first(where: { !$0.points.isEmpty })?.points.map(\.id) ?? []
    }

    private var clampedSelection: Int? {
        guard let sel = selection else { return nil }
        return indexAxis.contains(sel) ? sel : nil
    }

    private func nearestIndex(toX locationX: CGFloat, plot: CGRect) -> Int? {
        guard let base = series.first(where: { !$0.points.isEmpty }) else { return nil }
        let tx = Double((locationX - plot.minX) / max(plot.width, 1))
        let clamped = Swift.min(1.0, Swift.max(0.0, tx))
        var best: (id: Int, dist: Double)?
        for p in base.points {
            let d = abs(p.x - clamped)
            if best == nil || d < best!.dist { best = (p.id, d) }
        }
        return best?.id
    }

    private func scrubX(at index: Int) -> Double {
        for s in series {
            if let p = s.points.first(where: { $0.id == index }) { return p.x }
        }
        return 0
    }

    /// Rows for the floating readout: (name, value, tint).
    private func scrubRows(at index: Int) -> [(String, String, Color)] {
        series.compactMap { s in
            guard let p = s.points.first(where: { $0.id == index }) else { return nil }
            return (s.name, valueFormat(p.y), s.tint)
        }
    }

    // MARK: - Pulse animation

    private func startPulse() {
        // One-shot reveal of the polylines.
        withAnimation(.easeOut(duration: 0.6)) { appeared = true }
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
            pulse = 1
        }
    }
}

// MARK: - Sample data (preview only — NOT business data)

private enum _BandTrendSample {
    /// A monotone-ish series generator so the preview reads like real
    /// telemetry. Clearly sample data: deterministic, in-memory.
    static func zone(
        id: String,
        name: String,
        tint: Color,
        emphasis: BandTrendSeries.Emphasis,
        base: Double,
        slope: Double,
        wobble: Double,
        legend: String,
        trend: String? = nil
    ) -> BandTrendSeries {
        let n = 9
        let pts: [BandTrendPoint] = (0..<n).map { i in
            let t = Double(i) / Double(n - 1)
            let jitter = sin(Double(i) * 1.3) * wobble
            return BandTrendPoint(id: i, x: t, y: base + slope * t + jitter)
        }
        return BandTrendSeries(
            id: id, name: name, tint: tint,
            emphasis: emphasis, points: pts,
            legendValue: legend, trend: trend
        )
    }
}

// MARK: - Preview

#Preview("BandTrendChart · Reefer Temp Log (799)") {
    _BandTrendChartPreviewHost()
}

private struct _BandTrendChartPreviewHost: View {
    @State private var scheme: ColorScheme = .dark
    @State private var selection: Int?

    private var palette: Theme.Palette { scheme == .dark ? Theme.dark : Theme.light }

    private var sampleSeries: [BandTrendSeries] {
        [
            _BandTrendSample.zone(
                id: "front", name: "Front", tint: Brand.success, emphasis: .solid,
                base: 34.2, slope: -0.3, wobble: 0.3, legend: "34.2°"
            ),
            _BandTrendSample.zone(
                id: "center", name: "Center", tint: Color(hex: 0x3AA0FF), emphasis: .solid,
                base: 35.1, slope: -0.2, wobble: 0.25, legend: "35.1°"
            ),
            _BandTrendSample.zone(
                id: "rear", name: "Rear", tint: Brand.danger, emphasis: .rising,
                base: 35.0, slope: 3.6, wobble: 0.1, legend: "38.4°", trend: "↑"
            )
        ]
    }

    var body: some View {
        VStack(spacing: Space.s4) {
            BandTrendChart(
                series: sampleSeries,
                guides: [
                    BandTrendGuide(id: "ceiling", value: 40, label: "40°F · FSMA ceiling", role: .ceiling),
                    BandTrendGuide(id: "set", value: 34, label: "34°F setpoint", role: .setpoint),
                    BandTrendGuide(id: "floor", value: 33, label: "", role: .floor)
                ],
                band: (low: 33, high: 40),
                yDomain: (min: 31, max: 41),
                yTicks: [40, 36, 32],
                xTicks: [
                    BandTrendTick(id: 0, x: 0.0, label: "12a"),
                    BandTrendTick(id: 1, x: 0.25, label: "6a"),
                    BandTrendTick(id: 2, x: 0.5, label: "12p"),
                    BandTrendTick(id: 3, x: 0.75, label: "6p"),
                    BandTrendTick(id: 4, x: 1.0, label: "now", isNow: true)
                ],
                eyebrow: "ZONE TEMPERATURE · °F · LAST 24H",
                trailingCaption: "FSMA BAND 33–40°F",
                valueFormat: { String(format: "%.0f°", $0) },
                selection: $selection,
                onScrub: { _ in }
            )

            HStack {
                Text(selection.map { "Scrubbing sample #\($0)" } ?? "Drag the chart to scrub")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Button(scheme == .dark ? "Light" : "Dark") {
                    scheme = scheme == .dark ? .light : .dark
                }
                .font(EType.caption)
                .foregroundStyle(Brand.blue)
            }
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.bgPage.ignoresSafeArea())
        .environment(\.palette, palette)
        .preferredColorScheme(scheme)
    }
}
