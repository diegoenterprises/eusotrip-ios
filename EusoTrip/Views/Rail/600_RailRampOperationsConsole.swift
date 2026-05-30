//
//  600_RailRampOperationsConsole.swift
//  EusoTrip — Rail Engineer · Ramp Operations Console (live ramp board).
//
//  CARRIER-SIDE BOARD/OPERATIONS archetype — the live ramp console: a
//  capacity hero (slots used + utilization + dwell + detention) over a
//  swim-lane of in-progress hostler moves (pull / chassis-mount /
//  grounding), each row a 40-chip + container ID + relative progress bar
//  + short status pill clear of the right tabular ETA, plus a
//  capacity-guard tile shelf. Web parity: app/(rail)/yard/ramp/page.tsx.
//
//  Wiring (tRPC · yardManagement router · companyId-scoped
//  protectedProcedure):
//    capacity hero + guard  ← yardManagement.getYardDashboard
//    LIVE MOVES lane        ← yardManagement.getYardMoveQueue
//    'Assign next move' CTA → yardManagement.assignYardMove (mutation)
//
//  These three procedures EXIST on the web tRPC router but have NO typed
//  Swift wrapper in EusoTripAPI — they are reached through the generic
//  query/queryNoInput/mutation path helpers and decoded into the local
//  Decodable shapes below. See portGaps.
//
//  transportMode=rail · single-country US (Corwith · BNSF).
//  NAV: HOME · SHIPMENTS · [orb] · COMPLIANCE · ME.
//

import SwiftUI

struct RailRampOperationsConsoleScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailRampOperationsConsoleBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: true),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (yardManagement.getYardDashboard)

private struct YardCapacity: Decodable {
    let total: Int?
    let occupied: Int?
    let available: Int?
    let utilizationPct: Double?
}

private struct YardDetentionAlert: Decodable, Identifiable {
    let id: String?
    let containerId: String?
    let dwellHours: Double?
    var identity: String { id ?? containerId ?? UUID().uuidString }
}

private struct YardDashboard: Decodable {
    let capacity: YardCapacity?
    let dockSummary: Int?
    let avgDwellTimeHours: Double?
    let detentionAlerts: [YardDetentionAlert]?
    let crossDockActive: Int?
    // Gate-entry / facility context surfaced in the capacity-guard shelf.
    let gateEntriesToday: Int?
    let facility: String?
}

// MARK: - Data shapes (yardManagement.getYardMoveQueue)

private struct YardMove: Decodable, Identifiable {
    let id: String?
    let moveType: String?       // "pull" / "chassis-mount" / "grounding"
    let location: String?       // "Track 4" / "Lane 2" / "Track 7"
    let containerId: String?    // "DTTX 724501"
    let equipment: String?      // "well-car" / "40HC" / "reefer"
    let direction: String?      // "IB" / "dray-out" / "plug-in"
    let status: String?         // "MOVING" / "QUEUED" / "HOLD"
    let priority: String?
    let progressPct: Double?    // 0..100 relative completion
    let etaMinutes: Int?
    let etaLabel: String?       // "to ramp" / "wait" / "blocked"

    var identity: String { id ?? containerId ?? UUID().uuidString }
}

private struct YardMoveSummary: Decodable {
    let total: Int?
    let pending: Int?
    let assigned: Int?
    let inProgress: Int?
    let completed: Int?
    let avgCompletionMinutes: Double?
}

private struct YardMoveQueue: Decodable {
    let moves: [YardMove]?
    let summary: YardMoveSummary?
}

// MARK: - Body

private struct RailRampOperationsConsoleBody: View {
    @Environment(\.palette) private var palette

    @State private var dashboard: YardDashboard? = nil
    @State private var queue: YardMoveQueue? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var assigning = false
    @State private var assignNote: String? = nil

    // Eyebrow ref-stamp — single-country US ramp console reference (verbatim).
    private let refCode = "RAIL-260528-CA17FB02D9"

    // Filter chip selection — mirrors the four swim-lane buckets.
    enum MoveFilter: String, CaseIterable {
        case all        = "All"
        case inProgress = "In progress"
        case queued     = "Queued"
        case hold       = "Hold"
    }
    @State private var filter: MoveFilter = .all

    // MARK: Derived counts (from live queue · no fabricated data)

    private var moves: [YardMove] { queue?.moves ?? [] }

    private func isInProgress(_ m: YardMove) -> Bool {
        let s = (m.status ?? "").lowercased()
        return s == "moving" || s == "inprogress" || s == "in_progress" || s == "in progress"
    }
    private func isQueued(_ m: YardMove) -> Bool {
        let s = (m.status ?? "").lowercased()
        return s == "queued" || s == "pending" || s == "assigned"
    }
    private func isHold(_ m: YardMove) -> Bool {
        let s = (m.status ?? "").lowercased()
        return s == "hold" || s == "blocked" || s == "on_hold"
    }

    private var totalCount:      Int { queue?.summary?.total ?? moves.count }
    private var inProgressCount: Int { queue?.summary?.inProgress ?? moves.filter(isInProgress).count }
    private var queuedCount:     Int { (queue?.summary?.pending ?? 0) + (queue?.summary?.assigned ?? 0) > 0
                                        ? (queue?.summary?.pending ?? 0) + (queue?.summary?.assigned ?? 0)
                                        : moves.filter(isQueued).count }
    private var holdCount:       Int { moves.filter(isHold).count }

    private var filteredMoves: [YardMove] {
        switch filter {
        case .all:        return moves
        case .inProgress: return moves.filter(isInProgress)
        case .queued:     return moves.filter(isQueued)
        case .hold:       return moves.filter(isHold)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow
                titleBlock
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s2)
                filterRow
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s4)
                IridescentHairline()
                    .padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s5) {
                    if loading {
                        loadingCard
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    } else {
                        capacityHero
                        liveMovesSection
                        capacityGuardSection
                        ctaRow
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s5)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Eyebrow

    private var eyebrow: some View {
        HStack {
            Text("✦  RAIL ENGINEER · RAMP OPS")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text(refCode)
                .font(EType.mono(.micro)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }

    // MARK: - Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ramp operations")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .rotationEffect(.degrees(90))
            }
            Text("Corwith Intermodal · BNSF · live yard")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 4)
        }
    }

    // MARK: - Filter row (All · In progress · Queued · Hold)

    private var filterRow: some View {
        let counts: [MoveFilter: Int] = [
            .all: totalCount, .inProgress: inProgressCount,
            .queued: queuedCount, .hold: holdCount
        ]
        let accent: [MoveFilter: Color] = [
            .all: .white, .inProgress: Color(hex: 0x4DA3FF),
            .queued: Color(hex: 0x90A4AE), .hold: Brand.warning
        ]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(MoveFilter.allCases, id: \.self) { f in
                    let n = counts[f] ?? 0
                    let isOn = filter == f
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { filter = f }
                    } label: {
                        Text("\(f.rawValue) · \(n)")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(isOn ? Color.white : (accent[f] ?? palette.textSecondary))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(
                                Group {
                                    if isOn { AnyView(LinearGradient.primary) }
                                    else    { AnyView(Color(hex: 0x232932)) }
                                }
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    isOn ? Color.clear : Color.white.opacity(0.18),
                                    lineWidth: 1)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Loading card

    private var loadingCard: some View {
        LifecycleCard {
            HStack(spacing: Space.s2) {
                ProgressView().tint(palette.textSecondary)
                Text("Loading ramp console…")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: - Capacity hero (MOVES · ACTIVE NOW)

    private var capacityHero: some View {
        let cap = dashboard?.capacity
        let occupied = cap?.occupied
        let total = cap?.total
        let util = cap?.utilizationPct
        let dwell = dashboard?.avgDwellTimeHours
        let detentionN = dashboard?.detentionAlerts?.count
        let slotsLabel: String = {
            if let occ = occupied, let tot = total {
                return "\(occ.formatted()) / \(tot.formatted()) car slots used"
            }
            return "Car slots used unavailable"
        }()
        let fillFraction: CGFloat = {
            guard let util else { return 0 }
            return CGFloat(max(0, min(100, util)) / 100.0)
        }()

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("MOVES · ACTIVE NOW")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Text("\(totalCount)")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(palette.textPrimary).monospacedDigit()
                    Text(slotsLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: Space.s3) {
                    heroStat(value: util.map { "\(Int($0.rounded()))%" } ?? "—", label: "util")
                    heroStat(value: dwell.map { "\(Int($0.rounded()))h" } ?? "—", label: "avg dwell")
                    heroStat(value: detentionN.map { "\($0)" } ?? "—", label: "detention")
                }
            }
            // Slots-used progress bar.
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule().fill(LinearGradient.primary)
                        .frame(width: max(0, w * fillFraction))
                }
            }
            .frame(height: 6)
            .padding(.top, Space.s3)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    private func heroStat(value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value)
                .font(.system(size: 13, weight: .bold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Live moves section

    private var liveMovesSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("LIVE MOVES · \(totalCount) ACTIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Color(hex: 0x4DA3FF))
                Spacer()
                Text("see all ›")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)

            if filteredMoves.isEmpty {
                EusoEmptyState(
                    systemImage: "tram.fill",
                    title: "No live moves",
                    subtitle: "Active hostler moves on the ramp will appear here.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredMoves.enumerated()), id: \.element.identity) { idx, m in
                        if idx > 0 {
                            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                                .padding(.horizontal, Space.s4)
                        }
                        moveRow(m)
                    }
                }
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
            }
        }
    }

    private func moveRow(_ m: YardMove) -> some View {
        let accent = moveAccent(m)
        let title = moveTitle(m)
        let meta = moveMeta(m)
        let pill = movePill(m)
        let progress: CGFloat = {
            let p = m.progressPct ?? 0
            return CGFloat(max(0, min(100, p)) / 100.0)
        }()
        return HStack(alignment: .top, spacing: Space.s3) {
            // 40-chip glyph (container/hostler icon).
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(meta)
                    .font(EType.mono(.caption)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                // Relative progress bar.
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(accent)
                            .frame(width: max(0, w * progress))
                    }
                }
                .frame(height: 6)
                .padding(.top, 2)
            }
            VStack(alignment: .trailing, spacing: 6) {
                Text(pill.text.uppercased())
                    .font(.system(size: 10.5, weight: .bold)).tracking(0.4)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(accent.opacity(0.20)))
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(moveEta(m))
                        .font(.system(size: 14, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text(m.etaLabel ?? pill.etaCaption)
                        .font(.system(size: 9))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .frame(minHeight: 56)
        }
        .padding(Space.s4)
    }

    // MARK: - Move row helpers

    private func moveAccent(_ m: YardMove) -> Color {
        if isHold(m) { return Brand.warning }
        if isInProgress(m) { return Brand.success }
        if isQueued(m) { return Brand.blue }
        return palette.textSecondary
    }

    private func moveTitle(_ m: YardMove) -> String {
        let base: String = {
            switch (m.moveType ?? "").lowercased() {
            case "pull", "hostler-pull", "hostler_pull": return "Hostler pull"
            case "chassis-mount", "chassis_mount":       return "Chassis mount"
            case "grounding", "ground":                  return "Grounding"
            default: return (m.moveType ?? "Move").capitalized
            }
        }()
        if let loc = m.location, !loc.isEmpty { return "\(base) · \(loc)" }
        return base
    }

    private func moveMeta(_ m: YardMove) -> String {
        var parts: [String] = []
        if let c = m.containerId, !c.isEmpty { parts.append(c) }
        if let e = m.equipment,   !e.isEmpty { parts.append(e) }
        if let d = m.direction,   !d.isEmpty { parts.append(d) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func movePill(_ m: YardMove) -> (text: String, etaCaption: String) {
        if isHold(m)       { return ("HOLD",   "blocked") }
        if isInProgress(m) { return ("MOVING", "to ramp") }
        if isQueued(m)     { return ("QUEUED", "wait") }
        return ((m.status ?? "—").uppercased(), "")
    }

    private func moveEta(_ m: YardMove) -> String {
        if let mins = m.etaMinutes { return "\(mins) min" }
        return "—"
    }

    // MARK: - Capacity guard tile shelf

    private var capacityGuardSection: some View {
        let cap = dashboard?.capacity
        let openSlots = cap?.available
        let openPct: String? = {
            guard let avail = cap?.available, let tot = cap?.total, tot > 0 else { return nil }
            return "\(Int((Double(avail) / Double(tot) * 100).rounded()))% of yard"
        }()
        let detentionN = dashboard?.detentionAlerts?.count
        let gateN = dashboard?.gateEntriesToday
        let facility = dashboard?.facility

        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("CAPACITY GUARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("today")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)

            HStack(spacing: Space.s2) {
                guardTile(
                    dot: Brand.success,
                    value: openSlots.map { "\($0) open" } ?? "—",
                    line1: "slots free",
                    line2: openPct ?? "—")
                guardTile(
                    dot: Brand.danger,
                    value: detentionN.map { "\($0) alerts" } ?? "—",
                    line1: "detention live",
                    line2: "> 2h dwell")
                guardTile(
                    dot: Brand.blue,
                    value: gateN.map { "\($0) gate" } ?? "—",
                    line1: "entries today",
                    line2: facility ?? "BNSF · IL")
            }
        }
    }

    private func guardTile(dot: Color, value: String, line1: String, line2: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(dot).frame(width: 7, height: 7)
                Text(value)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(line1)
                .font(.system(size: 9.5))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, Space.s2)
            Text(line2)
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 2)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - CTA row (Assign next move · Queue)

    private var ctaRow: some View {
        VStack(spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                CTAButton(
                    title: "Assign next move",
                    action: { Task { await assignNextMove() } },
                    leadingIcon: "list.bullet.rectangle",
                    isLoading: assigning
                )
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { filter = .queued }
                } label: {
                    Text("Queue")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: 148, minHeight: 52)
                        .background(Color(hex: 0x232932))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18)))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            if let note = assignNote {
                Text(note)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        do {
            // PORT-GAP: yardManagement.getYardDashboard — EXISTS on the web
            // tRPC router (yardManagement.ts:79) but has no typed Swift
            // wrapper; reached via the generic queryNoInput path helper.
            async let d: YardDashboard = EusoTripAPI.shared.queryNoInput("yardManagement.getYardDashboard")
            // PORT-GAP: yardManagement.getYardMoveQueue — EXISTS
            // (yardManagement.ts:1743), no typed wrapper; generic helper.
            async let q: YardMoveQueue = EusoTripAPI.shared.queryNoInput("yardManagement.getYardMoveQueue")
            let (dash, queueResp) = try await (d, q)
            self.dashboard = dash
            self.queue = queueResp
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Assign next move (mutation)

    private func assignNextMove() async {
        guard !assigning else { return }
        assigning = true; assignNote = nil
        struct AssignIn: Encodable { let auto: Bool }
        struct AssignOut: Decodable { let moveId: String?; let hostlerId: String?; let status: String? }
        do {
            // PORT-GAP: yardManagement.assignYardMove — EXISTS
            // (yardManagement.ts:1829, mutation · updates yardMoves) but has
            // no typed Swift wrapper; reached via the generic mutation helper.
            let out: AssignOut = try await EusoTripAPI.shared.mutation(
                "yardManagement.assignYardMove", input: AssignIn(auto: true))
            if let id = out.moveId {
                assignNote = "Assigned move \(id)\(out.status.map { " · \($0)" } ?? "")."
            } else {
                assignNote = "Next move assigned."
            }
            await load()
        } catch {
            assignNote = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        assigning = false
    }
}

#Preview("600 · Rail Ramp Operations Console · Night") {
    RailRampOperationsConsoleScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("600 · Rail Ramp Operations Console · Light") {
    RailRampOperationsConsoleScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
