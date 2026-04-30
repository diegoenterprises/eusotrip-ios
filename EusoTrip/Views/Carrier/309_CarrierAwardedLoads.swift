//
//  309_CarrierAwardedLoads.swift
//  EusoTrip — Carrier · Awarded loads.
//
//  Cross-role chain: shipper.acceptTender / shipper.acceptBid →
//  load.status='assigned' + LOAD_STATUS_CHANGED emit → THIS SCREEN
//  reads via catalysts.getMyAwardedLoads. Carrier-side surface for
//  every Shipper-side acceptance decision.
//

import SwiftUI

struct CarrierAwardedLoadsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { AwardedLoadsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Bids", systemImage: "hand.raised.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct AwardedLoad: Decodable, Identifiable, Hashable {
    let id: String
    let loadNumber: String
    let shipperName: String?
    let lane: String?
    let rate: Double?
    let pickupISO: String?
    let assignedDriverName: String?
    let status: String
}

private struct AwardedLoadsBody: View {
    @Environment(\.palette) private var palette
    @State private var loads: [AwardedLoad] = []
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
                Image(systemName: "checkmark.seal.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CARRIER · AWARDED LOADS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Awarded loads").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading awarded loads…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if loads.isEmpty { EusoEmptyState(systemImage: "checkmark.seal", title: "No awarded loads", subtitle: "When a shipper accepts your bid the load lands here.") }
        else {
            ForEach(loads) { ld in
                Button {
                    NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "311", "loadId": ld.id])
                } label: {
                    LifecycleCard(accentGradient: ld.assignedDriverName == nil) {
                        LifecycleSection(label: ld.loadNumber.uppercased(), icon: "doc.text")
                        LifecycleRow(label: "Shipper",  value: dashIfEmpty(ld.shipperName))
                        LifecycleRow(label: "Lane",     value: dashIfEmpty(ld.lane))
                        LifecycleRow(label: "Rate",     value: usd(ld.rate))
                        LifecycleRow(label: "Pickup",   value: humanISO(ld.pickupISO))
                        LifecycleRow(label: "Driver",   value: dashIfEmpty(ld.assignedDriverName))
                        LifecycleRow(label: "Status",   value: ld.status.uppercased())
                        if ld.assignedDriverName == nil {
                            Text("ASSIGN A DRIVER →").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(LinearGradient.diagonal).clipShape(Capsule())
                        }
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [AwardedLoad] = try await EusoTripAPI.shared.queryNoInput("catalysts.getMyAwardedLoads")
            loads = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("309 · Awarded · Night") { CarrierAwardedLoadsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("309 · Awarded · Afternoon") { CarrierAwardedLoadsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
