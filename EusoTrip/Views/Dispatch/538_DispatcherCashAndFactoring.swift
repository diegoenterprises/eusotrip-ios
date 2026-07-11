//
//  538_DispatcherCashAndFactoring.swift
//  EusoTrip — Dispatcher · Cash & Factoring.
//
//  Verbatim SwiftUI port of:
//    `04 Dispatcher/Dark-SVG/538 Dispatcher Cash And Factoring.svg`
//
//  MONEY archetype — the dispatcher's working-capital control surface. A
//  bespoke INVOICE → CASH flow band (Invoiced → Funded → Fee) over an
//  available-to-withdraw hero + reserve, an open-AR aging stacked bar, and a
//  ready-to-fund invoice ledger. Not a stat dashboard; composition follows the
//  "where's my cash right now" job.
//
//  Honest wiring — 0 stubs, 0 mock data, fully dynamic (factoring router
//  confirmed on disk 2026-07-11):
//    • READ  factoring.getSummary        (factoring.ts:1129) → invoiced /
//            funded / invoicesFactored → hero + flow band.
//    • READ  factoring.getReserveBalance (factoring.ts:694)  → reserve cell.
//    • READ  factoring.getInvoices       (factoring.ts:490)  → ready-to-fund
//            rows (invoiceNumber / loadId / advance / status).
//    • READ  factoring.getDebtors        (factoring.ts:1168) → AR aging buckets
//            (outstanding × avgDaysToPay → 0-30 / 31-60 / 61-90).
//    • WRITE factoring.instantPay        (factoring.ts:1008, {factoringId}) →
//            "Factor selected" fires instant-pay on the tapped invoice.
//    • WRITE factoring.requestReserveWithdrawal (factoring.ts:710, {amount}) →
//            "Withdraw" pulls the available reserve.
//    All reads flow through a real do/catch with a surfaced error state.
//
//  HONEST GAP: factoring invoices carry no origin→destination lane in their
//  projection, so ready-to-fund rows lead with the invoice number + load id
//  (the real keys), not a fabricated lane. Surfaced as-is.
//
//  Persona: Aurora Freight Lines · Renée Marquette (RM) · shipper-of-record
//  Eusorone Technologies (Diego Usoro · DU). transportMode=truck; currency USD.
//  NAV (real DispatchNavController): HOME · BOARD(current) · [orb] · COMMS · ME.
//  Powered by ESANG AI™. Author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Decoders (field-for-field match to factoring.* returns)

private struct FactoringSummary538: Decodable {
    let totalFactored: Double      // sum of invoice amounts (INVOICED)
    let totalFunded: Double        // sum of advances (FUNDED / available)
    let invoicesFactored: Int
    let availableCredit: Double
    let pending: Int
}

private struct ReserveBalance538: Decodable {
    let currentBalance: Double
    let pendingRelease: Double
}

private struct FactoringInvoice538: Decodable, Identifiable {
    let id: String
    let invoiceNumber: String?
    let loadId: Int?
    let invoiceAmount: Double?
    let advanceAmount: Double?
    let factoringFee: Double?
    let status: String?
    let fundedAt: String?
    let collectedAt: String?
}

private struct Debtor538: Decodable, Identifiable {
    let id: String
    let name: String?
    let outstanding: Double?
    let avgDaysToPay: Int?
}

// MARK: - Screen

struct DispatcherCashAndFactoringScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { DispatcherCashAndFactoringBody() } nav: {
            DispatchPortNav()
        }
    }
}

// MARK: - Body

private struct DispatcherCashAndFactoringBody: View {
    @Environment(\.palette) private var palette

    @State private var summary: FactoringSummary538?
    @State private var reserve: ReserveBalance538?
    @State private var invoices: [FactoringInvoice538] = []
    @State private var debtors: [Debtor538] = []
    @State private var loading = true
    @State private var loadError: String?

    @State private var selectedInvoice: String?
    @State private var working = false
    @State private var actionNote: String?

    // Derived money
    private var invoiced: Double  { summary?.totalFactored ?? 0 }
    private var funded: Double    { summary?.totalFunded ?? 0 }
    private var feeAmount: Double  { max(0, invoiced - funded) }
    private var advancePct: Int   { invoiced > 0 ? Int((funded / invoiced * 100).rounded()) : 0 }
    private var feePct: Int       { invoiced > 0 ? max(0, 100 - advancePct) : 0 }

    // AR aging buckets from real debtor outstanding × days-to-pay
    private var aging: (b0: Double, b1: Double, b2: Double, total: Double) {
        var b0 = 0.0, b1 = 0.0, b2 = 0.0
        for d in debtors {
            let amt = d.outstanding ?? 0
            guard amt > 0 else { continue }
            let days = d.avgDaysToPay ?? 0
            if days <= 30 { b0 += amt } else if days <= 60 { b1 += amt } else { b2 += amt }
        }
        return (b0, b1, b2, b0 + b1 + b2)
    }

    private var fundable: [FactoringInvoice538] {
        invoices.filter { ($0.collectedAt ?? "").isEmpty }
    }
    private var topRows: [FactoringInvoice538] { Array(fundable.prefix(2)) }
    private var moreCount: Int { max(0, fundable.count - topRows.count) }
    private var avgAdvance: Double {
        let advs = fundable.compactMap(\.advanceAmount).filter { $0 > 0 }
        guard !advs.isEmpty else { return 0 }
        return advs.reduce(0, +) / Double(advs.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline().padding(.top, Space.s3)

            if loading {
                DispatchPortLoadingCard(text: "Loading cash position…").padding(.top, Space.s5)
            } else if let err = loadError, summary == nil {
                DispatchPortErrorCard(message: err) { Task { await load() } }.padding(.top, Space.s5)
            } else {
                heroCard.padding(.top, Space.s5)
                flowBand.padding(.top, Space.s5)
                agingCard.padding(.top, Space.s5)
                fundList.padding(.top, Space.s5)
                if let note = actionNote {
                    Text(note).font(EType.caption).foregroundStyle(palette.textSecondary)
                        .padding(.top, Space.s3)
                }
                ctaPair.padding(.top, Space.s5)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, Space.s2)
        .task { await load() }
    }

    // MARK: Top bar (DETAIL grammar)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("✦ DISPATCHER · CASH & FACTORING")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: Space.s2)
                Text("AURORA · NET-7")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                DispatchPortBackChevron()
                Text("Cash position")
                    .font(EType.h1).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: Space.s2)
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
        }
    }

    // MARK: Hero — available to withdraw + reserve

    private var heroCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("AVAILABLE TO WITHDRAW")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Text(Money538.full(funded))
                    .font(.system(size: 34, weight: .bold).monospacedDigit())
                    .foregroundStyle(LinearGradient.diagonal)
                    .padding(.top, 2)
                Text("advanced on \(summary?.invoicesFactored ?? 0) funded invoices · net-7 EusoQuickPay")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: Space.s1) {
                Text("RESERVE")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Text(Money538.full(reserve?.currentBalance ?? 0))
                    .font(.system(size: 20, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
                Text((reserve?.pendingRelease ?? 0) > 0 ? "release pending" : "no release due")
                    .font(EType.micro)
                    .foregroundStyle(Brand.success)
            }
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.xl).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    // MARK: Invoice → cash flow band (bespoke)

    private var flowBand: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("INVOICE → CASH · THIS BATCH")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("factoring")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            HStack(spacing: 0) {
                flowBlock("INVOICED", Money538.compact(invoiced), highlighted: false)
                flowConnector("\(advancePct)%", tint: LinearGradient.primary, danger: false)
                flowBlock("FUNDED", Money538.compact(funded), highlighted: true)
                flowConnector("−\(feePct)% fee", tint: nil, danger: true)
                flowBlock("FEE", "−" + Money538.compact(feeAmount), highlighted: false, danger: true)
            }
        }
        .padding(Space.s4)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    private func flowBlock(_ label: String, _ value: String, highlighted: Bool, danger: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(highlighted ? palette.textOnGradient.opacity(0.85) : palette.textTertiary)
            Text(value)
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .foregroundStyle(highlighted ? palette.textOnGradient
                                 : (danger ? Brand.danger : palette.textPrimary))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, Space.s3)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background {
            if highlighted {
                RoundedRectangle(cornerRadius: Radius.md).fill(LinearGradient.diagonal)
            } else {
                RoundedRectangle(cornerRadius: Radius.md).fill(Color.primary.opacity(0.04))
            }
        }
    }

    private func flowConnector(_ label: String, tint: LinearGradient?, danger: Bool) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(danger ? Brand.danger : palette.textOnGradient)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Capsule().fill(danger ? AnyShapeStyle(Brand.danger.opacity(0.14))
                                           : AnyShapeStyle(tint ?? LinearGradient.primary)))
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.textTertiary)
        }
        .frame(width: 46)
    }

    // MARK: AR aging

    private var agingCard: some View {
        let a = aging
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("OPEN AR · AGING")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(Money538.full(a.total)) total")
                    .font(EType.caption.monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
            }
            if a.total <= 0 {
                Text("No open receivables — every funded invoice has cleared.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            } else {
                GeometryReader { geo in
                    let w = geo.size.width
                    HStack(spacing: 3) {
                        agingSeg(a.b0, a.total, w, color: Brand.success)
                        agingSeg(a.b1, a.total, w, color: Brand.warning)
                        agingSeg(a.b2, a.total, w, color: Brand.danger)
                    }
                }
                .frame(height: 10)
                HStack(spacing: Space.s4) {
                    agingLegend("0–30", a.b0, Brand.success)
                    agingLegend("31–60", a.b1, Brand.warning)
                    agingLegend("61–90+", a.b2, Brand.danger)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(Space.s4)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    private func agingSeg(_ v: Double, _ total: Double, _ w: CGFloat, color: Color) -> some View {
        let frac = total > 0 ? CGFloat(v / total) : 0
        return Capsule().fill(color)
            .frame(width: max(v > 0 ? 6 : 0, (w - 6) * frac))
    }

    private func agingLegend(_ label: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(label) \(Money538.compact(value))")
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Ready-to-fund ledger

    private var fundList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("READY TO FUND · DELIVERED")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(fundable.isEmpty ? "none" : "See all (\(fundable.count))")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, Space.s2)

            VStack(spacing: 0) {
                if topRows.isEmpty {
                    Text("No invoices awaiting funding. Delivered loads land here the moment their POD clears.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.s4)
                } else {
                    ForEach(Array(topRows.enumerated()), id: \.element.id) { idx, inv in
                        fundRow(inv)
                        if idx < topRows.count - 1 {
                            Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                        }
                    }
                    if moreCount > 0 {
                        Text("+ \(moreCount) more delivered · \(Money538.full(avgAdvance)) avg advance · DU / Eusorone shipper-of-record")
                            .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Space.s4)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCardSoft))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private func fundRow(_ inv: FactoringInvoice538) -> some View {
        let selected = selectedInvoice == inv.id
        let instant = (inv.status ?? "").lowercased().contains("approv") || (inv.fundedAt ?? "").isEmpty == false
        return Button {
            selectedInvoice = selected ? nil : inv.id
        } label: {
            HStack(alignment: .center, spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill((selected ? Brand.success : Brand.info).opacity(0.14))
                    Image(systemName: selected ? "checkmark" : "doc.text.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(selected ? Brand.success : Brand.info)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(inv.invoiceNumber ?? "Invoice \(inv.id)")
                        .font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                    Text("Load #\(inv.loadId.map(String.init) ?? "—") · adv \(Money538.full(inv.advanceAmount ?? 0))")
                        .font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary).lineLimit(1)
                }
                Spacer(minLength: Space.s2)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(instant ? "INSTANT" : (inv.status ?? "NET-7").uppercased())
                        .font(EType.micro).tracking(0.5)
                        .foregroundStyle(instant ? palette.textOnGradient : palette.textSecondary)
                        .padding(.horizontal, 10).frame(height: 24)
                        .background(Capsule().fill(instant ? AnyShapeStyle(LinearGradient.primary)
                                                   : AnyShapeStyle(Color.primary.opacity(0.06))))
                    Text(Money538.full(inv.invoiceAmount ?? 0))
                        .font(EType.bodyStrong.monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                }
            }
            .padding(Space.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            Button { Task { await factorSelected() } } label: {
                HStack(spacing: Space.s2) {
                    if working { ProgressView().tint(palette.textOnGradient) }
                    Text(working ? "Working…" : "Factor selected")
                        .font(EType.bodyStrong).foregroundStyle(palette.textOnGradient)
                }
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .disabled(working || selectedInvoice == nil)
            .opacity(selectedInvoice == nil ? 0.5 : 1)

            Button { Task { await withdrawReserve() } } label: {
                Text("Withdraw")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    .frame(width: 132).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).fill(Color(hex: 0x232932)))
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(working || (reserve?.currentBalance ?? 0) <= 0)
        }
    }

    // MARK: Data + actions

    private func load() async {
        loading = true; loadError = nil
        struct InvIn: Encodable { let limit: Int }
        struct DebtIn: Encodable { let limit: Int }
        do {
            async let s: FactoringSummary538 = EusoTripAPI.shared.queryNoInput("factoring.getSummary")
            async let r: ReserveBalance538 = EusoTripAPI.shared.queryNoInput("factoring.getReserveBalance")
            async let inv: [FactoringInvoice538] = EusoTripAPI.shared.query("factoring.getInvoices", input: InvIn(limit: 8))
            async let deb: [Debtor538] = EusoTripAPI.shared.query("factoring.getDebtors", input: DebtIn(limit: 50))
            let (sv, rv, iv, dv) = try await (s, r, inv, deb)
            summary = sv; reserve = rv; invoices = iv; debtors = dv
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func factorSelected() async {
        guard let id = selectedInvoice else { return }
        working = true; actionNote = nil
        struct In: Encodable { let factoringId: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation("factoring.instantPay", input: In(factoringId: id))
            actionNote = "Instant-pay requested on \(invoices.first { $0.id == id }?.invoiceNumber ?? id)."
            selectedInvoice = nil
            await load()
        } catch {
            actionNote = "Couldn't factor that invoice: \((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)"
        }
        working = false
    }

    private func withdrawReserve() async {
        let amount = reserve?.currentBalance ?? 0
        guard amount > 0 else { return }
        working = true; actionNote = nil
        struct In: Encodable { let amount: Double; let reason: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation("factoring.requestReserveWithdrawal",
                                                               input: In(amount: amount, reason: "Dispatch cash position"))
            actionNote = "Withdrawal of \(Money538.full(amount)) requested from reserve."
            await load()
        } catch {
            actionNote = "Couldn't withdraw reserve: \((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)"
        }
        working = false
    }
}

// MARK: - Money formatting

private enum Money538 {
    static func full(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return "$" + (f.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v))")
    }
    static func compact(_ v: Double) -> String {
        let a = abs(v)
        if a >= 1000 { return String(format: "$%.1fK", v / 1000) }
        return "$\(Int(v.rounded()))"
    }
}

// MARK: - Preview

#if DEBUG
#Preview("538 · Cash & Factoring · Dark") {
    DispatcherCashAndFactoringScreen(theme: Theme.dark)
        .environment(\.palette, Theme.dark)
}
#Preview("538 · Cash & Factoring · Light") {
    DispatcherCashAndFactoringScreen(theme: Theme.light)
        .environment(\.palette, Theme.light)
}
#endif
