//
//  802_VesselClaimPayments.swift
//  EusoTrip — Vessel Operator · Claim Payments.
//
//  Faithful 1:1 port of "802 Vessel Claim Payments.svg" (Light + Dark), RECONSTRUCTED from a
//  money-hero clone of 800/801 into the flagship LEDGER archetype — mirror of 02 Shipper/227
//  Settlement Detail:
//    • a recovery-summary RimCard hero with a method-split bar (ACH / wire / settlement-deduction / credit)
//    • a BY-METHOD breakdown card (dot + name + count sub + tabular amount + share %)
//    • a TOTAL · RECOVERED strip
//    • a remittance activity timeline of the last paid claims
//    • a decisive "Release pending" gradient CTA + "Export" secondary, then the ESang row.
//  Kills the 800/801/802 monotony: 802 is now the disbursement ledger, not a third money board.
//  Nav anchored to the registered Vessel Operator Shell + BottomNav (HOME · SHIPMENTS · [orb] ·
//  COMPLIANCE[current] · ME) — the same wrapper the registered vessel siblings 757/664/680 ship.
//
//  Data / wiring (endpoint confirmed via EUSOTRIP_PLATFORM MCP this fire):
//    freightClaims.getClaimPayments (EXISTS frontend/server/routers/freightClaims.ts:728 ·
//        input {claimId?,status?(pending|processing|paid|failed),limit,offset} -> {payments:[{id,
//        claimId,claimNumber,amount,status,method,scheduledDate,paidDate,reference}],total,
//        totalPaid,totalPending}) feeds hero (totalPaid), the pending CTA value (totalPending),
//        the method breakdown + the timeline.
//    "Release pending" -> freightClaims.processClaimPayment (EXISTS freightClaims.ts:756 · {claimId,
//        amount,method:(ach|check|wire|deduct_from_settlement|credit),reference?,notes?}).
//    "Export" -> freightClaims.generateClaimReport(format:csv), copied for system share/paste.
//
//  ZERO-FALLBACK (2026-06-09 · B17 fix): NO seeded financial rows anywhere. The method breakdown,
//  the split bar AND the remittance timeline all COMPUTE from r.payments on every load — when the
//  proc returns no payments the honest empty states render ($0 hero, "no recoveries" rows), never
//  a fabricated ACH/wire ledger. The ESang advisory derives from the live totals only. RimCard802 /
//  ESangRow802 / secondaryButton802 are file-scoped bespoke helpers (the canonical port's RimCard /
//  ESangRow / SecondaryButton are not shared app symbols) built from the registered siblings'
//  gradient-rim grammar to preserve the exact wireframe look.
//

import SwiftUI
import UIKit

private struct PayBarSeg802 { let frac: Double; let color: Color }

private struct MethodRow802: Identifiable {
    let id = UUID()
    let dot: Color
    let name: String
    let count: String
    let amount: String
    let share: String
    let shareColor: Color
}

private struct RemitRow802: Identifiable {
    let id = UUID()
    let dot: Color
    let title: String
    let amount: String
    let ref: String
}

struct VesselClaimPaymentsScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselClaimPaymentsBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselClaimPaymentsBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil

    // B17: nil/empty initial state — every figure below is written by load() from the
    // live getClaimPayments response. No seeded dollars, methods or remittances.
    @State private var recovered = "—"
    @State private var pending   = "—"
    @State private var pendingValue: Double = 0
    @State private var payCount  = 0
    @State private var carriers  = 0
    @State private var segments: [PayBarSeg802] = []
    @State private var methods: [MethodRow802] = []
    @State private var remits: [RemitRow802] = []
    @State private var payments: [ClaimPayment802] = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text("Claim payments").font(.system(size: 34, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("Recoveries & disbursements").font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    heroCard
                    Text("BY METHOD · RECOVERED").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    methodCard
                    totalStrip
                    Text("RECENT REMITTANCES").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    timeline
                    HStack(spacing: 8) {
                        CTAButton(title: "Release pending · \(pending)", action: { Task { await releasePending() } }, trailingIcon: "arrow.right")
                            .disabled(pendingValue <= 0)
                            .opacity(pendingValue > 0 ? 1 : 0.45)
                        secondaryButton802(title: "Export") { Task { await exportStatement() } }
                    }
                    // ESang advisory derives from the LIVE totals only — no fabricated claim refs.
                    ESangRow802(title: payCount > 0 ? "ESang: \(payCount) payment\(payCount == 1 ? "" : "s") on the ledger"
                                                    : "ESang: no claim recoveries yet",
                                subtitle: pendingValue > 0 ? "\(pending) pending release across live claims"
                                                           : "recoveries appear here as claim payments post")
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text("VESSEL OPERATOR · CLAIM PAYMENTS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            Spacer()
            Text("USD").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
        }
    }

    private var heroCard: some View {
        RimCard802 {
            VStack(alignment: .leading, spacing: 10) {
                Text("RECOVERY LEDGER").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(recovered).font(.system(size: 30, weight: .bold, design: .monospaced)).foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("recovered · \(payCount) payment\(payCount == 1 ? "" : "s")").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                        Text("\(pending) pending · \(carriers) claim\(carriers == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                    }
                }
                // Split bar computes from the live by-method shares; renders as the
                // neutral track when no payments exist (no fabricated proportions).
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(Array(segments.enumerated()), id: \.offset) { _, s in
                            RoundedRectangle(cornerRadius: 4).fill(s.color).frame(width: max(0, geo.size.width * s.frac - 2))
                        }
                        Spacer(minLength: 0)
                    }
                    .background(RoundedRectangle(cornerRadius: 4).fill(palette.borderFaint))
                }.frame(height: 8)
            }
        }
    }

    private var methodCard: some View {
        LifecycleCard {
            VStack(spacing: 0) {
                if methods.isEmpty {
                    Text("No recoveries on the ledger yet — the by-method split renders from live claim payments.")
                        .font(EType.caption).foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                } else {
                    ForEach(Array(methods.enumerated()), id: \.element.id) { idx, m in
                        HStack(spacing: 12) {
                            Circle().fill(m.dot).frame(width: 10, height: 10)
                            Text(m.name).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                            Text(m.count).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(m.amount).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                                Text(m.share).font(.system(size: 9, weight: .bold)).foregroundStyle(m.shareColor)
                            }
                        }
                        .padding(.vertical, 10)
                        if idx < methods.count - 1 { Divider().overlay(palette.borderFaint) }
                    }
                }
            }
        }
    }

    private var totalStrip: some View {
        HStack {
            Text("TOTAL · RECOVERED").font(.system(size: 11, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            Spacer()
            Text(recovered).font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(.white)
        }
        .padding(.horizontal, 16).frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0x12161D)))
    }

    @ViewBuilder
    private var timeline: some View {
        if remits.isEmpty {
            Text("No remittances in range — paid claims appear here as they post.")
                .font(EType.caption).foregroundStyle(palette.textTertiary)
        } else {
            HStack(alignment: .top, spacing: 0) {
                Rectangle().fill(palette.borderFaint).frame(width: 1.5).padding(.leading, 11).padding(.top, 6)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(remits) { e in
                                HStack(alignment: .top, spacing: 14) {
                                    Circle().fill(e.dot).frame(width: 8, height: 8).padding(.leading, -4.5).padding(.top, 3)
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(e.title).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                                            Spacer()
                                            Text(e.amount).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                                        }
                                        Text(e.ref).font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textTertiary)
                                    }
                                }
                            }
                        }
                    }
            }
        }
    }

    /// Bespoke secondary (outline) button — the canonical port's `SecondaryButton`
    /// is not a shared app symbol, so we hand-roll the same outline grammar the
    /// registered siblings (757/680) use for their secondary CTA.
    private func secondaryButton802(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.blue)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: ClaimPaymentsResp802 = try await EusoTripAPI.shared.query(
                "freightClaims.getClaimPayments", input: ClaimPaymentsInput802(limit: 20, offset: 0))
            payments     = r.payments
            recovered    = usd802(r.totalPaid)
            pending      = usd802(r.totalPending)
            pendingValue = r.totalPending
            payCount     = r.total
            // B17: EVERY derived face recomputes unconditionally from r.payments —
            // an empty response clears the ledger to its honest empty states.
            carriers = Set(r.payments.compactMap { $0.claimNumber }).count
            remits = r.payments.prefix(2).map { p in
                RemitRow802(dot: methodColor(p.method),
                            title: "\(p.claimNumber ?? "-") · \((p.method ?? "—").uppercased())",
                            amount: usd802(p.amount ?? 0),
                            ref: (p.status ?? "—").lowercased())
            }
            (methods, segments) = Self.methodBreakdown(from: r.payments)
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// Compute the by-method breakdown + split-bar segments from live payment rows.
    private static func methodBreakdown(from payments: [ClaimPayment802]) -> ([MethodRow802], [PayBarSeg802]) {
        guard !payments.isEmpty else { return ([], []) }
        struct Bucket { var count = 0; var total = 0.0 }
        var buckets: [String: Bucket] = [:]
        for p in payments {
            let key = (p.method ?? "other").lowercased()
            var b = buckets[key] ?? Bucket()
            b.count += 1; b.total += p.amount ?? 0
            buckets[key] = b
        }
        let grand = buckets.values.reduce(0.0) { $0 + $1.total }
        let ordered = buckets.sorted { $0.value.total > $1.value.total }
        let rows: [MethodRow802] = ordered.map { key, b in
            let color = Self.staticMethodColor(key)
            let share = grand > 0 ? Int((b.total / grand * 100).rounded()) : 0
            return MethodRow802(dot: color,
                                name: Self.methodName(key),
                                count: "\(b.count) payment\(b.count == 1 ? "" : "s")",
                                amount: Self.usdStatic(b.total),
                                share: "\(share)%",
                                shareColor: color)
        }
        let segs: [PayBarSeg802] = grand > 0
            ? ordered.map { key, b in PayBarSeg802(frac: b.total / grand, color: Self.staticMethodColor(key)) }
            : []
        return (rows, segs)
    }

    private static func methodName(_ key: String) -> String {
        switch key {
        case "ach":                     return "ACH transfer"
        case "wire":                    return "Wire"
        case "check":                   return "Check"
        case "deduct_from_settlement":  return "Settlement deduction"
        case "credit":                  return "Credit memo"
        default:                        return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static func staticMethodColor(_ key: String) -> Color {
        switch key {
        case "ach":  return Brand.blue
        case "wire": return Brand.magenta
        case "deduct_from_settlement": return Brand.success
        case "credit": return Brand.warning
        default: return Brand.info
        }
    }

    private static func usdStatic(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }

    private func methodColor(_ m: String?) -> Color {
        switch (m ?? "").lowercased() {
        case "ach":  return Brand.blue
        case "wire": return Brand.magenta
        case "deduct_from_settlement": return Brand.success
        case "credit": return Brand.warning
        default: return Brand.blue
        }
    }

    private var nextPendingPayment: ClaimPayment802? {
        payments.first { payment in
            (payment.status ?? "").lowercased() == "pending" &&
            !(payment.claimId ?? "").isEmpty &&
            (payment.amount ?? 0) > 0
        }
    }

    private var reportClaimId: String? {
        payments.first { !($0.claimId ?? "").isEmpty }?.claimId
    }

    private func releaseMethod(_ method: String?) -> String {
        let value = (method ?? "").lowercased()
        return ["ach", "check", "wire", "deduct_from_settlement", "credit"].contains(value) ? value : "ach"
    }

    private func releasePending() async {
        guard let payment = nextPendingPayment,
              let claimId = payment.claimId,
              let amount = payment.amount
        else {
            await load()
            return
        }
        do {
            let _: ProcessClaimPaymentResp802 = try await EusoTripAPI.shared.mutation(
                "freightClaims.processClaimPayment",
                input: ProcessClaimPaymentInput802(
                    claimId: claimId,
                    amount: amount,
                    method: releaseMethod(payment.method),
                    reference: payment.reference,
                    notes: "Vessel claim payment release"
                )
            )
            await load()
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func exportStatement() async {
        guard let claimId = reportClaimId else {
            await load()
            return
        }
        do {
            let report: ClaimReportResp802 = try await EusoTripAPI.shared.mutation(
                "freightClaims.generateClaimReport",
                input: ClaimReportInput802(
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

    private func usd802(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}

// MARK: - Wire types (private to this file — no module-level EmptyInput)

private struct ClaimPaymentsInput802: Encodable { let limit: Int; let offset: Int }
private struct ClaimPayment802: Decodable {
    let id: String?
    let claimId: String?
    let claimNumber: String?
    let amount: Double?
    let status: String?
    let method: String?
    let reference: String?
}
private struct ClaimPaymentsResp802: Decodable { let payments: [ClaimPayment802]; let total: Int; let totalPaid: Double; let totalPending: Double }

private struct ProcessClaimPaymentInput802: Encodable {
    let claimId: String
    let amount: Double
    let method: String
    let reference: String?
    let notes: String?
}

private struct ProcessClaimPaymentResp802: Decodable {
    let success: Bool
    let paymentId: String?
    let status: String?
}

private struct ClaimReportInput802: Encodable {
    let claimId: String
    let format: String
    let includeEvidence: Bool
    let includeTimeline: Bool
    let includeFinancials: Bool
    let purpose: String
}

private struct ClaimReportResp802: Decodable {
    let success: Bool
    let filename: String?
    let content: String?
}

// MARK: - File-scoped bespoke helpers (preserve the canonical wireframe look)

/// Gradient-rim hero card — mirrors the gradient-stroked context cards the
/// registered siblings (757 `RimCard757`, 664 `moveContextCard`) ship.
private struct RimCard802<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
            )
    }
}

/// ESang advisory row — the canonical port's `ESangRow` is not a shared app
/// symbol, so we render the same sparkle + advisory grammar file-scoped.
private struct ESangRow802: View {
    @Environment(\.palette) private var palette
    let title: String
    let subtitle: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient.diagonal.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }
}

#Preview("802 · Claim Payments · Night") { VesselClaimPaymentsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("802 · Claim Payments · Light") { VesselClaimPaymentsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
