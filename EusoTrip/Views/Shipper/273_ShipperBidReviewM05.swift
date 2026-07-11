//
//  273_ShipperBidReviewM05.swift
//  EusoTrip — Shipper · LIFECYCLE ECHO · BIDDING (M-05 chain).
//
//  Wireframe: 02 Shipper/Dark-SVG/273 Shipper Bid Review M05.svg
//  Archetype: DETAIL + bid leaderboard. Shows Diego the live board mid-
//  window — the cheapest quote at the top with a safety grade he can
//  trust, ranked below, and one tap to accept the leader.
//
//  Web peer: frontend/client/src/pages/shipper/loads/:id?tab=bids.
//  Wiring (on-disk confirmed):
//    • shippers.getLifecycleSnapshot EXISTS shippers.ts  → hero + window.
//    • shippers.getBidsForLoad       EXISTS shippers.ts  → the leaderboard
//      (catalyst-decorated: name, USDOT, safetyScore, amount, recommended).
//    • Accept leader → shippers.acceptBid EXISTS shippers.ts (awards + drops
//      the other bids; transitions loads.status → assigned).
//    • Counter      → bids triage surface (203) via nav-swap.
//  RBAC: shipperProcedure (companyId-owned). transportMode=truck · US.
//
//  Honest: rank + deltas are computed from the REAL bid amounts and the
//  posted target rate; the letter grade is derived from the server's
//  safetyScore. No fabricated win-rate percentages.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct ShipperBidReviewM05Screen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            VStack(alignment: .leading, spacing: Space.s4) {
                ShipperEchoSnapshotView(loadId: loadId, eyebrow: "SHIPPER · LOAD · BIDDING") { live in
                    BidReviewM05Body(live: live, loadId: loadId)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        } nav: {
            shipperLifecycleNav(currentSlot: .loads)
        }
    }
}

private struct BidReviewM05Body: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot
    let loadId: String

    @State private var bids: [ShipperAPI.Bid] = []
    @State private var loadedBids = false
    @State private var isAccepting = false
    @State private var actionError: String? = nil

    /// Cheapest-first — the composite the SVG leads with (price + grade).
    private var ranked: [ShipperAPI.Bid] { bids.sorted { $0.amount < $1.amount } }
    private var leader: ShipperAPI.Bid? { ranked.first }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            ShipperEchoHeader(
                eyebrow: "SHIPPER · LOAD · BIDDING",
                trailing: live.load.loadNumber,
                title: "Bid review"
            )
            heroCard
            ShipperEchoLifecycleStrip(active: .bidding, caption: ribbonCaption)
            leaderboardSection
            if !ranked.isEmpty { rationaleCard }
            ShipperEchoCTAPair(
                primaryTitle: leader.map { "Accept · \(usd0($0.amount))" } ?? "No quotes yet",
                primaryLoading: isAccepting,
                primaryAction: { Task { await acceptLeader() } },
                secondaryTitle: "Counter",
                secondaryAction: { shipperEchoNavSwap("203", loadId: loadId) }
            )
            if let err = actionError { errorBanner(err) }
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
                HStack(spacing: Space.s2) {
                    Text("BIDDING LIVE")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(LinearGradient.primary))
                    Text("\(distanceLabel) · \(dashIfEmpty(live.load.equipmentType))")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(palette.bgCardSoft))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .bottom) {
                    ShipperEchoStatCell(
                        label: leader.map { "LEADER · \(echoMonogram($0.catalystName))" } ?? "LEADER",
                        value: leader.map { usd0($0.amount) } ?? "—",
                        sub: leaderDeltaLine,
                        gradient: true
                    )
                    ShipperEchoStatCell(
                        label: "CLOSES IN",
                        value: relativeETA(from: live.load.biddingEnds),
                        sub: "\(bids.count) quotes in"
                    )
                    .frame(maxWidth: 130)
                }
            }
        }
    }

    @ViewBuilder
    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ShipperEchoSectionLabel(text: "LEADERBOARD · \(bids.count) QUOTES",
                                    trailing: bids.isEmpty ? nil : "SEE ALL")
            if ranked.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No quotes yet")
                        .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text("Carriers surface offers here as they come in. The board re-ranks on each new quote over the lifecycle channel.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            } else {
                ForEach(Array(ranked.prefix(5).enumerated()), id: \.element.id) { idx, bid in
                    bidRow(bid, rank: idx + 1, isLeader: idx == 0)
                }
            }
        }
    }

    private func bidRow(_ bid: ShipperAPI.Bid, rank: Int, isLeader: Bool) -> some View {
        let content = VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 40, height: 40)
                    Text(echoMonogram(bid.catalystName)).font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(bid.catalystName).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                    Text(echoAuthorityLine(dot: bid.dotNumber, mc: nil)).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
                    HStack(spacing: 6) {
                        chip(isLeader ? "TOP BID" : "RANK \(rank)", filled: isLeader)
                        chip("SAFETY \(gradeLetter(bid.safetyScore))", filled: false)
                        if bid.recommended { chip("ESANG", filled: false, tint: Brand.blue) }
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(usd0(bid.amount)).font(.system(size: 20, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                    Text(echoRatePerMile(rate: bid.amount, distance: live.load.distance))
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(isLeader ? Brand.success : palette.textSecondary)
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)

        return Group {
            if isLeader {
                content.background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(LinearGradient.primary, lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            } else {
                content.background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func chip(_ text: String, filled: Bool, tint: Color = Brand.blue) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy)).tracking(0.3)
            .foregroundStyle(filled ? AnyShapeStyle(Color.white) : AnyShapeStyle(tint))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(filled ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(tint.opacity(0.12)))
            .clipShape(Capsule())
    }

    private var rationaleCard: some View {
        var lines: [String] = []
        if let l = leader { lines.append("Leader \(l.catalystName) at \(usd0(l.amount)) · safety \(gradeLetter(l.safetyScore))") }
        if let rec = bids.first(where: { $0.recommended }) {
            lines.append("ESANG recommends \(rec.catalystName) — best composite of price, grade, history.")
        } else {
            lines.append("Ranked by composite: price, safety grade, and prior-lane history.")
        }
        return ShipperEchoRationaleCard(label: "RATIONALE", lines: lines)
    }

    private var ribbonCaption: String {
        bids.isEmpty ? "Bid window open · awaiting first quote"
                     : "\(bids.count) quotes in · ranked by composite (price + grade + history)"
    }
    private var distanceLabel: String { live.load.distance.map { "\(Int($0)) mi" } ?? "— mi" }

    private var leaderDeltaLine: String {
        guard let l = leader else { return "—" }
        var bits: [String] = []
        if let target = live.load.rate, target > 0 {
            let d = l.amount - target
            bits.append("\(d <= 0 ? "-" : "+")\(usd0(abs(d))) vs target")
        }
        if ranked.count >= 2 {
            let second = ranked[1].amount
            bits.append("\(usd0(second - l.amount)) lead")
        }
        return bits.isEmpty ? "top quote" : bits.joined(separator: " · ")
    }

    private func gradeLetter(_ score: Double) -> String {
        switch score {
        case 90...: return "A"
        case 80..<90: return "B"
        case 70..<80: return "C"
        default: return "D"
        }
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

    private func acceptLeader() async {
        guard let l = leader else { return }
        isAccepting = true; actionError = nil
        do {
            _ = try await EusoTripAPI.shared.shipper.acceptBid(loadId: loadId, bidId: l.id)
            shipperEchoNavSwap("205", loadId: loadId)
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        isAccepting = false
    }
}

#Preview("273 · Bid review · Night") {
    ShipperBidReviewM05Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("273 · Bid review · Afternoon") {
    ShipperBidReviewM05Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
