//
//  428_CarrierCapacity.swift
//  EusoTrip — Shipper · Carrier capacity calendar + similar carriers AI.
//

import SwiftUI

struct CarrierCapacityScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { CapacityBody() } nav: { shipperLifecycleNav() }
    }
}

private struct CapacityCarrier: Decodable, Identifiable, Hashable {
    let catalystId: String
    let name: String
    let availableTrucks: Int
    let lanesCovered: [String]?
    let utilizationPct: Int?
    var id: String { catalystId }
}

private struct CapacityBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [CapacityCarrier] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "gauge").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · CARRIER CAPACITY").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Carrier availability").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading capacity…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if rows.isEmpty { EusoEmptyState(systemImage: "gauge", title: "No capacity data", subtitle: "Carriers report availability via carrierCapacity router.") }
        else {
            ForEach(rows) { c in
                LifecycleCard {
                    LifecycleSection(label: c.name.uppercased(), icon: "truck.box")
                    LifecycleRow(label: "Available trucks", value: "\(c.availableTrucks)")
                    LifecycleRow(label: "Utilization",       value: c.utilizationPct.map { "\($0)%" } ?? "—")
                    LifecycleRow(label: "Lanes",             value: (c.lanesCovered ?? []).joined(separator: ", ").isEmpty ? "—" : (c.lanesCovered ?? []).joined(separator: ", "))
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [CapacityCarrier] = try await EusoTripAPI.shared.queryNoInput("carrierCapacity.shipperView")
            rows = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("428 · Capacity · Night") { CarrierCapacityScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("428 · Capacity · Afternoon") { CarrierCapacityScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
