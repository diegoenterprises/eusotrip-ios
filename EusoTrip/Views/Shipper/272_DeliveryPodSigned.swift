//
//  272_DeliveryPodSigned.swift
//  EusoTrip — Shipper · Stage 6 · DELIVERY · POD signed (refactored).
//

import SwiftUI

struct DeliveryPodSignedScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) {
            LifecycleScaffold(loadId: loadId, eyebrow: "SHIPPER · DELIVERY · POD SIGNED · STAGE 6 OF 8", cycleStatus: "pod_pending") { live in
                PodSignedBody(live: live, loadId: loadId)
            }
        } nav: { shipperLifecycleNav() }
    }
}

private struct PodSignedBody: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot
    let loadId: String

    /// The snapshot carries no `transportMode` column — only `equipmentType`.
    /// Derive the base mode from the equipment keyword (same rail*/vessel*
    /// convention the LifecycleScaffold uses) so mode-dependent labels speak
    /// the load's language; default to truck.
    private var loadMode: TransportMode {
        let e = (live.load.equipmentType ?? "").lowercased()
        if e.contains("rail") || e.contains("tofc") || e.contains("cofc")
            || e.contains("boxcar") || e.contains("hopper") || e.contains("gondola")
            || e.contains("centerbeam") || e.contains("autorack") || e.contains("flatcar")
            || e.contains("well car") { return .rail }
        if e.contains("vessel") || e.contains("container ship") || e.contains("vlcc")
            || e.contains("bulk carrier") || e.contains("ro/ro") || e.contains("roro")
            || e.contains("lng") || e.contains("iso tank") { return .vessel }
        if e.contains("barge") { return .barge }
        return .truck
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            confirmationCard
            unloadWindowCard
            ctaRow
        }
    }

    private var confirmationCard: some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: TransportLexicon.short(.delivered, mode: loadMode, equipmentRaw: live.load.equipmentType).uppercased(), icon: "checkmark.seal.fill")
            LifecycleRow(label: TransportLexicon.short(.delivered, mode: loadMode, equipmentRaw: live.load.equipmentType),  value: humanISO(live.load.actualDeliveryDate ?? live.delivery?.departedAt))
            LifecycleRow(label: "Receiver",   value: dashIfEmpty(live.delivery?.contactName))
            LifecycleRow(label: "Driver",     value: dashIfEmpty(live.driver?.name))
            LifecycleRow(label: "Status",     value: live.load.status.uppercased())
        }
    }

    private var unloadWindowCard: some View {
        LifecycleCard {
            LifecycleSection(label: "\(loadMode.unloadingVerb) WINDOW", icon: "clock.arrow.2.circlepath")
            LifecycleRow(label: "Arrived",  value: humanISO(live.delivery?.arrivedAt))
            LifecycleRow(label: "Departed", value: humanISO(live.delivery?.departedAt))
            LifecycleRow(label: "Notes",    value: dashIfEmpty(live.delivery?.notes))
        }
    }

    private var ctaRow: some View {
        Button {
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "226", "loadId": loadId])
        } label: {
            Text("View paperwork").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain)
    }
}

#Preview("272 · Delivery · POD signed · Night") {
    DeliveryPodSignedScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("272 · Delivery · POD signed · Afternoon") {
    DeliveryPodSignedScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
