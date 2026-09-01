//
//  179_DriverFuelEconomy.swift
//  EusoTrip — Screen 179 · Driver Fuel Economy (LIVE-wired)
//
//  Purpose: turn the fuel bus into money — show the MPG benchmark, how much
//  idle is costing, and ranked coaching so the owner-operator knows exactly
//  which habit to fix and what the fix is worth.
//
//  Wiring manifest (server/routers/fuelManagement.ts):
//    fuelManagement.getFuelEfficiencyRanking  EXISTS · fuelManagement.ts:1208
//      output { rankings[{ rank, id, name, mpg, totalGallons, totalSpent,
//               costPerMile, transactions, trend }], fleetAvgMpg }
//      (real fuel_transactions + loads.distance aggregates, last 30 days)
//    fuelManagement.getIdlingReport           EXISTS · fuelManagement.ts:1526
//      output { byVehicle[...], avgPctIdle, totalFuelWasted, totalCostWasted,
//               recommendations[] }
//    fuelManagement.getFuelEfficiencyTips     EXISTS · fuelManagement.ts:1299
//      output { tips[{ id, category, title, impact, priority, description }] }
//  HONEST GAP handed to the-oath: the ranking is fleet-scoped (names read
//  "Driver N"); there is no per-signed-in-driver MPG identity join, so the
//  hero shows the real FLEET benchmark rather than fabricating a personal
//  "top 18%". Proposed: getMyFuelEconomy({ driverId }) → personal MPG +
//  percentile. Read-only analytics (no mutation).
//  transportMode = truck · currency USD.
//
//  Persona: Michael Eusorone (ME) · Eusotrans LLC · USDOT 3 194 882 · DR-00427.
//

import SwiftUI

// MARK: - Wire models

private struct FuelRanking: Decodable, Identifiable {
    let rank: Int
    let id: String
    let name: String
    let mpg: Double
    let trend: String
}
private struct FuelRankResult: Decodable { let rankings: [FuelRanking]; let fleetAvgMpg: Double }

private struct IdleReport: Decodable {
    let avgPctIdle: Double?
    let totalFuelWasted: Double?
    let totalCostWasted: Double?
}

private struct FuelTip: Decodable, Identifiable {
    let id: Int
    let category: String
    let title: String
    let impact: String
    let priority: String
}
private struct FuelTips: Decodable { let tips: [FuelTip] }

// MARK: - ViewModel

@MainActor
private final class FuelEconomyViewModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, ready, error(String) }
    @Published var phase: Phase = .idle
    @Published var ranking: FuelRankResult?
    @Published var idle: IdleReport?
    @Published var tips: [FuelTip] = []

    func load() async {
        phase = .loading
        do {
            async let r: FuelRankResult = EusoTripAPI.shared.queryNoInput("fuelManagement.getFuelEfficiencyRanking")
            async let i: IdleReport = EusoTripAPI.shared.queryNoInput("fuelManagement.getIdlingReport")
            async let t: FuelTips = EusoTripAPI.shared.queryNoInput("fuelManagement.getFuelEfficiencyTips")
            ranking = try await r
            idle = try? await i
            tips = (try? await t)?.tips ?? []
            phase = .ready
        } catch {
            phase = .error("Couldn't reach the fuel-economy feed.")
        }
    }

    var topByMpg: [FuelRanking] {
        (ranking?.rankings ?? []).sorted { $0.mpg > $1.mpg }
    }
}

// MARK: - Screen body

struct FuelEconomyView: View {
    @Environment(\.palette) var palette
    @StateObject private var vm = FuelEconomyViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DriverUtilityHeader(eyebrow: "DRIVER · ECO", caption: "LAST 30 DAYS",
                                title: "Fuel economy",
                                subtitle: "MPG · idle · coaching",
                                rightTop: "MICHAEL EUSORONE · DR-00427",
                                rightBottom: "Eusotrans LLC")
            IridescentHairline().padding(.top, Space.s3)
            switch vm.phase {
            case .idle, .loading: DriverUtilityLoading(text: "Crunching the fuel bus…")
            case .error(let m):   DriverUtilityError(message: m) { Task { await vm.load() } }
            case .ready:          content
            }
        }
        .task { if case .idle = vm.phase { await vm.load() } }
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: Space.s4) {
            mpgHero
            if let i = vm.idle { dutyMixCard(i) }
            coachingCard
            leaderboardCard
            CTAButton(title: "Refresh", action: { Task { await vm.load() } },
                      leadingIcon: "arrow.clockwise")
            footnote
        }
        .padding(Space.s5)
    }

    private var mpgHero: some View {
        let avg = vm.ranking?.fleetAvgMpg ?? 0
        let best = vm.topByMpg.first?.mpg ?? 0
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("FLEET AVG MPG · 30 DAYS").font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(vm.ranking?.rankings.count ?? 0) DRIVERS").font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(avg > 0 ? String(format: "%.1f", avg) : "—")
                    .font(EType.display).foregroundStyle(LinearGradient.diagonal)
                Text("mpg benchmark").font(EType.body).foregroundStyle(palette.textSecondary)
                Spacer()
                if best > 0 {
                    Text(String(format: "best %.1f", best))
                        .font(EType.mono(.caption)).fontWeight(.bold).foregroundStyle(Brand.success)
                }
            }
            Text("This is your fleet's rolling benchmark from the fuel bus + delivered-load miles. Beat it and every tenth of an MPG is money in your pocket.")
                .font(EType.caption).foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    private func dutyMixCard(_ i: IdleReport) -> some View {
        let idlePct = i.avgPctIdle ?? 0
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("ENGINE DUTY · IDLE").font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if let cost = i.totalCostWasted, cost > 0 {
                    Text(money(cost) + " wasted").font(EType.mono(.caption)).fontWeight(.bold)
                        .foregroundStyle(Brand.warning)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text("\(Int(idlePct.rounded()))%")
                    .font(EType.h1).foregroundStyle(idlePct > 20 ? Brand.danger : (idlePct > 10 ? Brand.warning : Brand.success))
                Text("idle").font(EType.body).foregroundStyle(palette.textSecondary)
                Spacer()
                if let gal = i.totalFuelWasted, gal > 0 {
                    Text(String(format: "%.0f gal", gal)).font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            GeometryReader { geo in
                let frac = min(max(idlePct / 100, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Brand.success.opacity(0.35))
                    Capsule().fill(idlePct > 20 ? Brand.danger : Brand.warning)
                        .frame(width: max(geo.size.width * frac, 4))
                }
            }
            .frame(height: 8)
            Text(idlePct > 20 ? "Excessive idle — an APU or a 5-minute shutdown timer pays for itself fast."
                 : idlePct > 10 ? "Idle is in the acceptable band. Trimming it is the fastest MPG win."
                 : "Idle is optimal. Keep it up.")
                .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private var coachingCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 26, height: 26)
                    Text("E").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                }
                Text("ESANG COACHING · IMPACT").font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
            }
            if vm.tips.isEmpty {
                DriverUtilityEmpty(systemImage: "sparkles",
                                   title: "No coaching tips yet",
                                   detail: "As the fuel bus builds history, ESANG surfaces the habit that's costing you the most.")
            } else {
                ForEach(vm.prioritizedTips.prefix(4)) { tip in
                    coachRow(tip)
                    if tip.id != vm.prioritizedTips.prefix(4).last?.id {
                        Divider().overlay(palette.borderFaint)
                    }
                }
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func coachRow(_ tip: FuelTip) -> some View {
        HStack(alignment: .top) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.success)
            VStack(alignment: .leading, spacing: 1) {
                Text(tip.title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text(tip.category).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text(tip.impact).font(EType.mono(.caption)).fontWeight(.bold)
                .foregroundStyle(Brand.success).multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private var leaderboardCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("FLEET MPG LEADERS").font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("MPG").font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
            }
            if vm.topByMpg.isEmpty {
                DriverUtilityEmpty(systemImage: "chart.bar",
                                   title: "No fuel data yet",
                                   detail: "Fuel-card transactions build this leaderboard as they post.")
            } else {
                ForEach(Array(vm.topByMpg.prefix(4).enumerated()), id: \.element.id) { idx, r in
                    leaderRow(idx + 1, r)
                    if idx < min(3, vm.topByMpg.count - 1) { Divider().overlay(palette.borderFaint) }
                }
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func leaderRow(_ place: Int, _ r: FuelRanking) -> some View {
        HStack {
            Text("\(place)").font(EType.mono(.caption)).fontWeight(.bold)
                .foregroundStyle(palette.textTertiary).frame(width: 18, alignment: .leading)
            Text(r.name).font(EType.body).foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: r.trend == "improving" ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(r.trend == "improving" ? Brand.success : Brand.warning)
            Text(String(format: "%.1f", r.mpg)).font(EType.mono(.caption)).fontWeight(.bold)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.vertical, 2)
    }

    private var footnote: some View {
        Text("ELD engine-bus MPG + idle · fleet rank by lane and equipment class.")
            .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func money(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.maximumFractionDigits = 0
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}

private extension FuelEconomyViewModel {
    var prioritizedTips: [FuelTip] {
        let order: [String: Int] = ["high": 0, "medium": 1, "low": 2]
        return tips.sorted { (order[$0.priority.lowercased()] ?? 3) < (order[$1.priority.lowercased()] ?? 3) }
    }
}

// MARK: - Screen (Shell + Driver nav · TRIPS current)

struct FuelEconomyScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            FuelEconomyView()
        } nav: {
            BottomNav(leading: driverUtilityNavLeading(tripsCurrent: true),
                      trailing: driverUtilityNavTrailing(), orbState: .idle)
        }
    }
}

#Preview("Fuel Economy · Dark") {
    FuelEconomyScreen(theme: Theme.dark)
        .preferredColorScheme(.dark).environment(\.palette, Theme.dark)
        .background(Theme.dark.bgPage)
}
#Preview("Fuel Economy · Light") {
    FuelEconomyScreen(theme: Theme.light)
        .preferredColorScheme(.light).environment(\.palette, Theme.light)
        .background(Theme.light.bgPage)
}
