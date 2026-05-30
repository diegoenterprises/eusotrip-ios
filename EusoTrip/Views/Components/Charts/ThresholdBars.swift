//
//  ThresholdBars.swift
//  EusoTrip 2027 · BespokeChartKit
//
//  A reusable, data-driven native-SwiftUI primitive: a vertical stack of
//  horizontal ranked bars, each on a fixed 0…max track, with a threshold
//  marker line and WARN/CRIT semantic tint (green / amber / red by value vs
//  threshold). Tap a bar to select it (selection binding + onSelect).
//
//  Verbatim to the founder's SVG design language —
//    • screen 383 Catalyst Fleet Safety CSA (7 BASIC percentile rails)
//    • screen 164 / 247 Driver CSA Safety Score
//  reproduced bar-for-bar:
//    – card-internal eyebrow row: TITLE (left, micro-caps tertiary) ·
//      TRAILING CAPTION (right, e.g. "vs THRESHOLD")
//    – each row 30pt pitch: label (left, 9pt heavy tertiary) · value
//      (right, SF-Mono secondary) · track (full width, 4pt, rx2, white@0.08)
//      · fill (value/max of track) · threshold tick (1pt vertical mark)
//    – a value of 0 paints NO fill bar (matches Controlled-Substances row)
//    – footer fineprint (SF-Mono, tertiary): the legend / threshold note.
//
//  Drives: FMCSA CSA BASIC percentile bars (383 / 247), comms response
//  ranking (481), driver-roster HOS bars (404), capacity-balance bars,
//  yard-fill bars (246). NO hardcoded business data lives here — the View
//  is fed a typed public model.
//
//  Guardrails honored: only `import SwiftUI`; no `func` inside Canvas /
//  @ViewBuilder closures (logic lives in methods / computed vars); .frame
//  with explicit width/height; Doubles reduced with reduce(into: 0.0).
//  Every helper type is private + suffixed to avoid cross-file collisions.
//

import SwiftUI

// MARK: - Public data model

/// A single ranked bar. `value` is measured on a `0…scaleMax` track; the
/// `threshold` is where the WARN line is drawn. Above `threshold` the bar
/// tints WARN (amber); above `critical` (when supplied) it tints CRIT (red).
/// For FMCSA CSA this maps to a BASIC: value = percentile, threshold = 65
/// (or 80 for Hazmat / Power-Units), and "higher = worse".
public struct ThresholdBarDatum: Identifiable, Equatable {

    public let id: String
    /// Left-aligned category label, e.g. "UNSAFE DRIVING".
    public let label: String
    /// The measured value on the `0…scaleMax` track.
    public let value: Double
    /// WARN threshold — the marker line position on the track.
    public let threshold: Double
    /// Optional CRIT threshold. When the value crosses this it tints red.
    /// When `nil`, anything at/above `threshold` is WARN (amber).
    public let critical: Double?
    /// Optional formatted readout shown right-aligned. When `nil` the value
    /// is rendered as a trimmed integer (matching the SVG's "39" / "0").
    public let readout: String?
    /// When true the bar is treated as the *primary* / focus rail and (when
    /// below threshold) paints with the full iridescent brand gradient —
    /// exactly like the lead BASIC rail in 383. Secondary rails below
    /// threshold paint a softer brand-blue. Above threshold both adopt the
    /// WARN/CRIT semantic tint.
    public let isPrimary: Bool

    public init(
        id: String,
        label: String,
        value: Double,
        threshold: Double,
        critical: Double? = nil,
        readout: String? = nil,
        isPrimary: Bool = false
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.threshold = threshold
        self.critical = critical
        self.readout = readout
        self.isPrimary = isPrimary
    }
}

// MARK: - Severity (private, suffixed)

/// Where a value falls relative to its thresholds. `higherIsWorse` flips the
/// comparison so the same primitive serves "percentile (worse up)" and
/// "fill-rate (worse down)" style charts.
private enum _TBSeverity {
    case safe, warn, crit

    static func classify(
        value: Double,
        threshold: Double,
        critical: Double?,
        higherIsWorse: Bool
    ) -> _TBSeverity {
        let crit = critical
        if higherIsWorse {
            if let c = crit, value >= c { return .crit }
            return value >= threshold ? .warn : .safe
        } else {
            if let c = crit, value <= c { return .crit }
            return value <= threshold ? .warn : .safe
        }
    }
}

// MARK: - ThresholdBars (the primitive)

public struct ThresholdBars: View {

    // ---- public surface ----

    /// Ranked rows, painted top-to-bottom in array order. Pass them
    /// pre-sorted if you want a leaderboard; the primitive does not reorder.
    public let data: [ThresholdBarDatum]
    /// The full-scale end of every track (e.g. 100 for CSA percentiles).
    public let scaleMax: Double
    /// Card-internal eyebrow title, micro-caps tertiary (e.g.
    /// "CARRIER BASIC PERCENTILES"). `nil` hides the header row.
    public let title: String?
    /// Right-aligned eyebrow caption (e.g. "vs THRESHOLD"). `nil` hides it.
    public let trailingCaption: String?
    /// Footer fineprint shown under the bars in SF-Mono tertiary (e.g.
    /// "Percentile higher = worse · threshold 65 (80 HM/PU)"). `nil` hides it.
    public let footnote: String?
    /// When true, larger values are "worse" → semantic tint climbs upward
    /// (CSA percentiles). When false, smaller values are worse (e.g. an SLA
    /// hit-rate where below-threshold is the alarm state).
    public let higherIsWorse: Bool
    /// Selected row id. Two-way bound so the host can drive or read selection.
    @Binding public var selection: String?
    /// Fired on tap with the tapped datum (after the binding is updated).
    public var onSelect: (ThresholdBarDatum) -> Void

    public init(
        data: [ThresholdBarDatum],
        scaleMax: Double = 100,
        title: String? = nil,
        trailingCaption: String? = nil,
        footnote: String? = nil,
        higherIsWorse: Bool = true,
        selection: Binding<String?> = .constant(nil),
        onSelect: @escaping (ThresholdBarDatum) -> Void = { _ in }
    ) {
        self.data = data
        self.scaleMax = scaleMax
        self.title = title
        self.trailingCaption = trailingCaption
        self.footnote = footnote
        self.higherIsWorse = higherIsWorse
        self._selection = selection
        self.onSelect = onSelect
    }

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Geometry — tuned to the 383/164 card: 4pt track, 30pt row pitch.
    private let trackHeight: CGFloat = 6
    private let rowPitch: CGFloat = 34
    private let labelWidth: CGFloat = 132

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if title != nil || trailingCaption != nil {
                headerRow
            }

            VStack(spacing: 0) {
                ForEach(data) { datum in
                    rowView(for: datum)
                        .frame(height: rowPitch)
                }
            }

            if let footnote {
                Text(footnote)
                    .font(EType.mono(.micro))
                    .tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.s1)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: data)
        .animation(.easeOut(duration: 0.2), value: selection)
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: Space.s2)
            if let trailingCaption {
                Text(trailingCaption.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    // MARK: Row

    private func rowView(for datum: ThresholdBarDatum) -> some View {
        let isSelected = selection == datum.id
        let severity = _TBSeverity.classify(
            value: datum.value,
            threshold: datum.threshold,
            critical: datum.critical,
            higherIsWorse: higherIsWorse
        )

        return VStack(alignment: .leading, spacing: 6) {
            // Label · value line
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(datum.label.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(isSelected ? palette.textPrimary : palette.textTertiary)
                    .lineLimit(1)
                    .frame(width: labelWidth, alignment: .leading)

                Spacer(minLength: 0)

                Text(self.readout(for: datum))
                    .font(EType.mono(.caption))
                    .foregroundStyle(self.readoutColor(severity: severity, selected: isSelected))
                    .monospacedDigit()
            }

            // The track + fill + threshold tick.
            barTrack(for: datum, severity: severity, isSelected: isSelected)
        }
        .padding(.horizontal, Space.s1)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.05) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(
                    isSelected ? self.accentStroke(for: severity) : Color.clear,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if selection == datum.id {
                selection = nil
            } else {
                selection = datum.id
            }
            onSelect(datum)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(datum.label)
        .accessibilityValue(self.accessibilityValue(for: datum, severity: severity))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Track (Canvas-free — layered Capsules so it animates cleanly)

    private func barTrack(for datum: ThresholdBarDatum, severity: _TBSeverity, isSelected: Bool) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fillFraction = self.fraction(of: datum.value)
            let threshFraction = self.fraction(of: datum.threshold)
            let critFraction = datum.critical.map { self.fraction(of: $0) }

            ZStack(alignment: .leading) {
                // Empty track
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: trackHeight)

                // Filled portion — omitted entirely at value 0, matching the
                // SVG's Controlled-Substances row (no bar drawn).
                if datum.value > 0 {
                    Capsule()
                        .fill(self.fillStyle(for: datum, severity: severity, selected: isSelected))
                        .frame(width: max(trackHeight, width * fillFraction), height: trackHeight)
                }

                // CRIT zone hairline (when a critical threshold is supplied)
                if let critFraction {
                    self.tick(at: critFraction, in: width, color: Brand.danger.opacity(0.9))
                }

                // WARN threshold marker line.
                self.tick(at: threshFraction, in: width, color: palette.textSecondary.opacity(0.8))
            }
            .frame(height: max(trackHeight, 12), alignment: .leading)
        }
        .frame(height: 12)
    }

    private func tick(at fraction: CGFloat, in width: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(color)
            .frame(width: 1.5, height: trackHeight + 4)
            .offset(x: max(0, min(width - 1.5, width * fraction - 0.75)))
    }

    // MARK: Style resolution

    private func fraction(of v: Double) -> CGFloat {
        guard scaleMax > 0 else { return 0 }
        return CGFloat(min(max(v / scaleMax, 0), 1))
    }

    /// Fill style: below threshold a primary rail uses the full iridescent
    /// brand gradient (like 383's lead BASIC), a secondary rail a softer
    /// brand-blue. At/over the WARN/CRIT thresholds both adopt the semantic
    /// amber/red tint.
    private func fillStyle(for datum: ThresholdBarDatum, severity: _TBSeverity, selected: Bool) -> LinearGradient {
        switch severity {
        case .safe:
            if datum.isPrimary {
                return LinearGradient.diagonal
            }
            return LinearGradient(
                colors: [Brand.blue.opacity(selected ? 0.85 : 0.65),
                         Brand.blue.opacity(selected ? 0.85 : 0.65)],
                startPoint: .leading, endPoint: .trailing
            )
        case .warn:
            return LinearGradient(
                colors: [Brand.warning.opacity(0.9), Brand.warning],
                startPoint: .leading, endPoint: .trailing
            )
        case .crit:
            return LinearGradient(
                colors: [Brand.danger.opacity(0.9), Brand.danger],
                startPoint: .leading, endPoint: .trailing
            )
        }
    }

    private func accentStroke(for severity: _TBSeverity) -> Color {
        switch severity {
        case .safe: return Brand.blue.opacity(0.55)
        case .warn: return Brand.warning.opacity(0.7)
        case .crit: return Brand.danger.opacity(0.7)
        }
    }

    private func readoutColor(severity: _TBSeverity, selected: Bool) -> Color {
        switch severity {
        case .safe: return selected ? palette.textPrimary : palette.textSecondary
        case .warn: return Brand.warning
        case .crit: return Brand.danger
        }
    }

    private func readout(for datum: ThresholdBarDatum) -> String {
        if let r = datum.readout { return r }
        // Trim to an integer when the value is whole (matches "39"/"0").
        if datum.value == datum.value.rounded() {
            return String(Int(datum.value))
        }
        return String(format: "%.1f", datum.value)
    }

    private func accessibilityValue(for datum: ThresholdBarDatum, severity: _TBSeverity) -> String {
        let state: String
        switch severity {
        case .safe: state = "within threshold"
        case .warn: state = "over warning threshold"
        case .crit: state = "critical"
        }
        return "\(self.readout(for: datum)) of \(Int(scaleMax)), \(state)"
    }
}

// MARK: - Preview (clearly sample data — demonstrates DYNAMIC + INTERACTIVE)

private struct _TBPreviewHarness: View {
    @State private var selection: String? = nil
    @State private var bars: [ThresholdBarDatum] = _TBPreviewHarness.fmcsaSample

    static let fmcsaSample: [ThresholdBarDatum] = [
        ThresholdBarDatum(id: "unsafe",  label: "Unsafe Driving",  value: 39, threshold: 65, critical: 80, isPrimary: true),
        ThresholdBarDatum(id: "hos",     label: "Hours-of-Service", value: 41, threshold: 65, critical: 80),
        ThresholdBarDatum(id: "fitness", label: "Driver Fitness",   value: 10, threshold: 65, critical: 80),
        ThresholdBarDatum(id: "subst",   label: "Controlled Subst", value: 0,  threshold: 65, critical: 80),
        ThresholdBarDatum(id: "maint",   label: "Vehicle Maint",    value: 71, threshold: 65, critical: 80),
        ThresholdBarDatum(id: "hazmat",  label: "Hazmat",           value: 84, threshold: 80, critical: 90),
        ThresholdBarDatum(id: "crash",   label: "Crash Indicator",  value: 22, threshold: 65, critical: 80)
    ]

    static let commsSample: [ThresholdBarDatum] = [
        ThresholdBarDatum(id: "n1", label: "Night Dispatch",  value: 96, threshold: 90, readout: "96%", isPrimary: true),
        ThresholdBarDatum(id: "n2", label: "Day Dispatch",    value: 88, threshold: 90, readout: "88%"),
        ThresholdBarDatum(id: "n3", label: "Weekend Desk",    value: 72, threshold: 90, critical: 70, readout: "72%"),
        ThresholdBarDatum(id: "n4", label: "After-Hours",     value: 64, threshold: 90, critical: 70, readout: "64%")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s5) {
                // Live randomize button proves the animated value transition.
                Button("Resync FMCSA (animate)") {
                    bars = bars.map {
                        ThresholdBarDatum(
                            id: $0.id, label: $0.label,
                            value: Double(Int.random(in: 0...95)),
                            threshold: $0.threshold, critical: $0.critical,
                            readout: $0.readout, isPrimary: $0.isPrimary
                        )
                    }
                }
                .font(EType.caption)
                .foregroundStyle(Brand.blue)

                // higher-is-worse percentile bars (383 / 247)
                ThresholdBars(
                    data: bars,
                    scaleMax: 100,
                    title: "Carrier BASIC Percentiles",
                    trailingCaption: "vs Threshold",
                    footnote: "Percentile higher = worse · threshold 65 (80 HM/PU)",
                    higherIsWorse: true,
                    selection: $selection,
                    onSelect: { _ in }
                )

                if let selection {
                    Text("selected · \(selection)")
                        .font(EType.mono(.caption))
                        .foregroundStyle(.secondary)
                }

                // lower-is-worse SLA ranking bars (481 comms response)
                ThresholdBars(
                    data: _TBPreviewHarness.commsSample,
                    scaleMax: 100,
                    title: "Comms Response Rate",
                    trailingCaption: "SLA 90%",
                    footnote: "Below 90% = SLA breach · red below 70%",
                    higherIsWorse: false
                )
            }
            .padding(Space.s4)
        }
        .background(Theme.dark.bgPrimary.ignoresSafeArea())
        .environment(\.palette, Theme.dark)
    }
}

#Preview("ThresholdBars · FMCSA CSA + Comms SLA") {
    _TBPreviewHarness()
}
