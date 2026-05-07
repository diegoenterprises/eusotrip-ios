//
//  298_Sustainability.swift
//  EusoTrip — Shipper · Sustainability (Arc G).
//  Backed by `co2Calculator.shipperSummary` (existing per audit).
//

import SwiftUI

struct SustainabilityScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { SustainabilityBody() } nav: { shipperLifecycleNav() }
    }
}

private struct CO2Summary: Decodable, Hashable {
    let ytdTons: Double?
    let mtdTons: Double?
    let perShipmentTons: Double?
    let treesEquivalent: Int?
    let milesGreen: Double?
    let totalMiles: Double?
}

private struct SustainabilityBody: View {
    @Environment(\.palette) private var palette
    @State private var summary: CO2Summary? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let s = summary { hero(s); breakdownCard(s); equivalenceCard(s) }
                else if loading { LifecycleCard { Text("Loading carbon snapshot…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "leaf").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · SUSTAINABILITY").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Carbon footprint").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func hero(_ s: CO2Summary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YTD CO₂ EMITTED").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(.white.opacity(0.85))
            Text(s.ytdTons.map { String(format: "%.1f t", $0) } ?? "—").font(.system(size: 28, weight: .heavy)).foregroundStyle(.white).monospacedDigit()
            HStack(spacing: 8) {
                Text("MTD \(s.mtdTons.map { String(format: "%.1f t", $0) } ?? "—")").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.18)).clipShape(Capsule())
                if let t = s.treesEquivalent {
                    Text("\(t) TREES EQUIV").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.18)).clipShape(Capsule())
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.diagonal)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func breakdownCard(_ s: CO2Summary) -> some View {
        LifecycleCard {
            LifecycleSection(label: "MILES", icon: "ruler")
            LifecycleRow(label: "Total miles", value: s.totalMiles.map { "\(Int($0)) mi" } ?? "—")
            LifecycleRow(label: "Green miles", value: s.milesGreen.map { "\(Int($0)) mi" } ?? "—")
            if let total = s.totalMiles, let g = s.milesGreen, total > 0 {
                LifecycleRow(label: "Green %", value: String(format: "%.1f%%", g / total * 100))
            }
        }
    }

    private func equivalenceCard(_ s: CO2Summary) -> some View {
        LifecycleCard {
            LifecycleSection(label: "PER SHIPMENT", icon: "shippingbox")
            LifecycleRow(label: "Avg CO₂ per shipment", value: s.perShipmentTons.map { String(format: "%.2f t", $0) } ?? "—")
            Text("CO₂ tonnage is computed by `co2Calculator` from miles + equipment + cargo. Lower numbers come from rail / vessel mode mix and load-consolidation.")
                .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let s: CO2Summary = try await EusoTripAPI.shared.queryNoInput("co2Calculator.shipperSummary")
            summary = s
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("298 · Sustainability · Night") {
    SustainabilityScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("298 · Sustainability · Afternoon") {
    SustainabilityScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
