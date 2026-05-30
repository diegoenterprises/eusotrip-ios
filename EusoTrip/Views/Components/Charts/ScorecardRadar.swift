//
//  ScorecardRadar.swift
//  EusoTrip 2027 · BespokeChartKit
//
//  N-axis radar / spider polygon primitive with a faint peer-benchmark
//  overlay hull, labelled axes, concentric grid rings, dot vertices, and
//  tap-an-axis-to-highlight interaction. Drives carrier / driver / fleet
//  scorecards (682 Vessel Carrier Scorecard · 383 Fleet CSA · 539/574/675
//  carrier scorecards · 057/213/320/340 broker & catalyst scorecards).
//
//  CANONICAL LOOK — reproduced verbatim from
//  "06 Vessel/Dark-SVG/682 Vessel Carrier Scorecard.svg":
//    · #1C2128 card on a blue→magenta gradient rim (eusoCard .feature)
//    · subject hull painted in the iridescent blue→magenta sweep, filled
//      translucent, dot vertices at each axis value
//    · network/peer benchmark drawn as a faint white hull underneath so the
//      subject is read AGAINST the fleet, not in isolation
//    · 9pt 800-weight eyebrow caps · SF-Mono metadata · tabular-nums values
//    · tinted success / warning / danger / info semantics per metric delta
//
//  PURE primitive: takes a typed public data model, holds NO business data.
//  Interactive: a selection binding + onSelect callback drive an axis
//  highlight; value / selection changes animate. The #Preview feeds clearly
//  sample data so the component renders alive.
//
//  Guardrails honoured: only `import SwiftUI`; no `func` inside Canvas
//  closures (all geometry lives in methods / computed vars); .frame(width:
//  height:); reduce(into: 0.0) for Doubles; no @ViewBuilder on returning
//  funcs. Every helper type is private + `Radar`-suffixed to avoid any
//  cross-file collision; the public surface is `ScorecardRadar` only.
//

import SwiftUI

// MARK: - Public data model

/// One labelled axis (spoke) of the radar. `value` and `benchmark` are
/// normalized to the metric's own scale by the caller into 0…1 — the
/// primitive plots fractions of the unit radius and never reasons about
/// raw units, so a percentage axis and a day-count axis coexist cleanly.
public struct ScorecardRadarAxis: Identifiable, Equatable {
    public let id: String
    /// Short spoke label drawn at the rim (e.g. "On-time", "Transit").
    public let label: String
    /// Subject value, normalized 0…1 (1 = best-on-this-axis).
    public let value: Double
    /// Faint peer / network benchmark, normalized 0…1. `nil` hides the
    /// benchmark vertex for this axis (hull bridges the gap).
    public let benchmark: Double?
    /// Human-readable display for the value, shown on highlight
    /// (e.g. "94%", "17.4d", "0.4%").
    public let valueText: String
    /// Optional benchmark display for the highlight readout
    /// (e.g. "network 88%").
    public let benchmarkText: String?
    /// Semantic accent for this axis — colours the highlight ring and the
    /// readout value. Defaults to the brand gradient (`nil`).
    public let accent: ScorecardRadarAccent

    public init(
        id: String,
        label: String,
        value: Double,
        benchmark: Double? = nil,
        valueText: String,
        benchmarkText: String? = nil,
        accent: ScorecardRadarAccent = .brand
    ) {
        self.id = id
        self.label = label
        self.value = max(0, min(1, value))
        self.benchmark = benchmark.map { max(0, min(1, $0)) }
        self.valueText = valueText
        self.benchmarkText = benchmarkText
        self.accent = accent
    }
}

/// Semantic accent for an axis vertex / highlight. Maps to the canonical
/// Brand palette so callers express intent, not raw hex.
public enum ScorecardRadarAccent: Equatable {
    case brand
    case success
    case warning
    case danger
    case info
    case hazmat
    case neutral
}

/// The whole radar payload: the subject's identity (the medallion grade),
/// its spokes, and labels for the two hulls in the legend.
public struct ScorecardRadarModel: Equatable {
    /// Letter grade / composite shown in the centre medallion
    /// (e.g. "A−"). Empty string hides the medallion.
    public let grade: String
    /// Caption under the legend describing the subject hull
    /// (e.g. "Maersk Line · MAEU").
    public let subjectLabel: String
    /// Caption describing the benchmark hull (e.g. "Network avg").
    public let benchmarkLabel: String
    /// The N axes, drawn clockwise from 12 o'clock.
    public let axes: [ScorecardRadarAxis]

    public init(
        grade: String,
        subjectLabel: String,
        benchmarkLabel: String,
        axes: [ScorecardRadarAxis]
    ) {
        self.grade = grade
        self.subjectLabel = subjectLabel
        self.benchmarkLabel = benchmarkLabel
        self.axes = axes
    }
}

// MARK: - ScorecardRadar (the primitive)

/// Reusable, data-driven radar / spider chart. Feed it a
/// `ScorecardRadarModel`; bind `selectedAxisID` and/or pass `onSelect` to
/// react to an axis being tapped. Value & selection changes animate.
public struct ScorecardRadar: View {

    // Public API ----------------------------------------------------------

    private let model: ScorecardRadarModel
    private let showsBenchmark: Bool
    private let showsGrid: Bool
    private let onSelect: ((ScorecardRadarAxis) -> Void)?

    @Binding private var selectedAxisID: String?

    /// Designated initializer — selection binding + onSelect callback.
    public init(
        model: ScorecardRadarModel,
        selectedAxisID: Binding<String?>,
        showsBenchmark: Bool = true,
        showsGrid: Bool = true,
        onSelect: ((ScorecardRadarAxis) -> Void)? = nil
    ) {
        self.model = model
        self._selectedAxisID = selectedAxisID
        self.showsBenchmark = showsBenchmark
        self.showsGrid = showsGrid
        self.onSelect = onSelect
    }

    /// Read-only convenience — no external selection state needed. The
    /// radar still highlights internally on tap.
    public init(
        model: ScorecardRadarModel,
        showsBenchmark: Bool = true,
        showsGrid: Bool = true,
        onSelect: ((ScorecardRadarAxis) -> Void)? = nil
    ) {
        self.model = model
        self._selectedAxisID = .constant(nil)
        self.showsBenchmark = showsBenchmark
        self.showsGrid = showsGrid
        self.onSelect = onSelect
        self.usesInternalSelection = true
    }

    // Internals -----------------------------------------------------------

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// When the read-only init is used we keep the highlight in @State so
    /// the chart is still interactive without a caller-supplied binding.
    @State private var internalSelection: String? = nil
    private var usesInternalSelection: Bool = false

    /// Drives the grow-in animation of the subject hull on appear and on
    /// data change (0 → 1 scales every vertex out from the centre).
    @State private var growth: CGFloat = 0

    private var effectiveSelection: String? {
        usesInternalSelection ? internalSelection : selectedAxisID
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            eyebrow
            chartCanvas
            legend
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg, intensity: .feature)
        .onAppear { animateGrowth() }
        .onChange(of: model) { _, _ in
            growth = 0
            animateGrowth()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scorecard radar")
        .accessibilityValue(accessibilitySummary)
    }

    private func animateGrowth() {
        guard !reduceMotion else { growth = 1; return }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) {
            growth = 1
        }
    }

    // MARK: Header / eyebrow

    private var eyebrow: some View {
        HStack(spacing: Space.s2) {
            Text("PERFORMANCE · vs NETWORK")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 0)
            if !model.grade.isEmpty {
                Text(model.grade)
                    .font(.system(size: 13, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
            }
        }
    }

    // MARK: Chart (Canvas + tappable axis overlay)

    private var chartCanvas: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: size / 2)
            let radius = (size / 2) - radarLabelInset

            ZStack {
                radarCanvas(center: center, radius: radius)
                medallion(center: center)
                axisLabels(center: center, radius: radius)
                tapTargets(center: center, radius: radius)
            }
            .frame(width: geo.size.width, height: size)
        }
        // Square aspect so the polygon is regular regardless of card width.
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity)
    }

    /// The faint inset so rim labels are not clipped by the card edge.
    private var radarLabelInset: CGFloat { 34 }

    // MARK: Canvas painting — grid, hulls, vertices

    private func radarCanvas(center: CGPoint, radius: CGFloat) -> some View {
        // Snapshot everything the draw closure needs into plain values so
        // the Canvas closure contains zero `func` declarations (guardrail)
        // and never touches `self` beyond these captured constants.
        let axes = model.axes
        let count = axes.count
        let grow = growth
        let drawGrid = showsGrid
        let drawBench = showsBenchmark
        let gridColor = palette.borderFaint
        let benchStroke = Color.white.opacity(0.22)
        let benchFill = Color.white.opacity(0.05)
        let brandStops = [Brand.blue, Brand.magenta]
        let selectedIndex = axes.firstIndex { $0.id == effectiveSelection }
        let accentColors = axes.map { accentColor(for: $0.accent) }

        return Canvas { context, _ in
            guard count >= 3 else { return }

            // --- concentric grid rings (4 levels) ---
            if drawGrid {
                for ring in 1...4 {
                    let rr = radius * CGFloat(ring) / 4.0
                    let path = ScorecardRadar.polygonPath(
                        center: center, radius: rr, count: count, fraction: { _ in 1 }
                    )
                    context.stroke(path, with: .color(gridColor), lineWidth: 1)
                }
                // radial spokes
                for i in 0..<count {
                    let p = ScorecardRadar.vertex(
                        center: center, radius: radius, index: i, count: count, fraction: 1
                    )
                    var spoke = Path()
                    spoke.move(to: center)
                    spoke.addLine(to: p)
                    context.stroke(spoke, with: .color(gridColor), lineWidth: 1)
                }
            }

            // --- benchmark hull (faint, underneath) ---
            if drawBench {
                let benchPath = ScorecardRadar.polygonPath(
                    center: center, radius: radius, count: count,
                    fraction: { i in (axes[i].benchmark ?? 0) * Double(grow) }
                )
                context.fill(benchPath, with: .color(benchFill))
                context.stroke(
                    benchPath,
                    with: .color(benchStroke),
                    style: StrokeStyle(lineWidth: 1.4, lineJoin: .round, dash: [4, 3])
                )
            }

            // --- subject hull (iridescent sweep) ---
            let subjectPath = ScorecardRadar.polygonPath(
                center: center, radius: radius, count: count,
                fraction: { i in axes[i].value * Double(grow) }
            )
            let sweep = GraphicsContext.Shading.linearGradient(
                Gradient(colors: brandStops),
                startPoint: CGPoint(x: center.x - radius, y: center.y - radius),
                endPoint: CGPoint(x: center.x + radius, y: center.y + radius)
            )
            let fillSweep = GraphicsContext.Shading.linearGradient(
                Gradient(colors: brandStops.map { $0.opacity(0.28) }),
                startPoint: CGPoint(x: center.x - radius, y: center.y - radius),
                endPoint: CGPoint(x: center.x + radius, y: center.y + radius)
            )
            context.fill(subjectPath, with: fillSweep)
            context.stroke(subjectPath, with: sweep,
                           style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))

            // --- dot vertices on the subject hull ---
            for i in 0..<count {
                let v = ScorecardRadar.vertex(
                    center: center, radius: radius, index: i, count: count,
                    fraction: axes[i].value * Double(grow)
                )
                let isSel = (i == selectedIndex)
                let dot = isSel ? 6.5 : 4.5
                let rect = CGRect(x: v.x - dot, y: v.y - dot, width: dot * 2, height: dot * 2)
                // Selection halo
                if isSel {
                    let haloR = dot + 5
                    let halo = CGRect(x: v.x - haloR, y: v.y - haloR,
                                      width: haloR * 2, height: haloR * 2)
                    context.fill(Circle().path(in: halo),
                                 with: .color(accentColors[i].opacity(0.22)))
                }
                context.fill(Circle().path(in: rect),
                             with: .color(isSel ? accentColors[i] : .white))
                context.stroke(Circle().path(in: rect),
                               with: sweep, lineWidth: isSel ? 2 : 1)
            }
        }
        .frame(width: radius * 2 + radarLabelInset * 2,
               height: radius * 2 + radarLabelInset * 2)
        .position(center)
        .animation(.spring(response: 0.45, dampingFraction: 0.8),
                   value: effectiveSelection)
    }

    // MARK: Centre grade medallion

    @ViewBuilder
    private func medallion(center: CGPoint) -> some View {
        if !model.grade.isEmpty {
            ZStack {
                Circle().fill(LinearGradient.diagonal)
                Circle().strokeBorder(Color.white.opacity(0.30), lineWidth: 1)
                Circle()
                    .fill(RadialGradient(
                        colors: [.white.opacity(0.65), .white.opacity(0)],
                        center: .init(x: 0.35, y: 0.30),
                        startRadius: 0, endRadius: 30))
                    .blendMode(.plusLighter)
                Text(model.grade)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)
            .shadow(color: Brand.magenta.opacity(0.35), radius: 10, y: 3)
            .position(center)
            .allowsHitTesting(false)
        }
    }

    // MARK: Rim axis labels

    private func axisLabels(center: CGPoint, radius: CGFloat) -> some View {
        let count = model.axes.count
        return ForEach(Array(model.axes.enumerated()), id: \.element.id) { idx, axis in
            let anchorPoint = ScorecardRadar.vertex(
                center: center, radius: radius + 18, index: idx, count: count, fraction: 1
            )
            axisLabel(axis: axis,
                      isSelected: axis.id == effectiveSelection,
                      at: anchorPoint, center: center)
        }
    }

    @ViewBuilder
    private func axisLabel(axis: ScorecardRadarAxis,
                           isSelected: Bool,
                           at point: CGPoint,
                           center: CGPoint) -> some View {
        let accent = accentColor(for: axis.accent)
        VStack(spacing: 1) {
            Text(axis.label)
                .font(isSelected ? EType.micro : EType.caption)
                .foregroundStyle(isSelected ? accent : palette.textSecondary)
            if isSelected {
                Text(axis.valueText)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                if let bt = axis.benchmarkText {
                    Text(bt)
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize()
        .position(point)
    }

    // MARK: Invisible tap targets (one per axis wedge)

    private func tapTargets(center: CGPoint, radius: CGFloat) -> some View {
        let count = model.axes.count
        return ForEach(Array(model.axes.enumerated()), id: \.element.id) { idx, axis in
            let target = ScorecardRadar.vertex(
                center: center, radius: radius * 0.78, index: idx, count: count, fraction: 1
            )
            Circle()
                .fill(Color.white.opacity(0.001))
                .frame(width: 46, height: 46)
                .contentShape(Circle())
                .position(target)
                .onTapGesture { select(axis) }
                .accessibilityLabel(axis.label)
                .accessibilityValue(axis.valueText)
                .accessibilityAddTraits(.isButton)
        }
    }

    // MARK: Legend (subject vs benchmark hull keys)

    private var legend: some View {
        HStack(spacing: Space.s4) {
            legendKey(swatch: AnyView(
                Capsule().fill(LinearGradient.diagonal).frame(width: 18, height: 4)
            ), text: model.subjectLabel)
            if showsBenchmark {
                legendKey(swatch: AnyView(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.35),
                                      style: StrokeStyle(lineWidth: 1.4, dash: [3, 2]))
                        .frame(width: 18, height: 6)
                ), text: model.benchmarkLabel)
            }
            Spacer(minLength: 0)
        }
    }

    private func legendKey(swatch: AnyView, text: String) -> some View {
        HStack(spacing: Space.s2) {
            swatch
            Text(text)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
    }

    // MARK: Selection plumbing

    private func select(_ axis: ScorecardRadarAxis) {
        let next: String? = (effectiveSelection == axis.id) ? nil : axis.id
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if usesInternalSelection {
                internalSelection = next
            } else {
                selectedAxisID = next
            }
        }
        if next != nil { onSelect?(axis) }
    }

    private func accentColor(for accent: ScorecardRadarAccent) -> Color {
        switch accent {
        case .brand:   return Brand.magenta
        case .success: return Brand.success
        case .warning: return Brand.warning
        case .danger:  return Brand.danger
        case .info:    return Brand.info
        case .hazmat:  return Brand.hazmat
        case .neutral: return Brand.neutral
        }
    }

    private var accessibilitySummary: String {
        model.axes
            .map { "\($0.label) \($0.valueText)" }
            .joined(separator: ", ")
    }

    // MARK: Geometry (pure static helpers — no instance state)

    /// Polar→cartesian vertex for axis `index` of `count`, at `fraction` of
    /// the unit radius. Spokes start at 12 o'clock and march clockwise so
    /// the layout matches the SVG's axis order.
    fileprivate static func vertex(center: CGPoint,
                                   radius: CGFloat,
                                   index: Int,
                                   count: Int,
                                   fraction: Double) -> CGPoint {
        let step = (2 * Double.pi) / Double(max(count, 1))
        let angle = -Double.pi / 2 + step * Double(index)
        let f = CGFloat(max(0, min(1, fraction)))
        return CGPoint(
            x: center.x + cos(angle) * radius * f,
            y: center.y + sin(angle) * radius * f
        )
    }

    /// Closed polygon path whose vertex `i` sits at `fraction(i)` of the
    /// radius. Used for grid rings (fraction == 1), the benchmark hull, and
    /// the subject hull.
    fileprivate static func polygonPath(center: CGPoint,
                                        radius: CGFloat,
                                        count: Int,
                                        fraction: (Int) -> Double) -> Path {
        var path = Path()
        guard count >= 3 else { return path }
        for i in 0..<count {
            let p = vertex(center: center, radius: radius, index: i,
                           count: count, fraction: fraction(i))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Sample data (preview-only, clearly synthetic)

private enum ScorecardRadarSampleData {
    /// 682 Vessel Carrier Scorecard — Maersk Line vs the ocean network.
    /// Values are pre-normalized 0…1 to each metric's best-direction.
    static let maersk = ScorecardRadarModel(
        grade: "A−",
        subjectLabel: "Maersk Line · MAEU",
        benchmarkLabel: "Ocean network avg",
        axes: [
            ScorecardRadarAxis(
                id: "ontime", label: "On-time", value: 0.94, benchmark: 0.88,
                valueText: "94%", benchmarkText: "network 88%", accent: .success),
            ScorecardRadarAxis(
                id: "transit", label: "Transit", value: 0.82, benchmark: 0.70,
                valueText: "17.4d", benchmarkText: "network 18.6d", accent: .info),
            ScorecardRadarAxis(
                id: "claims", label: "Claims", value: 0.88, benchmark: 0.55,
                valueText: "0.4%", benchmarkText: "network 0.9%", accent: .success),
            ScorecardRadarAxis(
                id: "docs", label: "Docs", value: 0.76, benchmark: 0.72,
                valueText: "96%", benchmarkText: "network 94%", accent: .brand),
            ScorecardRadarAxis(
                id: "rate", label: "Rate", value: 0.61, benchmark: 0.65,
                valueText: "+3.2%", benchmarkText: "network base", accent: .warning),
            ScorecardRadarAxis(
                id: "comms", label: "Comms", value: 0.90, benchmark: 0.80,
                valueText: "1.2h", benchmarkText: "network 2.1h", accent: .info)
        ]
    )
}

// MARK: - Preview (live, interactive, dynamic)

private struct ScorecardRadarPreviewHost: View {
    @State private var selected: String? = "claims"
    @State private var model = ScorecardRadarSampleData.maersk
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                Text("✦ SCORECARD RADAR · SAMPLE")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)

                ScorecardRadar(
                    model: model,
                    selectedAxisID: $selected,
                    onSelect: { _ in }
                )

                Text(selected.map { "selected axis · \($0)" } ?? "tap an axis to highlight")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)

                Button("Shuffle values (prove it animates)") {
                    model = ScorecardRadarModel(
                        grade: ["A−", "B+", "A", "B"].randomElement()!,
                        subjectLabel: model.subjectLabel,
                        benchmarkLabel: model.benchmarkLabel,
                        axes: model.axes.map {
                            ScorecardRadarAxis(
                                id: $0.id, label: $0.label,
                                value: Double.random(in: 0.35...1.0),
                                benchmark: $0.benchmark,
                                valueText: $0.valueText,
                                benchmarkText: $0.benchmarkText,
                                accent: $0.accent)
                        }
                    )
                }
                .font(EType.caption)
                .foregroundStyle(Brand.blue)

                // Read-only / no-grid variant (driver scorecard style).
                ScorecardRadar(
                    model: ScorecardRadarModel(
                        grade: "",
                        subjectLabel: "You",
                        benchmarkLabel: "Fleet avg",
                        axes: Array(ScorecardRadarSampleData.maersk.axes.prefix(5))
                    ),
                    showsGrid: false
                )
            }
            .padding(Space.s4)
        }
        .background(palette.bgPage.ignoresSafeArea())
    }
}

#Preview("ScorecardRadar · Dark") {
    ScorecardRadarPreviewHost()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("ScorecardRadar · Light") {
    ScorecardRadarPreviewHost()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
}
