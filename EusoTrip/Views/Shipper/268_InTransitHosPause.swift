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
            commsRow
        }
    }

    private var commsRow: some View {
        HStack(spacing: 8) {
            commsButton(icon: "phone.fill", label: "Driver", phone: live.driver?.phone)
            commsButton(icon: "map.fill",   label: "Parked", phone: nil)
        }
    }

    private func commsButton(icon: String, label: String, phone: String?) -> some View {
        let mapDeepLink: URL? = {
            guard icon == "map.fill" else { return nil }
            if let g = live.lastGeofence {
                return URL(string: "maps://?ll=\(g.latitude),\(g.longitude)&q=Parked")
            }
            return nil
        }()
        let enabled = (phone?.isEmpty == false) || (icon == "map.fill" && mapDeepLink != nil)
        return Button {
            if let p = phone, let url = URL(string: "tel://\(p.filter(\.isNumber))") {
                UIApplication.shared.open(url)
            } else if let url = mapDeepLink {
                UIApplication.shared.open(url)
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(enabled ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(!enabled)
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
