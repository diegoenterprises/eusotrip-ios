//
//  ES18_EarningsWallet.swift
//  EusoTrip — Escort · ES-18 Earnings & Wallet (the role-level pay surface).
//
//  Built from the ES-18 design-authority twins
//  ("07 Escort/{Light,Dark}-SVG/ES-18 Earnings Wallet.svg").
//  ARCHETYPE MONEY — a period selector governs the whole screen, the money is
//  itemized BY POSITION, a wallet block separates spendable from pending, and both
//  the settlement states and the year in review ride as analytics content in place.
//
//  Anti-clone: deliberately NOT ES-07 Settlement Detail. ES-07 is ONE assignment
//  drawn as a leg timeline answering "what did this move pay". ES-18 has no timeline,
//  no legs, no single assignment — it is the aggregate answering "what am I earning,
//  in which seat, and how much can I spend today". ES-07's back chevron reads
//  "Earnings" and lands here; this screen's primary CTA pushes into ES-07.
//
//  WIRING (traced first-hand against server/routers/escorts.ts this firing):
//    REAL  escorts.getEarningsStats        :2661  week / month / year, avg, jobs
//    REAL  escorts.getEarningsHistory      :1963  period totals
//    REAL  escorts.listSettlements         :4723  per-row position + netPayout + status
//    REAL  escorts.getCompletedJobs        :2423  route + distance per move
//    REAL  payments.getBalance      payments.ts:114  wallet block
//    REAL  escorts.submitSettlementDispute :4694  disputes row + status flip
//
//  HONEST SEAMS — none invented, every one re-proven this firing:
//    · getEarningsHistory returns `breakdown: []` hardcoded (escorts.ts:1976) and
//      getEarnings returns `items: []` hardcoded (escorts.ts:2657): the server ships
//      NO breakdown, so the position itemization here is a client-side fold of
//      listSettlements rows and the screen labels it as computed, not served.
//    · getEarningsStats returns hoursWorked / avgHourlyRate as literal 0
//      (escorts.ts:2685) — no hourly figure is drawn anywhere.
//    · escortAssignments.position ships only lead | chase | both
//      (drizzle/schema.ts:3810). HIGH-POLE is not a column value — it is a profile
//      capability whose money rides positionPremiumPerMile — and STEER has no column
//      value at all. This port folds ONLY the values the server actually returns and
//      prints the column truth under the breakdown. It never fabricates a slice.
//    · No monthly-series and no corridor-rollup procedure exists (GAP-086): BEST
//      MONTH and TOP CORRIDOR render as em-dashes with the reason beside them.
//    · createEscortSettlement credits wallets.availableBalance (escorts.ts:4688) but
//      no escort-facing read of that column exists, so the balance is the
//      payments-ledger view and the card says so.
//    · There is NO cash-out, withdraw or transfer procedure for the escort role —
//      no such control is drawn.
//
//  CHAIN
//    F1 ONE-SIDED — escorts.createEscortSettlement EXISTS (escorts.ts:4654, atomic
//       CAS pending→paid then the wallet credit at :4688) and has ZERO callers
//       anywhere in the tree. Nothing an escort can touch moves a settlement to paid.
//       Missing half: the system/dispatcher trigger. This screen renders settlement
//       STATES honestly and draws no pay, release or cash-out affordance at all.
//    F2 ONE-SIDED — submitSettlementDispute writes a disputes row whose
//       counterpartyUserId falls back to the caller's own id when the assignment has
//       no carrierUserId and no driverUserId (escorts.ts:4700), and emits no
//       notification and no WS fan-out, so a filed dispute can reach no counterparty.
//       Missing half: a resolved counterparty + a notification path. The CTA stays
//       live because the record is real and durable; the line under it says exactly
//       how far it travels, and the success copy never claims anyone was told.
//
//  OFFLINE (§W) — ALL mutations ONLINE_ONLY (escort outbox not yet ported — PLANNED
//  per Encyclopedia v2). Period aggregates READ_CACHED(10m) via EscortOfflineCache
//  with a visible staleness line. THE WALLET BLOCK IS NEVER CACHED: a cached balance
//  is a lie about money, so offline it renders its own unavailable state instead of a
//  stale number wearing a live face. Never a fake queue badge.
//
//  RBAC — escort-gated; pricing firewall holds (city/state only, never loads.rate,
//  never carrier margin, never shipper identity).
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire contracts (mirror server/routers/escorts.ts)

/// `escorts.getEarningsStats` (escorts.ts:2661). hoursWorked / avgHourlyRate are
/// server literals of 0 — modelled for fidelity, never painted.
private struct ES18Stats: Codable, Hashable {
    let thisWeek: Double?
    let thisMonth: Double?
    let thisYear: Double?
    let avgPerJob: Double?
    let jobsCompleted: Int?
    let hoursWorked: Double?
    let avgHourlyRate: Double?
}
private struct ES18PeriodInput: Encodable { let period: String }

/// `escorts.getEarningsHistory` (escorts.ts:1963). `breakdown` is always `[]` on the
/// wire; kept so the decoder matches the literal, never read for content.
private struct ES18History: Codable, Hashable {
    let period: String?
    let totalEarnings: Double?
    let jobCount: Int?
    let avgPerJob: Double?
}

/// `escorts.listSettlements` row (escorts.ts:4723).
private struct ES18Settlement: Codable, Identifiable, Hashable {
    let assignmentId: Int
    let settlementId: String?
    let settlementStatus: String?
    let netPayout: String?
    let settledAt: String?
    let loadId: Int?
    let position: String?
    var id: Int { assignmentId }
    var payout: Double { Double(netPayout ?? "") ?? 0 }
}
private struct ES18SettlementsInput: Encodable { var status: String? = nil; let limit: Int }

/// `escorts.getCompletedJobs` row (escorts.ts:2423) — supplies distance per move.
private struct ES18CompletedJob: Codable, Identifiable, Hashable {
    let id: String
    let loadNumber: String?
    let earnings: Double?
    let route: String?
    let distance: Double?
    let completedAt: String?
}
private struct ES18CompletedInput: Encodable { let limit: Int; let period: String }

/// `payments.getBalance` (payments.ts:114). Never cached.
private struct ES18Balance: Codable, Hashable { let balance: String; let currency: String }
private struct ES18EmptyInput: Encodable {}

/// `escorts.submitSettlementDispute` (escorts.ts:4694).
private struct ES18DisputeInput: Encodable {
    let assignmentId: Int
    let reason: String
    let notes: String
}
private struct ES18DisputeResult: Codable { let success: Bool? }

/// The disk snapshot (READ_CACHED 10m). The wallet balance is deliberately ABSENT
/// from this type — money that cannot be verified is not painted from disk.
private struct ES18Snapshot: Codable {
    var stats: ES18Stats
    var history: ES18History?
    var settlements: [ES18Settlement]
    var completed: [ES18CompletedJob]
}

/// DA badge vocabulary. `inColumn` records whether the value can actually arrive on
/// escortAssignments.position today (schema.ts:3810 = lead | chase | both).
private enum ES18Position: String, CaseIterable, Identifiable {
    case lead, chase, both, highPole, steer
    var id: String { rawValue }
    var label: String {
        switch self {
        case .lead:     return "LEAD"
        case .chase:    return "CHASE"
        case .both:     return "LEAD + CHASE"
        case .highPole: return "HIGH-POLE"
        case .steer:    return "STEER"
        }
    }
    var tint: Color {
        switch self {
        case .lead:     return Brand.info          // blue
        case .chase:    return Brand.escort        // purple
        case .both:     return Brand.blue
        case .steer:    return Brand.warning       // amber
        case .highPole: return Brand.hazmat        // orange
        }
    }
    var inColumn: Bool {
        switch self {
        case .lead, .chase, .both: return true
        case .highPole, .steer:    return false
        }
    }
    static func from(_ raw: String?) -> ES18Position? {
        guard let raw = raw?.lowercased() else { return nil }
        return ES18Position(rawValue: raw)
    }
}

/// A computed projection, not a wire type — the server ships no breakdown.
private struct ES18Slice: Identifiable, Hashable {
    let position: ES18Position
    let moves: Int
    let miles: Int
    let amount: Double
    let share: Double
    var id: String { position.rawValue }
}

private enum ES18Period: String, CaseIterable, Identifiable {
    case week, month, quarter, year
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

// MARK: - Screen

struct EscortEarningsWallet: View {
    @Environment(\.palette) private var palette

    @State private var period: ES18Period = .month
    @State private var stats: ES18Stats? = nil
    @State private var history: ES18History? = nil
    @State private var settlements: [ES18Settlement] = []
    @State private var completed: [ES18CompletedJob] = []
    @State private var balance: ES18Balance? = nil
    @State private var balanceUnavailable = false
    @State private var stalenessLine: String? = nil
    @State private var loading = true
    @State private var errorMessage: String? = nil

    // Dispute (the one mutation this surface can honestly offer) — ONLINE_ONLY.
    @State private var showDispute = false
    @State private var disputeTarget: ES18Settlement? = nil
    @State private var disputeReason = "incorrect_miles"
    @State private var disputeNotes = ""
    @State private var disputing = false
    @State private var disputeNotice: String? = nil

    private static let cacheKey = "es18-earnings-wallet"
    private static let cacheTTL: TimeInterval = 10 * 60   // READ_CACHED(10m)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrowRow
                headline
                periodSelector
                walletBlock
                positionBreakdown
                settlementStates
                yearInReview
                actionRow
                Text("DISPUTE FILES TO THE LEDGER · NO COUNTERPARTY IS NOTIFIED YET")
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load(force: true) }
        .sheet(isPresented: $showDispute) { disputeSheet }
    }

    // MARK: Header

    private var eyebrowRow: some View {
        HStack {
            Text("✦ ESCORT · EARNINGS & WALLET")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: Space.s2)
            Text("FMCSA 3 291 447")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PERIOD · \(period.label) TO DATE")
                    .font(EType.mono(.micro)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: Space.s2)
                if let stale = stalenessLine {
                    Label(stale, systemImage: "clock.arrow.circlepath")
                        .font(EType.mono(.micro)).foregroundStyle(Brand.warning)
                } else if !loading {
                    HStack(spacing: 5) {
                        Circle().fill(Brand.success).frame(width: 7, height: 7)
                        Text("LIVE").font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                    }
                }
            }
            Text(currency(periodGross))
                .font(.system(size: 32, weight: .heavy, design: .monospaced)).tracking(-0.8)
                .foregroundStyle(LinearGradient.diagonal)
            Text(subheadline)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            if let err = errorMessage {
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            }
        }
    }

    private var subheadline: String {
        let moves = periodMoves
        let miles = periodMiles
        let avg = moves > 0 ? periodGross / Double(moves) : 0
        let milesPart = miles > 0 ? " · \(miles.formatted()) escorted mi" : ""
        return "\(moves) move\(moves == 1 ? "" : "s")\(milesPart) · avg \(currency(avg)) / move"
    }

    // MARK: Period selector — governs the whole screen

    private var periodSelector: some View {
        HStack(spacing: 4) {
            ForEach(ES18Period.allCases) { item in
                let active = item == period
                Button {
                    guard !active else { return }
                    period = item
                    Task { await load(force: true) }
                } label: {
                    Text(item.label)
                        .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(active ? Color.white : palette.textSecondary)
                        .frame(maxWidth: .infinity).frame(height: 30)
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .fill(LinearGradient.primary)
                            } else {
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .fill(palette.bgCard)
                                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                        .strokeBorder(palette.borderFaint))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Wallet — spendable vs not. NEVER cached.

    private var walletBlock: some View {
        LifecycleCard(accentGradient: true) {
            HStack {
                sectionEyebrow("WALLET")
                Spacer(minLength: 0)
                Text("USD · ONLINE ONLY")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .top, spacing: Space.s4) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("AVAILABLE")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    if balanceUnavailable {
                        // Offline: the honesty law forbids painting a cached balance.
                        Text("—")
                            .font(.system(size: 24, weight: .heavy, design: .monospaced))
                            .foregroundStyle(palette.textTertiary)
                        Text("BALANCE NEEDS A LIVE READ")
                            .font(EType.mono(.micro)).foregroundStyle(Brand.warning)
                    } else {
                        Text(currency(Double(balance?.balance ?? "") ?? 0))
                            .font(.system(size: 24, weight: .heavy, design: .monospaced))
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle().fill(palette.borderFaint).frame(width: 1, height: 42)

                VStack(alignment: .leading, spacing: 5) {
                    Text("PENDING")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text(currency(pendingTotal))
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(Brand.warning)
                    Text("\(pendingRows.count) SETTLEMENT\(pendingRows.count == 1 ? "" : "S")")
                        .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().overlay(palette.borderFaint)
            if let credit = lastPaidRow {
                Text("LAST CREDIT · \(credit.settlementId ?? "REF NOT ISSUED") · \(currency(credit.payout))")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
            }
            Text("PAYMENTS-LEDGER VIEW · NO ESCORT READ OF THE WALLET COLUMN EXISTS YET")
                .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Position itemization — computed, and labelled as computed

    private var positionBreakdown: some View {
        LifecycleCard {
            HStack {
                sectionEyebrow("EARNINGS BY POSITION")
                Spacer(minLength: 0)
                Text("FOLDED CLIENT-SIDE")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            if slices.isEmpty {
                Text("No settled or pending moves in this period.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            } else {
                VStack(spacing: Space.s3) {
                    ForEach(slices) { slice in positionRow(slice) }
                }
            }
            Divider().overlay(palette.borderFaint)
            // The column truth, on glass — no invented seats.
            Text("COLUMN SHIPS LEAD · CHASE · BOTH — HIGH-POLE IS A PROFILE CAPABILITY, STEER HAS NO COLUMN VALUE")
                .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func positionRow(_ s: ES18Slice) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(s.position.label)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(.white)
                    .frame(width: 78, height: 18)
                    .background(Capsule().fill(s.position.tint))
                Text(s.miles > 0
                     ? "\(s.moves) MOVE\(s.moves == 1 ? "" : "S") · \(s.miles) MI"
                     : "\(s.moves) MOVE\(s.moves == 1 ? "" : "S")")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                Spacer(minLength: 6)
                Text(currency(s.amount))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
            }
            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.bgCardSoft).frame(height: 4)
                        Capsule().fill(s.position.tint)
                            .frame(width: max(2, geo.size.width * s.share), height: 4)
                    }
                }
                .frame(height: 4)
                Text(String(format: "%.1f%%", s.share * 100))
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                    .frame(width: 46, alignment: .trailing)
            }
        }
    }

    // MARK: Settlement states — F1 named on glass

    private var settlementStates: some View {
        LifecycleCard {
            HStack {
                sectionEyebrow("SETTLEMENT STATES")
                Spacer(minLength: 0)
                Text("\(settlements.count) THIS PERIOD")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            if settlements.isEmpty {
                Text("No settlements on file for this period.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(settlements.prefix(6)) { row in
                        Button {
                            disputeTarget = row
                            showDispute = true
                        } label: {
                            HStack(spacing: 10) {
                                settlementPill(row.settlementStatus ?? "pending")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.settlementId ?? "Not issued")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(palette.textPrimary)
                                        .lineLimit(1)
                                    Text((ES18Position.from(row.position)?.label ?? "POSITION —"))
                                        .font(EType.mono(.micro))
                                        .foregroundStyle(palette.textTertiary)
                                }
                                Spacer(minLength: 6)
                                Text(currency(row.payout))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(row.settlementStatus == "paid"
                                                     ? Brand.success : palette.textSecondary)
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Divider().overlay(palette.borderFaint)
            // CHAIN F1, on glass. There is no pay affordance anywhere on this screen.
            Text("PENDING → PAID IS SYSTEM-SIDE ONLY · NO ESCORT-CALLABLE PAY ACTION EXISTS")
                .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func settlementPill(_ status: String) -> some View {
        let tint: Color = {
            switch status.lowercased() {
            case "paid":       return Brand.success
            case "processing": return Brand.info
            case "disputed":   return Brand.danger
            case "cancelled":  return Brand.warning
            default:           return palette.textTertiary
            }
        }()
        return Text(status.uppercased())
            .font(.system(size: 7.5, weight: .heavy)).tracking(0.4).foregroundStyle(tint)
            .frame(width: 66, height: 16)
            .background(Capsule().fill(tint.opacity(0.18)))
    }

    // MARK: Year in review — analytics content, not a screen

    private var yearInReview: some View {
        LifecycleCard {
            HStack {
                sectionEyebrow("YEAR IN REVIEW")
                Spacer(minLength: 0)
                Text("TAB 3 · IN PLACE")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .top, spacing: 0) {
                yearStat(currency(stats?.thisYear ?? 0), "YTD GROSS", gradient: true)
                Rectangle().fill(palette.borderFaint).frame(width: 1, height: 32)
                yearStat("\(stats?.jobsCompleted ?? 0)", "MOVES ESCORTED")
                Rectangle().fill(palette.borderFaint).frame(width: 1, height: 32)
                yearStat(currency(stats?.avgPerJob ?? 0), "AVG / MOVE")
            }
            Divider().overlay(palette.borderFaint)
            Text("BEST MONTH — · TOP CORRIDOR — · HOURS — · MONTHLY TOTALS NOT TRACKED YET")
                .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func yearStat(_ value: String, _ label: String, gradient: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if gradient { Text(value).foregroundStyle(LinearGradient.primary) }
                else { Text(value).foregroundStyle(palette.textPrimary) }
            }
            .font(.system(size: 16, weight: .heavy, design: .monospaced))
            .lineLimit(1).minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    // MARK: Actions

    private var actionRow: some View {
        HStack(spacing: Space.s2) {
            Button {
                if let first = settlements.first {
                    NotificationCenter.default.post(
                        name: .eusoEscortNavSwap, object: nil,
                        userInfo: ["screenId": "605", "assignmentId": String(first.assignmentId)])
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold))
                    Text("OPEN SETTLEMENT").font(.system(size: 12.5, weight: .heavy)).tracking(0.4)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(settlements.isEmpty)

            Button {
                disputeTarget = settlements.first
                showDispute = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 12, weight: .bold))
                    Text("DISPUTE A LINE").font(.system(size: 12, weight: .heavy)).tracking(0.3)
                }
                .foregroundStyle(Brand.danger)
                .frame(width: 150).frame(height: 44)
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Brand.danger.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .disabled(settlements.isEmpty)
        }
    }

    // MARK: Dispute sheet — the one honest mutation. ONLINE_ONLY.

    private var disputeSheet: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Dispute a settlement line")
                .font(EType.h2).foregroundStyle(palette.textPrimary)
            if let t = disputeTarget {
                Text("\(t.settlementId ?? "Reference not issued") · \(currency(t.payout))")
                    .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
            }
            Text("REASON")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            // Exactly the server enum (escorts.ts:4696) — nothing else is accepted.
            Picker("Reason", selection: $disputeReason) {
                Text("Incorrect miles").tag("incorrect_miles")
                Text("Missing detention").tag("missing_detention")
                Text("Missing overnight").tag("missing_overnight")
                Text("Wrong position rate").tag("wrong_position_rate")
                Text("Other").tag("other")
            }
            .pickerStyle(.menu)
            TextField("What's wrong with this settlement?", text: $disputeNotes, axis: .vertical)
                .lineLimit(3, reservesSpace: true)
                .padding(Space.s3)
                .background(palette.bgCardSoft)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
            if let notice = disputeNotice {
                Text(notice).font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CTAButton(title: disputing ? "Filing…" : "File dispute",
                      action: { Task { await submitDispute() } })
                .disabled(disputing || disputeTarget == nil || disputeNotes.isEmpty)
            Text("Money mutations are online-only — there is no escort outbox to queue this.")
                .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            Spacer()
        }
        .padding(20)
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
        .background(palette.bgPage)
    }

    private func submitDispute() async {
        guard let target = disputeTarget else { return }
        disputing = true
        defer { disputing = false }
        do {
            let _: ES18DisputeResult = try await EusoTripAPI.shared.mutation(
                "escorts.submitSettlementDispute",
                input: ES18DisputeInput(assignmentId: target.assignmentId,
                                        reason: disputeReason,
                                        notes: disputeNotes))
            // CHAIN F2: the record is real; nobody is notified. Say exactly that.
            disputeNotice = "Filed. The settlement is now marked disputed. No counterparty notification exists yet — follow up with dispatch."
            disputeNotes = ""
            await load(force: true)
        } catch {
            disputeNotice = (error as? EusoTripAPIError)?.errorDescription
                ?? "Couldn't file the dispute. Money actions need a live connection."
        }
    }

    // MARK: Derived figures

    private var periodGross: Double {
        if let t = history?.totalEarnings, t > 0 { return t }
        switch period {
        case .week:  return stats?.thisWeek ?? 0
        case .month: return stats?.thisMonth ?? 0
        default:     return stats?.thisYear ?? 0
        }
    }

    private var periodMoves: Int { history?.jobCount ?? settlements.count }

    private var periodMiles: Int {
        Int(completed.compactMap(\.distance).reduce(0, +).rounded())
    }

    private var pendingRows: [ES18Settlement] {
        settlements.filter { ($0.settlementStatus ?? "pending") != "paid" }
    }
    private var pendingTotal: Double { pendingRows.map(\.payout).reduce(0, +) }
    private var lastPaidRow: ES18Settlement? {
        settlements.first { $0.settlementStatus == "paid" }
    }

    /// The client-side fold. Only positions the server actually returned appear —
    /// a seat the column cannot express is never fabricated into a slice.
    private var slices: [ES18Slice] {
        let milesByAssignment: [String: Double] = Dictionary(
            completed.map { ($0.id, $0.distance ?? 0) }, uniquingKeysWith: { a, _ in a })
        var buckets: [ES18Position: (moves: Int, miles: Double, amount: Double)] = [:]
        for row in settlements {
            guard let pos = ES18Position.from(row.position) else { continue }
            var b = buckets[pos] ?? (0, 0, 0)
            b.moves += 1
            b.miles += milesByAssignment[String(row.assignmentId)] ?? 0
            b.amount += row.payout
            buckets[pos] = b
        }
        let total = buckets.values.map(\.amount).reduce(0, +)
        return buckets
            .map { ES18Slice(position: $0.key, moves: $0.value.moves,
                             miles: Int($0.value.miles.rounded()), amount: $0.value.amount,
                             share: total > 0 ? $0.value.amount / total : 0) }
            .sorted { $0.amount > $1.amount }
    }

    // MARK: Data

    private func load(force: Bool = false) async {
        loading = true
        defer { loading = false }

        // READ_CACHED(10m) for the period aggregates only.
        if !force,
           let cached = EscortOfflineCache.load(ES18Snapshot.self,
                                                key: Self.cacheKey, ttl: Self.cacheTTL) {
            stats = cached.value.stats
            history = cached.value.history
            settlements = cached.value.settlements
            completed = cached.value.completed
            stalenessLine = EscortOfflineCache.stalenessLine(age: cached.age)
        }

        async let statsCall: ES18Stats? = try? await EusoTripAPI.shared.query(
            "escorts.getEarningsStats", input: ES18PeriodInput(period: period.rawValue))
        async let historyCall: ES18History? = try? await EusoTripAPI.shared.query(
            "escorts.getEarningsHistory", input: ES18PeriodInput(period: period.rawValue))
        async let settleCall: [ES18Settlement]? = try? await EusoTripAPI.shared.query(
            "escorts.listSettlements", input: ES18SettlementsInput(limit: 25))
        async let completedCall: [ES18CompletedJob]? = try? await EusoTripAPI.shared.query(
            "escorts.getCompletedJobs", input: ES18CompletedInput(limit: 25, period: period.rawValue))
        // The wallet read is live-or-nothing. It is never written to the snapshot.
        async let balanceCall: ES18Balance? = try? await EusoTripAPI.shared.query(
            "payments.getBalance", input: ES18EmptyInput())

        let (s, h, st, cj, bal) = await (statsCall, historyCall, settleCall, completedCall, balanceCall)

        balance = bal
        balanceUnavailable = (bal == nil)

        guard let s else {
            if stats == nil {
                errorMessage = "Couldn't reach the pay record. Pull to retry."
            }
            return
        }

        stats = s
        history = h
        settlements = st ?? []
        completed = cj ?? []
        stalenessLine = nil
        errorMessage = nil

        EscortOfflineCache.store(
            ES18Snapshot(stats: s, history: h, settlements: settlements, completed: completed),
            key: Self.cacheKey)
    }

    // MARK: Primitives

    private func sectionEyebrow(_ title: String) -> some View {
        Text(title).font(.system(size: 9, weight: .heavy)).tracking(1.0)
            .foregroundStyle(palette.textTertiary)
    }

    private func currency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "$0.00"
    }
}

// MARK: - Registered surface wrapper

struct EscortEarningsWalletScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortEarningsWallet()
        } nav: {
            BottomNav(
                leading: [
                    NavSlot(label: "Home",        systemImage: "house",                  isCurrent: false),
                    NavSlot(label: "Assignments", systemImage: "shield.lefthalf.filled", isCurrent: false),
                ],
                trailing: [
                    NavSlot(label: "Corridor", systemImage: "map",    isCurrent: false),
                    NavSlot(label: "Me",       systemImage: "person", isCurrent: true),
                ],
                orbState: .idle
            )
        }
    }
}

#Preview("ES-18 · Earnings & Wallet · Dark") {
    EscortEarningsWalletScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("ES-18 · Earnings & Wallet · Light") {
    EscortEarningsWalletScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
