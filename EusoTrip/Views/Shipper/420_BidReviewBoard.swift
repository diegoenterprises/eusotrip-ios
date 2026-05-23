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

private enum BidKanbanColumn: String, CaseIterable, Identifiable {
    case bidding   = "Bidding"
    case awarded   = "Awarded"
    case inTransit = "In Transit"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .bidding:   return "tray.full"
        case .awarded:   return "checkmark.circle.fill"
        case .inTransit: return "truck.box.fill"
        }
    }
}

private struct BidReviewBody: View {
    @Environment(\.palette) private var palette

    @State private var biddingLanes: [BidReviewLane] = []
    @State private var awardedLoads: [ShipperAPI.MyLoad] = []
    @State private var transitLoads: [ShipperAPI.MyLoad] = []
    @State private var biddingLoading  = true
    @State private var awardedLoading  = true
    @State private var transitLoading  = true
    @State private var biddingError:  String? = nil
    @State private var awardedError:  String? = nil
    @State private var transitError:  String? = nil
    @State private var selectedColumn = BidKanbanColumn.bidding

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 6)
            columnScrubber.padding(.bottom, 6)
            columnPager
        }
        .task { await loadAll() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "tray.full")
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · BID REVIEW BOARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                let total = biddingLanes.count + awardedLoads.count + transitLoads.count
                if total > 0 {
                    Text("\(total) LOADS")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(palette.bgCard).clipShape(Capsule())
                }
            }
            Text("Bid board")
                .font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Track loads from open bid to delivery.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - Column scrubber

    private var columnScrubber: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(BidKanbanColumn.allCases) { col in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { selectedColumn = col }
                    } label: {
                        let count = colCount(col)
                        let on = selectedColumn == col
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: col.icon).font(.system(size: 9, weight: .heavy))
                                Text(col.rawValue.uppercased())
                                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            }
                            Text(count.map { "\($0)" } ?? "—")
                                .font(.system(size: 13, weight: .heavy)).monospacedDigit()
                        }
                        .foregroundStyle(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textSecondary))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(on ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func colCount(_ col: BidKanbanColumn) -> Int? {
        switch col {
        case .bidding:   return biddingLoading  ? nil : biddingLanes.count
        case .awarded:   return awardedLoading  ? nil : awardedLoads.count
        case .inTransit: return transitLoading  ? nil : transitLoads.count
        }
    }

    // MARK: - Column pager

    private var columnPager: some View {
        TabView(selection: $selectedColumn) {
            ForEach(BidKanbanColumn.allCases) { col in
                columnView(col).tag(col)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    @ViewBuilder
    private func columnView(_ col: BidKanbanColumn) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: 6) {
                    Text(col.rawValue.uppercased())
                        .font(.system(size: 13, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textPrimary)
                    Text("\(colCount(col) ?? 0)")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                    Spacer(minLength: 0)
                }
                switch col {
                case .bidding:   biddingContent
                case .awarded:   awardedContent
                case .inTransit: transitContent
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 6)
        }
    }

    // MARK: - Bidding column

    @ViewBuilder
    private var biddingContent: some View {
        if biddingLoading {
            columnSkeleton
        } else if let err = biddingError {
            columnError(err)
        } else if biddingLanes.isEmpty {
            EusoEmptyState(systemImage: "tray", title: "No bids in flight",
                           subtitle: "Loads in BIDDING status surface here once carriers start submitting offers.")
        } else {
            VStack(spacing: Space.s2) {
                ForEach(biddingLanes) { lane in
                    Button {
                        NotificationCenter.default.post(
                            name: .eusoShipperNavSwap, object: nil,
                            userInfo: ["screenId": "261", "loadId": lane.loadId]
                        )
                    } label: {
                        LifecycleCard(accentGradient: lane.bidsCount > 0) {
                            LifecycleSection(label: lane.loadNumber.uppercased(), icon: "doc.text")
                            LifecycleRow(label: "Lane",               value: dashIfEmpty(lane.lane))
                            LifecycleRow(label: "Bids in",            value: "\(lane.bidsCount)")
                            LifecycleRow(label: "Top bid",            value: usd(lane.topBid))
                            LifecycleRow(label: "Avg bid",            value: usd(lane.avgBid))
                            LifecycleRow(label: "ESANG · recommend",  value: dashIfEmpty(lane.recommendedCarrier))
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Awarded column

    @ViewBuilder
    private var awardedContent: some View {
        if awardedLoading {
            columnSkeleton
        } else if let err = awardedError {
            columnError(err)
        } else if awardedLoads.isEmpty {
            EusoEmptyState(systemImage: "checkmark.circle", title: "No awarded loads",
                           subtitle: "Loads where you've accepted a carrier bid appear here.")
        } else {
            VStack(spacing: Space.s2) {
                ForEach(awardedLoads, id: \.id) { load in
                    LifecycleCard(accentGradient: load.rate != nil) {
                        LifecycleSection(label: load.loadNumber.uppercased(), icon: "checkmark.circle.fill")
                        LifecycleRow(label: "Lane",    value: "\(load.originRef.city), \(load.originRef.state) → \(load.destinationRef.city), \(load.destinationRef.state)")
                        LifecycleRow(label: "Driver",  value: dashIfEmpty(load.driver?.name))
                        LifecycleRow(label: "Rate",    value: usd(load.rate))
                        LifecycleRow(label: "Pickup",  value: humanISO(load.pickupDate))
                    }
                }
            }
        }
    }

    // MARK: - In Transit column

    @ViewBuilder
    private var transitContent: some View {
        if transitLoading {
            columnSkeleton
        } else if let err = transitError {
            columnError(err)
        } else if transitLoads.isEmpty {
            EusoEmptyState(systemImage: "truck.box", title: "Nothing in transit",
                           subtitle: "Loads currently on the road appear here.")
        } else {
            VStack(spacing: Space.s2) {
                ForEach(transitLoads, id: \.id) { load in
                    LifecycleCard(accentGradient: true) {
                        LifecycleSection(label: load.loadNumber.uppercased(), icon: "truck.box.fill")
                        LifecycleRow(label: "Lane",       value: "\(load.originRef.city), \(load.originRef.state) → \(load.destinationRef.city), \(load.destinationRef.state)")
                        LifecycleRow(label: "Driver",     value: dashIfEmpty(load.driver?.name))
                        LifecycleRow(label: "Rate",       value: usd(load.rate))
                        LifecycleRow(label: "Est. del.",  value: humanISO(load.deliveryDate))
                    }
                }
            }
        }
    }

    // MARK: - Skeleton / error helpers

    private var columnSkeleton: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCard)
                    .frame(height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                    .opacity(0.6)
            }
        }
    }

    private func columnError(_ err: String) -> some View {
        LifecycleCard(accentDanger: true) {
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
        }
    }

    // MARK: - Fetches

    private func loadAll() async {
        async let a: Void = fetchBidding()
        async let b: Void = fetchAwarded()
        async let c: Void = fetchTransit()
        _ = await (a, b, c)
    }

    private func fetchBidding() async {
        biddingLoading = true; biddingError = nil
        do {
            let r: [BidReviewLane] = try await EusoTripAPI.shared.queryNoInput("shippers.getBidReviewBoard")
            biddingLanes = r
        } catch {
            biddingError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        biddingLoading = false
    }

    private func fetchAwarded() async {
        awardedLoading = true; awardedError = nil
        do {
            awardedLoads = try await EusoTripAPI.shared.shipper.getMyLoads(status: "awarded")
        } catch {
            awardedError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        awardedLoading = false
    }

    private func fetchTransit() async {
        transitLoading = true; transitError = nil
        do {
            transitLoads = try await EusoTripAPI.shared.shipper.getMyLoads(status: "in_transit")
        } catch {
            transitError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        transitLoading = false
    }
}

#Preview("420 · Bid review · Night") { BidReviewBoardScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("420 · Bid review · Afternoon") { BidReviewBoardScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
