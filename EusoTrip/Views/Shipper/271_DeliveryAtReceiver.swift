//
//  271_DeliveryAtReceiver.swift
//  EusoTrip — Shipper · Stage 6 · DELIVERY · at receiver (refactored).
//

import SwiftUI

struct DeliveryAtReceiverScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) {
            LifecycleScaffold(loadId: loadId, eyebrow: "SHIPPER · DELIVERY · AT RECEIVER · STAGE 6 OF 8", cycleStatus: "at_delivery") { live in
                AtReceiverBody(live: live, loadId: loadId)
            }
        } nav: { shipperLifecycleNav() }
    }
}

private struct AtReceiverBody: View {
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
            arrivalCard
            receiverCard
            podCard
        }
    }

    private var arrivalCard: some View {
        LifecycleCard {
            LifecycleSection(label: "ARRIVAL", icon: "checkmark.shield.fill")
            LifecycleRow(label: "Status",     value: dashIfEmpty(live.delivery?.status.uppercased()))
            LifecycleRow(label: "Arrived at", value: humanISO(live.delivery?.arrivedAt))
            LifecycleRow(label: "Departed",   value: humanISO(live.delivery?.departedAt))
        }
    }

    private var receiverCard: some View {
        LifecycleCard {
            LifecycleSection(label: "RECEIVER", icon: "building.2.fill")
            LifecycleRow(label: "Facility", value: dashIfEmpty(live.delivery?.facilityName))
            LifecycleRow(label: "Address",  value: dashIfEmpty(live.delivery?.address))
            LifecycleRow(label: "Contact",  value: dashIfEmpty(live.delivery?.contactName))
            LifecycleRow(label: "Phone",    value: dashIfEmpty(live.delivery?.contactPhone))
        }
    }

    private var podCard: some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: TransportLexicon.short(.proofOfDelivery, mode: loadMode, equipmentRaw: live.load.equipmentType), icon: "doc.text.viewfinder")
            Text("Receiver must sign POD before driver leaves the dock. Counter-signature is automatic on receipt.")
                .font(EType.body).foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "300", "loadId": loadId, "doc": "pod"])
            } label: {
                Text("Open \(TransportLexicon.short(.proofOfDelivery, mode: loadMode, equipmentRaw: live.load.equipmentType)) viewer")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
    }
}

#Preview("271 · Delivery · At receiver · Night") {
    DeliveryAtReceiverScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("271 · Delivery · At receiver · Afternoon") {
    DeliveryAtReceiverScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
