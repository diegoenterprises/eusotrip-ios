//
//  282_CatalystLoadsHistory.swift
//  EusoTrip — Shipper · Catalyst loads history (Arc F).
//  Filters `shippers.getMyLoads` by catalystId on the client.
//

import SwiftUI

struct CatalystLoadsHistoryScreen: View {
    let theme: Theme.Palette
    let catalystId: String
    var body: some View {
        Shell(theme: theme) { CatalystLoadsHistoryBody(catalystId: catalystId) } nav: { shipperLifecycleNav() }
    }
}

private struct CatalystLoadsHistoryBody: View {
    @Environment(\.palette) private var palette
    let catalystId: String
    @StateObject private var store = ShipperMyLoadsStore()

    private var rows: [ShipperAPI.MyLoad] {
        let all = store.state.value ?? []
        return all.filter { ($0.catalystId ?? "") == catalystId }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await store.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · CATALYST LOADS HISTORY").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Loads with this carrier").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if rows.isEmpty {
            EusoEmptyState(systemImage: "shippingbox", title: "No loads yet", subtitle: "Once you tender a load to this carrier and it lands, it'll appear here.")
        } else {
            ForEach(rows) { ld in
                Button {
                    NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "205", "loadId": ld.id])
                } label: {
                    LifecycleCard {
                        LifecycleSection(label: ld.loadNumber.uppercased(), icon: "doc.text")
                        LifecycleRow(label: "Status",      value: ld.status.uppercased())
                        LifecycleRow(label: "Origin",      value: dashIfEmpty(ld.origin))
                        LifecycleRow(label: "Destination", value: dashIfEmpty(ld.destination))
                        if let r = ld.rate { LifecycleRow(label: "Rate", value: usd(r)) }
                    }
                }.buttonStyle(.plain)
            }
        }
    }
}

#Preview("282 · Loads history · Night") {
    CatalystLoadsHistoryScreen(theme: Theme.dark, catalystId: "car_1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("282 · Loads history · Afternoon") {
    CatalystLoadsHistoryScreen(theme: Theme.light, catalystId: "car_1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
