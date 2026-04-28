//
//  308_CarrierMyBids.swift
//  EusoTrip — Carrier · My bids (active + history).
//

import SwiftUI

struct CarrierMyBidsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { MyBidsBody() } nav: {
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

private struct MyBid: Decodable, Identifiable, Hashable {
    let id: String
    let loadId: String
    let loadNumber: String?
    let lane: String?
    let amount: Double
    let status: String       // pending / accepted / rejected / countered / withdrawn
    let createdAt: String?
}

private struct MyBidsBody: View {
    @Environment(\.palette) private var palette
    @State private var bids: [MyBid] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var filter: String = "all"

    private var filtered: [MyBid] {
        switch filter {
        case "active":   return bids.filter { ["pending", "countered"].contains($0.status) }
        case "won":      return bids.filter { $0.status == "accepted" }
        case "lost":     return bids.filter { ["rejected", "withdrawn"].contains($0.status) }
        default:         return bids
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                filterStrip
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
                Image(systemName: "hand.raised.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CARRIER · MY BIDS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("My bids").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var filterStrip: some View {
        HStack(spacing: 6) {
            ForEach([("all", "All"), ("active", "Active"), ("won", "Won"), ("lost", "Lost")], id: \.0) { f in
                Button { filter = f.0 } label: {
                    Text(f.1).font(.system(size: 11, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(filter == f.0 ? .white : palette.textPrimary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(filter == f.0 ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.tintNeutral))
                        .clipShape(Capsule())
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading bids…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if filtered.isEmpty { EusoEmptyState(systemImage: "hand.raised", title: "No bids in this view", subtitle: "Bid on loads from the marketplace; outcomes show up here.") }
        else {
            ForEach(filtered) { b in
                LifecycleCard(accentGradient: b.status == "accepted", accentWarning: b.status == "countered", accentDanger: b.status == "rejected") {
                    LifecycleSection(label: dashIfEmpty(b.loadNumber).uppercased(), icon: "doc.text")
                    LifecycleRow(label: "Lane",      value: dashIfEmpty(b.lane))
                    LifecycleRow(label: "Amount",    value: usd(b.amount))
                    LifecycleRow(label: "Status",    value: b.status.uppercased())
                    LifecycleRow(label: "Submitted", value: humanISO(b.createdAt))
                    if b.status == "countered" {
                        Button {
                            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "305", "bidId": b.id])
                        } label: {
                            Text("View counter →").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(LinearGradient.diagonal).clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [MyBid] = try await EusoTripAPI.shared.api.queryNoInput("catalysts.getMyBids")
            bids = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("308 · My bids · Night") { CarrierMyBidsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("308 · My bids · Afternoon") { CarrierMyBidsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
