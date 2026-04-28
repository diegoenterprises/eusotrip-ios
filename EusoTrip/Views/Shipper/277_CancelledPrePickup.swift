//
//  277_CancelledPrePickup.swift
//  EusoTrip — Shipper · CANCELLED · pre-pickup (refactored).
//

import SwiftUI

struct CancelledPrePickupScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) {
            LifecycleScaffold(loadId: loadId, eyebrow: "SHIPPER · CANCELLED · PRE-PICKUP", cycleStatus: "cancelled") { live in
                CancelPrePickupBody(live: live, loadId: loadId)
            }
        } nav: { shipperLifecycleNav() }
    }
}

private struct CancelPrePickupBody: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot
    let loadId: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            statusCard
            refundCard
            ctaRow
        }
    }

    private var statusCard: some View {
        LifecycleCard(accentDanger: true) {
            LifecycleSection(label: "CANCELLATION", icon: "xmark.octagon.fill")
            LifecycleRow(label: "Status",   value: live.load.status.uppercased())
            LifecycleRow(label: "Carrier",  value: dashIfEmpty(live.carrier?.name))
            LifecycleRow(label: "Lane",     value: laneDisplay(live))
        }
    }

    private var refundCard: some View {
        LifecycleCard {
            LifecycleSection(label: "ESCROW", icon: "arrow.counterclockwise.circle.fill")
            if let e = live.escrow {
                LifecycleRow(label: "Held",       value: usd(e.amount))
                LifecycleRow(label: "Status",     value: dashIfEmpty(e.status?.uppercased()))
                LifecycleRow(label: "Release at", value: humanISO(e.releaseAt))
            } else {
                Text("No escrow hold for this load — no refund required.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var ctaRow: some View {
        Button {
            // Re-tender from a cancelled load opens the post-load
            // wizard pre-filled with the original lane.
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "204", "loadId": loadId, "mode": "retender"])
        } label: {
            Text("Re-tender").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain)
    }
}

#Preview("277 · Cancelled · Pre-pickup · Night") {
    CancelledPrePickupScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("277 · Cancelled · Pre-pickup · Afternoon") {
    CancelledPrePickupScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
