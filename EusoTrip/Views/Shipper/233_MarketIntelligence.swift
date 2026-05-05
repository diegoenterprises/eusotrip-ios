//
//  233_MarketIntelligence.swift
//  EusoTrip — Shipper · Market Intelligence (Operations).
//
//  Founder mandate 2026-05-05: web platform's Market Intelligence
//  has commodity prices (WTI / Brent / gold etc) — iOS Operations
//  only had Hot Zones. This screen ports the canonical macro signal
//  + diesel regionals from `marketIntelligence.*` so the founder
//  has lane-grade rate intel in-app, not just on web.
//
//  Data sources (already wired server-side):
//    • `marketIntelligence.getReconciledMacroSignal` — WTI + diesel
//      + PPI blended into a confidence-scored macro lane signal.
//    • `marketIntelligence.getDieselRegionalLatest` — EIA regional
//      diesel by PADD region.
//    • `marketIntelligence.getMarketSignals` — recent provider
//      observations (DAT, Sonar, etc).
//

import SwiftUI

struct MarketIntelligenceScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { MarketIntelligenceBody() } nav: { shipperLifecycleNav() }
    }
}

private struct MacroProvider: Decodable, Hashable, Identifiable {
    var id: String { provider }
    let provider: String
    let rateRpm: Double?
    let observedAt: String?
    let status: String?
}

private struct MacroSignal: Decodable {
    let available: Bool
    let blendedSignal: Double?
    let confidence: Double?
    let providers: [MacroProvider]?
}

private struct DieselRow: Decodable, Hashable, Identifiable {
    let region: String
    let priceUsdPerGallon: Double?
    let observedAt: String?
    var id: String { region }
}

private struct MarketIntelligenceBody: View {
    @Environment(\.palette) private var palette
    @State private var macro: MacroSignal? = nil
    @State private var diesel: [DieselRow] = []
    @State private var loading = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard {
                        Text("Loading macro signal + diesel regionals…")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                } else {
                    if let m = macro { macroCard(m) }
                    if !diesel.isEmpty { dieselCard(diesel) }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · MARKET INTELLIGENCE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Market Intelligence")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Macro signal · diesel · WTI · PPI · provider feeds")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func macroCard(_ m: MacroSignal) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "MACRO SIGNAL", icon: "chart.line.uptrend.xyaxis")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(m.blendedSignal.map { String(format: "$%.2f", $0) } ?? "—")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text("/ mi blended")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            if let conf = m.confidence {
                LifecycleRow(label: "Confidence", value: String(format: "%.0f%%", conf * 100))
            }
            if let providers = m.providers, !providers.isEmpty {
                Divider().overlay(palette.borderFaint).padding(.vertical, 4)
                ForEach(providers) { p in
                    HStack {
                        Text(p.provider.uppercased())
                            .font(EType.micro).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Spacer(minLength: 0)
                        Text(p.rateRpm.map { String(format: "$%.2f / mi", $0) } ?? "—")
                            .font(.system(size: 12, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func dieselCard(_ rows: [DieselRow]) -> some View {
        LifecycleCard {
            LifecycleSection(label: "DIESEL REGIONALS · EIA", icon: "fuelpump.fill")
            ForEach(rows) { r in
                LifecycleRow(
                    label: r.region,
                    value: r.priceUsdPerGallon.map { String(format: "$%.3f / gal", $0) } ?? "—"
                )
            }
        }
    }

    private func load() async {
        loading = true
        defer { Task { @MainActor in loading = false } }
        async let macroT: Void = loadMacro()
        async let dieselT: Void = loadDiesel()
        _ = await (macroT, dieselT)
    }

    private func loadMacro() async {
        do {
            let m: MacroSignal = try await EusoTripAPI.shared.queryNoInput(
                "marketIntelligence.getReconciledMacroSignal"
            )
            await MainActor.run { macro = m }
        } catch { /* keep prior — silent UX */ }
    }

    private func loadDiesel() async {
        struct Resp: Decodable { let rows: [DieselRow]? }
        do {
            let r: Resp = try await EusoTripAPI.shared.queryNoInput(
                "marketIntelligence.getDieselRegionalLatest"
            )
            await MainActor.run { diesel = r.rows ?? [] }
        } catch { /* silent */ }
    }
}

#Preview("233 · Market Intelligence · Night") {
    MarketIntelligenceScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("233 · Market Intelligence · Afternoon") {
    MarketIntelligenceScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
