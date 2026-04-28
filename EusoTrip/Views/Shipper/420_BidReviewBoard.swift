//
//  420_BidReviewBoard.swift
//  EusoTrip — Shipper · Bid review board (cross-load).
//

import SwiftUI

struct BidReviewBoardScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { BidReviewBody() } nav: { shipperLifecycleNav() }
    }
}

private struct BidReviewLane: Decodable, Identifiable, Hashable {
    let loadId: String
    let loadNumber: String
    let lane: String?
    let bidsCount: Int
    let topBid: Double?
    let avgBid: Double?
    let recommendedCarrier: String?
    var id: String { loadId }
}

private struct BidReviewBody: View {
    @Environment(\.palette) private var palette
    @State private var lanes: [BidReviewLane] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "tray.full").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · BID REVIEW BOARD").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("All open bids").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Compare bids across every BIDDING-status load. Tap a row to drill into the load's bid feed.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading bid board…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if lanes.isEmpty { EusoEmptyState(systemImage: "tray", title: "No bids in flight", subtitle: "Loads in BIDDING status surface here once carriers start submitting offers.") }
        else {
            ForEach(lanes) { lane in
                Button {
                    NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "261", "loadId": lane.loadId])
                } label: {
                    LifecycleCard(accentGradient: lane.bidsCount > 0) {
                        LifecycleSection(label: lane.loadNumber.uppercased(), icon: "doc.text")
                        LifecycleRow(label: "Lane",                  value: dashIfEmpty(lane.lane))
                        LifecycleRow(label: "Bids in",                value: "\(lane.bidsCount)")
                        LifecycleRow(label: "Top bid",                value: usd(lane.topBid))
                        LifecycleRow(label: "Avg bid",                value: usd(lane.avgBid))
                        LifecycleRow(label: "ESANG · recommended",    value: dashIfEmpty(lane.recommendedCarrier))
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [BidReviewLane] = try await EusoTripAPI.shared.api.queryNoInput("shippers.getBidReviewBoard")
            lanes = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("420 · Bid review · Night") { BidReviewBoardScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("420 · Bid review · Afternoon") { BidReviewBoardScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
