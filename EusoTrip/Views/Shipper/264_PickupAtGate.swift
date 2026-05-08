//
//  264_PickupAtGate.swift
//  EusoTrip — Shipper · Stage 4 · PICKUP · at gate (refactored).
//

import SwiftUI

struct PickupAtGateScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) {
            LifecycleScaffold(loadId: loadId, eyebrow: "SHIPPER · PICKUP · AT GATE · STAGE 4 OF 8", cycleStatus: "at_pickup") { live in
                AtGateBody(live: live)
            }
        } nav: { shipperLifecycleNav() }
    }
}

private struct AtGateBody: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            arrivalCard
            facilityCard
            if (live.load.hazmatClass?.isEmpty == false) { hazmatCard }
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
            if let lat = live.pickup?.lat, let lng = live.pickup?.lng {
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

    private var arrivalCard: some View {
        LifecycleCard {
            LifecycleSection(label: "ARRIVAL", icon: "checkmark.shield.fill")
            LifecycleRow(label: "Status",     value: dashIfEmpty(live.pickup?.status.uppercased()))
            LifecycleRow(label: "Arrived at", value: humanISO(live.pickup?.arrivedAt))
            LifecycleRow(label: "Departed",   value: humanISO(live.pickup?.departedAt))
            if let g = live.lastGeofence {
                LifecycleRow(label: "Last event", value: "\(g.type.uppercased()) · \(humanISO(g.eventTimestamp))")
            }
        }
    }

    private var facilityCard: some View {
        LifecycleCard {
            LifecycleSection(label: "FACILITY + GATE", icon: "lock.shield.fill")
            LifecycleRow(label: "Facility", value: dashIfEmpty(live.pickup?.facilityName))
            LifecycleRow(label: "Address",  value: dashIfEmpty(live.pickup?.address))
            LifecycleRow(label: "Contact",  value: dashIfEmpty(live.pickup?.contactName))
            LifecycleRow(label: "Phone",    value: dashIfEmpty(live.pickup?.contactPhone))
        }
    }

    private var hazmatCard: some View {
        LifecycleCard(accentWarning: true) {
            LifecycleSection(label: "HAZMAT VERIFY", icon: "triangle.fill")
            LifecycleRow(label: "UN",         value: dashIfEmpty(live.load.unNumber))
            LifecycleRow(label: "Class",      value: dashIfEmpty(live.load.hazmatClass))
            LifecycleRow(label: "ERG guide",  value: live.load.ergGuide.map { "#\($0)" } ?? "—")
        }
    }
}

#Preview("264 · Pickup · At gate · Night") {
    PickupAtGateScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("264 · Pickup · At gate · Afternoon") {
    PickupAtGateScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
