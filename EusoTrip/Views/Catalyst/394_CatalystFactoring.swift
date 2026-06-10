//
//  394_CatalystFactoring.swift
//  EusoTrip 2027 — Catalyst track · carrier back-office growth band.
//
//  Verbatim iOS-house port of the canonical bespoke wireframe:
//    03 Catalyst/Code/394_CatalystFactoring.swift
//    03 Catalyst/Dark-SVG/394 Catalyst Factoring.svg
//
//  Moment: Michael Eusorone (Eusotrans LLC owner-op) opens his factoring
//  line from the Wallet tab to turn delivered, POD-signed receivables into
//  same-day cash instead of waiting net-30. The body is a LENDING ledger —
//  an "available to advance" hero with the advance-rate gauge, a fee/reserve
//  band, a list of eligible invoices each showing face value, advance amount
//  and verification state, and a one-tap fund CTA. Money rows carry the
//  doc/$ chip but omit lifecycle dots (Foundation Contract §5). The screen
//  exists to collapse a 30-day cash-flow gap to ~2 minutes.
//
//  LIVE WIRING (zero-fallback purge · 2026-06-09 · audit B13):
//    • hero available + reserve + advance rate → factoring.getOverview (factoring.ts:392)
//    • fee / rate band                         → factoring.getRates    (factoring.ts:1004)
//    • eligible-invoice rows                   → factoring.getInvoices (factoring.ts:428)
//    • last advance strip                      → getOverview.recentActivity
//  All decoded against the exact server projections (Number()-wrapped on the
//  server, plain Doubles on the wire). NO seed fixture remains: every figure
//  is live or an honest em-dash / EusoEmptyState. The "Advance now" CTA stays
//  a NotificationCenter intent (factoring.instantPay not yet bridged) and is
//  disabled until real selected invoices exist.
//
//  Bottom nav (Catalyst variant): HOME · DISPATCH · [orb] · WALLET · ME.
//

import SwiftUI

// MARK: - Wrapper

struct CatalystFactoringScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) { FactoringBody_394() }
        nav: { BottomNav(leading: catalystNavLeading_394(), trailing: catalystNavTrailing_394(), orbState: .idle) }
    }
}

private func catalystNavLeading_394() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: false)]
}
private func catalystNavTrailing_394() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard",         isCurrent: true),
     NavSlot(label: "Me",     systemImage: "person.crop.circle", isCurrent: false)]
}

// MARK: - Display row (built from live factoring.getInvoices rows only)

private struct FactorInvoice_394: Identifiable {
    enum Verify { case verified, pending }
    let id: String
    let shipper: String        // invoice number (title line)
    let idLane: String         // load ref + submitted date
    let statusLine: String     // raw server status, honest
    let verify: Verify
    let face: String
    let advance: String?       // nil when holding
    let advanceAmount: Double  // numeric, for the selected-total sum
}

// MARK: - Wire shapes (mirror server/routers/factoring.ts projections exactly)

private struct FactoringOverviewWire_394: Decodable {
    struct Account: Decodable {
        let status: String
        let creditLimit: Double
        let availableCredit: Double
        let usedCredit: Double
        let reserveBalance: Double
        let factoringRate: Double
        let advanceRate: Double
    }
    struct Period: Decodable {
        let invoicesSubmitted: Int
        let totalFactored: Double
        let feesCharged: Double
        let pendingPayments: Int
    }
    struct Activity: Decodable {
        let id: String
        let invoiceNumber: String?
        let status: String?
        let amount: Double
        let date: String
    }
    let account: Account
    let currentPeriod: Period
    let recentActivity: [Activity]
}

private struct FactoringInvoiceWire_394: Decodable {
    let id: String
    let invoiceNumber: String?
    let loadId: Int?
    let invoiceAmount: Double
    let advanceAmount: Double
    let factoringFee: Double
    let status: String?
    let submittedAt: String?
    let fundedAt: String?
    let collectedAt: String?
}

private struct FactoringRatesWire_394: Decodable {
    let standard: Double
    let quickPay: Double
    let sameDay: Double
    let currentRate: Double
    let advanceRate: Double
}

// MARK: - Body

private struct FactoringBody_394: View {
    @Environment(\.palette) private var palette

    // Live state — nil/empty until the real procs answer. No seeds.
    @State private var overview: FactoringOverviewWire_394? = nil
    @State private var rates: FactoringRatesWire_394? = nil
    @State private var invoices: [FactorInvoice_394] = []
    @State private var selectedIds: Set<String> = []
    @State private var loading: Bool = true
    @State private var loadError: String? = nil
    @State private var funding: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar_394
            IridescentHairline()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    }
                    heroCard_394
                    feeBand_394
                    invoicesSection_394
                    fundCTA_394
                    assuranceText_394
                    lastAdvanceStrip_394
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s3)
                .padding(.bottom, Space.s7)
            }
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    // MARK: Derived (live-only)

    private var availableDisplay: String {
        guard let a = overview?.account else { return "—" }
        return money_394(a.availableCredit)
    }
    private var eligibleCount: Int { invoices.count }
    private var advanceRatePct: Int {
        guard let r = overview?.account.advanceRate ?? rates?.advanceRate else { return 0 }
        return Int((r * 100).rounded())
    }
    private var factorFeeDisplay: String {
        guard let r = overview?.account.factoringRate ?? rates?.currentRate else { return "—" }
        return String(format: "%.1f%%", r * 100)
    }
    private var reserveHeldDisplay: String {
        guard let a = overview?.account else { return "—" }
        return money_394(a.reserveBalance)
    }
    private var selectedRows: [FactorInvoice_394] { invoices.filter { selectedIds.contains($0.id) } }
    private var selectedTotal: Double { selectedRows.reduce(0) { $0 + $1.advanceAmount } }
    private var selectedTotalDisplay: String { selectedRows.isEmpty ? "—" : money_394(selectedTotal) }

    // MARK: TopBar (inline — eyebrow / back / title / carrier)

    private var topBar_394: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ CATALYST · FACTORING · ADVANCE LINE")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("EusoQuickPay")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("Back to Wallet")
                Text("Factoring").font(EType.display).foregroundStyle(palette.textPrimary)
                Spacer()
            }
            .padding(.top, Space.s2)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    // MARK: Hero — available to advance + advance-rate gauge

    private var heroCard_394: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: Radius.xl - 1.5, style: .continuous).fill(palette.bgCard).padding(1.5)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AVAILABLE TO ADVANCE · TODAY")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Text(availableDisplay)
                        .font(.system(size: 38, weight: .bold).monospacedDigit())
                        .foregroundStyle(LinearGradient.diagonal)
                    (Text("across ")
                        + Text("\(eligibleCount)").fontWeight(.bold).foregroundColor(palette.textPrimary)
                        + Text(" factored invoices on file"))
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                advanceGauge_394
            }
            .padding(Space.s4)
        }
        .frame(height: 108)
    }

    private var advanceGauge_394: some View {
        ZStack {
            Circle().stroke(palette.textTertiary.opacity(0.20), lineWidth: 7)
            Circle().trim(from: 0, to: CGFloat(advanceRatePct) / 100)
                .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(advanceRatePct > 0 ? "\(advanceRatePct)%" : "—")
                    .font(.system(size: 18, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
                Text("ADV RATE")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .frame(width: 68, height: 68)
        .accessibilityLabel("Advance rate \(advanceRatePct) percent")
    }

    // MARK: Fee / reserve band

    private var feeBand_394: some View {
        HStack(spacing: 0) {
            bandStat_394("FACTOR FEE", factorFeeDisplay)
            bandDivider_394
            bandStat_394("RESERVE HELD", reserveHeldDisplay)
            bandDivider_394
            // No term/recourse field exists on factoring.getOverview/getRates —
            // honest em-dash, never an invented "Recourse · net-30".
            bandStat_394("TERM", "—")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s3)
        .frame(height: 48)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func bandStat_394(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(EType.micro).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 14, weight: .bold).monospacedDigit()).foregroundStyle(palette.textPrimary)
        }
        .padding(.trailing, 16)
    }

    private var bandDivider_394: some View {
        Rectangle().fill(palette.borderFaint).frame(width: 1, height: 24).padding(.trailing, 16)
    }

    // MARK: Eligible invoices

    private var invoicesSection_394: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("FACTORED INVOICES · LIVE")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if !invoices.isEmpty {
                    Button {
                        if selectedIds.count == invoices.count {
                            selectedIds.removeAll()
                        } else {
                            selectedIds = Set(invoices.map(\.id))
                        }
                    } label: {
                        Text(selectedIds.count == invoices.count ? "Clear all" : "Select all")
                            .font(.system(size: 11, weight: .heavy)).foregroundStyle(LinearGradient.primary)
                    }.buttonStyle(.plain)
                }
            }
            VStack(spacing: 0) {
                if loading && invoices.isEmpty {
                    Text("Loading invoices…")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, Space.s5)
                } else if invoices.isEmpty {
                    EusoEmptyState(
                        systemImage: "doc.text",
                        title: "No factored invoices yet",
                        subtitle: "Invoices you submit for factoring appear here with their advance state."
                    )
                    .padding(.vertical, Space.s3)
                } else {
                    ForEach(Array(invoices.enumerated()), id: \.element.id) { idx, inv in
                        invoiceRow_394(inv)
                        if idx < invoices.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.leading, 52)
                        }
                    }
                    Rectangle().fill(palette.borderFaint).frame(height: 1)
                    HStack {
                        Text("\(selectedIds.count) selected · advance total")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text(selectedTotalDisplay)
                            .font(.system(size: 15, weight: .bold).monospacedDigit())
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private func invoiceRow_394(_ inv: FactorInvoice_394) -> some View {
        let verified = inv.verify == .verified
        let isSelected = selectedIds.contains(inv.id)
        return Button {
            if isSelected { selectedIds.remove(inv.id) } else { selectedIds.insert(inv.id) }
        } label: {
            HStack(alignment: .top, spacing: Space.s3) {
                // doc/$ chip — gradient when verified, amber clock when pending
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill((verified ? Brand.blue : Brand.warning).opacity(0.14))
                    Image(systemName: verified ? "doc.text" : "clock")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(verified ? AnyShapeStyle(LinearGradient.primary)
                                                  : AnyShapeStyle(Brand.warning))
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(inv.shipper).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text(inv.idLane).font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Text(inv.statusLine).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(verified ? Brand.success : Brand.warning)
                }
                Spacer(minLength: Space.s2)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(inv.face).font(EType.bodyStrong).monospacedDigit().foregroundStyle(palette.textPrimary)
                    Text(inv.advance ?? "holding").font(EType.caption).monospacedDigit()
                        .foregroundStyle(inv.advance != nil ? palette.textSecondary : palette.textTertiary)
                    selectMark_394(isSelected)
                }
            }
            .padding(Space.s4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(inv.shipper), \(inv.face), \(isSelected ? "selected" : "not selected")")
    }

    private func selectMark_394(_ on: Bool) -> some View {
        Group {
            if on {
                ZStack {
                    Circle().fill(LinearGradient.primary)
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                }
            } else {
                Circle().strokeBorder(palette.textTertiary.opacity(0.40), lineWidth: 1.6)
            }
        }
        .frame(width: 18, height: 18)
    }

    // MARK: Fund CTA + assurance + last advance

    private var fundCTA_394: some View {
        CTAButton(
            title: selectedRows.isEmpty ? "Select invoices to advance" : "Advance \(selectedTotalDisplay) now",
            action: { fundSelected() },
            leadingIcon: "arrow.right",
            isLoading: funding
        )
        .disabled(selectedRows.isEmpty)
        .opacity(selectedRows.isEmpty ? 0.5 : 1.0)
        .accessibilityLabel(selectedRows.isEmpty ? "Select invoices to advance" : "Advance \(selectedTotalDisplay) now")
    }

    private var assuranceText_394: some View {
        HStack(alignment: .top) {
            Text("Advances settle to your EusoQuickPay wallet · reserve releases when the shipper pays the invoice.")
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.s2)
            Button { } label: {
                Text("Fee schedule").font(EType.micro).tracking(0.4).fontWeight(.heavy)
                    .foregroundStyle(LinearGradient.primary)
            }.buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var lastAdvanceStrip_394: some View {
        // Live: most recent funded row from getOverview.recentActivity.
        // Hidden entirely when there is no real advance history.
        if let last = overview?.recentActivity.first(where: { ($0.status ?? "").lowercased() == "funded" || ($0.status ?? "").lowercased() == "collected" }) {
            Button { } label: {
                HStack(spacing: Space.s3) {
                    ZStack {
                        Circle().fill(Brand.success.opacity(0.18))
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Brand.success)
                    }
                    .frame(width: 16, height: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last advance · \(money_394(last.amount))")
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Text("\(last.invoiceNumber ?? "—") · \((last.status ?? "—").uppercased()) · \(shortDate_394(last.date))")
                            .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.85)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(Space.s3)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Last advance \(money_394(last.amount)). View advance history.")
        }
    }

    // MARK: Actions

    private func fundSelected() {
        // factoring.instantPay (factoring.ts:882) is not yet bridged to the iOS
        // client — the CTA hands the REAL selected ids + total to the host
        // action layer and is disabled when nothing real is selected.
        guard !selectedRows.isEmpty else { return }
        NotificationCenter.default.post(
            name: .eusoCatalystFactoringFund_394, object: nil,
            userInfo: [
                "source": "394_CatalystFactoring",
                "amount": selectedTotal,
                "invoiceIds": selectedRows.map(\.id),
            ]
        )
    }

    // MARK: Network — live procs only (factoring.getOverview/getInvoices/getRates)

    private struct InvoicesInput_394: Encodable { let limit: Int; let offset: Int }

    private func loadAll() async {
        loading = true
        loadError = nil
        defer { loading = false }

        async let overviewTask: FactoringOverviewWire_394 =
            EusoTripAPI.shared.queryNoInput("factoring.getOverview")
        async let ratesTask: FactoringRatesWire_394 =
            EusoTripAPI.shared.queryNoInput("factoring.getRates")
        async let invoicesTask: [FactoringInvoiceWire_394] =
            EusoTripAPI.shared.query("factoring.getInvoices", input: InvoicesInput_394(limit: 20, offset: 0))

        do {
            let (ov, rt, rows) = try await (overviewTask, ratesTask, invoicesTask)
            overview = ov
            rates = rt
            invoices = rows.map { mapInvoice_394($0) }
            selectedIds.formIntersection(Set(invoices.map(\.id)))
        } catch {
            loadError = "Couldn't reach the factoring service - pull to retry."
        }
    }

    private func mapInvoice_394(_ w: FactoringInvoiceWire_394) -> FactorInvoice_394 {
        let status = (w.status ?? "").lowercased()
        let verified = ["approved", "funded", "collected"].contains(status)
        let loadRef = w.loadId.map { "LOAD #\($0)" } ?? "—"
        let submitted = w.submittedAt.map { shortDate_394($0) } ?? "—"
        return FactorInvoice_394(
            id: w.id,
            shipper: w.invoiceNumber ?? "Invoice \(w.id)",
            idLane: "\(loadRef) · submitted \(submitted)",
            statusLine: status.isEmpty ? "—" : status.replacingOccurrences(of: "_", with: " "),
            verify: verified ? .verified : .pending,
            face: money_394(w.invoiceAmount),
            advance: w.advanceAmount > 0 ? "adv \(money_394(w.advanceAmount))" : nil,
            advanceAmount: w.advanceAmount
        )
    }

    // MARK: Formatting

    private func money_394(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    private func shortDate_394(_ iso: String) -> String {
        iso.count >= 10 ? String(iso.prefix(10)) : (iso.isEmpty ? "—" : iso)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let eusoCatalystFactoringFund_394 = Notification.Name("eusoCatalystFactoringFund_394")
}

// MARK: - Previews

#Preview("394 · Catalyst · Factoring · Night") {
    CatalystFactoringScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("394 · Catalyst · Factoring · Afternoon") {
    CatalystFactoringScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
