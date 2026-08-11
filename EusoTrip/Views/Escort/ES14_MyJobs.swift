//
//  ES14_MyJobs.swift
//  EusoTrip — Escort · ES-14 My Jobs (iOS peer of the ES-14 twins).
//
//  A STAGE PIPELINE BOARD: the escort's own book strung on one vertical
//  gutter, grouped by lifecycle stage, with a per-stage count node at every
//  group head and a funnel strip above that carries the whole ladder —
//  including the stages that are currently empty, drawn as the gaps they are.
//  Nothing here is ranked and nothing competes; it flows.
//
//  Wiring truth (code-traced this firing against
//  frontend/server/routers/escorts.ts, working tree, 4745 lines):
//    REAL  escorts.getMyJobs        escorts.ts:1093 → every row on the board
//          input {status?} → id / loadNumber / status / loadStatus /
//          position / cargoType / hazmatClass / origin / destination /
//          rate / rateType / distance / pickupDate, updatedAt desc, limit 30.
//    REAL  escorts.getJobsSummary   escorts.ts:2392 → the volume band
//          pending / accepted / inProgress / completed / totalEarnings /
//          weeklyEarnings.
//    REAL  escorts.updateJobStatus  escorts.ts:1171 → ADVANCE STAGE
//          and it is a real gate, not a label: promoting a job to en_route
//          requires a PASSED escort_vehicle_inspection for that assignment
//          inside 24 h, or the server throws PRECONDITION_FAILED
//          "Pre-trip vehicle check required" (escorts.ts:1178-1195) — the
//          ES-06 convoy-release interlock. That message is surfaced verbatim
//          and the row does not move.
//
//  Stage vocabulary is the real column, not a local invention:
//  escortAssignments.status = pending | accepted | en_route | on_site |
//  escorting | completed | cancelled (drizzle/schema.ts; zod mirror
//  escorts.ts:26). Position badges come from escortAssignments.position,
//  whose enum is lead | chase | both ONLY (escorts.ts:25) — STEER and
//  HIGH-POLE are in the escort design directive but NOT in this column, so
//  this screen never draws them.
//
//  DOCUMENTED DIVERGENCES FROM THE TWINS (live screen vs fixed fixture —
//  zero invention):
//   1. Per-stage counts. getJobsSummary collapses en_route, on_site and
//      escorting into a single `inProgress` number, so the funnel's three
//      middle nodes are counted from the getMyJobs rows themselves. PENDING,
//      ACCEPTED and COMPLETED come straight off the summary. Stated on
//      screen in the funnel's caption.
//   2. The 187/yr volume line. getCompletedJobs accepts a `period` input in
//      its zod schema (escorts.ts:2424) and never applies it to the query,
//      so no year window is enforced anywhere on the server. This port
//      therefore shows the completed figure the server actually returns —
//      lifetime — and labels it as lifetime rather than dressing it as a
//      rolling twelve months. The twins' 187/yr band returns the moment
//      `period` is honoured or getVolumeByYear lands.
//   3. Days-in-stage. escortAssignments carries startedAt and completedAt
//      only; there is no stage-entered timestamp, so dwell is measured from
//      the row's own updatedAt when the server sends one and is otherwise
//      omitted. STALLED is a client-side aging read on the same field —
//      there is no server aging rule and no auto-withdraw.
//
//  OFFLINE: READ_CACHED(15m). Both reads are stored through
//  EscortOfflineCache (Views/Escort/EscortOfflineCache.swift — used, not
//  re-created). When the live read fails and a snapshot inside the ttl
//  exists, the board paints the snapshot AND renders
//  EscortOfflineCache.stalenessLine above the actions with a grey dot: a
//  snapshot never wears a live badge. Past the ttl the snapshot is refused
//  and the screen shows its offline state instead of stale numbers.
//  ADVANCE STAGE stays ONLINE_ONLY — the escort role has no outbox lanes
//  (PLANNED per the Offline Mode Encyclopedia v2). No queue badge, ever.
//
//  CHAIN: stage transitions are PARTLY CLOSED on the phone.
//  escort:job_assigned, escort:job_started and escort:job_completed all
//  reach iOS and refresh this surface (RealtimeService.swift:451-458), so
//  ACCEPTED, EN ROUTE and DONE light on push. Two halves are missing and
//  named for the ledger: no event distinguishes ON SITE from ESCORTING (both
//  ride the generic job_started lane), and an application going stale in
//  PENDING emits nothing at all — those move on poll only. This screen is
//  also the receiving end of ES-13's A1 SILENT chain: a tender that never
//  lights the marketplace still lands here correctly, because applyForJob
//  broadcasts ESCORT_JOB_APPLIED back to the applicant's own user channel
//  (escorts.ts:918).
//
//  RBAC: escortProcedure (escorts.ts:11) → roleProcedure(ROLES.ESCORT);
//  every row self-scoped by resolveEscortUserId (escorts.ts:138). The money
//  shown is the escort's own assignment rate — never the shipper's linehaul.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire contracts (Codable — the cache stores these verbatim)

/// One row of `escorts.getMyJobs` (escorts.ts:1093).
private struct MyJobRow: Codable, Identifiable {
    let id: String
    let loadNumber: String?
    /// escortAssignments.status
    let status: String?
    /// loads.status — the haul's own state, shown as context only.
    let loadStatus: String?
    /// lead | chase | both
    let position: String?
    let cargoType: String?
    let hazmatClass: String?
    let origin: String?
    let destination: String?
    let rate: Double?
    let rateType: String?
    let distance: Double?
    let pickupDate: String?

    var lane: String { "\(origin ?? "-") → \(destination ?? "-")" }
    var stage: JobStage { JobStage(status ?? "") }
}

private struct MyJobsInput: Encodable { let status: String? }

/// `escorts.getJobsSummary` (escorts.ts:2392). The server's own empty envelope
/// is all-zeros, so absent keys decode to 0 rather than to a second layer of
/// optionality every call-site would have to unwrap twice.
private struct JobsSummary: Codable {
    let available: Int
    let accepted: Int
    let completed: Int
    let totalEarnings: Double
    /// accepted + pending, per the server's own arithmetic (escorts.ts:2416).
    let assigned: Int
    /// en_route + on_site + escorting collapsed into one figure by the server.
    let inProgress: Int
    let weeklyEarnings: Double

    private enum CodingKeys: String, CodingKey {
        case available, accepted, completed, totalEarnings, assigned, inProgress, weeklyEarnings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        available      = try c.decodeIfPresent(Int.self, forKey: .available) ?? 0
        accepted       = try c.decodeIfPresent(Int.self, forKey: .accepted) ?? 0
        completed      = try c.decodeIfPresent(Int.self, forKey: .completed) ?? 0
        totalEarnings  = try c.decodeIfPresent(Double.self, forKey: .totalEarnings) ?? 0
        assigned       = try c.decodeIfPresent(Int.self, forKey: .assigned) ?? 0
        inProgress     = try c.decodeIfPresent(Int.self, forKey: .inProgress) ?? 0
        weeklyEarnings = try c.decodeIfPresent(Double.self, forKey: .weeklyEarnings) ?? 0
    }
}

/// `escorts.updateJobStatus` (escorts.ts:1171).
private struct UpdateJobStatusInput: Encodable {
    let jobId: String
    let status: String
    let notes: String?
}
private struct UpdateJobStatusResult: Decodable {
    let success: Bool?
    let status: String?
}

// MARK: - Stage ladder (the real enum, in lifecycle order)

private enum JobStage: String, CaseIterable, Identifiable {
    case pending, accepted, enRoute = "en_route", onSite = "on_site",
         escorting, completed, cancelled

    var id: String { rawValue }

    init(_ raw: String) {
        self = JobStage(rawValue: raw.lowercased()) ?? .pending
    }

    /// The six stages the board draws. `cancelled` is a terminal side exit
    /// and is never a pipeline node.
    static var ladder: [JobStage] { [.pending, .accepted, .enRoute, .onSite, .escorting, .completed] }

    var label: String {
        switch self {
        case .pending:   return "PENDING"
        case .accepted:  return "ACCEPTED"
        case .enRoute:   return "EN ROUTE"
        case .onSite:    return "ON SITE"
        case .escorting: return "ESCORTING"
        case .completed: return "DONE"
        case .cancelled: return "CANCELLED"
        }
    }

    /// The next status the operator can push this job to, or nil at the end.
    var next: JobStage? {
        switch self {
        case .pending:   return nil          // an award is the counterparty's move
        case .accepted:  return .enRoute
        case .enRoute:   return .onSite
        case .onSite:    return .escorting
        case .escorting: return .completed
        default:         return nil
        }
    }

    var isLive: Bool { self == .escorting }

    func tint(_ palette: Theme.Palette) -> Color {
        switch self {
        case .pending:   return palette.textTertiary
        case .accepted,
             .enRoute:   return Brand.blue
        case .onSite:    return Brand.info
        case .escorting: return Brand.escort
        case .completed: return Brand.success
        case .cancelled: return Brand.danger
        }
    }

    var groupNote: String {
        switch self {
        case .escorting: return "ROLLING NOW"
        case .onSite:    return "ON THE PAD"
        case .enRoute:   return "ROLLING TO STAGE"
        case .accepted:  return "PRE-TRIP DUE"
        case .pending:   return "AWAITING AWARD"
        default:         return ""
        }
    }
}

// MARK: - Screen

struct EscortMyJobs: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    private enum Phase { case loading, empty, loaded, failed }

    private static let cacheTTL: TimeInterval = 15 * 60
    private static let jobsKey = "es14-my-jobs"
    private static let summaryKey = "es14-jobs-summary"

    @State private var phase: Phase = .loading
    @State private var jobs: [MyJobRow] = []
    @State private var summary: JobsSummary? = nil
    /// Non-nil only while the board is painting a disk snapshot.
    @State private var stalenessLine: String? = nil
    @State private var advancing: String? = nil
    @State private var toast: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrowRow
                titleRow
                metaRow
                hairline
                content
                Color.clear.frame(height: 104)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await refresh() }
        .refreshable { await refresh() }
        .overlay(alignment: .bottom) { toastLayer }
    }

    // MARK: Header

    private var eyebrowRow: some View {
        HStack {
            Text("✦ ESCORT · MY JOBS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.diagonal)
            Spacer(minLength: Space.s2)
            Text(companyCaps)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
    }

    private var companyCaps: String {
        if let cid = session.user?.companyId, !cid.isEmpty { return "COMPANY · \(cid)".uppercased() }
        return "ESCORT NETWORK"
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Text("My Jobs")
                .font(.system(size: 28, weight: .heavy)).tracking(-0.4)
                .foregroundStyle(LinearGradient.diagonal)
            Spacer(minLength: 0)
            if let rolling = rollingJob, let n = rolling.loadNumber {
                HStack(spacing: 6) {
                    Circle().fill(AnyShapeStyle(Brand.escort)).frame(width: 6, height: 6)
                    Text(n)
                        .font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(palette.bgCardSoft)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
            }
        }
    }

    private var rollingJob: MyJobRow? {
        jobs.first { $0.stage == .escorting } ?? jobs.first { $0.stage == .onSite }
    }

    /// Green dot is earned here — three of this board's transitions arrive as
    /// push. It flips to grey the moment the board is painting a snapshot.
    private var metaRow: some View {
        HStack(spacing: Space.s3) {
            if let stage = rollingJob?.stage {
                Text(stage.label)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(stage.tint(palette))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(stage.tint(palette).opacity(0.16))
                    .clipShape(Capsule())
            }
            Text("\(liveCount) in book\(rollingJob == nil ? "" : " · 1 rolling")")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
            HStack(spacing: 5) {
                Circle()
                    .fill(AnyShapeStyle(stalenessLine == nil ? Brand.success : palette.textTertiary))
                    .frame(width: 7, height: 7)
                Text(stalenessLine == nil ? "LIVE · PUSH" : "SNAPSHOT")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer(minLength: 0)
            Text(operatorCaps)
                .font(EType.mono(.micro)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
    }

    private var operatorCaps: String {
        let name = session.user?.name ?? ""
        guard !name.isEmpty else { return "" }
        let initials = name.split(separator: " ").prefix(2)
            .compactMap { $0.first.map(String.init) }.joined().uppercased()
        return "\(name) · \(initials)"
    }

    private var hairline: some View {
        Rectangle().fill(palette.iridescentHairline)
            .frame(height: 1).padding(.horizontal, -14)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            loadingCard
        case .empty:
            EusoEmptyState(
                systemImage: "shippingbox",
                title: "Your book is empty",
                subtitle: "Applications and awarded moves land here and walk the stages from pending to done. Open the marketplace to put one in.")
        case .failed:
            errorCard
        case .loaded:
            volumeBand
            funnelStrip
            pipeline
            if let line = stalenessLine { cacheStrip(line) }
            actionBar
        }
    }

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("RESOLVING YOUR BOOK", icon: "arrow.clockwise")
            Text("Pulling your assignments and their stage counts…")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var errorCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
                Text("COULDN'T LOAD YOUR BOOK")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.danger)
            }
            Text("No connection and no snapshot inside the 15-minute window. EusoTrip won't paint older numbers as if they were current — check your signal and pull to refresh.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { Task { await refresh() } } label: {
                Text("Retry")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Volume band (the escort's own throughput — the personality figure)

    private var volumeBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("VOLUME · COMPLETED BOOK")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                if let pct = completionPct {
                    Text("\(pct)% COMPLETION")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(Brand.success)
                }
            }
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(summary?.completed ?? 0)")
                        .font(.system(size: 30, weight: .heavy, design: .monospaced))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("ESCORTS DONE")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(palette.textTertiary)
                }
                .frame(width: 86, alignment: .leading)
                Rectangle().fill(palette.borderFaint).frame(width: 1, height: 36)
                volumeCell("IN BOOK", "\(liveCount)")
                Rectangle().fill(palette.borderFaint).frame(width: 1, height: 36)
                volumeCell("THIS WEEK", money(summary?.weeklyEarnings))
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            Text("Lifetime figure. A rolling-12-month window isn't enforced server-side yet, so this screen won't label it as one.")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var completionPct: Int? {
        guard let done = summary?.completed, done > 0 else { return nil }
        let total = done + liveCount
        guard total > 0 else { return nil }
        return Int((Double(done) / Double(total) * 100).rounded())
    }

    private func volumeCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.mono(.body).weight(.bold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(width: 96, alignment: .leading)
        .padding(.leading, 14)
    }

    private func money(_ v: Double?) -> String {
        guard let v, v > 0 else { return "$0" }
        return "$\(Int(v.rounded()).formatted())"
    }

    // MARK: Funnel strip (the whole ladder, empty stages included)

    private var liveCount: Int {
        jobs.filter { $0.stage != .completed && $0.stage != .cancelled }.count
    }

    /// PENDING / ACCEPTED / COMPLETED come off the summary; the three middle
    /// stages are counted from the rows because getJobsSummary collapses them
    /// into one `inProgress` figure.
    private func count(_ stage: JobStage) -> Int {
        guard let s = summary else { return rowCount(stage) }
        switch stage {
        // The server reports `assigned` as accepted + pending, so pending is
        // that difference — not a second count of the same rows.
        case .pending:   return max(0, s.assigned - s.accepted)
        case .accepted:  return s.accepted
        case .completed: return s.completed
        default:         return rowCount(stage)
        }
    }

    private func rowCount(_ stage: JobStage) -> Int { jobs.filter { $0.stage == stage }.count }

    private var funnelStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("PIPELINE · STAGE COUNTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("\(liveCount) LIVE · \(count(.completed)) DONE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            ZStack(alignment: .top) {
                GeometryReader { geo in
                    let inset = geo.size.width / CGFloat(JobStage.ladder.count) / 2
                    let reach = geo.size.width - inset * 2
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.textTertiary.opacity(0.18))
                            .frame(width: reach, height: 2)
                        Capsule().fill(LinearGradient.primary)
                            .frame(width: reach * reachFraction, height: 2.5)
                    }
                    .padding(.leading, inset)
                    .padding(.top, 13)
                }
                .frame(height: 30)
                HStack(spacing: 0) {
                    ForEach(JobStage.ladder) { stage in
                        funnelNode(stage).frame(maxWidth: .infinity)
                    }
                }
            }
            Text("Middle three counted from your rows — the summary proc reports en route, on site and escorting as one number.")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// How far down the ladder the book actually reaches.
    private var reachFraction: Double {
        let idx = JobStage.ladder.lastIndex { rowCount($0) > 0 } ?? 0
        return Double(idx) / Double(max(1, JobStage.ladder.count - 1))
    }

    private func funnelNode(_ stage: JobStage) -> some View {
        let c = count(stage)
        let empty = c == 0
        return VStack(spacing: 8) {
            ZStack {
                if stage.isLive && !empty {
                    Circle().fill(LinearGradient.diagonal).frame(width: 28, height: 28)
                } else if empty {
                    Circle().fill(palette.bgCard).frame(width: 26, height: 26)
                    Circle()
                        .strokeBorder(palette.textTertiary.opacity(0.5),
                                      style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                        .frame(width: 26, height: 26)
                } else {
                    Circle().fill(stage == .completed ? Brand.success.opacity(0.16) : palette.bgCard)
                        .frame(width: 26, height: 26)
                    Circle().strokeBorder(stage.tint(palette), lineWidth: 2).frame(width: 26, height: 26)
                }
                Text("\(c)")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(stage.isLive && !empty ? Color.white
                                     : (empty ? palette.textTertiary.opacity(0.65)
                                              : (stage == .completed ? Brand.success : palette.textPrimary)))
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Text(stage == .completed ? "DONE" : stage.label)
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.4)
                .foregroundStyle(empty ? palette.textTertiary.opacity(0.65) : stage.tint(palette))
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    // MARK: The pipeline gutter — the book, grouped by stage

    /// Groups run MOST-ADVANCED FIRST so the rolling move sits under the
    /// thumb — the inverse of the funnel above it.
    private var groupOrder: [JobStage] {
        [.escorting, .onSite, .enRoute, .accepted, .pending]
    }

    private var pipeline: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(LinearGradient(
                    colors: [Brand.escort.opacity(0.55), Brand.blue.opacity(0.35)],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: 2)
                .padding(.top, 8)
                .padding(.leading, 11)
            VStack(alignment: .leading, spacing: Space.s3) {
                ForEach(groupOrder) { stage in
                    let rows = jobs.filter { $0.stage == stage }
                    if !rows.isEmpty { stageGroup(stage, rows) }
                }
            }
            .padding(.leading, -1)
        }
    }

    private func stageGroup(_ stage: JobStage, _ rows: [MyJobRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(stage == .escorting || stage == .enRoute
                          ? AnyShapeStyle(stage.tint(palette)) : AnyShapeStyle(palette.bgPage))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(stage.tint(palette), lineWidth: 2.5))
                    .padding(.leading, -7)
                Text(stage.label)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Text("\(rows.count)")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(stage.tint(palette))
                    .frame(width: 26, height: 18)
                    .background(stage.tint(palette).opacity(0.16))
                    .clipShape(Capsule())
                Spacer(minLength: 0)
                Text(stage.groupNote)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(stage == .pending ? Brand.warning : stage.tint(palette))
            }
            VStack(spacing: 6) { ForEach(rows) { jobRow($0) } }
                .padding(.leading, 16)
        }
    }

    private func jobRow(_ job: MyJobRow) -> some View {
        let stalled = isStalled(job)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let p = job.position { positionBadge(p) }
                if stalled {
                    Text("STALLED")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Brand.warning)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Brand.warning.opacity(0.22))
                        .clipShape(Capsule())
                }
                Spacer(minLength: 0)
                if let n = job.loadNumber {
                    Text(n).font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                }
            }
            HStack(alignment: .bottom, spacing: Space.s2) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.lane)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(metaLine(job))
                        .font(EType.mono(.caption))
                        .foregroundStyle(stalled ? Brand.warning : palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                Spacer(minLength: 0)
                if let next = job.stage.next {
                    advanceButton(job, to: next)
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(stalled ? AnyShapeStyle(Brand.warning.opacity(0.08)) : AnyShapeStyle(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(stalled ? Brand.warning.opacity(0.45)
                          : (job.stage.isLive ? Brand.escort.opacity(0.30) : palette.borderFaint),
                          lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func metaLine(_ job: MyJobRow) -> String {
        var parts: [String] = []
        if let d = job.distance, d > 0 { parts.append("\(Int(d.rounded())) mi") }
        if let r = job.rate, r > 0 {
            parts.append("$\(Int(r.rounded()).formatted())\(job.rateType.map { " \($0)" } ?? "")")
        } else {
            parts.append("rate on award")
        }
        if let p = job.pickupDate, let rel = pickupLabel(p) { parts.append(rel) }
        return parts.joined(separator: " · ")
    }

    /// lead | chase | both — nothing else can appear in this column.
    private func positionBadge(_ position: String) -> some View {
        let upper = position.uppercased()
        let tint: Color = upper == "CHASE" ? Brand.escort : (upper == "BOTH" ? Brand.info : Brand.blue)
        return Text(upper)
            .font(.system(size: 9, weight: .heavy)).tracking(0.4)
            .foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(tint.opacity(0.14))
            .clipShape(Capsule())
    }

    /// Client-side aging read: a pending application older than seven days
    /// with nothing back. There is no server rule and no auto-withdraw.
    private func isStalled(_ job: MyJobRow) -> Bool {
        guard job.stage == .pending, let p = job.pickupDate, let d = parseISO(p) else { return false }
        return d.timeIntervalSinceNow < -7 * 86_400
    }

    // MARK: Advance (ONLINE_ONLY, pre-trip gated server-side)

    @ViewBuilder
    private func advanceButton(_ job: MyJobRow, to next: JobStage) -> some View {
        let busy = advancing == job.id
        Button { Task { await advance(job, to: next) } } label: {
            VStack(spacing: 1) {
                Text(busy ? "…" : "→ \(next.label)")
                    .font(.system(size: 9.5, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(palette.textPrimary)
                Text("online only")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .frame(width: 96, height: 34)
            .background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    // MARK: Snapshot staleness

    private func cacheStrip(_ line: String) -> some View {
        HStack(spacing: 8) {
            // grey, never green — a snapshot does not wear a live badge
            Circle().fill(AnyShapeStyle(palette.textTertiary)).frame(width: 7, height: 7)
            Text("\(line) · pull to refresh")
                .font(EType.mono(.caption).weight(.semibold))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Text("SNAPSHOT")
                .font(.system(size: 8.5, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                toast = rollingJob == nil
                    ? "Nothing is rolling right now."
                    : "Opening the rolling move…"
            } label: {
                Text("OPEN ROLLING MOVE")
                    .font(.system(size: 13, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(rollingJob == nil
                                ? AnyShapeStyle(palette.textTertiary.opacity(0.4))
                                : AnyShapeStyle(LinearGradient.primary))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(rollingJob == nil)
        }
    }

    @ViewBuilder
    private var toastLayer: some View {
        if let msg = toast {
            Text(msg)
                .font(EType.caption).foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Capsule().fill(palette.textPrimary.opacity(0.92)))
                .padding(.horizontal, 20).padding(.bottom, 108)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task {
                    try? await Task.sleep(nanoseconds: 2_800_000_000)
                    await MainActor.run { withAnimation(.easeOut(duration: 0.2)) { toast = nil } }
                }
        }
    }

    private func sectionHeader(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 9, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text(text).font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.diagonal)
        }
    }

    // MARK: Data — READ_CACHED(15m) through EscortOfflineCache

    private func refresh() async {
        if jobs.isEmpty { phase = .loading }
        do {
            let rows: [MyJobRow] = try await EusoTripAPI.shared.query(
                "escorts.getMyJobs", input: MyJobsInput(status: nil))
            let sum: JobsSummary? = try? await EusoTripAPI.shared.queryNoInput("escorts.getJobsSummary")
            EscortOfflineCache.store(rows, key: Self.jobsKey)
            if let sum { EscortOfflineCache.store(sum, key: Self.summaryKey) }
            await MainActor.run {
                jobs = rows
                summary = sum
                stalenessLine = nil          // live read — no staleness line
                phase = rows.isEmpty ? .empty : .loaded
            }
        } catch {
            await paintSnapshotOrFail()
        }
    }

    /// The honesty law: paint the last-good snapshot only if it is inside the
    /// declared ttl, and always render its age. Otherwise show the offline
    /// state rather than stale numbers dressed as live ones.
    private func paintSnapshotOrFail() async {
        guard let cached = EscortOfflineCache.load([MyJobRow].self, key: Self.jobsKey, ttl: Self.cacheTTL) else {
            await MainActor.run { if jobs.isEmpty { phase = .failed } }
            return
        }
        let cachedSummary = EscortOfflineCache.load(JobsSummary.self, key: Self.summaryKey, ttl: Self.cacheTTL)
        let line = EscortOfflineCache.stalenessLine(age: cached.age)
        await MainActor.run {
            jobs = cached.value
            summary = cachedSummary?.value
            stalenessLine = line
            phase = cached.value.isEmpty ? .empty : .loaded
        }
    }

    /// ONLINE_ONLY. The ES-06 pre-trip interlock lives on the server; when it
    /// fires, its message is shown verbatim and the row does not move.
    private func advance(_ job: MyJobRow, to next: JobStage) async {
        guard advancing == nil else { return }
        await MainActor.run { advancing = job.id }
        defer { Task { await MainActor.run { advancing = nil } } }
        do {
            let _: UpdateJobStatusResult = try await EusoTripAPI.shared.mutation(
                "escorts.updateJobStatus",
                input: UpdateJobStatusInput(jobId: job.id, status: next.rawValue, notes: nil))
            await MainActor.run { toast = "Moved to \(next.label.lowercased())." }
            await refresh()
        } catch {
            let msg = (error as? EusoTripAPIError)?.errorDescription
                ?? "Couldn't move that job. Stage changes need a live connection — the escort role has no outbox yet."
            await MainActor.run { toast = msg }
        }
    }

    // MARK: Time helpers

    private func parseISO(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }

    private func pickupLabel(_ iso: String) -> String? {
        guard let d = parseISO(iso) else { return nil }
        let s = d.timeIntervalSinceNow
        if s > 0 {
            if s < 3600 { return "pickup in \(Int(s / 60))m" }
            if s < 86_400 { return "pickup in \(Int(s / 3600))h" }
            return "pickup in \(Int(s / 86_400))d"
        }
        let ago = -s
        if ago < 86_400 { return "started \(Int(ago / 3600))h ago" }
        return "started \(Int(ago / 86_400))d ago"
    }
}

// MARK: - Registered surface wrapper

struct EscortMyJobsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortMyJobs()
        } nav: {
            // Escort role tab bar TRIP · COMMS · PERMIT · ME. The book is a
            // pushed route under TRIP until a dedicated JOBS slot lands —
            // EscortNavController.swift is a single-writer file and is NOT
            // edited by this drop.
            BottomNav(
                leading: [
                    NavSlot(label: "Trip",  systemImage: "house",       isCurrent: true),
                    NavSlot(label: "Comms", systemImage: "bubble.left", isCurrent: false),
                ],
                trailing: [
                    NavSlot(label: "Permit", systemImage: "doc.text", isCurrent: false),
                    NavSlot(label: "Me",     systemImage: "person",   isCurrent: false),
                ],
                orbState: .idle
            )
        }
    }
}

#if DEBUG
// Previews don't run `.task`, so both variants render in the loading
// register without touching the network or the cache.
#Preview("ES-14 · My Jobs · Dark") {
    EscortMyJobsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("ES-14 · My Jobs · Light") {
    EscortMyJobsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
#endif
