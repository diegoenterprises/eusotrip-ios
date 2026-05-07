//
//  283_CatalystRatings.swift
//  EusoTrip — Shipper · Catalyst ratings & reviews (Arc F).
//  Until `ratings.list` ships server-side (no current endpoint per
//  audit), this surface renders the existing performance data with
//  composite-score explanation. Honest empty state for review text.
//

import SwiftUI

struct CatalystRatingsScreen: View {
    let theme: Theme.Palette
    let catalystId: String
    var body: some View {
        Shell(theme: theme) { CatalystRatingsBody(catalystId: catalystId) } nav: { shipperLifecycleNav() }
    }
}

private struct CatalystRatingsBody: View {
    @Environment(\.palette) private var palette
    let catalystId: String
    @StateObject private var perf = ShipperCatalystPerformanceStore()

    private var row: ShipperAPI.CatalystPerformance? {
        perf.state.value?.first(where: { $0.catalystId == catalystId })
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let r = row { compositeCard(r) } else { emptyCard }
                reviewListCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await perf.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "star.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · CATALYST · RATINGS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Ratings & reviews").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func compositeCard(_ r: ShipperAPI.CatalystPerformance) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "COMPOSITE SCORE", icon: "chart.bar.fill")
            LifecycleRow(label: "On-time",   value: "\(r.onTimeRate)%")
            LifecycleRow(label: "Completion", value: r.totalLoads > 0 ? "\(Int(Double(r.delivered) / Double(r.totalLoads) * 100))%" : "—")
            LifecycleRow(label: "Loads",     value: "\(r.totalLoads)")
            Text("Composite = on-time × 0.5 + completion × 0.3 + log₁₀(loads+1)/log₁₀(50) × 0.2")
                .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyCard: some View {
        LifecycleCard {
            Text("Carrier not in this window's directory.").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var reviewListCard: some View {
        LifecycleCard {
            LifecycleSection(label: "REVIEWS", icon: "text.bubble")
            Text("Per-load reviews ship in a future round (server `ratings.listForCatalyst` not yet exposed). Composite score above is the live signal until then.")
                .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("283 · Ratings · Night") {
    CatalystRatingsScreen(theme: Theme.dark, catalystId: "car_1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("283 · Ratings · Afternoon") {
    CatalystRatingsScreen(theme: Theme.light, catalystId: "car_1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
