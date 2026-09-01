//
//  288_ShipperFreshMatrixPostedM07.swift
//  EusoTrip — Shipper · LIFECYCLE ECHO · POSTED (M-07 chain).
//
//  Wireframe: 02 Shipper/Dark-SVG/288 Shipper Fresh Matrix Posted M07.svg
//  Archetype: DETAIL — the calm landing page in the first hour after a
//  post. Opens the fresh M-07 chain (a dry-van general-cargo lane LA →
//  Phoenix, rotating away from the M-06 reefer): the load is live, the bid
//  window is running, and the moment the first quote lands the ribbon
//  breaks into Bidding. Equipment class + commodity are REAL snapshot data
//  (equipmentType / cargoType) — the dry-van-vs-reefer contrast is not
//  baked copy.
//
//  Web peer: frontend/client/src/pages/shipper/loads/:id (posted state).
//  Wiring (on-disk confirmed):
//    • shippers.getLifecycleSnapshot EXISTS shippers.ts:1216 → hero rate +
//      window + bids counter + spec (PRIMARY CONSUME).
//    • shippers.getBidsForLoad       EXISTS shippers.ts:761 → the incoming-
//      quote panel (empty pre-quote — honest "awaiting first quote").
//    • Edit load   → post-load editor (204, mode=edit) via nav-swap.
//    • Cancel post → loads.cancel     EXISTS loads.ts (allowed pre-award).
//  RBAC: shipperProcedure. transportMode=truck · country=US (USD · FMCSA).
//
//  Honest gap: the SVG's invited-catalyst roster (favorites with win-rates
//  + NOTIFIED chips) is not on the snapshot — the panel renders the REAL
//  incoming quotes and an honest awaiting-state instead of a fabricated
//  favorites list.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct ShipperFreshMatrixPostedM07Screen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            VStack(alignment: .leading, spacing: Space.s4) {
                ShipperEchoSnapshotView(loadId: loadId, eyebrow: "SHIPPER · LOAD · POSTED") { live in
                    PostedM07Body(live: live, loadId: loadId)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        } nav: {
            shipperLifecycleNav(currentSlot: .loads)
        }
    }
}

private struct PostedM07Body: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot
    let loadId: String

    @State private var bids: [ShipperAPI.Bid] = []
    @State private var loadedBids = false
    @State private var isCancelling = false
    @State private var cancelError: String? = nil

    private var closesIn: String { relativeETA(from: live.load.biddingEnds) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            ShipperEchoHeader(
                eyebrow: "SHIPPER · LOAD · POSTED",
                trailing: live.load.loadNumber,
                title: echoLaneCities(live)
            )
            heroCard
            ShipperEchoLifecycleStrip(active: .posted, caption: ribbonCaption)
            specSection
            quotesSection
            ShipperEchoCTAPair(
                primaryTitle: "Edit load",
                primaryAction: { shipperEchoNavSwap("204", loadId: loadId, mode: "edit") },
                secondaryTitle: isCancelling ? "Cancelling…" : "Cancel post",
                secondaryAction: { Task { await cancelPost() } }
            )
            if let err = cancelError { errorBanner(err) }
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
                HStack(alignment: .top) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle().fill(LinearGradient.diagonal).frame(width: 16, height: 16)
                            Circle().fill(.white).frame(width: 7, height: 7)
                        }
                        Text("JUST POSTED · BIDDING OPENS")
                            .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textPrimary)
                    }
                    Spacer(minLength: Space.s2)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("CLOSES IN").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textSecondary)
                        Text(closesIn).font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                    }
                }
                HStack(alignment: .bottom) {
                    ShipperEchoStatCell(
                        label: "TARGET RATE",
                        value: usd(live.load.rate),
                        sub: "linehaul · \(echoRatePerMile(rate: live.load.rate, distance: live.load.distance)) · \(distanceLabel)",
                        gradient: true
                    )
                    ShipperEchoStatCell(
                        label: "BIDS",
                        value: "\(live.bidsSummary.count)",
                        sub: live.bidsSummary.count == 0 ? "awaiting first" : "quotes in"
                    )
                    .frame(maxWidth: 120)
                }
            }
        }
    }

    private var specSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ShipperEchoSectionLabel(text: "LOAD SPEC · SHIPPER-OF-RECORD")
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Brand.blue.opacity(0.14)).frame(width: 40, height: 40)
                        Image(systemName: equipmentIcon).font(.system(size: 16, weight: .semibold)).foregroundStyle(LinearGradient.diagonal)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(equipmentTitle).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                        Text(specMono).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                }
                Divider().overlay(palette.borderFaint)
                HStack(alignment: .top, spacing: Space.s4) {
                    stopBlock(label: "PICKUP", facility: live.pickup?.facilityName ?? live.pickup?.city, window: live.load.pickupDate)
                    stopBlock(label: "DELIVERY", facility: live.delivery?.facilityName ?? live.delivery?.city, window: live.load.deliveryDate)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func stopBlock(label: String, facility: String?, window: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            Text(dashIfEmpty(facility)).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
            Text(humanISO(window)).font(.system(size: 10, weight: .medium)).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var quotesSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ShipperEchoSectionLabel(text: "INCOMING QUOTES · \(bids.count) IN",
                                    trailing: bids.isEmpty ? nil : "SEE ALL")
            if bids.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Awaiting first quote")
                        .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text("Your favorite catalysts were notified on post. The ribbon breaks into Bidding the moment the first quote lands over the lifecycle channel.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            } else {
                ForEach(bids.prefix(4)) { bid in
                    ShipperEchoPartyRow(
                        monogram: echoMonogram(bid.catalystName),
                        title: bid.catalystName,
                        authority: echoAuthorityLine(dot: bid.dotNumber, mc: nil),
                        pill: (usd0(bid.amount), .info)
                    )
                }
            }
        }
    }

    private var ribbonCaption: String {
        live.bidsSummary.count == 0
            ? "Awaiting first quote · favorite catalysts notified"
            : "\(live.bidsSummary.count) quotes in · ranked by composite"
    }

    private var distanceLabel: String { live.load.distance.map { "\(Int($0)) mi" } ?? "— mi" }
    private var equipmentTitle: String { dashIfEmpty(live.load.equipmentType) }
    private var specMono: String {
        var parts: [String] = []
        if let w = live.load.weight, w > 0 { parts.append("\(Int(w)) lb") }
        if let c = live.load.cargoType, !c.isEmpty { parts.append(c) }
        parts.append(distanceLabel)
        return parts.joined(separator: " · ")
    }

    /// SF Symbol keyed to the REAL equipment class — dry van rides a box,
    /// reefer a snowflake, flatbed a slab, tanker a drop. Honest for any
    /// posted load rather than a baked reefer glyph.
    private var equipmentIcon: String {
        let e = (live.load.equipmentType ?? "").lowercased()
        if e.contains("reefer") || e.contains("refriger") { return "snowflake" }
        if e.contains("flat")   { return "rectangle.split.3x1.fill" }
        if e.contains("tank")   { return "drop.fill" }
        if e.contains("hopper") || e.contains("bulk") { return "cylinder.fill" }
        return "shippingbox.fill"
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
            Text(msg).font(EType.caption).foregroundStyle(Brand.danger)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func cancelPost() async {
        isCancelling = true; cancelError = nil
        do {
            _ = try await EusoTripAPI.shared.loads.cancel(loadId: loadId, reason: nil)
            shipperEchoNavSwap("201")
        } catch {
            cancelError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        isCancelling = false
    }
}

#Preview("288 · Posted M07 · Night") {
    ShipperFreshMatrixPostedM07Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("288 · Posted M07 · Afternoon") {
    ShipperFreshMatrixPostedM07Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
