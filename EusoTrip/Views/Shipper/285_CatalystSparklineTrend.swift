//
//  285_CatalystSparklineTrend.swift
//  EusoTrip — Shipper · Catalyst trend (Arc F).
//
//  Plots monthly delivered count for this carrier across the
//  shipper's history. Currently derives from `getMyLoads` filtered
//  to the carrier (server gap §5: `shippers.getCatalystTrend` would
//  serve this directly).
//

import SwiftUI

struct CatalystSparklineTrendScreen: View {
    let theme: Theme.Palette
    let catalystId: String
    var body: some View {
        Shell(theme: theme) { CatalystSparklineTrendBody(catalystId: catalystId) } nav: { shipperLifecycleNav() }
    }
}

private struct CatalystSparklineTrendBody: View {
    @Environment(\.palette) private var palette
    let catalystId: String
    @StateObject private var loads = ShipperMyLoadsStore()

    private var monthly: [(month: String, count: Int)] {
        let all = (loads.state.value ?? []).filter { ($0.catalystId ?? "") == catalystId }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM"
        let iso = ISO8601DateFormatter()
        var bucket: [String: Int] = [:]
        for ld in all {
            guard let createdAtRaw = ld.createdAt, let d = iso.date(from: createdAtRaw) else { continue }
            let key = fmt.string(from: d)
            bucket[key, default: 0] += 1
        }
        return bucket.sorted(by: { $0.key < $1.key }).map { ($0.key, $0.value) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                trendCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await loads.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · CATALYST · TREND").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Volume trend").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var trendCard: some View {
        LifecycleCard {
            LifecycleSection(label: "MONTHLY DELIVERED", icon: "calendar")
            if monthly.isEmpty {
                Text("No history with this carrier in the rolling window.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            } else {
                let maxN = monthly.map(\.count).max() ?? 1
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(monthly, id: \.month) { row in
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(LinearGradient.diagonal)
                                .frame(height: max(4, CGFloat(row.count) / CGFloat(maxN) * 80))
                            Text(row.month.suffix(2)).font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 110)
                Text("\(monthly.last?.count ?? 0) loads in latest month")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }
}

#Preview("285 · Trend · Night") {
    CatalystSparklineTrendScreen(theme: Theme.dark, catalystId: "car_1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("285 · Trend · Afternoon") {
    CatalystSparklineTrendScreen(theme: Theme.light, catalystId: "car_1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
