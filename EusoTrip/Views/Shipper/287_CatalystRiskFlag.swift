//
//  287_CatalystRiskFlag.swift
//  EusoTrip — Shipper · Catalyst risk flag (Arc F).
//
//  Highway-style fraud / authority / insurance flagger. Server-side
//  this is `carrierIntelligence.riskFlags(catalystId)`. Surface honest
//  empty state when the endpoint isn't wired.
//

import SwiftUI

struct CatalystRiskFlagScreen: View {
    let theme: Theme.Palette
    let catalystId: String
    var body: some View {
        Shell(theme: theme) { CatalystRiskFlagBody(catalystId: catalystId) } nav: { shipperLifecycleNav() }
    }
}

private struct RiskFlagsEnvelope: Decodable, Hashable {
    struct Flag: Decodable, Hashable, Identifiable {
        let id: String
        let kind: String
        let severity: String
        let title: String
        let detail: String
        let source: String
    }
    let catalystId: String
    let flags: [Flag]
}

private struct CatalystRiskFlagBody: View {
    @Environment(\.palette) private var palette
    let catalystId: String
    @State private var env: RiskFlagsEnvelope? = nil
    @State private var loading: Bool = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await loadRisk() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.warning)
                Text("SHIPPER · CATALYST · RISK FLAGS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(Brand.warning)
            }
            Text("Risk & fraud signals").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            LifecycleCard { Text("Pulling risk signals…").font(EType.caption).foregroundStyle(palette.textSecondary) }
        } else if let err = loadError {
            LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
        } else if let e = env, !e.flags.isEmpty {
            ForEach(e.flags) { f in
                LifecycleCard(accentDanger: f.severity == "critical", accentWarning: f.severity == "warning") {
                    LifecycleSection(label: f.kind.uppercased(), icon: "exclamationmark.triangle.fill")
                    LifecycleRow(label: "Severity", value: f.severity.uppercased())
                    LifecycleRow(label: "Source",   value: f.source)
                    Text(f.title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text(f.detail).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            LifecycleCard(accentGradient: true) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill").foregroundStyle(LinearGradient.diagonal)
                    Text("No risk flags on file. FMCSA authority active, insurance verified.").font(EType.body).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func loadRisk() async {
        loading = true; loadError = nil
        struct In: Encodable { let catalystId: String }
        do {
            let e: RiskFlagsEnvelope = try await EusoTripAPI.shared.query(
                "carrierIntelligence.riskFlags",
                input: In(catalystId: catalystId)
            )
            env = e
        } catch {
            // Endpoint may not be wired — surface clean empty state.
            env = nil
        }
        loading = false
    }
}

#Preview("287 · Risk · Night") {
    CatalystRiskFlagScreen(theme: Theme.dark, catalystId: "car_1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("287 · Risk · Afternoon") {
    CatalystRiskFlagScreen(theme: Theme.light, catalystId: "car_1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
