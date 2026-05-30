//
//  698_VesselBerthWindow.swift
//  EusoTrip — Vessel Operator · Berth Window.
//
//  CARRIER / PORT-MASTER vantage. Purpose-built berth × time OCCUPANCY GANTT:
//  time on X (next 24h), the terminal's berths on Y, each vessel call a
//  positioned bar, a live NOW line, conflict shown as overlapping hatched
//  bars. One glance answers which berth is free, when, and where the clash is.
//
//  Verbatim port of "698 Vessel Berth Window · Dark". Nav anchored to
//  VesselOperatorNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME)
//  with SHIPMENTS current (per the SVG BottomNav · SHIPMENTS active).
//
//  Wiring: vesselShipments.getBerthSchedule ({portId, berthId?} ->
//  vesselBerthAssignments[] {berthId, vesselId, voyageId, scheduledArrival,
//  scheduledDeparture, status, pilotRequired, tugboatsRequired}). RBAC
//  vesselProcedure -> {VESSEL_OPERATOR, PORT_MASTER, ...}. Mode VESSEL ·
//  country US · USLGB Long Beach Pier T · USD.
//
//  PORT-GAP: getBerthSchedule returns RAW vesselBerthAssignments rows — it
//  does NOT join portBerths.berthNumber nor a vessel display name, so the
//  lane gutter renders from the integer berthId ("B<id>") and each call
//  shows "Vessel #<vesselId>". The de-conflict copy is derived locally from
//  the first detected overlap (no server suggestion endpoint exists).
//

import SwiftUI

struct VesselBerthWindowScreen: View {
    let theme: Theme.Palette
    /// Default-valued so the screen is constructable as
    /// VesselBerthWindowScreen(theme: p) from ScreenRegistry. USLGB Long
    /// Beach Pier T is the canonical port in the wireframe; the real
    /// portId is resolved at the booking layer when known.
    var portId: Int = 0

    var body: some View {
        Shell(theme: theme) { VesselBerthWindowBody(portId: portId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

/// One row of vesselBerthAssignments as returned verbatim by
/// vesselShipments.getBerthSchedule. Timestamps arrive as ISO-8601
/// strings (or null); ints are nullable per the drizzle schema.
private struct BerthAssignment698: Decodable, Identifiable {
    let id: Int
    let vesselId: Int?
    let berthId: Int?
    let voyageId: Int?
    let scheduledArrival: String?
    let actualArrival: String?
    let scheduledDeparture: String?
    let actualDeparture: String?
    let status: String?          // scheduled | berthed | departed | cancelled
    let pilotRequired: Bool?
    let tugboatsRequired: Int?
}

// MARK: - Body

private struct VesselBerthWindowBody: View {
    let portId: Int

    @Environment(\.palette) private var palette
    @State private var assignments: [BerthAssignment698] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var now = Date()

    // Gantt geometry — verbatim from the SVG card (400-wide card, the inner
    // plot runs x=56..384 across 0..24h, lanes are 54pt tall).
    private let cardWidth: CGFloat   = 400
    private let plotLeft:  CGFloat   = 56   // x of hour 00
    private let plotRight: CGFloat   = 384  // x of hour 24
    private let laneHeight: CGFloat  = 54
    private let barHeight:  CGFloat  = 30
    private var plotSpan: CGFloat { plotRight - plotLeft }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusBarSpacer
            topBar
            titleRow
            IridescentHairline()
                .padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    loadingState
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    headerBand
                    legend
                    ganttCard
                    esangSuggestion
                    ctaPair
                }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Status bar spacer

    private var statusBarSpacer: some View {
        Color.clear.frame(height: 8)
    }

    // MARK: - Top bar (eyebrow)

    private var topBar: some View {
        HStack {
            Text("✦ VESSEL OPERATOR · BERTH WINDOW")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("USLGB · PIER T")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s4)
    }

    private var titleRow: some View {
        HStack(alignment: .center) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Text("Berth window")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .rotationEffect(.degrees(90))
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s3)
    }

    // MARK: - Header band: numbers-first

    private var headerBand: some View {
        HStack(alignment: .top, spacing: Space.s4) {
            Text("\(busyCount)/\(berthCount)")
                .font(.system(size: 34, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 2) {
                Text("BERTHS BUSY")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Text("Long Beach · Pier T")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle().fill(Brand.success).frame(width: 8, height: 8)
                    Text("\(freeWindows) windows free")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
                HStack(spacing: 8) {
                    Circle().fill(Brand.warning).frame(width: 8, height: 8)
                    Text("\(conflictCount) overlap")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(.top, Space.s3)
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: Space.s4) {
            legendDot(Brand.success, "In service")
            legendDot(Brand.info, "Booked")
            legendDot(Brand.warning, "Conflict")
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(palette.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .frame(width: 8, height: 8)
                Text("Open")
            }
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 8, height: 8)
                Text("Done")
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(palette.textSecondary)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    // MARK: - THE GANTT — berth × time occupancy (the hero)

    private var ganttCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("BERTH SCHEDULE · NEXT 24H")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("tap a window")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, 6)

            // hour axis labels
            HStack(spacing: 0) {
                ForEach(Array(stride(from: 0, through: 24, by: 4)), id: \.self) { h in
                    Text(String(format: "%02d", h))
                        .font(.system(size: 9, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.leading, plotLeftInset)
            .padding(.bottom, 4)

            // The plot: gridlines + lanes + bars + NOW line, drawn in a
            // single coordinate space so bar x maps exactly to wall time.
            ZStack(alignment: .topLeading) {
                gridlines
                lanes
                nowLine
            }
            .frame(height: laneHeight * CGFloat(max(displayBerths.count, 1)) + 8)
            .padding(.top, 8)

            footerLine
                .padding(.top, Space.s3)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    /// Plot left inset relative to the card's inner content width. The SVG
    /// plot starts at x=56 inside a 400-wide card whose left content edge is
    /// at x=20 (gutter). We approximate with a fixed gutter for berth codes.
    private let plotLeftInset: CGFloat = 36

    private var gridlines: some View {
        GeometryReader { geo in
            let left = plotLeftInset
            let span = geo.size.width - left
            ZStack(alignment: .topLeading) {
                ForEach(Array(stride(from: 0, through: 24, by: 4)), id: \.self) { h in
                    let x = left + span * CGFloat(h) / 24.0
                    Rectangle()
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 1)
                        .offset(x: x)
                }
                ForEach(0..<displayBerths.count, id: \.self) { i in
                    Rectangle()
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 1)
                        .offset(y: CGFloat(i) * laneHeight)
                }
            }
        }
    }

    private var lanes: some View {
        GeometryReader { geo in
            let left = plotLeftInset
            let span = geo.size.width - left
            ZStack(alignment: .topLeading) {
                ForEach(Array(displayBerths.enumerated()), id: \.offset) { idx, berth in
                    laneRow(berth: berth, index: idx, left: left, span: span)
                }
            }
        }
    }

    @ViewBuilder
    private func laneRow(berth: BerthLane, index: Int, left: CGFloat, span: CGFloat) -> some View {
        let yMid = CGFloat(index) * laneHeight + laneHeight / 2
        // berth code gutter
        Text(berth.code)
            .font(.system(size: 12, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(palette.textPrimary)
            .offset(x: 0, y: yMid - 8)

        if berth.calls.isEmpty {
            // OPEN all day — dashed full-width window
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(palette.textTertiary.opacity(0.5),
                                  style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                Text("open · available 00:00–24:00")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .frame(width: span, height: barHeight)
            .offset(x: left, y: yMid - barHeight / 2)
        } else {
            ForEach(berth.calls) { call in
                berthBar(call, left: left, span: span, y: yMid - barHeight / 2)
            }
            // conflict caption on the lane
            if let clash = berth.conflictLabel {
                Text(clash)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Brand.warning)
                    .offset(x: left + 4, y: yMid - barHeight / 2 - 12)
            }
        }
    }

    @ViewBuilder
    private func berthBar(_ call: BerthCall, left: CGFloat, span: CGFloat, y: CGFloat) -> some View {
        let x0 = left + span * call.startFrac
        let w  = max(span * (call.endFrac - call.startFrac), 18)
        let tint = call.kind.color
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(call.kind == .done ? Color.white.opacity(0.05) : tint.opacity(0.22))
                .overlay(
                    call.kind == .conflict
                        ? RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Brand.warning.opacity(0.75), lineWidth: 1)
                        : nil
                )
            // left accent rail
            RoundedRectangle(cornerRadius: 1.6, style: .continuous)
                .fill(call.kind == .done ? palette.textTertiary : tint)
                .frame(width: 3.2)
            HStack(spacing: 6) {
                if call.kind == .conflict {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Brand.warning)
                } else if call.kind == .inService {
                    Circle().fill(Brand.success).frame(width: 6, height: 6)
                }
                Text(call.label)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(call.kind.textColor(palette))
                    .lineLimit(1)
            }
            .padding(.leading, 10)
        }
        .frame(width: w, height: barHeight)
        .offset(x: x0, y: y)
    }

    private var nowLine: some View {
        GeometryReader { geo in
            let left = plotLeftInset
            let span = geo.size.width - left
            let x = left + span * nowFrac
            let h = laneHeight * CGFloat(max(displayBerths.count, 1))
            ZStack(alignment: .top) {
                LinearGradient.primary
                    .frame(width: 2, height: h)
                    .offset(x: x - 1)
                Circle().fill(Brand.magenta).frame(width: 7, height: 7)
                    .offset(x: x - 3.5, y: -3.5)
                Text("NOW \(nowLabel)")
                    .font(.system(size: 10, weight: .bold)).tracking(0.3)
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(LinearGradient.diagonal))
                    .offset(x: min(max(x - 31, 0), span + left - 62), y: -22)
            }
        }
    }

    private var footerLine: some View {
        Text("+ \(berthCount) berths · \(bookedToday) calls booked today · avg turn \(avgTurnLabel)")
            .font(.system(size: 10))
            .foregroundStyle(palette.textTertiary)
    }

    // MARK: - ESang suggestion

    @ViewBuilder
    private var esangSuggestion: some View {
        HStack(spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("ESANG AI")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Text(esangTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(esangSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Book a window")
            Button {
            } label: {
                Text("List view")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                        .strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(width: 148)
        }
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(spacing: Space.s2) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 360)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            Text("Loading berth schedule…")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - Derived view-model (built from REAL assignment rows)

    private enum BarKind {
        case inService   // berthed     → green
        case booked      // scheduled   → blue
        case conflict    // overlapping scheduled/berthed → amber
        case done        // departed    → grey
        case cancelled   // cancelled   → neutral

        var color: Color {
            switch self {
            case .inService: return Brand.success
            case .booked:    return Brand.info
            case .conflict:  return Brand.warning
            case .done:      return Brand.neutral
            case .cancelled: return Brand.neutral
            }
        }
        func textColor(_ p: Theme.Palette) -> Color {
            switch self {
            case .inService: return Color(hex: 0x3FE0B0)
            case .booked:    return Color(hex: 0x64B5F6)
            case .conflict:  return Brand.warning
            case .done:      return p.textTertiary
            case .cancelled: return p.textTertiary
            }
        }
    }

    private struct BerthCall: Identifiable {
        let id: Int
        let label: String
        let kind: BarKind
        let startFrac: CGFloat   // 0..1 across the 24h window
        let endFrac: CGFloat
    }

    private struct BerthLane: Identifiable {
        let id: Int
        let code: String
        let calls: [BerthCall]
        let conflictLabel: String?
    }

    /// Window origin = local midnight of `now`; the X axis spans 24h.
    private var windowStart: Date {
        Calendar.current.startOfDay(for: now)
    }
    private var windowSpan: TimeInterval { 24 * 3600 }

    private func frac(for iso: String?) -> CGFloat? {
        guard let iso, let date = Self.parse(iso) else { return nil }
        let f = (date.timeIntervalSince(windowStart)) / windowSpan
        return CGFloat(min(max(f, 0), 1))
    }

    private static let isoFormatters: [ISO8601DateFormatter] = {
        let a = ISO8601DateFormatter()
        a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let b = ISO8601DateFormatter()
        b.formatOptions = [.withInternetDateTime]
        return [a, b]
    }()
    private static func parse(_ s: String) -> Date? {
        for f in isoFormatters { if let d = f.date(from: s) { return d } }
        // Fallback: "yyyy-MM-dd HH:mm:ss" (MySQL timestamp wire form).
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df.date(from: s)
    }

    /// Build the lane model from the raw assignment rows, grouped by berthId.
    private var displayBerths: [BerthLane] {
        let grouped = Dictionary(grouping: assignments.filter { $0.berthId != nil },
                                 by: { $0.berthId! })
        let sortedBerthIds = grouped.keys.sorted()
        return sortedBerthIds.map { bid in
            let rows = grouped[bid] ?? []
            // PORT-GAP: no berthNumber in payload — render from the integer id.
            let calls: [BerthCall] = rows.compactMap { row in
                guard let s = frac(for: row.scheduledArrival),
                      let e = frac(for: row.scheduledDeparture) else { return nil }
                let kind = kindFor(row)
                // PORT-GAP: no vessel name in payload — render from vesselId.
                let label = row.vesselId.map { "Vessel #\($0)" } ?? "Vessel"
                return BerthCall(id: row.id, label: label, kind: kind,
                                 startFrac: s, endFrac: max(e, s + 0.01))
            }
            // Conflict detection: two non-cancelled calls whose windows overlap.
            let clash = conflictCaption(for: rows)
            // If a clash exists, recolor the involved calls to conflict tint.
            let painted: [BerthCall] = clash == nil ? calls : calls.map {
                BerthCall(id: $0.id, label: $0.label, kind: .conflict,
                          startFrac: $0.startFrac, endFrac: $0.endFrac)
            }
            return BerthLane(id: bid, code: "B\(bid)", calls: painted, conflictLabel: clash)
        }
    }

    private func kindFor(_ row: BerthAssignment698) -> BarKind {
        switch (row.status ?? "scheduled").lowercased() {
        case "berthed":   return .inService
        case "scheduled": return .booked
        case "departed":  return .done
        case "cancelled": return .cancelled
        default:          return .booked
        }
    }

    /// Returns a "+Nm overlap HH:mm" caption when two active calls on the
    /// same berth overlap in time; nil otherwise.
    private func conflictCaption(for rows: [BerthAssignment698]) -> String? {
        let active = rows
            .filter { ($0.status ?? "").lowercased() != "cancelled" && ($0.status ?? "").lowercased() != "departed" }
            .compactMap { row -> (Date, Date)? in
                guard let a = row.scheduledArrival, let d = row.scheduledDeparture,
                      let sa = Self.parse(a), let sd = Self.parse(d) else { return nil }
                return (sa, sd)
            }
            .sorted { $0.0 < $1.0 }
        guard active.count >= 2 else { return nil }
        for i in 0..<(active.count - 1) {
            let (_, end0) = active[i]
            let (start1, _) = active[i + 1]
            if start1 < end0 {
                let overlapMin = Int(end0.timeIntervalSince(start1) / 60)
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "HH:mm"
                return "+\(overlapMin)m overlap \(f.string(from: start1))"
            }
        }
        return nil
    }

    // MARK: - Header-band counters (all derived from real rows)

    private var berthCount: Int { displayBerths.count }
    private var busyCount: Int {
        displayBerths.filter { lane in
            lane.calls.contains { $0.kind == .inService || $0.kind == .booked || $0.kind == .conflict }
        }.count
    }
    private var freeWindows: Int { displayBerths.filter { $0.calls.isEmpty }.count }
    private var conflictCount: Int { displayBerths.filter { $0.conflictLabel != nil }.count }
    private var bookedToday: Int {
        assignments.filter { ($0.status ?? "").lowercased() != "cancelled" }.count
    }
    private var avgTurnLabel: String {
        let turns: [TimeInterval] = assignments.compactMap { row in
            guard let a = row.scheduledArrival, let d = row.scheduledDeparture,
                  let sa = Self.parse(a), let sd = Self.parse(d), sd > sa else { return nil }
            return sd.timeIntervalSince(sa)
        }
        guard !turns.isEmpty else { return "—" }
        let avgH = (turns.reduce(0, +) / Double(turns.count)) / 3600
        return String(format: "%.1fh", avgH)
    }

    // MARK: - NOW line

    private var nowFrac: CGFloat {
        CGFloat(min(max(now.timeIntervalSince(windowStart) / windowSpan, 0), 1))
    }
    private var nowLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: now)
    }

    // MARK: - ESang copy (derived from the first detected conflict)

    private var firstConflictLane: BerthLane? {
        displayBerths.first { $0.conflictLabel != nil }
    }
    private var esangTitle: String {
        if let lane = firstConflictLane, let first = lane.calls.first {
            return "Shift \(first.label) off \(lane.code)"
        }
        return "All berth windows clear"
    }
    private var esangSubtitle: String {
        if let lane = firstConflictLane, let clash = lane.conflictLabel {
            return "Clears the \(clash) on \(lane.code) · holds avg turn \(avgTurnLabel)"
        }
        return "No clashes in the next 24h · avg turn \(avgTurnLabel)"
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        now = Date()
        struct BerthIn: Encodable { let portId: Int }
        do {
            let rows: [BerthAssignment698] = try await EusoTripAPI.shared.query(
                "vesselShipments.getBerthSchedule", input: BerthIn(portId: portId))
            self.assignments = rows
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("698 · Vessel Berth Window · Night") { VesselBerthWindowScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("698 · Vessel Berth Window · Light") { VesselBerthWindowScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
