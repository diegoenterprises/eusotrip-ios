//
//  315_eSangAssistRankBids.swift
//  EusoTrip — Shipper · eSang · Rank bids (Arc I).
//

import SwiftUI

struct eSangAssistRankBidsScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) { RankBidsBody(loadId: loadId) } nav: { shipperLifecycleNav() }
    }
}

private struct RankResult: Decodable, Hashable {
    struct Pick: Decodable, Hashable, Identifiable {
        let bidId: String
        let catalystName: String
        let amount: Double
        let composite: Double
        let reason: String
        var id: String { bidId }
    }
    let picks: [Pick]
    let summary: String
}

private struct RankBidsBody: View {
    @Environment(\.palette) private var palette
    let loadId: String
    @State private var result: RankResult? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading { LifecycleCard { Text("eSang ranking bids…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let r = result { picksCard(r) }
                else { LifecycleCard { Text("No bids on this load yet — nothing to rank.").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("ESANG · RANK BIDS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Which bid should I take?").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func picksCard(_ r: RankResult) -> some View {
        VStack(spacing: 10) {
            LifecycleCard(accentGradient: true) { Text(r.summary).font(EType.body).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true) }
            ForEach(Array(r.picks.enumerated()), id: \.offset) { i, p in
                LifecycleCard {
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1)").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 26, height: 26).background(LinearGradient.diagonal).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.catalystName).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                            Text("$\(Int(p.amount)) · composite \(String(format: "%.2f", p.composite))").font(EType.caption).foregroundStyle(palette.textSecondary)
                            Text(p.reason).font(EType.caption).foregroundStyle(palette.textTertiary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let loadId: String }
        do {
            let r: RankResult = try await EusoTripAPI.shared.query("esangAI.rankBidsForLoad", input: In(loadId: loadId))
            result = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("315 · Rank bids · Night") { eSangAssistRankBidsScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("315 · Rank bids · Afternoon") { eSangAssistRankBidsScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
