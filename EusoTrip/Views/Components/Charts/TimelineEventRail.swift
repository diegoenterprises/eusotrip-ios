//
//  TimelineEventRail.swift
//  EusoTrip — BespokeChartKit
//
//  PRIMITIVE · vertical event ledger.
//
//  A connector spine threads a stack of semantic status dots; each row
//  carries a title, a mono location/detail subtitle, a right-aligned
//  timestamp and a per-event status chip (DONE · LIVE · ETA). An optional
//  live ETA countdown header sits above the ledger and ticks every second.
//
//  Verbatim to "05 Rail/Dark-SVG/560 Rail Live Tracking.svg" event block:
//    · 40×40 rounded-square dot (radius 10) — tinted by state
//        done    → green check on success@0.18 square
//        current → gradient ring + dot on diagonal@0.18 square ("LIVE")
//        future  → dashed neutral ring on white@0.04 square ("ETA")
//        hold/exception/warn carry their own semantic tint
//    · title 14/700 textPrimary
//    · subtitle 11 mono, textSecondary, tracking 0.4
//    · timestamp 12/700 tabular, textPrimary (right)
//    · status chip 11 under the timestamp, colored by state
//    · 1px divider (white@0.08) between rows; vertical spine through the dots
//
//  Powers (per _COMPONENT_INTEGRATION_CENSUS_2026-05-30):
//    560/565 rail tracking events · 003 vessel container timeline ·
//    692 transshipment · claim 5-step workflow · 050 lifecycle beats · HOS.
//
//  REUSABLE · DATA-DRIVEN · INTERACTIVE · DYNAMIC.
//  No hardcoded business data — the host passes [TimelineEventNode].
//  Selection is exposed as a binding + an onSelect closure; the live ETA
//  header drives an internal 1s TimelineView countdown. All state / value
//  changes animate.
//
//  Guardrails honored: only `import SwiftUI`; no `func` inside ViewBuilder
//  or Canvas closures; .frame(width:height:); reduce(into: 0.0) for Doubles;
//  no @ViewBuilder on a func that uses explicit return. Every helper type is
//  private + `Tevr`-suffixed to avoid cross-file collision.
//

import SwiftUI

// MARK: - Public data model

/// Lifecycle state of a single event row. Drives the dot glyph, the tint,
/// the spine segment color and the trailing status chip.
public enum TimelineEventState: String, Equatable, Hashable, CaseIterable, Sendable {
    /// Completed beat — green check on a success-tinted square.
    case done
    /// The live / in-progress beat — gradient ring + filled core, "LIVE".
    case current
    /// Scheduled / not-yet-reached beat — dashed neutral ring, "ETA".
    case future
    /// On-hold beat — pause glyph, warning tint.
    case hold
    /// Exception / alert beat — triangle glyph, danger tint.
    case exception
}

/// One row in the ledger. Pure value type — the host maps its API rows
/// (getRailTracking.events[], container timeline, claim steps, …) into this.
public struct TimelineEventNode: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    /// Headline, e.g. "Departed Argentine Yard".
    public var title: String
    /// Mono detail line, e.g. "Kansas City, KS · interchange BNSF". Optional.
    public var detail: String?
    /// Right-aligned timestamp label, e.g. "06:12 CT" or "now". Optional.
    public var timestamp: String?
    /// Lifecycle state — controls every semantic visual.
    public var state: TimelineEventState
    /// Overrides the trailing status chip text. Defaults derive from `state`
    /// (DONE · LIVE · ETA · HOLD · ALERT).
    public var statusLabel: String?
    /// Optional SF Symbol to paint inside the dot square instead of the
    /// state's default glyph (check / ring / dashed ring / pause / triangle).
    public var symbolName: String?

    public init(
        id: String,
        title: String,
        detail: String? = nil,
        timestamp: String? = nil,
        state: TimelineEventState,
        statusLabel: String? = nil,
        symbolName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
        self.state = state
        self.statusLabel = statusLabel
        self.symbolName = symbolName
    }
}

/// Optional live ETA header model. When supplied, the rail renders a
/// gradient-rimmed header with a destination label and a 1s-ticking
/// countdown to `arrival`. Pass `nil` to omit the header entirely.
public struct TimelineETACountdown: Equatable, Sendable {
    /// Caption above the countdown, e.g. "ETA · CORWITH · CHI".
    public var label: String
    /// Absolute arrival instant the countdown targets.
    public var arrival: Date
    /// Optional static fallback shown once the countdown reaches zero or
    /// when motion is reduced, e.g. "14:20 CT".
    public var staticETA: String?

    public init(label: String, arrival: Date, staticETA: String? = nil) {
        self.label = label
        self.arrival = arrival
        self.staticETA = staticETA
    }
}

// MARK: - TimelineEventRail (the primitive)

/// Vertical event ledger: connector spine + semantic status dots + location
/// + timestamp rows + an optional live ETA countdown header.
///
/// ```swift
/// TimelineEventRail(
///     events: nodes,
///     eta: TimelineETACountdown(label: "ETA · CORWITH · CHI",
///                               arrival: .now.addingTimeInterval(4_320)),
///     selection: $selectedID,
///     onSelect: { node in … }
/// )
/// ```
public struct TimelineEventRail: View {
    // Data
    private let events: [TimelineEventNode]
    private let eta: TimelineETACountdown?
    private let title: String?

    // Interaction
    @Binding private var selection: String?
    private let onSelect: (TimelineEventNode) -> Void

    // Layout knobs (sensible verbatim defaults; host may override)
    private let dotSize: CGFloat
    private let showSpine: Bool

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Designated initializer.
    /// - Parameters:
    ///   - events:    ordered ledger rows (top = newest/first beat).
    ///   - eta:       optional live countdown header; `nil` to omit.
    ///   - title:     optional section eyebrow above the card, e.g. "EVENTS".
    ///   - selection: two-way bound selected row id (tap-to-select). Pass a
    ///                constant binding for a read-only ledger.
    ///   - onSelect:  fired on every row tap (after the binding updates).
    ///   - dotSize:   leading status-square edge (verbatim default 40).
    ///   - showSpine: draw the vertical connector spine through the dots.
    public init(
        events: [TimelineEventNode],
        eta: TimelineETACountdown? = nil,
        title: String? = nil,
        selection: Binding<String?> = .constant(nil),
        onSelect: @escaping (TimelineEventNode) -> Void = { _ in },
        dotSize: CGFloat = 40,
        showSpine: Bool = true
    ) {
        self.events = events
        self.eta = eta
        self.title = title
        self._selection = selection
        self.onSelect = onSelect
        self.dotSize = dotSize
        self.showSpine = showSpine
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            if let eta {
                TevrCountdownHeader(model: eta, reduceMotion: reduceMotion)
            }
            ledgerCard
        }
        .animation(.easeInOut(duration: 0.28), value: events)
        .animation(.easeInOut(duration: 0.22), value: selection)
    }

    // MARK: Ledger card

    private var ledgerCard: some View {
        VStack(spacing: 0) {
            if events.isEmpty {
                emptyState
            } else {
                ForEach(Array(events.enumerated()), id: \.element.id) { idx, node in
                    TevrRow(
                        node: node,
                        index: idx,
                        isFirst: idx == 0,
                        isLast: idx == events.count - 1,
                        isSelected: selection == node.id,
                        dotSize: dotSize,
                        showSpine: showSpine,
                        palette: palette
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let isOn = selection == node.id
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            selection = isOn ? nil : node.id
                        }
                        onSelect(node)
                    }

                    if idx < events.count - 1 {
                        Divider()
                            .overlay(palette.borderFaint)
                            .padding(.leading, dotSize + Space.s4 + Space.s3)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var emptyState: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
            Text("No events recorded.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Row

private struct TevrRow: View {
    let node: TimelineEventNode
    let index: Int
    let isFirst: Bool
    let isLast: Bool
    let isSelected: Bool
    let dotSize: CGFloat
    let showSpine: Bool
    let palette: Theme.Palette

    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            // Spine + status dot column
            ZStack {
                if showSpine {
                    TevrSpine(
                        isFirst: isFirst,
                        isLast: isLast,
                        accent: TevrPalette.spineColor(node.state, palette: palette),
                        width: dotSize
                    )
                }
                TevrStatusDot(
                    state: node.state,
                    symbolOverride: node.symbolName,
                    size: dotSize,
                    palette: palette
                )
            }
            .frame(width: dotSize)

            // Text column
            VStack(alignment: .leading, spacing: 3) {
                Text(node.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                if let detail = node.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: Space.s2)

            // Timestamp + status chip column
            VStack(alignment: .trailing, spacing: 3) {
                if let ts = node.timestamp, !ts.isEmpty {
                    Text(ts)
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
                TevrStatusChip(state: node.state, override: node.statusLabel, palette: palette)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3 + 2)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(isSelected
                      ? TevrPalette.accentColor(node.state, palette: palette).opacity(0.10)
                      : Color.clear)
                .padding(.horizontal, Space.s2)
        )
        .overlay(alignment: .leading) {
            // Selection rail — a short gradient/semantic bar flush-left.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(TevrPalette.accentStyle(node.state))
                .frame(width: 3)
                .padding(.vertical, Space.s2)
                .opacity(isSelected ? 1 : 0)
        }
    }
}

// MARK: - Vertical connector spine

private struct TevrSpine: View {
    let isFirst: Bool
    let isLast: Bool
    let accent: Color
    let width: CGFloat

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let midX = width / 2
            Path { p in
                let topY: CGFloat = isFirst ? h / 2 : 0
                let bottomY: CGFloat = isLast ? h / 2 : h
                p.move(to: CGPoint(x: midX, y: topY))
                p.addLine(to: CGPoint(x: midX, y: bottomY))
            }
            .stroke(accent.opacity(0.45),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Status dot (the 40×40 square)

private struct TevrStatusDot: View {
    let state: TimelineEventState
    let symbolOverride: String?
    let size: CGFloat
    let palette: Theme.Palette

    private var squareFill: Color {
        switch state {
        case .done:      return Brand.success.opacity(0.18)
        case .current:   return Brand.blue.opacity(0.16)
        case .future:    return Color.white.opacity(0.04)
        case .hold:      return Brand.warning.opacity(0.18)
        case .exception: return Brand.danger.opacity(0.18)
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(squareFill)
                .frame(width: size, height: size)
            glyph
        }
    }

    @ViewBuilder
    private var glyph: some View {
        if let symbolOverride {
            Image(systemName: symbolOverride)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(TevrPalette.accentStyle(state))
        } else {
            switch state {
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.36, weight: .heavy))
                    .foregroundStyle(Brand.success)
            case .current:
                liveRing
            case .future:
                Circle()
                    .strokeBorder(
                        palette.textTertiary,
                        style: StrokeStyle(lineWidth: 2, dash: [3, 3])
                    )
                    .frame(width: size * 0.43, height: size * 0.43)
            case .hold:
                Image(systemName: "pause.fill")
                    .font(.system(size: size * 0.30, weight: .bold))
                    .foregroundStyle(Brand.warning)
            case .exception:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(Brand.danger)
            }
        }
    }

    // Live pulsing gradient ring + filled core (verbatim to SVG "current").
    private var liveRing: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = 0.5 + 0.5 * sin(t * 2.4)
            ZStack {
                Circle()
                    .fill(LinearGradient.diagonal)
                    .opacity(0.18 + 0.18 * pulse)
                    .frame(width: size * 0.62, height: size * 0.62)
                Circle()
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 2.2)
                    .frame(width: size * 0.46, height: size * 0.46)
                Circle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: size * 0.20, height: size * 0.20)
            }
        }
    }
}

// MARK: - Status chip (DONE · LIVE · ETA · HOLD · ALERT)

private struct TevrStatusChip: View {
    let state: TimelineEventState
    let override: String?
    let palette: Theme.Palette

    private var text: String {
        if let override, !override.isEmpty { return override }
        switch state {
        case .done:      return "DONE"
        case .current:   return "LIVE"
        case .future:    return "ETA"
        case .hold:      return "HOLD"
        case .exception: return "ALERT"
        }
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(TevrPalette.accentStyle(state))
    }
}

// MARK: - Live ETA countdown header

private struct TevrCountdownHeader: View {
    let model: TimelineETACountdown
    let reduceMotion: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.6), lineWidth: 1.25)

            HStack(spacing: Space.s3) {
                ZStack {
                    Circle()
                        .fill(LinearGradient.diagonal.opacity(0.18))
                        .frame(width: 34, height: 34)
                    Image(systemName: "timer")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.label.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                    countdownText
                }
                Spacer(minLength: 0)
                // A small live pulse so the header reads "ticking".
                if !reduceMotion {
                    TevrLivePulse()
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
        }
        .frame(height: 60)
    }

    private var countdownText: some View {
        TimelineView(.periodic(from: .now, by: reduceMotion ? 60 : 1)) { context in
            let remaining = model.arrival.timeIntervalSince(context.date)
            Group {
                if remaining <= 0 {
                    Text(model.staticETA ?? "ARRIVED")
                        .foregroundStyle(LinearGradient.diagonal)
                } else {
                    Text(TevrFormat.hms(remaining))
                        .foregroundStyle(palette.textPrimary)
                }
            }
            .font(.system(size: 22, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.25), value: remaining <= 0)
        }
    }
}

private struct TevrLivePulse: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = 0.5 + 0.5 * sin(t * 2.2)
            ZStack {
                Circle()
                    .fill(Brand.success.opacity(0.25 + 0.25 * pulse))
                    .frame(width: 16, height: 16)
                Circle()
                    .fill(Brand.success)
                    .frame(width: 7, height: 7)
            }
        }
    }
}

// MARK: - Semantic palette helpers

private enum TevrPalette {
    static func accentColor(_ state: TimelineEventState, palette: Theme.Palette) -> Color {
        switch state {
        case .done:      return Brand.success
        case .current:   return Brand.blue
        case .future:    return palette.textTertiary
        case .hold:      return Brand.warning
        case .exception: return Brand.danger
        }
    }

    static func spineColor(_ state: TimelineEventState, palette: Theme.Palette) -> Color {
        switch state {
        case .done:      return Brand.success
        case .current:   return Brand.blue
        case .future:    return palette.textTertiary
        case .hold:      return Brand.warning
        case .exception: return Brand.danger
        }
    }

    /// Gradient for the "current" beat (verbatim diagonal sweep), flat
    /// semantic color otherwise.
    static func accentStyle(_ state: TimelineEventState) -> AnyShapeStyle {
        switch state {
        case .current: return AnyShapeStyle(LinearGradient.diagonal)
        case .done:    return AnyShapeStyle(Brand.success)
        case .future:  return AnyShapeStyle(Brand.neutral)
        case .hold:    return AnyShapeStyle(Brand.warning)
        case .exception: return AnyShapeStyle(Brand.danger)
        }
    }
}

// MARK: - Formatting

private enum TevrFormat {
    /// "HH:MM:SS" remaining, or "MM:SS" under an hour.
    static func hms(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Preview (clearly SAMPLE data — demonstrates live + interactive)

private struct TevrPreviewHost: View {
    let theme: Theme.Palette
    @State private var selection: String? = "evt-3"

    private var sample: [TimelineEventNode] {
        [
            TimelineEventNode(
                id: "evt-1",
                title: "Departed Argentine Yard",
                detail: "Kansas City, KS · interchange BNSF",
                timestamp: "06:12 CT",
                state: .done
            ),
            TimelineEventNode(
                id: "evt-2",
                title: "AEI scan — Fort Madison",
                detail: "Fort Madison, IA · 78 cars confirmed",
                timestamp: "10:48 CT",
                state: .done
            ),
            TimelineEventNode(
                id: "evt-3",
                title: "In transit — Galesburg",
                detail: "tankcar UN1203 Class 3 monitored · no exceptions",
                timestamp: "now",
                state: .current
            ),
            TimelineEventNode(
                id: "evt-4",
                title: "Hold — interchange congestion",
                detail: "Cameron, IL · awaiting BNSF crew",
                timestamp: "12:30 CT",
                state: .hold
            ),
            TimelineEventNode(
                id: "evt-5",
                title: "Arrive Corwith Intermodal",
                detail: "Chicago, IL · scheduled arrival",
                timestamp: "14:20 CT",
                state: .future
            )
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                Text("TimelineEventRail · SAMPLE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)

                TimelineEventRail(
                    events: sample,
                    eta: TimelineETACountdown(
                        label: "ETA · Corwith · CHI",
                        arrival: Date().addingTimeInterval(72 * 60 + 18),
                        staticETA: "14:20 CT"
                    ),
                    title: "Events · getRailTracking",
                    selection: $selection,
                    onSelect: { _ in }
                )

                if let selection {
                    Text("selected → \(selection)")
                        .font(EType.mono(.caption))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .padding(Space.s5)
        }
        .background(theme.bgPrimary.ignoresSafeArea())
        .environment(\.palette, theme)
    }
}

#Preview("TimelineEventRail · Night") {
    TevrPreviewHost(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("TimelineEventRail · Afternoon") {
    TevrPreviewHost(theme: Theme.light)
        .preferredColorScheme(.light)
}
