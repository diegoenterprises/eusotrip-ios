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
                leading: DispatchNavRoute.leading(current: .home),
                trailing: DispatchNavRoute.trailing(current: .home),
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

    private let modeColumns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading { LifecycleCard { Text("Loading day digest…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let s = stats {
                    commandHero(s)
                    nextMoveCard(s)
                    modeGrid(s)
                    driverCard(s)
                }
                Color.clear.frame(height: 150)
            }
            .padding(.horizontal, 14)
            .padding(.top, 58)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCH · DAILY KPI").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Daily command pulse").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Board health, modal movement and driver capacity from the live dispatch desk.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func commandHero(_ s: DashboardStats) -> some View {
        let severity = commandSeverity(s)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("COMMAND POSTURE")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(severity.title)
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(s.completedToday ?? 0)")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("completed")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.76))
                }
            }
            HStack(spacing: 8) {
                heroChip("ACTIVE", s.activeLoads ?? 0)
                heroChip("UNASSIGNED", s.unassigned ?? 0)
                heroChip("ISSUES", s.issues ?? 0)
            }
            Text(severity.detail)
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.diagonal)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func nextMoveCard(_ s: DashboardStats) -> some View {
        LifecycleCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: commandSeverity(s).symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEXT MOVE")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Text(nextMove(s).title)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(nextMove(s).detail)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func modeGrid(_ s: DashboardStats) -> some View {
        LazyVGrid(columns: modeColumns, spacing: 8) {
            modeTile(name: "Truck", symbol: "truck.box.fill", active: s.truckActive ?? 0, transit: s.truckInTransit ?? 0)
            modeTile(name: "Rail", symbol: "tram.fill", active: s.railActive ?? 0, transit: s.railInTransit ?? 0)
            modeTile(name: "Vessel", symbol: "ferry.fill", active: s.vesselActive ?? 0, transit: s.vesselInTransit ?? 0)
        }
    }

    private func modeTile(name: String, symbol: String, active: Int, transit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text(name.uppercased())
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text("\(active)")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
            Text("\(transit) in transit")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func driverCard(_ s: DashboardStats) -> some View {
        let total = max(0, s.totalDrivers ?? 0)
        let available = max(0, s.availableDrivers ?? 0)
        let pct = total > 0 ? Double(available) / Double(total) : 0
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 10) {
                LifecycleSection(label: "DRIVER POOL", icon: "person.3")
                HStack(alignment: .firstTextBaseline) {
                    Text("\(available)")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                    Text("available of \(total)")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                    Text("\(s.loading ?? 0) loading")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.5)
                        .foregroundStyle(palette.textTertiary)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.borderFaint)
                        Capsule().fill(LinearGradient.diagonal)
                            .frame(width: pct <= 0 ? 0 : max(8, proxy.size.width * pct))
                    }
                }
                .frame(height: 8)
                Text(total == 0 ? "No company-scoped drivers are attached to this dispatch desk yet." : "\(Int((pct * 100).rounded()))% fleet availability from the live roster.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func heroChip(_ label: String, _ value: Int) -> some View {
        Text("\(label) \(value)")
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.18))
            .clipShape(Capsule())
    }

    private func commandSeverity(_ s: DashboardStats) -> (title: String, detail: String, symbol: String) {
        let issues = s.issues ?? 0
        let unassigned = s.unassigned ?? 0
        if issues > 0 {
            return ("Exception watch", "\(issues) unresolved dispatch issue\(issues == 1 ? "" : "s") need attention before closeout.", "exclamationmark.triangle.fill")
        }
        if unassigned > 0 {
            return ("Tender gap", "\(unassigned) unassigned shipment\(unassigned == 1 ? "" : "s") should be covered before the next planning window.", "person.crop.circle.badge.exclamationmark")
        }
        return ("Board steady", "No open exceptions in the live KPI envelope.", "checkmark.seal.fill")
    }

    private func nextMove(_ s: DashboardStats) -> (title: String, detail: String) {
        if (s.issues ?? 0) > 0 {
            return ("Clear exception queue", "Open the board and work unresolved incidents before assigning more freight.")
        }
        if (s.unassigned ?? 0) > 0 {
            return ("Assign uncovered freight", "Use driver availability and modal status to cover the unassigned lane list.")
        }
        if (s.loading ?? 0) > 0 {
            return ("Watch loading windows", "Loading freight is moving; keep dwell and ETA changes visible to counterparties.")
        }
        return ("Keep pulse live", "Refresh after the next board change or mode handoff.")
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let s: DashboardStats = try await EusoTripAPI.shared.queryNoInput("dispatch.getDashboardStats")
            stats = s
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("707 · Daily KPI · Night") { DispatchDailyKPIScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("707 · Daily KPI · Afternoon") { DispatchDailyKPIScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
