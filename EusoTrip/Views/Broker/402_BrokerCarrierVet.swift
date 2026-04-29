//
//  402_BrokerCarrierVet.swift
//  EusoTrip — Broker · Carrier vetting (Highway / RMIS / Carrier411 / Carrier Assure).
//

import SwiftUI

struct BrokerCarrierVetScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) { CarrierVetBody(loadId: loadId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Carriers", systemImage: "person.3.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VetCandidate: Decodable, Identifiable, Hashable {
    let catalystId: String
    let name: String
    let dotNumber: String
    let mcNumber: String?
    let safetyRating: String?
    let highwayScore: Double?         // Highway-style identity / fraud confidence
    let rmisOnboarded: Bool?
    let insuranceFiling: Bool?
    let oosViolations: Int?
    let lanesCovered: [String]?
    var id: String { catalystId }
}

private struct CarrierVetBody: View {
    @Environment(\.palette) private var palette
    let loadId: String
    @State private var candidates: [VetCandidate] = []
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
                Image(systemName: "checkmark.shield.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("BROKER · CARRIER VET").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Vet carriers for this lane").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Highway identity + RMIS onboard + FMCSA authority + insurance filing + OOS history. Tap to tender.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Vetting carriers…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if candidates.isEmpty { EusoEmptyState(systemImage: "person.3", title: "No matched carriers", subtitle: "Lane-eligible carriers with cleared identity surface here.") }
        else {
            ForEach(candidates) { c in
                Button {
                    NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "403", "loadId": loadId, "catalystId": c.catalystId])
                } label: {
                    LifecycleCard(accentGradient: (c.highwayScore ?? 0) > 0.85) {
                        LifecycleSection(label: c.name.uppercased(), icon: "person.2")
                        LifecycleRow(label: "USDOT",            value: c.dotNumber)
                        LifecycleRow(label: "MC",               value: dashIfEmpty(c.mcNumber))
                        LifecycleRow(label: "Safety",           value: dashIfEmpty(c.safetyRating))
                        LifecycleRow(label: "Highway score",     value: c.highwayScore.map { String(format: "%.2f", $0) } ?? "—")
                        LifecycleRow(label: "RMIS",              value: c.rmisOnboarded == true ? "Onboarded" : "—")
                        LifecycleRow(label: "Insurance",         value: c.insuranceFiling == true ? "Filed" : "—")
                        LifecycleRow(label: "OOS",               value: "\(c.oosViolations ?? 0)")
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let loadId: String }
        do {
            let r: [VetCandidate] = try await EusoTripAPI.shared.api.query("brokers.getVetCandidates", input: In(loadId: loadId))
            candidates = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("402 · Carrier vet · Night") { BrokerCarrierVetScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("402 · Carrier vet · Afternoon") { BrokerCarrierVetScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
