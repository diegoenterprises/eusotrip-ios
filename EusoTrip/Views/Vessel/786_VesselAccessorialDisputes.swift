//
//  786_VesselAccessorialDisputes.swift
//  EusoTrip — Vessel Operator · Accessorial Disputes (AGED-WORKLIST archetype).
//
//  Faithful 1:1 port of "786 Vessel Accessorial Disputes.svg" (Light + Dark).
//  Turns scattered contested accessorial charges into one aged worklist — an
//  aging bar bucketed by days-since-filed + an oldest-first list — so the
//  operator chases the disputes nearest their carrier-response deadline before
//  they expire. The aging bar + oldest-first order replace per-carrier email
//  chasing; the 90d+ at-deadline dollars surface first. An escalation-forum
//  node rail names the jurisdiction a contested charge escalates to.
//
//  WIRING (server/routers/detentionAccessorials.ts — verified this fire):
//    · getAccessorialDisputes {status?,dateFrom?,dateTo?,limit}? (query,
//        protectedProcedure, dc.status='disputed', companyId-scoped :1940)
//        -> { disputes[{id,claimId,loadId,type,originalAmount,disputedAmount,
//             reason,status,filedDate,carrierName,shipperName}],
//             summary{total,totalDisputedAmount,resolvedCount,pendingCount,winRate} }
//        SERVER GAP (honest): resolvedCount=0, winRate=0 hard-coded and
//        status pinned 'under_review' — won/denied aging + win-rate not yet
//        computed, so the hero shows "win-rate pending" (never a faked rate).
//    · "File new dispute" -> disputeDetention {claimId,reason(min10)} mutation
//        (:1083, IDOR-gated by companyId ownership, writes blockchainAuditTrail
//        + broadcasts). On this board every row is already disputed, so the
//        call is idempotent — the real server response is surfaced honestly.
//    · "Export" -> exportDetentionLedger NAMED SERVER GAP — surfaced honestly.
//  transportMode=vessel · USD. No mock data.
//

import SwiftUI

private struct Dispute786: Decodable, Identifiable {
    let id: Int
    let claimId: Int?
    let loadId: Int?
    let type: String?
    let disputedAmount: Double?
    let reason: String?
    let filedDate: String?
    let carrierName: String?
}
private struct DisputeSummary786: Decodable {
    let total: Int?
    let totalDisputedAmount: Double?
    let winRate: Int?
}
private struct DisputeResponse786: Decodable {
    let disputes: [Dispute786]?
    let summary: DisputeSummary786?
}
private struct DisputeResult786: Decodable { let success: Bool?; let status: String?; let message: String? }

private enum AgeBucket786: Int, CaseIterable {
    case a0_30, a31_60, a61_90, a90plus
    var label: String { ["0-30d", "31-60d", "61-90d", "90d+"][rawValue] }
    var color: Color { [Brand.success, Brand.warning, Color(hex: 0xFF7043), Brand.danger][rawValue] }
    static func of(days: Int) -> AgeBucket786 {
        if days <= 30 { return .a0_30 }; if days <= 60 { return .a31_60 }
        if days <= 90 { return .a61_90 }; return .a90plus
    }
}

struct VesselAccessorialDisputesScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselAccessorialDisputesBody() } nav: { VesselDetnNav(active: .compliance) }
    }
}

private struct VesselAccessorialDisputesBody: View {
    @Environment(\.palette) private var palette
    @State private var data: DisputeResponse786? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionMessage: String? = nil
    @State private var actionError: String? = nil
    @State private var filing = false

    private var disputes: [Dispute786] { data?.disputes ?? [] }
    private var totalDisputed: Double { data?.summary?.totalDisputedAmount ?? 0 }

    private func ageDays(_ iso: String?) -> Int {
        guard let iso, let d = Self.parse(iso) else { return 0 }
        return max(0, Int(Date().timeIntervalSince(d) / 86400))
    }
    private func bucketTotal(_ b: AgeBucket786) -> Double {
        disputes.filter { AgeBucket786.of(days: ageDays($0.filedDate)) == b }.reduce(0) { $0 + ($1.disputedAmount ?? 0) }
    }
    private var atDeadline: [Dispute786] { disputes.filter { AgeBucket786.of(days: ageDays($0.filedDate)) == .a90plus } }
    private var sortedOldest: [Dispute786] { disputes.sorted { ageDays($0.filedDate) > ageDays($1.filedDate) } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                VDetnEyebrow(section: "DISPUTES", caption: "\(disputes.count) OPEN · \(atDeadline.count) AT DEADLINE")
                Text("Accessorial disputes").font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                IridescentHairline()

                if loading {
                    loadingCard
                } else if let err = loadError {
                    errorCard(err)
                } else if disputes.isEmpty {
                    EusoEmptyState(systemImage: "checkmark.seal",
                                   title: "No open disputes",
                                   subtitle: "No contested accessorial charges are awaiting a carrier reply.")
                } else {
                    heroCard
                    agingCard
                    worklistCard
                    atDeadlineStrip
                    escalationForum
                    ctaPair
                    if let e = actionError {
                        errorCard(e)
                    } else if let m = actionMessage {
                        LifecycleCard { Text(m).font(EType.caption).foregroundStyle(palette.textSecondary) }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Hero

    private var heroCard: some View {
        ActiveCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TOTAL IN DISPUTE").font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(VDetn.money(totalDisputed))
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundStyle(LinearGradient.diagonal).minimumScaleFactor(0.6).lineLimit(1)
                    Text("\(disputes.count) open · \(atDeadline.count) nearing deadline")
                        .font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("WIN RATE").font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text("pending").font(.system(size: 20, weight: .bold)).foregroundStyle(Brand.warning)
                    Text("awaiting carrier reply").font(.system(size: 9)).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    // MARK: Aging bar

    private var agingCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("DISPUTE AGING · DAYS SINCE FILED").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 14) {
                GeometryReader { g in
                    let vals = AgeBucket786.allCases.map { bucketTotal($0) }
                    let denom = max(1, vals.reduce(0, +))
                    HStack(spacing: 3) {
                        ForEach(AgeBucket786.allCases, id: \.rawValue) { b in
                            RoundedRectangle(cornerRadius: 3).fill(b.color)
                                .frame(width: max(0, CGFloat(bucketTotal(b) / denom) * g.size.width - 3))
                        }
                    }
                    .frame(height: 16)
                }
                .frame(height: 16)
                VStack(spacing: 10) {
                    HStack {
                        agingLegend(.a0_30); Spacer(minLength: 24); agingLegend(.a31_60)
                    }
                    HStack {
                        agingLegend(.a61_90); Spacer(minLength: 24); agingLegend(.a90plus)
                    }
                }
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func agingLegend(_ b: AgeBucket786) -> some View {
        HStack(spacing: 8) {
            Circle().fill(b.color).frame(width: 8, height: 8)
            Text(b.label).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(palette.textPrimary)
            Spacer(minLength: 8)
            Text(VDetn.money(bucketTotal(b))).font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Worklist — oldest first

    private var worklistCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("OPEN DISPUTES · OLDEST FIRST").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                let rows = Array(sortedOldest.prefix(3).enumerated())
                ForEach(rows, id: \.element.id) { idx, d in
                    disputeRow(d)
                    if idx < rows.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func disputeRow(_ d: Dispute786) -> some View {
        let bucket = AgeBucket786.of(days: ageDays(d.filedDate))
        return HStack(spacing: Space.s3) {
            VDetnIconChip(systemImage: "hammer", color: Brand.escort)
            VStack(alignment: .leading, spacing: 3) {
                Text(d.carrierName ?? "Carrier").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text("\(d.type ?? "detention") · \(d.reason ?? "amount contested")")
                    .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                VDetnPill(text: bucket.label, color: bucket.color)
                Text(VDetn.money(d.disputedAmount ?? 0))
                    .font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    // MARK: At-deadline strip

    private var atDeadlineStrip: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("AT DEADLINE · 90d+ BUCKET").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text("\(atDeadline.count) claim\(atDeadline.count == 1 ? "" : "s") · carrier reply overdue")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text(VDetn.money(bucketTotal(.a90plus)))
                .font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundStyle(Brand.danger)
        }
        .padding(Space.s4)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
    }

    // MARK: Escalation forum node rail

    private var escalationForum: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("ESCALATION FORUM BY REGIME").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("US ACTIVE · 46 CFR 541").font(.system(size: 9, weight: .bold)).foregroundStyle(Brand.info)
            }
            HStack(spacing: 0) {
                forumNode("US · FMC", active: true); forumConnector()
                forumNode("CA · CTA", active: false); forumConnector()
                forumNode("MX · API", active: false)
            }
        }
    }

    private func forumNode(_ label: String, active: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack {
                if active { Circle().fill(Brand.info.opacity(0.16)).frame(width: 18, height: 18) }
                Circle().fill(active ? Brand.info : palette.bgCard).frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(active ? Color.clear : palette.textTertiary, lineWidth: 1.6))
            }
            Text(label).font(.system(size: 10.5, weight: active ? .heavy : .semibold))
                .foregroundStyle(active ? Brand.info : palette.textSecondary)
        }
    }
    private func forumConnector() -> some View {
        Rectangle().fill(palette.borderSoft).frame(height: 1).frame(maxWidth: .infinity).padding(.bottom, 18)
    }

    // MARK: CTA

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: filing ? "Filing…" : "File new dispute", action: { Task { await fileDispute() } }, isLoading: filing)
            secondaryButton786(title: "Export") { exportGap() }.frame(width: 120)
        }
    }

    private func secondaryButton786(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(EType.title).foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color(hex: 0x232932))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Load / actions

    private struct DisputeInput786: Encodable { let limit: Int }
    private struct FileInput786: Encodable { let claimId: Int; let reason: String }

    private func load() async {
        loading = true; loadError = nil
        do {
            self.data = try await EusoTripAPI.shared.query(
                "detentionAccessorials.getAccessorialDisputes", input: DisputeInput786(limit: 25))
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func fileDispute() async {
        guard !filing else { return }
        actionMessage = nil; actionError = nil
        guard let target = sortedOldest.first, let claimId = target.claimId else {
            actionError = "No claim is available to file against. New disputes are filed from the approved-charges queue; this board lists charges already contested."
            return
        }
        filing = true
        do {
            let r: DisputeResult786 = try await EusoTripAPI.shared.mutation(
                "detentionAccessorials.disputeDetention",
                input: FileInput786(claimId: claimId,
                                    reason: "Re-asserting dispute on the oldest at-deadline accessorial charge pending carrier reply and free-time evidence review."))
            actionMessage = r.message ?? "Dispute re-asserted for claim \(claimId) (status \(r.status ?? "disputed"))."
            await load()
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        filing = false
    }

    private func exportGap() {
        actionMessage = nil
        actionError = "Export is not available for this view. The live dispute worklist remains available here."
    }

    private var loadingCard: some View {
        LifecycleCard { Text("Loading dispute worklist…").font(EType.caption).foregroundStyle(palette.textSecondary) }
    }
    private func errorCard(_ e: String) -> some View {
        LifecycleCard(accentDanger: true) { Text(e).font(EType.caption).foregroundStyle(Brand.danger) }
    }

    // ISO-8601 or "yyyy-MM-dd HH:mm:ss" parser (filedDate can be either).
    private static let isoFmt: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private static let isoFmtNoFrac: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
    private static let sqlFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; f.timeZone = TimeZone(identifier: "UTC"); return f }()
    private static func parse(_ s: String) -> Date? {
        isoFmt.date(from: s) ?? isoFmtNoFrac.date(from: s) ?? sqlFmt.date(from: s)
    }
}

#Preview("786 · Vessel Accessorial Disputes · Night") { VesselAccessorialDisputesScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("786 · Vessel Accessorial Disputes · Light") { VesselAccessorialDisputesScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
