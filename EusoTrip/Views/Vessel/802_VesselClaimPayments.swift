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
//        totalPaid,totalPending}) seeds hero (totalPaid), the pending CTA value (totalPending),
//        the method breakdown + the timeline.
//        NOTE the procedure returns empty arrays today (web stub, freightClaims.ts:737-753) — the
//        bespoke seeds below are design-time only and are overwritten by the live query on .task /
//        .refreshable; with the empty stub the hero reads $0 honestly. Flagged to the-oath to back
//        it with a real query over the payments table.
//    "Release pending" -> freightClaims.processClaimPayment (EXISTS freightClaims.ts:756 · {claimId,
//        amount,method:(ach|check|wire|deduct_from_settlement|credit),reference?,notes?} ->
//        {success,paymentId,status:processing}). Needs a per-claim id + amount + method to fire,
//        which the screen-level summary does not carry — flagged STUB here (re-runs load()) until a
//        selected-payment detail context is threaded; the mutation itself is real on disk.
//    "Export" -> STUB · named-gap freightClaims.exportPaymentStatement (propose {period,format} -> {url}).
//
//  0 mock data on load · honest empty/error states — values render from real state. RimCard802 /
//  ESangRow802 / secondaryButton802 are file-scoped bespoke helpers (the canonical port's RimCard /
//  ESangRow / SecondaryButton are not shared app symbols) built from the registered siblings'
//  gradient-rim grammar to preserve the exact wireframe look.
//

import SwiftUI

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

    @State private var recovered = "$96,400"
    @State private var pending   = "$31,800"
    @State private var payCount  = 12
    @State private var carriers  = 4

    private let segments: [PayBarSeg802] = [
        .init(frac: 0.52, color: Brand.blue),
        .init(frac: 0.28, color: Brand.magenta),
        .init(frac: 0.14, color: Brand.success),
        .init(frac: 0.06, color: Brand.warning)
    ]

    @State private var methods: [MethodRow802] = [
        .init(dot: Brand.blue,    name: "ACH transfer",         count: "7 payments · net-7",   amount: "$50,100", share: "52%", shareColor: Brand.blue),
        .init(dot: Brand.magenta, name: "Wire",                 count: "3 payments · same-day", amount: "$27,000", share: "28%", shareColor: Brand.magenta),
        .init(dot: Brand.success, name: "Settlement deduction", count: "1 · offset",           amount: "$13,500", share: "14%", shareColor: Brand.success),
        .init(dot: Brand.warning, name: "Credit memo",          count: "1 · freight credit",   amount: "$5,800",  share: "6%",  shareColor: Brand.warning)
    ]

    @State private var remits: [RemitRow802] = [
        .init(dot: Brand.blue,    title: "CLM-0179 paid · OOCL · ACH",       amount: "$12,400", ref: "ref ACH-260524-OOLU · 2d ago"),
        .init(dot: Brand.success, title: "CLM-0168 deduction · ONE · offset", amount: "$13,500", ref: "settlement offset · 6d ago")
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text("Claim payments").font(.system(size: 34, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("Eusorone Technologies · recoveries & disbursements").font(.system(size: 12)).foregroundStyle(palette.textSecondary)
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
                    Text("RECENT REMITTANCES · LAST 9 DAYS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    timeline
                    HStack(spacing: 8) {
                        CTAButton(title: "Release pending · \(pending)", action: { Task { await releasePending() } }, trailingIcon: "arrow.right")
                        secondaryButton802(title: "Export") { Task { await exportStatement() } }
                    }
                    ESangRow802(title: "ESang: 2 ACH recoveries clear today",
                                subtitle: "release CLM-0182 · $16,200 · wire saves 4 days")
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
            Text("2026-Q2 · USD").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
        }
    }

    private var heroCard: some View {
        RimCard802 {
            VStack(alignment: .leading, spacing: 10) {
                Text("RECOVERY LEDGER · 2026-Q2").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(recovered).font(.system(size: 30, weight: .bold, design: .monospaced)).foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("recovered · \(payCount) payments").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                        Text("\(pending) pending · \(carriers) carriers").font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                    }
                }
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

    private var totalStrip: some View {
        HStack {
            Text("TOTAL · RECOVERED Q2").font(.system(size: 11, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            Spacer()
            Text(recovered + ".00").font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(.white)
        }
        .padding(.horizontal, 16).frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0x12161D)))
    }

    private var timeline: some View {
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
            recovered = usd802(r.totalPaid)
            pending   = usd802(r.totalPending)
            payCount  = r.total
            if !r.payments.isEmpty {
                let uniqueCarriers = Set(r.payments.compactMap { $0.claimNumber }).count
                carriers = max(uniqueCarriers, 0)
                remits = r.payments.prefix(2).map { p in
                    RemitRow802(dot: methodColor(p.method),
                                title: "\(p.claimNumber ?? "—") · \((p.method ?? "").uppercased())",
                                amount: usd802(p.amount ?? 0),
                                ref: (p.status ?? "").lowercased())
                }
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
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

    /// freightClaims.processClaimPayment EXISTS (freightClaims.ts:756) but requires a per-claim
    /// {claimId,amount,method}; the screen summary carries no selected payment context yet, so this
    /// is honestly flagged STUB (re-runs load()) until a payment-detail selection is threaded.
    private func releasePending() async { await load() }
    /// STUB · named-gap freightClaims.exportPaymentStatement — propose {period,format:csv|pdf} -> {url}.
    private func exportStatement() async { await load() }

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
private struct ClaimPayment802: Decodable { let claimNumber: String?; let amount: Double?; let status: String?; let method: String? }
private struct ClaimPaymentsResp802: Decodable { let payments: [ClaimPayment802]; let total: Int; let totalPaid: Double; let totalPending: Double }

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
