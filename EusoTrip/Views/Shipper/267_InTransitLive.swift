//
//  267_InTransitLive.swift
//  EusoTrip — Shipper · Stage 5 · IN TRANSIT · live (refactored).
//

import SwiftUI

struct InTransitLiveScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) {
            LifecycleScaffold(loadId: loadId, eyebrow: "SHIPPER · IN TRANSIT · LIVE · STAGE 5 OF 8", cycleStatus: "in_transit") { live in
                InTransitBody(live: live)
            }
        } nav: { shipperLifecycleNav() }
    }
}

private struct InTransitBody: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            etaStrip
            LifecycleMapCard(live: live, label: "LIVE TRACK", mode: .full, height: 260)
            telemetryCard
            commsRow
        }
    }

    private var etaStrip: some View {
        HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "ETA",      value: humanISO(live.load.estimatedDeliveryDate, format: "MMM d · HH:mm"), icon: "clock")
            LifecycleStatTile(label: "DISTANCE", value: live.load.distance.map { "\(Int($0)) mi" } ?? "—", icon: "ruler")
            LifecycleStatTile(label: "STATUS",   value: live.load.status.uppercased(), icon: "flag")
        }
    }

    private var telemetryCard: some View {
        LifecycleCard {
            LifecycleSection(label: "LATEST TELEMETRY", icon: "antenna.radiowaves.left.and.right")
            if let g = live.lastGeofence {
                LifecycleRow(label: "Last event",  value: g.type.uppercased())
                LifecycleRow(label: "Recorded at", value: humanISO(g.eventTimestamp))
                LifecycleRow(label: "GPS",         value: String(format: "%.4f, %.4f", g.latitude, g.longitude))
                if let dwell = g.dwellSeconds {
                    LifecycleRow(label: "Dwell", value: "\(dwell / 60) min")
                }
            } else {
                Text("Truck en route — no geofence event in this window yet.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LifecycleRow(label: "Pickup window",   value: humanISO(live.load.pickupDate))
            LifecycleRow(label: "Delivery window", value: humanISO(live.load.deliveryDate))
        }
    }

    private var commsRow: some View {
        HStack(spacing: 8) {
            commsButton(icon: "phone.fill", label: "Driver",  phone: live.driver?.phone)
            commsButton(icon: "phone.fill", label: "Carrier", phone: nil) // carrier dispatch line — future endpoint
            commsButton(icon: "map.fill",   label: "Map",     phone: nil)
        }
    }

    private func commsButton(icon: String, label: String, phone: String?) -> some View {
        let mapDeepLink: URL? = {
            guard icon == "map.fill" else { return nil }
            // Truck's current pin first; fall back to delivery
            // facility coords; finally the destination address.
            if let g = live.lastGeofence {
                return URL(string: "maps://?ll=\(g.latitude),\(g.longitude)&q=Truck")
            }
            if let lat = live.delivery?.lat, let lng = live.delivery?.lng {
                return URL(string: "maps://?ll=\(lat),\(lng)&q=Delivery")
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

#Preview("267 · In transit · Live · Night") {
    InTransitLiveScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("267 · In transit · Live · Afternoon") {
    InTransitLiveScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
