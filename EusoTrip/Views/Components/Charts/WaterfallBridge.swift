//
//  WaterfallBridge.swift
//  EusoTrip 2027 · BespokeChartKit
//
//  A stepped cumulative "bridge" chart: a START bar steps up (green) and
//  down (red) through a sequence of signed deltas — each linked to the next
//  by a dashed connector line — and lands on an END bar painted with the
//  iridescent brand gradient. Every step carries a value label; tapping a
//  step selects it (selection binding + onSelect callback) and the whole
//  chart animates value / selection changes.
//
//  CANONICAL LOOK — verbatim to wireframe screen 541 "Dispatcher Margin
//  Bridge" (04 Dispatcher · Dark-SVG). That screen drives a per-load
//  QUOTED→ACTUAL margin bridge:
//      QUOTE $2,200 → −LINEHAUL $1,500 → −FUEL $260 → −DEADHEAD $180
//      → −DETENTION $128 → MARGIN $332 (15.1% net vs 20.5% quoted)
//  Geometry mirrored from the SVG:
//      • 44pt-wide columns, ~14pt gutters
//      • QUOTE bar = solid info-blue @ 0.85, rounded top
//      • down-steps = danger-red @ 0.80, suspended at the running total
//      • the terminal bar = LinearGradient.diagonal (blue→magenta)
//      • dashed neutral connector from each bar's landing edge to the next
//      • value label above each bar, axis caption below a hairline baseline
//
//  REUSABLE / DATA-DRIVEN — this primitive holds NO business data. The
//  caller passes a `WaterfallBridgeModel` (start + ordered steps + end) and
//  optional hero header values. The #Preview at the bottom feeds clearly-
//  labelled SAMPLE data so the component renders alive in Xcode canvas.
//
//  GUARDRAILS: only `import SwiftUI`; no `func` inside Canvas/ViewBuilder
//  closures (helpers are methods / computed vars); `.frame(width:height:)`;
//  `reduce(into: 0.0)` for Doubles. All helper types are private + suffixed
//  `_WB` to avoid cross-file collisions. The public surface is the single
//  `WaterfallBridge` view + its public model.
//

import SwiftUI

// MARK: - Public data model

/// One signed step in the bridge. A positive `delta` raises the running
/// total (rendered green / "up"); a negative `delta` lowers it (rendered
/// red / "down"). The `kind` lets a caller force the visual role for the
/// anchor columns (start total / end total) independent of sign.
public struct WaterfallBridgeStep: Identifiable, Equatable {
    public enum Role: Equatable {
        /// The opening column — drawn as a full bar from the baseline to its
        /// own height, in the info tint. (e.g. QUOTE $2,200)
        case start
        /// A floating delta column suspended at the running total. Up = green,
        /// down = red, driven by the sign of `delta`.
        case delta
        /// The closing column — drawn as a full bar from the baseline, painted
        /// with the iridescent brand gradient. (e.g. MARGIN $332)
        case end
    }

    public let id: String
    /// Short axis caption shown beneath the bar (e.g. "QUOTE", "FUEL").
    public let label: String
    /// Signed contribution. For `.start` / `.end` this is the absolute column
    /// magnitude (always treated as the cumulative anchor). For `.delta` the
    /// sign drives up/down coloring.
    public let delta: Double
    /// Value label rendered above the bar (e.g. "$2,200", "−1500", "$332").
    /// Pre-formatted by the caller so the primitive carries no number locale.
    public let valueLabel: String
    public let role: Role

    public init(
        id: String,
        label: String,
        delta: Double,
        valueLabel: String,
        role: Role = .delta
    ) {
        self.id = id
        self.label = label
        self.delta = delta
        self.valueLabel = valueLabel
        self.role = role
    }
}

/// The full bridge: an opening anchor, an ordered set of deltas, and a
/// closing anchor — plus an optional hero header (the big figure + the
/// quoted-vs-actual context line shown above the chart on screen 541).
public struct WaterfallBridgeModel: Equatable {
    public var eyebrow: String?          // e.g. "QUOTED → ACTUAL MARGIN · LD-…7C3A09F18B"
    public var heroValue: String?        // e.g. "$332"
    public var heroBadge: String?        // e.g. "15.1% net"   (success-tinted)
    public var heroDelta: String?        // e.g. "−$118 vs quote" (danger-tinted)
    public var heroSubline: String?      // e.g. "quoted $450 · 20.5%"
    public var steps: [WaterfallBridgeStep]

    public init(
        eyebrow: String? = nil,
        heroValue: String? = nil,
        heroBadge: String? = nil,
        heroDelta: String? = nil,
        heroSubline: String? = nil,
        steps: [WaterfallBridgeStep]
    ) {
        self.eyebrow = eyebrow
        self.heroValue = heroValue
        self.heroBadge = heroBadge
        self.heroDelta = heroDelta
        self.heroSubline = heroSubline
        self.steps = steps
    }
}

// MARK: - Primitive

/// `WaterfallBridge` — reusable, data-driven, interactive stepped bridge.
///
/// ```swift
/// @State private var picked: String? = nil
/// WaterfallBridge(model: marginBridge, selection: $picked) { step in
///     openColumnDetail(step)
/// }
/// ```
public struct WaterfallBridge: View {
    public let model: WaterfallBridgeModel
    /// Two-way selected-step binding. Tapping a bar sets it; tapping the
    /// already-selected bar clears it. Drives the highlight ring + dim.
    @Binding public var selection: String?
    /// Fired on every tap with the tapped step (after `selection` updates).
    public var onSelect: ((WaterfallBridgeStep) -> Void)?

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Animation phase 0→1 used to grow bars + draw connectors on appear and
    /// whenever the model identity changes (dynamic data swap).
    @State private var grow: CGFloat = 0
    @State private var modelToken: Int = 0

    public init(
        model: WaterfallBridgeModel,
        selection: Binding<String?> = .constant(nil),
        onSelect: ((WaterfallBridgeStep) -> Void)? = nil
    ) {
        self.model = model
        self._selection = selection
        self.onSelect = onSelect
    }

    // MARK: Layout constants (mirrored from screen 541 geometry)

    private let columnWidth: CGFloat = 44
    private let gutter: CGFloat = 14
    private let plotHeight: CGFloat = 132
    private let topLabelGap: CGFloat = 18      // headroom for the value label
    private let axisGap: CGFloat = 16          // baseline → axis caption

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            header
            chart
        }
        .padding(Space.s5)
        .eusoCard(radius: Radius.xl, intensity: .feature)
        .onAppear { animateIn() }
        .onChange(of: model) { _, _ in
            // Dynamic data swap: re-run the grow animation so a new bridge
            // visibly re-draws rather than snapping in.
            modelToken &+= 1
            grow = 0
            animateIn()
        }
    }

    // MARK: Header (hero block above the chart)

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if let eyebrow = model.eyebrow {
                Text(eyebrow.uppercased())
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                if let heroValue = model.heroValue {
                    Text(heroValue)
                        .font(.system(size: 32, weight: .bold, design: .default))
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                        .contentTransition(.numericText())
                }
                if let heroBadge = model.heroBadge {
                    Text(heroBadge)
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Brand.success)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    if let heroDelta = model.heroDelta {
                        Text(heroDelta)
                            .font(.system(size: 11, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Brand.danger)
                    }
                    if let heroSubline = model.heroSubline {
                        Text(heroSubline)
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: Chart (bars + connectors + axis)

    @ViewBuilder
    private var chart: some View {
        let frames = layout
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                connectors(frames)
                bars(frames)
            }
            .frame(height: plotHeight + topLabelGap)
            baseline
            axis(frames)
        }
    }

    /// The hairline baseline beneath the bars.
    private var baseline: some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(height: 1)
            .padding(.top, 4)
    }

    @ViewBuilder
    private func axis(_ frames: [_WBFrame]) -> some View {
        HStack(spacing: gutter) {
            ForEach(Array(model.steps.enumerated()), id: \.element.id) { idx, step in
                Text(step.label.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.3)
                    .foregroundStyle(
                        selection == step.id ? palette.textSecondary : palette.textTertiary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: columnWidth)
                    .opacity(idx < frames.count ? 1 : 1)
            }
        }
        .padding(.top, axisGap - 8)
    }

    // MARK: Bars

    @ViewBuilder
    private func bars(_ frames: [_WBFrame]) -> some View {
        ForEach(Array(zip(model.steps, frames)), id: \.0.id) { step, frame in
            barCell(step: step, frame: frame)
        }
    }

    @ViewBuilder
    private func barCell(step: WaterfallBridgeStep, frame: _WBFrame) -> some View {
        let isSelected = selection == step.id
        let dimmed = selection != nil && !isSelected
        let animatedHeight = frame.barHeight * grow
        // The bar grows from its landing edge: start/end anchor from the
        // baseline (grow upward); deltas grow from their suspended top.
        VStack(spacing: 4) {
            Text(step.valueLabel)
                .font(.system(size: 9.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(labelColor(step))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: columnWidth + 8)
                .opacity(grow > 0.6 ? 1 : 0)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(barFill(step))
                .frame(width: columnWidth, height: max(animatedHeight, 2))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(
                            isSelected ? AnyShapeStyle(LinearGradient.diagonal)
                                       : AnyShapeStyle(Color.clear),
                            lineWidth: 2
                        )
                )
                .shadow(
                    color: isSelected ? Brand.magenta.opacity(0.45) : .clear,
                    radius: 8, y: 2
                )
        }
        .frame(width: columnWidth + 8, alignment: .bottom)
        // Position the cell so the bar's TOP sits at frame.topY. The value
        // label (≈18pt) lives above that, so we offset the whole VStack up
        // by the label gap.
        .offset(
            x: frame.x - 4,
            y: frame.topY - topLabelGap
        )
        .opacity(dimmed ? 0.4 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture { toggle(step) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.label), \(step.valueLabel)")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Connectors (dashed step links)

    @ViewBuilder
    private func connectors(_ frames: [_WBFrame]) -> some View {
        // Draw a dashed line from each bar's landing edge to the next bar's
        // landing edge — the canonical waterfall "step" connector. Rendered
        // in a Canvas so it's a single GPU pass and animates with `grow`.
        Canvas { context, _ in
            guard frames.count > 1 else { return }
            for i in 0..<(frames.count - 1) {
                let a = frames[i]
                let b = frames[i + 1]
                // Landing Y = where the next step departs from. For a down
                // step the connector rides along the bottom of bar `a`; for
                // an up step along its top. We use each bar's running-total
                // edge (frame.connectorY) which the layout already resolved.
                let startX = a.x + columnWidth
                let endX = b.x
                let y = a.connectorY
                guard grow > 0.05 else { continue }
                let reach = startX + (endX - startX) * Double(min(grow, 1))
                var path = Path()
                path.move(to: CGPoint(x: startX, y: y))
                path.addLine(to: CGPoint(x: reach, y: y))
                context.stroke(
                    path,
                    with: .color(palette.textTertiary.opacity(0.55)),
                    style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                )
            }
        }
        .frame(height: plotHeight + topLabelGap)
        .allowsHitTesting(false)
    }

    // MARK: Geometry resolution

    /// Resolves the on-screen frame of every step: x-offset, bar height, the
    /// y of its top edge, and the y of the connector that departs from it.
    /// Heights are scaled so the tallest anchor fills `plotHeight`.
    private var layout: [_WBFrame] {
        let steps = model.steps
        guard !steps.isEmpty else { return [] }

        // Resolve running totals so deltas float at the correct height.
        var runningTotals: [Double] = []
        var running = 0.0
        for step in steps {
            switch step.role {
            case .start:
                running = abs(step.delta)
                runningTotals.append(running)
            case .delta:
                let before = running
                running += step.delta
                // store the *higher* of before/after as the bar's top anchor
                runningTotals.append(max(before, running))
            case .end:
                running = abs(step.delta)
                runningTotals.append(running)
            }
        }

        // Scale: tallest cumulative anchor → plotHeight.
        let peak = max(runningTotals.max() ?? 1, 1)
        let scale = plotHeight / peak
        let baselineY = plotHeight + topLabelGap   // y of the chart baseline

        var frames: [_WBFrame] = []
        var rolling = 0.0
        for (idx, step) in steps.enumerated() {
            let x = CGFloat(idx) * (columnWidth + gutter)
            switch step.role {
            case .start, .end:
                let h = CGFloat(abs(step.delta)) * scale
                let topY = baselineY - h
                rolling = abs(step.delta)
                frames.append(
                    _WBFrame(x: x, barHeight: h, topY: topY, connectorY: topY)
                )
            case .delta:
                let before = rolling
                let after = rolling + step.delta
                rolling = after
                let hi = max(before, after)
                let lo = min(before, after)
                let h = CGFloat(hi - lo) * scale
                let topY = baselineY - CGFloat(hi) * scale
                // The connector departs from the LANDING edge of this step:
                // for a down step that's the bottom (the new, lower total);
                // for an up step that's the top (the new, higher total).
                let landing = CGFloat(after) * scale
                let connectorY = baselineY - landing
                frames.append(
                    _WBFrame(x: x, barHeight: h, topY: topY, connectorY: connectorY)
                )
            }
        }
        return frames
    }

    // MARK: Fills + label colors

    private func barFill(_ step: WaterfallBridgeStep) -> AnyShapeStyle {
        switch step.role {
        case .start:
            return AnyShapeStyle(Brand.info.opacity(0.85))
        case .end:
            return AnyShapeStyle(LinearGradient.diagonal)
        case .delta:
            return AnyShapeStyle(
                (step.delta >= 0 ? Brand.success : Brand.danger).opacity(0.82)
            )
        }
    }

    private func labelColor(_ step: WaterfallBridgeStep) -> Color {
        switch step.role {
        case .start: return palette.textPrimary
        case .end:   return Brand.success
        case .delta: return step.delta >= 0 ? Brand.success : Color(hex: 0xFF6B5E)
        }
    }

    // MARK: Interaction

    private func toggle(_ step: WaterfallBridgeStep) {
        let response: Animation = reduceMotion ? .default : .spring(response: 0.32, dampingFraction: 0.8)
        withAnimation(response) {
            selection = (selection == step.id) ? nil : step.id
        }
        onSelect?(step)
    }

    private func animateIn() {
        guard !reduceMotion else { grow = 1; return }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
            grow = 1
        }
    }
}

// MARK: - Private geometry helper (suffixed _WB to avoid collisions)

private struct _WBFrame {
    let x: CGFloat          // leading x of the column within the plot
    let barHeight: CGFloat  // resting (grow == 1) bar height in points
    let topY: CGFloat       // y of the bar's top edge (within the plot box)
    let connectorY: CGFloat // y where the dashed connector to the next bar departs
}

// MARK: - Preview (clearly SAMPLE data — demonstrably dynamic + interactive)

#Preview("WaterfallBridge · Margin (sample)") {
    _WBPreviewHost()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .padding()
        .background(Theme.dark.bgPage)
}

/// Stateful preview host so the selection binding + a live data swap are
/// both exercised. NOT shipped — preview-only, prefixed `_WB`.
private struct _WBPreviewHost: View {
    @State private var selection: String? = nil
    @State private var swapped = false

    private var sampleA: WaterfallBridgeModel {
        WaterfallBridgeModel(
            eyebrow: "QUOTED → ACTUAL MARGIN · LD-…7C3A09F18B",
            heroValue: "$332",
            heroBadge: "15.1% net",
            heroDelta: "−$118 vs quote",
            heroSubline: "quoted $450 · 20.5%",
            steps: [
                .init(id: "quote",    label: "Quote",    delta:  2200, valueLabel: "$2,200", role: .start),
                .init(id: "linehaul", label: "Linehaul", delta: -1500, valueLabel: "−1500",  role: .delta),
                .init(id: "fuel",     label: "Fuel",     delta:  -260, valueLabel: "−260",   role: .delta),
                .init(id: "deadhead", label: "Deadhead", delta:  -180, valueLabel: "−180",   role: .delta),
                .init(id: "detention",label: "Detent.",  delta:  -128, valueLabel: "−128",   role: .delta),
                .init(id: "margin",   label: "Margin",   delta:   332, valueLabel: "$332",   role: .end)
            ]
        )
    }

    private var sampleB: WaterfallBridgeModel {
        WaterfallBridgeModel(
            eyebrow: "QUOTED → ACTUAL MARGIN · LD-…B41782FF02",
            heroValue: "$704",
            heroBadge: "22.0% net",
            heroDelta: "+$54 vs quote",
            heroSubline: "quoted $650 · 20.3%",
            steps: [
                .init(id: "quote",    label: "Quote",    delta:  3200, valueLabel: "$3,200", role: .start),
                .init(id: "linehaul", label: "Linehaul", delta: -1900, valueLabel: "−1900",  role: .delta),
                .init(id: "fuel",     label: "Fuel",     delta:  -340, valueLabel: "−340",   role: .delta),
                .init(id: "bonus",    label: "Bonus",    delta:   120, valueLabel: "+120",   role: .delta),
                .init(id: "detention",label: "Detent.",  delta:  -376, valueLabel: "−376",   role: .delta),
                .init(id: "margin",   label: "Margin",   delta:   704, valueLabel: "$704",   role: .end)
            ]
        )
    }

    var body: some View {
        VStack(spacing: Space.s4) {
            WaterfallBridge(
                model: swapped ? sampleB : sampleA,
                selection: $selection
            ) { step in
                selection = step.id
            }

            Text(selection.map { "selected: \($0)" } ?? "tap a step to drill in")
                .font(EType.caption)
                .foregroundStyle(Theme.dark.textSecondary)

            Button(swapped ? "Show LA→PHX load" : "Swap to KC→OMA load") {
                swapped.toggle()
            }
            .font(EType.bodyStrong)
            .foregroundStyle(.white)
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s2)
            .background(LinearGradient.primary, in: Capsule())
        }
    }
}
