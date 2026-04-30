//
//  315_CarrierMaintenance.swift
//  EusoTrip — Carrier · Maintenance · Zeun work orders.
//
//  Cross-role chain: driver/carrier-side breakdown report → Zeun ticket
//  → carrier sees here → mechanic provider network notified → settlement
//  layer logs maintenance cost against the truck.
//

import SwiftUI

struct CarrierMaintenanceScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { MaintenanceBody() } nav: {
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

private struct WorkOrder: Decodable, Identifiable, Hashable {
    let id: String
    let truckNumber: String?
    let kind: String           // "preventive" / "breakdown" / "DVIR" / "recall"
    let status: String         // "queued" / "in_progress" / "complete"
    let openedAt: String?
    let costEstimate: Double?
    let mechanic: String?
    let summary: String?
}

private struct MaintenanceBody: View {
    @Environment(\.palette) private var palette
    @State private var orders: [WorkOrder] = []
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
                Image(systemName: "wrench.and.screwdriver.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CARRIER · ZEUN").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Maintenance work orders").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading work orders…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if orders.isEmpty { EusoEmptyState(systemImage: "wrench", title: "No work orders", subtitle: "DVIR exceptions / breakdowns / preventive maintenance schedules surface here.") }
        else {
            ForEach(orders) { o in
                LifecycleCard(accentDanger: o.kind == "breakdown", accentWarning: o.status == "queued") {
                    LifecycleSection(label: o.kind.uppercased(), icon: kindIcon(o.kind))
                    LifecycleRow(label: "Truck",     value: dashIfEmpty(o.truckNumber))
                    LifecycleRow(label: "Status",    value: o.status.uppercased())
                    LifecycleRow(label: "Mechanic",  value: dashIfEmpty(o.mechanic))
                    LifecycleRow(label: "Opened",    value: humanISO(o.openedAt))
                    LifecycleRow(label: "Estimate",  value: usd(o.costEstimate))
                    if let s = o.summary, !s.isEmpty { Text(s).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true) }
                }
            }
        }
    }

    private func kindIcon(_ kind: String) -> String {
        switch kind {
        case "breakdown": return "exclamationmark.triangle.fill"
        case "preventive": return "calendar"
        case "DVIR": return "checklist"
        case "recall": return "exclamationmark.octagon"
        default: return "wrench"
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [WorkOrder] = try await EusoTripAPI.shared.queryNoInput("zeun.getWorkOrdersForCarrier")
            orders = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("315 · Maintenance · Night") { CarrierMaintenanceScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("315 · Maintenance · Afternoon") { CarrierMaintenanceScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
