//
//  ReeferTempLogChart.swift
//  EusoTrip — Components · 799 Reefer Temp Log
//
//  A bespoke zone-temperature line chart for refrigerated (reefer) hauls.
//  Plots up to three probe traces across a time axis — FRONT (nose, nearest
//  the reefer unit), CENTER, and REAR (tail, furthest from the supply air) —
//  against two reference rails:
//
//    • SETPOINT  — the commanded box temperature (e.g. 34°F). Subtle solid
//                  hairline so the operator reads "where we asked it to sit".
//    • FSMA CEILING — the Sanitary-Transportation excursion limit (e.g. 40°F).
//                  Dashed, near the top, in danger red. Crossing it is a
//                  reportable temperature excursion under the FSMA Sanitary
//                  Transportation of Human & Animal Food rule.
//
//  Reefer air stratifies: the REAR probe (last to receive chilled supply
//  air) drifts warm first when the unit can't keep up — a defrost cycle, a
//  failed door seal, or a dying compressor. So the REAR trace is the one we
//  watch climb toward the ceiling; when its recent slope is positive and it
//  is within the warn band of the ceiling we surface a WARN end-state: a
//  filled, pulsing end-dot + an inline label ("38.4°F ↑") and a synchronized
//  pulse on the ceiling rail, plus a soft ceiling-approach glow.
//
//  Drawing & motion
//  ----------------
//  Traces draw in left→right via an animatable `trim`-style progress baked
//  into each Shape's `animatableData` (so SwiftUI interpolates the partial
//  polyline frame-by-frame rather than snapping). The three traces are
//  staggered, each ~0.9s on a cubic-bezier(0.4, 0, 0.2, 1) "standard" curve.
//  Once the rear trace finishes drawing, the warn pulse + ceiling pulse run
//  on a TimelineView heartbeat.
//
//  Accessibility
//  -------------
//  Honors @Environment(\.accessibilityReduceMotion): when on, every trace is
//  drawn fully and statically (progress = 1, no stagger), the pulse is frozen
//  at its resting value, and the ceiling-approach glow is shown at a constant
//  low intensity rather than breathing. An aggregated accessibilityLabel
//  summarizes the warn state for VoiceOver.
//
//  Self-contained: defines its own data model (TempZone) and depends only on
//  the EusoTrip design system (Brand / Space / Radius / EType / palette /
//  LinearGradient.diagonal).
//

import SwiftUI

// MARK: - Data model

/// One probe trace on the reefer chart.
///
/// `readings` are (time, °F) samples in chronological order. `t` is a wall-
/// clock `Date`; the chart maps the full reading span across the x-axis, so
/// callers can hand in raw telemetry timestamps without normalizing.
public struct TempZone: Identifiable, Hashable {
    public enum Position: String, Hashable {
        case front, center, rear
    }

    public let id: String
    /// Display name — "Front" / "Center" / "Rear".
    public let name: String
    /// Where this probe sits in the box. Drives which trace is treated as the
    /// excursion-risk trace (rear) for the derived warn state.
    public let position: Position
    /// Trace color. Front green, center blue, rear orange/red per the proof.
    public let color: Color
    /// (time, tempF) samples, chronological.
    public let readings: [Reading]

    public struct Reading: Hashable {
        public let t: Date
        public let tempF: Double
        public init(t: Date, tempF: Double) {
            self.t = t
            self.tempF = tempF
        }
    }

    public init(
        id: String? = nil,
        name: String,
        position: Position,
        color: Color,
        readings: [Reading]
    ) {
        self.id = id ?? name
        self.name = name
        self.position = position
        self.color = color
        self.readings = readings
    }

    /// Most-recent sample value, if any.
    public var lastValue: Double? { readings.last?.tempF }

    /// Signed slope (°F per sample) over the trailing `window` readings. Used
    /// to decide whether a trace is trending UP toward the ceiling.
    public func recentSlope(window: Int = 4) -> Double {
        guard readings.count >= 2 else { return 0 }
        let tail = readings.suffix(max(2, window))
        guard let first = tail.first?.tempF, let last = tail.last?.tempF else { return 0 }
        return (last - first) / Double(tail.count - 1)
    }
}

// MARK: - Chart

public struct ReeferTempLogChart: View {

    // Inputs
    private let zones: [TempZone]
    private let setpointF: Double
    private let ceilingF: Double
    private let title: String

    /// Distance below the ceiling (°F) within which a rising rear trace is
    /// treated as "approaching" — drives the warn end-state + glow.
    private let warnBandF: Double

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Per-zone draw-in progress (0…1). Animated on appear with a stagger.
    @State private var drawProgress: [String: CGFloat] = [:]
    /// Set true once the rear trace has finished drawing; gates the pulse so
    /// the warning doesn't fire before the line reaches the ceiling.
    @State private var rearDrawn = false

    public init(
        zones: [TempZone],
        setpointF: Double,
        ceilingF: Double,
        warnBandF: Double = 2.0,
        title: String = "REEFER TEMP LOG"
    ) {
        self.zones = zones
        self.setpointF = setpointF
        self.ceilingF = ceilingF
        self.warnBandF = warnBandF
        self.title = title
    }

    // MARK: derived

    /// The excursion-risk trace (rear). Falls back to the warmest trailing
    /// trace if no probe is explicitly tagged `.rear`.
    private var rearZone: TempZone? {
        zones.first { $0.position == .rear }
            ?? zones.max { ($0.lastValue ?? -.infinity) < ($1.lastValue ?? -.infinity) }
    }

    /// Warn = rear trace is trending up AND its last value is inside the warn
    /// band beneath the ceiling (or already at/over it).
    private var isWarn: Bool {
        guard let r = rearZone, let last = r.lastValue else { return false }
        let approaching = last >= (ceilingF - warnBandF)
        let rising = r.recentSlope() > 0.02
        return approaching && rising
    }

    /// Y-domain. Pad a touch above the ceiling and below the coldest sample so
    /// the rails and traces never sit flush against the plot edges.
    private var yDomain: (lo: Double, hi: Double) {
        let temps = zones.flatMap { $0.readings.map(\.tempF) } + [setpointF, ceilingF]
        let rawLo = (temps.min() ?? 30) - 2
        let rawHi = max(temps.max() ?? 42, ceilingF) + 2
        // Snap to friendly 4°F ticks (…32 / 36 / 40…) so the axis labels land.
        let lo = (rawLo / 4).rounded(.down) * 4
        let hi = (rawHi / 4).rounded(.up) * 4
        return (lo, max(hi, lo + 8))
    }

    /// X-domain across all readings (earliest → latest).
    private var xDomain: (lo: Date, hi: Date)? {
        let times = zones.flatMap { $0.readings.map(\.t) }
        guard let lo = times.min(), let hi = times.max(), hi > lo else { return nil }
        return (lo, hi)
    }

    // Layout constants
    private let plotHeight: CGFloat = 168
    private let yAxisWidth: CGFloat = 34
    private let xAxisHeight: CGFloat = 18

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            header
            chartBody
            legend
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
        .onAppear(perform: kickoff)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "thermometer.snowflake")
                .font(EType.caption.weight(.bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text(title)
                .font(EType.micro).tracking(0.8)
                .foregroundStyle(palette.textSecondary)
            Spacer()
            if isWarn {
                Label("EXCURSION RISK", systemImage: "exclamationmark.triangle.fill")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(Brand.danger)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(palette.tintDanger))
            }
        }
    }

    // MARK: chart body

    private var chartBody: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { tl in
            // Heartbeat 0…1 for the warn pulse. Frozen at rest under reduce-motion.
            let beat = pulseValue(at: tl.date)

            HStack(alignment: .top, spacing: 0) {
                yAxis
                VStack(spacing: 0) {
                    GeometryReader { geo in
                        plot(in: geo.size, beat: beat)
                    }
                    .frame(height: plotHeight)
                    xAxis
                }
            }
        }
    }

    // MARK: plot

    @ViewBuilder
    private func plot(in size: CGSize, beat: Double) -> some View {
        let d = yDomain

        ZStack(alignment: .topLeading) {
            // Gridlines at each 4°F tick.
            ForEach(yTicks, id: \.self) { tick in
                let y = yPos(tick, in: size.height, domain: d)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                .stroke(palette.borderFaint, lineWidth: 0.5)
            }

            // Ceiling-approach glow — a soft red wash banding the top of the
            // plot down to the ceiling line, intensifying with the pulse when
            // we're in a warn state.
            if isWarn {
                let yCeil = yPos(ceilingF, in: size.height, domain: d)
                LinearGradient(
                    colors: [Brand.danger.opacity(0.0), Brand.danger.opacity(reduceMotion ? 0.16 : 0.10 + 0.16 * beat)],
                    startPoint: .bottom, endPoint: .top
                )
                .frame(width: size.width, height: max(0, yCeil))
                .blur(radius: 8)
                .allowsHitTesting(false)
            }

            // FSMA ceiling — dashed danger rail near the top, pulsing on warn.
            ceilingRail(in: size, domain: d, beat: beat)

            // Setpoint — subtle solid hairline.
            setpointRail(in: size, domain: d)

            // Traces, draw-in left→right, staggered.
            ForEach(zones) { zone in
                let progress = drawProgress[zone.id] ?? (reduceMotion ? 1 : 0)
                TraceShape(points: normalizedPoints(for: zone, in: size, domain: d), progress: progress)
                    .stroke(
                        zone.color,
                        style: StrokeStyle(lineWidth: zone.position == .rear ? 2.4 : 1.8,
                                           lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: zone.color.opacity(0.35), radius: 3)
            }

            // Warn end-dot on the rear trace.
            if let r = rearZone, let dot = endPoint(for: r, in: size, domain: d) {
                rearEndDot(at: dot, color: r.color, beat: beat,
                           visible: (drawProgress[r.id] ?? (reduceMotion ? 1 : 0)) > 0.92,
                           label: warnDotLabel(for: r))
            }
        }
        .clipShape(Rectangle())
    }

    // MARK: rails

    @ViewBuilder
    private func ceilingRail(in size: CGSize, domain d: (lo: Double, hi: Double), beat: Double) -> some View {
        let y = yPos(ceilingF, in: size.height, domain: d)
        let pulse = (isWarn && !reduceMotion) ? beat : (isWarn ? 1 : 0)
        Path { p in
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: size.width, y: y))
        }
        .stroke(
            Brand.danger.opacity(0.45 + 0.45 * pulse),
            style: StrokeStyle(lineWidth: 1.0 + 0.6 * pulse, dash: [5, 4])
        )
        .overlay(alignment: .topTrailing) {
            Text("FSMA \(tempLabel(ceilingF))")
                .font(EType.micro).tracking(0.4)
                .foregroundStyle(Brand.danger.opacity(0.85))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Capsule().fill(palette.tintDanger))
                .offset(y: max(0, y - 9))
                .padding(.trailing, 2)
        }
    }

    @ViewBuilder
    private func setpointRail(in size: CGSize, domain d: (lo: Double, hi: Double)) -> some View {
        let y = yPos(setpointF, in: size.height, domain: d)
        Path { p in
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: size.width, y: y))
        }
        .stroke(palette.textTertiary.opacity(0.55), lineWidth: 0.75)
        .overlay(alignment: .topLeading) {
            Text("SET \(tempLabel(setpointF))")
                .font(EType.micro).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
                .offset(y: max(0, y - 11))
                .padding(.leading, 2)
        }
    }

    // MARK: rear end-dot (warn)

    @ViewBuilder
    private func rearEndDot(at point: CGPoint, color: Color, beat: Double, visible: Bool, label: String?) -> some View {
        let warn = isWarn
        let pulse = (warn && !reduceMotion) ? beat : 0
        let ringScale = 1.0 + 0.9 * pulse
        let ringOpacity = warn ? (0.55 * (1 - pulse)) : 0

        ZStack {
            // Expanding warn ring (only paints in warn state).
            if warn {
                Circle()
                    .stroke(Brand.danger, lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)
            }
            // Filled end-dot.
            Circle()
                .fill(warn ? Brand.danger : color)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(palette.bgPage, lineWidth: 1.5))
        }
        .position(x: point.x, y: point.y)
        .opacity(visible ? 1 : 0)

        // Inline value label ("38.4°F ↑"). Anchored just up-left of the dot
        // so it doesn't collide with the right edge.
        if visible, let label {
            Text(label)
                .font(EType.caption.weight(.bold)).monospacedDigit()
                .foregroundStyle(warn ? Brand.danger : color)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(
                    Capsule().fill(palette.bgPage.opacity(0.85))
                        .overlay(Capsule().stroke((warn ? Brand.danger : color).opacity(0.5), lineWidth: 0.75))
                )
                .fixedSize()
                .position(x: max(34, point.x - 26), y: max(12, point.y - 16))
        }
    }

    private func warnDotLabel(for zone: TempZone) -> String? {
        guard let v = zone.lastValue else { return nil }
        let arrow = zone.recentSlope() > 0.02 ? " ↑" : (zone.recentSlope() < -0.02 ? " ↓" : "")
        // One decimal on the live end-dot (e.g. "38.4°F ↑") — the dot is the
        // precise live read, while the axis ticks stay integer.
        return preciseTempLabel(v) + arrow
    }

    // MARK: y-axis

    private var yAxis: some View {
        GeometryReader { geo in
            let d = yDomain
            ZStack(alignment: .topTrailing) {
                ForEach(yTicks, id: \.self) { tick in
                    Text(tempLabel(tick))
                        .font(EType.micro).monospacedDigit()
                        .foregroundStyle(palette.textTertiary)
                        .offset(y: yPos(tick, in: geo.size.height, domain: d) - 6)
                        .padding(.trailing, 4)
                }
            }
        }
        .frame(width: yAxisWidth, height: plotHeight)
    }

    // MARK: x-axis

    private var xAxis: some View {
        HStack {
            ForEach(Array(xTickLabels.enumerated()), id: \.offset) { idx, label in
                Text(label)
                    .font(EType.micro).monospacedDigit()
                    .foregroundStyle(palette.textTertiary)
                if idx < xTickLabels.count - 1 { Spacer() }
            }
        }
        .frame(height: xAxisHeight)
        .padding(.top, 2)
    }

    // MARK: legend

    private var legend: some View {
        HStack(spacing: Space.s4) {
            ForEach(zones) { zone in
                HStack(spacing: 6) {
                    Capsule()
                        .fill(zone.position == .rear && isWarn ? Brand.danger : zone.color)
                        .frame(width: 14, height: 3)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(zone.name)
                            .font(EType.micro)
                            .foregroundStyle(palette.textSecondary)
                        Text(zone.lastValue.map(preciseTempLabel) ?? "—")
                            .font(EType.caption.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(
                                zone.position == .rear && isWarn ? Brand.danger : palette.textPrimary
                            )
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Scales & helpers

    /// 4°F ticks across the domain.
    private var yTicks: [Double] {
        let d = yDomain
        var ticks: [Double] = []
        var t = d.lo
        while t <= d.hi + 0.001 {
            ticks.append(t)
            t += 4
        }
        return ticks
    }

    /// Map a temperature to a y-pixel (inverted: hotter = higher on screen).
    private func yPos(_ tempF: Double, in height: CGFloat, domain d: (lo: Double, hi: Double)) -> CGFloat {
        guard d.hi > d.lo else { return height / 2 }
        let frac = (tempF - d.lo) / (d.hi - d.lo)
        return height * (1 - CGFloat(frac))
    }

    /// Normalize a zone's readings to plot-space CGPoints.
    private func normalizedPoints(for zone: TempZone, in size: CGSize, domain d: (lo: Double, hi: Double)) -> [CGPoint] {
        guard let x = xDomain, !zone.readings.isEmpty else { return [] }
        let span = x.hi.timeIntervalSince(x.lo)
        return zone.readings.map { r in
            let fx = span > 0 ? r.t.timeIntervalSince(x.lo) / span : 0
            return CGPoint(x: size.width * CGFloat(fx),
                           y: yPos(r.tempF, in: size.height, domain: d))
        }
    }

    /// Final (rightmost) plotted point for a zone's trace.
    private func endPoint(for zone: TempZone, in size: CGSize, domain d: (lo: Double, hi: Double)) -> CGPoint? {
        normalizedPoints(for: zone, in: size, domain: d).last
    }

    /// X-axis tick labels — first / mid / last reading times, "12a" style.
    private var xTickLabels: [String] {
        guard let x = xDomain else { return [] }
        let mid = x.lo.addingTimeInterval(x.hi.timeIntervalSince(x.lo) / 2)
        return [x.lo, mid, x.hi].map(Self.hourLabel)
    }

    private func tempLabel(_ f: Double) -> String {
        String(format: "%.0f°F", f.rounded())
    }

    private func preciseTempLabel(_ f: Double) -> String {
        String(format: "%.1f°F", f)
    }

    private static func hourLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "ha"   // "12AM"
        var s = f.string(from: date).lowercased()
        s = s.replacingOccurrences(of: ":00", with: "")
        // "12am" -> "12a"
        s = s.replacingOccurrences(of: "am", with: "a").replacingOccurrences(of: "pm", with: "p")
        return s
    }

    // MARK: - Motion

    /// 0…1 triangle/sine heartbeat for the warn pulse. Static at 0 under
    /// reduce-motion so callers don't have to special-case it.
    private func pulseValue(at date: Date) -> Double {
        guard !reduceMotion, isWarn, rearDrawn else { return 0 }
        let t = date.timeIntervalSinceReferenceDate
        // ~1.2s period.
        return 0.5 + 0.5 * sin(t * (2 * .pi / 1.2))
    }

    /// Standard-curve draw-in. cubic-bezier(0.4, 0, 0.2, 1) ≈ the Material
    /// "standard" easing the spec asks for. Staggered front → center → rear.
    private func kickoff() {
        guard !reduceMotion else {
            for z in zones { drawProgress[z.id] = 1 }
            rearDrawn = true
            return
        }
        let standard = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.9)
        // Stable stagger order: front, center, rear, then any extras.
        let ordered = zones.sorted { staggerRank($0.position) < staggerRank($1.position) }
        for (i, zone) in ordered.enumerated() {
            let delay = Double(i) * 0.22
            drawProgress[zone.id] = 0
            withAnimation(standard.delay(delay)) {
                drawProgress[zone.id] = 1
            }
        }
        // Arm the pulse only after the rear trace has fully drawn in.
        let rearDelay = Double(max(0, ordered.count - 1)) * 0.22 + 0.9
        DispatchQueue.main.asyncAfter(deadline: .now() + rearDelay) {
            rearDrawn = true
        }
    }

    private func staggerRank(_ p: TempZone.Position) -> Int {
        switch p {
        case .front:  return 0
        case .center: return 1
        case .rear:   return 2
        }
    }

    // MARK: - Accessibility

    private var accessibilitySummary: String {
        var parts: [String] = ["Reefer temperature log."]
        parts.append("Setpoint \(tempLabel(setpointF)), FSMA ceiling \(tempLabel(ceilingF)).")
        for z in zones {
            if let v = z.lastValue {
                parts.append("\(z.name) \(tempLabel(v)).")
            }
        }
        if isWarn, let r = rearZone, let v = r.lastValue {
            parts.append("Warning: \(r.name) trace rising at \(tempLabel(v)), approaching the FSMA ceiling.")
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Animatable trace shape (draw-in left→right)

/// A polyline whose visible fraction is driven by `progress` (0…1). Unlike
/// `.trim`, this interpolates along the *cumulative arc length* of the
/// polyline so the head moves at a constant on-screen speed regardless of
/// segment spacing — and `progress` is the shape's `animatableData`, so the
/// SwiftUI animation engine tweens the partial path frame-by-frame.
private struct TraceShape: Shape {
    var points: [CGPoint]
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard points.count > 1 else {
            if let only = points.first { p.move(to: only) }
            return p
        }

        let clamped = max(0, min(1, progress))
        if clamped <= 0 {
            p.move(to: points[0])
            return p
        }

        // Total arc length.
        var lengths: [CGFloat] = []
        var total: CGFloat = 0
        for i in 1..<points.count {
            let seg = hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
            lengths.append(seg)
            total += seg
        }
        guard total > 0 else {
            p.move(to: points[0])
            return p
        }

        let target = total * clamped
        p.move(to: points[0])
        var walked: CGFloat = 0
        for i in 1..<points.count {
            let seg = lengths[i - 1]
            if walked + seg <= target {
                p.addLine(to: points[i])
                walked += seg
            } else {
                // Partial final segment — stop the head mid-segment.
                let remain = target - walked
                let f = seg > 0 ? remain / seg : 0
                let x = points[i - 1].x + (points[i].x - points[i - 1].x) * f
                let y = points[i - 1].y + (points[i].y - points[i - 1].y) * f
                p.addLine(to: CGPoint(x: x, y: y))
                break
            }
        }
        return p
    }
}

// MARK: - Preview helpers

private extension Date {
    /// Build a reading time `hoursAgo` before `now`.
    static func ago(_ hoursAgo: Double, from now: Date = Date()) -> Date {
        now.addingTimeInterval(-hoursAgo * 3600)
    }
}

private func proofZones() -> [TempZone] {
    // 13 samples across ~12h (12a → now). Front holds tight to setpoint,
    // center wanders a hair, rear climbs steadily toward the 40°F ceiling and
    // ends at 38.4°F with a positive slope — the proof warn state.
    let now = Date()
    func mk(_ vals: [Double]) -> [TempZone.Reading] {
        let n = vals.count
        return vals.enumerated().map { i, v in
            .init(t: Date.ago(Double(n - 1 - i), from: now), tempF: v)
        }
    }

    let front  = mk([34.1, 33.9, 34.0, 34.2, 33.8, 34.0, 34.1, 33.9, 34.0, 34.2, 34.0, 33.9, 34.1])
    let center = mk([34.6, 34.4, 34.8, 35.1, 34.9, 35.2, 35.0, 35.3, 35.1, 35.4, 35.2, 35.5, 35.3])
    let rear   = mk([34.8, 34.9, 35.2, 35.6, 35.9, 36.3, 36.6, 36.9, 37.2, 37.5, 37.8, 38.1, 38.4])

    return [
        TempZone(name: "Front",  position: .front,  color: Brand.success, readings: front),
        TempZone(name: "Center", position: .center, color: Brand.blue,    readings: center),
        TempZone(name: "Rear",   position: .rear,   color: Brand.warning, readings: rear),
    ]
}

// MARK: - Previews

#Preview("799 Reefer Temp Log · Warn · Dark") {
    ScrollView {
        ReeferTempLogChart(
            zones: proofZones(),
            setpointF: 34,
            ceilingF: 40
        )
        .padding(Space.s4)
    }
    .background(Theme.dark.bgPage)
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("799 Reefer Temp Log · Light") {
    ScrollView {
        ReeferTempLogChart(
            zones: proofZones(),
            setpointF: 34,
            ceilingF: 40
        )
        .padding(Space.s4)
    }
    .background(Theme.light.bgPage)
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
