//
//  421_LoadConsolidation.swift
//  EusoTrip — Shipper · Load consolidation.
//

import SwiftUI

struct LoadConsolidationScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { LoadConsolBody() } nav: { shipperLifecycleNav() }
    }
}

private struct ConsolGroup: Decodable, Identifiable, Hashable {
    let id: String
    let lane: String
    let loadIds: [String]
    let combinedRate: Double?
    let savingsUsd: Double?
    let mode: String?     // "stop_chain" | "lane_split"
}

private struct LoadConsolBody: View {
    @Environment(\.palette) private var palette
    @State private var groups: [ConsolGroup] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var executing: String? = nil

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
                Image(systemName: "arrow.triangle.merge").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · LOAD CONSOLIDATION").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Consolidation suggestions").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("ESANG groups loads on overlapping lanes for stop-chain or lane-split consolidation. Each suggestion reports the savings.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading suggestions…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if groups.isEmpty { EusoEmptyState(systemImage: "arrow.triangle.merge", title: "No consolidations available", subtitle: "ESANG suggests grouping when 2+ loads share lane segments.") }
        else {
            ForEach(groups) { g in
                LifecycleCard(accentGradient: true) {
                    LifecycleSection(label: dashIfEmpty(g.mode?.uppercased()), icon: "arrow.triangle.merge")
                    LifecycleRow(label: "Lane",          value: g.lane)
                    LifecycleRow(label: "Loads",         value: "\(g.loadIds.count)")
                    LifecycleRow(label: "Combined rate",  value: usd(g.combinedRate))
                    LifecycleRow(label: "Savings",        value: usd(g.savingsUsd))
                    Button { Task { await execute(g.id) } } label: {
                        HStack(spacing: 6) {
                            if executing == g.id { ProgressView().tint(.white) }
                            Text(executing == g.id ? "Consolidating…" : "Consolidate").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                    }.buttonStyle(.plain).disabled(executing != nil)
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [ConsolGroup] = try await EusoTripAPI.shared.api.queryNoInput("shippers.getConsolidationSuggestions")
            groups = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func execute(_ id: String) async {
        executing = id
        struct In: Encodable { let groupId: String }
        struct Out: Decodable { let success: Bool; let consolidatedLoadId: String? }
        let _ : Out = (try? await EusoTripAPI.shared.api.mutation("shippers.executeConsolidation", input: In(groupId: id))) ?? Out(success: false, consolidatedLoadId: nil)
        await load()
        executing = nil
    }
}

#Preview("421 · Consolidation · Night") { LoadConsolidationScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("421 · Consolidation · Afternoon") { LoadConsolidationScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
