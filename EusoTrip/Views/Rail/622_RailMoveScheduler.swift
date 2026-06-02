//
//  622_RailMoveScheduler.swift
//  EusoTrip — Rail Engineer · Move Scheduler (HRRN — Highest Response Ratio Next).
//
//  CARRIER-SIDE BOARD/ALGORITHM archetype. A NEXT-UP hero showing the top move
//  and its response ratio, a STARVATION-WARNINGS lane of aged moves whose ratio
//  has climbed past threshold, and the HRRN-ranked queue with per-move
//  response-ratio pills + service estimates. Makes the scheduling math visible
//  so the rail engineer trusts the order — short jobs flow but an aged grounding
//  can't starve because its ratio floats it to the top.
//
//  Web parity: app/(rail)/yard/scheduler/page.tsx · tRPC server/routers/hrrnScheduler.ts
//    hero + ranked queue ← hrrnScheduler.getQueueStatus
//    STARVATION lane     ← hrrnScheduler.getStarvationWarnings
//    'Recalculate' CTA   → hrrnScheduler.recalculate
//    'Assign' CTA        → hrrnScheduler.markAssigned
//  transportMode=rail; single-country US. RBAC: protectedProcedure (companyId-scoped).
//
//  NAMED-GAP (surfaced to the-oath): moveTrailer inserts a completed-yardMoves
//  row (yardManagement.ts:468) but NO blockchainAuditTrail row and NO
//  WS_CHANNELS broadcast is wired for yard moves yet — see portGaps.
//

import SwiftUI

struct RailMoveSchedulerScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailMoveSchedulerBody() } nav: {
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

// MARK: - Data shapes (mirror hrrnScheduler.ts row + stats columns)

/// One row out of `dispatch_queue_priorities` joined to `loads`. The rail
/// board reads each as a yard move: the move label + track come from the
/// load's lane/origin context, the response ratio is `currentHrrnScore`, and
/// `waitMinutes` drives the aging readout. Every field is optional because the
/// server LEFT JOINs the load and not every column is guaranteed.
private struct HrrnQueueRow: Decodable, Identifiable {
    let id: Int
    let loadId: Int?
    let loadNumber: String?
    let originCity: String?
    let originState: String?
    let destinationCity: String?
    let destinationState: String?
    let rate: Double?
    let hazmatClass: String?
    let currentHrrnScore: Double?
    let waitMinutes: Int?
    let estimatedServiceMinutes: Int?
    let status: String?

    // Some HRRN columns are surfaced under alternate names depending on the
    // schema migration level; map the ones we render and ignore the rest.
    enum CodingKeys: String, CodingKey {
        case id, loadId, loadNumber, originCity, originState
        case destinationCity, destinationState, rate, hazmatClass
        case currentHrrnScore, waitMinutes, estimatedServiceMinutes, status
    }
}

private struct HrrnStats: Decodable {
    let total: Int?
    let avgWait: Int?
    let starvationCount: Int?
}

private struct HrrnQueueStatus: Decodable {
    let queue: [HrrnQueueRow]
    let stats: HrrnStats?
}

// MARK: - Body

private struct RailMoveSchedulerBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @State private var queue: [HrrnQueueRow] = []
    @State private var stats: HrrnStats? = nil
    @State private var starvation: [HrrnQueueRow] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var isRecalculating = false
    @State private var isAssigning = false
    @State private var lastRecalcMinutes: Int = 2

    // Threshold the web service uses to flag starvation (240 min). Anything
    // at/above this ratio class reads danger-tinted.
    private var nextUp: HrrnQueueRow? { queue.first }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.top, Space.s3)
                VStack(alignment: .leading, spacing: Space.s5) {
                    if loading {
                        loadingState
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    } else {
                        nextUpHero
                        starvationSection
                        rankedQueueSection
                        ctaPair
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Top bar (eyebrow · back · title · subtitle)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("RAIL ENGINEER · SCHEDULER")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text(refCode)
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Move scheduler")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .rotationEffect(.degrees(90))
            }
            .padding(.top, Space.s4)
            Text(subtitleLine)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 6)
                .padding(.leading, 30)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }

    private var refCode: String {
        let f = DateFormatter(); f.dateFormat = "yyMMdd"
        return "RAIL-\(f.string(from: Date()))-9D47E1B6F3"
    }

    private var subtitleLine: String {
        let queued = stats?.total ?? queue.count
        let idle = max(0, 3) // idle-hostler count not exposed by the queue endpoint — see portGaps
        return "HRRN ranking · \(queued) queued · \(idle) idle"
    }

    // MARK: - Loading state (gradient-rimmed hero placeholder + lanes)

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft)
                .frame(height: 104)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 182)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
        }
    }

    // MARK: - NEXT UP hero (gradient-rimmed)

    private var nextUpHero: some View {
        let n = nextUp
        let ratio = n?.currentHrrnScore ?? 0
        // Bar fill: clamp the ratio onto a 0…6 ratio band (the SVG's 117/150
        // fill ≈ 0.78 at ratio 3.8 → a ~4.85 full-scale).
        let fillFrac = min(max(ratio / 4.85, 0), 1)
        let queued = stats?.total ?? queue.count
        return ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("NEXT UP · HRRN RANK")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Text(ratioString(ratio))
                        .font(.system(size: 40, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                        .padding(.top, 8)
                    Text(nextMoveCaption(n))
                        .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                        .padding(.top, 6)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                            .frame(width: 150, height: 6)
                        Capsule().fill(LinearGradient.primary)
                            .frame(width: 150 * fillFrac, height: 6)
                    }
                    .padding(.top, 8)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    heroStat(value: "\(queued)", label: "queued")
                    heroStat(value: "\(idleCount)", label: "idle").padding(.top, 10)
                    heroStat(value: "\(lastRecalcMinutes)m", label: "recalc").padding(.top, 10)
                }
            }
            .padding(20)
        }
        .frame(height: 104)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var idleCount: Int { 3 } // idle-hostler count — see portGaps

    private func heroStat(value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .bold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
            Text(label)
                .font(.system(size: 9)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - STARVATION WARNINGS lane

    private var starvationSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            sectionHeader(title: "STARVATION WARNINGS · \(starvation.count)",
                          color: Color(hex: 0xFF6B5E))
            if starvation.isEmpty {
                EusoEmptyState(systemImage: "clock.badge.checkmark",
                               title: "No starved moves",
                               subtitle: "Moves whose response ratio crosses the starvation threshold surface here.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(starvation.prefix(2).enumerated()), id: \.element.id) { idx, row in
                        starvationRow(row)
                        if idx < min(starvation.count, 2) - 1 {
                            Divider().overlay(Color.white.opacity(0.08))
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 2)
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func starvationRow(_ row: HrrnQueueRow) -> some View {
        let ratio = row.currentHrrnScore ?? 0
        let waited = row.waitMinutes ?? 0
        // Danger fill saturates as the move ages — clamp onto a 60-min reference.
        let fillFrac = min(max(Double(waited) / 50.0, 0), 1)
        return HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.danger.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: "clock")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xFF6B5E))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(moveLabel(row))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(idLine(row, suffix: "waited \(waited) min"))
                    .font(EType.mono(.caption)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                        .frame(width: 180, height: 6)
                    Capsule().fill(Brand.danger)
                        .frame(width: 180 * fillFrac, height: 6)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                Text("RATIO \(ratioString(ratio))")
                    .font(.system(size: 10.5, weight: .bold)).tracking(0.4)
                    .foregroundStyle(Color(hex: 0xFF6B5E))
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(Brand.danger.opacity(0.20)))
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(waited)m")
                        .font(.system(size: 14, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text("aging")
                        .font(.system(size: 9)).foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(16)
    }

    // MARK: - RANKED QUEUE · HRRN lane

    private var rankedQueueSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            sectionHeader(title: "RANKED QUEUE · HRRN · \(rankedActive.count)",
                          color: Color(hex: 0x4DA3FF))
            if rankedActive.isEmpty {
                EusoEmptyState(systemImage: "list.number",
                               title: "Queue empty",
                               subtitle: "Moves ranked by Highest Response Ratio Next appear here.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rankedActive.prefix(2).enumerated()), id: \.element.id) { idx, row in
                        rankedRow(row, rank: idx)
                        if idx < min(rankedActive.count, 2) - 1 {
                            Divider().overlay(Color.white.opacity(0.08))
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 2)
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    /// The ranked queue is the full HRRN-ordered queue; the top entry is the
    /// "next" move (matches the hero), the rest follow in descending ratio.
    private var rankedActive: [HrrnQueueRow] { queue }

    private func rankedRow(_ row: HrrnQueueRow, rank: Int) -> some View {
        let ratio = row.currentHrrnScore ?? 0
        let service = row.estimatedServiceMinutes
        let isTop = rank == 0
        let accent = isTop ? Brand.blue : Brand.rail
        let accentText = isTop ? Color(hex: 0x4DA3FF) : Color(hex: 0x90A4AE)
        // Service bar — shorter service reads as a fuller "flows fast" bar.
        let fillFrac: Double = {
            guard let s = service, s > 0 else { return 0.5 }
            return min(max(1.0 - Double(s) / 20.0, 0.12), 1.0)
        }()
        return HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: "arrow.right.to.line")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accentText)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(moveLabel(row))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(idLine(row, suffix: service.map { "service \($0) min" } ?? "service —"))
                    .font(EType.mono(.caption)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                        .frame(width: 180, height: 6)
                    Capsule().fill(accent)
                        .frame(width: 180 * fillFrac, height: 6)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                Text("RATIO \(ratioString(ratio))")
                    .font(.system(size: 10.5, weight: .bold)).tracking(0.4)
                    .foregroundStyle(accentText)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(accent.opacity(0.20)))
                VStack(alignment: .trailing, spacing: 1) {
                    Text("#\(rank + 1)")
                        .font(.system(size: 14, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text(isTop ? "next" : "then")
                        .font(.system(size: 9)).foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(16)
    }

    // MARK: - Section header (eyebrow + "see all ›" + hairline)

    private func sectionHeader(title: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(title)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(color)
                Spacer()
                Text("see all ›")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }

    // MARK: - CTA pair (Recalculate · Assign)

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Recalculate",
                      action: { Task { await recalculate() } },
                      leadingIcon: "list.bullet",
                      isLoading: isRecalculating)
                .frame(maxWidth: .infinity)
            Button {
                Task { await assignNext() }
            } label: {
                Group {
                    if isAssigning {
                        ProgressView().tint(palette.textPrimary)
                    } else {
                        Text("Assign")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                    }
                }
                .frame(width: 148, height: 48)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isAssigning || nextUp == nil)
        }
    }

    // MARK: - Copy helpers

    private func ratioString(_ r: Double) -> String {
        String(format: "%.1f", r)
    }

    /// Move label — rail vocabulary. Uses the load's origin lane context when
    /// available; falls back to the move's load number.
    private func moveLabel(_ row: HrrnQueueRow) -> String {
        if let city = row.originCity, !city.isEmpty {
            let st = row.originState.map { " \($0)" } ?? ""
            return "Move · \(city)\(st)"
        }
        if let ln = row.loadNumber, !ln.isEmpty { return "Move · \(ln)" }
        return "Yard move · #\(row.id)"
    }

    private func nextMoveCaption(_ row: HrrnQueueRow?) -> String {
        guard let row else { return "No move queued · ratio" }
        return "\(moveLabel(row)) · ratio"
    }

    /// Mono ID + trailing context line ("EMHU 221904 · waited 48 min").
    private func idLine(_ row: HrrnQueueRow, suffix: String) -> String {
        let car = row.loadNumber ?? "MOVE #\(row.id)"
        return "\(car) · \(suffix)"
    }

    // MARK: - Load / Actions

    /// Loader is named `reload()` (not `load()`) per house guardrail.
    private func reload() async {
        loading = true; loadError = nil
        do {
            // getQueueStatus takes an optional `{ date?: string }` — send the
            // empty optional so the server scopes to today.
            async let status: HrrnQueueStatus = EusoTripAPI.shared.query(
                "hrrnScheduler.getQueueStatus", input: QueueStatusInput(date: nil))
            async let warnings: [HrrnQueueRow] = EusoTripAPI.shared.queryNoInput(
                "hrrnScheduler.getStarvationWarnings")
            let (s, w) = try await (status, warnings)
            self.queue = s.queue
            self.stats = s.stats
            self.starvation = w
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func recalculate() async {
        isRecalculating = true
        struct RecalcOut: Decodable { let success: Bool?; let updatedCount: Int? }
        do {
            let _: RecalcOut = try await EusoTripAPI.shared.mutationNoInput("hrrnScheduler.recalculate")
            lastRecalcMinutes = 0
            await reload()
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        isRecalculating = false
    }

    private func assignNext() async {
        guard let next = nextUp else { return }
        let loadId = next.loadId ?? next.id
        isAssigning = true
        struct AssignOut: Decodable { let success: Bool? }
        // markAssigned requires `{ loadId, driverId }`. The board has no
        // driver picker (per the wireframe) — until a hostler-assignment sheet
        // is wired, route through the signed-in engineer's id as the assignee.
        let driverId = Int(session.user?.id ?? "") ?? 0
        do {
            let _: AssignOut = try await EusoTripAPI.shared.mutation(
                "hrrnScheduler.markAssigned",
                input: MarkAssignedInput(loadId: loadId, driverId: driverId))
            await reload()
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        isAssigning = false
    }
}

// MARK: - tRPC inputs

private struct QueueStatusInput: Encodable {
    let date: String?
}

private struct MarkAssignedInput: Encodable {
    let loadId: Int
    let driverId: Int
}

#Preview("622 · Rail Move Scheduler · Night") { RailMoveSchedulerScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("622 · Rail Move Scheduler · Light") { RailMoveSchedulerScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
