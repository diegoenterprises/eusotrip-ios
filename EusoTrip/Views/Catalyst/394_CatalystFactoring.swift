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
//  Shipper-of-record on each invoice = Diego Usoro / Eusorone Technologies (§11).
//
//  Wiring manifest (tRPC procedures, line-confirmed on disk this fire). None
//  of these are surfaced as iOS EusoTripAPI.shared.factoring clients yet —
//  the wired client exposes only getOffer(loadId:) / accept(loadId:offerId:).
//  We therefore keep the canonical representative seeds (house "0% mock —
//  seeds overwritten on hydrate") and leave one WIRE marker per missing call:
//    • hero available + reserve   → factoring.getOverview        (factoring.ts:392)
//                                   + factoring.getReserveBalance (factoring.ts:590)
//    • fee / rate band            → factoring.getRates           (factoring.ts:1000)
//                                   + factoring.getFeeSchedule    (factoring.ts:686)
//    • eligible-invoice rows      → factoring.getInvoices        (factoring.ts:424)
//                                   + factoring.getInvoiceStatus  (factoring.ts:497)
//    • "Advance now" CTA          → factoring.instantPay         (factoring.ts:878)
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

// MARK: - Seed model (canonical fixture — overwritten on hydrate)

private struct FactorInvoice_394: Identifiable {
    enum Verify { case verified, pending }
    let id: String
    let shipper: String
    let idLane: String
    let statusLine: String
    let verify: Verify
    let face: String
    let advance: String?   // nil when holding
    let selected: Bool
}

private struct FactoringVM_394 {
    let available: String
    let eligibleCount: Int
    let advanceRatePct: Int
    let factorFee: String
    let reserveHeld: String
    let term: String
    let invoices: [FactorInvoice_394]
    let selectedCount: Int
    let selectedTotal: String
    let lastAdvanceTitle: String
    let lastAdvanceSub: String
}

private let seedFactoring_394 = FactoringVM_394(
    available: "$11,420", eligibleCount: 4, advanceRatePct: 96,
    factorFee: "1.8%", reserveHeld: "$476", term: "Recourse · net-30",
    invoices: [
        FactorInvoice_394(id: "LD-260427-A38FB12C7E", shipper: "Diego Usoro · Eusorone",
                          idLane: "LD-260427-A38FB12C7E · Houston → Dallas",
                          statusLine: "POD signed · verified 14 min ago", verify: .verified,
                          face: "$1,900", advance: "adv $1,824", selected: true),
        FactorInvoice_394(id: "LD-260427-B41782FF02", shipper: "Diego Usoro · Eusorone",
                          idLane: "LD-260427-B41782FF02 · KC → Omaha",
                          statusLine: "POD signed · escort verified · no detention", verify: .verified,
                          face: "$3,200", advance: "adv $3,072", selected: true),
        FactorInvoice_394(id: "LD-260427-DA1592B7CC", shipper: "Diego Usoro · Eusorone",
                          idLane: "LD-260427-DA1592B7CC · Pittsburgh → Cleveland",
                          statusLine: "POD uploaded · auto-verify in progress", verify: .pending,
                          face: "$2,200", advance: nil, selected: false),
    ],
    selectedCount: 2, selectedTotal: "$4,896",
    lastAdvanceTitle: "Last advance · $2,112 funded",
    lastAdvanceSub: "LD-260427-7C3A09F18B · reserve $88 pending · 2 days ago"
)

// MARK: - Body

private struct FactoringBody_394: View {
    @Environment(\.palette) private var palette

    @State private var vm: FactoringVM_394 = seedFactoring_394
    @State private var funding: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar_394
            IridescentHairline()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
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
    }

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
                    Text(vm.available)
                        .font(.system(size: 38, weight: .bold).monospacedDigit())
                        .foregroundStyle(LinearGradient.diagonal)
                    (Text("across ")
                        + Text("\(vm.eligibleCount)").fontWeight(.bold).foregroundColor(palette.textPrimary)
                        + Text(" POD-cleared invoices · funds in ~2 min"))
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
            Circle().trim(from: 0, to: CGFloat(vm.advanceRatePct) / 100)
                .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(vm.advanceRatePct)%")
                    .font(.system(size: 18, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
                Text("ADV RATE")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .frame(width: 68, height: 68)
        .accessibilityLabel("Advance rate \(vm.advanceRatePct) percent")
    }

    // MARK: Fee / reserve band

    private var feeBand_394: some View {
        HStack(spacing: 0) {
            bandStat_394("FACTOR FEE", vm.factorFee)
            bandDivider_394
            bandStat_394("RESERVE HELD", vm.reserveHeld)
            bandDivider_394
            bandStat_394("TERM", vm.term)
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
                Text("ELIGIBLE INVOICES · POD CLEARED")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Button { } label: {
                    Text("Select all").font(.system(size: 11, weight: .heavy)).foregroundStyle(LinearGradient.primary)
                }.buttonStyle(.plain)
            }
            VStack(spacing: 0) {
                ForEach(Array(vm.invoices.enumerated()), id: \.element.id) { idx, inv in
                    invoiceRow_394(inv)
                    if idx < vm.invoices.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.leading, 52)
                    }
                }
                Rectangle().fill(palette.borderFaint).frame(height: 1)
                HStack {
                    Text("\(vm.selectedCount) selected · advance total")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(vm.selectedTotal)
                        .font(.system(size: 15, weight: .bold).monospacedDigit())
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private func invoiceRow_394(_ inv: FactorInvoice_394) -> some View {
        let verified = inv.verify == .verified
        return HStack(alignment: .top, spacing: Space.s3) {
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
                selectMark_394(inv.selected)
            }
        }
        .padding(Space.s4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(inv.shipper), \(inv.face), \(inv.selected ? "selected" : "not selected")")
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
            title: "Advance \(vm.selectedTotal) now",
            action: { fundSelected() },
            leadingIcon: "arrow.right",
            isLoading: funding
        )
        .accessibilityLabel("Advance \(vm.selectedTotal) now")
    }

    private var assuranceText_394: some View {
        HStack(alignment: .top) {
            Text("Funds land in your EusoQuickPay wallet in ~2 min · 4% reserve released automatically when Eusorone pays on net-30.")
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.s2)
            Button { } label: {
                Text("Fee schedule").font(EType.micro).tracking(0.4).fontWeight(.heavy)
                    .foregroundStyle(LinearGradient.primary)
            }.buttonStyle(.plain)
        }
    }

    private var lastAdvanceStrip_394: some View {
        Button { } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle().fill(Brand.success.opacity(0.18))
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Brand.success)
                }
                .frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.lastAdvanceTitle).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text(vm.lastAdvanceSub).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
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
        .accessibilityLabel("\(vm.lastAdvanceTitle). View advance history.")
    }

    // MARK: Actions

    private func fundSelected() {
        // WIRE: factoring.instantPay (factoring.ts:878) — writes a paymentLedger
        // row + blockchainAudit row, broadcasts WS_EVENTS.FACTORING_ADVANCE_FUNDED
        // on WS_CHANNELS.catalyst(carrierId). The wired iOS client surfaces only
        // factoring.getOffer / factoring.accept, so the advance stays a no-op
        // until instantPay is exposed on EusoTripAPI.shared.factoring.
        NotificationCenter.default.post(
            name: .eusoCatalystFactoringFund_394, object: nil,
            userInfo: ["source": "394_CatalystFactoring", "amount": vm.selectedTotal]
        )
    }

    // MARK: Network — seeds overwritten on hydrate

    private func loadAll() async {
        // WIRE: factoring.getOverview (factoring.ts:392) + factoring.getReserveBalance (factoring.ts:590) — hero available + reserve
        // WIRE: factoring.getRates (factoring.ts:1000) + factoring.getFeeSchedule (factoring.ts:686) — fee / rate band
        // WIRE: factoring.getInvoices (factoring.ts:424) + factoring.getInvoiceStatus (factoring.ts:497) — eligible-invoice rows
        // EusoTripAPI.shared.factoring exposes only getOffer(loadId:) / accept(loadId:offerId:)
        // (verified in Services/EusoTripAPI.swift:5548–5591). Until the carrier-scope
        // factoring.* procedures above are surfaced as iOS clients, the canonical
        // seeds (0% mock — overwritten on hydrate) stand as the representative figures.
        vm = seedFactoring_394
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
