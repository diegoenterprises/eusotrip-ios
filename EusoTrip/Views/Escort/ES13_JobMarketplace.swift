//
//  ES13_JobMarketplace.swift
//  EusoTrip — Escort · ES-13 Job Marketplace (iOS peer of the ES-13 twins).
//
//  A RANKED DEMAND BOARD: the open oversize tenders an escort can bid on,
//  ordered by a live sort key, with an URGENT broadcast class pinned above
//  the ranking and APPLY as the single verb.
//
//  Wiring truth (code-traced this firing against
//  frontend/server/routers/escorts.ts, working tree, 4745 lines):
//    REAL  escorts.getAvailableJobs     escorts.ts:771  → the board rows
//          input {filter?, search?}; server filter is
//          requiresEscort = true OR cargoType = 'oversized', status IN
//          posted|assigned, ordered createdAt desc, limit 50. Returns
//          escortsNeeded / positionsFilled / positionsOpen / applicants /
//          urgency / applied per row — every count on this screen is one of
//          those fields, never a local guess.
//    REAL  escorts.getMarketplaceStats  escorts.ts:849  → header + market strip
//          avgPay = AVG(escortAssignments.rate) over COMPLETED assignments,
//          i.e. the escort's OWN completed book. It is never loads.rate:
//          shipper linehaul is RBAC-forbidden to this role and is not read
//          anywhere in this file.
//    REAL  escorts.applyForJob          escorts.ts:890  → APPLY
//          INSERT escortAssignments status 'pending'; the server's own
//          duplicate guard throws "Already applied to this job" and that
//          message is surfaced verbatim rather than pre-empted locally.
//
//  ABSENT (named gaps — nothing on this screen pretends otherwise):
//    · Load WIDTH. The loads table has no width/height/length column; the
//      only dimension source in the tree is routes.vehicleProfile, which
//      getAvailableJobs does not join. The twins rank on width; this port
//      cannot, so the WIDTH key is not offered and the third metric bar
//      carries WEIGHT, which is real. Stated on screen in the market note.
//    · Per-tender RATE. getAvailableJobs returns none, and the escort's rate
//      is only set at apply. The RATE rank chip is rendered dashed and
//      disabled with that sentence attached — the board never ranks on a
//      number that does not exist.
//    · The 30-mi emergency RING. No radius / geo / emergency procedure
//      exists in escorts.ts, and emitEscortJobAvailable fans out globally
//      with no geo filter. This port therefore renders the URGENT class off
//      the real server flag (urgency == "urgent", computed as pickup inside
//      48 h) and labels it by what it actually is — a time ring, not a
//      distance ring.
//    · Deadhead from the operator. The server returns lane distance only;
//      the DIST key ranks on lane distance and says so.
//    · ESANG match score. No scoring procedure exists for the escort role,
//      so no match chip is drawn here.
//
//  OFFLINE: ONLINE_ONLY. The phone's Unified Outbox is Driver-only, so the
//  escort role has no queue lanes (PLANNED per the Offline Mode Encyclopedia
//  v2) and APPLY is a live call or nothing. This surface also takes NO read
//  cache by design: a stale tender board would send an operator driving at
//  an expired window, so with no connection it shows its offline state
//  rather than a snapshot. No queue badge is ever drawn.
//
//  CHAIN A1 SILENT. A newly posted tender does not light this board on the
//  phone. The server half exists — escorts.requestEscort (escorts.ts:572)
//  calls emitEscortJobAvailable (escorts.ts:624) onto WS_CHANNELS.ESCORT_JOBS
//  — but iOS never joins the escort:jobs room and RealtimeService handles
//  only escort:job_applied / job_assigned / job_started / job_completed, so
//  escort:job_available is dropped. The board therefore lights on POLL: the
//  freshness dot is amber, the sweep line says "no push lane", and pull-to-
//  refresh is the real refresh path. Missing half for the chain ledger:
//  an escort:jobs room join + an escort:job_available case in
//  RealtimeService.swift (not edited here — single-writer file).
//
//  RBAC: escortProcedure (escorts.ts:11) → roleProcedure(ROLES.ESCORT);
//  applications are self-scoped by resolveEscortUserId (escorts.ts:138).
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire contracts (mirror the escorts.ts return literals — no invented fields)

/// One row of `escorts.getAvailableJobs` (escorts.ts:771).
private struct AvailableJobRow: Decodable, Identifiable {
    let id: String
    let loadNumber: String?
    let status: String?
    let cargoType: String?
    let hazmatClass: String?
    let commodityName: String?
    let origin: String?
    let destination: String?
    let distance: Double?
    let weight: Double?
    let pickupDate: String?
    let specialInstructions: String?
    let escortsNeeded: Int?
    let positionsFilled: Int?
    let positionsOpen: Int?
    let applicants: Int?
    /// "urgent" (pickup inside 48 h) | "filled" | "normal" — server-computed.
    let urgency: String?
    let applied: Bool?
    let postedAt: String?

    var seats: Int { escortsNeeded ?? 0 }
    var open: Int { positionsOpen ?? 0 }
    var bidders: Int { applicants ?? 0 }
    var isUrgent: Bool { (urgency ?? "") == "urgent" }
    var isFilled: Bool { open <= 0 }
    var didApply: Bool { applied ?? false }
    /// More bidders than seats left.
    var isContested: Bool { !isFilled && bidders > open }
    var lane: String {
        let o = origin ?? "-", d = destination ?? "-"
        return "\(o) → \(d)"
    }
}

private struct AvailableJobsInput: Encodable {
    let filter: String?
    let search: String?
}

/// `escorts.getMarketplaceStats` (escorts.ts:849). The server's own empty
/// envelope is all-zeros, so absent keys decode to 0 rather than to a second
/// layer of optionality the call-sites would have to unwrap twice.
private struct MarketplaceStats: Decodable {
    let availableJobs: Int
    let urgentJobs: Int
    let avgPay: Int
    let newThisWeek: Int
    let myApplications: Int

    private enum CodingKeys: String, CodingKey {
        case availableJobs, urgentJobs, avgPay, newThisWeek, myApplications
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        availableJobs  = try c.decodeIfPresent(Int.self, forKey: .availableJobs) ?? 0
        urgentJobs     = try c.decodeIfPresent(Int.self, forKey: .urgentJobs) ?? 0
        avgPay         = try c.decodeIfPresent(Int.self, forKey: .avgPay) ?? 0
        newThisWeek    = try c.decodeIfPresent(Int.self, forKey: .newThisWeek) ?? 0
        myApplications = try c.decodeIfPresent(Int.self, forKey: .myApplications) ?? 0
    }
}

/// `escorts.applyForJob` (escorts.ts:890).
private struct ApplyForJobInput: Encodable {
    let jobId: String
    let position: String?
    let message: String?
}
private struct ApplyForJobResult: Decodable {
    let success: Bool?
    let jobId: String?
    let appliedAt: String?
}

// MARK: - Rank keys

private enum MarketRankKey: String, CaseIterable, Identifiable {
    case distance = "DIST"
    case weight   = "WEIGHT"
    case demand   = "DEMAND"
    case rate     = "RATE"

    var id: String { rawValue }
    /// RATE is permanently unrankable — see the header note.
    var isRankable: Bool { self != .rate }
    var chipLabel: String { self == .rate ? "RATE ✱" : rawValue }
}

// MARK: - Screen

struct EscortJobMarketplace: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    private enum Phase { case loading, empty, loaded, failed }

    @State private var phase: Phase = .loading
    @State private var rows: [AvailableJobRow] = []
    @State private var stats: MarketplaceStats? = nil
    @State private var rankKey: MarketRankKey = .distance
    @State private var search: String = ""
    @State private var applying: String? = nil
    @State private var toast: String? = nil
    @State private var sweptAt: Date? = nil

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
            Text("✦ ESCORT · JOB MARKETPLACE")
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
            Text("Job Marketplace")
                .font(.system(size: 28, weight: .heavy)).tracking(-0.4)
                .foregroundStyle(LinearGradient.diagonal)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if let n = stats?.availableJobs {
                HStack(spacing: 6) {
                    Circle().fill(AnyShapeStyle(Brand.blue)).frame(width: 6, height: 6)
                    Text("\(n) POSTED")
                        .font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textPrimary)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(palette.bgCardSoft)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
            }
        }
    }

    /// Amber dot, not green: this board polls (chain A1 SILENT).
    private var metaRow: some View {
        HStack(spacing: Space.s3) {
            if let u = stats?.urgentJobs, u > 0 {
                Text("\(u) URGENT")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(Brand.danger)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Brand.danger.opacity(0.14))
                    .clipShape(Capsule())
            }
            if let a = stats?.myApplications {
                Text("\(a) application\(a == 1 ? "" : "s") out")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            HStack(spacing: 5) {
                Circle().fill(AnyShapeStyle(Brand.warning)).frame(width: 7, height: 7)
                Text(sweepLabel)
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

    private var sweepLabel: String {
        guard let t = sweptAt else { return "POLL" }
        let s = Int(Date().timeIntervalSince(t))
        if s < 60 { return "POLL \(max(s, 1))s" }
        return "POLL \(s / 60)m"
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
                systemImage: "tray",
                title: "No open tenders",
                subtitle: "Nothing needing an escort is posted right now. This board sweeps on refresh — pull down once you are staged and ready to run.")
        case .failed:
            errorCard
        case .loaded:
            if !urgentRows.isEmpty { urgentSection }
            rankSection
            rankedList
            marketStrip
            sweepStrip
        }
    }

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("SWEEPING THE BOARD", icon: "arrow.clockwise")
            Text("Pulling open oversize tenders and your application state…")
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
                Text("COULDN'T REACH THE BOARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.danger)
            }
            Text("This screen shows live demand only — it keeps no cached copy, because a stale tender board would send you driving at a window that already closed. Check your connection and retry.")
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

    // MARK: Urgent class (real server `urgency` flag — a time ring, not a geo ring)

    private var urgentRows: [AvailableJobRow] { rows.filter { $0.isUrgent && !$0.isFilled } }
    private var normalRows: [AvailableJobRow] { rows.filter { !($0.isUrgent && !$0.isFilled) } }

    private var urgentSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("URGENT · PICKUP INSIDE 48 H")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(Brand.danger)
                Spacer(minLength: 0)
                Text("\(urgentRows.count) LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.danger)
            }
            VStack(spacing: 6) { ForEach(urgentRows) { urgentRow($0) } }
        }
    }

    private func urgentRow(_ row: AvailableJobRow) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().strokeBorder(Brand.danger.opacity(0.28), lineWidth: 1.2).frame(width: 44, height: 44)
                Circle().strokeBorder(Brand.danger.opacity(0.45), lineWidth: 1.2).frame(width: 30, height: 30)
                Circle().fill(Brand.danger.opacity(0.85)).frame(width: 15, height: 15)
                Circle().fill(.white).frame(width: 5, height: 5)
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.lane)
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(urgentMeta(row))
                    .font(EType.mono(.caption).weight(.bold)).foregroundStyle(Brand.danger)
                    .lineLimit(1).minimumScaleFactor(0.8)
                if let n = row.loadNumber {
                    Text(n).font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                }
            }
            Spacer(minLength: 0)
            applyButton(row, compact: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.45), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func urgentMeta(_ row: AvailableJobRow) -> String {
        var parts: [String] = []
        if let d = row.distance, d > 0 { parts.append("\(Int(d.rounded())) mi") }
        parts.append("\(row.seats) NEEDED")
        parts.append("\(row.open) OPEN")
        if let p = row.pickupDate, let rel = hoursOut(p) { parts.append(rel) }
        return parts.joined(separator: " · ")
    }

    // MARK: Rank control

    private var rankSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("RANK BY · \(normalRows.count) RANKED TENDER\(normalRows.count == 1 ? "" : "S")")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 4) {
                ForEach(MarketRankKey.allCases) { rankChip($0) }
            }
        }
    }

    @ViewBuilder
    private func rankChip(_ key: MarketRankKey) -> some View {
        let active = key == rankKey
        Button {
            guard key.isRankable else {
                toast = "Tenders carry no rate until you apply — nothing to rank on."
                return
            }
            withAnimation(.easeOut(duration: 0.15)) { rankKey = key }
        } label: {
            Text(active ? "\(key.rawValue) ↓" : key.chipLabel)
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(active ? AnyShapeStyle(Color.white)
                                        : AnyShapeStyle(key.isRankable ? palette.textPrimary : palette.textTertiary))
                .frame(maxWidth: .infinity, minHeight: 26)
                .background {
                    if active { Capsule().fill(LinearGradient.primary) }
                    else if key.isRankable { Capsule().fill(palette.bgCard) }
                    else {
                        Capsule().strokeBorder(palette.textTertiary.opacity(0.55),
                                               style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .overlay { if !active && key.isRankable { Capsule().strokeBorder(palette.borderFaint, lineWidth: 1) } }
        }
        .buttonStyle(.plain)
    }

    private var ranked: [AvailableJobRow] {
        switch rankKey {
        case .distance:
            return normalRows.sorted { ($0.distance ?? .greatestFiniteMagnitude) < ($1.distance ?? .greatestFiniteMagnitude) }
        case .weight:
            return normalRows.sorted { ($0.weight ?? 0) > ($1.weight ?? 0) }
        case .demand:
            return normalRows.sorted { demandScore($0) > demandScore($1) }
        case .rate:
            return normalRows
        }
    }

    private func demandScore(_ r: AvailableJobRow) -> Double {
        guard r.seats > 0 else { return 0 }
        return Double(r.open) / Double(r.seats)
    }

    // MARK: Ranked rows

    private var rankedList: some View {
        VStack(spacing: 6) {
            ForEach(Array(ranked.enumerated()), id: \.element.id) { idx, row in
                tenderRow(row, rank: idx + 1)
            }
        }
    }

    private func tenderRow(_ row: AvailableJobRow, rank: Int) -> some View {
        let top = rank == 1 && !row.isFilled
        let ink = row.isFilled ? palette.textTertiary : palette.textPrimary
        return HStack(alignment: .top, spacing: Space.s2) {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(format: "%02d", rank))
                    .font(.system(size: 18, weight: .heavy, design: .monospaced))
                    .foregroundStyle(top ? AnyShapeStyle(LinearGradient.diagonal)
                                         : AnyShapeStyle(palette.textTertiary.opacity(0.65)))
                Text("RANK")
                    .font(.system(size: 7, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            .frame(width: 30, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.lane)
                    .font(.system(size: 13.5, weight: .bold)).foregroundStyle(ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(rowMeta(row))
                    .font(EType.mono(.caption))
                    .foregroundStyle(row.isFilled ? palette.textTertiary : palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.75)
                metricBar("DIST", fraction: distFraction(row),
                          value: row.distance.map { "\(Int($0.rounded())) mi" } ?? "-",
                          tint: top ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(Brand.blue),
                          ink: row.isFilled ? palette.textTertiary : palette.textPrimary)
                metricBar("WEIGHT", fraction: weightFraction(row),
                          value: row.weight.map { weightLabel($0) } ?? "-",
                          tint: AnyShapeStyle(Brand.hazmat.opacity(row.isFilled ? 0.45 : 0.75)),
                          ink: row.isFilled ? palette.textTertiary : Brand.hazmat)
                metricBar("DEMAND", fraction: demandScore(row),
                          value: "\(row.open) of \(row.seats) open",
                          tint: AnyShapeStyle(row.isContested ? Brand.danger.opacity(0.7) : Brand.success.opacity(0.7)),
                          ink: row.isFilled ? palette.textTertiary : (row.isContested ? Brand.danger : Brand.success))
            }

            VStack(alignment: .trailing, spacing: 6) {
                statusChip(row)
                if let facet = facetLabel(row) { facetChip(facet) }
                applyButton(row, compact: true)
            }
            .frame(width: 88)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func rowMeta(_ row: AvailableJobRow) -> String {
        var parts: [String] = []
        if let n = row.loadNumber { parts.append(n) }
        if row.didApply { parts.append("applied") }
        else { parts.append("\(row.bidders) applicant\(row.bidders == 1 ? "" : "s")") }
        if let p = row.postedAt, let rel = relativeAge(p) { parts.append("posted \(rel)") }
        return parts.joined(separator: " · ")
    }

    /// Nearer is fuller. Scale is the widest lane on the board, so the bars
    /// stay comparable without inventing a constant.
    private func distFraction(_ row: AvailableJobRow) -> Double {
        let maxD = rows.compactMap(\.distance).max() ?? 0
        guard maxD > 0, let d = row.distance else { return 0 }
        return max(0.04, 1 - (d / maxD))
    }

    private func weightFraction(_ row: AvailableJobRow) -> Double {
        let maxW = rows.compactMap(\.weight).max() ?? 0
        guard maxW > 0, let w = row.weight else { return 0 }
        return max(0.04, w / maxW)
    }

    private func weightLabel(_ w: Double) -> String {
        w >= 1000 ? "\(Int((w / 1000).rounded()))k lb" : "\(Int(w.rounded())) lb"
    }

    private func metricBar(_ label: String, fraction: Double, value: String,
                           tint: AnyShapeStyle, ink: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 44, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.textTertiary.opacity(0.14))
                    Capsule().fill(tint).frame(width: max(0, min(1, fraction)) * geo.size.width)
                }
            }
            .frame(height: 5)
            Text(value)
                .font(EType.mono(.caption).weight(.bold))
                .foregroundStyle(ink)
                .frame(width: 74, alignment: .trailing)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func statusChip(_ row: AvailableJobRow) -> some View {
        let (label, tint): (String, Color) = {
            if row.didApply { return ("APPLIED", Brand.escort) }
            if row.isFilled { return ("FILLED", palette.textTertiary) }
            return ("\(row.open) OPEN", Brand.blue)
        }()
        return Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.4)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 20)
            .background(tint.opacity(0.14))
            .clipShape(Capsule())
    }

    /// Facets only from fields the server actually returns.
    private func facetLabel(_ row: AvailableJobRow) -> String? {
        if let h = row.hazmatClass, !h.isEmpty { return "HAZ \(h)" }
        if let c = row.cargoType, c == "oversized" { return "OVERSIZE" }
        if let c = row.commodityName, !c.isEmpty { return c.uppercased() }
        return nil
    }

    private func facetChip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.4)
            .foregroundStyle(Brand.hazmat)
            .frame(maxWidth: .infinity, minHeight: 20)
            .background(Brand.hazmat.opacity(0.14))
            .clipShape(Capsule())
            .lineLimit(1).minimumScaleFactor(0.7)
    }

    // MARK: Apply (ONLINE_ONLY)

    @ViewBuilder
    private func applyButton(_ row: AvailableJobRow, compact: Bool) -> some View {
        let busy = applying == row.id
        let disabled = row.didApply || row.isFilled || busy
        Button { Task { await apply(row) } } label: {
            Text(row.didApply ? "SENT" : (row.isFilled ? "CLOSED" : (busy ? "…" : "APPLY")))
                .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                .foregroundStyle(disabled ? palette.textTertiary : Color.white)
                .frame(maxWidth: .infinity, minHeight: compact ? 26 : 40)
                .background {
                    if disabled { Capsule().fill(palette.bgCardSoft) }
                    else { Capsule().fill(LinearGradient.primary) }
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: Market + sweep strips

    /// The escort's own completed-book average — never shipper linehaul.
    /// Zero means "you have no completed assignments yet", which is said
    /// rather than rendered as $0.
    private var avgPayLabel: String {
        guard let p = stats?.avgPay, p > 0 else { return "no completed book yet" }
        return "$\(p) avg"
    }

    private var marketStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MARKET · YOUR COMPLETED BOOK")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(avgPayLabel)
                        .font(EType.mono(.body).weight(.bold))
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer(minLength: Space.s3)
                if let n = stats?.newThisWeek, n > 0 {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("NEW THIS WEEK")
                            .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text("\(n)")
                            .font(EType.mono(.body).weight(.bold))
                            .foregroundStyle(palette.textPrimary)
                    }
                }
            }
            Text("✱ A tender carries no rate and no width on the wire: your rate is set when you apply, and the load record has no width column. Ranking on either would be a number nobody published.")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// Chain A1 SILENT, said in words rather than worn as a live badge.
    private var sweepStrip: some View {
        HStack(spacing: 8) {
            Circle().fill(AnyShapeStyle(Brand.warning)).frame(width: 7, height: 7)
            Text("Board sweeps on refresh — new tenders do not push to this phone yet. Pull down to re-sweep.")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Brand.warning)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.warning.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.warning.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
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
                    try? await Task.sleep(nanoseconds: 2_600_000_000)
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

    // MARK: Data

    private func refresh() async {
        if rows.isEmpty { phase = .loading }
        do {
            let fetched: [AvailableJobRow] = try await EusoTripAPI.shared.query(
                "escorts.getAvailableJobs",
                input: AvailableJobsInput(filter: nil, search: search.isEmpty ? nil : search))
            let s: MarketplaceStats? = try? await EusoTripAPI.shared.queryNoInput("escorts.getMarketplaceStats")
            await MainActor.run {
                rows = fetched
                stats = s
                sweptAt = Date()
                phase = fetched.isEmpty ? .empty : .loaded
            }
        } catch {
            await MainActor.run { if rows.isEmpty { phase = .failed } }
        }
    }

    /// ONLINE_ONLY. No outbox, no optimistic row flip — the board re-sweeps
    /// and the server's own `applied` flag is what turns the chip.
    private func apply(_ row: AvailableJobRow) async {
        guard applying == nil else { return }
        await MainActor.run { applying = row.id }
        defer { Task { await MainActor.run { applying = nil } } }
        do {
            let _: ApplyForJobResult = try await EusoTripAPI.shared.mutation(
                "escorts.applyForJob",
                input: ApplyForJobInput(jobId: row.id, position: nil, message: nil))
            await MainActor.run { toast = "Application sent — it shows up under My Jobs as pending." }
            await refresh()
        } catch {
            let msg = (error as? EusoTripAPIError)?.errorDescription
                ?? "Couldn't send that application. You have to be online to apply — there is no escort outbox yet."
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

    private func relativeAge(_ iso: String) -> String? {
        guard let d = parseISO(iso) else { return nil }
        let s = Date().timeIntervalSince(d)
        if s < 3600 { return "\(max(1, Int(s / 60)))m ago" }
        if s < 86_400 { return "\(Int(s / 3600))h ago" }
        return "\(Int(s / 86_400))d ago"
    }

    private func hoursOut(_ iso: String) -> String? {
        guard let d = parseISO(iso) else { return nil }
        let s = d.timeIntervalSince(Date())
        guard s > 0 else { return "PICKUP NOW" }
        if s < 3600 { return "PICKUP IN \(Int(s / 60))M" }
        return "PICKUP IN \(Int(s / 3600))H"
    }
}

// MARK: - Registered surface wrapper

struct EscortJobMarketplaceScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortJobMarketplace()
        } nav: {
            // Escort role tab bar TRIP · COMMS · PERMIT · ME (ES-01/02/08
            // precedent). The marketplace is a pushed route under TRIP until a
            // dedicated JOBS slot lands — EscortNavController.swift is a
            // single-writer file and is NOT edited by this drop.
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
// register without touching the network.
#Preview("ES-13 · Job Marketplace · Dark") {
    EscortJobMarketplaceScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("ES-13 · Job Marketplace · Light") {
    EscortJobMarketplaceScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
#endif
