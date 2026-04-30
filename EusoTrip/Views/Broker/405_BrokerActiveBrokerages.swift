//
//  405_BrokerActiveBrokerages.swift
//  EusoTrip — Broker · Active brokerages (deals in flight).
//

import SwiftUI

struct BrokerActiveBrokeragesScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ActiveBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Carriers", systemImage: "person.3.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct ActiveBrokerage: Decodable, Identifiable, Hashable {
    let id: String
    let loadNumber: String
    let shipperName: String
    let carrierName: String
    let driverName: String?
    let lane: String?
    let status: String
    let margin: Double?
}

private struct ActiveBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [ActiveBrokerage] = []
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
                Image(systemName: "rectangle.stack").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("BROKER · ACTIVE BROKERAGES").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Deals in flight").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading brokerages…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if rows.isEmpty { EusoEmptyState(systemImage: "rectangle.stack", title: "No active brokerages", subtitle: "Loads you've tendered land here mid-haul. Track shipper-side and carrier-side states in one row.") }
        else {
            ForEach(rows) { b in
                LifecycleCard(accentGradient: b.status == "in_transit") {
                    LifecycleSection(label: b.loadNumber.uppercased(), icon: "doc.text")
                    LifecycleRow(label: "Shipper",  value: b.shipperName)
                    LifecycleRow(label: "Carrier",  value: b.carrierName)
                    LifecycleRow(label: "Driver",    value: dashIfEmpty(b.driverName))
                    LifecycleRow(label: "Lane",      value: dashIfEmpty(b.lane))
                    LifecycleRow(label: "Status",    value: b.status.uppercased())
                    LifecycleRow(label: "Margin",    value: usd(b.margin))
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [ActiveBrokerage] = try await EusoTripAPI.shared.queryNoInput("brokers.getActiveBrokerages")
            rows = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("405 · Active · Night") { BrokerActiveBrokeragesScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("405 · Active · Afternoon") { BrokerActiveBrokeragesScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
