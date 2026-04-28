//
//  270_DeliveryApproaching.swift
//  EusoTrip — Shipper · Stage 6 · DELIVERY · approaching (refactored).
//

import SwiftUI

struct DeliveryApproachingScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) {
            LifecycleScaffold(loadId: loadId, eyebrow: "SHIPPER · DELIVERY · APPROACHING · STAGE 6 OF 8", cycleStatus: "approaching_delivery") { live in
                DeliveryApproachingBody(live: live)
            }
        } nav: { shipperLifecycleNav() }
    }
}

private struct DeliveryApproachingBody: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            geofenceCard
            receiverCard
            etaStrip
        }
    }

    private var geofenceCard: some View {
        LifecycleCard {
            LifecycleSection(label: "GEOFENCE", icon: "dot.radiowaves.left.and.right")
            if let g = live.lastGeofence {
                LifecycleRow(label: "Type",      value: g.type.uppercased())
                LifecycleRow(label: "Recorded",  value: humanISO(g.eventTimestamp))
                LifecycleRow(label: "GPS",       value: String(format: "%.4f, %.4f", g.latitude, g.longitude))
            } else {
                Text("No geofence event yet for the receiver radius.").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var receiverCard: some View {
        LifecycleCard {
            LifecycleSection(label: "RECEIVER", icon: "building.2.fill")
            LifecycleRow(label: "Facility",    value: dashIfEmpty(live.delivery?.facilityName))
            LifecycleRow(label: "Address",     value: dashIfEmpty(live.delivery?.address))
            LifecycleRow(label: "Contact",     value: dashIfEmpty(live.delivery?.contactName))
            LifecycleRow(label: "Phone",       value: dashIfEmpty(live.delivery?.contactPhone))
            LifecycleRow(label: "Appointment", value: humanISO(live.delivery?.appointmentStart))
        }
    }

    private var etaStrip: some View {
        HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "ETA",       value: humanISO(live.load.estimatedDeliveryDate, format: "MMM d · HH:mm"), icon: "clock")
            LifecycleStatTile(label: "STATUS",    value: dashIfEmpty(live.delivery?.status.uppercased()), icon: "flag")
            LifecycleStatTile(label: "EQUIPMENT", value: dashIfEmpty(live.load.equipmentType), icon: "shippingbox")
        }
    }
}

#Preview("270 · Delivery · Approaching · Night") {
    DeliveryApproachingScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("270 · Delivery · Approaching · Afternoon") {
    DeliveryApproachingScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
