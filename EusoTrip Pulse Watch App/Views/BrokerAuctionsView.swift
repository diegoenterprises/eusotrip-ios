//
//  BrokerAuctionsView.swift
//  EusoTrip Watch App
//
//  Broker persona — a compact board of their active load auctions:
//  current high bid, time remaining, number of bidders. Tapping a row
//  opens LoadAuctionView where the broker can accept the high bid or
//  hand off to iPhone for deeper review.
//

import SwiftUI
import Combine
import WatchKit

struct BrokerAuctionItem: Identifiable, Equatable {
    let id: String
    let loadId: String
    let displayId: String
    let lane: String
    let highBid: Double?
    let bidders: Int
    let endsAt: Date
}

@MainActor
final class BrokerAuctionsStore: ObservableObject {
    static let shared = BrokerAuctionsStore()
    /// No seed data. Doctrine: no mocks, no fake load ids. The
    /// broker's live auction list lives on the web platform's
    /// richer auction surface; the wrist mirrors whatever the
    /// server's broker-scoped loadBidding feed returns today and
    /// an empty state otherwise. The previous seed rows (LD-48301
    /// / LD-48288 / LD-48254) were visible in production and
    /// misleading.
    @Published var auctions: [BrokerAuctionItem] = []
    @Published var hasLoadedOnce: Bool = false
    @Published var lastError: String?

    func refresh(auth: AuthStore) async {
        guard auth.isSignedIn else {
            lastError = "Sign in on your iPhone"
            return
        }
        do {
            let client = EsangClient(auth: auth)
            // `loadBidding.getReceivedBids` is the real server-side
            // proc that returns the bids a broker is currently
            // receiving on their loads — the closest equivalent to
            // the "active auctions I'm running" view. Verified at
            // `frontend/server/routers/loadBidding.ts:117`. We pass
            // no filter so we get the default "open bids on my
            // loads" slice.
            let data = try await client.queryJSON(
                "loadBidding.getReceivedBids",
                input: ["limit": 10]
            )
            struct Envelope: Decodable {
                struct Result: Decodable {
                    struct DataContainer: Decodable {
                        let json: [RemoteBid]
                    }
                    let data: DataContainer
                }
                let result: Result
            }
            /// Mirror of the server's received-bid row. All fields
            /// optional — the broker's feed is broader than a
            /// single-auction shape and we render whatever subset
            /// the server returned.
            struct RemoteBid: Decodable {
                let id: String?
                let loadId: String?
                let displayId: String?
                let loadNumber: String?
                let origin: String?
                let destination: String?
                let lane: String?
                let highBid: Double?
                let bidAmount: Double?
                let bidders: Int?
                let biddersCount: Int?
                let endsAt: String?
                let expiresAt: String?
            }
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            // Coalesce by loadId so multiple bids on the same load
            // show as a single wrist row with the high bid.
            var byLoad: [String: BrokerAuctionItem] = [:]
            for b in env.result.data.json {
                let loadId = b.loadId ?? b.loadNumber ?? b.id ?? UUID().uuidString
                let displayId = b.displayId ?? b.loadNumber ?? loadId
                let lane = b.lane ?? [b.origin, b.destination].compactMap { $0 }.joined(separator: " → ")
                let bid = b.highBid ?? b.bidAmount
                let ends = ISO8601DateFormatter.iso.date(from: b.endsAt ?? b.expiresAt ?? "") ?? Date().addingTimeInterval(60 * 30)
                let existing = byLoad[loadId]
                let existingHigh = existing?.highBid ?? 0
                if existing == nil || (bid ?? 0) > existingHigh {
                    byLoad[loadId] = BrokerAuctionItem(
                        id: b.id ?? loadId,
                        loadId: loadId,
                        displayId: displayId,
                        lane: lane,
                        highBid: bid,
                        bidders: max(existing?.bidders ?? 0, b.bidders ?? b.biddersCount ?? 1),
                        endsAt: ends
                    )
                }
            }
            auctions = Array(byLoad.values).sorted { $0.endsAt < $1.endsAt }
            hasLoadedOnce = true
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "Can't reach broker feed"
        }
    }
}

struct BrokerAuctionsView: View {
    @EnvironmentObject var auth: AuthStore
    @StateObject private var store = BrokerAuctionsStore.shared
    @State private var active: BrokerAuctionItem?

    var body: some View {
        ScrollView {
            VStack(spacing: S.s1) {
                if store.auctions.isEmpty {
                    Text("No live auctions.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                } else {
                    ForEach(store.auctions) { auction in
                        Button {
                            WKInterfaceDevice.current().play(.click)
                            active = auction
                        } label: {
                            auctionRow(auction)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, S.s1)
            .padding(.horizontal, S.s2)
        }
        .navigationTitle("Auctions")
        .task { await store.refresh(auth: auth) }
        .sheet(item: $active) { a in
            LoadAuctionView(loadId: a.loadId)
        }
        // Keep bounce/overscroll of auction cards inside the rounded
        // watch bezel — otherwise amber timer text or green bid
        // highlights can flash into the corner radius.
        .clipShape(ContainerRelativeShape())
    }

    @ViewBuilder
    private func auctionRow(_ a: BrokerAuctionItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(a.displayId).font(.system(size: 10, weight: .bold))
                Spacer()
                Text("\(a.bidders) bids")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Text(a.lane)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack {
                if let high = a.highBid {
                    Text("$\(Int(high))")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.esangGreen)
                        .monospacedDigit()
                } else {
                    Text("No bids")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(a.endsAt, style: .timer)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.esangAmber)
                    .monospacedDigit()
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
    }
}
