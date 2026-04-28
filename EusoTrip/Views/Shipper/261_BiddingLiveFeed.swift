//
//  261_BiddingLiveFeed.swift
//  EusoTrip — Shipper · Stage 2 · BIDDING · live feed (refactored 2026-04-28).
//
//  Consumes `shippers.getLifecycleSnapshot` for the metrics + live bid
//  rows from `shippers.getBidsForLoad`. Accept-bid CTA mutates
//  `shippers.acceptBid`, refreshes both stores, advances the load to
//  AWARDED via the same call.
//

import SwiftUI

struct BiddingLiveFeedScreen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            LifecycleScaffold(
                loadId: loadId,
                eyebrow: "SHIPPER · BIDDING · LIVE · STAGE 2 OF 8",
                cycleStatus: "bidding"
            ) { live in
                BiddingBody(live: live, loadId: loadId)
            }
        } nav: {
            shipperLifecycleNav()
        }
    }
}

private struct BiddingBody: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot
    let loadId: String
    @StateObject private var bids = ShipperBidsStore()
    @State private var processingBidId: String? = nil
    @State private var actionError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            summaryStrip
            bidFeedCard
            if let err = actionError { errorBanner(err) }
        }
        .task {
            bids.setLoadId(loadId)
            await bids.refresh()
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "BIDS",     value: "\(live.bidsSummary.count)", icon: "hand.raised")
            LifecycleStatTile(label: "TOP BID",  value: usd0(live.bidsSummary.topBid), icon: "arrow.down.circle")
            LifecycleStatTile(label: "AVG",      value: usd0(live.bidsSummary.averageBid), icon: "scalemass")
        }
    }

    @ViewBuilder
    private var bidFeedCard: some View {
        switch bids.state {
        case .loading:
            LifecycleCard {
                LifecycleSection(label: "LIVE BID FEED", icon: "hand.raised")
                Text("Loading bids…").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        case .empty:
            LifecycleCard {
                LifecycleSection(label: "LIVE BID FEED", icon: "hand.raised")
                Text("No bids yet — carriers will surface offers as they come in.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .loaded(let rows):
            LifecycleCard {
                LifecycleSection(label: "LIVE BID FEED", icon: "hand.raised")
                VStack(spacing: 8) {
                    ForEach(rows) { bid in bidRow(bid) }
                }
            }
        case .error(let err):
            LifecycleCard(accentDanger: true) {
                LifecycleSection(label: "FEED ERROR", icon: "exclamationmark.triangle.fill")
                Text((err as? EusoTripAPIError)?.errorDescription ?? err.localizedDescription)
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func bidRow(_ bid: ShipperAPI.Bid) -> some View {
        HStack(spacing: 10) {
            Text(initials(bid.catalystName))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(LinearGradient.diagonal)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(bid.catalystName).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(dashIfEmpty(bid.dotNumber)).font(EType.mono(.micro)).tracking(0.4).foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(usd(bid.amount)).font(.system(size: 17, weight: .heavy)).foregroundStyle(palette.textPrimary).monospacedDigit()
                if bid.recommended {
                    Text("ESANG ★").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                }
            }
            Button {
                Task { await accept(bidId: bid.id) }
            } label: {
                if processingBidId == bid.id {
                    ProgressView().tint(.white).frame(width: 30, height: 30).background(LinearGradient.diagonal).clipShape(Circle())
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 30, height: 30).background(LinearGradient.diagonal).clipShape(Circle())
                }
            }.buttonStyle(.plain).disabled(processingBidId != nil)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(bid.recommended
                    ? AnyShapeStyle(LinearGradient(colors: [Brand.gradientStart.opacity(0.7), Brand.gradientEnd.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(palette.borderFaint),
                    lineWidth: bid.recommended ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func errorBanner(_ msg: String) -> some View {
        LifecycleCard(accentDanger: true) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.danger)
                Text(msg).font(EType.caption).foregroundStyle(Brand.danger)
                Spacer(minLength: 0)
            }
        }
    }

    private func accept(bidId: String) async {
        processingBidId = bidId
        actionError = nil
        do {
            _ = try await EusoTripAPI.shared.shippers.acceptBid(loadId: loadId, bidId: bidId)
            await bids.refresh()
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        processingBidId = nil
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)) }.joined().uppercased()
    }
}

#Preview("261 · Bidding · Live feed · Night") {
    BiddingLiveFeedScreen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}

#Preview("261 · Bidding · Live feed · Afternoon") {
    BiddingLiveFeedScreen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
