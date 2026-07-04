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
            statusCard
            LifecycleMapCard(live: live, label: loadMode.atPickupLabel, mode: .truckAtPickup, height: 200)
            LifecycleAnimationStrip(live: live, label: loadMode.loadingVerb, height: 200)
            facilityCard
            cargoCard
            commsRow
        }
    }

    private var commsRow: some View {
        HStack(spacing: 8) {
            commsButton(icon: "phone.fill", label: "Facility", phone: live.pickup?.contactPhone)
            commsButton(icon: "phone.fill", label: "Driver",   phone: live.driver?.phone)
            commsButton(icon: "map.fill",   label: "Map",      phone: nil)
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

    private var statusCard: some View {
        LifecycleCard {
            LifecycleSection(label: "\(loadMode.pickupNoun) STATUS", icon: "arrow.up.bin.fill")
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
            LifecycleRow(label: "Weight",     value: live.load.weight.map { "\(Int($0)) lb" } ?? "-")
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
