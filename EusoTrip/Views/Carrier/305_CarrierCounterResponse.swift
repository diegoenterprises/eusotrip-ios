//
//  305_CarrierCounterResponse.swift
//  EusoTrip — Carrier · Counter-response inbox.
//
//  Cross-role chain (closes the counter-bid loop):
//    Shipper.counterBid (offer countered + emits BID_COUNTERED)
//      → THIS SCREEN reads via catalysts.getMyCounteredBids
//      → catalysts.respondToCounter (accept/reject + emits BID_AWARDED/DECLINED)
//      → Shipper.getLifecycleSnapshot refresh
//
//  Without this surface the carrier never sees the shipper's counter
//  and the loop dies. Every counter-bid flow on the platform routes
//  through here.
//

import SwiftUI

struct CarrierCounterResponseScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { CounterResponseBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Bids", systemImage: "hand.raised.fill", isCurrent: true),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct CounteredBid: Decodable, Identifiable, Hashable {
    let bidId: String
    let loadId: String
    let originalAmount: Double
    let notes: String
    let status: String
    let createdAt: String?
    var id: String { bidId }
}

private struct CounterResponseBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [CounteredBid] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var responding: String? = nil
    @State private var counterRates: [String: Double] = [:]

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
                Image(systemName: "arrow.triangle.swap").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CARRIER · COUNTER-OFFERS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Pending counters").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Shippers countered these bids. Accept the new rate or reject and stay at your original.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading counters…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if rows.isEmpty { EusoEmptyState(systemImage: "tray", title: "No pending counters", subtitle: "When a shipper counters one of your bids, it lands here.") }
        else {
            ForEach(rows) { bid in
                LifecycleCard(accentGradient: true) {
                    LifecycleSection(label: bid.bidId.uppercased(), icon: "doc.text")
                    LifecycleRow(label: "Load",            value: bid.loadId)
                    LifecycleRow(label: "Original amount",  value: usd(bid.originalAmount))
                    LifecycleRow(label: "Status",           value: bid.status.uppercased())
                    LifecycleRow(label: "Submitted",        value: humanISO(bid.createdAt))
                    if let counter = parseCounter(bid.notes) {
                        LifecycleRow(label: "Counter rate", value: usd(counter))
                    }
                    Text("NOTES").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary).padding(.top, 6)
                    Text(bid.notes).font(EType.mono(.micro)).tracking(0.4).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button { Task { await respond(bid: bid, accept: true) } } label: {
                            HStack {
                                if responding == bid.bidId+":a" { ProgressView().tint(.white) }
                                Text(responding == bid.bidId+":a" ? "Accepting…" : "Accept counter").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(LinearGradient.diagonal).clipShape(Capsule())
                        }.buttonStyle(.plain).disabled(responding != nil)
                        Button { Task { await respond(bid: bid, accept: false) } } label: {
                            Text(responding == bid.bidId+":r" ? "Rejecting…" : "Reject").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(Brand.danger)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(palette.bgCard)
                                .overlay(Capsule().strokeBorder(Brand.danger.opacity(0.5), lineWidth: 1))
                                .clipShape(Capsule())
                        }.buttonStyle(.plain).disabled(responding != nil)
                    }
                }
            }
        }
    }

    /// Parse `[COUNTERED 2026-... AT $1900, '...']` from notes to surface
    /// the counter rate cleanly. Falls back to nil if the marker isn't
    /// in the format we control (server controls this format, so this
    /// is a best-effort display optimization).
    private func parseCounter(_ notes: String) -> Double? {
        guard let range = notes.range(of: "AT $"), range.upperBound < notes.endIndex else { return nil }
        let after = notes[range.upperBound...]
        let digits = after.prefix { $0.isNumber || $0 == "." }
        return Double(digits)
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [CounteredBid] = try await EusoTripAPI.shared.queryNoInput("catalysts.getMyCounteredBids")
            rows = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func respond(bid: CounteredBid, accept: Bool) async {
        responding = bid.bidId + (accept ? ":a" : ":r")
        struct In: Encodable { let bidId: String; let accept: Bool; let counterRate: Double?; let note: String? }
        struct Out: Decodable { let success: Bool }
        let cr = parseCounter(bid.notes)
        let _ : Out = (try? await EusoTripAPI.shared.mutation(
            "catalysts.respondToCounter",
            input: In(bidId: bid.bidId, accept: accept, counterRate: accept ? cr : nil, note: nil)
        )) ?? Out(success: false)
        await load()
        responding = nil
    }
}

#Preview("305 · Carrier counter-response · Night") { CarrierCounterResponseScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("305 · Carrier counter-response · Afternoon") { CarrierCounterResponseScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
