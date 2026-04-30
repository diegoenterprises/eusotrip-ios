//
//  266_PickupBolSigning.swift
//  EusoTrip — Shipper · Stage 4 · PICKUP · BOL signing (refactored).
//

import SwiftUI

struct ShipperPickupBolSigningScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) {
            LifecycleScaffold(loadId: loadId, eyebrow: "SHIPPER · PICKUP · BOL SIGNING · STAGE 4 OF 8", cycleStatus: "loading") { live in
                BolSigningBody(live: live, loadId: loadId)
            }
        } nav: { shipperLifecycleNav() }
    }
}

private struct BolSigningBody: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot
    let loadId: String
    @State private var openingBol = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            bolCard
            signaturesCard
            if live.load.hazmatClass?.isEmpty == false { hazmatCard }
            ctaRow
        }
    }

    private var bolCard: some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "BOL", icon: "doc.text.below.ecg.fill")
            LifecycleRow(label: "Load number", value: live.load.loadNumber)
            LifecycleRow(label: "Origin",      value: laneDisplay(live).components(separatedBy: " → ").first ?? "—")
            LifecycleRow(label: "Destination", value: laneDisplay(live).components(separatedBy: " → ").last ?? "—")
            LifecycleRow(label: "Equipment",   value: dashIfEmpty(live.load.equipmentType))
        }
    }

    private var signaturesCard: some View {
        LifecycleCard {
            LifecycleSection(label: "SIGNATURES", icon: "signature")
            LifecycleRow(label: "Driver",   value: dashIfEmpty(live.driver?.name))
            LifecycleRow(label: "Carrier",  value: dashIfEmpty(live.carrier?.name))
            LifecycleRow(label: "Pickup ts", value: humanISO(live.pickup?.departedAt ?? live.pickup?.arrivedAt))
        }
    }

    private var hazmatCard: some View {
        LifecycleCard(accentWarning: true) {
            LifecycleSection(label: "HAZMAT MANIFEST", icon: "triangle.fill")
            LifecycleRow(label: "UN",        value: dashIfEmpty(live.load.unNumber))
            LifecycleRow(label: "Class",     value: dashIfEmpty(live.load.hazmatClass))
            LifecycleRow(label: "ERG guide", value: live.load.ergGuide.map { "#\($0)" } ?? "—")
        }
    }

    private var ctaRow: some View {
        Button {
            // Open the run-tickets / BOL document viewer.
            // Web peer renders the HTML at /documents/bol; the iOS
            // surface routes through the Documents tab.
            NotificationCenter.default.post(
                name: .eusoShipperNavSwap, object: nil,
                userInfo: ["screenId": "300", "loadId": loadId, "doc": "bol"]
            )
        } label: {
            HStack(spacing: 6) {
                if openingBol { ProgressView().tint(.white) }
                else { Image(systemName: "doc.text.fill").font(.system(size: 13, weight: .heavy)) }
                Text("Open BOL").font(.system(size: 13, weight: .heavy)).tracking(0.4)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain)
    }
}

#Preview("266 · Pickup · BOL signing · Night") {
    ShipperPickupBolSigningScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("266 · Pickup · BOL signing · Afternoon") {
    ShipperPickupBolSigningScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
