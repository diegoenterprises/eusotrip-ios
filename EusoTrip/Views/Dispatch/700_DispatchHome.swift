//
//  700_DispatchHome.swift
//  EusoTrip — Dispatch · Home (glanceable widgets only).
//
//  Doctrine: Home is glanceable widgets — KPI hero, stat strip, and 1–2
//  priority widgets. Never a list of nav cells. Heavy boards (kanban,
//  bulk funnel, run-ticket capture, price book, reports) live under
//  the operational bottom-nav tabs (Drivers · Loads · Me).
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

private struct PriorityException: Decodable, Identifiable, Hashable {
    let id: String
    let type: String?
    let severity: String?
    let driverName: String?
    let loadNumber: String?
    let createdAt: String?
}

private struct PriorityHOSDriver: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let status: String
    let load: String?
    let hoursRemaining: Double?
}

private struct DispatchHomeBody: View {
    @Environment(\.palette) private var palette
    @State private var kpi: DispatchKPI? = nil
    @State private var topException: PriorityException? = nil
    @State private var hosWatchlist: [PriorityHOSDriver] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                // Canonical lead: morning brief → weather. Driver 010 is the
                // baseline; every role home opens with these two cards.
                RoleHomeIntro()
                if loading {
                    LifecycleCard { Text("Loading dispatch pulse…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let k = kpi {
                    if let e = topException { priorityWidget(e) }
                    kpiHero(k)
                    statsGrid(k)
                    if !hosWatchlist.isEmpty { hosWidget }
                }
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

    private func priorityWidget(_ e: PriorityException) -> some View {
        Button {
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "703"])
        } label: {
            LifecycleCard(accentDanger: true) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TRIAGE NOW").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(Brand.danger)
                        Text(e.type ?? "Open exception").font(.system(size: 18, weight: .heavy)).foregroundStyle(palette.textPrimary).lineLimit(1)
                        Text("\(e.driverName ?? "—") · \(e.loadNumber ?? "—")").font(EType.caption).foregroundStyle(palette.textSecondary)
                        if let s = e.severity {
                            Text(s.uppercased())
                                .font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(s.lowercased() == "high" || s.lowercased() == "critical" ? Brand.danger : palette.textTertiary)
                                .clipShape(Capsule())
                                .padding(.top, 4)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 28)).foregroundStyle(LinearGradient.diagonal)
                }
            }
        }.buttonStyle(.plain)
    }

    private var hosWidget: some View {
        LifecycleCard {
            HStack {
                Text("HOS WATCHLIST").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
                Text("UNDER 4H").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }
            ForEach(hosWatchlist) { d in
                HStack {
                    Text(d.name).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                    Spacer(minLength: 0)
                    if let load = d.load, !load.isEmpty {
                        Text(load).font(EType.caption).foregroundStyle(palette.textTertiary).lineLimit(1)
                    }
                    Text(d.hoursRemaining.map { String(format: "%.1fh", $0) } ?? "—")
                        .font(EType.bodyStrong).monospacedDigit()
                        .foregroundStyle((d.hoursRemaining ?? 999) < 2 ? Brand.danger : palette.textPrimary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct DriverIn: Encodable { let limit: Int }
        do {
            async let kpiR: DispatchKPI = EusoTripAPI.shared.queryNoInput("dispatch.getKPI")
            async let issuesR: [PriorityException] = EusoTripAPI.shared.queryNoInput("dispatch.getActiveIssues")
            async let driversR: [PriorityHOSDriver] = EusoTripAPI.shared.query("dispatch.getDriverStatuses", input: DriverIn(limit: 100))
            let (k, issues, drivers) = try await (kpiR, issuesR, driversR)
            kpi = k
            topException = issues.first { ($0.severity?.lowercased() == "high" || $0.severity?.lowercased() == "critical") } ?? issues.first
            hosWatchlist = drivers
                .filter { ($0.hoursRemaining ?? 999) < 4 }
                .sorted { ($0.hoursRemaining ?? 999) < ($1.hoursRemaining ?? 999) }
                .prefix(3).map { $0 }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("700 · Dispatch home · Night") { DispatchHomeScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("700 · Dispatch home · Afternoon") { DispatchHomeScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
