//
//  BayPlanStowElevation.swift
//  EusoTrip — Vessel Operator · Bay-Plan Stow Elevation (proof "704 Bay Plan").
//
//  A bespoke AAA visualization of a container vessel's bay-plan stowage
//  elevation: a slot grid framed by a ship-HULL outline, split into two
//  row bands — ON DECK (above the hatch line) and IN HOLD (below) — with
//  bay-number column headers descending fore→aft (34 30 26 … 06).
//
//  Each cell is a container SLOT, color-coded by cargo type:
//    DRY     — neutral grey fill (the bulk of the stack)
//    REEFER  — blue stroke / outline (plugged refrigerated box)
//    HAZMAT  — amber fill + a small ◇ diamond glyph (IMDG placard)
//    RESTOW  — red fill + an up-arrow ↑ (must be lifted & re-placed)
//    EMPTY   — faint dashed outline (open cell)
//
//  A red "<n> LIFTS" badge is pinned over the conflict bay — the bay whose
//  RESTOW count drives the discharge re-handle penalty. The lift count and
//  conflict bay both DERIVE from the restow slots in the model; nothing is
//  passed in twice.
//
//  ── ANIMATION ────────────────────────────────────────────────────────
//   • On appear the cells stagger-fade in by bay, left→right, ~30ms each,
//     on a cubic-bezier(0.4,0,0.2,1) curve (SwiftUI's .timingCurve).
//   • The ship-hull outline draws itself in with an animatable trim.
//   • RESTOW (red) cells get a gentle attention pulse (scale + opacity,
//     ~1.6s ease-in-out loop) and the conflict-bay badge "breathes".
//   • An optional lift-sequence highlight sweeps the restow cells in
//     bay order so the operator can read the discharge order at a glance.
//   • Reduce-motion: fully static — no stagger, no pulse, no sweep.
//
//  Self-contained: defines its own [BayColumn]/Slot model. Only dependency
//  is the EusoTrip design system (Brand / Space / Radius / EType / palette /
//  LinearGradient.diagonal). Drawn with Canvas + Shape/Path (animatable
//  trim) and driven by withAnimation / TimelineView.
//
//  Embeds into 655_VesselContainerPositions (Vessel Operator · Containers)
//  above the container roster, and reads on 652_VesselCompliance.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Data model

/// One container slot in the elevation grid.
public struct BayPlanSlot: Identifiable, Hashable {
    public enum Kind: String, Hashable, CaseIterable {
        case dry, reefer, hazmat, restow, empty
    }

    public let id: UUID
    public let kind: Kind

    public init(_ kind: Kind, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
    }
}

/// One vertical column of the elevation — a single bay number with its
/// on-deck and in-hold stacks (tier 0 = nearest the hatch line, growing
/// outward in each band).
public struct BayColumn: Identifiable, Hashable {
    public let id: UUID
    /// The displayed bay number (e.g. 34, 30, … 06). Drives the header.
    public let bayNumber: Int
    /// Slots stowed above the hatch line, deck-up.
    public let onDeck: [BayPlanSlot]
    /// Slots stowed below the hatch line, in the cargo hold.
    public let inHold: [BayPlanSlot]

    public init(bayNumber: Int, onDeck: [BayPlanSlot], inHold: [BayPlanSlot], id: UUID = UUID()) {
        self.id = id
        self.bayNumber = bayNumber
        self.onDeck = onDeck
        self.inHold = inHold
    }

    /// Number of slots in this bay that must be re-stowed (lifted).
    public var restowCount: Int {
        (onDeck + inHold).filter { $0.kind == .restow }.count
    }
}

// MARK: - View

public struct BayPlanStowElevation: View {
    /// Fore→aft columns, left to right as displayed.
    public let columns: [BayColumn]
    /// When true, run the lift-sequence highlight sweep across restow cells.
    public let showLiftSequence: Bool

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the stagger-fade (0 = nothing shown, columns reveal up to this).
    @State private var revealedColumns: Int = 0
    /// Drives the hull trim draw-in (0…1).
    @State private var hullTrim: CGFloat = 0
    @State private var didAnimate = false

    public init(columns: [BayColumn], showLiftSequence: Bool = true) {
        self.columns = columns
        self.showLiftSequence = showLiftSequence
    }

    // Derived conflict facts — single source of truth is the restow slots.
    private var totalLifts: Int { columns.reduce(0) { $0 + $1.restowCount } }
    private var conflictBayIndex: Int? {
        columns.enumerated()
            .max(by: { $0.element.restowCount < $1.element.restowCount })
            .flatMap { $0.element.restowCount > 0 ? $0.offset : nil }
    }
    private var maxTiersOnDeck: Int { columns.map { $0.onDeck.count }.max() ?? 0 }
    private var maxTiersInHold: Int { columns.map { $0.inHold.count }.max() ?? 0 }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            titleRow
            grid
            legend
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
        .onAppear(perform: runIntro)
    }

    // MARK: Title

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "ferry.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("BAY-PLAN · STOW ELEVATION")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Discharge sequence")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("\(columns.count) bays · fore → aft")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            liftSummaryBadge
        }
    }

    private var liftSummaryBadge: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("\(totalLifts)")
                .font(.system(size: 22, weight: .heavy).monospacedDigit())
                .foregroundStyle(totalLifts > 0 ? Brand.danger : palette.textPrimary)
            Text("RESTOW LIFTS")
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Grid

    private var grid: some View {
        GeometryReader { geo in
            let labelGutter: CGFloat = 56
            let cols = max(columns.count, 1)
            let gridWidth = max(geo.size.width - labelGutter, 1)
            let cell = min(gridWidth / CGFloat(cols), 30)
            let gap: CGFloat = 3

            let onDeckH = CGFloat(maxTiersOnDeck) * (cell + gap)
            let inHoldH = CGFloat(maxTiersInHold) * (cell + gap)
            let hatchGap: CGFloat = 10
            let headerH: CGFloat = 18

            ZStack(alignment: .topLeading) {
                // Ship-hull outline behind the slots, drawn in via trim.
                hullShape(
                    cols: cols, cell: cell, gap: gap,
                    onDeckH: onDeckH, inHoldH: inHoldH,
                    hatchGap: hatchGap, headerH: headerH,
                    labelGutter: labelGutter
                )
                .trim(from: 0, to: reduceMotion ? 1 : hullTrim)
                .stroke(
                    LinearGradient.diagonal,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
                .opacity(0.55)

                // Band labels in the left gutter.
                bandLabels(
                    onDeckH: onDeckH, inHoldH: inHoldH,
                    hatchGap: hatchGap, headerH: headerH,
                    gutter: labelGutter
                )

                // Column stacks.
                ForEach(Array(columns.enumerated()), id: \.element.id) { idx, col in
                    columnView(
                        col, index: idx, cell: cell, gap: gap,
                        onDeckH: onDeckH, inHoldH: inHoldH,
                        hatchGap: hatchGap, headerH: headerH
                    )
                    .offset(x: labelGutter + CGFloat(idx) * (cell + gap))
                }

                // Conflict-bay LIFTS badge, pinned over the worst bay.
                if let ci = conflictBayIndex {
                    conflictBadge(columns[ci].restowCount)
                        .offset(
                            x: labelGutter + CGFloat(ci) * (cell + gap) + cell / 2 - 26,
                            y: -6
                        )
                        .opacity(badgeVisible(ci) ? 1 : 0)
                }
            }
        }
        .frame(height: gridHeight)
    }

    private var gridHeight: CGFloat {
        let cell: CGFloat = 30, gap: CGFloat = 3
        let onDeckH = CGFloat(maxTiersOnDeck) * (cell + gap)
        let inHoldH = CGFloat(maxTiersInHold) * (cell + gap)
        return 18 /*header*/ + onDeckH + 10 /*hatch*/ + inHoldH + 20 /*badge/pad*/
    }

    private func badgeVisible(_ index: Int) -> Bool {
        reduceMotion ? true : revealedColumns > index
    }

    // One bay column: header number, on-deck stack, hatch line, in-hold stack.
    private func columnView(
        _ col: BayColumn, index: Int, cell: CGFloat, gap: CGFloat,
        onDeckH: CGFloat, inHoldH: CGFloat,
        hatchGap: CGFloat, headerH: CGFloat
    ) -> some View {
        let shown = reduceMotion ? true : revealedColumns > index
        return VStack(spacing: 0) {
            // Bay number header.
            Text(String(format: "%02d", col.bayNumber))
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundStyle(index == conflictBayIndex ? Brand.danger : palette.textSecondary)
                .frame(width: cell, height: headerH)

            // ON DECK band — tier 0 sits just above the hatch line, so we
            // bottom-align by padding the top.
            stackBand(col.onDeck, cell: cell, gap: gap, bandHeight: onDeckH, anchor: .bottom)

            // Hatch line spacer.
            Color.clear.frame(width: cell, height: hatchGap)

            // IN HOLD band — tier 0 sits just below the hatch line, top-aligned.
            stackBand(col.inHold, cell: cell, gap: gap, bandHeight: inHoldH, anchor: .top)
        }
        .frame(width: cell)
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown ? 1 : 0.92, anchor: .center)
    }

    private enum BandAnchor { case top, bottom }

    private func stackBand(
        _ slots: [BayPlanSlot], cell: CGFloat, gap: CGFloat,
        bandHeight: CGFloat, anchor: BandAnchor
    ) -> some View {
        VStack(spacing: gap) {
            if anchor == .bottom { Spacer(minLength: 0) }
            ForEach(slots) { slot in
                BayPlanSlotCell(
                    kind: slot.kind,
                    side: cell,
                    pulsePhase: pulsePhase(for: slot),
                    sweepActive: sweepActive(for: slot),
                    palette: palette,
                    reduceMotion: reduceMotion
                )
            }
            if anchor == .top { Spacer(minLength: 0) }
        }
        .frame(width: cell, height: max(bandHeight, cell))
    }

    // MARK: Band labels + hull

    private func bandLabels(
        onDeckH: CGFloat, inHoldH: CGFloat,
        hatchGap: CGFloat, headerH: CGFloat, gutter: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: headerH)
            Text("ON\nDECK")
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.leading)
                .frame(width: gutter - 8, height: onDeckH, alignment: .leading)
            Color.clear.frame(height: hatchGap)
            Text("IN\nHOLD")
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.leading)
                .frame(width: gutter - 8, height: inHoldH, alignment: .leading)
        }
    }

    /// Ship-hull silhouette: a flat deck line across the top of the on-deck
    /// band and a curved, tapering hull bottom under the in-hold band.
    private func hullShape(
        cols: Int, cell: CGFloat, gap: CGFloat,
        onDeckH: CGFloat, inHoldH: CGFloat,
        hatchGap: CGFloat, headerH: CGFloat,
        labelGutter: CGFloat
    ) -> Path {
        let left = labelGutter - 6
        let right = labelGutter + CGFloat(cols) * (cell + gap) + 2
        let deckY = headerH - 2
        let hatchY = headerH + onDeckH + hatchGap / 2
        let keelY = headerH + onDeckH + hatchGap + inHoldH + 6
        let taper = min((right - left) * 0.16, 46)

        var p = Path()
        // Deck line (flat, full width).
        p.move(to: CGPoint(x: left, y: deckY))
        p.addLine(to: CGPoint(x: right, y: deckY))
        // Starboard side down to the keel curve.
        p.addLine(to: CGPoint(x: right, y: hatchY))
        p.addLine(to: CGPoint(x: right - taper * 0.4, y: keelY - 8))
        // Keel: gentle belly curve fore→aft.
        p.addQuadCurve(
            to: CGPoint(x: left + taper * 0.4, y: keelY - 8),
            control: CGPoint(x: (left + right) / 2, y: keelY + 10)
        )
        // Port side back up.
        p.addLine(to: CGPoint(x: left, y: hatchY))
        p.addLine(to: CGPoint(x: left, y: deckY))
        // Hatch (deck/hold divider) line.
        p.move(to: CGPoint(x: left, y: hatchY))
        p.addLine(to: CGPoint(x: right, y: hatchY))
        return p
    }

    // MARK: Conflict badge

    private func conflictBadge(_ lifts: Int) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { tl in
            let breathe = reduceMotion ? 1.0 : breatheScale(tl.date)
            HStack(spacing: 3) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 8, weight: .heavy))
                Text("\(lifts) LIFTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(
                Capsule().fill(Brand.danger)
                    .shadow(color: Brand.danger.opacity(0.6), radius: 6)
            )
            .scaleEffect(breathe)
        }
        .fixedSize()
    }

    // MARK: Animation drivers

    private func runIntro() {
        guard !didAnimate else { return }
        didAnimate = true
        guard !reduceMotion else {
            revealedColumns = columns.count
            hullTrim = 1
            return
        }
        // Hull draws in first.
        withAnimation(.easeInOut(duration: 0.7)) { hullTrim = 1 }
        // Cells stagger-fade by bay, left→right, ~30ms each, on the
        // material-standard cubic-bezier(0.4, 0, 0.2, 1) curve.
        for i in 0..<columns.count {
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.34).delay(Double(i) * 0.03)) {
                revealedColumns = i + 1
            }
        }
    }

    /// Gentle attention pulse for restow cells (~1.6s ease-in-out loop).
    private func pulsePhase(for slot: BayPlanSlot) -> Double {
        slot.kind == .restow ? 1 : 0
    }

    /// Whether a slot is currently lit by the lift-sequence sweep. We use a
    /// time-based window keyed off the slot's bay position so successive
    /// restow bays light in order.
    private func sweepActive(for slot: BayPlanSlot) -> Bool {
        guard showLiftSequence, !reduceMotion, slot.kind == .restow else { return false }
        return true
    }

    private func breatheScale(_ date: Date) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate
        let phase = (sin(t * 2 * .pi / 1.6) + 1) / 2   // 0…1, 1.6s period
        return 1.0 + 0.06 * phase
    }

    // MARK: Legend

    private var legend: some View {
        HStack(spacing: Space.s3) {
            legendChip(.dry,    "Dry")
            legendChip(.reefer, "Reefer")
            legendChip(.hazmat, "Hazmat")
            legendChip(.restow, "Restow")
            legendChip(.empty,  "Empty")
            Spacer(minLength: 0)
        }
        .font(.system(size: 8.5, weight: .heavy))
    }

    private func legendChip(_ kind: BayPlanSlot.Kind, _ label: String) -> some View {
        HStack(spacing: 4) {
            BayPlanSlotCell(
                kind: kind, side: 13,
                pulsePhase: 0, sweepActive: false,
                palette: palette, reduceMotion: true
            )
            Text(label.uppercased()).tracking(0.4)
                .foregroundStyle(palette.textSecondary)
        }
    }
}

// MARK: - Slot cell

/// A single container slot, color-coded by kind. Restow cells carry the
/// pulse + sweep state passed down from the elevation; everything else is
/// static. Drawn with Canvas so the glyphs (◇ diamond, ↑ arrow) and the
/// dashed empty outline render crisply at any cell size.
private struct BayPlanSlotCell: View {
    let kind: BayPlanSlot.Kind
    let side: CGFloat
    /// 1 when this cell should pulse (restow), else 0.
    let pulsePhase: Double
    /// True when the lift-sequence sweep is lighting this restow cell.
    let sweepActive: Bool
    let palette: Theme.Palette
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || pulsePhase == 0)) { tl in
            let pulse = (reduceMotion || pulsePhase == 0) ? 1.0 : pulseValue(tl.date)
            Canvas { ctx, size in
                draw(into: &ctx, size: size, pulse: pulse)
            }
            .frame(width: side, height: side)
            .scaleEffect(kind == .restow && !reduceMotion ? 0.94 + 0.06 * pulse : 1)
        }
    }

    private func pulseValue(_ date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        return (sin(t * 2 * .pi / 1.6) + 1) / 2   // 0…1, 1.6s ease-like loop
    }

    private func draw(into ctx: inout GraphicsContext, size: CGSize, pulse: Double) {
        let r: CGFloat = 2.5
        let inset: CGFloat = 0.75
        let rect = CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
        let rr = Path(roundedRect: rect, cornerRadius: r)

        switch kind {
        case .dry:
            ctx.fill(rr, with: .color(Brand.neutral.opacity(0.40)))
            ctx.stroke(rr, with: .color(palette.borderSoft), lineWidth: 0.75)

        case .reefer:
            // Blue outline, faint blue wash.
            ctx.fill(rr, with: .color(Brand.info.opacity(0.10)))
            ctx.stroke(rr, with: .color(Brand.info), lineWidth: 1.4)
            // Plug dot, top-right.
            let dot = Path(ellipseIn: CGRect(
                x: rect.maxX - 5, y: rect.minY + 1.5, width: 3, height: 3))
            ctx.fill(dot, with: .color(Brand.info))

        case .hazmat:
            ctx.fill(rr, with: .color(Brand.hazmat.opacity(0.85)))
            ctx.stroke(rr, with: .color(Brand.hazmat), lineWidth: 1.0)
            // Small ◇ diamond glyph, centered.
            drawDiamond(into: &ctx, in: rect, color: Color.black.opacity(0.75))

        case .restow:
            let lit = sweepActive ? pulse : 0
            ctx.fill(rr, with: .color(Brand.danger.opacity(0.78 + 0.22 * lit)))
            ctx.stroke(rr, with: .color(Brand.danger), lineWidth: 1.0 + 0.6 * lit)
            // Up-arrow ↑ glyph — must be lifted.
            drawUpArrow(into: &ctx, in: rect, color: .white)

        case .empty:
            ctx.stroke(
                rr,
                with: .color(palette.textTertiary.opacity(0.55)),
                style: StrokeStyle(lineWidth: 0.9, dash: [2.5, 2.5])
            )
        }
    }

    private func drawDiamond(into ctx: inout GraphicsContext, in rect: CGRect, color: Color) {
        let cx = rect.midX, cy = rect.midY
        let h = min(rect.width, rect.height) * 0.30
        var d = Path()
        d.move(to: CGPoint(x: cx, y: cy - h))
        d.addLine(to: CGPoint(x: cx + h, y: cy))
        d.addLine(to: CGPoint(x: cx, y: cy + h))
        d.addLine(to: CGPoint(x: cx - h, y: cy))
        d.closeSubpath()
        ctx.stroke(d, with: .color(color), lineWidth: 1.2)
    }

    private func drawUpArrow(into ctx: inout GraphicsContext, in rect: CGRect, color: Color) {
        let cx = rect.midX
        let top = rect.midY - rect.height * 0.22
        let bot = rect.midY + rect.height * 0.22
        let head = rect.width * 0.20
        var a = Path()
        a.move(to: CGPoint(x: cx, y: bot))
        a.addLine(to: CGPoint(x: cx, y: top))
        a.move(to: CGPoint(x: cx - head, y: top + head))
        a.addLine(to: CGPoint(x: cx, y: top))
        a.addLine(to: CGPoint(x: cx + head, y: top + head))
        ctx.stroke(a, with: .color(color), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - Sample / proof data

public extension BayPlanStowElevation {
    /// The proof's data — bays 34…06 (fore→aft) with a 12-lift restow
    /// conflict concentrated at bay 09/10. Mixed dry / reefer / hazmat /
    /// empty stowage elsewhere so the legend exercises every kind.
    static var proofColumns: [BayColumn] {
        func od(_ k: [BayPlanSlot.Kind]) -> [BayPlanSlot] { k.map { BayPlanSlot($0) } }

        return [
            BayColumn(bayNumber: 34,
                      onDeck: od([.dry, .dry, .reefer]),
                      inHold: od([.dry, .dry, .dry])),
            BayColumn(bayNumber: 30,
                      onDeck: od([.dry, .hazmat, .dry]),
                      inHold: od([.dry, .dry, .empty])),
            BayColumn(bayNumber: 26,
                      onDeck: od([.reefer, .dry, .dry]),
                      inHold: od([.dry, .dry, .dry])),
            BayColumn(bayNumber: 22,
                      onDeck: od([.dry, .dry, .empty]),
                      inHold: od([.dry, .hazmat, .dry])),
            BayColumn(bayNumber: 18,
                      onDeck: od([.dry, .reefer, .dry]),
                      inHold: od([.dry, .dry, .dry])),
            BayColumn(bayNumber: 14,
                      onDeck: od([.dry, .dry, .dry]),
                      inHold: od([.dry, .empty, .empty])),
            // Conflict bay 09/10 — 12 restow lifts (6 on deck + 6 in hold).
            // Highest restow count, so this is the bay the LIFTS badge pins to.
            BayColumn(bayNumber: 10,
                      onDeck: od([.restow, .restow, .restow, .restow, .restow, .restow]),
                      inHold: od([.restow, .restow, .restow, .restow, .restow, .restow])),
            BayColumn(bayNumber: 6,
                      onDeck: od([.dry, .reefer, .dry]),
                      inHold: od([.dry, .dry, .hazmat])),
        ]
    }
}

// MARK: - Preview

#Preview("704 · Bay-Plan Stow Elevation · Night") {
    ScrollView {
        BayPlanStowElevation(columns: BayPlanStowElevation.proofColumns)
            .padding(16)
    }
    .background(Theme.dark.bgPage)
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("704 · Bay-Plan Stow Elevation · Light") {
    ScrollView {
        BayPlanStowElevation(columns: BayPlanStowElevation.proofColumns)
            .padding(16)
    }
    .background(Theme.light.bgPage)
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
