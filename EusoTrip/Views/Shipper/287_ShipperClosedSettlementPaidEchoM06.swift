//
//  287_ShipperClosedSettlementPaidEchoM06.swift
//  EusoTrip — Shipper · LIFECYCLE ECHO · CLOSED / SETTLEMENT-PAID (M-06).
//
//  Wireframe: 02 Shipper/Dark-SVG/287 Shipper Closed Settlement Paid Echo M06.svg
//  Archetype: MONEY / RECEIPT (terminal, read-only). Seals the M-06 chain
//  end-to-end (POSTED → CLOSED · port 8): Diego pays Aurora and the load
//  closes. A tall gradient-rimmed receipt hero leads with the paid amount,
//  the saving against target, and a chain-complete footline, then a full
//  settlement breakdown. Terminal read surface — the pay action ran
//  upstream (founder-initiated per the no-execute-money guardrail); this
//  screen only confirms the receipt.
//
//  Web peer: frontend/client/src/pages/shipper/loads/:id/settlement.
//  Wiring (on-disk confirmed):
//    • shippers.getSettlementForLoad EXISTS shippers.ts:1390 → status=paid,
//      amount, paidAt, source (PRIMARY CONSUME).
//    • shippers.getLifecycleSnapshot EXISTS shippers.ts:1216 → closed load
//      + carrier + lane + posted rate (for the saved-vs-target line).
//    • View receipt → settlement detail (227) via nav-swap.
//    • Open ledger  → invoices (437) via nav-swap.
//  READ-ONLY: no mutation fires. RBAC: shipperProcedure. US · USD.
//
//  Honest fan-out (per the SVG desc): at the terminal paid state the
//  shipper is NOT a `paid` push recipient — this surface learns the
//  closed/paid state via getSettlementForLoad + getLifecycleSnapshot
//  re-poll + the WS LOAD_STATE_CHANGE broadcast, not a Payment-Received
//  push. The "saved vs target" delta is computed from the real settlement
//  amount and posted rate; the method line renders the settlement `source`
//  verbatim, never a fabricated rail.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct ShipperClosedSettlementPaidEchoM06Screen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            VStack(alignment: .leading, spacing: Space.s4) {
                ShipperEchoSnapshotView(loadId: loadId, eyebrow: "SHIPPER · LOAD · CLOSED · PAID") { live in
                    ClosedPaidM06Body(live: live, loadId: loadId)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        } nav: {
            shipperLifecycleNav(currentSlot: .loads)
        }
    }
}

private struct ClosedPaidM06Body: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    let live: ShipperAPI.LifecycleSnapshot
    let loadId: String

    @State private var settlement: ShipperAPI.SettlementForLoad?
    @State private var loadedSettlement = false

    private var disc: String? {
        session.user?.name.flatMap { $0.isEmpty ? nil : echoMonogram($0) }
    }
    private var isPaid: Bool {
        (settlement?.status.lowercased().contains("paid") ?? false) || settlement?.paidAt != nil
    }
    private var paidAmount: Double? { settlement?.amount ?? live.load.rate }
    private var paidLabel: String { isPaid ? "PAID" : (settlement?.status.uppercased() ?? "SETTLING") }
    private var paidWhen: String { settlement?.paidAt.map { humanISO($0, format: "HH:mm") } ?? "—" }
    private var perMile: String { echoRatePerMile(rate: paidAmount, distance: live.load.distance) }
    private var distanceLabel: String { live.load.distance.map { "\(Int($0)) mi" } ?? "— mi" }
    private var methodLine: String {
        guard let src = settlement?.source, !src.isEmpty else { return "settlement rail" }
        return src
    }
    private var savedAmount: Double? {
        guard let a = paidAmount, let t = live.load.rate, t > 0 else { return nil }
        return t - a
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            ShipperEchoHeader(
                eyebrow: "SHIPPER · LOAD · CLOSED · PAID",
                trailing: live.load.loadNumber,
                title: echoLaneCities(live),
                showBack: true,
                discInitials: disc
            )
            receiptHero
            ShipperEchoLifecycleStrip(active: .closed, caption: ribbonCaption)
            breakdownCard
            carrierBadge
            ShipperEchoCTAPair(
                primaryTitle: "View receipt",
                primaryAction: { shipperEchoNavSwap("227", loadId: loadId) },
                secondaryTitle: "Open ledger",
                secondaryAction: { shipperEchoNavSwap("437", loadId: loadId) }
            )
        }
        .task {
            guard !loadedSettlement else { return }
            loadedSettlement = true
            settlement = (try? await EusoTripAPI.shared.shipper.getSettlementForLoad(loadId: loadId)) ?? nil
        }
    }

    // MARK: Receipt hero (gradient-rimmed, money-led)

    private var receiptHero: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: 8) {
                    heroBadge(paidLabel, tint: isPaid ? Brand.success : Brand.warning)
                    heroBadge("\(methodLine.uppercased()) · \(paidWhen)", tint: nil)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .bottom, spacing: Space.s3) {
                    Text(usd(paidAmount))
                        .font(.system(size: 40, weight: .bold)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("paid to \(live.carrier?.name ?? "carrier") · \(perMile)")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("\(distanceLabel) · linehaul")
                            .font(.system(size: 11, weight: .regular)).foregroundStyle(palette.textTertiary)
                        if let saved = savedAmount {
                            Text(saved >= 0 ? "−\(usd0(saved)) vs target · saved \(usd0(saved))" : "+\(usd0(-saved)) over target · grade-picked")
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(saved >= 0 ? Brand.success : Brand.warning)
                        }
                    }
                    Spacer(minLength: 0)
                }
                Divider().overlay(palette.borderFaint)
                Text("CHAIN COMPLETE · POSTED → CLOSED · next load opens linear")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
        }
    }

    private func heroBadge(_ text: String, tint: Color?) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
            .foregroundStyle(tint ?? palette.textPrimary)
            .lineLimit(1).minimumScaleFactor(0.7)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(tint?.opacity(0.20) ?? palette.bgCardSoft))
    }

    // MARK: Settlement breakdown

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ShipperEchoSectionLabel(text: "SETTLEMENT BREAKDOWN")
            VStack(spacing: 10) {
                breakdownRow(label: "Linehaul · \(distanceLabel) @ \(perMile)", value: usd0(live.load.rate), tone: .primary)
                Divider().overlay(palette.borderFaint)
                breakdownRow(label: "Accessorials · detention / tarp / lumper", value: usd0(live.accessorialTotal), tone: .primary)
                Divider().overlay(palette.borderFaint)
                breakdownRow(label: "Method · \(methodLine)", value: isPaid ? "paid \(paidWhen)" : "pending", tone: .secondary)
                if let saved = savedAmount {
                    Divider().overlay(palette.borderFaint)
                    breakdownRow(label: "vs target rate \(usd0(live.load.rate))", value: saved >= 0 ? "−\(usd0(saved))" : "+\(usd0(-saved))", tone: saved >= 0 ? .success : .warning)
                }
                Divider().overlay(palette.borderFaint)
                HStack(alignment: .firstTextBaseline) {
                    Text("PAID TO \((live.carrier?.name ?? "carrier").uppercased())")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: Space.s3)
                    Text(usd0(paidAmount)).font(.system(size: 15, weight: .bold)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private enum RowTone { case primary, secondary, success, warning }
    private func breakdownRow(label: String, value: String, tone: RowTone) -> some View {
        let valueColor: Color
        switch tone {
        case .primary:   valueColor = palette.textPrimary
        case .secondary: valueColor = palette.textPrimary
        case .success:   valueColor = Brand.success
        case .warning:   valueColor = Brand.warning
        }
        return HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: Space.s3)
            Text(value).font(.system(size: 12, weight: .bold)).monospacedDigit().foregroundStyle(valueColor)
        }
    }

    // MARK: Carrier badge

    private var carrierBadge: some View {
        ShipperEchoPartyRow(
            monogram: echoMonogram(live.carrier?.name),
            title: live.carrier?.name ?? "Awarded carrier",
            authority: echoAuthorityLine(dot: live.carrier?.dotNumber, mc: live.carrier?.mcNumber, place: live.driver.map { "driver \($0.name)" }),
            pill: (isPaid ? "PAID" : "SETTLING", isPaid ? .success : .warning),
            accent: Brand.escort
        )
    }

    private var ribbonCaption: String {
        isPaid ? "Paid in full \(paidWhen) · \(methodLine) · chain complete"
               : "Settlement in progress · \(usd0(paidAmount))"
    }
}

#Preview("287 · Closed settled M06 · Night") {
    ShipperClosedSettlementPaidEchoM06Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("287 · Closed settled M06 · Afternoon") {
    ShipperClosedSettlementPaidEchoM06Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
