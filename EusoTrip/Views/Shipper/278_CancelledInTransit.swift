//
//  278_CancelledInTransit.swift
//  EusoTrip — Shipper · CANCELLED · in transit (refactored).
//

import SwiftUI

struct CancelledInTransitScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) {
            LifecycleScaffold(loadId: loadId, eyebrow: "SHIPPER · CANCELLED · IN TRANSIT", cycleStatus: "cancelled") { live in
                CancelInTransitBody(live: live, loadId: loadId)
            }
        } nav: { shipperLifecycleNav() }
    }
}

private struct CancelInTransitBody: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot
    let loadId: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            statusCard
            LifecycleMapCard(live: live, label: "LAST KNOWN POSITION", icon: "exclamationmark.triangle.fill", mode: .full)
            telemetryCard
            ctaRow
        }
    }

    private var statusCard: some View {
        LifecycleCard(accentDanger: true) {
            LifecycleSection(label: "MID-HAUL CANCEL", icon: "exclamationmark.triangle.fill")
            LifecycleRow(label: "Status",   value: live.load.status.uppercased())
            LifecycleRow(label: "Carrier",  value: dashIfEmpty(live.carrier?.name))
            LifecycleRow(label: "Driver",   value: dashIfEmpty(live.driver?.name))
            LifecycleRow(label: "Lane",     value: laneDisplay(live))
            if live.load.hazmatClass?.isEmpty == false {
                LifecycleRow(label: "Hazmat", value: "Class \(dashIfEmpty(live.load.hazmatClass)) — verify 49 CFR 397 secure parking before any salvage routing.")
            }
        }
    }

    private var telemetryCard: some View {
        LifecycleCard {
            LifecycleSection(label: "LAST KNOWN POSITION", icon: "antenna.radiowaves.left.and.right")
            if let g = live.lastGeofence {
                LifecycleRow(label: "Event",     value: g.type.uppercased())
                LifecycleRow(label: "Recorded",  value: humanISO(g.eventTimestamp))
                LifecycleRow(label: "GPS",       value: String(format: "%.4f, %.4f", g.latitude, g.longitude))
            } else {
                Text("No live geofence event for this load.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var ctaRow: some View {
        HStack(spacing: 10) {
            Button {
                if let p = live.driver?.phone, let url = URL(string: "tel://\(p.filter(\.isNumber))") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Call driver").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain).disabled(live.driver?.phone?.isEmpty != false)
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "219", "loadId": loadId, "mode": "create"])
            } label: {
                Image(systemName: "exclamationmark.octagon")
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(Brand.danger)
                    .frame(width: 44, height: 44).background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.danger.opacity(0.5), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
    }
}

#Preview("278 · Cancelled · In transit · Night") {
    CancelledInTransitScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("278 · Cancelled · In transit · Afternoon") {
    CancelledInTransitScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
