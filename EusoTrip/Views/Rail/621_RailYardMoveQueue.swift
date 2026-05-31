//
//  621_RailYardMoveQueue.swift
//  EusoTrip — Rail Engineer · Yard Move Queue.
//
//  CARRIER-SIDE BOARD/QUEUE archetype — distinct from the 600 console.
//  Leads with a HOSTLER roster tile shelf (who is busy/available) then the
//  backlog in priority swim-lanes (URGENT / HIGH), each move row a 40-chip +
//  container ID + relative wait bar + wait-time pill + tabular rank.
//  Pairs the oldest-waiting move with the next free hostler so nothing
//  starves — Owen taps "Assign top move" and the #1 urgent grounding goes to
//  the next available hostler.
//
//  Web parity: app/(rail)/yard/queue/page.tsx
//  tRPC (server/routers/yardManagement.ts):
//    queue + hostler roster ← getYardMoveQueue  (EXISTS yardManagement.ts:1743)
//        → moves[{status,priority,trailerNumber,fromSpot,toSpot,reason,
//          requestedAt,assignedTo,hostlerId,estimatedMinutes}],
//          hostlers[{id,name,status,currentMove,movesCompleted}],
//          summary{total,pending,assigned,inProgress,completed,avgCompletionMinutes}
//    "Assign top move" → assignYardMove  (EXISTS yardManagement.ts:1829, mutation)
//  transportMode=rail · single-country US · RBAC: protectedProcedure
//  (companyId-scoped) on every yardManagement call.
//
//  PORT-GAP (named, surfaced to the-oath):
//    • getYardMoveQueue hostlers[] has no ETA / idle-minutes / track field —
//      the SVG hostler tiles show "ETA 3 min" / "idle 4 min" / "Track 4".
//      We render real {name, status, movesCompleted} only.
//    • moves[] has no commodity / hazmat / reefer flag and no location name —
//      the SVG container-ID line shows "reefer · plug-in due / hazmat UN1203".
//      We render the real trailerNumber + reason + from→to spot only.
//    • yard-move blockchain audit + WS yard channel NOT wired server-side
//      (yardManagement.ts:468 inserts the completed row, no audit/broadcast).
//

import SwiftUI

struct RailYardMoveQueueScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailYardMoveQueueBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror getYardMoveQueue output verbatim)

private struct YardMove: Decodable, Identifiable {
    let id: String
    let status: String?
    let trailerNumber: String?
    let fromSpot: String?
    let toSpot: String?
    let priority: String?
    let requestedAt: String?
    let assignedTo: String?
    let hostlerId: String?
    let reason: String?
    let estimatedMinutes: Int?
    let startedAt: String?
    let completedAt: String?
}

private struct YardHostler: Decodable, Identifiable {
    let id: String
    let name: String?
    let status: String?
    let currentMove: String?
    let movesCompleted: Int?
}

private struct YardMoveSummary: Decodable {
    let total: Int?
    let pending: Int?
    let assigned: Int?
    let inProgress: Int?
    let completed: Int?
    let avgCompletionMinutes: Int?
}

private struct YardMoveQueueResponse: Decodable {
    let moves: [YardMove]
    let hostlers: [YardHostler]
    let summary: YardMoveSummary?
}

private struct AssignYardMoveResponse: Decodable {
    let success: Bool?
    let moveId: String?
    let hostlerId: String?
    let assignedAt: String?
}

// MARK: - Priority filter

private enum PriorityFilter: String, CaseIterable {
    case all = "All"
    case urgent = "Urgent"
    case high = "High"
    case normal = "Normal"
}

// MARK: - Body

private struct RailYardMoveQueueBody: View {
    @Environment(\.palette) private var palette

    @State private var moves: [YardMove] = []
    @State private var hostlers: [YardHostler] = []
    @State private var summary: YardMoveSummary? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var activeFilter: PriorityFilter = .all
    @State private var assigning = false
    @State private var assignBanner: String? = nil

    // Reference code shown top-right of the eyebrow (verbatim format from SVG).
    private let refCode = "RAIL-260528-B5108F3CA0"

    // MARK: priority helpers

    private func isPriority(_ m: YardMove, _ p: String) -> Bool {
        (m.priority ?? "normal").lowercased() == p
    }
    private var urgentMoves: [YardMove] { moves.filter { isPriority($0, "urgent") } }
    private var highMoves:   [YardMove] { moves.filter { isPriority($0, "high") } }
    private var normalMoves: [YardMove] { moves.filter { !isPriority($0, "urgent") && !isPriority($0, "high") } }

    private var activeCount: Int { summary?.total ?? moves.count }
    private var hostlersOnShift: Int { hostlers.count }

    // The oldest-waiting urgent move (falls back to oldest overall) — the
    // move "Assign top move" targets. Sorted by requestedAt ascending.
    private var topMove: YardMove? {
        let pool = urgentMoves.isEmpty ? (highMoves.isEmpty ? moves : highMoves) : urgentMoves
        return pool.sorted { (waitSeconds($0) ?? 0) > (waitSeconds($1) ?? 0) }.first
    }
    private var nextFreeHostler: YardHostler? {
        hostlers.first { ($0.status ?? "").lowercased() == "available" } ?? hostlers.first
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow
                titleBlock
                filterChips
                    .padding(.top, Space.s3)
                IridescentHairline()
                    .padding(.top, Space.s4)

                if loading {
                    loadingState
                        .padding(.top, Space.s4)
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    .padding(.top, Space.s4)
                } else {
                    if let banner = assignBanner {
                        assignAck(banner)
                            .padding(.top, Space.s3)
                    }

                    hostlerShelf
                        .padding(.top, Space.s4)

                    if activeFilter == .all || activeFilter == .urgent {
                        laneSection(title: "URGENT", color: Brand.danger, rows: urgentMoves)
                            .padding(.top, Space.s5)
                    }
                    if activeFilter == .all || activeFilter == .high {
                        laneSection(title: "HIGH", color: Brand.warning, rows: highMoves)
                            .padding(.top, Space.s5)
                    }
                    if activeFilter == .normal {
                        laneSection(title: "NORMAL", color: Brand.neutral, rows: normalMoves)
                            .padding(.top, Space.s5)
                    }

                    actionBar
                        .padding(.top, Space.s6)
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Eyebrow

    private var eyebrow: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "tram.fill")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(LinearGradient.primary)
                Text("RAIL ENGINEER · MOVE QUEUE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
            }
            Spacer()
            Text(refCode)
                .font(EType.mono(.micro)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Move queue")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .rotationEffect(.degrees(90))
            }
            Text("Corwith Intermodal · \(activeCount) active · \(hostlersOnShift) hostlers")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.top, Space.s3)
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        HStack(spacing: Space.s2) {
            filterChip(.all,    count: activeCount,        color: nil)
            filterChip(.urgent, count: urgentMoves.count,  color: Brand.danger)
            filterChip(.high,   count: highMoves.count,    color: Brand.warning)
            filterChip(.normal, count: normalMoves.count,  color: Brand.neutral)
            Spacer(minLength: 0)
        }
    }

    private func filterChip(_ filter: PriorityFilter, count: Int, color: Color?) -> some View {
        let isActive = activeFilter == filter
        let label = "\(filter.rawValue) · \(count)"
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { activeFilter = filter }
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(
                    isActive ? AnyShapeStyle(Color.white)
                             : AnyShapeStyle(color ?? palette.textSecondary)
                )
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(
                    Group {
                        if isActive {
                            AnyView(LinearGradient.primary)
                        } else {
                            AnyView(palette.bgCardSoft)
                        }
                    }
                )
                .overlay(
                    Capsule().strokeBorder(palette.borderSoft, lineWidth: isActive ? 0 : 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hostler shelf

    private var hostlerShelf: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("HOSTLERS · \(hostlersOnShift) ON SHIFT")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("live")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            Rectangle().fill(palette.borderFaint).frame(height: 1)

            if hostlers.isEmpty {
                EusoEmptyState(systemImage: "person.2",
                               title: "No hostlers on shift",
                               subtitle: "Yard hostler roster will appear here.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.s3) {
                        ForEach(hostlers) { hostlerTile($0) }
                    }
                }
            }
        }
    }

    private func hostlerTile(_ h: YardHostler) -> some View {
        let isBusy = (h.status ?? "").lowercased() == "busy"
        let dot: Color = isBusy ? Brand.warning : Brand.success
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(dot).frame(width: 7, height: 7)
                Text(h.name ?? h.id)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer(minLength: 0)
            Text(isBusy ? "busy" : "available")
                .font(.system(size: 9.5, weight: .regular))
                .foregroundStyle(palette.textSecondary)
            Text("\(h.movesCompleted ?? 0) moves done")
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 2)
        }
        .padding(Space.s3)
        .frame(width: 124, height: 64, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Lane section (swim-lane header + card of move rows)

    @ViewBuilder
    private func laneSection(title: String, color: Color, rows: [YardMove]) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("\(title) · \(rows.count)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(color)
                Spacer()
                if rows.count > 2 {
                    Text("see all ›")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Rectangle().fill(palette.borderFaint).frame(height: 1)

            if rows.isEmpty {
                EusoEmptyState(systemImage: "tray",
                               title: "No \(title.lowercased()) moves",
                               subtitle: "Yard moves at this priority will appear here.")
            } else {
                VStack(spacing: 0) {
                    let ranked = rankedRows(rows)
                    ForEach(Array(ranked.enumerated()), id: \.element.move.id) { idx, item in
                        moveRow(item.move, color: color, rank: item.rank,
                                maxWait: ranked.first?.wait ?? 1)
                        if idx < ranked.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                                .padding(.vertical, Space.s1)
                        }
                    }
                }
                .padding(Space.s4)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private struct RankedMove { let move: YardMove; let rank: Int; let wait: Double }

    // Global rank across all moves by descending wait, so the URGENT lane's
    // oldest is #1, then the next, etc. — matching the SVG's #1..#N tabular
    // priority column.
    private func rankedRows(_ rows: [YardMove]) -> [RankedMove] {
        let globalOrder = moves.sorted { (waitSeconds($0) ?? 0) > (waitSeconds($1) ?? 0) }
        let rankIndex: [String: Int] = Dictionary(
            uniqueKeysWithValues: globalOrder.enumerated().map { ($0.element.id, $0.offset + 1) }
        )
        return rows
            .sorted { (waitSeconds($0) ?? 0) > (waitSeconds($1) ?? 0) }
            .map { RankedMove(move: $0, rank: rankIndex[$0.id] ?? 0, wait: waitSeconds($0) ?? 0) }
    }

    // MARK: - Move row

    private func moveRow(_ m: YardMove, color: Color, rank: Int, maxWait: Double) -> some View {
        let wait = waitSeconds(m) ?? 0
        let frac = maxWait > 0 ? min(max(wait / maxWait, 0.05), 1.0) : 0.05
        return HStack(alignment: .top, spacing: Space.s3) {
            // 40-chip move-glyph
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: "arrow.right.to.line")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(moveTitle(m))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Text(moveSubtitle(m))
                            .font(EType.mono(.caption)).tracking(0.3)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("WAITED \(waitLabel(wait))")
                            .font(.system(size: 10.5, weight: .bold)).tracking(0.4)
                            .foregroundStyle(color)
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .background(Capsule().fill(color.opacity(0.20)))
                    }
                }
                // relative wait bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                            .frame(height: 6)
                        Capsule().fill(color)
                            .frame(width: geo.size.width * frac, height: 6)
                    }
                }
                .frame(height: 6)
                .padding(.top, 2)
            }
            // tabular rank
            VStack(alignment: .trailing, spacing: 1) {
                Text("#\(rank)")
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("priority")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
            }
            .frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, Space.s2)
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: Space.s3) {
            CTAButton(
                title: "Assign top move",
                action: { Task { await assignTopMove() } },
                leadingIcon: "list.bullet.rectangle",
                isLoading: assigning
            )
            .frame(maxWidth: .infinity)

            Button {
                Task { await reload() }
            } label: {
                Text("Rebalance")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(width: 148)
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 64)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
        }
    }

    private func assignAck(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.success)
            Text(text)
                .font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
        }
        .padding(Space.s3)
        .background(Brand.success.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.success.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Copy derivation (verbatim RAIL vocabulary from real fields)

    private func moveTitle(_ m: YardMove) -> String {
        let reasonLabel: String
        switch (m.reason ?? "reposition").lowercased() {
        case "dock_assignment":  reasonLabel = "Spot to door"
        case "outbound_staging": reasonLabel = "Outbound staging"
        case "repair_move":      reasonLabel = "Repair move"
        case "gate_staging":     reasonLabel = "Gate staging"
        default:                 reasonLabel = "Reposition"
        }
        if let to = m.toSpot, !to.isEmpty {
            return "\(reasonLabel) · \(to)"
        }
        return reasonLabel
    }

    private func moveSubtitle(_ m: YardMove) -> String {
        var parts: [String] = []
        if let car = m.trailerNumber, !car.isEmpty { parts.append(car) }
        if let from = m.fromSpot, !from.isEmpty,
           let to = m.toSpot, !to.isEmpty {
            parts.append("\(from) → \(to)")
        } else if let from = m.fromSpot, !from.isEmpty {
            parts.append("from \(from)")
        }
        if let who = m.assignedTo, !who.isEmpty { parts.append(who) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    // Seconds the move has waited since requestedAt.
    private func waitSeconds(_ m: YardMove) -> Double? {
        guard let r = m.requestedAt,
              let d = ISO8601DateFormatter.yardFormatter.date(from: r)
        else { return nil }
        return max(0, Date().timeIntervalSince(d))
    }

    private func waitLabel(_ seconds: Double) -> String {
        let mins = Int(seconds / 60)
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60, m = mins % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    // MARK: - Load

    private func reload() async {
        loading = true; loadError = nil
        struct QueueIn: Encodable {}
        do {
            let resp: YardMoveQueueResponse = try await EusoTripAPI.shared.query(
                "yardManagement.getYardMoveQueue", input: QueueIn())
            self.moves = resp.moves
            self.hostlers = resp.hostlers
            self.summary = resp.summary
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func assignTopMove() async {
        guard !assigning else { return }
        guard let move = topMove else {
            assignBanner = "No move to assign — the queue is clear."
            return
        }
        guard let hostler = nextFreeHostler else {
            assignBanner = "No hostler available — none on shift to take the move."
            return
        }
        assigning = true; assignBanner = nil
        struct AssignIn: Encodable {
            let moveId: String
            let hostlerId: String
            let hostlerName: String
        }
        do {
            let resp: AssignYardMoveResponse = try await EusoTripAPI.shared.mutation(
                "yardManagement.assignYardMove",
                input: AssignIn(moveId: move.id,
                                hostlerId: hostler.id,
                                hostlerName: hostler.name ?? hostler.id))
            if resp.success == true {
                assignBanner = "Assigned \(moveTitle(move)) → \(hostler.name ?? hostler.id)."
                await reload()
            } else {
                assignBanner = "Assignment did not complete — try again."
            }
        } catch {
            assignBanner = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        assigning = false
    }
}

// MARK: - ISO8601 helper (fractional + non-fractional)

private extension ISO8601DateFormatter {
    static let yardFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

#Preview("621 · Rail Yard Move Queue · Night") { RailYardMoveQueueScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("621 · Rail Yard Move Queue · Light") { RailYardMoveQueueScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
