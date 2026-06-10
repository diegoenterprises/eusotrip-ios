//
//  263_PickupApproaching.swift
//  EusoTrip — Shipper · Stage 4 · PICKUP · approaching (refactored).
//

import SwiftUI

struct PickupApproachingScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) {
            LifecycleScaffold(loadId: loadId, eyebrow: "SHIPPER · PICKUP · APPROACHING · STAGE 4 OF 8", cycleStatus: "approaching_pickup") { live in
                ApproachingBody(live: live)
            }
        } nav: { shipperLifecycleNav() }
    }
}

private struct ApproachingBody: View {
    @Environment(\.palette) private var palette
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
            LifecycleMapCard(live: live, label: "\(loadMode.displayName.uppercased()) → \(loadMode.pickupNoun)", mode: .truckAtPickup)
            // Wave A2 strip extension — the same live-bound equipment
            // animation 264/265/267/268/270 host, so the shipper sees the
            // real rig inbound to the pickup (echo-cel 263 M04 purpose).
            LifecycleAnimationStrip(live: live, label: "\(loadMode.displayName.uppercased()) INBOUND", height: 180)
            facilityCard
            etaStrip
            commsRow
        }
    }

    private var geofenceCard: some View {
        LifecycleCard {
            LifecycleSection(label: "LAST GEOFENCE EVENT", icon: "dot.radiowaves.left.and.right")
            if let g = live.lastGeofence {
                LifecycleRow(label: "Type",      value: g.type.uppercased())
                LifecycleRow(label: "Timestamp", value: humanISO(g.eventTimestamp))
                LifecycleRow(label: "GPS",       value: String(format: "%.4f, %.4f", g.latitude, g.longitude))
            } else {
                Text("No geofence events yet for this load.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var facilityCard: some View {
        LifecycleCard {
            LifecycleSection(label: "\(loadMode.pickupNoun) FACILITY", icon: "building.2.fill")
            LifecycleRow(label: "Facility",    value: dashIfEmpty(live.pickup?.facilityName))
            LifecycleRow(label: "Address",     value: dashIfEmpty(live.pickup?.address))
            LifecycleRow(label: "Contact",     value: dashIfEmpty(live.pickup?.contactName))
            LifecycleRow(label: "Phone",       value: dashIfEmpty(live.pickup?.contactPhone))
            LifecycleRow(label: TransportLexicon.short(.appointment, mode: loadMode, equipmentRaw: live.load.equipmentType), value: humanISO(live.pickup?.appointmentStart))
        }
    }

    private var etaStrip: some View {
        HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "\(loadMode.pickupNoun) ETA",  value: relativeETA(from: live.load.pickupDate), icon: "clock")
            LifecycleStatTile(label: "STATUS",       value: dashIfEmpty(live.pickup?.status.uppercased()), icon: "flag")
            LifecycleStatTile(label: "EQUIPMENT",   value: dashIfEmpty(live.load.equipmentType), icon: "shippingbox")
        }
    }

    private var commsRow: some View {
        HStack(spacing: 8) {
            commsButton(icon: "phone.fill", label: "Facility", phone: live.pickup?.contactPhone)
            commsButton(icon: "phone.fill", label: "Driver",   phone: live.driver?.phone)
            commsButton(icon: "map.fill",   label: "Map", phone: nil)
        }
    }

    private func commsButton(icon: String, label: String, phone: String?) -> some View {
        let mapDeepLink: URL? = {
            guard icon == "map.fill" else { return nil }
            if let lat = live.pickup?.lat, let lng = live.pickup?.lng, !(lat == 0 && lng == 0) {
                return URL(string: "maps://?ll=\(lat),\(lng)&q=\(label)")
            }
            if let addr = live.pickup?.address, !addr.isEmpty {
                let q = addr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                return URL(string: "maps://?q=\(q)")
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
}

#Preview("263 · Pickup · Approaching · Night") {
    PickupApproachingScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("263 · Pickup · Approaching · Afternoon") {
    PickupApproachingScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
