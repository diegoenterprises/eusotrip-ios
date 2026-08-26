//
//  270_ShipperPaperworkEchoM04.swift
//  EusoTrip — Shipper · LIFECYCLE ECHO · PAPERWORK (M-04 chain).
//
//  Wireframe: 02 Shipper/Dark-SVG/270 Shipper Paperwork Echo M04.svg
//  Archetype: MONEY / read-only monitoring. Diego sees the delivered load
//  with POD received, BOL final, invoice on terms, and settlement queued —
//  the paperwork stage held until settlement completes.
//
//  Web peer: client/src/pages/PODManagement.tsx + SettlementDetails.tsx.
//  Wiring (on-disk confirmed):
//    • shippers.getLifecycleSnapshot EXISTS shippers.ts → delivered load +
//      carrier + lane (PRIMARY CONSUME).
//    • shippers.getSettlementForLoad EXISTS shippers.ts → invoice status,
//      amount, payable date (CONSUMED).
//    • View POD   → POD receipt (248) · Invoice → invoices (437) ·
//      Open Load → load detail (205), all via nav-swap.
//  READ-ONLY: no mutation fires from this echo. RBAC: shipperProcedure. US.
//
//  Honest gap: the SVG's driver-payout / catalyst-margin figures are
//  carrier-internal and not on the shipper snapshot — the roster shows the
//  shipper-vantage ledger (POD · BOL · invoice · settlement) only.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct ShipperPaperworkEchoM04Screen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            VStack(alignment: .leading, spacing: Space.s4) {
                ShipperEchoSnapshotView(loadId: loadId, eyebrow: "SHIPPER · LOADS · PAPERWORK · ECHO") { live in
                    PaperworkEchoM04Body(live: live, loadId: loadId)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        } nav: {
            shipperLifecycleNav(currentSlot: .loads)
        }
    }
}

private struct PaperworkEchoM04Body: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    let live: ShipperAPI.LifecycleSnapshot
    let loadId: String

    @State private var settlement: ShipperAPI.SettlementForLoad?
    @State private var loadedSettlement = false

    private var disc: String? {
        session.user?.name.flatMap { $0.isEmpty ? nil : echoMonogram($0) }
    }
    private var podReceived: Bool {
        let s = live.load.status.lowercased()
        return s.contains("delivered") || s.contains("pod") || s.contains("invoiced") || s.contains("paid") || s.contains("closed")
    }
    private var invoiceLabel: String {
        guard let st = settlement else { return "QUEUED" }
        let s = st.status.lowercased()
        if s.contains("paid") { return "PAID" }
        if s.contains("invoiced") || s.contains("net") { return "NET-30" }
        return st.status.uppercased()
    }
    private var settleLabel: String {
        guard let st = settlement else { return "QUEUED" }
        return st.status.lowercased().contains("paid") ? "PAID" : "QUEUED"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            ShipperEchoHeader(
                eyebrow: "SHIPPER · LOADS · PAPERWORK · ECHO",
                trailing: "PAPERWORK · SETTLING",
                title: "Paperwork · settling",
                subtitle: "\(live.load.loadNumber) · \(echoLaneCities(live)) · invoice \(invoiceLabel.lowercased())",
                showBack: true,
                discInitials: disc
            )
            ShipperEchoSettlementStrip(cells: [
                .init(label: "POD", value: podReceived ? "RECEIVED" : "PENDING", sub: podReceived ? "delivered" : "awaiting"),
                .init(label: "INVOICE", value: invoiceLabel, sub: usd0(settlement?.amount)),
                .init(label: "SETTLE", value: settleLabel, sub: settlement?.payableDate.map { humanISO($0, format: "MMM d") } ?? "—")
            ])
            kpiQuartet
            ShipperEchoLifecycleStrip(active: .paperwork, caption: ribbonCaption)
            carrierSection
            rosterCard
            ShipperEchoTripleCTA(
                primaryTitle: "View POD",
                primaryAction: { shipperEchoNavSwap("248", loadId: loadId) },
                secondaryTitle: "Invoice",
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
            quadCell("STAGE", "PAPERWORK", "ringed")
            quadDivider
            quadCell("POD", podReceived ? "RECEIVED" : "PENDING", "shipper vantage")
            quadDivider
            quadCell("INVOICE", usd0(settlement?.amount), invoiceLabel)
            quadDivider
            quadCell("SETTLE", settleLabel, settlement?.payableDate.map { humanISO($0, format: "MMM d") } ?? "—")
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
                detail: live.driver.map { "Driver \($0.name) · delivered · POD signed" },
                pill: ("DELIVERED", .success),
                accent: Brand.escort
            )
        }
    }

    private var rosterCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShipperEchoSectionLabel(text: "PAPERWORK ECHO", trailing: "QUARTET 4/4")
            VStack(spacing: 8) {
                ShipperEchoRosterRow(label: "POD", value: podReceived ? "RECEIVED" : "PENDING")
                Divider().overlay(palette.borderFaint)
                ShipperEchoRosterRow(label: "BOL", value: podReceived ? "FINAL" : "IN TRANSIT")
                Divider().overlay(palette.borderFaint)
                ShipperEchoRosterRow(label: "INVOICE", value: "\(invoiceLabel) · \(usd0(settlement?.amount))")
                Divider().overlay(palette.borderFaint)
                ShipperEchoRosterRow(label: "NEXT STEP", value: "settlement → closed")
                Divider().overlay(palette.borderFaint)
                ShipperEchoRosterRow(label: "SNAPSHOT SOURCE", value: "getLifecycleSnapshot · getSettlementForLoad", accent: true)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var ribbonCaption: String {
        let recv = live.delivery?.facilityName ?? live.delivery?.city ?? "consignee"
        return "Delivered at \(recv) · invoice \(invoiceLabel) · settlement \(settleLabel.lowercased())"
    }
}

#Preview("270 · Paperwork echo · Night") {
    ShipperPaperworkEchoM04Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("270 · Paperwork echo · Afternoon") {
    ShipperPaperworkEchoM04Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
