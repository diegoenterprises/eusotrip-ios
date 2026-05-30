//
//  FunnelBars.swift
//  EusoTrip 2027 · BespokeChartKit
//
//  A descending stage funnel: tapering, center-aligned bars (one per stage)
//  carrying a stage label, an absolute count, and a stage-to-stage conversion
//  %, with faint connector trapezoids bridging each step — paired with a
//  streak / clean-day hero chip (a big gradient day-count + a shield-clock
//  "free rate" badge). Canonical look ported verbatim from wireframe
//  483 Dispatcher Comms Escalation-Free Detail (Dark · TRUCK).
//
//  It is the comms escalation funnel primitive: OPENED → FLAGGED → ESCALATED,
//  plus "days clean" as a streak the dispatcher protects.
//
//  PRIMITIVE CONTRACT
//  ------------------
//  • PUBLIC, reusable, data-driven. No hardcoded business data lives inside —
//    every label, count, color, %, and streak figure arrives via the typed
//    `FunnelBarsModel`. Feed it any descending funnel (sales pipeline, claims
//    triage, lead-to-close, defect escalation …), not just comms.
//  • INTERACTIVE: tap a stage to select it (`selection` @Binding + `onSelect`),
//    or drag-scrub vertically across the stack to sweep the selection. The
//    selected stage lifts with a gradient focus ring + its connector brightens.
//  • DYNAMIC: bars animate their taper-width in from zero on first paint and
//    re-spring whenever the model's counts change; selection transitions are
//    animated. A #Preview at the bottom feeds clearly-sample data and drives a
//    live selection so the component renders alive.
//
//  GUARDRAILS: only SwiftUI. No `func` inside ViewBuilder/Canvas closures.
//  .frame(width:height:) only. reduce(into: 0.0) for Doubles. Every helper
//  type is private + suffixed to avoid cross-file collisions.
//

import SwiftUI

// MARK: - Public data model

/// One stage in a descending funnel. `count` is the absolute volume that
/// reached this stage; `tint` is the semantic color of the bar (the first
/// stage is typically rendered with the iridescent brand gradient — see
/// `FunnelBarsModel.usesBrandGradientForFirstStage`).
public struct FunnelStage: Identifiable, Equatable {
    public let id: String
    /// Left-hand row label, e.g. "Opened" / "Flagged" / "Escalated".
    public let label: String
    /// Absolute count that reached this stage. Drives bar width.
    public let count: Int
    /// Optional caption shown inside / beside the count, e.g. "threads".
    /// Pass an empty string to render the bare number (matches stages 2/3
    /// in 483 which show only "5" and "1").
    public let unit: String
    /// Semantic bar color. The first stage usually ignores this in favor of
    /// the brand gradient; deeper stages use warning/danger tints.
    public let tint: Color

    public init(id: String, label: String, count: Int, unit: String = "", tint: Color) {
        self.id = id
        self.label = label
        self.count = count
        self.unit = unit
        self.tint = tint
    }
}

/// The streak / clean-day hero chip that sits above the funnel.
public struct FunnelStreak: Equatable {
    /// Current consecutive clean days (the streak the operator protects).
    public let daysClean: Int
    /// Eyebrow over the numeral, e.g. "CURRENT STREAK · DAYS WITHOUT AN ESCALATION".
    public let eyebrow: String
    /// Sub-line under the numeral, e.g. "clean since Apr 30 · personal best 34d".
    public let subtitle: String
    /// The "free rate" headline shown inside the shield badge, e.g. "97.9%".
    public let freeRateLabel: String
    /// Small line under the free rate, e.g. "46 / 47 clean".
    public let freeRateDetail: String

    public init(daysClean: Int,
                eyebrow: String,
                subtitle: String,
                freeRateLabel: String,
                freeRateDetail: String) {
        self.daysClean = daysClean
        self.eyebrow = eyebrow
        self.subtitle = subtitle
        self.freeRateLabel = freeRateLabel
        self.freeRateDetail = freeRateDetail
    }
}

/// Full data envelope for `FunnelBars`. The funnel header + ordered stages +
/// optional streak chip. Stages MUST be supplied in descending order (top =
/// widest). The primitive does not sort — order is meaningful (it is the
/// stage sequence).
public struct FunnelBarsModel: Equatable {
    /// Card eyebrow over the funnel, e.g.
    /// "ESCALATION FUNNEL · 90D · OPENED → FLAGGED → ESCALATED".
    public let title: String
    /// Ordered, descending stages. First is the 100% baseline.
    public let stages: [FunnelStage]
    /// Optional streak chip. When nil, only the funnel card renders.
    public let streak: FunnelStreak?
    /// When true (default) the first/widest stage paints with the brand
    /// iridescent gradient regardless of its `tint`, matching 483's
    /// blue→magenta "Opened" band. Deeper stages always use their `tint`.
    public let usesBrandGradientForFirstStage: Bool

    public init(title: String,
                stages: [FunnelStage],
                streak: FunnelStreak? = nil,
                usesBrandGradientForFirstStage: Bool = true) {
        self.title = title
        self.stages = stages
        self.streak = streak
        self.usesBrandGradientForFirstStage = usesBrandGradientForFirstStage
    }
}

// MARK: - FunnelBars (the primitive)

/// Descending stage-funnel chart + streak chip. Verbatim to wireframe 483.
///
///     FunnelBars(
///         model: model,
///         selection: $selectedStageID,
///         onSelect: { stage in … }
///     )
///
/// - `selection` is an optional stage-id binding. Tap a bar to set it; tap the
///   same bar again to clear. Drag vertically to scrub the selection across
///   stages. Pass `.constant(nil)` for a non-interactive read-only funnel.
/// - `onSelect` fires with the resolved stage (or nil on clear) on every
///   selection change, for call-sites that prefer a closure over the binding.
public struct FunnelBars: View {
    private let model: FunnelBarsModel
    @Binding private var selection: String?
    private let onSelect: (FunnelStage?) -> Void

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 0 → 1 grow-in driver for the bar taper widths. Animates on appear and
    /// whenever the model changes so the funnel "draws" itself.
    @State private var grow: CGFloat = 0
    /// Identity used to re-trigger the grow-in when the data set changes.
    @State private var renderedStageKey: String = ""

    public init(model: FunnelBarsModel,
                selection: Binding<String?> = .constant(nil),
                onSelect: @escaping (FunnelStage?) -> Void = { _ in }) {
        self.model = model
        self._selection = selection
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: Space.s4) {
            if let streak = model.streak {
                streakChip(streak)
            }
            funnelCard
        }
        .onAppear { startGrow(for: stageKey) }
        .onChange(of: stageKey) { _, key in startGrow(for: key) }
    }

    // MARK: Streak hero chip

    @ViewBuilder
    private func streakChip(_ s: FunnelStreak) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(s.eyebrow.uppercased())
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                // Big gradient day-count + small "d" suffix (483 line 57).
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(s.daysClean)")
                        .font(.system(size: 48, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                        .contentTransition(.numericText())
                    Text("d")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                }
                .animation(reduceMotion ? nil : .snappy, value: s.daysClean)

                Text(s.subtitle)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer(minLength: Space.s2)

            _ShieldFreeRateBadge483(
                freeRate: s.freeRateLabel,
                detail: s.freeRateDetail,
                palette: palette
            )
        }
        .padding(Space.s5)
        .eusoCard(radius: Radius.xl, intensity: .feature)
    }

    // MARK: Funnel card

    private var funnelCard: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(model.title.uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            // The stage stack. GeometryReader gives the taper math a concrete
            // width so the widest stage fills the row and deeper stages center-
            // taper proportionally to count.
            GeometryReader { geo in
                stageStack(in: geo.size.width)
            }
            // Fixed, deterministic height: per-stage rows + inter-stage
            // connector bands. Keeps the GeometryReader from collapsing.
            .frame(height: stackHeight)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.xl, intensity: .standard)
    }

    @ViewBuilder
    private func stageStack(in width: CGFloat) -> some View {
        ZStack(alignment: .top) {
            // Connector trapezoids between consecutive stages, drawn behind
            // the bars so the bars sit on top of their funnel "waist".
            ForEach(connectorIndices, id: \.self) { i in
                _ConnectorTaper483(
                    topWidth: barWidth(for: i, in: width) * grow,
                    bottomWidth: barWidth(for: i + 1, in: width) * grow,
                    fill: connectorFill(for: i),
                    maxWidth: width
                )
                .frame(width: width, height: _Geom483.connector)
                .offset(y: connectorYOffset(i))
            }

            // The stage bars themselves.
            ForEach(Array(model.stages.enumerated()), id: \.element.id) { idx, stage in
                stageRow(stage, index: idx, totalWidth: width)
                    .offset(y: rowYOffset(idx))
            }
        }
        // One scrub gesture spanning the whole stack so a vertical drag sweeps
        // the selection across stages (the SVG implies a touch-to-inspect
        // funnel; we make it a live scrub).
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in scrub(to: value.location.y) }
        )
    }

    @ViewBuilder
    private func stageRow(_ stage: FunnelStage, index: Int, totalWidth: CGFloat) -> some View {
        let w = barWidth(for: index, in: totalWidth) * grow
        let isSelected = selection == stage.id
        let isFirst = index == 0

        ZStack {
            // Center-tapered, rounded bar. First stage = brand gradient.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(barStyle(for: stage, isFirst: isFirst))
                .frame(width: max(w, _Geom483.minBar), height: barHeight(index))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal,
                                      lineWidth: isSelected ? 1.6 : 0)
                        .opacity(isSelected ? 1 : 0)
                )
                .shadow(color: isSelected ? stage.tint.opacity(0.45) : .clear,
                        radius: isSelected ? 10 : 0, y: 2)

            // Count text centered in the bar (483 lines 87/92/97).
            Text(countText(stage))
                .font(.system(size: 12, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(.white)
                .opacity(grow)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        // Left label + right conversion %, overlaid on the full row width so
        // they pin to the row edges regardless of the centered bar width.
        .frame(width: totalWidth, height: barHeight(index))
        .overlay(alignment: .leading) {
            Text(stage.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? palette.textPrimary : palette.textSecondary)
        }
        .overlay(alignment: .trailing) {
            Text(conversionText(index))
                .font(.system(size: 10, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(isFirst ? Brand.blue : stage.tint)
                .opacity(grow)
        }
        .scaleEffect(isSelected ? 1.015 : 1.0, anchor: .center)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture { toggle(stage) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stage.label)
        .accessibilityValue(accessibilityValue(stage, index: index))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Geometry / taper math

    /// Bar width for a stage, proportional to its count vs. the first
    /// (baseline) stage. Clamped to a readable minimum so a "1 of 47" bar is
    /// still tappable. Excludes the grow factor — callers multiply by `grow`.
    private func barWidth(for index: Int, in totalWidth: CGFloat) -> CGFloat {
        guard model.stages.indices.contains(index) else { return 0 }
        let count = Double(model.stages[index].count)
        let usable = max(totalWidth - _Geom483.sidePad * 2, 1)
        let ratio = baseline > 0 ? count / baseline : 0
        let raw = usable * CGFloat(ratio)
        let floor = max(_Geom483.minBar, usable * _Geom483.minRatio)
        return min(max(raw, floor), usable)
    }

    /// The baseline count = the largest stage (top of the funnel).
    private var baseline: Double {
        let counts = model.stages.map { Double($0.count) }
        return counts.max() ?? 0
    }

    private func barHeight(_ index: Int) -> CGFloat {
        // Gentle taper in HEIGHT too (28 → 24), echoing 483's 28/26/24 bands.
        let h = _Geom483.barTop - CGFloat(index) * _Geom483.barShrink
        return max(h, _Geom483.barMin)
    }

    /// Y position of stage row `idx` within the stack.
    private func rowYOffset(_ idx: Int) -> CGFloat {
        CGFloat(idx) * (_Geom483.barTop + _Geom483.connector)
            + (_Geom483.barTop - barHeight(idx)) / 2
    }

    /// Y offset for the connector band that bridges stage `i` → `i+1`.
    private func connectorYOffset(_ i: Int) -> CGFloat {
        CGFloat(i) * (_Geom483.barTop + _Geom483.connector) + _Geom483.barTop
    }

    private var connectorIndices: [Int] {
        guard model.stages.count > 1 else { return [] }
        return Array(0..<(model.stages.count - 1))
    }

    private var stackHeight: CGFloat {
        let n = CGFloat(model.stages.count)
        let bands = max(n - 1, 0)
        return n * _Geom483.barTop + bands * _Geom483.connector
    }

    private var totalRows: Int { model.stages.count }

    // MARK: - Fills

    private func barStyle(for stage: FunnelStage, isFirst: Bool) -> AnyShapeStyle {
        if isFirst && model.usesBrandGradientForFirstStage {
            return AnyShapeStyle(LinearGradient.diagonal)
        }
        return AnyShapeStyle(stage.tint)
    }

    /// Connector trapezoid fill — first connector picks up the brand gradient
    /// at low alpha (483 line 82 used the diagonal @0.12); deeper connectors
    /// use the lower stage's tint at low alpha (483 line 83, warning @0.18).
    private func connectorFill(for i: Int) -> AnyShapeStyle {
        let highlighted = selection == model.stages[safe: i]?.id
            || selection == model.stages[safe: i + 1]?.id
        let alpha = highlighted ? 0.34 : (i == 0 ? 0.14 : 0.18)
        if i == 0 && model.usesBrandGradientForFirstStage {
            return AnyShapeStyle(LinearGradient.diagonal.opacity(alpha))
        }
        let tint = model.stages[safe: i + 1]?.tint ?? Brand.warning
        return AnyShapeStyle(tint.opacity(alpha))
    }

    // MARK: - Text

    private func countText(_ stage: FunnelStage) -> String {
        stage.unit.isEmpty ? "\(stage.count)" : "\(stage.count) \(stage.unit)"
    }

    /// Right-edge conversion readout. First stage = "100%". Deeper stages show
    /// the cumulative % of baseline plus the step-over-step delta, e.g.
    /// "10.6% · −89%" (483 lines 88/93/98).
    private func conversionText(_ index: Int) -> String {
        guard model.stages.indices.contains(index) else { return "" }
        let count = Double(model.stages[index].count)
        let pctOfBaseline = baseline > 0 ? (count / baseline) * 100 : 0

        if index == 0 {
            return _fmtPct483(pctOfBaseline, decimals: 0) + "%"
        }
        let prev = Double(model.stages[index - 1].count)
        let stepRatio = prev > 0 ? count / prev : 0
        let drop = Int((1.0 - stepRatio) * 100.0 + 0.5)
        let cum = _fmtPct483(pctOfBaseline, decimals: 1) + "%"
        return "\(cum) · −\(drop)%"
    }

    private func accessibilityValue(_ stage: FunnelStage, index: Int) -> String {
        "\(stage.count). " + conversionText(index)
            .replacingOccurrences(of: "·", with: ", ")
            .replacingOccurrences(of: "−", with: "down ")
    }

    // MARK: - Interaction

    private func toggle(_ stage: FunnelStage) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            if selection == stage.id {
                selection = nil
                onSelect(nil)
            } else {
                selection = stage.id
                onSelect(stage)
            }
        }
    }

    /// Map a drag's vertical position to the nearest stage and select it.
    private func scrub(to y: CGFloat) {
        guard totalRows > 0 else { return }
        let band = _Geom483.barTop + _Geom483.connector
        let raw = Int((y / max(band, 1)).rounded(.down))
        let idx = min(max(raw, 0), totalRows - 1)
        let stage = model.stages[idx]
        guard selection != stage.id else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
            selection = stage.id
        }
        onSelect(stage)
    }

    // MARK: - Grow-in

    private var stageKey: String {
        model.stages.map { "\($0.id):\($0.count)" }.joined(separator: "|")
    }

    private func startGrow(for key: String) {
        guard renderedStageKey != key else { return }
        renderedStageKey = key
        grow = 0
        if reduceMotion {
            grow = 1
        } else {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) {
                grow = 1
            }
        }
    }
}

// MARK: - Number formatting (file-private, suffixed)

/// Formats a percentage to a fixed number of decimals without pulling in a
/// NumberFormatter — `reduce`-free, allocation-light, deterministic.
private func _fmtPct483(_ value: Double, decimals: Int) -> String {
    if decimals <= 0 {
        return "\(Int(value.rounded()))"
    }
    let scale = pow(10.0, Double(decimals))
    let rounded = (value * scale).rounded() / scale
    return String(format: "%.\(decimals)f", rounded)
}

// MARK: - Connector trapezoid shape (file-private, suffixed)

/// A funnel "waist" — a downward trapezoid connecting a wider top edge to a
/// narrower bottom edge, both horizontally centered. Drawn as a filled Shape
/// so the taper between stages reads as a continuous funnel, not stacked bars.
private struct _ConnectorTaper483: View {
    let topWidth: CGFloat
    let bottomWidth: CGFloat
    let fill: AnyShapeStyle
    let maxWidth: CGFloat

    var body: some View {
        _TaperPath483(topWidth: topWidth, bottomWidth: bottomWidth)
            .fill(fill)
            .frame(width: maxWidth, height: _Geom483.connector)
    }
}

private struct _TaperPath483: Shape {
    var topWidth: CGFloat
    var bottomWidth: CGFloat

    /// Animatable so the connector morphs in lockstep with the grow-in bars.
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topWidth, bottomWidth) }
        set { topWidth = newValue.first; bottomWidth = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let topHalf = max(topWidth, 0) / 2
        let botHalf = max(bottomWidth, 0) / 2
        var p = Path()
        p.move(to: CGPoint(x: cx - topHalf, y: rect.minY))
        p.addLine(to: CGPoint(x: cx + topHalf, y: rect.minY))
        p.addLine(to: CGPoint(x: cx + botHalf, y: rect.maxY))
        p.addLine(to: CGPoint(x: cx - botHalf, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Shield / free-rate badge (file-private, suffixed)

/// The shield-clock "free rate" motif from 483 (lines 60–66): a double shield
/// outline with a centered percentage, a "FREE RATE" caplet, and a small
/// fraction detail. Rendered with a Shape so it scales crisply.
private struct _ShieldFreeRateBadge483: View {
    let freeRate: String
    let detail: String
    let palette: Theme.Palette

    var body: some View {
        ZStack {
            _ShieldShape483()
                .fill(LinearGradient.diagonal.opacity(0.10))
            _ShieldShape483()
                .inset(by: 7)
                .stroke(LinearGradient.primary, lineWidth: 1.5)

            VStack(spacing: 2) {
                Text(freeRate)
                    .font(.system(size: 18, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("FREE RATE")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                Text(detail)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
        }
        .frame(width: 84, height: 92)
    }
}

/// Heraldic shield outline (483 lines 61–62): flat top, straight upper sides,
/// curved lower flanks meeting at a point.
private struct _ShieldShape483: InsettableShape {
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> some InsettableShape {
        var s = self
        s.inset += amount
        return s
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let w = r.width
        let h = r.height
        let x0 = r.minX, y0 = r.minY
        var p = Path()
        // Top edge.
        p.move(to: CGPoint(x: x0, y: y0 + h * 0.16))
        p.addLine(to: CGPoint(x: x0 + w * 0.5, y: y0))
        p.addLine(to: CGPoint(x: x0 + w, y: y0 + h * 0.16))
        // Right flank down to the point, curved.
        p.addLine(to: CGPoint(x: x0 + w, y: y0 + h * 0.52))
        p.addQuadCurve(
            to: CGPoint(x: x0 + w * 0.5, y: y0 + h),
            control: CGPoint(x: x0 + w, y: y0 + h * 0.84)
        )
        // Left flank back up.
        p.addQuadCurve(
            to: CGPoint(x: x0, y: y0 + h * 0.52),
            control: CGPoint(x: x0, y: y0 + h * 0.84)
        )
        p.closeSubpath()
        return p
    }
}

// MARK: - Geometry constants (file-private, suffixed)

private enum _Geom483 {
    /// Height of the widest (top) bar; deeper bars shrink by `barShrink`.
    static let barTop: CGFloat = 28
    static let barShrink: CGFloat = 2
    static let barMin: CGFloat = 22
    /// Inter-stage connector band height.
    static let connector: CGFloat = 14
    /// Horizontal padding inside the chart so bars never touch the card edge.
    static let sidePad: CGFloat = 4
    /// Smallest bar width so a near-zero stage stays tappable + labelled.
    static let minBar: CGFloat = 44
    /// Floor as a fraction of usable width (belt + suspenders with minBar).
    static let minRatio: CGFloat = 0.12
}

// MARK: - Safe array subscript (file-private, suffixed)

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview (clearly-sample data; demonstrates DYNAMIC + INTERACTIVE)

#Preview("FunnelBars · 483 Comms Escalation") {
    _FunnelBarsPreviewHost483()
        .environment(\.palette, Theme.dark)
}

/// Live host so the preview drives a real selection binding + a data toggle —
/// proving the funnel is interactive and re-animates on data change.
private struct _FunnelBarsPreviewHost483: View {
    @State private var selection: String? = nil
    @State private var tightDesk = false

    @Environment(\.palette) private var palette

    private var model: FunnelBarsModel {
        // SAMPLE DATA — clearly a preview, not production business data.
        FunnelBarsModel(
            title: "Escalation funnel · 90D · opened → flagged → escalated",
            stages: [
                FunnelStage(id: "opened",
                            label: "Opened",
                            count: 47,
                            unit: "threads",
                            tint: Brand.blue),
                FunnelStage(id: "flagged",
                            label: "Flagged",
                            count: tightDesk ? 3 : 5,
                            tint: Brand.warning),
                FunnelStage(id: "escalated",
                            label: "Escalated",
                            count: tightDesk ? 0 : 1,
                            tint: Brand.danger)
            ],
            streak: FunnelStreak(
                daysClean: tightDesk ? 41 : 28,
                eyebrow: "Current streak · days without an escalation",
                subtitle: tightDesk ? "clean since Apr 17 · personal best 41d"
                                    : "clean since Apr 30 · personal best 34d",
                freeRateLabel: tightDesk ? "100%" : "97.9%",
                freeRateDetail: tightDesk ? "47 / 47 clean" : "46 / 47 clean"
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("PREVIEW · SAMPLE DATA")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)

                FunnelBars(
                    model: model,
                    selection: $selection,
                    onSelect: { _ in }
                )

                Text(selection.map { "Selected stage: \($0)" } ?? "Tap a bar or drag to scrub")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)

                Button {
                    withAnimation { tightDesk.toggle() }
                } label: {
                    Text(tightDesk ? "Show 90-day window (1 escalation)"
                                   : "Show spotless window (0 escalations)")
                        .font(EType.bodyStrong)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(LinearGradient.primary)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(Space.s5)
        }
        .background(palette.bgPrimary.ignoresSafeArea())
    }
}
