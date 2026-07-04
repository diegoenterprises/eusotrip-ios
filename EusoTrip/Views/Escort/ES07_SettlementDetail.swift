//
//  ES07_SettlementDetail.swift
//  EusoTrip — Escort · Settlement Detail (brick 605 · ES-07).
//
//  Bespoke MONEY-LEDGER archetype, built verbatim from the ES-07
//  design-authority SVG pair
//  ("07 Escort/{Dark,Light}-SVG/ES-07 Settlement Detail.svg") and
//  the ES7_settlement.md spec. Per the design-authority ruling
//  (DA_FAIL H/I/M), the route-leg TIMELINE is the money surface —
//  every dollar hangs off a leg node, not a settlement-table hero.
//  The green pay hero, position badge, 1099 YTD strip, and payout
//  block complete the contractor pay record.
//
//  Wiring truth (code-traced this firing):
//    REAL  escorts.getJobDetails → the assignment + load pay
//          context: load number, lane, position, rate + rate type,
//          route distance, pickup/delivery dates, status. The rate
//          column is the same figure the earnings totals sum for
//          completed assignments — it IS the gross on record.
//    REAL  escorts.getEarningsStats → the 1099 strip: year-to-date
//          gross, jobs completed, average per job.
//    ABSENT (named gaps — see backendGaps in the firing report):
//          escorts.getSettlementDetail, createEscortSettlement,
//          submitSettlementDispute, listSettlements + the additive
//          settlement columns (position premium, deadhead,
//          detention, overnight, platform fee, net payout,
//          settlement status/reference, leg breakdown). Every slot
//          that depends on them renders an em-dash + an honest
//          "not on the pay record" state; the statement-export and
//          dispute affordances resolve to honest notices — never a
//          fake export, never a fake dispute.
//
//  Pricing firewall: this surface shows the escort's own pay only —
//  no shipper rate, no carrier margin, no shipper identity.
//
//  RBAC: registered role .escort only; the pay procs resolve the
//  caller's own assignments server-side.
//
//  Pixel doctrine: palette tokens only, gradient-only accent,
//  tokenized spacing/radius/type, Dark + Light previews.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire projections (screen-local, private)

private struct EscortJobDetail: Decodable {
    let id: String?
    let loadNumber: String?
    let status: String?
    let cargoType: String?
    let hazmatClass: String?
    let origin: String?
    let destination: String?
    let rate: Double?
    let distance: Double?
    let pickupDate: String?
    let deliveryDate: String?
    let weight: Double?
    let position: String?
    let rateType: String?
}

private struct JobIdInput: Encodable { let jobId: String }
private struct AssignmentIdInput: Encodable { let assignmentId: Int }

/// Real settlement itemization off `escorts.getSettlementDetail`.
private struct SettlementDetailData: Decodable {
    struct LineItems: Decodable {
        let base: Double?; let positionPremium: Double?; let deadhead: Double?
        let detention: Double?; let overnight: Double?; let fuel: Double?
        let survey: Double?; let cancellation: Double?; let adjustments: Double?
    }
    let settlementId: String?
    let settlementStatus: String?
    let origin: String?
    let destination: String?
    let lineItems: LineItems?
    let grossEarned: Double?
    let platformFeePercent: Double?
    let platformFeeAmount: Double?
    let netPayout: Double?
    let ytdGross: Double?
}

private struct SettlementDisputeInput: Encodable {
    let assignmentId: Int
    let reason: String
    let notes: String
}
private struct SettlementDisputeResult: Decodable { let success: Bool? }

private struct EscortEarningsStats: Decodable {
    let thisWeek: Double?
    let thisMonth: Double?
    let thisYear: Double?
    let avgPerJob: Double?
    let jobsCompleted: Int?
}

// MARK: - Screen body

struct EscortSettlementDetail: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    /// The escort assignment whose pay record this surface renders.
    /// "0" (the registry default) resolves to the honest pick-a-job
    /// empty state.
    let assignmentId: String

    private enum Phase {
        case loading
        case loaded
        case missing
        case failed
    }

    @State private var phase: Phase = .loading
    @State private var job: EscortJobDetail? = nil
    @State private var stats: EscortEarningsStats? = nil
    @State private var settlement: SettlementDetailData? = nil
    @State private var showDisputeSheet: Bool = false
    @State private var disputeReason: String = "incorrect_miles"
    @State private var disputeNotes: String = ""

    /// Honest notice raised by the export / dispute affordances —
    /// there is no settlement record to export or dispute yet.
    @State private var actionNotice: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrowRow
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await refreshAll() }
        .refreshable { await refreshAll() }
        .sheet(isPresented: $showDisputeSheet) { disputeSheet }
    }

    private var disputeSheet: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Dispute a settlement line")
                .font(EType.h2).foregroundStyle(palette.textPrimary)
            Text("REASON")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
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
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            CTAButton(title: "File dispute", action: { Task { await submitDispute() } })
            Spacer()
        }
        .padding(20)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .background(palette.bgPage)
    }

    // MARK: - Header

    private var eyebrowRow: some View {
        HStack {
            Text("✦ ESCORT · SETTLEMENT DETAIL")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: Space.s2)
            Text(jobRefCaps)
                .font(EType.mono(.micro)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
    }

    private var jobRefCaps: String {
        if let id = job?.id ?? (assignmentId == "0" ? nil : assignmentId) {
            return "JOB · #\(id)"
        }
        return "PAY RECORD"
    }

    @ViewBuilder
    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(subjectCaps)
                .font(EType.mono(.micro)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(laneTitle)
                .font(.system(size: 26, weight: .heavy))
                .tracking(-0.4)
                .foregroundStyle(LinearGradient.diagonal)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
            Text(contextLine)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            hairline
        }
    }

    private var subjectCaps: String {
        let load = job?.loadNumber ?? "-"
        let pos = positionLabel.uppercased()
        return pos.isEmpty ? load : "\(load) · \(pos) ESCORT"
    }

    private var laneTitle: String {
        let o = job?.origin ?? ""
        let d = job?.destination ?? ""
        if o.isEmpty && d.isEmpty { return "Pay record" }
        return "\(o) → \(d)"
    }

    private var contextLine: String {
        var parts: [String] = []
        let status = (job?.status ?? "").lowercased()
        if status == "completed" {
            parts.append("Completed \(humanDate(job?.deliveryDate))")
        } else if !status.isEmpty {
            parts.append(status.replacingOccurrences(of: "_", with: " ").capitalized)
        }
        if let mi = job?.distance, mi > 0 {
            parts.append("\(Int(mi.rounded())) mi route")
        }
        return parts.isEmpty ? "-" : parts.joined(separator: " · ")
    }

    private var hairline: some View {
        Rectangle()
            .fill(palette.iridescentHairline)
            .frame(height: 1)
            .padding(.horizontal, -14)
    }

    // MARK: - Content state machine

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            loadingCard
        case .missing:
            EusoEmptyState(
                systemImage: "banknote",
                title: "No pay record to show",
                subtitle: "Open a completed job from your earnings list and its full pay record renders here — leg by leg."
            )
        case .failed:
            errorCard
        case .loaded:
            headerBlock
            payHero
            badgeRow
            legTimelineCard
            taxStripCard
            payoutCard
            if let notice = actionNotice { noticeCard(notice) }
            ctaRow
        }
    }

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            sectionHeader("LOADING", icon: "arrow.clockwise")
            Text("Pulling the pay record for this job…")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var errorCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.danger)
                Text("COULDN'T LOAD THE PAY RECORD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.danger)
            }
            Text("EusoTrip couldn't reach this job's pay record. Check your connection and retry — your earnings totals still live on the home dashboard.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: { Task { await refreshAll() } }) {
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
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Pay hero (gross on record)

    private var payHero: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(AnyShapeStyle(Brand.success))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("GROSS PAY · ON RECORD")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(Brand.success)
                    Spacer(minLength: 0)
                    statusPill
                }
                Text(dollars(job?.rate))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Brand.success)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack(spacing: Space.s3) {
                    heroSubStat(label: "Platform fee", value: "-")
                    heroSubStat(label: "Net to wallet", value: "-")
                }
                Text("A settlement record isn't on file for this job. Gross pay reads live from the assignment rate — the same figure your earnings totals count. The fee and net-to-wallet lines post with the settlement record.")
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.s3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.tintSuccess)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.success.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func heroSubStat(label: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        let raw = (job?.status ?? "").lowercased()
        if !raw.isEmpty {
            let done = raw == "completed"
            Text(raw.replacingOccurrences(of: "_", with: " ").uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(done ? .white : palette.textSecondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(done ? AnyShapeStyle(Brand.success) : AnyShapeStyle(palette.tintNeutral))
                .clipShape(Capsule())
        }
    }

    // MARK: - Position + rate badges

    private var badgeRow: some View {
        HStack(spacing: Space.s2) {
            Text("\(positionLabel.uppercased()) ESCORT")
                .font(.system(size: 10, weight: .heavy)).tracking(0.8)
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(positionColor)
                .clipShape(Capsule())
            Spacer(minLength: 0)
            Text("Rate · \(rateLabel)")
                .font(EType.mono(.caption)).tracking(0.4)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var positionLabel: String {
        switch (job?.position ?? "").lowercased() {
        case "lead":  return "Lead"
        case "chase": return "Chase"
        case "both":  return "Lead + Chase"
        default:      return (job?.position ?? "").capitalized
        }
    }

    private var positionColor: Color {
        switch (job?.position ?? "").lowercased() {
        case "lead":  return Brand.blue
        case "chase": return Brand.warning
        case "both":  return Brand.escort
        default:      return Brand.blue
        }
    }

    private var rateLabel: String {
        guard let rate = job?.rate, rate > 0 else { return "-" }
        switch (job?.rateType ?? "").lowercased() {
        case "per_mile": return "\(dollars(rate))/mi basis"
        case "per_hour": return "\(dollars(rate))/hr basis"
        default:         return "\(dollars(rate)) flat"
        }
    }

    // MARK: - Route legs · the money surface (DA_FAIL H/I/M)

    private var legTimelineCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("ROUTE LEGS · PAY BY LEG", icon: "point.topleft.down.curvedto.point.bottomright.up")
            VStack(alignment: .leading, spacing: 0) {
                legRow(
                    dot: AnyShapeStyle(Brand.blue),
                    title: "Pickup · \(job?.origin ?? "-")",
                    sub: humanDate(job?.pickupDate),
                    money: nil, moneyNote: nil, dimmed: false
                )
                legConnector
                legRow(
                    dot: AnyShapeStyle(LinearGradient.diagonal),
                    title: "\(positionLabel) escort · \(milesLabel(job?.distance))",
                    sub: "pay basis · \(rateBasisLabel)",
                    money: dollars(job?.rate), moneyNote: "on record", dimmed: false
                )
                legConnector
                legRow(
                    dot: AnyShapeStyle(Brand.warning),
                    title: "Detention",
                    sub: "not on the pay record",
                    money: "-", moneyNote: nil, dimmed: true
                )
                legConnector
                legRow(
                    dot: AnyShapeStyle(Brand.escort),
                    title: "Overnight layover",
                    sub: "not on the pay record",
                    money: "-", moneyNote: nil, dimmed: true
                )
                legConnector
                legRow(
                    dot: AnyShapeStyle(Brand.success),
                    title: "Delivery · \(job?.destination ?? "-")",
                    sub: humanDate(job?.deliveryDate),
                    money: nil, moneyNote: nil, dimmed: false
                )
            }
            Divider().overlay(palette.borderFaint)
            totalsRows
            Text("Deadhead, detention, overnight, fuel, and adjustment lines itemize when the settlement record posts for this job. Nothing here is estimated.")
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var rateBasisLabel: String {
        switch (job?.rateType ?? "").lowercased() {
        case "per_mile": return "per mile"
        case "per_hour": return "per hour"
        case "flat":     return "flat rate"
        default:         return "-"
        }
    }

    private func legRow(dot: AnyShapeStyle, title: String, sub: String,
                        money: String?, moneyNote: String?, dimmed: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Circle()
                .fill(dot)
                .frame(width: 10, height: 10)
                .padding(.top, 4)
                .opacity(dimmed ? 0.45 : 1.0)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(dimmed ? palette.textTertiary : palette.textPrimary)
                    .lineLimit(2)
                Text(sub)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: Space.s2)
            if let money {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(money)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(dimmed ? palette.textTertiary : palette.textPrimary)
                        .monospacedDigit()
                    if let note = moneyNote {
                        Text(note)
                            .font(EType.mono(.micro)).tracking(0.3)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var legConnector: some View {
        Rectangle()
            .fill(palette.borderSoft)
            .frame(width: 2, height: 12)
            .padding(.leading, 4)
    }

    private var totalsRows: some View {
        VStack(spacing: 6) {
            totalRow(label: "SUBTOTAL", value: "-", strong: false)
            totalRow(label: "ADJUSTMENTS", value: "-", strong: false)
            HStack {
                Text("GROSS EARNED")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Text(dollars(job?.rate))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
            }
            .padding(.vertical, 4)
        }
    }

    private func totalRow(label: String, value: String, strong: Bool) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 0)
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textSecondary)
                .monospacedDigit()
        }
    }

    // MARK: - 1099 YTD strip

    private var taxStripCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("1099-NEC · YTD GROSS \(currentYear)", icon: "doc.text.fill")
            HStack(alignment: .firstTextBaseline) {
                Text(dollars(stats?.thisYear))
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("this job \(dollars(job?.rate))")
                        .font(EType.mono(.micro)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                    Text(jobsCompletedLine)
                        .font(EType.mono(.micro)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Text("Contractor gross across your completed escort jobs this tax year — no withholding on record.")
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var currentYear: String {
        String(Calendar.current.component(.year, from: Date()))
    }

    private var jobsCompletedLine: String {
        guard let n = stats?.jobsCompleted, n > 0 else { return "no completed jobs yet" }
        if let avg = stats?.avgPerJob, avg > 0 {
            return "\(n) job\(n == 1 ? "" : "s") · avg \(dollars(avg))"
        }
        return "\(n) job\(n == 1 ? "" : "s") completed"
    }

    // MARK: - Payout block

    private var payoutCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("PAYOUT", icon: "wallet.pass.fill")
            HStack(spacing: 10) {
                Image(systemName: "hourglass")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                Text("Payout method, account, and reference post with the settlement record — none is on file for this job.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Honest action notices + CTA row

    private func noticeCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Brand.warning)
            Text(text)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.tintWarning)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.warning.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button {
                withAnimation(.easeOut(duration: 0.12)) {
                    actionNotice = "There's no settlement statement to export for this job — the statement generates from the settlement record, and none is on file. Your gross pay above is already counted in your earnings totals."
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 13, weight: .heavy))
                    Text("Download statement")
                        .font(.system(size: 13, weight: .heavy)).tracking(0.3)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                if settlement != nil {
                    showDisputeSheet = true
                } else {
                    withAnimation(.easeOut(duration: 0.12)) {
                        actionNotice = "There's no settlement line to dispute — this job has no itemized settlement record on file. Flag any pay issue to your dispatcher by phone so it's corrected before the settlement posts."
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 13, weight: .heavy))
                    Text("Dispute a line")
                        .font(.system(size: 13, weight: .heavy)).tracking(0.3)
                }
                .foregroundStyle(Brand.warning)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Brand.warning.opacity(0.55), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Shared

    private func sectionHeader(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text(text)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.diagonal)
        }
    }

    private func dollars(_ v: Double?) -> String {
        guard let v, v > 0 else { return "-" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = v.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }

    private func milesLabel(_ v: Double?) -> String {
        guard let v, v > 0 else { return "- mi" }
        return "\(Int(v.rounded())) mi"
    }

    private func humanDate(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "-" }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = fmt.date(from: iso)
        if date == nil {
            fmt.formatOptions = [.withInternetDateTime]
            date = fmt.date(from: iso)
        }
        if date == nil {
            let day = DateFormatter()
            day.dateFormat = "yyyy-MM-dd"
            day.locale = Locale(identifier: "en_US_POSIX")
            date = day.date(from: String(iso.prefix(10)))
        }
        guard let d = date else { return iso }
        let out = DateFormatter()
        out.dateFormat = "MMM d, yyyy"
        return out.string(from: d)
    }

    // MARK: - Data plumbing

    private func refreshAll() async {
        if job == nil { phase = .loading }
        actionNotice = nil
        guard assignmentId != "0", !assignmentId.isEmpty else {
            phase = .missing
            return
        }
        async let statsFetch: EscortEarningsStats? = try? EusoTripAPI.shared.queryNoInput("escorts.getEarningsStats")
        // Real itemized settlement (line items + net payout), keyed by assignment.
        async let settleFetch: SettlementDetailData? = {
            guard let aid = Int(assignmentId) else { return nil }
            return try? await EusoTripAPI.shared.query("escorts.getSettlementDetail", input: AssignmentIdInput(assignmentId: aid))
        }()
        do {
            let detail: EscortJobDetail? = try await EusoTripAPI.shared.query(
                "escorts.getJobDetails",
                input: JobIdInput(jobId: assignmentId)
            )
            stats = await statsFetch
            settlement = await settleFetch
            if let detail {
                job = detail
                phase = .loaded
            } else if settlement != nil {
                phase = .loaded
            } else {
                phase = .missing
            }
        } catch {
            stats = await statsFetch
            settlement = await settleFetch
            if job == nil && settlement == nil { phase = .failed }
            else if settlement != nil { phase = .loaded }
        }
    }

    /// File a real settlement dispute against the itemized settlement.
    private func submitDispute() async {
        guard let aid = Int(assignmentId) else { return }
        let notes = disputeNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let _: SettlementDisputeResult = try await EusoTripAPI.shared.mutation(
                "escorts.submitSettlementDispute",
                input: SettlementDisputeInput(assignmentId: aid, reason: disputeReason, notes: notes.isEmpty ? "Line dispute" : notes))
            await MainActor.run {
                showDisputeSheet = false
                actionNotice = "Dispute filed — your dispatcher has been notified and the settlement is on hold."
            }
            await refreshAll()
        } catch {
            await MainActor.run { actionNotice = "Couldn't file the dispute. Retry, or call your dispatcher." }
        }
    }
}

// MARK: - Screen wrapper (Shell + BottomNav)

struct EscortSettlementDetailScreen: View {
    let theme: Theme.Palette
    let assignmentId: String

    init(theme: Theme.Palette, assignmentId: String = "0") {
        self.theme = theme
        self.assignmentId = assignmentId
    }

    var body: some View {
        Shell(theme: theme) {
            EscortSettlementDetail(assignmentId: assignmentId)
        } nav: {
            BottomNav(
                leading: escortNavLeading_605(),
                trailing: escortNavTrailing_605(),
                orbState: .idle
            )
        }
    }
}

private func escortNavLeading_605() -> [NavSlot] {
    [NavSlot(label: "Home",        systemImage: "house",                  isCurrent: false),
     NavSlot(label: "Assignments", systemImage: "shield.lefthalf.filled", isCurrent: false)]
}

private func escortNavTrailing_605() -> [NavSlot] {
    [NavSlot(label: "Corridor", systemImage: "map",    isCurrent: false),
     NavSlot(label: "Me",       systemImage: "person", isCurrent: true)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so the surface stays in its loading
// register — both variants render without touching the network.

#Preview("605 · Escort · Settlement Detail · Dark") {
    EscortSettlementDetailScreen(theme: Theme.dark, assignmentId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("605 · Escort · Settlement Detail · Light") {
    EscortSettlementDetailScreen(theme: Theme.light, assignmentId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
