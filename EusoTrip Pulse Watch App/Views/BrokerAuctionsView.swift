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
            // `loadBidding.getReceivedBids` (loadBidding.ts:278-310)
            // returns RAW drizzle `load_bids` rows: id/loadId are
            // Ints, bidAmount is a DECIMAL → JSON string, createdAt/
            // expiresAt are ISO strings. The previous decoder declared
            // String ids + Double amounts, so ANY real bid threw a
            // typeMismatch and the tab looked permanently dead —
            // exactly when the broker had money on the table.
            let data = try await client.queryJSON(
                "loadBidding.getReceivedBids",
                input: ["limit": 50]
            )
            let env = try JSONDecoder().decode(TRPCEnvelope<[ReceivedBidRow]>.self, from: data)
            // Coalesce by loadId so multiple bids on the same load
            // show as a single wrist row with the high bid.
            var byLoad: [String: BrokerAuctionItem] = [:]
            var bidderCount: [String: Int] = [:]
            for b in env.result.data.json {
                let loadId = String(b.loadId)
                bidderCount[loadId, default: 0] += 1
                let bid = b.amount
                let ends = ISO8601DateFormatter.iso.date(from: b.expiresAt ?? "")
                    ?? BoardDateFallback.parse(b.expiresAt ?? b.createdAt)
                let existing = byLoad[loadId]
                if existing == nil || (bid ?? 0) > (existing?.highBid ?? 0) {
                    byLoad[loadId] = BrokerAuctionItem(
                        id: String(b.id),
                        loadId: loadId,
                        displayId: "Load #\(loadId)",
                        lane: (b.equipmentType ?? "").isEmpty ? "" : b.equipmentType!.replacingOccurrences(of: "_", with: " ").capitalized,
                        highBid: bid,
                        bidders: 0,
                        endsAt: ends ?? Date().addingTimeInterval(60 * 30)
                    )
                }
            }
            auctions = byLoad.map { key, item in
                BrokerAuctionItem(
                    id: item.id,
                    loadId: item.loadId,
                    displayId: item.displayId,
                    lane: item.lane,
                    highBid: item.highBid,
                    bidders: bidderCount[key] ?? 1,
                    endsAt: item.endsAt
                )
            }
            .sorted { $0.endsAt < $1.endsAt }
            hasLoadedOnce = true
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "Can't reach broker feed"
        }
    }
}

/// Mirror of the RAW `load_bids` drizzle row `getReceivedBids` ships
/// (schema.ts:5438-5460): numeric ids, decimal-string bidAmount, ISO
/// timestamp strings.
nonisolated struct ReceivedBidRow: Decodable, Sendable {
    let id: Int
    let loadId: Int
    let bidAmount: String?
    let bidderUserId: Int?
    let equipmentType: String?
    let status: String?
    let expiresAt: String?
    let createdAt: String?

    var amount: Double? { bidAmount.flatMap(Double.init) }
}

/// Tiny shared fallback for ISO strings without fractional seconds.
nonisolated enum BoardDateFallback {
    nonisolated(unsafe) static let noFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return noFractional.date(from: raw)
    }
}

struct BrokerAuctionsView: View {
    @EnvironmentObject var auth: AuthStore
    @StateObject private var store = BrokerAuctionsStore.shared
    @State private var active: BrokerAuctionItem?

    var body: some View {
        ScrollView {
            VStack(spacing: S.s1) {
                // Honest state ladder (same as DynamicBoardView): a
                // decode/transport failure paints an error banner —
                // it can never masquerade as "No live auctions."
                if let err = store.lastError, !store.hasLoadedOnce {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.esangAmber)
                        Text(err)
                            .font(.system(size: 9, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(6)
                    .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: R.sm))
                } else if store.auctions.isEmpty && store.hasLoadedOnce {
                    Text("No live auctions.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                } else if store.auctions.isEmpty {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.7)
                        Text("Loading…")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
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
        .onChange(of: auth.isSignedIn) { _, signedIn in
            guard signedIn else { return }
            Task { await store.refresh(auth: auth) }
        }
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
