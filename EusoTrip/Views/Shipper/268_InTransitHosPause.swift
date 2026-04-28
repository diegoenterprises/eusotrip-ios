//
//  268_InTransitHosPause.swift
//  EusoTrip — Shipper · Stage 5 · IN TRANSIT · HOS pause (refactored).
//

import SwiftUI

struct InTransitHosPauseScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) {
            LifecycleScaffold(loadId: loadId, eyebrow: "SHIPPER · IN TRANSIT · HOS PAUSE · STAGE 5 OF 8", cycleStatus: "in_transit") { live in
                HosPauseBody(live: live)
            }
        } nav: { shipperLifecycleNav() }
    }
}

private struct HosPauseBody: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            driverCard
            scheduleCard
            telemetryCard
        }
    }

    private var driverCard: some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "DRIVER OFF-DUTY", icon: "moon.zzz.fill")
            LifecycleRow(label: "Driver",  value: dashIfEmpty(live.driver?.name))
            LifecycleRow(label: "Carrier", value: dashIfEmpty(live.carrier?.name))
            LifecycleRow(label: "Phone",   value: dashIfEmpty(live.driver?.phone))
            Text("Driver flipped off-duty on the ELD. The load is parked and will resume when the HOS clock allows. Live updates over the driver:status_changed channel.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scheduleCard: some View {
        LifecycleCard {
            LifecycleSection(label: "SCHEDULE IMPACT", icon: "clock.arrow.2.circlepath")
            LifecycleRow(label: "Original ETA", value: humanISO(live.load.estimatedDeliveryDate))
            LifecycleRow(label: "Delivery window", value: humanISO(live.load.deliveryDate))
            LifecycleRow(label: "Equipment",     value: dashIfEmpty(live.load.equipmentType))
        }
    }

    private var telemetryCard: some View {
        LifecycleCard {
            LifecycleSection(label: "PARKED", icon: "p.circle.fill")
            if let g = live.lastGeofence {
                LifecycleRow(label: "Last event", value: g.type.uppercased())
                LifecycleRow(label: "GPS",        value: String(format: "%.4f, %.4f", g.latitude, g.longitude))
                LifecycleRow(label: "Recorded",   value: humanISO(g.eventTimestamp))
            } else {
                Text("No geofence event captured for the parked location yet.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if live.load.hazmatClass?.isEmpty == false {
                LifecycleRow(label: "Hazmat 49 CFR 397", value: "Verify secure parking before approving any deviation.")
            }
        }
    }
}

#Preview("268 · In transit · HOS pause · Night") {
    InTransitHosPauseScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("268 · In transit · HOS pause · Afternoon") {
    InTransitHosPauseScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
