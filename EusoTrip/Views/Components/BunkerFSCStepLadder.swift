//
//  BunkerFSCStepLadder.swift
//  EusoTrip — Bunker Fuel-Surcharge Stepped-Ladder chart (proof "685 Bunker FSC").
//
//  A vessel/ocean Bunker Adjustment Factor (BAF) schedule reads as a step
//  function: each bracket of the bunker index ($/MT — the price of Very Low
//  Sulfur Fuel Oil at a benchmark hub like Singapore / Rotterdam) maps to a
//  flat fuel-surcharge percentage applied to the base freight rate. As the
//  index climbs through brackets the surcharge ratchets up, never down — a
//  monotonic staircase.
//
//  This component draws that staircase left→right and highlights the ACTIVE
//  bracket the live index ($712/MT in the proof) currently sits inside. The
//  active step is filled with the brand blue→magenta diagonal gradient and
//  carries a pill marker ("$712") dropped to the x-axis on a dashed line, so
//  an operator can read "we are in the 650–750 step → 6% surcharge" at a
//  glance.
//
//  Domain note: BAF/FSC is typically expressed either as $/revenue-ton or as
//  a percentage of base rate, indexed to bunker price brackets. Carriers don't
//  share one universal table, so the schedule is supplied by the caller — this
//  view only renders + animates whatever bracket table it's handed.
//
//  ── Animation ──────────────────────────────────────────────────────────
//   • The staircase DRAWS in left→right: each step's riser+tread extends in
//     sequence (~0.12s/step on a cubic-bezier(0.4, 0, 0.2, 1) curve).
//   • Once the active bracket is reached its gradient fill SWEEPS up from the
//     baseline, and the "$712" marker SETTLES onto the active tread with a
//     small spring.
//   • A soft highlight pulse sits behind the active step.
//   • Reduce Motion: the full ladder is drawn instantly, the fill is placed,
//     the marker is placed — no sweep, no spring, no pulse.
//
//  Matches the app design system (Brand / Space / Radius / EType / palette,
//  LinearGradient.diagonal) and the Canvas/Path drawing + TimelineView idiom
//  used by sibling Components (see LoadingParticleField, TileReveal).
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Data model

/// One bracket of a bunker fuel-surcharge schedule: the index spans
/// `[indexFrom, indexTo)` in $/MT and applies a flat `surchargePct`
/// (a percentage of base freight) while the live index sits inside it.
public struct BunkerFSCStep: Identifiable, Equatable {
    public let id = UUID()
    /// Lower bound of the bunker index bracket, in $/MT (inclusive).
    public var indexFrom: Double
    /// Upper bound of the bunker index bracket, in $/MT (exclusive — except
    /// the final, open-ended bracket which is treated as inclusive at its top).
    public var indexTo: Double
    /// Flat fuel surcharge applied while the index is in this bracket,
    /// expressed as a percentage (e.g. `6.0` → 6%).
    public var surchargePct: Double

    public init(indexFrom: Double, indexTo: Double, surchargePct: Double) {
        self.indexFrom = indexFrom
        self.indexTo = indexTo
        self.surchargePct = surchargePct
    }
}

// MARK: - View

/// Bunker fuel-surcharge stepped-ladder chart. Renders a monotonic staircase
/// mapping bunker index ($/MT) → surcharge %, highlights the bracket the live
/// `activeIndex` falls in, and drops a labeled pill marker to the x-axis.
///
/// ```swift
/// BunkerFSCStepLadder(
///     steps: [
///         .init(indexFrom: 450, indexTo: 550, surchargePct: 2.0),
///         .init(indexFrom: 550, indexTo: 650, surchargePct: 3.5),
///         .init(indexFrom: 650, indexTo: 750, surchargePct: 5.0),
///         .init(indexFrom: 750, indexTo: 850, surchargePct: 6.0),
///         .init(indexFrom: 850, indexTo: 950, surchargePct: 8.0),
///     ],
///     activeIndex: 712,
///     markerLabel: "$712"
/// )
/// ```
public struct BunkerFSCStepLadder: View {

    // Inputs
    private let steps: [BunkerFSCStep]
    private let activeIndex: Double
    private let markerLabel: String
    private let height: CGFloat

    // Per-step draw cadence — cubic-bezier(0.4, 0, 0.2, 1) ≈ Material "standard".
    private let perStep: Double = 0.12

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 0…stepCount progress of the left→right staircase draw. A fractional
    /// value means a step is mid-extend.
    @State private var drawProgress: CGFloat = 0
    /// 0…1 vertical sweep of the active bracket's gradient fill.
    @State private var fillSweep: CGFloat = 0
    /// Marker settle (false = lifted/transparent, true = seated).
    @State private var markerSeated: Bool = false

    public init(
        steps: [BunkerFSCStep] = BunkerFSCStepLadder.proofSchedule,
        activeIndex: Double = 712,
        markerLabel: String = "$712",
        height: CGFloat = 240
    ) {
        // Defensive: keep brackets sorted by lower bound so the staircase is
        // monotonic in x regardless of caller ordering.
        self.steps = steps.sorted { $0.indexFrom < $1.indexFrom }
        self.activeIndex = activeIndex
        self.markerLabel = markerLabel
        self.height = height
    }

    // MARK: Derived domain geometry

    /// Index of the active bracket within `steps`, or nil if the live index
    /// falls outside the whole schedule.
    private var activeStepIndex: Int? {
        guard !steps.isEmpty else { return nil }
        for (i, s) in steps.enumerated() {
            let isLast = (i == steps.count - 1)
            if activeIndex >= s.indexFrom && (activeIndex < s.indexTo || (isLast && activeIndex <= s.indexTo)) {
                return i
            }
        }
        // Below the floor → clamp to first; above the ceiling → clamp to last.
        if activeIndex < (steps.first?.indexFrom ?? 0) { return 0 }
        return steps.count - 1
    }

    /// X-axis domain in $/MT.
    private var xDomain: ClosedRange<Double> {
        let lo = steps.first?.indexFrom ?? 0
        let hi = steps.last?.indexTo ?? 1
        return lo...max(hi, lo + 1)
    }

    /// Y-axis domain in surcharge %. Floored at 0, headroom above the max.
    private var yDomain: ClosedRange<Double> {
        let maxPct = steps.map(\.surchargePct).max() ?? 1
        return 0...(maxPct * 1.18)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            header
            chart
                .frame(height: height)
            legend
        }
        .padding(Space.s4)
        .eusoCard()
        .onAppear(perform: runIntro)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bunker Fuel Surcharge")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                Text("BAF schedule · indexed to $/MT")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: Space.s2)
            if let i = activeStepIndex {
                HStack(spacing: 6) {
                    Text(markerLabel)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textOnGradient)
                    Text(pctString(steps[i].surchargePct))
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textOnGradient)
                }
                .padding(.horizontal, Space.s3)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(LinearGradient.diagonal)
                )
            }
        }
    }

    // MARK: Chart canvas

    private var chart: some View {
        GeometryReader { geo in
            let plot = plotRect(in: geo.size)
            ZStack(alignment: .topLeading) {
                // Grid + axis frame + tick labels.
                axisLayer(plot: plot, full: geo.size)

                // The staircase + active fill + marker, animated.
                ladderLayer(plot: plot)
            }
        }
    }

    // MARK: Axis layer (static — grid, frame, ticks)

    private func axisLayer(plot: CGRect, full: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            // Horizontal gridlines at each surcharge level present in the table.
            Canvas { ctx, _ in
                // Baseline + left axis.
                var axis = Path()
                axis.move(to: CGPoint(x: plot.minX, y: plot.minY))
                axis.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
                axis.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
                ctx.stroke(axis, with: .color(palette.borderSoft), lineWidth: 1)

                // Faint horizontal gridline per distinct surcharge level.
                let levels = Set(steps.map(\.surchargePct)).sorted()
                for pct in levels {
                    let y = yToPoint(pct, in: plot)
                    var line = Path()
                    line.move(to: CGPoint(x: plot.minX, y: y))
                    line.addLine(to: CGPoint(x: plot.maxX, y: y))
                    ctx.stroke(
                        line,
                        with: .color(palette.borderFaint),
                        style: StrokeStyle(lineWidth: 1, dash: [2, 4])
                    )
                }
            }

            // Y tick labels (surcharge %) — placed to the left of the plot.
            ForEach(Array(Set(steps.map(\.surchargePct)).sorted()), id: \.self) { pct in
                Text(pctString(pct))
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize()
                    .position(
                        x: plot.minX - 16,
                        y: yToPoint(pct, in: plot)
                    )
            }

            // X tick labels (bunker index $/MT) — at each bracket boundary.
            ForEach(xTickValues, id: \.self) { v in
                Text("\(Int(v))")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize()
                    .position(
                        x: xToPoint(v, in: plot),
                        y: plot.maxY + 12
                    )
            }

            // Axis captions.
            Text("$/MT")
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary.opacity(0.8))
                .position(x: plot.maxX - 4, y: plot.maxY + 12)

            Text("FSC %")
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary.opacity(0.8))
                .position(x: plot.minX - 14, y: plot.minY - 10)
        }
    }

    // MARK: Ladder layer (animated — staircase, fill, highlight, marker)

    private func ladderLayer(plot: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            // Soft highlight behind the active step.
            if let ai = activeStepIndex {
                let r = stepRect(ai, in: plot)
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(Brand.magenta.opacity(0.10))
                    .frame(width: r.width, height: r.height)
                    .position(x: r.midX, y: r.midY)
                    .opacity(activeRevealed ? (reduceMotion ? 1 : highlightOpacity) : 0)
                    .blur(radius: reduceMotion ? 0 : 6)
            }

            // Active bracket gradient fill (sweeps up).
            if let ai = activeStepIndex {
                let r = stepRect(ai, in: plot)
                let sweep = reduceMotion ? 1 : fillSweep
                let filledHeight = r.height * sweep
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient.diagonal)
                    .frame(width: r.width, height: max(0, filledHeight))
                    .opacity(activeRevealed ? 1 : 0)
                    // Pin the bottom of the fill to the tread baseline so it
                    // grows upward.
                    .position(x: r.midX, y: r.maxY - filledHeight / 2)
                    .clipped()
            }

            // The staircase outline (draws in left→right via TimelineView).
            TimelineView(.animation) { _ in
                Canvas { ctx, _ in
                    let p = staircasePath(in: plot, progress: drawProgress)
                    // Glow underlay.
                    ctx.stroke(
                        p,
                        with: .color(Brand.blue.opacity(0.35)),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                    )
                    // Crisp top line.
                    ctx.stroke(
                        p,
                        with: .linearGradient(
                            Gradient(colors: [Brand.blue, Brand.magenta]),
                            startPoint: CGPoint(x: plot.minX, y: plot.midY),
                            endPoint: CGPoint(x: plot.maxX, y: plot.midY)
                        ),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )
                }
            }

            // Dashed vertical drop-line + pill marker for the active index.
            if let ai = activeStepIndex {
                markerOverlay(activeStep: ai, plot: plot)
            }
        }
    }

    // MARK: Marker overlay

    private func markerOverlay(activeStep ai: Int, plot: CGRect) -> some View {
        let x = xToPoint(clampedActiveIndex, in: plot)
        let treadY = yToPoint(steps[ai].surchargePct, in: plot)
        let settledY = treadY
        let liftedY = treadY - 22
        let y = (reduceMotion || markerSeated) ? settledY : liftedY

        return ZStack {
            // Dashed drop-line from the active tread to the x-axis.
            Path { p in
                p.move(to: CGPoint(x: x, y: treadY))
                p.addLine(to: CGPoint(x: x, y: plot.maxY))
            }
            .stroke(
                Brand.magenta.opacity(0.9),
                style: StrokeStyle(lineWidth: 1.5, dash: [3, 4])
            )
            .opacity(activeRevealed ? 1 : 0)

            // Anchor dot where the index meets the tread.
            Circle()
                .fill(palette.bgCard)
                .overlay(Circle().stroke(LinearGradient.diagonal, lineWidth: 2))
                .frame(width: 9, height: 9)
                .position(x: x, y: treadY)
                .opacity(activeRevealed ? 1 : 0)

            // The "$712" pill — settles onto the tread with a spring.
            Text(markerLabel)
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textOnGradient)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(LinearGradient.diagonal)
                        .shadow(color: Brand.magenta.opacity(0.45), radius: 6, y: 2)
                )
                .position(x: x, y: y - 16)
                .opacity(activeRevealed ? (reduceMotion || markerSeated ? 1 : 0.0) : 0)
                .scaleEffect(reduceMotion || markerSeated ? 1 : 0.6, anchor: .bottom)
        }
        .allowsHitTesting(false)
    }

    // MARK: Legend

    private var legend: some View {
        HStack(spacing: Space.s4) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient.diagonal)
                    .frame(width: 14, height: 8)
                Text("Active bracket")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            if let ai = activeStepIndex {
                Text("\(Int(steps[ai].indexFrom))–\(Int(steps[ai].indexTo)) $/MT")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
        }
    }

    // MARK: - Intro animation

    private func runIntro() {
        let stepCount = steps.count
        guard stepCount > 0 else { return }

        if reduceMotion {
            // Static drawn ladder, fill placed, marker placed — no sweep/spring.
            drawProgress = CGFloat(stepCount)
            fillSweep = 1
            markerSeated = true
            return
        }

        // 1. Draw the staircase left→right, one step at a time.
        // cubic-bezier(0.4, 0, 0.2, 1) ≈ Material standard easing.
        let total = perStep * Double(stepCount)
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: total)) {
            drawProgress = CGFloat(stepCount)
        }

        // 2. When the draw reaches the active bracket, sweep the fill up.
        let activeReachedAt = perStep * Double((activeStepIndex ?? 0) + 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + activeReachedAt) {
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.45)) {
                fillSweep = 1
            }
            // 3. Marker settles onto the tread with a small spring shortly after.
            withAnimation(.spring(response: 0.45, dampingFraction: 0.62).delay(0.18)) {
                markerSeated = true
            }
        }
    }

    /// Whether the staircase draw has progressed past the active bracket,
    /// gating the fill/marker/highlight reveal.
    private var activeRevealed: Bool {
        guard let ai = activeStepIndex else { return false }
        return drawProgress >= CGFloat(ai) + 0.85
    }

    /// Subtle pulse on the highlight, derived from the seated state.
    private var highlightOpacity: Double { markerSeated ? 1 : 0.5 }

    // MARK: - Geometry helpers

    /// Inset plot rect inside the canvas — leaves room for axis labels.
    private func plotRect(in size: CGSize) -> CGRect {
        let leftGutter: CGFloat = 34   // y tick labels
        let bottomGutter: CGFloat = 26 // x tick labels
        let topGutter: CGFloat = 16    // y caption headroom
        let rightGutter: CGFloat = 12
        return CGRect(
            x: leftGutter,
            y: topGutter,
            width: max(0, size.width - leftGutter - rightGutter),
            height: max(0, size.height - topGutter - bottomGutter)
        )
    }

    private func xToPoint(_ v: Double, in plot: CGRect) -> CGFloat {
        let lo = xDomain.lowerBound, hi = xDomain.upperBound
        let t = (v - lo) / (hi - lo)
        return plot.minX + CGFloat(t) * plot.width
    }

    private func yToPoint(_ pct: Double, in plot: CGRect) -> CGFloat {
        let lo = yDomain.lowerBound, hi = yDomain.upperBound
        let t = (pct - lo) / (hi - lo)
        return plot.maxY - CGFloat(t) * plot.height
    }

    /// Bounding rect of one step's bracket region (from its tread down to the
    /// baseline), used for the gradient fill + highlight.
    private func stepRect(_ i: Int, in plot: CGRect) -> CGRect {
        let s = steps[i]
        let x0 = xToPoint(s.indexFrom, in: plot)
        let x1 = xToPoint(s.indexTo, in: plot)
        let yTop = yToPoint(s.surchargePct, in: plot)
        return CGRect(x: x0, y: yTop, width: x1 - x0, height: plot.maxY - yTop)
    }

    /// Live index clamped into the rendered x-domain so the marker never
    /// escapes the plot.
    private var clampedActiveIndex: Double {
        min(max(activeIndex, xDomain.lowerBound), xDomain.upperBound)
    }

    /// X tick values: each bracket boundary (deduplicated).
    private var xTickValues: [Double] {
        var vals = steps.map(\.indexFrom)
        if let last = steps.last { vals.append(last.indexTo) }
        // Deduplicate while preserving order.
        var seen = Set<Double>()
        return vals.filter { seen.insert($0).inserted }
    }

    /// Builds the staircase as a single path, extending up to `progress`
    /// steps. A fractional progress partially extends the current step's
    /// riser then tread, producing the left→right "draws in" reveal.
    private func staircasePath(in plot: CGRect, progress: CGFloat) -> Path {
        var path = Path()
        guard !steps.isEmpty else { return path }

        // Start at the baseline under the first bracket's left edge.
        var pen = CGPoint(x: xToPoint(steps[0].indexFrom, in: plot), y: plot.maxY)
        path.move(to: pen)

        for (i, s) in steps.enumerated() {
            let stepStart = CGFloat(i)
            // How much of THIS step (0…1) is revealed.
            let local = max(0, min(1, progress - stepStart))
            if local <= 0 { break }

            let treadY = yToPoint(s.surchargePct, in: plot)
            let x0 = xToPoint(s.indexFrom, in: plot)
            let x1 = xToPoint(s.indexTo, in: plot)

            // Split each step's reveal: first ~30% raises the riser to the new
            // tread height, remaining ~70% extends the tread rightward.
            let riserFrac = min(1, local / 0.3)
            let treadFrac = max(0, (local - 0.3) / 0.7)

            // Riser: from current pen y up to treadY.
            let curY = pen.y + (treadY - pen.y) * riserFrac
            path.addLine(to: CGPoint(x: x0, y: curY))
            pen = CGPoint(x: x0, y: curY)

            if riserFrac >= 1 {
                // Tread: extend rightward as treadFrac fills.
                let curX = x0 + (x1 - x0) * treadFrac
                path.addLine(to: CGPoint(x: curX, y: treadY))
                pen = CGPoint(x: curX, y: treadY)
            }
        }
        return path
    }

    // MARK: - Formatting / a11y

    private func pctString(_ pct: Double) -> String {
        if pct == pct.rounded() {
            return "\(Int(pct))%"
        }
        return String(format: "%.1f%%", pct)
    }

    private var accessibilitySummary: String {
        guard let ai = activeStepIndex else {
            return "Bunker fuel surcharge ladder. Live index \(markerLabel) is outside the schedule."
        }
        let s = steps[ai]
        return "Bunker fuel surcharge ladder. Live bunker index \(markerLabel) per metric ton "
            + "is in the \(Int(s.indexFrom)) to \(Int(s.indexTo)) dollar bracket, "
            + "applying a \(pctString(s.surchargePct)) fuel surcharge."
    }

    // MARK: - Defaults

    /// The proof "685 Bunker FSC" schedule: 450 → 950 $/MT in $100 brackets
    /// ratcheting 2% → 3.5% → 5% → 6% → 8%.
    public static let proofSchedule: [BunkerFSCStep] = [
        .init(indexFrom: 450, indexTo: 550, surchargePct: 2.0),
        .init(indexFrom: 550, indexTo: 650, surchargePct: 3.5),
        .init(indexFrom: 650, indexTo: 750, surchargePct: 5.0),
        .init(indexFrom: 750, indexTo: 850, surchargePct: 6.0),
        .init(indexFrom: 850, indexTo: 950, surchargePct: 8.0),
    ]
}

// MARK: - Preview

#Preview("Bunker FSC · $712 @ 650–750 step") {
    ZStack {
        Color(hex: 0x030309).ignoresSafeArea()
        BunkerFSCStepLadder(
            steps: BunkerFSCStepLadder.proofSchedule,
            activeIndex: 712,
            markerLabel: "$712"
        )
        .padding(Space.s4)
    }
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}
