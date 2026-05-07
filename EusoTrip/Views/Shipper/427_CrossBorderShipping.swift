//
//  427_CrossBorderShipping.swift
//  EusoTrip — Shipper · Cross-border shipping (customs + USMCA + VUCEM + CARM).
//

import SwiftUI

struct CrossBorderShippingScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { CrossBorderBody() } nav: { shipperLifecycleNav() }
    }
}

private struct CrossBorderEnvelope: Decodable, Hashable {
    struct Lane: Decodable, Hashable, Identifiable {
        let id: String
        let loadNumber: String
        let originCountry: String
        let destinationCountry: String
        let usmcaEligible: Bool
        let customsStatus: String
        let documentsRequired: [String]
    }
    let lanes: [Lane]
    let trustedPrograms: [String]
}

private struct CrossBorderBody: View {
    @Environment(\.palette) private var palette
    @State private var env: CrossBorderEnvelope? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading { LifecycleCard { Text("Loading cross-border lanes…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let e = env { trustedCard(e); lanesCard(e) }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "globe.americas.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · CROSS-BORDER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Cross-border lanes").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func trustedCard(_ e: CrossBorderEnvelope) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "TRUSTED-TRADER PROGRAMS", icon: "checkmark.shield")
            Text(e.trustedPrograms.isEmpty ? "Not enrolled in any" : e.trustedPrograms.joined(separator: " · "))
                .font(EType.body).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func lanesCard(_ e: CrossBorderEnvelope) -> some View {
        VStack(spacing: 8) {
            ForEach(e.lanes) { lane in
                LifecycleCard {
                    LifecycleSection(label: lane.loadNumber.uppercased(), icon: "arrow.left.arrow.right")
                    LifecycleRow(label: "Lane",            value: "\(lane.originCountry) → \(lane.destinationCountry)")
                    LifecycleRow(label: "USMCA-eligible",  value: lane.usmcaEligible ? "Yes" : "No")
                    LifecycleRow(label: "Customs status",  value: lane.customsStatus.uppercased())
                    if !lane.documentsRequired.isEmpty {
                        LifecycleRow(label: "Required docs", value: lane.documentsRequired.joined(separator: ", "))
                    }
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let e: CrossBorderEnvelope = try await EusoTripAPI.shared.queryNoInput("shippers.getCrossBorderSummary")
            env = e
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("427 · Cross-border · Night") { CrossBorderShippingScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("427 · Cross-border · Afternoon") { CrossBorderShippingScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
