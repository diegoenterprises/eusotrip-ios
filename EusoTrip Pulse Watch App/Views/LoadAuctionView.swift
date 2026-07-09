//
//  LoadAuctionView.swift
//  EusoTrip Watch App
//
//  Phase 3 — brokers and dispatchers can peek at a single load auction
//  from the wrist: current high bid + timer + accept-high-bid action
//  (with a required confirmation so a bad tap doesn't close a deal).
//
//  Wired to REAL procs: hydrates from `loadBidding.getByLoad`
//  (loadBidding.ts:184 — raw load_bids rows for this load) and accepts
//  via `loadBidding.accept { bidId }` (loadBidding.ts:685). The
//  previously called `loadBidding.getAuction` / `.acceptHighBid` do
//  not exist on any router — the sheet was permanently blank and
//  Accept played a success haptic on a 404.
//

import SwiftUI
import Combine
import WatchKit

struct LoadAuctionView: View {
    let loadId: String

    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = SingleAuctionStore()
    @State private var confirming = false
    @State private var accepting = false

    var body: some View {
        ScrollView {
            VStack(spacing: S.s2) {
                Text(store.displayId.isEmpty ? "Load #\(loadId)" : store.displayId)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)

                if let err = store.lastError {
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
                }

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

                Text(store.hasLoadedOnce
                     ? "\(store.bidders) active bidder\(store.bidders == 1 ? "" : "s")"
                     : "Loading bids…")
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
                                guard !accepting else { return }
                                accepting = true
                                Task {
                                    let ok = await store.acceptHighBid(auth: auth)
                                    accepting = false
                                    if ok {
                                        WKInterfaceDevice.current().play(.success)
                                        dismiss()
                                    } else {
                                        WKInterfaceDevice.current().play(.failure)
                                        confirming = false
                                    }
                                }
                            } label: {
                                Text(accepting ? "Accepting…" : "Accept")
                                    .font(.system(size: 11, weight: .bold))
                                    .frame(maxWidth: .infinity, minHeight: 26)
                                    .background(Color.esangGreen, in: RoundedRectangle(cornerRadius: R.sm))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .disabled(accepting)
                        }
                    }
                } else {
                    // Accept only renders when there is a REAL winning
                    // bid to award — a broker can't "accept" an empty
                    // auction.
                    if store.highBidId != nil {
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
                    }

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
        // Success-gradient Accept button + confirm pill can reach the
        // edges — clip to the watch bezel so nothing escapes the
        // rounded corners during animation.
        .clipShape(ContainerRelativeShape())
    }
}

@MainActor
final class SingleAuctionStore: ObservableObject {
    @Published var displayId: String = ""
    @Published var highBid: Double?
    @Published var highBidId: Int?
    @Published var bidders: Int = 0
    @Published var endsAt: Date?
    @Published var hasLoadedOnce = false
    @Published var lastError: String?

    private var loadIdNumeric: Int?

    func refresh(auth: AuthStore, loadId: String) async {
        guard auth.isSignedIn else {
            lastError = "Sign in on your iPhone"
            return
        }
        // getByLoad coerces loadId to a number server-side; strip a
        // "load_1077"-style prefix per the canonical resolver pattern.
        let numeric = Int(loadId) ?? Int(loadId.split(separator: "_").last.map(String.init) ?? "")
        guard let numeric else {
            lastError = "Auction unavailable for this load."
            return
        }
        loadIdNumeric = numeric
        do {
            let data = try await EsangClient(auth: auth).queryJSON(
                "loadBidding.getByLoad",
                input: ["loadId": numeric, "status": "pending"]
            )
            let env = try JSONDecoder().decode(TRPCEnvelope<[ReceivedBidRow]>.self, from: data)
            let rows = env.result.data.json
            displayId = "Load #\(numeric)"
            bidders = Set(rows.compactMap { $0.bidderUserId }).count
            if let top = rows.max(by: { ($0.amount ?? 0) < ($1.amount ?? 0) }) {
                highBid = top.amount
                highBidId = top.id
                endsAt = ISO8601DateFormatter.iso.date(from: top.expiresAt ?? "")
                    ?? BoardDateFallback.parse(top.expiresAt)
            } else {
                highBid = nil
                highBidId = nil
                endsAt = nil
            }
            hasLoadedOnce = true
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription
                ?? "Can't reach the auction feed"
        }
    }

    /// Awards the current high bid via the REAL `loadBidding.accept`
    /// mutation. Returns true only on a 2xx — the caller plays the
    /// success haptic strictly on truth.
    func acceptHighBid(auth: AuthStore) async -> Bool {
        guard let bidId = highBidId else {
            lastError = "No live bid to accept."
            return false
        }
        do {
            _ = try await EsangClient(auth: auth).mutateJSON(
                "loadBidding.accept",
                input: ["bidId": bidId]
            )
            lastError = nil
            return true
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't award the bid — try from your iPhone."
            return false
        }
    }
}

#Preview("Load auction — Dark") {
    LoadAuctionView(loadId: "1077")
        .environmentObject(AuthStore.preview)
        .environmentObject(WatchConnectivityManager.shared)
        .preferredColorScheme(.dark)
}

#Preview("Load auction — Light") {
    LoadAuctionView(loadId: "1077")
        .environmentObject(AuthStore.preview)
        .environmentObject(WatchConnectivityManager.shared)
        .preferredColorScheme(.light)
}
