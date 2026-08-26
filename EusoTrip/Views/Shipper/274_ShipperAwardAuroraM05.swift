//
//  274_ShipperAwardAuroraM05.swift
//  EusoTrip — Shipper · LIFECYCLE ECHO · AWARDED (M-05 chain).
//
//  Wireframe: 02 Shipper/Dark-SVG/274 Shipper Award Aurora M05.svg
//  Archetype: DETAIL + money-led outcomes ledger. Closes the bidding loop
//  in one decisive view: who won, what was saved against target, and the
//  underbidders surfaced with the amount each lost by.
//
//  Web peer: frontend/client/src/pages/shipper/loads/:id (awarded state).
//  Wiring (on-disk confirmed):
//    • shippers.getLifecycleSnapshot EXISTS shippers.ts → awarded carrier +
//      posted rate + lane.
//    • shippers.getBidsForLoad       EXISTS shippers.ts → the outcomes ledger
//      (awarded + lost quotes).
//    • View tender → load detail (205) via nav-swap (rate-con / tender pane).
//    • Message RM  → messaging (310) via nav-swap.
//      NOTE dispatcher.comms.openThread is a STUB on the web peer (named-gap
//      surfaced to the-oath); this routes to the real in-app messaging
//      surface rather than a dead tap.
//  RBAC: shipperProcedure (bid award gated to load.shipperCompanyId). US.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct ShipperAwardAuroraM05Screen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            VStack(alignment: .leading, spacing: Space.s4) {
                ShipperEchoSnapshotView(loadId: loadId, eyebrow: "SHIPPER · LOAD · AWARDED") { live in
                    AwardM05Body(live: live, loadId: loadId)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        } nav: {
            shipperLifecycleNav(currentSlot: .loads)
        }
    }
}

private struct AwardM05Body: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot
    let loadId: String

    @State private var bids: [ShipperAPI.Bid] = []
    @State private var loadedBids = false

    /// Awarded = the bid whose catalyst matches the assigned carrier;
    /// falls back to the cheapest quote, then to the posted rate — all
    /// honest, never fabricated.
    private var awardedBid: ShipperAPI.Bid? {
        if let name = live.carrier?.name, let m = bids.first(where: { $0.catalystName == name }) { return m }
        return bids.min(by: { $0.amount < $1.amount })
    }
    private var awardedAmount: Double? { awardedBid?.amount ?? live.load.rate }
    private var lostBids: [ShipperAPI.Bid] {
        bids.filter { $0.id != awardedBid?.id }.sorted { $0.amount < $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            ShipperEchoHeader(
                eyebrow: "SHIPPER · LOAD · AWARDED",
                trailing: live.load.loadNumber,
                title: awardTitle
            )
            heroCard
            ShipperEchoLifecycleStrip(active: .awarded, caption: ribbonCaption)
            outcomesSection
            rationaleCard
            ShipperEchoCTAPair(
                primaryTitle: "View tender",
                primaryAction: { shipperEchoNavSwap("205", loadId: loadId) },
                secondaryTitle: "Message",
                secondaryAction: { shipperEchoNavSwap("310", loadId: loadId) }
            )
        }
        .task {
            guard !loadedBids else { return }
            loadedBids = true
            bids = (try? await EusoTripAPI.shared.shipper.getBidsForLoad(loadId: loadId)) ?? []
        }
    }

    private var heroCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(Brand.escort).frame(width: 16, height: 16)
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .black)).foregroundStyle(.white)
                    }
                    Text("AWARDED · \(carrierMono) · TENDER SENT")
                        .font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .bottom) {
                    ShipperEchoStatCell(
                        label: "AWARD COMMITTED",
                        value: usd(awardedAmount),
                        sub: savedLine,
                        gradient: true
                    )
                    ShipperEchoStatCell(
                        label: "RATE / MI",
                        value: echoRatePerMile(rate: awardedAmount, distance: live.load.distance),
                        sub: "\(distanceLabel) linehaul"
                    )
                    .frame(maxWidth: 130)
                }
            }
        }
    }

    @ViewBuilder
    private var outcomesSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ShipperEchoSectionLabel(text: "BID OUTCOMES · \(bids.count) QUOTES")
            if bids.isEmpty {
                ShipperEchoPartyRow(
                    monogram: carrierMono,
                    title: live.carrier?.name ?? "Awarded carrier",
                    authority: echoAuthorityLine(dot: live.carrier?.dotNumber, mc: live.carrier?.mcNumber),
                    pill: ("Awarded", .success),
                    accent: Brand.escort
                )
            } else {
                if let a = awardedBid { outcomeRow(a, awarded: true) }
                ForEach(lostBids) { b in outcomeRow(b, awarded: false) }
            }
        }
    }

    private func outcomeRow(_ bid: ShipperAPI.Bid, awarded: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(awarded ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCardSoft)).frame(width: 40, height: 40)
                Text(echoMonogram(bid.catalystName)).font(.system(size: 12, weight: .heavy)).foregroundStyle(awarded ? .white : palette.textSecondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(bid.catalystName).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                Text(echoAuthorityLine(dot: bid.dotNumber, mc: nil)).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
                StatusPill(text: awarded ? "AWARDED" : "LOST", kind: awarded ? .success : .danger)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(usd0(bid.amount)).font(.system(size: 18, weight: .bold)).monospacedDigit()
                    .foregroundStyle(awarded ? palette.textPrimary : palette.textSecondary)
                Text(deltaVsWinner(bid, awarded: awarded))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(awarded ? Brand.success : palette.textTertiary)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(awarded ? AnyShapeStyle(Brand.escort.opacity(0.45)) : AnyShapeStyle(palette.borderFaint), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var rationaleCard: some View {
        var lines: [String] = []
        lines.append("Awarded \(live.carrier?.name ?? "carrier") · \(echoAuthorityLine(dot: live.carrier?.dotNumber, mc: live.carrier?.mcNumber))")
        if let saved = savedAmount { lines.append(saved >= 0 ? "Saved \(usd0(saved)) against the posted target." : "\(usd0(-saved)) over target — chosen on grade + history.") }
        if let d = live.driver?.name, !d.isEmpty { lines.append("Driver \(d) assigned · pickup \(humanISO(live.load.pickupDate)).") }
        return ShipperEchoRationaleCard(label: "AWARD RATIONALE", lines: lines)
    }

    private var carrierMono: String { echoMonogram(live.carrier?.name) }
    private var awardTitle: String { live.carrier.map { "Awarded · \($0.name.split(separator: " ").first.map(String.init) ?? $0.name)" } ?? "Awarded" }
    private var distanceLabel: String { live.load.distance.map { "\(Int($0)) mi" } ?? "— mi" }

    private var savedAmount: Double? {
        guard let a = awardedAmount, let t = live.load.rate, t > 0 else { return nil }
        return t - a
    }
    private var savedLine: String {
        guard let s = savedAmount else { return "committed · founder pin held" }
        return s >= 0 ? "saved \(usd0(s)) vs target · founder pin held" : "\(usd0(-s)) over target · grade-picked"
    }
    private var ribbonCaption: String {
        "\(live.carrier?.name ?? "Carrier") · pickup \(humanISO(live.load.pickupDate))"
    }

    private func deltaVsWinner(_ bid: ShipperAPI.Bid, awarded: Bool) -> String {
        if awarded {
            if let t = live.load.rate, t > 0 { let d = bid.amount - t; return "\(d <= 0 ? "-" : "+")\(usd0(abs(d))) vs target" }
            return "awarded"
        }
        guard let w = awardedAmount else { return "lost" }
        let d = bid.amount - w
        return "\(d >= 0 ? "+" : "-")\(usd0(abs(d))) vs winner"
    }
}

#Preview("274 · Award · Night") {
    ShipperAwardAuroraM05Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("274 · Award · Afternoon") {
    ShipperAwardAuroraM05Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
