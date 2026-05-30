//
//  StateGrid.swift
//  EusoTrip 2027 · BespokeChartKit
//
//  A labeled COORDINATE grid of status cells (NOT a geo map). Each cell is a
//  rounded-rect slot tinted by its state — empty / occupied / reserved /
//  maintenance — carrying a short label (trailer #, slot id). Tap selects a
//  cell; an optional drag-to-move lifts the picked cell and drops it onto a
//  target cell, emitting a move callback. Drives the rail yard track-grid
//  (628 Rail Yard Map · yardManagement.getYardMap), 555 Consist Board, and
//  the vessel drop-yard ops grid (702).
//
//  VERBATIM to 628 Rail Yard Map · Dark-SVG:
//    • cells 38×28, corner radius 6, ~9pt gutter (stride 46/47)            (SVG :35–66)
//    • occupied  = Brand.blue   @ 0.90 fill                                (#1473FF)
//    • reserved  = Brand.warning@ 0.90 fill                                (#FFA726)
//    • empty/open= white        @ 0.18 fill                                (#FFFFFF/0.18)
//    • maint     = Brand.danger @ 0.90 fill                                (#F44336)
//    • card = #1C2128 rim, white@0.08 hairline, radius 20                  (SVG :32)
//    • eyebrow "TRACK GRID · LIVE" + right meta, micro caps               (SVG :33–34)
//    • legend row: 12×12 rx3 swatches + 10pt labels                        (SVG :67–74)
//
//  PUBLIC + DATA-DRIVEN: the View takes a typed model (StateGridModel) — no
//  hardcoded business data inside. INTERACTIVE: `selection` binding + onSelect
//  closure for tap, optional onMove closure for drag-to-move, animated
//  selection ring + occupancy transitions. A #Preview feeds sample data.
//
//  GUARDRAILS: only `import SwiftUI`; no `func` inside @ViewBuilder/Canvas
//  closures; .frame(width:height:); reduce(into:0.0) for Doubles; helpers are
//  private + `SG`-suffixed to dodge cross-file collisions.
//

import SwiftUI

// MARK: - Public data model

/// The four canonical slot states a `StateGrid` cell can be in. Each maps to a
/// bespoke fill color verbatim to the 628 yard-map legend.
public enum StateGridStatusSG: String, Hashable, CaseIterable, Sendable {
    case empty       // open / available — white @ 0.18
    case occupied    // a unit is parked here — brand blue @ 0.90
    case reserved    // held for an inbound — warning amber @ 0.90
    case maintenance // out of service — danger red @ 0.90
}

/// One cell in the grid. `row`/`col` are zero-based coordinates; `label` is the
/// short glyph painted inside the cell (trailer #, slot id, or blank for open
/// slots). `id` defaults to the coordinate so callers can pass raw spots.
public struct StateGridCellSG: Identifiable, Hashable, Sendable {
    public let id: String
    public let row: Int
    public let col: Int
    public var status: StateGridStatusSG
    public var label: String
    /// When false the cell renders dimmed and ignores taps/drags (e.g. a
    /// track segment outside the addressable yard). Defaults true.
    public var isInteractive: Bool

    public init(
        id: String? = nil,
        row: Int,
        col: Int,
        status: StateGridStatusSG,
        label: String = "",
        isInteractive: Bool = true
    ) {
        self.id = id ?? "\(row)-\(col)"
        self.row = row
        self.col = col
        self.status = status
        self.label = label
        self.isInteractive = isInteractive
    }
}

/// The full grid payload. `rows`×`cols` define the coordinate space; `cells`
/// are sparse — any (row,col) absent from the array renders as an empty slot.
public struct StateGridModel: Equatable, Sendable {
    public var rows: Int
    public var cols: Int
    public var cells: [StateGridCellSG]
    /// Micro-caps eyebrow shown top-left ("TRACK GRID · LIVE").
    public var eyebrow: String
    /// Right-aligned meta shown next to the eyebrow ("Corwith · 24 tracks").
    public var meta: String

    public init(
        rows: Int,
        cols: Int,
        cells: [StateGridCellSG],
        eyebrow: String = "TRACK GRID · LIVE",
        meta: String = ""
    ) {
        self.rows = rows
        self.cols = cols
        self.cells = cells
        self.eyebrow = eyebrow
        self.meta = meta
    }

    public static func == (lhs: StateGridModel, rhs: StateGridModel) -> Bool {
        lhs.rows == rhs.rows && lhs.cols == rhs.cols &&
        lhs.eyebrow == rhs.eyebrow && lhs.meta == rhs.meta &&
        lhs.cells == rhs.cells
    }
}

// MARK: - StateGrid (the primitive)

/// A bespoke, data-driven, interactive status-cell coordinate grid.
///
///     StateGrid(
///         model: yardModel,
///         selection: $picked,
///         onSelect: { cell in ... },
///         onMove:   { from, to in viewModel.moveTrailer(from, to) }
///     )
///
/// - `selection`: two-way binding to the selected cell id (nil = none).
/// - `onSelect`:  fired on tap with the chosen cell.
/// - `onMove`:    when non-nil, enables drag-to-move; fires `(from, to)` ids
///                when an occupied/reserved cell is dropped onto another cell.
public struct StateGrid: View {

    private let model: StateGridModel
    @Binding private var selection: String?
    private let onSelect: (StateGridCellSG) -> Void
    private let onMove: ((_ from: String, _ to: String) -> Void)?
    private let showsLegend: Bool

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Live drag state — the cell being dragged and the current finger
    /// translation, plus the cell currently hovered as a drop target.
    @State private var draggingID: String? = nil
    @State private var dragTranslation: CGSize = .zero
    @State private var hoverTargetID: String? = nil

    public init(
        model: StateGridModel,
        selection: Binding<String?> = .constant(nil),
        showsLegend: Bool = true,
        onSelect: @escaping (StateGridCellSG) -> Void = { _ in },
        onMove: ((_ from: String, _ to: String) -> Void)? = nil
    ) {
        self.model = model
        self._selection = selection
        self.showsLegend = showsLegend
        self.onSelect = onSelect
        self.onMove = onMove
    }

    // MARK: Body

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            header
            gridBody
            if showsLegend { legend }
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(palette.bgCardSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: model)
        .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.78),
                   value: selection)
    }

    // MARK: Header (eyebrow + right meta) — SVG :33–34

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.eyebrow)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: Space.s2)
            if !model.meta.isEmpty {
                Text(model.meta)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    // MARK: Grid — geometry-driven layout, verbatim cell rhythm

    private var gridBody: some View {
        GeometryReader { geo in
            let metrics = StateGridMetricsSG(
                availableWidth: geo.size.width,
                cols: max(model.cols, 1),
                rows: max(model.rows, 1)
            )
            ZStack(alignment: .topLeading) {
                ForEach(allCoordinates, id: \.self) { coord in
                    cellView(for: coord, metrics: metrics)
                }
            }
            .frame(width: geo.size.width, height: metrics.gridHeight, alignment: .topLeading)
        }
        .frame(height: gridIntrinsicHeight)
    }

    /// Every coordinate in the rows×cols space, so absent cells still paint as
    /// open slots. Sorted row-major for a stable ForEach identity.
    private var allCoordinates: [StateGridCoordSG] {
        var out: [StateGridCoordSG] = []
        out.reserveCapacity(model.rows * model.cols)
        for r in 0..<max(model.rows, 1) {
            for c in 0..<max(model.cols, 1) {
                out.append(StateGridCoordSG(row: r, col: c))
            }
        }
        return out
    }

    /// O(1)-ish resolution of a coordinate to its sparse cell (or a synthesized
    /// open slot). The map is rebuilt per body pass — fine for yard-scale grids.
    private var cellIndex: [String: StateGridCellSG] {
        var map: [String: StateGridCellSG] = [:]
        for cell in model.cells { map["\(cell.row)-\(cell.col)"] = cell }
        return map
    }

    private func resolved(_ coord: StateGridCoordSG) -> StateGridCellSG {
        cellIndex["\(coord.row)-\(coord.col)"]
            ?? StateGridCellSG(row: coord.row, col: coord.col, status: .empty)
    }

    /// Intrinsic height for the grid block at the canonical 400pt-wide card —
    /// keeps the GeometryReader from collapsing to zero in a VStack.
    private var gridIntrinsicHeight: CGFloat {
        let metrics = StateGridMetricsSG(
            availableWidth: Device.width - Space.s4 * 2 - Space.s4 * 2,
            cols: max(model.cols, 1),
            rows: max(model.rows, 1)
        )
        return metrics.gridHeight
    }

    // MARK: One cell

    @ViewBuilder
    private func cellView(for coord: StateGridCoordSG, metrics: StateGridMetricsSG) -> some View {
        let cell = resolved(coord)
        let isSelected = selection == cell.id && cell.isInteractive
        let isDragging = draggingID == cell.id
        let isHoverTarget = hoverTargetID == cell.id && draggingID != nil && draggingID != cell.id
        let origin = metrics.origin(row: coord.row, col: coord.col)

        StateGridCellViewSG(
            cell: cell,
            width: metrics.cellWidth,
            height: metrics.cellHeight,
            isSelected: isSelected,
            isHoverTarget: isHoverTarget,
            fill: fillColor(for: cell.status),
            textColor: cellTextColor(for: cell.status)
        )
        .offset(x: origin.x, y: origin.y)
        .offset(isDragging ? dragTranslation : .zero)
        .zIndex(isDragging ? 10 : (isSelected ? 2 : 1))
        .scaleEffect(isDragging ? 1.08 : 1.0)
        .shadow(color: isDragging ? Brand.blue.opacity(0.45) : .clear,
                radius: isDragging ? 10 : 0, y: isDragging ? 6 : 0)
        .allowsHitTesting(cell.isInteractive)
        .onTapGesture { select(cell) }
        .gesture(moveGesture(for: cell, metrics: metrics))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: cell))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Selection

    private func select(_ cell: StateGridCellSG) {
        guard cell.isInteractive else { return }
        if reduceMotion {
            selection = cell.id
        } else {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                selection = cell.id
            }
        }
        onSelect(cell)
    }

    // MARK: Drag-to-move

    private func moveGesture(
        for cell: StateGridCellSG,
        metrics: StateGridMetricsSG
    ) -> some Gesture {
        // Only occupied/reserved cells can be picked up, and only when an
        // onMove handler is wired. A high minimumDistance lets taps win.
        let canDrag = onMove != nil
            && cell.isInteractive
            && (cell.status == .occupied || cell.status == .reserved)

        return DragGesture(minimumDistance: canDrag ? 8 : .infinity)
            .onChanged { value in
                guard canDrag else { return }
                if draggingID == nil { draggingID = cell.id }
                dragTranslation = value.translation
                hoverTargetID = metrics.hitTest(
                    fromRow: cell.row, fromCol: cell.col,
                    translation: value.translation,
                    rows: model.rows, cols: model.cols
                )
            }
            .onEnded { _ in
                guard canDrag else { return }
                let from = cell.id
                let target = hoverTargetID
                draggingID = nil
                hoverTargetID = nil
                withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) {
                    dragTranslation = .zero
                }
                if let target, target != from {
                    onMove?(from, target)
                }
            }
    }

    // MARK: Legend — SVG :67–74

    private var legend: some View {
        HStack(spacing: Space.s4) {
            ForEach(StateGridStatusSG.allCases, id: \.self) { status in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(fillColor(for: status))
                        .frame(width: 12, height: 12)
                    Text(legendLabel(for: status))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Palette mapping — verbatim to SVG fills

    private func fillColor(for status: StateGridStatusSG) -> Color {
        switch status {
        case .empty:       return Color.white.opacity(0.18)   // #FFFFFF / 0.18
        case .occupied:    return Brand.blue.opacity(0.90)    // #1473FF / 0.9
        case .reserved:    return Brand.warning.opacity(0.90) // #FFA726 / 0.9
        case .maintenance: return Brand.danger.opacity(0.90)  // #F44336 / 0.9
        }
    }

    private func cellTextColor(for status: StateGridStatusSG) -> Color {
        switch status {
        case .empty: return palette.textSecondary
        default:     return .white
        }
    }

    private func legendLabel(for status: StateGridStatusSG) -> String {
        switch status {
        case .empty:       return "Open"
        case .occupied:    return "Occupied"
        case .reserved:    return "Reserved"
        case .maintenance: return "Maint"
        }
    }

    private func accessibilityLabel(for cell: StateGridCellSG) -> String {
        let coord = "Row \(cell.row + 1), column \(cell.col + 1)"
        let state: String
        switch cell.status {
        case .empty:       state = "open"
        case .occupied:    state = "occupied"
        case .reserved:    state = "reserved"
        case .maintenance: state = "maintenance"
        }
        return cell.label.isEmpty ? "\(coord), \(state)" : "\(coord), \(state), \(cell.label)"
    }
}

// MARK: - Coordinate (private, SG-suffixed)

private struct StateGridCoordSG: Hashable {
    let row: Int
    let col: Int
}

// MARK: - Metrics (private) — derives the verbatim cell rhythm from width

/// Reproduces the 628 geometry: 38×28 cells on a ~46pt horizontal / ~36pt
/// vertical stride. Rather than hard-pinning those numbers (which would clip on
/// narrower devices), we hold the SVG's 38:9 cell:gutter ratio and the 38:28
/// aspect, then scale to fill the available width.
private struct StateGridMetricsSG {
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let hGap: CGFloat
    let vGap: CGFloat
    let cols: Int
    let rows: Int

    init(availableWidth: CGFloat, cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        // SVG ratios: cell 38 wide, horizontal gutter ≈ 8–9 (stride 46/47).
        let gutterRatio: CGFloat = 9.0 / 38.0
        let widthForCells = max(availableWidth, 1)
        // width = cols*cw + (cols-1)*cw*gutterRatio  →  solve for cw
        let denom = CGFloat(cols) + CGFloat(max(cols - 1, 0)) * gutterRatio
        let cw = widthForCells / max(denom, 1)
        self.cellWidth = cw
        self.hGap = cw * gutterRatio
        // SVG cell aspect 38:28 ≈ 0.7368; vertical stride 36 → gutter 8 over 28.
        self.cellHeight = cw * (28.0 / 38.0)
        self.vGap = self.cellHeight * (8.0 / 28.0)
    }

    var gridHeight: CGFloat {
        CGFloat(rows) * cellHeight + CGFloat(max(rows - 1, 0)) * vGap
    }

    func origin(row: Int, col: Int) -> CGPoint {
        CGPoint(
            x: CGFloat(col) * (cellWidth + hGap),
            y: CGFloat(row) * (cellHeight + vGap)
        )
    }

    /// Resolve a drag translation (from a source cell) to the target cell id
    /// whose rect the finger currently sits over, clamped to the grid. Returns
    /// nil when the finger is outside the grid bounds.
    func hitTest(
        fromRow: Int, fromCol: Int,
        translation: CGSize,
        rows: Int, cols: Int
    ) -> String? {
        let originX = CGFloat(fromCol) * (cellWidth + hGap)
        let originY = CGFloat(fromRow) * (cellHeight + vGap)
        let cx = originX + cellWidth / 2 + translation.width
        let cy = originY + cellHeight / 2 + translation.height
        let strideX = cellWidth + hGap
        let strideY = cellHeight + vGap
        guard strideX > 0, strideY > 0 else { return nil }
        let col = Int((cx / strideX).rounded(.down))
        let row = Int((cy / strideY).rounded(.down))
        guard row >= 0, row < rows, col >= 0, col < cols else { return nil }
        return "\(row)-\(col)"
    }
}

// MARK: - Cell view (private) — the rounded status slot, SVG :35

private struct StateGridCellViewSG: View {
    let cell: StateGridCellSG
    let width: CGFloat
    let height: CGFloat
    let isSelected: Bool
    let isHoverTarget: Bool
    let fill: Color
    let textColor: Color

    @Environment(\.palette) private var palette

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
    }

    var body: some View {
        shape
            .fill(fill)
            .frame(width: width, height: height)
            .overlay(label)
            .overlay(selectionRing)
            .overlay(hoverRing)
            .opacity(cell.isInteractive ? 1.0 : 0.45)
            .contentShape(shape)
    }

    @ViewBuilder
    private var label: some View {
        if !cell.label.isEmpty {
            Text(cell.label)
                .font(.system(size: max(8, min(11, height * 0.34)),
                              weight: .semibold, design: .monospaced))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private var selectionRing: some View {
        if isSelected {
            shape
                .strokeBorder(LinearGradient.diagonal, lineWidth: 2)
                .shadow(color: Brand.magenta.opacity(0.5), radius: 6)
        }
    }

    @ViewBuilder
    private var hoverRing: some View {
        if isHoverTarget {
            shape
                .strokeBorder(Brand.success, lineWidth: 2)
                .background(shape.fill(Brand.success.opacity(0.12)))
        }
    }
}

// MARK: - Preview (sample data — clearly a preview)

#if DEBUG
private enum StateGridPreviewDataSG {
    /// A 6-col × 5-row track grid mirroring the 628 occupancy mosaic.
    static var yard: StateGridModel {
        var cells: [StateGridCellSG] = []
        // Row-major statuses transcribed loosely from the SVG mosaic so the
        // preview reads like the canonical yard map.
        let pattern: [[StateGridStatusSG]] = [
            [.occupied, .occupied, .empty,    .occupied, .reserved, .empty],
            [.occupied, .empty,    .occupied, .occupied, .empty,    .occupied],
            [.empty,    .occupied, .occupied, .reserved, .occupied, .empty],
            [.occupied, .occupied, .empty,    .occupied, .occupied, .reserved],
            [.maintenance, .occupied, .occupied, .empty, .occupied, .occupied]
        ]
        var trailerSeq = 1401
        for (r, rowStatuses) in pattern.enumerated() {
            for (c, status) in rowStatuses.enumerated() {
                let label: String
                switch status {
                case .occupied, .reserved:
                    label = "T\(trailerSeq)"; trailerSeq += 1
                case .maintenance:
                    label = "OOS"
                case .empty:
                    label = ""
                }
                cells.append(
                    StateGridCellSG(row: r, col: c, status: status, label: label)
                )
            }
        }
        return StateGridModel(
            rows: 5, cols: 6, cells: cells,
            eyebrow: "TRACK GRID · LIVE",
            meta: "Corwith · 24 tracks"
        )
    }
}

private struct StateGridPreviewHostSG: View {
    @State private var model = StateGridPreviewDataSG.yard
    @State private var selection: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("StateGrid · SAMPLE PREVIEW")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(Brand.magenta)

                StateGrid(
                    model: model,
                    selection: $selection,
                    onSelect: { _ in },
                    onMove: { from, to in
                        // Swap the two cells' status/label to demonstrate the
                        // move callback live in the preview.
                        guard
                            let fi = model.cells.firstIndex(where: { $0.id == from }),
                            let ti = model.cells.firstIndex(where: { $0.id == to })
                        else { return }
                        let movedStatus = model.cells[fi].status
                        let movedLabel  = model.cells[fi].label
                        model.cells[ti].status = movedStatus
                        model.cells[ti].label  = movedLabel
                        model.cells[fi].status = .empty
                        model.cells[fi].label  = ""
                        selection = to
                    }
                )

                if let sel = selection,
                   let cell = model.cells.first(where: { $0.id == sel }) {
                    Text("Selected: \(cell.label.isEmpty ? "slot \(sel)" : cell.label) · \(cell.status.rawValue)")
                        .font(EType.caption)
                        .foregroundStyle(Theme.dark.textSecondary)
                } else {
                    Text("Tap a cell to select · drag an occupied cell to move it")
                        .font(EType.caption)
                        .foregroundStyle(Theme.dark.textTertiary)
                }
            }
            .padding(Space.s4)
        }
        .background(Theme.dark.bgPrimary)
        .environment(\.palette, Theme.dark)
    }
}

#Preview("StateGrid · Rail Yard (dark)") {
    StateGridPreviewHostSG()
}
#endif
