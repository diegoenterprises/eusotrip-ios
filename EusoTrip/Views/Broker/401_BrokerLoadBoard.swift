//
//  401_BrokerLoadBoard.swift
//  EusoTrip — Broker · Load board (shipper-posted loads available to broker).
//
//  Cross-role chain: shipper posts → broker board surfaces → broker
//  vets carrier (402) → broker tenders to carrier (403) → carrier
//  accepts → settlement layer splits commission to broker (404).
//

import SwiftUI

struct BrokerLoadBoardScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { LoadBoardBody() } nav: {
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

private struct BoardLoad: Decodable, Identifiable, Hashable {
    let id: String
    let loadNumber: String
    let shipperName: String?
    let lane: String?
    let cargoType: String?
    let postedRate: Double?
    let mileage: Int?
    let pickupISO: String?
    let estimatedMargin: Double?
}

private struct LoadBoardBody: View {
    @Environment(\.palette) private var palette
    @State private var loads: [BoardLoad] = []
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
                Text("BROKER · LOAD BOARD").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Available loads").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Shipper-posted loads with estimated margin (DAT/Truckstop blended).").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading board…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if loads.isEmpty { EusoEmptyState(systemImage: "shippingbox", title: "No loads on the board", subtitle: "Loads in BIDDING status from shippers in your network surface here.") }
        else {
            ForEach(loads) { ld in
                Button {
                    NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "402", "loadId": ld.id])
                } label: {
                    LifecycleCard(accentGradient: (ld.estimatedMargin ?? 0) > 200) {
                        LifecycleSection(label: ld.loadNumber.uppercased(), icon: "doc.text")
                        LifecycleRow(label: "Shipper",  value: dashIfEmpty(ld.shipperName))
                        LifecycleRow(label: "Lane",     value: dashIfEmpty(ld.lane))
                        LifecycleRow(label: "Cargo",    value: dashIfEmpty(ld.cargoType))
                        LifecycleRow(label: "Rate",     value: usd(ld.postedRate))
                        LifecycleRow(label: "Mileage",  value: ld.mileage.map { "\($0) mi" } ?? "—")
                        LifecycleRow(label: "Est. margin", value: usd(ld.estimatedMargin))
                        LifecycleRow(label: "Pickup",   value: humanISO(ld.pickupISO))
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [BoardLoad] = try await EusoTripAPI.shared.queryNoInput("brokers.getLoadBoard")
            loads = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("401 · Broker board · Night") { BrokerLoadBoardScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("401 · Broker board · Afternoon") { BrokerLoadBoardScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
