//
//  HeatCellMatrix.swift
//  EusoTrip 2027 · BespokeChartKit
//
//  A color-scaled grid of cells (intensity → hot/warm/soft color ramp) with
//  optional row/column axis labels and a HOT · WARM · SOFT legend. Tapping (or
//  dragging across) a cell selects it and fires a detail callback.
//
//  CANONICAL LOOK — verbatim to "544 Dispatcher Demand Map" (04 Dispatcher /
//  Dark-SVG). The bespoke composition there is a LOAD-TO-TRUCK HEAT GRID of
//  markets where cell color encodes demand intensity:
//      • HOT  = #F44336 @ 0.85   (Brand.danger)
//      • WARM = #FFA726 @ 0.55   (Brand.warning)
//      • SOFT = #00C48C @ 0.35   (Brand.success)
//  Each cell is an 82×72 rounded rect (radius 12) carrying a bold label, a
//  tabular numeric value, and a small unit caption. Text reads white on HOT,
//  textPrimary on WARM/SOFT (legibility against the lighter washes). The grid
//  sits inside a gradient-rimmed card (radius 20 → inner 18.5) with a small-
//  caps eyebrow + hottest-cell summary row and the three-swatch legend below.
//
//  This is a PRIMITIVE: a public, reusable, data-driven View. It contains no
//  hardcoded business data — callers pass a typed `[Cell]` model plus the
//  semantic thresholds that map a raw intensity onto the ramp. It drives the
//  544 demand heatmap, the 558 Rail / 658 Vessel demurrage-accrual matrix,
//  port-congestion grids, and the 822 DG segregation matrix.
//
//  Guardrails honored: only `import SwiftUI`; no `func` inside Canvas/
//  @ViewBuilder closures; `.frame(width:height:)`; `reduce(into: 0.0)` for
//  Doubles; no `@ViewBuilder` on a func that uses explicit `return`.
//

import SwiftUI

// MARK: - Public data model

/// Where a cell's raw intensity lands on the hot/warm/soft ramp. Callers can
/// either let the matrix derive this from `intensity` + the supplied
/// `HeatCellThresholds`, or pin a band explicitly per cell (e.g. compliance
/// matrices where the band is a categorical verdict rather than a magnitude).
public enum HeatCellBand: String, CaseIterable, Hashable, Sendable {
    case hot
    case warm
    case soft

    /// Display order coldest → hottest for the legend swatch row.
    public static var legendOrder: [HeatCellBand] { [.hot, .warm, .soft] }

    public var title: String {
        switch self {
        case .hot:  return "HOT"
        case .warm: return "WARM"
        case .soft: return "SOFT"
        }
    }
}

/// A single grid cell. Fully data-driven — the matrix paints whatever the
/// caller supplies and never invents business values.
public struct HeatCell: Identifiable, Hashable, Sendable {
    public let id: String
    /// Short cell label, e.g. a market code ("TX") or a lane/day key.
    public let label: String
    /// Formatted primary value drawn under the label, e.g. "3.8×".
    public let valueText: String
    /// Small unit caption under the value, e.g. "loads/truck". Optional.
    public let unitText: String?
    /// Raw magnitude used both to derive the band (via thresholds) and to
    /// scale the wash opacity so hotter cells read denser within their band.
    public let intensity: Double
    /// Explicit band override. When non-nil it wins over threshold derivation
    /// — used by categorical matrices (segregation verdicts, SLA states).
    public let band: HeatCellBand?
    /// Optional axis coordinates. When both are supplied across the model the
    /// matrix lays cells out on an `(row, col)` grid honoring the axis labels;
    /// otherwise it flows them left-to-right in `columns`-wide rows.
    public let row: Int?
    public let col: Int?
    /// Free-form detail payload surfaced to the caller on selection.
    public let detail: String?

    public init(
        id: String,
        label: String,
        valueText: String,
        unitText: String? = nil,
        intensity: Double,
        band: HeatCellBand? = nil,
        row: Int? = nil,
        col: Int? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.label = label
        self.valueText = valueText
        self.unitText = unitText
        self.intensity = intensity
        self.band = band
        self.row = row
        self.col = col
        self.detail = detail
    }
}

/// Semantic cut-points that map a raw `intensity` onto the ramp. `intensity >=
/// hotAt` → HOT, `>= warmAt` → WARM, else SOFT. Defaults mirror the 544
/// loads/truck cuts (≥3.0 hot, ≥1.4 warm). The min/max bound the per-band
/// wash-opacity scaling so a 3.1× and a 3.8× cell read distinct without
/// leaving their band's color.
public struct HeatCellThresholds: Equatable, Sendable {
    public var warmAt: Double
    public var hotAt: Double
    public var minIntensity: Double
    public var maxIntensity: Double

    public init(
        warmAt: Double = 1.4,
        hotAt: Double = 3.0,
        minIntensity: Double = 0.0,
        maxIntensity: Double = 4.0
    ) {
        self.warmAt = warmAt
        self.hotAt = hotAt
        self.minIntensity = minIntensity
        self.maxIntensity = maxIntensity
    }
}

// MARK: - HeatCellMatrix (the primitive)

/// Color-scaled grid of cells with row/col labels + legend; tap or drag a cell
/// to select and drill. Selection is exposed both as a `@Binding` (so the host
/// can drive/observe it) and as an `onSelect` callback (so a host that just
/// wants the event can stay stateless).
public struct HeatCellMatrix: View {

    // ── Inputs ────────────────────────────────────────────────────────────
    private let title: String
    private let eyebrow: String
    private let cells: [HeatCell]
    private let columns: Int
    private let thresholds: HeatCellThresholds
    private let rowLabels: [String]
    private let columnLabels: [String]
    private let showLegend: Bool
    private let showSummary: Bool

    @Binding private var selection: String?
    private let onSelect: (HeatCell) -> Void

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Cell currently under the drag finger — drives a live highlight before
    /// the gesture ends and commits the selection.
    @State private var scrubbingID: String?
    /// Re-keys the selection haptic.
    @State private var selectionTick: Int = 0

    public init(
        title: String,
        eyebrow: String,
        cells: [HeatCell],
        columns: Int = 4,
        thresholds: HeatCellThresholds = HeatCellThresholds(),
        rowLabels: [String] = [],
        columnLabels: [String] = [],
        showLegend: Bool = true,
        showSummary: Bool = true,
        selection: Binding<String?> = .constant(nil),
        onSelect: @escaping (HeatCell) -> Void = { _ in }
    ) {
        self.title = title
        self.eyebrow = eyebrow
        self.cells = cells
        self.columns = max(1, columns)
        self.thresholds = thresholds
        self.rowLabels = rowLabels
        self.columnLabels = columnLabels
        self.showLegend = showLegend
        self.showSummary = showSummary
        self._selection = selection
        self.onSelect = onSelect
    }

    // MARK: Body

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            eyebrowRow
            if showSummary { summaryRow }
            gridBody
            if showLegend { legendRow }
        }
        .padding(Space.s4)
        .background(cardSurface)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: selection)
        .animation(.easeOut(duration: 0.25), value: cells)
        .sensoryFeedback(.selection, trigger: selectionTick)
    }

    // MARK: Card surface (gradient rim → inner fill, verbatim to 544)

    private var cardSurface: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
        return shape
            .fill(palette.bgCard)
            .overlay(shape.strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
            .shadow(color: Brand.blue.opacity(0.18), radius: 6, x: -2, y: 2)
            .shadow(color: Brand.magenta.opacity(0.18), radius: 6, x: 2, y: 2)
    }

    // MARK: Eyebrow

    private var eyebrowRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(eyebrow.uppercased())
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: Space.s3)
            Text("\(cells.count) cell\(cells.count == 1 ? "" : "s")")
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Summary (hottest cell + its value)

    @ViewBuilder
    private var summaryRow: some View {
        if let top = hottestCell {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(top.label)
                    .font(EType.h2)
                    .foregroundStyle(palette.textPrimary)
                Text("hottest")
                    .font(EType.body)
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: Space.s2)
                Text(top.valueText)
                    .font(EType.mono(.body))
                    .foregroundStyle(color(for: bandFor(top)))
            }
        }
    }

    // MARK: Grid

    private var gridBody: some View {
        let cols = Array(
            repeating: GridItem(.flexible(), spacing: Space.s2),
            count: hasAxes ? max(columnLabels.count, columns) : columns
        )
        return VStack(alignment: .leading, spacing: Space.s2) {
            if hasAxes && !columnLabels.isEmpty { columnHeaderRow }
            LazyVGrid(columns: cols, alignment: .leading, spacing: Space.s2) {
                ForEach(orderedCells) { cell in
                    cellTile(cell)
                        .reportHeatCellFrameHCM(id: cell.id)
                }
            }
        }
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(HeatCellFrameKeyHCM.self) { frames in
            scrubFrames = frames
        }
        .gesture(scrubGesture)
    }

    private var columnHeaderRow: some View {
        HStack(spacing: Space.s2) {
            ForEach(Array(columnLabels.enumerated()), id: \.offset) { _, label in
                Text(label.uppercased())
                    .font(EType.micro)
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, Space.s1)
    }

    // MARK: Cell tile (82×72 rounded rect, verbatim wash + text rules)

    private func cellTile(_ cell: HeatCell) -> some View {
        let band = bandFor(cell)
        let washOpacity = washOpacity(for: cell, band: band)
        let isSelected = selection == cell.id
        let isScrubbing = scrubbingID == cell.id
        let active = isSelected || isScrubbing
        let textColor = textColor(for: band, washOpacity: washOpacity)

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(cell.label)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(textColor)
                if let row = cell.row, !rowLabels.isEmpty, rowLabels.indices.contains(row) {
                    Text(rowLabels[row])
                        .font(EType.micro)
                        .foregroundStyle(textColor.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
            Text(cell.valueText)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(textColor)
            if let unit = cell.unitText {
                Text(unit)
                    .font(.system(size: 8, weight: .regular))
                    .foregroundStyle(textColor.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .frame(height: 72)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(rampColor(band).opacity(washOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    active ? rampColor(band) : Color.clear,
                    lineWidth: active ? 2 : 0
                )
        )
        .scaleEffect(active ? (reduceMotion ? 1.0 : 1.04) : 1.0)
        .shadow(
            color: active ? rampColor(band).opacity(0.45) : .clear,
            radius: active ? 12 : 0, y: 4
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { commit(cell) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(cell.label), \(band.title)")
        .accessibilityValue(cell.valueText)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: Legend (HOT · WARM · SOFT swatch row, verbatim to 544)

    private var legendRow: some View {
        HStack(spacing: Space.s4) {
            ForEach(HeatCellBand.legendOrder, id: \.self) { band in
                HStack(spacing: 6) {
                    Circle()
                        .fill(rampColor(band).opacity(legendWash(band)))
                        .frame(width: 8, height: 8)
                    Text(band.title)
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Space.s1)
    }

    // MARK: - Selection plumbing

    private func commit(_ cell: HeatCell) {
        if selection != cell.id {
            selection = cell.id
            selectionTick &+= 1
            onSelect(cell)
        }
    }

    /// Drag-to-scrub: highlight the cell under the finger, and commit it when
    /// the finger lifts. Cell frames are resolved against the named coordinate
    /// space so the hit-test stays correct as the grid reflows.
    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if let hit = cellID(at: value.location) {
                    if scrubbingID != hit { scrubbingID = hit; selectionTick &+= 1 }
                }
            }
            .onEnded { value in
                if let hit = cellID(at: value.location),
                   let cell = orderedCells.first(where: { $0.id == hit }) {
                    commit(cell)
                }
                scrubbingID = nil
            }
    }

    fileprivate static let space = "HeatCellMatrix.grid"

    /// Resolves which cell the drag finger is over by testing the captured
    /// per-cell frames (in the grid coordinate space). Returns nil over a gap.
    private func cellID(at point: CGPoint) -> String? {
        guard let frame = scrubFrames.first(where: { $0.value.contains(point) }) else {
            return nil
        }
        return frame.key
    }

    /// Frames captured for each cell, keyed by id, in the grid coordinate
    /// space. Populated by `reportHeatCellFrameHCM` + the `onPreferenceChange`
    /// collector wired in `gridBody`.
    @State private var scrubFrames: [String: CGRect] = [:]

    // MARK: - Derivations

    private var hasAxes: Bool {
        cells.contains { $0.row != nil && $0.col != nil } &&
        (!rowLabels.isEmpty || !columnLabels.isEmpty)
    }

    /// Cells ordered for layout: by (row, col) when axes are present, else in
    /// the order supplied by the caller.
    private var orderedCells: [HeatCell] {
        guard hasAxes else { return cells }
        return cells.sorted { a, b in
            let ar = a.row ?? 0, br = b.row ?? 0
            if ar != br { return ar < br }
            return (a.col ?? 0) < (b.col ?? 0)
        }
    }

    private var hottestCell: HeatCell? {
        cells.max { lhs, rhs in lhs.intensity < rhs.intensity }
    }

    private func bandFor(_ cell: HeatCell) -> HeatCellBand {
        if let pinned = cell.band { return pinned }
        if cell.intensity >= thresholds.hotAt { return .hot }
        if cell.intensity >= thresholds.warmAt { return .warm }
        return .soft
    }

    /// Base ramp color for a band — the EusoTrip semantic trio.
    private func rampColor(_ band: HeatCellBand) -> Color {
        switch band {
        case .hot:  return Brand.danger
        case .warm: return Brand.warning
        case .soft: return Brand.success
        }
    }

    /// Convenience used by the summary metric text.
    private func color(for band: HeatCellBand) -> Color { rampColor(band) }

    /// 544 base washes: HOT 0.85 · WARM 0.55 · SOFT 0.35. Within a band the
    /// wash is nudged ±0.10 by where `intensity` sits between the band's lower
    /// and upper bound, so a 3.8× cell reads denser than a 3.1× cell without
    /// changing hue.
    private func washOpacity(for cell: HeatCell, band: HeatCellBand) -> Double {
        let base: Double
        let lower: Double
        let upper: Double
        switch band {
        case .hot:
            base = 0.85
            lower = thresholds.hotAt
            upper = thresholds.maxIntensity
        case .warm:
            base = 0.55
            lower = thresholds.warmAt
            upper = thresholds.hotAt
        case .soft:
            base = 0.35
            lower = thresholds.minIntensity
            upper = thresholds.warmAt
        }
        guard upper > lower else { return base }
        let t = min(max((cell.intensity - lower) / (upper - lower), 0.0), 1.0)
        // Map t∈[0,1] → ±0.10 around the base, clamped to a sane range.
        let nudged = base + (t - 0.5) * 0.20
        return min(max(nudged, 0.18), 0.92)
    }

    private func legendWash(_ band: HeatCellBand) -> Double {
        switch band {
        case .hot:  return 0.85
        case .warm: return 0.55
        case .soft: return 0.35
        }
    }

    /// Text reads white on a dense HOT wash; on the lighter WARM/SOFT washes
    /// (or a faded HOT) it falls back to the palette's primary ink so it stays
    /// legible — exactly the rule the 544 SVG applies.
    private func textColor(for band: HeatCellBand, washOpacity: Double) -> Color {
        if band == .hot && washOpacity >= 0.6 { return .white }
        return palette.textPrimary
    }
}

// MARK: - Cell frame capture (for drag-scrub hit testing)

/// Preference key carrying each cell's frame in the grid coordinate space so
/// the drag gesture can resolve which cell the finger is over without a
/// per-cell GeometryReader hierarchy. Suffixed to avoid cross-file collisions.
private struct HeatCellFrameKeyHCM: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension View {
    /// Publishes this view's frame (in the named grid space) under `id` so the
    /// matrix's drag-scrub gesture can resolve finger position → cell without
    /// a per-cell GeometryReader hierarchy.
    func reportHeatCellFrameHCM(id: String) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: HeatCellFrameKeyHCM.self,
                    value: [id: geo.frame(in: .named(HeatCellMatrix.space))]
                )
            }
        )
    }
}

// MARK: - #Preview (clearly SAMPLE data — demonstrates dynamic + interactive)

#Preview("HeatCellMatrix · Demand (544)") {
    HeatCellMatrixPreviewHCM()
        .environment(\.palette, Theme.dark)
}

/// Preview harness. Holds selection state so the live selection ring + detail
/// readout are demonstrably interactive. All values are obviously sample data.
private struct HeatCellMatrixPreviewHCM: View {
    @State private var selected: String? = nil
    @State private var lastDetail: String = "Tap or drag a market"

    // SAMPLE demand cells — mirrors the 544 wireframe markets.
    private let demand: [HeatCell] = [
        HeatCell(id: "TX", label: "TX", valueText: "3.8×", unitText: "loads/truck", intensity: 3.8, detail: "148 outbound surplus · reposition in"),
        HeatCell(id: "CA", label: "CA", valueText: "3.1×", unitText: "loads/truck", intensity: 3.1, detail: "96 outbound surplus · reposition in"),
        HeatCell(id: "IL", label: "IL", valueText: "2.4×", unitText: "loads/truck", intensity: 2.4, detail: "62 inbound surplus · source out"),
        HeatCell(id: "GA", label: "GA", valueText: "2.1×", unitText: "loads/truck", intensity: 2.1, detail: "38 inbound surplus · source out"),
        HeatCell(id: "AZ", label: "AZ", valueText: "1.6×", unitText: "loads/truck", intensity: 1.6, detail: "balanced market"),
        HeatCell(id: "OH", label: "OH", valueText: "1.2×", unitText: "loads/truck", intensity: 1.2, detail: "44 outbound surplus · reposition in"),
        HeatCell(id: "PA", label: "PA", valueText: "0.9×", unitText: "loads/truck", intensity: 0.9, detail: "soft demand"),
        HeatCell(id: "NE", label: "NE", valueText: "0.6×", unitText: "loads/truck", intensity: 0.6, detail: "18 inbound surplus · source out")
    ]

    var body: some View {
        ZStack {
            Theme.dark.bgPrimary.ignoresSafeArea()
            VStack(spacing: Space.s4) {
                HeatCellMatrix(
                    title: "Demand map",
                    eyebrow: "Load-to-truck heat · 7-day outlook",
                    cells: demand,
                    columns: 4,
                    thresholds: HeatCellThresholds(warmAt: 1.4, hotAt: 3.0, minIntensity: 0.0, maxIntensity: 4.0),
                    selection: $selected,
                    onSelect: { cell in
                        lastDetail = "\(cell.label): \(cell.detail ?? cell.valueText)"
                    }
                )

                Text(lastDetail)
                    .font(EType.mono(.caption))
                    .foregroundStyle(Theme.dark.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.s2)
            }
            .padding(Space.s4)
        }
        .preferredColorScheme(.dark)
    }
}
