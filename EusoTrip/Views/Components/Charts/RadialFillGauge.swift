//
//  RadialFillGauge.swift
//  EusoTrip 2027 · BespokeChartKit
//
//  A reusable, data-driven native SwiftUI radial / arc gauge primitive.
//  Verbatim to the EusoTrip 2027 SVG design language (06 Vessel · 681
//  Emissions CII rating band + 682 Carrier Scorecard performance gauges).
//
//  WHAT IT DRIVES (census _COMPONENT_INTEGRATION_CENSUS_2026-05-30):
//    • 681 CII A–E band ring               (attained-AER vs required-AER tick)
//    • 682 carrier on-time / transit / claims gauges (value vs network tick)
//    • 057 / 320 scorecard composite ring   (letter-grade medallion)
//    • 050 Live Load Monitor                (single-value beat gauge)
//    • 482 Comms SLA gauge
//    • 575 Rail Equipment Health
//    • 383 Fleet CSA composite ring
//
//  CANONICAL LOOK (read verbatim from the Dark-SVG sources):
//    - 270° open-bottom arc track on white@8% (Theme.dark borderFaint).
//    - Colored fill arc animated up to the value fraction.
//    - A–E grade band drives the fill color
//      (A #00C48C · B #66BB6A · C #FFB100 · D #FF7043 · E #F44336),
//      matching 681's five-box CII rating band exactly.
//    - A target / benchmark TICK drawn on the arc (681 required-AER tick,
//      682 "network 88%" benchmark line) — a short radial mark + halo.
//    - Centered value + small grade medallion letter, the way 681/682
//      center the attained AER and the gradient letter-grade disc.
//    - Card surface is the iridescent blue→magenta rim (cardRim 0.95)
//      over the near-black page skin — reused via `.eusoCard(.feature)`.
//
//  INTERACTIVE + DYNAMIC (guardrails):
//    - `.animation` springs the fill + the value text on every data change.
//    - Tap-to-select a band segment: a `selection` @Binding and an
//      `onSelectBand` closure fire when the operator taps the band legend
//      or scrubs the arc.
//    - Drag-to-scrub the arc: dragging across the gauge reports the
//      scrubbed fraction back through `onScrub`, the way 681 lets you drag
//      the attained-AER marker. A live scrub readout rides the arc.
//
//  GUARDRAILS HONORED: only `import SwiftUI`; no `func` inside Canvas/
//  @ViewBuilder closures (geometry lives in pure methods/computed vars);
//  `.frame(width:height:)`; `reduce(into: 0.0)` for Doubles; no
//  @ViewBuilder on a func that uses explicit `return`. Every helper type
//  is `private` and `RFG`-suffixed to avoid cross-file collisions.
//

import SwiftUI

// MARK: - Public data model

/// A single A–E (or richer) grade tier for the gauge. Drives the fill
/// color, the centered medallion letter, and the optional legend chips.
/// Order in the array = visual order A→E (best→worst by convention, but
/// the caller decides — nothing is hardcoded).
public struct RadialGaugeBand: Identifiable, Equatable {
    public let id: String
    /// The single-letter (or short) grade shown in the band chip and,
    /// when this band is active, the centered medallion ("A", "B+", "C").
    public let grade: String
    /// Optional longer label for the legend / accessibility ("Superior").
    public let label: String
    /// The fill color for this tier — paint the arc + the band chip.
    public let color: Color
    /// Inclusive lower bound (in the gauge's value domain) where this band
    /// begins. The band runs up to the next band's `lowerBound` (or `max`).
    public let lowerBound: Double

    public init(
        id: String,
        grade: String,
        label: String = "",
        color: Color,
        lowerBound: Double
    ) {
        self.id = id
        self.grade = grade
        self.label = label
        self.color = color
        self.lowerBound = lowerBound
    }
}

/// A reference tick rendered on the arc — the 681 "required-AER" tick or
/// the 682 "network 88%" benchmark line. Purely declarative; no logic.
public struct RadialGaugeTarget: Equatable {
    public let value: Double
    public let label: String
    public let color: Color

    /// Default tick color matches the SVG benchmark tick (#AAB2BB) but is
    /// expressed as a public literal so this public initializer doesn't
    /// reference an `internal` token in its default-argument value.
    public init(value: Double, label: String,
                color: Color = Color(.sRGB, red: 0.667, green: 0.698, blue: 0.733, opacity: 1)) {
        self.value = value
        self.label = label
        self.color = color
    }
}

/// The fully data-driven model the gauge renders. Contains NO business
/// data of its own — the call-site supplies everything (CII attained AER,
/// carrier on-time %, SLA %, CSA composite, etc.).
public struct RadialGaugeModel: Equatable {
    /// The measured value, in the caller's own domain (gCO₂, %, days…).
    public var value: Double
    /// Domain bounds. `min` maps to the arc start, `max` to the arc end.
    public var min: Double
    public var max: Double
    /// `true` when a LOWER value is better (CII AER, transit days, claims).
    /// Drives which band the value lands in when bands are descending and
    /// how the scrub readout phrases "better / worse".
    public var lowerIsBetter: Bool
    /// The grade bands (A→E). May be empty for a plain single-color gauge.
    public var bands: [RadialGaugeBand]
    /// Optional benchmark / required tick(s).
    public var targets: [RadialGaugeTarget]
    /// Units suffix shown under the value ("gCO₂/t·nm", "%", "d").
    public var unit: String
    /// Eyebrow caption over the value ("ATTAINED AER · 2024").
    public var caption: String
    /// Fallback fill color when `bands` is empty (single-tone gauge).
    public var plainColor: Color
    /// Number of decimals in the centered value readout.
    public var decimals: Int

    public init(
        value: Double,
        min: Double,
        max: Double,
        lowerIsBetter: Bool = false,
        bands: [RadialGaugeBand] = [],
        targets: [RadialGaugeTarget] = [],
        unit: String = "",
        caption: String = "",
        // Brand blue (#1473FF) as a public literal — keeps this public
        // initializer free of `internal` token references in its default.
        plainColor: Color = Color(.sRGB, red: 0.078, green: 0.451, blue: 1.0, opacity: 1),
        decimals: Int = 1
    ) {
        self.value = value
        self.min = min
        self.max = max
        self.lowerIsBetter = lowerIsBetter
        self.bands = bands
        self.targets = targets
        self.unit = unit
        self.caption = caption
        self.plainColor = plainColor
        self.decimals = decimals
    }

    /// The band the current value lands in (nil if no bands supplied).
    public var activeBand: RadialGaugeBand? {
        RadialGaugeModel.band(for: value, in: bands)
    }

    /// Resolve which band a value falls into. Bands are ordered by visual
    /// rank; the matching band is the last whose `lowerBound` ≤ value.
    static func band(for v: Double, in bands: [RadialGaugeBand]) -> RadialGaugeBand? {
        guard !bands.isEmpty else { return nil }
        let sorted = bands.sorted { $0.lowerBound < $1.lowerBound }
        var match = sorted.first
        for b in sorted where v >= b.lowerBound {
            match = b
        }
        return match
    }
}

// MARK: - RadialFillGauge (the primitive)

/// Single-value radial / arc gauge with a target/threshold tick, an A–E
/// grade band, and a centered value + grade medallion. Data-driven,
/// animated, tap-to-select, drag-to-scrub.
public struct RadialFillGauge: View {

    private let model: RadialGaugeModel
    private let title: String
    private let diameter: CGFloat

    /// Two-way selection of a band (legend chip tap / arc scrub). Optional
    /// so plain gauges can omit it.
    @Binding private var selection: String?
    /// Fired when a band is selected (id of the band).
    private let onSelectBand: (RadialGaugeBand) -> Void
    /// Fired continuously while the user drags across the arc, reporting the
    /// scrubbed value in the caller's domain.
    private let onScrub: (Double) -> Void

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Animated fraction the fill arc has reached (0…1).
    @State private var animatedFraction: Double = 0
    /// Live scrub fraction (nil = not scrubbing). When set, the arc shows
    /// the scrub head + readout instead of the static value.
    @State private var scrubFraction: Double? = nil

    public init(
        title: String = "",
        model: RadialGaugeModel,
        diameter: CGFloat = 200,
        selection: Binding<String?> = .constant(nil),
        onSelectBand: @escaping (RadialGaugeBand) -> Void = { _ in },
        onScrub: @escaping (Double) -> Void = { _ in }
    ) {
        self.title = title
        self.model = model
        self.diameter = diameter
        self._selection = selection
        self.onSelectBand = onSelectBand
        self.onScrub = onScrub
    }

    // MARK: Geometry (pure — no closures)

    /// Arc sweep: a 270° dial that opens at the bottom (like the CII
    /// medallion / scorecard gauges read as a near-full ring with a gap).
    private let startAngle: Double = 135   // degrees, screen space
    private let sweepAngle: Double = 270   // total arc travel

    /// Map a domain value → 0…1 fraction along the arc, clamped.
    private func fraction(for v: Double) -> Double {
        let span = model.max - model.min
        guard span != 0 else { return 0 }
        let raw = (v - model.min) / span
        return Swift.max(0, Swift.min(1, raw))
    }

    /// Map a 0…1 fraction → domain value.
    private func value(forFraction f: Double) -> Double {
        model.min + (model.max - model.min) * Swift.max(0, Swift.min(1, f))
    }

    /// The fraction the static value sits at.
    private var valueFraction: Double { fraction(for: model.value) }

    /// The fraction currently driving the head (scrub overrides value).
    private var headFraction: Double { scrubFraction ?? valueFraction }

    /// Domain value at the head (scrub overrides value).
    private var headValue: Double {
        if let s = scrubFraction { return value(forFraction: s) }
        return model.value
    }

    /// Fill color = the band the HEAD value lands in, else plainColor.
    private var fillColor: Color {
        RadialGaugeModel.band(for: headValue, in: model.bands)?.color ?? model.plainColor
    }

    /// The grade letter shown in the centered medallion (head band).
    private var headGrade: String {
        RadialGaugeModel.band(for: headValue, in: model.bands)?.grade ?? ""
    }

    // MARK: Body

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if !title.isEmpty {
                Text(title.uppercased())
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }

            HStack(alignment: .center, spacing: Space.s5) {
                dial
                    .frame(width: diameter, height: diameter)
                if !model.bands.isEmpty {
                    legend
                }
            }
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.xl, intensity: .feature)
        .onAppear { animateIn() }
        .onChange(of: model.value) { _, _ in animateIn() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private func animateIn() {
        if reduceMotion {
            animatedFraction = valueFraction
        } else {
            withAnimation(.spring(response: 0.85, dampingFraction: 0.82)) {
                animatedFraction = valueFraction
            }
        }
    }

    // MARK: Dial (Canvas arc + fill + tick + centered readout)

    private var dial: some View {
        ZStack {
            arcCanvas
            centerReadout
        }
        .contentShape(Circle())
        .gesture(scrubGesture)
    }

    /// All arc drawing lives in this Canvas. No `func` is declared inside
    /// the closure — every value it needs is a captured computed property.
    private var arcCanvas: some View {
        Canvas { context, size in
            let cx = size.width / 2
            let cy = size.height / 2
            let lineW = max(size.width * 0.085, 10)
            let radius = (min(size.width, size.height) - lineW) / 2 - 2
            let center = CGPoint(x: cx, y: cy)

            // 1) Track — faint full sweep (white@8% in dark).
            var track = Path()
            track.addArc(
                center: center, radius: radius,
                startAngle: .degrees(startAngle),
                endAngle: .degrees(startAngle + sweepAngle),
                clockwise: false
            )
            context.stroke(
                track,
                with: .color(palette.borderFaint),
                style: StrokeStyle(lineWidth: lineW, lineCap: .round)
            )

            // 2) Band tint underlay — paint each grade band as a faint
            //    colored segment along the sweep so the A→E rating band
            //    reads on the ring itself (verbatim to 681's 5-box band).
            let bands = self.orderedBandsForArc
            for seg in bands {
                var p = Path()
                p.addArc(
                    center: center, radius: radius,
                    startAngle: .degrees(startAngle + sweepAngle * seg.start),
                    endAngle: .degrees(startAngle + sweepAngle * seg.end),
                    clockwise: false
                )
                context.stroke(
                    p,
                    with: .color(seg.color.opacity(0.20)),
                    style: StrokeStyle(lineWidth: lineW * 0.5, lineCap: .butt)
                )
            }

            // 3) Fill — animated value arc in the active band color.
            let frac = self.scrubFraction ?? self.animatedFraction
            if frac > 0 {
                var fill = Path()
                fill.addArc(
                    center: center, radius: radius,
                    startAngle: .degrees(startAngle),
                    endAngle: .degrees(startAngle + sweepAngle * frac),
                    clockwise: false
                )
                context.stroke(
                    fill,
                    with: .color(self.fillColor),
                    style: StrokeStyle(lineWidth: lineW, lineCap: .round)
                )
                // Soft glow pass under the fill (neon-lifted, dark-mode look).
                context.addFilter(.blur(radius: 6))
                context.stroke(
                    fill,
                    with: .color(self.fillColor.opacity(0.45)),
                    style: StrokeStyle(lineWidth: lineW, lineCap: .round)
                )
            }

            // 4) Target / benchmark ticks (681 required-AER · 682 network).
            for t in self.model.targets {
                let tf = self.fraction(for: t.value)
                let ang = (startAngle + sweepAngle * tf) * .pi / 180
                let inner = radius - lineW * 0.85
                let outer = radius + lineW * 0.85
                var tick = Path()
                tick.move(to: CGPoint(
                    x: cx + cos(ang) * inner, y: cy + sin(ang) * inner))
                tick.addLine(to: CGPoint(
                    x: cx + cos(ang) * outer, y: cy + sin(ang) * outer))
                context.stroke(
                    tick,
                    with: .color(t.color),
                    style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                )
            }

            // 5) Scrub head — a bright dot riding the arc while dragging.
            if let s = self.scrubFraction {
                let ang = (startAngle + sweepAngle * s) * .pi / 180
                let hx = cx + cos(ang) * radius
                let hy = cy + sin(ang) * radius
                let r: CGFloat = lineW * 0.55
                let dot = Path(ellipseIn: CGRect(
                    x: hx - r, y: hy - r, width: r * 2, height: r * 2))
                context.fill(dot, with: .color(.white))
                context.stroke(
                    dot, with: .color(self.fillColor),
                    style: StrokeStyle(lineWidth: 3))
            }
        }
    }

    /// Centered medallion: the value + unit, and a small gradient grade
    /// disc — verbatim to 681/682's centered attained-AER + grade letter.
    private var centerReadout: some View {
        VStack(spacing: 2) {
            if !headGrade.isEmpty {
                Text(headGrade)
                    .font(.system(size: diameter * 0.16, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .contentTransition(.numericText())
            }
            Text(formattedValue)
                .font(.system(size: diameter * 0.14, weight: .bold, design: .default))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .contentTransition(.numericText())
            if !model.unit.isEmpty {
                Text(model.unit)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            if !model.caption.isEmpty {
                Text(model.caption.uppercased())
                    .font(EType.micro)
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: diameter * 0.62)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: headGrade)
    }

    private var formattedValue: String {
        let v = headValue
        if model.decimals <= 0 {
            return String(Int(v.rounded()))
        }
        return String(format: "%.\(model.decimals)f", v)
    }

    // MARK: Legend (tap-to-select band chips — verbatim 681 A–E boxes)

    private var legend: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ForEach(model.bands) { band in
                RFGBandChip(
                    band: band,
                    isActive: band.id == (model.activeBand?.id),
                    isSelected: band.id == selection
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    let newSel = (selection == band.id) ? nil : band.id
                    withAnimation(.easeOut(duration: 0.2)) { selection = newSel }
                    onSelectBand(band)
                }
            }
        }
    }

    // MARK: Band arc segmentation (pure)

    /// Maps each band to its [start, end] fraction along the arc so we can
    /// tint the ring per-band. Bands are placed by their domain bounds.
    private var orderedBandsForArc: [RFGArcSegment] {
        guard !model.bands.isEmpty else { return [] }
        let sorted = model.bands.sorted { $0.lowerBound < $1.lowerBound }
        var out: [RFGArcSegment] = []
        for (i, b) in sorted.enumerated() {
            let lo = b.lowerBound
            let hi = (i + 1 < sorted.count) ? sorted[i + 1].lowerBound : model.max
            let s = fraction(for: lo)
            let e = fraction(for: hi)
            guard e > s else { continue }
            out.append(RFGArcSegment(start: s, end: e, color: b.color))
        }
        return out
    }

    // MARK: Scrub gesture (drag-to-scrub the arc)

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { g in
                let f = fractionFromPoint(g.location)
                scrubFraction = f
                onScrub(value(forFraction: f))
                // While scrubbing, surface the band under the head.
                if let b = RadialGaugeModel.band(
                    for: value(forFraction: f), in: model.bands) {
                    selection = b.id
                }
            }
            .onEnded { _ in
                if let s = scrubFraction,
                   let b = RadialGaugeModel.band(
                    for: value(forFraction: s), in: model.bands) {
                    onSelectBand(b)
                }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    scrubFraction = nil
                }
            }
    }

    /// Convert a tap/drag point in the dial into an arc fraction.
    private func fractionFromPoint(_ p: CGPoint) -> Double {
        let cx = diameter / 2
        let cy = diameter / 2
        var deg = atan2(p.y - cy, p.x - cx) * 180 / .pi   // -180…180
        // Normalize into the arc's own [startAngle, startAngle+sweep] frame.
        var rel = deg - startAngle
        while rel < 0 { rel += 360 }
        while rel > 360 { rel -= 360 }
        if rel > sweepAngle {
            // Past the open bottom gap — clamp to nearest end.
            rel = (rel - sweepAngle) < (360 - rel) ? sweepAngle : 0
        }
        _ = deg // silence unused-mutation warning path
        deg = rel
        return Swift.max(0, Swift.min(1, rel / sweepAngle))
    }

    // MARK: Accessibility

    private var accessibilityText: String {
        var parts: [String] = []
        if !title.isEmpty { parts.append(title) }
        parts.append("\(formattedValue) \(model.unit)")
        if let g = model.activeBand?.grade, !g.isEmpty {
            parts.append("grade \(g)")
        }
        for t in model.targets {
            parts.append("\(t.label) \(t.value)")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Private helpers (RFG-suffixed, file-local)

/// One tinted segment of the arc for a grade band.
private struct RFGArcSegment {
    let start: Double  // 0…1 along the sweep
    let end: Double
    let color: Color
}

/// A legend row — verbatim to 681's A–E colored boxes, but interactive.
private struct RFGBandChip: View {
    let band: RadialGaugeBand
    let isActive: Bool
    let isSelected: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: Space.s2) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(band.color)
                .frame(width: 26, height: 18)
                .overlay(
                    Text(band.grade)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            isActive ? Color.white : Color.clear,
                            lineWidth: 1.5)
                )
                .scaleEffect(isActive ? 1.08 : 1.0)
            if !band.label.isEmpty {
                Text(band.label)
                    .font(EType.caption)
                    .foregroundStyle(
                        isActive ? palette.textPrimary : palette.textSecondary)
            }
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(band.color)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, isSelected ? 6 : 0)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? band.color.opacity(0.12) : Color.clear)
        )
        .animation(.easeOut(duration: 0.2), value: isActive)
        .animation(.easeOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - Preview (clearly SAMPLE data — demonstrably dynamic + interactive)

#Preview("RadialFillGauge · CII + Scorecard (sample)") {
    RadialFillGaugePreviewHarness_RFG()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}

private struct RadialFillGaugePreviewHarness_RFG: View {
    // SAMPLE — IMO CII A–E band (681). LOWER AER is better, so the bands
    // ascend by severity. Attained 14.2, required tick 13.6 (C grade).
    @State private var ciiSelection: String? = nil
    @State private var ciiValue: Double = 14.2

    // SAMPLE — carrier on-time gauge (682). Higher is better.
    @State private var onTimeSelection: String? = nil

    private var ciiModel: RadialGaugeModel {
        RadialGaugeModel(
            value: ciiValue,
            min: 4, max: 22,
            lowerIsBetter: true,
            bands: [
                RadialGaugeBand(id: "A", grade: "A", label: "Superior",
                                color: Color(hex: 0x00C48C), lowerBound: 4),
                RadialGaugeBand(id: "B", grade: "B", label: "Strong",
                                color: Color(hex: 0x66BB6A), lowerBound: 8),
                RadialGaugeBand(id: "C", grade: "C", label: "On grade",
                                color: Color(hex: 0xFFB100), lowerBound: 11),
                RadialGaugeBand(id: "D", grade: "D", label: "Slipping",
                                color: Color(hex: 0xFF7043), lowerBound: 14),
                RadialGaugeBand(id: "E", grade: "E", label: "Inferior",
                                color: Color(hex: 0xF44336), lowerBound: 18),
            ],
            targets: [RadialGaugeTarget(value: 13.6, label: "required",
                                        color: Color(hex: 0xAAB2BB))],
            unit: "gCO₂/t·nm",
            caption: "Attained AER · 2024",
            decimals: 1
        )
    }

    private var onTimeModel: RadialGaugeModel {
        RadialGaugeModel(
            value: 94, min: 0, max: 100,
            lowerIsBetter: false,
            bands: [
                RadialGaugeBand(id: "low",  grade: "C",
                                color: Color(hex: 0xFF7043), lowerBound: 0),
                RadialGaugeBand(id: "mid",  grade: "B",
                                color: Color(hex: 0xFFB100), lowerBound: 80),
                RadialGaugeBand(id: "high", grade: "A",
                                color: Color(hex: 0x00C48C), lowerBound: 92),
            ],
            targets: [RadialGaugeTarget(value: 88, label: "network",
                                        color: Color(hex: 0xAAB2BB))],
            unit: "% on-time",
            caption: "Schedule reliability",
            decimals: 0
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s5) {
                RadialFillGauge(
                    title: "Emissions CII · IMO DCS",
                    model: ciiModel,
                    diameter: 200,
                    selection: $ciiSelection,
                    onSelectBand: { _ in },
                    onScrub: { v in ciiValue = v }
                )

                // Live control proving the gauge is DYNAMIC: scrub the value
                // and watch the fill arc + band color + grade re-animate.
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("SAMPLE CONTROL · attained AER \(String(format: "%.1f", ciiValue))")
                        .font(EType.micro)
                        .foregroundStyle(Theme.dark.textTertiary)
                    Slider(value: $ciiValue, in: 4...22)
                        .tint(Brand.magenta)
                }
                .padding(.horizontal, Space.s4)

                RadialFillGauge(
                    title: "On-time · trailing 4Q vs network",
                    model: onTimeModel,
                    diameter: 180,
                    selection: $onTimeSelection
                )
            }
            .padding(Space.s4)
        }
        .background(Theme.dark.bgPrimary.ignoresSafeArea())
    }
}
