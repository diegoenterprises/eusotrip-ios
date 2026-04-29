//
//  700_DispatchHome.swift
//  EusoTrip — Dispatch · Home (daily ops dashboard).
//

import SwiftUI

struct DispatchHomeScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { DispatchHomeBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: true),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct DispatchKPI: Decodable, Hashable {
    let driversOnDuty: Int
    let driversDriving: Int
    let activeLoads: Int
    let openExceptions: Int
    let lateArrivalsToday: Int
    let etaCriticalCount: Int
    let avgUtilizationPct: Int?
}

private struct DispatchHomeBody: View {
    @Environment(\.palette) private var palette
    @State private var kpi: DispatchKPI? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading { LifecycleCard { Text("Loading KPIs…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let k = kpi { kpiHero(k); statsGrid(k); cellLinks }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.split.3x1.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCH · HOME").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Dispatch board").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func kpiHero(_ k: DispatchKPI) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DRIVERS DRIVING").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(.white.opacity(0.85))
            Text("\(k.driversDriving)").font(.system(size: 36, weight: .heavy)).foregroundStyle(.white).monospacedDigit()
            HStack(spacing: 8) {
                Text("ON-DUTY \(k.driversOnDuty)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.18)).clipShape(Capsule())
                Text("UTIL \(k.avgUtilizationPct ?? 0)%").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.18)).clipShape(Capsule())
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.diagonal)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func statsGrid(_ k: DispatchKPI) -> some View {
        HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "ACTIVE LOADS", value: "\(k.activeLoads)", icon: "shippingbox")
            LifecycleStatTile(label: "EXCEPTIONS", value: "\(k.openExceptions)", icon: "exclamationmark.triangle", danger: k.openExceptions > 0)
            LifecycleStatTile(label: "LATE TODAY", value: "\(k.lateArrivalsToday)", icon: "clock", danger: k.lateArrivalsToday > 0)
        }
    }

    private var cellLinks: some View {
        VStack(spacing: 8) {
            link(icon: "person.3.fill", label: "Driver board (live)", screen: "701")
            link(icon: "shippingbox.fill", label: "Load assignments", screen: "702")
            link(icon: "exclamationmark.triangle.fill", label: "Exception triage", screen: "703")
            link(icon: "clock.fill", label: "HOS alerts", screen: "704")
            link(icon: "map.fill", label: "Route optimization", screen: "705")
            link(icon: "message.fill", label: "Driver chat", screen: "706")
        }
    }

    private func link(icon: String, label: String, screen: String) -> some View {
        Button {
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": screen])
        } label: {
            LifecycleCard {
                HStack {
                    Image(systemName: icon).foregroundStyle(LinearGradient.diagonal)
                    Text(label).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
                }
            }
        }.buttonStyle(.plain)
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let k: DispatchKPI = try await EusoTripAPI.shared.api.queryNoInput("dispatch.getKPI")
            kpi = k
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("700 · Dispatch home · Night") { DispatchHomeScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("700 · Dispatch home · Afternoon") { DispatchHomeScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
