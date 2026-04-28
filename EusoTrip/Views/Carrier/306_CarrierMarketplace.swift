//
//  306_CarrierMarketplace.swift
//  EusoTrip — Carrier · Marketplace (find loads).
//
//  Cross-role chain: shipper posts → carrier marketplace surfaces
//  → carrier composes bid → shipper bids feed refreshes via realtime.
//

import SwiftUI

struct CarrierMarketplaceScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { MarketplaceBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Bids", systemImage: "hand.raised.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct AvailableLoad: Decodable, Identifiable, Hashable {
    let id: String
    let loadNumber: String
    let origin: String?
    let destination: String?
    let cargoType: String?
    let equipment: String?
    let postedRate: Double?
    let pickupISO: String?
    let mileage: Int?
}

private struct MarketplaceBody: View {
    @Environment(\.palette) private var palette
    @State private var loads: [AvailableLoad] = []
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
                Image(systemName: "shippingbox.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CARRIER · MARKETPLACE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Available loads").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading marketplace…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if loads.isEmpty { EusoEmptyState(systemImage: "shippingbox", title: "No available loads", subtitle: "Loads in BIDDING status surface here as shippers post.") }
        else {
            ForEach(loads) { ld in
                Button {
                    NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "307", "loadId": ld.id])
                } label: {
                    LifecycleCard {
                        LifecycleSection(label: ld.loadNumber.uppercased(), icon: "doc.text")
                        LifecycleRow(label: "Lane",       value: "\(dashIfEmpty(ld.origin)) → \(dashIfEmpty(ld.destination))")
                        LifecycleRow(label: "Equipment",  value: dashIfEmpty(ld.equipment))
                        LifecycleRow(label: "Cargo",      value: dashIfEmpty(ld.cargoType))
                        LifecycleRow(label: "Rate",       value: usd(ld.postedRate))
                        LifecycleRow(label: "Pickup",     value: humanISO(ld.pickupISO))
                        LifecycleRow(label: "Mileage",    value: ld.mileage.map { "\($0) mi" } ?? "—")
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [AvailableLoad] = try await EusoTripAPI.shared.api.queryNoInput("catalysts.getAvailableLoads")
            loads = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("306 · Marketplace · Night") { CarrierMarketplaceScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("306 · Marketplace · Afternoon") { CarrierMarketplaceScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
