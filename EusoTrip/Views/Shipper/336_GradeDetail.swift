//
//  336_GradeDetail.swift
//  EusoTrip — Shipper · Catalyst grade detail (Arc J).
//

import SwiftUI

struct GradeDetailScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { GradeDetailBody() } nav: { shipperLifecycleNav() }
    }
}

private struct GradeDetailBody: View {
    @Environment(\.palette) private var palette
    @StateObject private var perf = ShipperCatalystPerformanceStore()

    private let gradeBuckets: [(label: String, min: Double, max: Double)] = [
        ("A+", 0.97, 1.00),
        ("A",  0.93, 0.97),
        ("A-", 0.90, 0.93),
        ("B+", 0.87, 0.90),
        ("B",  0.80, 0.87),
        ("C",  0.70, 0.80),
        ("D",  0.00, 0.70),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                formulaCard
                bucketsCard
                distributionCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await perf.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · CATALYST GRADE EXPLAINER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("How carriers are graded").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var formulaCard: some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "COMPOSITE FORMULA", icon: "function")
            Text("Composite = on-time × 0.5 + completion × 0.3 + log₁₀(loads + 1) / log₁₀(50) × 0.2").font(EType.body).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bucketsCard: some View {
        LifecycleCard {
            LifecycleSection(label: "GRADE BUCKETS", icon: "rosette")
            ForEach(gradeBuckets, id: \.label) { b in
                LifecycleRow(label: b.label, value: String(format: "%.2f – %.2f", b.min, b.max))
            }
        }
    }

    private var distributionCard: some View {
        let rows = perf.state.value ?? []
        let counts: [String: Int] = rows.reduce(into: [:]) { dict, r in
            let comp = computeComposite(r)
            let label = gradeBuckets.first(where: { comp >= $0.min && comp < $0.max })?.label ?? "—"
            dict[label, default: 0] += 1
        }
        return LifecycleCard {
            LifecycleSection(label: "YOUR PORTFOLIO", icon: "person.3.fill")
            ForEach(gradeBuckets, id: \.label) { b in
                LifecycleRow(label: b.label, value: "\(counts[b.label, default: 0]) carriers")
            }
        }
    }

    private func computeComposite(_ r: ShipperAPI.CatalystPerformance) -> Double {
        let onTime = Double(r.onTimeRate) / 100
        let completion = r.totalLoads > 0 ? Double(r.delivered) / Double(r.totalLoads) : 0
        let volume = log10(Double(r.totalLoads) + 1) / log10(50)
        return onTime * 0.5 + completion * 0.3 + min(1, volume) * 0.2
    }
}

#Preview("336 · Grade · Night") { GradeDetailScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("336 · Grade · Afternoon") { GradeDetailScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
