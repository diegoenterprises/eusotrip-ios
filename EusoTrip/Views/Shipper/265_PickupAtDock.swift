//
//  265_PickupAtDock.swift
//  EusoTrip — Shipper · Stage 4 · PICKUP · at dock (refactored).
//

import SwiftUI

struct PickupAtDockScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) {
            LifecycleScaffold(loadId: loadId, eyebrow: "SHIPPER · PICKUP · AT DOCK · STAGE 4 OF 8", cycleStatus: "loading") { live in
                AtDockBody(live: live)
            }
        } nav: { shipperLifecycleNav() }
    }
}

private struct AtDockBody: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            statusCard
            facilityCard
            cargoCard
        }
    }

    private var statusCard: some View {
        LifecycleCard {
            LifecycleSection(label: "DOCK STATUS", icon: "arrow.up.bin.fill")
            LifecycleRow(label: "Stop status",  value: dashIfEmpty(live.pickup?.status.uppercased()))
            LifecycleRow(label: "Arrived at",   value: humanISO(live.pickup?.arrivedAt))
            if let dwell = live.lastGeofence?.dwellSeconds {
                LifecycleRow(label: "Dwell", value: "\(dwell / 60) min")
            }
        }
    }

    private var facilityCard: some View {
        LifecycleCard {
            LifecycleSection(label: "FACILITY", icon: "building.2.fill")
            LifecycleRow(label: "Facility", value: dashIfEmpty(live.pickup?.facilityName))
            LifecycleRow(label: "Address",  value: dashIfEmpty(live.pickup?.address))
            LifecycleRow(label: "Notes",    value: dashIfEmpty(live.pickup?.notes))
        }
    }

    private var cargoCard: some View {
        LifecycleCard {
            LifecycleSection(label: "CARGO", icon: "shippingbox")
            LifecycleRow(label: "Cargo type", value: dashIfEmpty(live.load.cargoType))
            LifecycleRow(label: "Equipment",  value: dashIfEmpty(live.load.equipmentType))
            LifecycleRow(label: "Weight",     value: live.load.weight.map { "\(Int($0)) lb" } ?? "—")
            if live.load.hazmatClass?.isEmpty == false {
                LifecycleRow(label: "Hazmat", value: "Class \(dashIfEmpty(live.load.hazmatClass)) · UN \(dashIfEmpty(live.load.unNumber))")
            }
        }
    }
}

#Preview("265 · Pickup · At dock · Night") {
    PickupAtDockScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("265 · Pickup · At dock · Afternoon") {
    PickupAtDockScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
