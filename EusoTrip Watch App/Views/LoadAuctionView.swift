//
//  LoadAuctionView.swift
//  EusoTrip Watch App
//
//  Phase 3 — brokers and dispatchers can peek at a single load auction
//  from the wrist: current high bid + timer + accept-high-bid action
//  (with a required confirmation so a bad tap doesn't close a deal).
//

import SwiftUI
import WatchKit

struct LoadAuctionView: View {
    let loadId: String

    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = SingleAuctionStore()
    @State private var confirming = false

    var body: some View {
        ScrollView {
            VStack(spacing: S.s2) {
                Text(store.displayId.isEmpty ? loadId : store.displayId)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                Text(store.lane)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                VStack(spacing: 2) {
                    Text("HIGH BID")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                    Text(store.highBid.map { "$\(Int($0))" } ?? "—")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.esangGreen)
                        .monospacedDigit()
                    if let endsAt = store.endsAt {
                        Text(endsAt, style: .timer)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.esangAmber)
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.md))

                Text("\(store.bidders) active bidders")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                if confirming {
                    VStack(spacing: 4) {
                        Text("Accept high bid?")
                            .font(.system(size: 11, weight: .semibold))
                        HStack(spacing: 4) {
                            Button(role: .cancel) {
                                confirming = false
                            } label: {
                                Text("No")
                                    .font(.system(size: 11))
                                    .frame(maxWidth: .infinity, minHeight: 26)
                                    .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            Button {
                                Task {
                                    _ = try? await EsangClient(auth: auth).mutateJSON(
                                        "loadBidding.acceptHighBid",
                                        input: ["loadId": loadId, "source": "watch"]
                                    )
                                    WKInterfaceDevice.current().play(.success)
                                    dismiss()
                                }
                            } label: {
                                Text("Accept")
                                    .font(.system(size: 11, weight: .bold))
                                    .frame(maxWidth: .infinity, minHeight: 26)
                                    .background(Color.esangGreen, in: RoundedRectangle(cornerRadius: R.sm))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Button {
                        WKInterfaceDevice.current().play(.click)
                        confirming = true
                    } label: {
                        Text("Accept High Bid")
                            .font(.system(size: 12, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(LinearGradient.esangSuccess, in: RoundedRectangle(cornerRadius: R.sm))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        connectivity.requestPhoneActivation(
                            transcript: "open auction \(loadId)",
                            reply: "Opening auction on your iPhone."
                        )
                        dismiss()
                    } label: {
                        Label("Open on iPhone", systemImage: "iphone.and.arrow.forward")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .background(Color.esangBlue, in: RoundedRectangle(cornerRadius: R.sm))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(S.s2)
        }
        .navigationTitle("Auction")
        .task { await store.refresh(auth: auth, loadId: loadId) }
    }
}

@MainActor
final class SingleAuctionStore: ObservableObject {
    @Published var displayId: String = ""
    @Published var lane: String = ""
    @Published var highBid: Double?
    @Published var bidders: Int = 0
    @Published var endsAt: Date?

    func refresh(auth: AuthStore, loadId: String) async {
        guard auth.isSignedIn else { return }
        do {
            let client = EsangClient(auth: auth)
            let data = try await client.queryJSON(
                "loadBidding.getAuction",
                input: ["loadId": loadId]
            )
            struct Envelope: Decodable {
                struct Result: Decodable {
                    struct DataContainer: Decodable {
                        let json: Auction
                    }
                    let data: DataContainer
                }
                let result: Result
            }
            struct Auction: Decodable {
                let displayId: String?
                let lane: String?
                let highBid: Double?
                let bidders: Int?
                let endsAt: String?
            }
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            let a = env.result.data.json
            displayId = a.displayId ?? ""
            lane = a.lane ?? ""
            highBid = a.highBid
            bidders = a.bidders ?? 0
            endsAt = ISO8601DateFormatter.iso.date(from: a.endsAt ?? "")
        } catch {}
    }
}
