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
    @Environment(\.openURL) private var openURL
    let live: ShipperAPI.LifecycleSnapshot

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
            geofenceCard
            LifecycleMapCard(live: live, label: "\(loadMode.displayName.uppercased()) → \(loadMode.deliveryNoun)", mode: .truckAtDelivery)
            LifecycleAnimationStrip(live: live, label: "EQUIPMENT", height: 180)
            receiverCard
            etaStrip
            commsRow
        }
    }

    private var commsRow: some View {
        HStack(spacing: 8) {
            commsButton(icon: "phone.fill", label: "Receiver", phone: live.delivery?.contactPhone)
            commsButton(icon: "phone.fill", label: "Driver",   phone: live.driver?.phone)
            commsButton(icon: "map.fill",   label: "Map",      phone: nil)
        }
    }

    private func commsButton(icon: String, label: String, phone: String?) -> some View {
        let mapDeepLink: URL? = {
            guard icon == "map.fill" else { return nil }
            // Receiver coords first; truck pin second; receiver address last.
            // Gate null-island (0,0): an un-geocoded delivery must fall through
            // to the truck pin / address link, never deep-link to the ocean.
            if let lat = live.delivery?.lat, let lng = live.delivery?.lng, !(lat == 0 && lng == 0) {
                return URL(string: "maps://?ll=\(lat),\(lng)&q=Receiver")
            }
            if let g = live.lastGeofence, !(g.latitude == 0 && g.longitude == 0) {
                return URL(string: "maps://?ll=\(g.latitude),\(g.longitude)&q=Truck")
            }
            if let addr = live.delivery?.address, !addr.isEmpty {
                let q = addr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                return URL(string: "maps://?q=\(q)")
            }
            return nil
        }()
        let enabled = (phone?.isEmpty == false) || (icon == "map.fill" && mapDeepLink != nil)
        return Button {
            if let p = phone, let url = URL(string: "tel://\(p.filter(\.isNumber))") {
                openURL(url)
            } else if let url = mapDeepLink {
                openURL(url)
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
            LifecycleRow(label: TransportLexicon.short(.appointment, mode: loadMode, equipmentRaw: live.load.equipmentType), value: humanISO(live.delivery?.appointmentStart))
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
