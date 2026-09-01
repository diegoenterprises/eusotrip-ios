//
//  715_RailSwitchlist.swift
//  EusoTrip — 05 Rail · 715 Rail Switchlist.
//  YARD SIDE · the switching crew's ordered work · nav tab SHIPMENTS.
//
//  Faithful 1:1 port of "05 Rail/Light-SVG/715 Rail Switchlist.svg" — same
//  sections, same order, same device:
//    eyebrow → headline → subline → state chips → iridescent hairline →
//    NUMBERED MOVE SEQUENCE (cumulative-time rail down the left; each step a
//    from-track → to-track arrow with the car cut and the switching verb;
//    completed struck and settled, current anchored, remaining quiet) →
//    OFFLINE local-outbox strip → tri-country band → CTA pair.
//
//  ─── WIRING MANIFEST ─────────────────────────────────────────────────────────
//    yardManagement.getYardMoveQueue      EXISTS server/routers/yardManagement.ts:1940
//        → {moves:[{id,status,trailerNumber,fromSpot,toSpot,priority,requestedAt,
//           assignedTo,hostlerId,reason,estimatedMinutes,startedAt,completedAt}],
//           summary:{total,pending,assigned,inProgress,completed,avgCompletionMinutes},
//           hostlers:[{id,name,status,currentMove,movesCompleted}]}
//    yardManagement.assignYardMove        EXISTS server/routers/yardManagement.ts:2026  MUTATION
//    yardManagement.getYardMap            EXISTS server/routers/yardManagement.ts:379
//    railShipments.getYardTrackOccupancy EXISTS railShipments.ts:1246
//    railShipments.getRailcars            EXISTS server/routers/railShipments.ts:1192
//    railShipments.assignCarToTrack EXISTS railShipments.ts:1300  MUTATION
//    railShipments.getRailYards           EXISTS server/routers/railShipments.ts:1512
//    railShipments.getRailCrew            EXISTS server/routers/railShipments.ts:2453
//    railSwitchlist.getSwitchlist         STUB · named-gap RAIL-YRD-715-SWITCH-VERB
//    railSwitchlist.completeMove          STUB · named-gap RAIL-YRD-715-COMPLETE-MOVE
//
//  RBAC:    railReadProcedure (railShipments.ts:94) · RAIL_ENGINEER (server/_core/trpc.ts:32) holds the
//           yard-master function, RAIL_CONDUCTOR (:33) works the list. The
//           yardManagement reads and the assign write are protectedProcedure and
//           companyId-scoped.
//  WS:      WS_EVENTS.RAIL_IN_YARD (shared/websocket-events.ts:403) advances the
//           sequence when a cut lands; channel WS_CHANNELS.RAIL_YARD(yardId) (:622).
//  OFFLINE: QUEUE(yard) for move completion with a visible queued badge and a REAL
//           local outbox depth; reads are READ_CACHED(5 min) with a real cached-at.
//
//  0 stubs in the view layer · 0 mock arrays · 0 placeholders. The switching verb
//  is not a served field — yard_moves carries a `reason` enum (why the move was
//  ordered), never how it is worked — so each step renders the server's own reason
//  in the verb slot, explicitly labelled as the reason, and the elapsed clock is
//  summed only from real startedAt / completedAt stamps.
//
//  ─── S12 · DEAD PRIMARY (cured 2026-08-25) ───────────────────────────────────
//    "Complete move" shipped as a styled Text with .allowsHitTesting(false) — a
//    control that looked live and could never be pressed. It is now a REAL
//    Button with .disabled(true), because railSwitchlist.completeMove is a STUB
//    (RAIL-YRD-715-COMPLETE-MOVE) and there is no receiver to wire. The whole
//    label is dimmed so it cannot read as live, and the caption underneath
//    states the gap in place. "Assign job" was already a real Button and stays
//    wired to assignJob() → yardManagement.assignYardMove.
//
//  ─── S12 · QUEUED-WORK COUNTER (verified 2026-08-25) ─────────────────────────
//    The phantom outbox counter (`queuedCompletions`) that no code path could
//    raise is ALREADY GONE from this view; nothing here counts queued work.
//    The strip states "NOT QUEUED" and the caption says a completion is neither
//    queued nor posted, which is the true state while the write is a stub. The
//    OFFLINE line above describes the intended QUEUE(yard) design, not what is
//    shipped today; no depth is displayed until a real queue backs it.
//
//  ─── S16 · ACCESSIBILITY (added 2026-08-25) ──────────────────────────────────
//    Every interactive control and information-bearing composite carries a
//    label; the disabled CTA announces WHY through .accessibilityValue;
//    multi-Text composites are combined into one coherent announcement;
//    decorative glyphs are hidden. No control on this screen is under 44pt.
//
//  Author of record: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Screen

struct RailSwitchlistScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailSwitchlistBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Decoded server shapes

/// `yardManagement.getYardMoveQueue` (:1940) envelope.
private struct SlMoveQueue: Decodable {
    let moves: [SlMove]?
    let summary: SlSummary?
    let hostlers: [SlHostler]?
}

private struct SlSummary: Decodable {
    let total: Int?
    let pending: Int?
    let assigned: Int?
    let inProgress: Int?
    let completed: Int?
    let avgCompletionMinutes: Int?
}

/// One yard_moves row as the router shapes it.
private struct SlMove: Decodable, Identifiable {
    let id: String                // "YM-<n>"
    let status: String?           // pending | assigned | in_progress | completed | cancelled
    let trailerNumber: String?
    let fromSpot: String?
    let toSpot: String?
    let priority: String?         // low | normal | high | urgent
    let requestedAt: String?      // ISO-8601
    let assignedTo: String?
    let hostlerId: String?        // "HST-<n>"
    let reason: String?           // dock_assignment | reposition | outbound_staging | repair_move | gate_staging
    let estimatedMinutes: Int?
    let startedAt: String?
    let completedAt: String?
}

private struct SlHostler: Decodable, Identifiable {
    let id: String
    let name: String?
    let status: String?           // busy | available
    let currentMove: String?
    let movesCompleted: Int?
}

/// `railShipments.getRailCrew` (railShipments.ts:2453) — bare array of rail_crew_assignments rows.
private struct SlCrewMember: Decodable, Identifiable {
    let id: Int
    let role: String?
    let crewId: String?
    let dutyStatus: String?
    let endorsement: String?
}

/// `railShipments.getRailYards` (railShipments.ts:1512) — bare array of rail_yards rows.
private struct SlYard: Decodable, Identifiable {
    let id: Int
    let name: String?
    let splcCode: String?
    let city: String?
    let state: String?
    let country: String?
    let yardType: String?
    let totalTracks: Int?
    let capacity: Int?
}

/// `railShipments.getYardTrackOccupancy` (railShipments.ts:1246).
private struct SlYardOccupancy: Decodable {
    let yardId: Int?
    let yardName: String?
    let totalTracks: Int?
    let capacity: Int?
    let utilizationPct: Double?
    let tracks: [SlTrack]?
    let unassigned: [SlSlimCar]?
    let note: String?
}

private struct SlTrack: Decodable, Identifiable {
    var id: Int { trackNumber }
    let trackNumber: Int
    let carCount: Int?
    let cars: [SlSlimCar]?
}

private struct SlSlimCar: Decodable, Identifiable {
    let id: Int
    let carNumber: String?
    let carType: String?
    let status: String?
}

/// `railShipments.getRailcars` (railShipments.ts:1192) envelope.
private struct SlRailcarEnvelope: Decodable {
    let railcars: [SlRailcar]?
    let total: Int?
}

private struct SlRailcar: Decodable, Identifiable {
    let id: Int
    let railcarNumber: String?
    let carType: String?
    let status: String?
    let trackNumber: Int?
    let currentYardId: Int?
    let yardName: String?
}

// MARK: - Step state

private enum SlStepState {
    case done, working, next, planned, cancelled

    var label: String {
        switch self {
        case .done:      return "DONE"
        case .working:   return "WORKING"
        case .next:      return "NEXT"
        case .planned:   return "PLANNED"
        case .cancelled: return "CANCELLED"
        }
    }
}

// MARK: - Body

private struct RailSwitchlistBody: View {
    @Environment(\.palette) private var palette

    @State private var queue: SlMoveQueue? = nil
    @State private var crew: [SlCrewMember] = []
    @State private var yard: SlYard? = nil
    @State private var occupancy: SlYardOccupancy? = nil
    @State private var carsAtYard: [SlRailcar] = []

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var assigning = false
    /// Real read timestamp — the only source of the cached-at line.
    @State private var readAt: Date? = nil
    @State private var now = Date()
    /// OFFLINE: reads are READ_CACHED(5 min); completions are QUEUE(yard).
    private let cacheTTL: TimeInterval = 5 * 60
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    // MARK: The ordered sequence
    //
    // The server orders the queue newest-first. A switchlist is worked oldest-
    // first, so the sequence is re-sorted ascending by the REAL requestedAt
    // stamp. Nothing is re-ranked by priority: a switchlist is an order, not a
    // triage — that is 621's job, not this screen's.

    private var steps: [SlMove] {
        (queue?.moves ?? []).sorted { lhs, rhs in
            switch (lhs.requestedAt, rhs.requestedAt) {
            case let (l?, r?): return l < r
            case (nil, _?):    return false
            case (_?, nil):    return true
            default:           return lhs.id < rhs.id
            }
        }
    }

    /// The current move is the visual anchor: the one in progress, else the first
    /// step that is not finished.
    private var anchorIndex: Int? {
        if let i = steps.firstIndex(where: { ($0.status ?? "") == "in_progress" }) { return i }
        return steps.firstIndex { !["completed", "cancelled"].contains($0.status ?? "") }
    }

    private func state(at index: Int) -> SlStepState {
        switch (steps[index].status ?? "") {
        case "completed":   return .done
        case "cancelled":   return .cancelled
        case "in_progress": return .working
        default:            return index == anchorIndex ? .working : (index == (anchorIndex.map { $0 + 1 } ?? -1) ? .next : .planned)
        }
    }

    /// Cumulative planned start of each step — the sum of the estimated minutes of
    /// every step before it. Real field, real sum; nil when the rows carry none.
    private func cumulativeStart(at index: Int) -> Int? {
        let priors = steps.prefix(index).compactMap { $0.estimatedMinutes }
        guard priors.count == index else { return index == 0 ? 0 : nil }
        return priors.reduce(0, +)
    }

    private var plannedTotalMinutes: Int? {
        let served = steps.compactMap { $0.estimatedMinutes }
        return served.isEmpty ? nil : served.reduce(0, +)
    }

    /// Elapsed is measured, never assumed: the real wall time of every move that
    /// carries BOTH a startedAt and a completedAt.
    private var elapsedMinutes: Int? {
        let iso = ISO8601DateFormatter()
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let spans: [Int] = steps.compactMap { m in
            guard let s = m.startedAt, let e = m.completedAt,
                  let sd = isoFrac.date(from: s) ?? iso.date(from: s),
                  let ed = isoFrac.date(from: e) ?? iso.date(from: e),
                  ed > sd else { return nil }
            return Int(ed.timeIntervalSince(sd) / 60)
        }
        return spans.isEmpty ? nil : spans.reduce(0, +)
    }

    private var remainingMinutes: Int? {
        guard let total = plannedTotalMinutes else { return nil }
        let spent = steps.enumerated()
            .filter { ["completed", "cancelled"].contains($0.element.status ?? "") }
            .compactMap { $0.element.estimatedMinutes }
            .reduce(0, +)
        return max(0, total - spent)
    }

    private func hhmm(_ minutes: Int?) -> String {
        guard let m = minutes else { return "—" }
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    /// VoiceOver reads the house separator "·" aloud as a symbol and an em dash
    /// as "dash". Spoken strings swap them so a combined composite reads as one
    /// sentence. Never changes what is displayed — only how it is announced.
    private func spoken(_ s: String) -> String {
        s.replacingOccurrences(of: "—:—", with: "not reported")
         .replacingOccurrences(of: " · ", with: ", ")
         .replacingOccurrences(of: "—", with: "not reported")
    }

    private var completedCount: Int {
        steps.filter { ($0.status ?? "") == "completed" }.count
    }

    private var jobLabel: String {
        // The job identity is the hostler the moves are assigned to — a real field.
        if let h = queue?.hostlers?.first(where: { ($0.status ?? "") == "busy" }) ?? queue?.hostlers?.first {
            return h.name ?? h.id
        }
        if let a = steps.compactMap({ $0.assignedTo }).first { return a }
        return "job not assigned"
    }

    /// The track being worked — the from-spot of the current move, which is the
    /// only track the crew is physically standing on.
    private var workingTrack: String? {
        guard let i = anchorIndex else { return nil }
        return steps[i].fromSpot
    }

    /// Every fragment decoded — the crew rows, the current move's from-track, and
    /// the cars the yard actually reports standing here. No invented tonnage, no
    /// invented cut size.
    private var bandDetail: String {
        var parts: [String] = [crewLine]
        parts.append(workingTrack.map { "working \($0)" } ?? "no track under the crew")
        if !carsAtYard.isEmpty {
            let unassigned = carsAtYard.filter { $0.trackNumber == nil }.count
            parts.append("\(carsAtYard.count) cars on the ground\(unassigned > 0 ? " · \(unassigned) unassigned" : "")")
        }
        return parts.joined(separator: " · ")
    }

    private var crewLine: String {
        guard !crew.isEmpty else { return "no crew assigned to this yard" }
        let roles = crew.prefix(3).map { ($0.role ?? "crew").replacingOccurrences(of: "_", with: " ") }
        return roles.joined(separator: " + ")
    }

    private var subline: String {
        var parts: [String] = []
        parts.append(jobLabel)
        if let y = yard {
            let place = [y.city, y.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            parts.append(place.isEmpty ? (y.name ?? "Yard \(y.id)") : place)
        }
        let left = steps.count - completedCount
        parts.append("\(left) move\(left == 1 ? "" : "s") left")
        if remainingMinutes != nil { parts.append(hhmm(remainingMinutes)) }
        return parts.joined(separator: " · ")
    }

    // MARK: Cache clock

    private var cacheAgeSeconds: TimeInterval? {
        guard let readAt else { return nil }
        return max(0, now.timeIntervalSince(readAt))
    }
    private var cacheExpired: Bool {
        guard let age = cacheAgeSeconds else { return true }
        return age > cacheTTL
    }
    private var readAtLabel: String {
        guard let readAt else { return "—:—" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: readAt)
    }

    // MARK: View

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                headline
                Text(subline).font(EType.caption).foregroundStyle(palette.textSecondary)
                    .accessibilityLabel("Job summary")
                    .accessibilityValue(spoken(subline))
                stateChips
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Reading the switchlist…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Reading the switchlist")
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text("Switchlist unavailable").font(EType.bodyStrong).foregroundStyle(Brand.danger)
                        Text(err).font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Switchlist unavailable")
                    .accessibilityValue(err)
                } else {
                    moveSequence
                    sectionLabel("MOVE STATUS", trailing: "moves cached · TTL 5 min")
                    outboxStrip
                    triCountryBand
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
        .onReceive(clock) { now = $0 }
    }

    // MARK: Eyebrow · headline · chips

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                .accessibilityHidden(true)
            Text("RAIL ENGINEER · SWITCHLIST")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            Spacer()
            Text(yard?.splcCode.map { "SPLC \($0)" } ?? "—")
                .font(EType.mono(.micro)).tracking(1.0).foregroundStyle(palette.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rail engineer, switchlist")
        .accessibilityValue(yard?.splcCode.map { "Standard point location code \($0)" } ?? "Standard point location code not reported")
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Switchlist").font(.system(size: 28, weight: .heavy)).kerning(-0.4)
                .foregroundStyle(palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textTertiary)
                .accessibilityHidden(true)
        }
    }

    private var stateChips: some View {
        HStack(spacing: Space.s2) {
            chip(anchorIndex == nil
                 ? (steps.isEmpty ? "NO MOVES" : "LIST WORKED")
                 : "STEP \((anchorIndex ?? 0) + 1) OF \(steps.count)",
                 anchorIndex == nil ? Brand.neutral : Brand.info,
                 spoken: anchorIndex == nil
                 ? (steps.isEmpty ? "No moves ordered on this job" : "List worked, every ordered move is finished")
                 : "On step \((anchorIndex ?? 0) + 1) of \(steps.count)")
            chip(remainingMinutes == nil ? "TIME UNKNOWN" : "\(hhmm(remainingMinutes)) LEFT",
                 remainingMinutes == nil ? Brand.neutral : Brand.warning,
                 spoken: remainingMinutes == nil
                 ? "Time remaining unknown, the yard did not report an estimate"
                 : "\(remainingMinutes ?? 0) minutes of planned work left")
            chip("COMPLETION UNAVAILABLE", Brand.warning,
                 spoken: "Completion unavailable, this screen cannot record a completed move")
            Spacer(minLength: 0)
        }
    }

    /// `spoken` carries the plain-language announcement. The displayed token is
    /// an all-caps yard abbreviation; VoiceOver gets the sentence instead.
    private func chip(_ text: String, _ color: Color, spoken: String? = nil) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy)).tracking(0.3).foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(palette.bgCard)
            .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(Capsule())
            .accessibilityLabel(spoken ?? text)
    }

    private func sectionLabel(_ text: String, trailing: String) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(text).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(trailing).font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary)
            }
            Rectangle().fill(palette.borderFaint).frame(height: 1)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(text.lowercased().capitalized))
        .accessibilityValue(spoken(trailing))
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: THE DEVICE · numbered move sequence with a cumulative-time rail

    private var moveSequence: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard)
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
            VStack(alignment: .leading, spacing: 0) {
                jobBand
                if steps.isEmpty {
                    Text("The yard has ordered no moves for this job. The sequence stays empty rather than inventing work.")
                        .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Space.s3)
                        .accessibilityLabel("No moves ordered")
                        .accessibilityValue("The yard has ordered no moves for this job. The sequence stays empty rather than inventing work.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(steps.prefix(8).enumerated()), id: \.element.id) { idx, move in
                            stepRow(index: idx, move: move)
                        }
                    }
                    .padding(.top, Space.s3)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Ordered move sequence, \(min(steps.count, 8)) of \(steps.count) moves shown")
                    if steps.count > 8 {
                        Text("+ \(steps.count - 8) more moves ordered on this job")
                            .font(.system(size: 9.5, weight: .bold)).foregroundStyle(palette.textTertiary)
                            .padding(.top, 8)
                            .accessibilityLabel("\(steps.count - 8) more moves ordered on this job are not shown")
                    }
                }
                Text("Switching instructions are unavailable. Each row shows the recorded reason for the move, not a switching method; confirm how the move is to be worked with yard control.")
                    .font(.system(size: 9.5)).foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.s3)
                    .accessibilityLabel("Switching instructions unavailable")
                    .accessibilityValue("Each row shows the recorded reason for the move, not a switching method. Confirm how the move is to be worked with yard control.")
            }
            .padding(Space.s4)
        }
    }

    private var jobBand: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("SWITCHLIST · \(jobLabel.uppercased()) · \((yard?.name ?? occupancy?.yardName ?? "yard not resolved").uppercased())")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Brand.info)
                    .lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 8)
                Text("\(hhmm(elapsedMinutes)) / \(hhmm(plannedTotalMinutes))")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Brand.info)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.info.opacity(0.14)))
            }
            Text(bandDetail)
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Switchlist for \(spoken(jobLabel)) at \(yard?.name ?? occupancy?.yardName ?? "yard not resolved")")
        .accessibilityValue(
            "\(elapsedMinutes == nil ? "Elapsed not measured" : "\(elapsedMinutes ?? 0) minutes elapsed") of "
            + "\(plannedTotalMinutes == nil ? "a planned total the yard did not report" : "\(plannedTotalMinutes ?? 0) minutes planned"). "
            + spoken(bandDetail))
        .accessibilityAddTraits(.isHeader)
    }

    private func stepRow(index: Int, move: SlMove) -> some View {
        let st = state(at: index)
        let isAnchor = (st == .working)
        let tint: Color = {
            switch st {
            case .done:      return Brand.success
            case .working:   return Brand.info
            case .next:      return Brand.warning
            case .cancelled: return Brand.danger
            case .planned:   return palette.textTertiary
            }
        }()
        let quiet = (st == .done || st == .cancelled)

        return HStack(alignment: .top, spacing: 8) {
            // Cumulative-time rail: the clock label, the node, and the connector.
            VStack(spacing: 0) {
                Text(cumulativeStart(at: index).map { hhmm($0) } ?? "—")
                    .font(.system(size: 9, weight: isAnchor ? .heavy : .regular, design: .monospaced))
                    .foregroundStyle(isAnchor ? Brand.info : palette.textTertiary)
                    .frame(width: 34, alignment: .trailing)
                Spacer(minLength: 0)
            }
            VStack(spacing: 0) {
                ZStack {
                    if st == .done {
                        Circle().fill(Brand.success).frame(width: 18, height: 18)
                        Text("\(index + 1)").font(.system(size: 9.5, weight: .heavy)).foregroundStyle(.white)
                    } else if isAnchor {
                        Circle().fill(LinearGradient.diagonal).frame(width: 18, height: 18)
                        Text("\(index + 1)").font(.system(size: 9.5, weight: .heavy)).foregroundStyle(.white)
                    } else {
                        Circle().strokeBorder(palette.textTertiary, lineWidth: 1.6).frame(width: 18, height: 18)
                        Text("\(index + 1)").font(.system(size: 9.5, weight: .heavy)).foregroundStyle(palette.textTertiary)
                    }
                }
                if index < min(steps.count, 8) - 1 {
                    Rectangle()
                        .fill(st == .done ? Brand.success : palette.textPrimary.opacity(0.10))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                // The cut — the unit the yard reports moving.
                Text(move.trailerNumber ?? "unit not reported")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(quiet ? palette.textTertiary : palette.textPrimary)
                    .strikethrough(quiet, color: palette.textTertiary)
                    .lineLimit(1)
                // The MOVE: from track → to track.
                HStack(spacing: 6) {
                    Text(move.fromSpot ?? "—")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(quiet ? palette.textTertiary : palette.textPrimary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: isAnchor ? .heavy : .semibold))
                        .foregroundStyle(isAnchor ? Brand.info : palette.textTertiary)
                        .accessibilityHidden(true)
                    Text(move.toSpot ?? "—")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(quiet ? palette.textTertiary : palette.textPrimary)
                    if isHazardous(move) {
                        Text("DG · NO KICK")
                            .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(Brand.warning)
                    }
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                Text(verbSlot(move))
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4).foregroundStyle(tint)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(tint.opacity(0.12)))
                    .lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: 6) {
                    Text(move.estimatedMinutes.map { "\($0) min" } ?? "—")
                        .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                        .foregroundStyle(quiet ? palette.textTertiary : palette.textSecondary)
                    Text(st.label)
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.3).foregroundStyle(tint)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, isAnchor ? 8 : 0)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isAnchor ? Brand.info.opacity(0.07) : .clear)
        )
        .overlay(alignment: .leading) {
            if isAnchor {
                RoundedRectangle(cornerRadius: 1.5).fill(Brand.info).frame(width: 3)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(stepSpokenLabel(index: index, move: move))
        .accessibilityValue(stepSpokenValue(index: index, move: move, state: st))
    }

    /// One coherent announcement per step, assembled only from decoded fields.
    /// Absent fields say they are absent; nothing is filled in.
    private func stepSpokenLabel(index: Int, move: SlMove) -> String {
        let unit = move.trailerNumber ?? "unit not reported"
        let from = move.fromSpot ?? "a from-track the yard did not report"
        let to   = move.toSpot ?? "a to-track the yard did not report"
        return "Step \(index + 1) of \(steps.count). \(unit), \(from) to \(to)."
    }

    private func stepSpokenValue(index: Int, move: SlMove, state st: SlStepState) -> String {
        var parts: [String] = [st.label.lowercased().capitalized]
        parts.append(move.reason.map { "ordered for \($0.replacingOccurrences(of: "_", with: " "))" }
                     ?? "reason not reported")
        parts.append(move.estimatedMinutes.map { "\($0) minutes estimated" } ?? "estimate not reported")
        parts.append(cumulativeStart(at: index).map { "starts \($0) minutes into the job" }
                     ?? "cumulative start not reported")
        if isHazardous(move) {
            parts.append("A tank car stands on the from-track. Regulated lading, do not kick.")
        }
        return parts.joined(separator: ". ") + "."
    }

    /// The verb slot carries the server's own `reason` enum, uppercased. It is the
    /// reason the move was ordered — never a switching verb the server did not send.
    private func verbSlot(_ move: SlMove) -> String {
        guard let r = move.reason, !r.isEmpty else { return "REASON —" }
        return r.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    /// A tank car standing on the from-track is regulated lading — flagged from the
    /// server's own carType enum, never from a guessed commodity.
    private func isHazardous(_ move: SlMove) -> Bool {
        guard let from = move.fromSpot,
              let n = Int(from.filter { $0.isNumber }),
              let track = (occupancy?.tracks ?? []).first(where: { $0.trackNumber == n }) else { return false }
        return (track.cars ?? []).contains { ($0.carType ?? "") == "tankcar" }
    }

    // MARK: OFFLINE · QUEUE(yard) + READ_CACHED(5 min)

    /// The server's own move-queue summary, shown only where it actually reports.
    private var outboxLine: String {
        var line = "move rows cached \(readAtLabel)"
        if let avg = queue?.summary?.avgCompletionMinutes, avg > 0 {
            line += " · yard avg \(avg) min per move"
        }
        if let done = queue?.summary?.completed, let total = queue?.summary?.total, total > 0 {
            line += " · \(done)/\(total) worked"
        }
        return line
    }

    private var outboxStrip: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.info.opacity(0.12)).frame(width: 40, height: 40)
                Image(systemName: "arrow.up.doc")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.info)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Move completion cannot be recorded here")
                        .font(.system(size: 12.5, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("NOT QUEUED")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(Brand.warning)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Brand.warning.opacity(0.14)))
                }
                Text("No completion was queued or posted. Contact yard control to record the completed move; the current step remains unchanged.")
                    .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(outboxLine)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(cacheExpired ? Brand.warning : palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Move completion cannot be recorded here. Not queued.")
        .accessibilityValue("No completion was queued or posted. Contact yard control to record the completed move; the current step remains unchanged. "
                            + spoken(outboxLine)
                            + (cacheExpired ? ". The cached move rows are past their five minute window." : "."))
    }

    // MARK: Tri-country band · the job clock the cumulative rail is judged against

    private var triCountryBand: some View {
        HStack(spacing: Space.s2) {
            countryTile("US · FRA · 49 CFR 218", "USD · 12h job", active: activeCountry == "US")
            countryTile("CA · TC · CROR",        "CAD · 12h job", active: activeCountry == "CA")
            countryTile("MX · ARTF · RSF",       "MXN · 8h job",  active: activeCountry == "MX")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(activeCountry.map { "Regulatory regime, \($0) is the yard's recorded country" }
                            ?? "Regulatory regime, the yard row carries no country so no regime is marked active")
    }

    /// Gated by the REAL country on the yard row — never hardcoded.
    private var activeCountry: String? { yard?.country }

    private func countryTile(_ top: String, _ bottom: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(top).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                .foregroundStyle(active ? Brand.info : palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(bottom).font(.system(size: 9, weight: .heavy))
                .foregroundStyle(active ? Brand.info : palette.textSecondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(top))
        .accessibilityValue(spoken(bottom) + (active ? ". Active for this yard." : ""))
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Space.s2) {
                // A REAL control, disabled — never a Text dressed as a button.
                // railSwitchlist.completeMove is a STUB (named-gap
                // RAIL-YRD-715-COMPLETE-MOVE), so there is no receiver to wire
                // and the action body posts nothing and queues nothing. The
                // whole label is dimmed so the control cannot read as live
                // while it is inert, and the gap is stated in the caption below.
                Button {
                    // No receiver. Deliberately empty — see the note above.
                } label: {
                    Text("Complete move")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(LinearGradient.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .opacity(0.45)
                }
                .buttonStyle(.plain)
                .disabled(true)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Complete move")
                .accessibilityValue("Unavailable. Move completion cannot be recorded here. Contact yard control to record the completed move; the current step remains unchanged.")
                Button {
                    Task { await assignJob() }
                } label: {
                    Text(assigning ? "Assigning…" : "Assign job")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                        .frame(width: 132).frame(height: 48)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .disabled(assignInput == nil || assigning)
                .opacity(assignInput == nil || assigning ? 0.5 : 1)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Assign job")
                .accessibilityValue(assignSpokenValue)
                .accessibilityHint("Assigns the first move the yard reports as pending to a hostler the yard reports, then re-reads the switchlist.")
            }
            Text(ctaNote).font(.system(size: 9.5)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("What these controls do")
                .accessibilityValue(ctaNote)
        }
    }

    /// A disabled control has to say WHY out loud, not only by looking dim.
    private var assignSpokenValue: String {
        if assigning { return "Assigning now." }
        if assignInput == nil {
            return "Unavailable. Assign job needs an unassigned move and a hostler the yard actually reports; one or both are missing."
        }
        return "Available."
    }

    private var ctaNote: String {
        let assign = assignInput == nil
            ? "Assign job needs an unassigned move and a hostler the yard actually reports."
            : "Assign job requests the first unassigned move for an available hostler and refreshes the yard record after acceptance."
        return "Move completion is unavailable. Contact yard control to record completed work. " + assign
    }

    /// Both fields decoded from real rows — nil keeps the button disabled rather
    /// than posting an invented move or hostler id.
    private var assignInput: AssignMoveInput? {
        guard let move = steps.first(where: { ($0.status ?? "") == "pending" }),
              let hostler = (queue?.hostlers ?? []).first(where: { ($0.status ?? "") == "available" })
                            ?? (queue?.hostlers ?? []).first else { return nil }
        return AssignMoveInput(moveId: move.id, hostlerId: hostler.id, hostlerName: hostler.name, notes: nil)
    }

    // MARK: Data

    private struct YardsInput: Encodable { let limit: Int }
    private struct YardInput: Encodable { let yardId: Int }
    private struct CrewInput: Encodable { let limit: Int }
    private struct RailcarsInput: Encodable {
        let yardId: Int
        let limit: Int
        let offset: Int
    }
    private struct AssignMoveInput: Encodable {
        let moveId: String
        let hostlerId: String
        let hostlerName: String?
        let notes: String?
    }
    private struct AssignMoveResult: Decodable {
        let success: Bool?
        let moveId: String?
        let hostlerId: String?
        let assignedAt: String?
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            // 1. The ordered move rows — the sequence itself.
            self.queue = try await EusoTripAPI.shared.queryNoInput("yardManagement.getYardMoveQueue")

            // 2. The yard the job is worked in, and its track state.
            let yards: [SlYard] = try await EusoTripAPI.shared.query("railShipments.getRailYards",
                                                                     input: YardsInput(limit: 50))
            self.yard = yards.first { ($0.yardType ?? "") == "classification" } ?? yards.first
            if let yid = self.yard?.id {
                self.occupancy = try await EusoTripAPI.shared.query("railShipments.getYardTrackOccupancy",
                                                                    input: YardInput(yardId: yid))
                let cars: SlRailcarEnvelope = try await EusoTripAPI.shared.query(
                    "railShipments.getRailcars",
                    input: RailcarsInput(yardId: yid, limit: 100, offset: 0))
                self.carsAtYard = cars.railcars ?? []
            } else {
                self.occupancy = nil
                self.carsAtYard = []
            }

            self.readAt = Date()
            self.now = Date()
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false

        // 3. The crew on the job. Soft-fail: crew is tenant-private and may be
        //    empty; the header says so rather than inventing a name.
        self.crew = (try? await EusoTripAPI.shared.query("railShipments.getRailCrew",
                                                         input: CrewInput(limit: 20))) ?? []
    }

    /// The one write this screen can honestly make today: assign the first move
    /// the yard reports as pending to a hostler the yard actually reports. Real
    /// mutation, real companyId scoping server-side, and the sequence re-reads
    /// from the server rather than mutating local state.
    private func assignJob() async {
        guard let input = assignInput else { return }
        assigning = true
        do {
            let _: AssignMoveResult = try await EusoTripAPI.shared.mutation(
                "yardManagement.assignYardMove", input: input)
            assigning = false
            await load()
        } catch {
            assigning = false
            loadError = error.eusoUserCopy
        }
    }
}

#Preview("715 · Rail Switchlist · Night") {
    RailSwitchlistScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("715 · Rail Switchlist · Light") {
    RailSwitchlistScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
