//
//  431_MultiModalTransport.swift
//  EusoTrip — Shipper · Multi-modal (truck / rail / ocean / air).
//

import SwiftUI

struct MultiModalTransportScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { MultiModalBody() } nav: { shipperLifecycleNav() }
    }
}

private struct ModalLeg: Decodable, Identifiable, Hashable {
    let id: String
    let mode: String              // "truck" / "rail" / "vessel" / "air"
    let segment: String
    let etaISO: String?
    let status: String
}

private struct MultiModalBody: View {
    @Environment(\.palette) private var palette
    @State private var legs: [ModalLeg] = []
    @State private var loading = true
    @State private var loadError: String? = nil

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
                Image(systemName: "shuffle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · MULTI-MODAL").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Intermodal legs").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading legs…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if legs.isEmpty { EusoEmptyState(systemImage: "shuffle", title: "No multi-modal legs", subtitle: "Intermodal loads (rail handoff, ocean container, air cargo) surface here.") }
        else {
            ForEach(legs) { leg in
                LifecycleCard {
                    HStack {
                        Image(systemName: modeIcon(leg.mode)).font(.system(size: 22, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(leg.mode.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                            Text(leg.segment).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                            Text("ETA \(humanISO(leg.etaISO))").font(EType.mono(.micro)).tracking(0.4).foregroundStyle(palette.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Text(leg.status.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
    }

    private func modeIcon(_ mode: String) -> String {
        switch mode { case "rail": return "tram.fill"; case "vessel": return "ferry.fill"; case "air": return "airplane"; default: return "truck.box" }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [ModalLeg] = try await EusoTripAPI.shared.api.queryNoInput("shippers.getMultiModalLegs")
            legs = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("431 · Multi-modal · Night") { MultiModalTransportScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("431 · Multi-modal · Afternoon") { MultiModalTransportScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
