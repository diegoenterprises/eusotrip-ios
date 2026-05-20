//
//  323_TierDetail.swift
//  EusoTrip — Shipper · Tier detail (Arc J).
//

import SwiftUI

struct TierDetailScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { TierDetailBody() } nav: { shipperLifecycleNav() }
    }
}

private struct TierDetailBody: View {
    @Environment(\.palette) private var palette
    @State private var stats: ShipperAPI.Stats? = nil
    @State private var loading = true
    /// Inline error surface for stats fetch failures (was an empty
    /// `catch {}` that left the ladder collapsed with no hint).
    @State private var loadError: String? = nil

    private let tiers: [(name: String, threshold: Int, benefits: [String])] = [
        ("Bronze",  0,    ["Base spot rates", "Standard insurance"]),
        ("Silver",  10,   ["Lane-priority routing", "Faster ACH", "Carrier scorecard access"]),
        ("Gold",    50,   ["Volume rebates", "Dedicated dispatcher", "eSang AI ranking"]),
        ("Platinum",250,  ["Net-15 instead of Net-30", "RFP white-label", "Multi-mode rates"]),
        ("Diamond", 1000, ["Bespoke SLAs", "Insurance underwriting", "Founder-line escalation"]),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let s = stats { currentTierCard(s) }
                if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err)
                            .font(EType.caption)
                            .foregroundStyle(Brand.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                ladder
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
    }

    private func load() async {
        loadError = nil
        do {
            stats = try await EusoTripAPI.shared.shipper.getStats()
        } catch let apiErr as EusoTripAPIError {
            loadError = "Couldn't load tier stats: \(apiErr.errorDescription ?? "network error")"
        } catch {
            loadError = "Couldn't load tier stats: \(error.localizedDescription)"
        }
        loading = false
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "rosette").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · TIER LADDER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Your tier ladder").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func currentTierCard(_ s: ShipperAPI.Stats) -> some View {
        let n = s.totalLoads
        let cur = tiers.last(where: { n >= $0.threshold }) ?? tiers[0]
        let nextIdx = (tiers.firstIndex(where: { $0.name == cur.name }) ?? 0) + 1
        let next = nextIdx < tiers.count ? tiers[nextIdx] : nil
        return LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "CURRENT TIER", icon: "rosette")
            LifecycleRow(label: "Tier",        value: cur.name.uppercased())
            LifecycleRow(label: "Loads to date", value: "\(n)")
            if let next = next {
                LifecycleRow(label: "Next",      value: "\(next.name) at \(next.threshold)")
                LifecycleRow(label: "To go",     value: "\(max(0, next.threshold - n)) loads")
            } else {
                LifecycleRow(label: "Next",      value: "Top tier")
            }
        }
    }

    private var ladder: some View {
        VStack(spacing: 8) {
            ForEach(tiers, id: \.name) { tier in
                LifecycleCard {
                    LifecycleSection(label: tier.name.uppercased(), icon: "star.fill")
                    LifecycleRow(label: "Threshold", value: "\(tier.threshold) loads")
                    ForEach(tier.benefits, id: \.self) { benefit in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(LinearGradient.diagonal)
                            Text(benefit).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

#Preview("323 · Tier · Night") { TierDetailScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("323 · Tier · Afternoon") { TierDetailScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
