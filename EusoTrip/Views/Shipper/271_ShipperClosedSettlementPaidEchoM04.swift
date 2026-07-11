//
//  271_ShipperClosedSettlementPaidEchoM04.swift
//  EusoTrip — Shipper · LIFECYCLE ECHO · CLOSED / SETTLEMENT-PAID (M-04).
//
//  Wireframe: 02 Shipper/Dark-SVG/271 Shipper Closed Settlement Paid Echo M04.svg
//  Archetype: MONEY / terminal read-only. Diego sees the load paid in full —
//  POD received, BOL final, invoice PAID, settlement PAID. CLOSED is terminal;
//  the ring rolled here at the prior paperwork→closed transition.
//
//  Web peer: client/src/pages/SettlementDetails.tsx + SettlementHistory.tsx.
//  Wiring (on-disk confirmed):
//    • shippers.getSettlementForLoad EXISTS shippers.ts → status=paid,
//      amount, paidAt (PRIMARY CONSUME).
//    • shippers.getLifecycleSnapshot EXISTS shippers.ts → closed load + carrier.
//    • View Settlement → settlement detail (227) · Receipt → invoices (437) ·
//      Open Load → load detail (205), all via nav-swap.
//  READ-ONLY: no mutation fires. RBAC: shipperProcedure. US.
//
//  Honest fan-out note (from the SVG desc): at the terminal paid state the
//  shipper is NOT a `paid` push recipient (loadLifecycle.ts paid userFields
//  = catalyst + driver only). This screen learns the closed/paid state via
//  getSettlementForLoad + getLifecycleSnapshot re-poll + the WS
//  LOAD_STATE_CHANGE broadcast — not a Payment Received push.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct ShipperClosedSettlementPaidEchoM04Screen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            VStack(alignment: .leading, spacing: Space.s4) {
                ShipperEchoSnapshotView(loadId: loadId, eyebrow: "SHIPPER · LOADS · CLOSED · ECHO") { live in
                    ClosedPaidM04Body(live: live, loadId: loadId)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        } nav: {
            shipperLifecycleNav(currentSlot: .loads)
        }
    }
}

private struct ClosedPaidM04Body: View {
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
    private var paidLabel: String { isPaid ? "PAID" : (settlement?.status.uppercased() ?? "SETTLING") }
    private var paidWhen: String { settlement?.paidAt.map { humanISO($0, format: "MMM d · HH:mm") } ?? "—" }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            ShipperEchoHeader(
                eyebrow: "SHIPPER · LOADS · CLOSED · ECHO",
                trailing: "CLOSED · SETTLED",
                title: "Closed · settled",
                subtitle: "\(live.load.loadNumber) · \(echoLaneCities(live)) · invoice \(paidLabel.lowercased())",
                showBack: true,
                discInitials: disc
            )
            ShipperEchoSettlementStrip(cells: [
                .init(label: "POD", value: "RECEIVED", sub: "delivered"),
                .init(label: "INVOICE", value: paidLabel, sub: usd0(settlement?.amount)),
                .init(label: "SETTLE", value: paidLabel, sub: settlement?.paidAt.map { humanISO($0, format: "MMM d") } ?? "—")
            ])
            kpiQuartet
            ShipperEchoLifecycleStrip(active: .closed, caption: ribbonCaption)
            carrierSection
            rosterCard
            ShipperEchoTripleCTA(
                primaryTitle: "View settlement",
                primaryAction: { shipperEchoNavSwap("227", loadId: loadId) },
                secondaryTitle: "Receipt",
                secondaryAction: { shipperEchoNavSwap("437", loadId: loadId) },
                tertiaryTitle: "Open",
                tertiaryAction: { shipperEchoNavSwap("205", loadId: loadId) }
            )
        }
        .task {
            guard !loadedSettlement else { return }
            loadedSettlement = true
            settlement = (try? await EusoTripAPI.shared.shipper.getSettlementForLoad(loadId: loadId)) ?? nil
        }
    }

    private var kpiQuartet: some View {
        HStack(spacing: 0) {
            quadCell("STAGE", "CLOSED", "terminal")
            quadDivider
            quadCell("POD", "RECEIVED", "shipper vantage")
            quadDivider
            quadCell("INVOICE", usd0(settlement?.amount), paidLabel)
            quadDivider
            quadCell("SETTLE", paidLabel, paidWhen == "—" ? "—" : "paid")
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.6), lineWidth: 1.25))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private func quadCell(_ label: String, _ value: String, _ sub: String) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 13, weight: .heavy)).foregroundStyle(Brand.magenta.opacity(0.85))
                .lineLimit(1).minimumScaleFactor(0.55)
            Text(sub).font(.system(size: 8, weight: .medium)).foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
    private var quadDivider: some View { Rectangle().fill(palette.borderFaint).frame(width: 1, height: 34) }

    private var carrierSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ShipperEchoSectionLabel(text: "CATALYST · CARRIER")
            ShipperEchoPartyRow(
                monogram: echoMonogram(live.carrier?.name),
                title: live.carrier?.name ?? "Awarded carrier",
                authority: echoAuthorityLine(dot: live.carrier?.dotNumber, mc: live.carrier?.mcNumber),
                detail: live.driver.map { "Driver \($0.name) · settled" },
                pill: (isPaid ? "PAID" : "SETTLING", isPaid ? .success : .warning),
                accent: Brand.escort
            )
        }
    }

    private var rosterCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShipperEchoSectionLabel(text: "CLOSED ECHO", trailing: "QUARTET 4/4")
            VStack(spacing: 8) {
                ShipperEchoRosterRow(label: "INVOICE", value: "\(paidLabel) · \(usd0(settlement?.amount)) · \(paidWhen)")
                Divider().overlay(palette.borderFaint)
                ShipperEchoRosterRow(label: "POD / BOL", value: "POD received · BOL final")
                Divider().overlay(palette.borderFaint)
                ShipperEchoRosterRow(label: "STATUS", value: live.load.status.uppercased())
                Divider().overlay(palette.borderFaint)
                ShipperEchoRosterRow(label: "NEXT STEP", value: "chain closed · terminal")
                Divider().overlay(palette.borderFaint)
                ShipperEchoRosterRow(label: "SNAPSHOT SOURCE", value: "getSettlementForLoad · getLifecycleSnapshot", accent: true)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var ribbonCaption: String {
        isPaid ? "Paid in full \(paidWhen) · chain closed" : "Settlement in progress · \(usd0(settlement?.amount))"
    }
}

#Preview("271 · Closed settled · Night") {
    ShipperClosedSettlementPaidEchoM04Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("271 · Closed settled · Afternoon") {
    ShipperClosedSettlementPaidEchoM04Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
