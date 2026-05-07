//
//  429_CompetitiveIntelligence.swift
//  EusoTrip — Shipper · Competitive intelligence (market benchmarking).
//

import SwiftUI

struct CompetitiveIntelligenceScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { CompIntelBody() } nav: { shipperLifecycleNav() }
    }
}

private struct CompIntel: Decodable, Hashable {
    let myAvgRate: Double?
    let marketAvgRate: Double?
    let myOnTime: Int?
    let marketOnTime: Int?
    let myCo2PerLoad: Double?
    let marketCo2PerLoad: Double?
    let lanePosition: String?    // "top quartile" / "median" / "lagging"
    let recommendations: [String]?
}

private struct CompIntelBody: View {
    @Environment(\.palette) private var palette
    @State private var data: CompIntel? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading { LifecycleCard { Text("Loading benchmarks…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let d = data { positionCard(d); benchmarksCard(d); recsCard(d) }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.xaxis").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · COMPETITIVE INTEL").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Market benchmarking").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func positionCard(_ d: CompIntel) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "LANE POSITION", icon: "trophy")
            Text(dashIfEmpty(d.lanePosition?.uppercased())).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func benchmarksCard(_ d: CompIntel) -> some View {
        LifecycleCard {
            LifecycleSection(label: "BENCHMARKS", icon: "chart.line.uptrend.xyaxis")
            LifecycleRow(label: "Avg rate · me",      value: usd(d.myAvgRate))
            LifecycleRow(label: "Avg rate · market",  value: usd(d.marketAvgRate))
            LifecycleRow(label: "On-time · me",       value: d.myOnTime.map { "\($0)%" } ?? "—")
            LifecycleRow(label: "On-time · market",   value: d.marketOnTime.map { "\($0)%" } ?? "—")
            LifecycleRow(label: "CO₂/load · me",      value: d.myCo2PerLoad.map { String(format: "%.2f t", $0) } ?? "—")
            LifecycleRow(label: "CO₂/load · market",  value: d.marketCo2PerLoad.map { String(format: "%.2f t", $0) } ?? "—")
        }
    }

    @ViewBuilder
    private func recsCard(_ d: CompIntel) -> some View {
        if let recs = d.recommendations, !recs.isEmpty {
            LifecycleCard {
                LifecycleSection(label: "ESANG · ACTIONS", icon: "sparkles")
                ForEach(Array(recs.enumerated()), id: \.offset) { _, r in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(LinearGradient.diagonal).padding(.top, 6)
                        Text(r).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: CompIntel = try await EusoTripAPI.shared.queryNoInput("shippers.getCompetitiveIntelligence")
            data = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("429 · Comp intel · Night") { CompetitiveIntelligenceScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("429 · Comp intel · Afternoon") { CompetitiveIntelligenceScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
