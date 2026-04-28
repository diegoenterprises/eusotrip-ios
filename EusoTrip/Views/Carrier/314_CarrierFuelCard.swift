//
//  314_CarrierFuelCard.swift
//  EusoTrip — Carrier · Fuel card (Comdata / EFS / WEX / FleetOne).
//

import SwiftUI

struct CarrierFuelCardScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { FuelCardBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Bids", systemImage: "hand.raised.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

private struct FuelCard: Decodable, Identifiable, Hashable {
    let id: String
    let provider: String       // "comdata" / "efs" / "wex" / "fleetone"
    let last4: String?
    let balance: Double?
    let creditLimit: Double?
    let mtdSpend: Double?
    let driverName: String?
    let isActive: Bool
}

private struct FuelCardBody: View {
    @Environment(\.palette) private var palette
    @State private var cards: [FuelCard] = []
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
                Image(systemName: "fuelpump.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CARRIER · FUEL CARDS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Fuel cards").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading cards…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if cards.isEmpty { EusoEmptyState(systemImage: "creditcard", title: "No fuel cards", subtitle: "Add a Comdata / EFS / WEX / FleetOne card via the integrations registry.") }
        else {
            ForEach(cards) { c in
                LifecycleCard(accentGradient: c.isActive) {
                    LifecycleSection(label: c.provider.uppercased(), icon: "fuelpump")
                    LifecycleRow(label: "Last 4",         value: dashIfEmpty(c.last4))
                    LifecycleRow(label: "Balance",         value: usd(c.balance))
                    LifecycleRow(label: "Credit limit",    value: usd(c.creditLimit))
                    LifecycleRow(label: "MTD spend",       value: usd(c.mtdSpend))
                    LifecycleRow(label: "Driver",          value: dashIfEmpty(c.driverName))
                    LifecycleRow(label: "Active",          value: c.isActive ? "Yes" : "No")
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [FuelCard] = try await EusoTripAPI.shared.api.queryNoInput("catalysts.getFuelCards")
            cards = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("314 · Fuel cards · Night") { CarrierFuelCardScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("314 · Fuel cards · Afternoon") { CarrierFuelCardScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
