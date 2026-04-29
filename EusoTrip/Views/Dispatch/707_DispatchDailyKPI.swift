//
//  707_DispatchDailyKPI.swift
//  EusoTrip — Dispatch · Daily KPI digest (board snapshot for end-of-day).
//

import SwiftUI

struct DispatchDailyKPIScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { DailyKPIBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

private struct DashboardStats: Decodable, Hashable {
    let activeLoads: Int?
    let unassigned: Int?
    let inTransit: Int?
    let loading: Int?
    let issues: Int?
    let completedToday: Int?
    let totalDrivers: Int?
    let availableDrivers: Int?
    let truckActive: Int?
    let railActive: Int?
    let vesselActive: Int?
    let truckInTransit: Int?
    let railInTransit: Int?
    let vesselInTransit: Int?
}

private struct DailyKPIBody: View {
    @Environment(\.palette) private var palette
    @State private var stats: DashboardStats? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading { LifecycleCard { Text("Loading day digest…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let s = stats { hero(s); modeCard(s); driverCard(s) }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCH · DAILY KPI").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("End-of-day digest").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func hero(_ s: DashboardStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COMPLETED TODAY").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(.white.opacity(0.85))
            Text("\(s.completedToday ?? 0)").font(.system(size: 36, weight: .heavy)).foregroundStyle(.white).monospacedDigit()
            HStack(spacing: 8) {
                Text("ACTIVE \(s.activeLoads ?? 0)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.18)).clipShape(Capsule())
                Text("UNASSIGNED \(s.unassigned ?? 0)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.18)).clipShape(Capsule())
                Text("ISSUES \(s.issues ?? 0)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.18)).clipShape(Capsule())
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.diagonal)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func modeCard(_ s: DashboardStats) -> some View {
        LifecycleCard {
            LifecycleSection(label: "BY MODE", icon: "rectangle.3.group")
            LifecycleRow(label: "Truck active",   value: "\(s.truckActive ?? 0)  ·  in-transit \(s.truckInTransit ?? 0)")
            LifecycleRow(label: "Rail active",    value: "\(s.railActive ?? 0)  ·  in-transit \(s.railInTransit ?? 0)")
            LifecycleRow(label: "Vessel active",  value: "\(s.vesselActive ?? 0)  ·  in-transit \(s.vesselInTransit ?? 0)")
        }
    }

    private func driverCard(_ s: DashboardStats) -> some View {
        LifecycleCard {
            LifecycleSection(label: "DRIVER POOL", icon: "person.3")
            LifecycleRow(label: "Total drivers",     value: "\(s.totalDrivers ?? 0)")
            LifecycleRow(label: "Available drivers", value: "\(s.availableDrivers ?? 0)")
            LifecycleRow(label: "Loading now",       value: "\(s.loading ?? 0)")
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let s: DashboardStats = try await EusoTripAPI.shared.api.queryNoInput("dispatch.getDashboardStats")
            stats = s
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("707 · Daily KPI · Night") { DispatchDailyKPIScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("707 · Daily KPI · Afternoon") { DispatchDailyKPIScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
