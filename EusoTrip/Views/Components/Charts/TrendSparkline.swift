//
//  TrendSparkline.swift
//  EusoTrip — BespokeChartKit
//
//  Compact inline micro-trend polyline (no axes). The canonical "sparkline"
//  that lives inside metric tiles across the 2027 wireframes — 225 Shipper
//  Hot Zones, the 640 Rail Diesel Fuel Index hero, fuel-efficiency tiles, and
//  the HOS / MetricTile mini-charts (census plan §primitiveKit: "Sparkline —
//  compact inline micro-trend (no axes). Tiny Canvas polyline + optional
//  last-point dot.").
//
//  Verbatim to the SVG design language extracted from the wireframes:
//    • 640 hero spark  — `<path … stroke="url(#eusoPrimary)" stroke-width=2.5
//                         stroke-linecap=round stroke-linejoin=round>` over an
//                         area fill `url(#sparkArea)` = #1473FF@0.22 → #BE01FF@0.02
//                         (top→bottom), with a last-point `circle r=4.5` filled
//                         by the diagonal gradient and ringed by a 1.5px white
//                         stroke.
//    • 312 / 225 tiles — smaller `<polyline … stroke-width=1.5 linecap=round>`
//                         tinted by a semantic fade: `riskFade` #F44336→#FF7A00
//                         (rising-cost / up-bad) or `clearFade` #00C48C→#2196F3
//                         (clearing / down-good), with an optional wash beneath
//                         (`riskWash` / `clearWash`, 0.16 → 0.04 top→bottom).
//
//  This is a PRIMITIVE: a public, reusable, data-driven SwiftUI View. It owns
//  NO business data — the caller passes a typed `[TrendSparkPoint]` series and
//  the styling knobs. It is INTERACTIVE (tap / drag-scrub to inspect a point
//  via an optional selection @Binding + onScrub closure) and DYNAMIC (the line
//  trim + the dot + the selected-index marker all animate on data / selection
//  change).
//
//  Guardrails: only `import SwiftUI`; no `func` declared inside a Canvas /
//  @ViewBuilder closure (all geometry lives in methods / computed vars);
//  `.frame(width:height:)` everywhere; `reduce(into: 0.0)` for Double sums.
//

import SwiftUI

// MARK: - Public data model

/// One sample in a sparkline series. `value` is plotted on the y-axis; the
/// x-position is derived from the index in the series (sparklines are evenly
/// spaced, no time axis). `label` is surfaced only on scrub (the optional
/// callout) so callers can show "Mon" / "Q3" / "$2.41" etc.
public struct TrendSparkPoint: Identifiable, Equatable {
    public let id: String
    public let value: Double
    public let label: String?

    public init(id: String = UUID().uuidString, value: Double, label: String? = nil) {
        self.id = id
        self.value = value
        self.label = label
    }
}

/// Direction semantics drive the line/area tint. `.auto` resolves the tint
/// from the series itself (last vs. first), where the meaning of "good" can be
/// inverted for cost-style metrics (a fuel-price rise is *bad*).
public enum TrendSparkDirection: Equatable {
    /// Always the iridescent brand gradient (blue→magenta) — neutral metric.
    case brand
    /// Resolve up/down from the data. `risingIsGood` flips the success/danger
    /// mapping for cost-style series (rate rising = bad = danger tint).
    case auto(risingIsGood: Bool)
    /// Force a specific semantic tint regardless of the data.
    case forced(TrendSparkTint)
}

/// The four canonical tints the wireframes use for a sparkline line+wash.
public enum TrendSparkTint: Equatable {
    case brand     // #1473FF → #BE01FF
    case success   // #00C48C → #2196F3   (clearFade — clearing / down-good)
    case danger    // #F44336 → #FF7A00   (riskFade  — rising / up-bad)
    case warning   // #FFA726 → #FFB100
    case info      // #2196F3 → #1473FF
}

// MARK: - TrendSparkline (the primitive)

/// Inline micro-trend polyline with optional area fill + last-point dot and a
/// drag-to-scrub inspector. Drop it into a `MetricTile`, a KPI strip, or a
/// hero card. Data-driven, animated, interactive.
public struct TrendSparkline: View {

    // — Data —
    private let points: [TrendSparkPoint]

    // — Look (defaults reproduce the 640 hero spark) —
    private let direction: TrendSparkDirection
    private let lineWidth: CGFloat
    private let showArea: Bool
    private let showLastDot: Bool
    private let showBaseline: Bool
    private let smooth: Bool

    // — Interaction —
    /// Two-way selection of a sample index. When bound, a vertical marker +
    /// dot tracks the value under the user's finger as they scrub.
    @Binding private var selectedIndex: Int?
    /// Fired continuously while scrubbing (and with `nil` on release) so the
    /// host tile can echo the inspected value into its big numeral.
    private let onScrub: (TrendSparkPoint?) -> Void

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the line draw-on animation (0 → 1 trim) when the data changes.
    @State private var drawProgress: CGFloat = 0
    /// Identity that re-keys the draw animation whenever the underlying series
    /// is replaced (live poll, equipment filter, etc.).
    @State private var seriesKey: Int = 0

    // MARK: Designated init

    /// - Parameters:
    ///   - points: the typed series (no business data baked in).
    ///   - direction: how the line/area is tinted (brand / auto / forced).
    ///   - lineWidth: stroke weight. 2.5 = hero (640), 1.5 = tile (312/225).
    ///   - showArea: paint the gradient wash beneath the line.
    ///   - showLastDot: draw the ringed last-point dot.
    ///   - showBaseline: draw the faint zero-grid hairline.
    ///   - smooth: Catmull-Rom smoothing vs. straight segments.
    ///   - selectedIndex: optional two-way scrub selection.
    ///   - onScrub: optional live scrub callback.
    public init(
        points: [TrendSparkPoint],
        direction: TrendSparkDirection = .brand,
        lineWidth: CGFloat = 2.5,
        showArea: Bool = true,
        showLastDot: Bool = true,
        showBaseline: Bool = false,
        smooth: Bool = true,
        selectedIndex: Binding<Int?> = .constant(nil),
        onScrub: @escaping (TrendSparkPoint?) -> Void = { _ in }
    ) {
        self.points = points
        self.direction = direction
        self.lineWidth = lineWidth
        self.showArea = showArea
        self.showLastDot = showLastDot
        self.showBaseline = showBaseline
        self.smooth = smooth
        self._selectedIndex = selectedIndex
        self.onScrub = onScrub
    }

    // MARK: Derived tint

    private var resolvedTint: TrendSparkTint {
        switch direction {
        case .brand:
            return .brand
        case .forced(let t):
            return t
        case .auto(let risingIsGood):
            guard let first = points.first?.value,
                  let last = points.last?.value,
                  first != last else { return .brand }
            let rising = last > first
            // rising & good → success ; rising & bad → danger ; etc.
            if rising { return risingIsGood ? .success : .danger }
            else      { return risingIsGood ? .danger  : .success }
        }
    }

    /// Two-stop gradient for the LINE stroke (left→right, matching the SVG
    /// `x1=0 → x2=1` fade defs).
    private var lineGradient: LinearGradient {
        let stops: [Color]
        switch resolvedTint {
        case .brand:   stops = [Brand.blue, Brand.magenta]
        case .success: stops = [Brand.success, Brand.info]               // clearFade
        case .danger:  stops = [Brand.danger, Color(hex: 0xFF7A00)]      // riskFade
        case .warning: stops = [Brand.warning, Brand.hazmat]
        case .info:    stops = [Brand.info, Brand.blue]
        }
        return LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing)
    }

    /// Vertical wash beneath the line (top → bottom, matching `sparkArea` /
    /// `riskWash` / `clearWash` which all run `x1=0 y1=0 → x2=0 y2=1`).
    private var areaGradient: LinearGradient {
        let top: Color
        let bottom: Color
        switch resolvedTint {
        case .brand:
            top = Brand.blue.opacity(0.22);    bottom = Brand.magenta.opacity(0.02)
        case .success:
            top = Brand.success.opacity(0.16); bottom = Brand.info.opacity(0.04)
        case .danger:
            top = Brand.danger.opacity(0.16);  bottom = Color(hex: 0xFF7A00).opacity(0.04)
        case .warning:
            top = Brand.warning.opacity(0.16); bottom = Brand.hazmat.opacity(0.04)
        case .info:
            top = Brand.info.opacity(0.16);    bottom = Brand.blue.opacity(0.04)
        }
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    /// Solid accent used for the last-point dot ring glow + scrub marker.
    private var accentColor: Color {
        switch resolvedTint {
        case .brand:   return Brand.magenta
        case .success: return Brand.success
        case .danger:  return Brand.danger
        case .warning: return Brand.warning
        case .info:    return Brand.info
        }
    }

    // MARK: Geometry helpers (NOT inside any Canvas/@ViewBuilder closure)

    private var valueRange: (min: Double, max: Double) {
        guard let lo = points.map(\.value).min(),
              let hi = points.map(\.value).max() else { return (0, 1) }
        if lo == hi { return (lo - 0.5, hi + 0.5) }   // flat line → center it
        return (lo, hi)
    }

    /// Map a sample into chart space. Insets so the dot/marker never clips.
    private func position(of index: Int, in size: CGSize) -> CGPoint {
        let n = max(points.count - 1, 1)
        let inset: CGFloat = max(lineWidth, 4)
        let usableW = max(size.width - inset * 2, 1)
        let usableH = max(size.height - inset * 2, 1)
        let x = inset + (CGFloat(index) / CGFloat(n)) * usableW
        let r = valueRange
        let t = (points[index].value - r.min) / max(r.max - r.min, 0.0001)
        // y is flipped: high value → top.
        let y = inset + (1 - CGFloat(t)) * usableH
        return CGPoint(x: x, y: y)
    }

    private func linePoints(in size: CGSize) -> [CGPoint] {
        guard points.count > 1 else {
            // single sample → a tiny flat segment so it still reads as a line
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            return [CGPoint(x: c.x - 6, y: c.y), CGPoint(x: c.x + 6, y: c.y)]
        }
        return points.indices.map { position(of: $0, in: size) }
    }

    /// Straight or Catmull-Rom-smoothed stroke path through the samples.
    private func strokePath(in size: CGSize) -> Path {
        let pts = linePoints(in: size)
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        if smooth && pts.count > 2 {
            for i in 1..<pts.count {
                let p0 = pts[max(i - 1, 0)]
                let p1 = pts[i]
                let prev = pts[max(i - 2, 0)]
                let next = pts[min(i + 1, pts.count - 1)]
                let c1 = CGPoint(x: p0.x + (p1.x - prev.x) / 6.0,
                                 y: p0.y + (p1.y - prev.y) / 6.0)
                let c2 = CGPoint(x: p1.x - (next.x - p0.x) / 6.0,
                                 y: p1.y - (next.y - p0.y) / 6.0)
                path.addCurve(to: p1, control1: c1, control2: c2)
            }
        } else {
            for p in pts.dropFirst() { path.addLine(to: p) }
        }
        return path
    }

    /// Closed area path: the stroke, then down to the baseline and back.
    private func areaPath(in size: CGSize) -> Path {
        var path = strokePath(in: size)
        let pts = linePoints(in: size)
        guard let first = pts.first, let last = pts.last else { return Path() }
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.addLine(to: CGPoint(x: first.x, y: size.height))
        path.closeSubpath()
        return path
    }

    private func nearestIndex(toX x: CGFloat, in size: CGSize) -> Int {
        guard !points.isEmpty else { return 0 }
        var best = 0
        var bestDist = CGFloat.greatestFiniteMagnitude
        for i in points.indices {
            let d = abs(position(of: i, in: size).x - x)
            if d < bestDist { bestDist = d; best = i }
        }
        return best
    }

    // MARK: Body

    public var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                if showBaseline { baseline(in: size) }
                if showArea && points.count > 1 {
                    areaPath(in: size)
                        .fill(areaGradient)
                        .opacity(Double(drawProgress))
                }
                // The line draws on via a trim animation. Stroked with the
                // gradient + rounded caps/joins exactly like the SVG path.
                strokePath(in: size)
                    .trimmedPath(from: 0, to: drawProgress)
                    .stroke(lineGradient,
                            style: StrokeStyle(lineWidth: lineWidth,
                                               lineCap: .round,
                                               lineJoin: .round))
                if showLastDot, drawProgress > 0.98 { lastDot(in: size) }
                scrubOverlay(in: size)
            }
            .contentShape(Rectangle())
            .gesture(scrubGesture(in: size))
        }
        .frame(minHeight: 28)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.55), value: seriesKey)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: selectedIndex)
        .onAppear { runDrawAnimation() }
        .onChange(of: points) { _, _ in
            seriesKey &+= 1
            drawProgress = 0
            runDrawAnimation()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trend sparkline")
        .accessibilityValue(accessibilitySummary)
    }

    // MARK: Layers

    private func baseline(in size: CGSize) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: size.height - 0.5))
            p.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
        }
        .stroke(palette.borderFaint, lineWidth: 1)
    }

    private func lastDot(in size: CGSize) -> some View {
        let p = linePoints(in: size).last ?? CGPoint(x: size.width / 2, y: size.height / 2)
        return ZStack {
            // soft glow halo
            Circle()
                .fill(accentColor.opacity(0.30))
                .frame(width: 14, height: 14)
                .blur(radius: 3)
            // diagonal-gradient core (SVG: fill="url(#eusoDiagonal)" r=4.5)
            Circle()
                .fill(LinearGradient.diagonal)
                .frame(width: 9, height: 9)
            // 1.5px white ring (SVG: stroke="#FFFFFF" stroke-width=1.5)
            Circle()
                .strokeBorder(Color.white, lineWidth: 1.5)
                .frame(width: 9, height: 9)
        }
        .position(p)
        .transition(.scale.combined(with: .opacity))
    }

    @ViewBuilder
    private func scrubOverlay(in size: CGSize) -> some View {
        if let idx = selectedIndex, points.indices.contains(idx) {
            let p = position(of: idx, in: size)
            // vertical guide
            Path { path in
                path.move(to: CGPoint(x: p.x, y: 0))
                path.addLine(to: CGPoint(x: p.x, y: size.height))
            }
            .stroke(accentColor.opacity(0.45),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            // inspector dot
            Circle()
                .fill(accentColor)
                .frame(width: 7, height: 7)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5).frame(width: 7, height: 7))
                .position(p)
            // value callout
            if let label = points[idx].label {
                Text(label)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(palette.bgSheet)
                            .overlay(Capsule().strokeBorder(accentColor.opacity(0.5), lineWidth: 1))
                    )
                    .fixedSize()
                    .position(x: min(max(p.x, 18), size.width - 18),
                              y: max(p.y - 14, 8))
            }
        }
    }

    // MARK: Interaction

    private func scrubGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                guard !points.isEmpty else { return }
                let idx = nearestIndex(toX: g.location.x, in: size)
                if selectedIndex != idx { selectedIndex = idx }
                onScrub(points[idx])
            }
            .onEnded { _ in
                selectedIndex = nil
                onScrub(nil)
            }
    }

    private func runDrawAnimation() {
        guard !reduceMotion else { drawProgress = 1; return }
        drawProgress = 0
        withAnimation(.easeOut(duration: 0.7)) { drawProgress = 1 }
    }

    private var accessibilitySummary: String {
        guard let first = points.first?.value, let last = points.last?.value else {
            return "No data"
        }
        let delta = last - first
        let dir = delta > 0 ? "up" : (delta < 0 ? "down" : "flat")
        let pct = first != 0 ? abs(delta / first) * 100 : 0
        return "\(points.count) points, trending \(dir) \(String(format: "%.0f", pct)) percent"
    }
}

// MARK: - DeltaTrendSparkline (tile convenience wrapper)
//
// The MetricTile pairing the census calls out ("KPITileStrip … value + caption
// + optional sparkline/delta"). Bundles the sparkline with a numeric delta
// chip tinted up/down — the exact composition seen on the Hot Zones / fuel
// tiles. Still fully data-driven; renders the host tile's own numeral & label.

public struct DeltaTrendSparkline: View {
    private let title: String
    private let value: String
    private let points: [TrendSparkPoint]
    private let risingIsGood: Bool

    @Environment(\.palette) private var palette
    @State private var scrubIndex: Int? = nil
    @State private var scrubbedLabel: String? = nil

    public init(
        title: String,
        value: String,
        points: [TrendSparkPoint],
        risingIsGood: Bool = true
    ) {
        self.title = title
        self.value = value
        self.points = points
        self.risingIsGood = risingIsGood
    }

    private var deltaPct: Double {
        guard let f = points.first?.value, let l = points.last?.value, f != 0 else { return 0 }
        return (l - f) / abs(f) * 100
    }

    private var deltaTint: Color {
        let rising = deltaPct > 0
        if deltaPct == 0 { return palette.textSecondary }
        let good = rising == risingIsGood
        return good ? Brand.success : Brand.danger
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title.uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(scrubbedLabel ?? value)
                    .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                deltaChip
            }

            TrendSparkline(
                points: points,
                direction: .auto(risingIsGood: risingIsGood),
                lineWidth: 2,
                showArea: true,
                showLastDot: true,
                selectedIndex: $scrubIndex,
                onScrub: { pt in scrubbedLabel = pt?.label }
            )
            .frame(height: 36)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private var deltaChip: some View {
        HStack(spacing: 2) {
            Image(systemName: deltaPct >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 8, weight: .heavy))
            Text("\(String(format: "%.1f", abs(deltaPct)))%")
                .font(EType.mono(.micro))
        }
        .foregroundStyle(deltaTint)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Capsule().fill(deltaTint.opacity(0.14)))
    }
}

// MARK: - Preview (SAMPLE data — clearly a preview)

#Preview("TrendSparkline · Night") {
    // Clearly-sample preview data — NOT shipped business data.
    let fuel: [TrendSparkPoint] = [3.92, 3.88, 4.01, 4.10, 3.97, 4.22, 4.31, 4.28, 4.40, 4.51]
        .enumerated().map { TrendSparkPoint(id: "f\($0.0)",
                                            value: $0.1,
                                            label: String(format: "$%.2f", $0.1)) }
    let clearing: [TrendSparkPoint] = [72, 68, 64, 59, 61, 54, 48, 44, 39, 33]
        .enumerated().map { TrendSparkPoint(id: "c\($0.0)",
                                            value: Double($0.1),
                                            label: "\($0.1)%") }

    return ScrollView {
        VStack(spacing: Space.s4) {
            Text("BespokeChartKit · TrendSparkline")
                .font(EType.h2)
                .foregroundStyle(Theme.dark.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Hero spark (640 Fuel Index look) — brand gradient, big dot.
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("DIESEL FUEL INDEX")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(Theme.dark.textTertiary)
                Text("$4.51 / gal")
                    .font(EType.numeric)
                    .foregroundStyle(LinearGradient.diagonal)
                TrendSparkline(points: fuel, direction: .brand, lineWidth: 2.5)
                    .frame(height: 72)
            }
            .padding(Space.s4)
            .eusoCard(radius: Radius.lg, intensity: .feature)

            // Tile pair (225 Hot Zones look) — auto-tinted + scrub + delta.
            HStack(spacing: Space.s3) {
                DeltaTrendSparkline(title: "Spot Rate / mi",
                                    value: "$4.51",
                                    points: fuel,
                                    risingIsGood: false)   // cost rising = bad
                DeltaTrendSparkline(title: "Risk Pulse",
                                    value: "33%",
                                    points: clearing,
                                    risingIsGood: false)   // risk falling = good
            }

            // Drag across either tile to scrub the value.
            Text("Drag across a sparkline to scrub →")
                .font(EType.caption)
                .foregroundStyle(Theme.dark.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Space.s4)
    }
    .background(Theme.dark.bgPage)
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("TrendSparkline · Afternoon") {
    let series: [TrendSparkPoint] = [12, 18, 15, 22, 19, 27, 24, 31, 35, 33, 41]
        .enumerated().map { TrendSparkPoint(id: "a\($0.0)",
                                            value: Double($0.1),
                                            label: "\($0.1)") }
    return VStack(spacing: Space.s4) {
        DeltaTrendSparkline(title: "Loads Delivered",
                            value: "41",
                            points: series,
                            risingIsGood: true)
        TrendSparkline(points: series,
                       direction: .forced(.info),
                       lineWidth: 2,
                       showBaseline: true)
            .frame(height: 44)
            .padding(Space.s4)
            .eusoCard()
    }
    .padding(Space.s4)
    .background(Theme.light.bgPage)
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
