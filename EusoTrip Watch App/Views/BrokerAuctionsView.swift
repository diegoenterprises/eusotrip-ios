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
    @Published var auctions: [BrokerAuctionItem] = [
        .init(id: "a1", loadId: "LD-48301", displayId: "LD-48301",
              lane: "LAX → PHX", highBid: 1980, bidders: 4,
              endsAt: Date().addingTimeInterval(60 * 18)),
        .init(id: "a2", loadId: "LD-48288", displayId: "LD-48288",
              lane: "DAL → ATL", highBid: 3200, bidders: 7,
              endsAt: Date().addingTimeInterval(60 * 43)),
        .init(id: "a3", loadId: "LD-48254", displayId: "LD-48254",
              lane: "CHI → CLE", highBid: 980, bidders: 2,
              endsAt: Date().addingTimeInterval(60 * 2))
    ]

    func refresh(auth: AuthStore) async {
        guard auth.isSignedIn else { return }
        do {
            let client = EsangClient(auth: auth)
            let data = try await client.queryJSON("loadBidding.listActiveAuctions", input: ["limit": 10])
            struct Envelope: Decodable {
                struct Result: Decodable {
                    struct DataContainer: Decodable {
                        let json: [RemoteAuction]
                    }
                    let data: DataContainer
                }
                let result: Result
            }
            struct RemoteAuction: Decodable {
                let id: String
                let loadId: String
                let displayId: String?
                let lane: String?
                let highBid: Double?
                let bidders: Int?
                let endsAt: String?
            }
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            auctions = env.result.data.json.map {
                BrokerAuctionItem(
                    id: $0.id,
                    loadId: $0.loadId,
                    displayId: $0.displayId ?? $0.loadId,
                    lane: $0.lane ?? "",
                    highBid: $0.highBid,
                    bidders: $0.bidders ?? 0,
                    endsAt: ISO8601DateFormatter.iso.date(from: $0.endsAt ?? "") ?? Date()
                )
            }
        } catch {}
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

extension BrokerAuctionItem: Identifiable {}
