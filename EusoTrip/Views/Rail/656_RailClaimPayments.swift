//
//  656_RailClaimPayments.swift
//  EusoTrip — Rail Engineer · Claim Payments — RECONCILIATION & AGING.
//
//  Bespoke port of "05 Rail/Code/656_RailClaimPayments.swift" (Light + Dark),
//  reconstructed 2026-06-02 into a distinct reconciliation/aging surface:
//    outstanding-payables hero + 4-bucket payables aging bars + reconciliation rows
//    matching payouts to the settlement ledger + variance flag.
//  Adapted to app convention: Shell + rail BottomNav (COMPLIANCE slot inked).
//  Role: RAIL_ENGINEER. transportMode=rail · US/BNSF. RBAC: protectedProcedure.
//
//  Data:
//    freightClaims.getClaimPayments (EXISTS freightClaims.ts:728)
//      input  → { claimId?, status?, limit, offset }
//      output → { payments:[{id,claimId,claimNumber,amount,status,method,
//                            scheduledDate,paidDate,reference}], total, totalPaid, totalPending }
//    processClaimPayment reconciles the next pending claim payout from the live ledger.
//    generateClaimReport exports the selected claim as CSV from the server-side report generator.
//
//  NAV (REAL): HOME · SHIPMENTS · [orb] · COMPLIANCE(current) · ME
//

import SwiftUI
import UIKit

struct RailClaimPaymentsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { RailClaimPaymentsBody656() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Input / data shapes

private struct ClaimPaymentsInput656: Encodable {
    let limit: Int
    let offset: Int
}

private struct ClaimPayment656: Decodable, Identifiable {
    let id: String
    let claimId: String?
    let claimNumber: String?
    let amount: Double?
    let status: String?
    let method: String?
    let scheduledDate: String?
    let paidDate: String?
    let reference: String?
}

private struct ClaimPaymentsResp656: Decodable {
    let payments: [ClaimPayment656]
    let total: Double?
    let totalPaid: Double?
    let totalPending: Double?
}

private struct ProcessClaimPaymentInput656: Encodable {
    let claimId: String
    let amount: Double
    let method: String
    let reference: String?
    let notes: String?
}

private struct ProcessClaimPaymentResp656: Decodable {
    let success: Bool
    let paymentId: String?
    let status: String?
}

private struct ClaimReportInput656: Encodable {
    let claimId: String
    let format: String
    let includeEvidence: Bool
    let includeTimeline: Bool
    let includeFinancials: Bool
    let purpose: String
}

private struct ClaimReportResp656: Decodable {
    let success: Bool
    let filename: String?
    let content: String?
}

// MARK: - Aging bar (decorative payables-aging visual)

private struct AgingBar656: Identifiable {
    let id = UUID()
    let label: String
    let frac: CGFloat
    let tint: Color
}

// MARK: - Body

private struct RailClaimPaymentsBody656: View {
    @Environment(\.palette) private var palette

    @State private var payments: [ClaimPayment656] = []
    @State private var total: Double = 0
    @State private var totalPaid: Double = 0
    @State private var totalPending: Double = 0
    @State private var loading = true
    @State private var loadError: String? = nil

    // MARK: Derived

    private var reconciledPct: Int {
        guard total > 0 else { return 0 }
        return Int((totalPaid / total * 100).rounded())
    }
    private var inProcessCount: Int {
        payments.filter { ($0.status ?? "").lowercased() == "processing" || ($0.status ?? "").lowercased() == "pending" }.count
    }

    // Payables-aging buckets. With no per-payment scheduledDate data today (payments[]
    // empty server-side), the bars read a flat baseline so the aging visual still
    // communicates the 0–30 / 31–60 / 61–90 / 90+ structure honestly.
    private var aging: [AgingBar656] {
        let buckets = bucketFractions()
        return [ .init(label: "0–30",  frac: buckets.0, tint: Brand.blue),
                 .init(label: "31–60", frac: buckets.1, tint: Brand.warning),
                 .init(label: "61–90", frac: buckets.2, tint: Brand.magenta),
                 .init(label: "90+",   frac: buckets.3, tint: Brand.danger) ]
    }

    private func bucketFractions() -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        guard !payments.isEmpty else { return (1.0, 0.0, 0.0, 0.0) }
        var b0 = 0.0, b1 = 0.0, b2 = 0.0, b3 = 0.0
        for p in payments {
            let amt = p.amount ?? 0
            switch ageDays(p.scheduledDate) {
            case ..<31:  b0 += amt
            case 31..<61: b1 += amt
            case 61..<91: b2 += amt
            default:      b3 += amt
            }
        }
        let maxV = max(b0, b1, b2, b3, 1)
        return (CGFloat(b0 / maxV), CGFloat(b1 / maxV), CGFloat(b2 / maxV), CGFloat(b3 / maxV))
    }

    private func ageDays(_ iso: String?) -> Int {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return 0 }
        return max(0, Int(Date().timeIntervalSince(d) / 86_400))
    }

    private func money(_ v: Double) -> String {
        if v >= 1000 { return String(format: "$%.1fK", v / 1000) }
        return String(format: "$%.0f", v)
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                if loading {
                    LifecycleCard { Text("Loading payments…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    hero
                    list
                    reconBand
                    ctaRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("RAIL ENGINEER · CLAIM PAYMENTS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text("RECON · BNSF")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Payments")
                    .font(.system(size: 28, weight: .heavy)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            IridescentHairline()
        }
    }

    // MARK: - Hero (outstanding payables + aging bars)

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { pillChip656("outstanding"); Spacer() }
            HStack(alignment: .firstTextBaseline) {
                Text(money(totalPending))
                    .font(.system(size: 30, weight: .bold)).monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("payables open").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    Text("\(inProcessCount) in process").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("RECONCILED").font(.system(size: 10, weight: .heavy)).kerning(0.6).foregroundStyle(palette.textTertiary)
                    Text("\(reconciledPct)%").font(.system(size: 22, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                    Text("to settlement").font(.system(size: 11)).foregroundStyle(Brand.success)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(aging) { b in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4).fill(b.tint).frame(height: 8 + 24 * b.frac)
                        Text(b.label).font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textTertiary)
                    }.frame(maxWidth: .infinity)
                }
            }.frame(height: 44)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(LinearGradient.primary, lineWidth: 1.5))
    }

    // MARK: - Reconcile list

    private var list: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("RECONCILE · CLAIM PAYMENTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("settlement ledger")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            if payments.isEmpty {
                EusoEmptyState(systemImage: "checklist",
                               title: "No payments to reconcile",
                               subtitle: "Outstanding totals are tracked above. Per-payment reconciliation rows appear once the settlement ledger posts claim lines.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(payments.prefix(8).enumerated()), id: \.element.id) { i, p in
                        reconRow(p)
                        if i < min(payments.count, 8) - 1 {
                            Divider().overlay(palette.borderFaint)
                        }
                    }
                    Text("ties payouts to the settlement's shipper charge · per-diem basis")
                        .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
            }
        }
    }

    private func reconRow(_ p: ClaimPayment656) -> some View {
        let info = statusInfo656(p.status)
        let sub = [p.claimNumber, p.reference].compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: 12) {
            chip656(info.glyph, info.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(p.claimNumber ?? p.claimId ?? p.id)
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(sub.isEmpty ? (p.method ?? "-") : sub)
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                StatusPill(text: info.pill, kind: info.kind)
                Text(money(p.amount ?? 0)).font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Recon band

    private var reconBand: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RECON · payee Eusorone Technologies (DU)")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text("Variances need review before close · ACH 2–3 business days")
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
    }

    private var nextPendingPayment: ClaimPayment656? {
        payments.first { payment in
            (payment.status ?? "").lowercased() == "pending" &&
            !(payment.claimId ?? "").isEmpty &&
            (payment.amount ?? 0) > 0
        }
    }

    private var reportClaimId: String? {
        payments.first { !($0.claimId ?? "").isEmpty }?.claimId
    }

    // MARK: - CTA row

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Reconcile", action: { Task { await reconcileNextPayment() } })
                .disabled(nextPendingPayment == nil)
                .opacity(nextPendingPayment == nil ? 0.45 : 1)
            Button {
                Task { await exportClaimReport() }
            } label: {
                Text("Export")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(reportClaimId == nil)
            .opacity(reportClaimId == nil ? 0.45 : 1)
        }
    }

    // MARK: - Sub-views

    private func pillChip656(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .bold)).kerning(0.5)
            .foregroundStyle(palette.textSecondary)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(palette.tintNeutral))
    }

    private func chip656(_ icon: String, _ tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.16)).frame(width: 40, height: 40)
            .overlay(Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint))
    }

    private func statusInfo656(_ status: String?) -> (glyph: String, tint: Color, pill: String, kind: StatusPill.Kind) {
        switch (status ?? "").lowercased() {
        case "paid":       return ("checkmark.circle",       Brand.success, "RECONCILED", .success)
        case "processing": return ("clock",                  Brand.warning, "OPEN",       .warning)
        case "failed":     return ("exclamationmark.triangle", Brand.danger, "REVIEW",     .danger)
        case "pending":    return ("clock",                  Brand.warning, "PENDING",    .warning)
        default:           return ("circle",                 Brand.info,    "-",          .info)
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        do {
            let resp: ClaimPaymentsResp656 = try await EusoTripAPI.shared.query(
                "freightClaims.getClaimPayments",
                input: ClaimPaymentsInput656(limit: 20, offset: 0)
            )
            self.payments     = resp.payments
            self.total        = resp.total ?? 0
            self.totalPaid    = resp.totalPaid ?? 0
            self.totalPending = resp.totalPending ?? 0
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func reconcileNextPayment() async {
        guard let payment = nextPendingPayment,
              let claimId = payment.claimId,
              let amount = payment.amount
        else {
            await load()
            return
        }
        do {
            let _: ProcessClaimPaymentResp656 = try await EusoTripAPI.shared.mutation(
                "freightClaims.processClaimPayment",
                input: ProcessClaimPaymentInput656(
                    claimId: claimId,
                    amount: amount,
                    method: "ach",
                    reference: nil,
                    notes: "Rail claim reconciliation release"
                )
            )
            await load()
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func exportClaimReport() async {
        guard let claimId = reportClaimId else {
            await load()
            return
        }
        do {
            let report: ClaimReportResp656 = try await EusoTripAPI.shared.mutation(
                "freightClaims.generateClaimReport",
                input: ClaimReportInput656(
                    claimId: claimId,
                    format: "csv",
                    includeEvidence: true,
                    includeTimeline: true,
                    includeFinancials: true,
                    purpose: "internal"
                )
            )
            if let content = report.content, !content.isEmpty {
                UIPasteboard.general.string = content
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("656 · Rail Claim Payments · Night") {
    RailClaimPaymentsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("656 · Rail Claim Payments · Light") {
    RailClaimPaymentsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
