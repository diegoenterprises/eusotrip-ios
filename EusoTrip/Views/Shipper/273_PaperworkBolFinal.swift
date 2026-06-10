//
//  273_PaperworkBolFinal.swift
//  EusoTrip — Shipper · Stage 7 · PAPERWORK · BOL final (refactored).
//

import SwiftUI

struct PaperworkBolFinalScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) {
            LifecycleScaffold(loadId: loadId, eyebrow: "SHIPPER · PAPERWORK · BOL FINAL · STAGE 7 OF 8", cycleStatus: "paperwork") { live in
                BolFinalBody(live: live, loadId: loadId)
            }
        } nav: { shipperLifecycleNav() }
    }
}

private struct BolFinalBody: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot
    let loadId: String

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
            documentCard
            // Wave A2 strip extension — the strip carries through the
            // paperwork stage (echo-cel 273 M04).
            LifecycleAnimationStrip(live: live, label: "EQUIPMENT · CLOSE-OUT", height: 160)
            attachmentsCard
            ctaRow
        }
    }

    private var documentCard: some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: TransportLexicon.short(.billOfLading, mode: loadMode, equipmentRaw: live.load.equipmentType), icon: "doc.text.below.ecg.fill")
            LifecycleRow(label: "Load number", value: live.load.loadNumber)
            LifecycleRow(label: "Lane",        value: laneDisplay(live))
            LifecycleRow(label: "Equipment",   value: dashIfEmpty(live.load.equipmentType))
            LifecycleRow(label: TransportLexicon.short(.delivered, mode: loadMode, equipmentRaw: live.load.equipmentType),   value: humanISO(live.load.actualDeliveryDate))
        }
    }

    private var attachmentsCard: some View {
        LifecycleCard {
            LifecycleSection(label: "ATTACHED", icon: "paperclip")
            LifecycleRow(label: "Carrier", value: dashIfEmpty(live.carrier?.name))
            LifecycleRow(label: "Driver",  value: dashIfEmpty(live.driver?.name))
            if live.load.hazmatClass?.isEmpty == false {
                LifecycleRow(label: "Hazmat manifest", value: "UN \(dashIfEmpty(live.load.unNumber)) · Class \(dashIfEmpty(live.load.hazmatClass))")
                LifecycleRow(label: "ERG guide",       value: live.load.ergGuide.map { "#\($0)" } ?? "-")
            }
            if live.load.spectraMatchVerified == true {
                LifecycleRow(label: "SpectraMatch", value: "Verified")
            }
        }
    }

    private var ctaRow: some View {
        HStack(spacing: 10) {
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "226", "loadId": loadId, "doc": "bol"])
            } label: {
                Text("Open \(TransportLexicon.short(.billOfLading, mode: loadMode, equipmentRaw: live.load.equipmentType))").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "275", "loadId": loadId])
            } label: {
                Image(systemName: "creditcard.fill").font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    .frame(width: 44, height: 44).background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
    }
}

#Preview("273 · Paperwork · BOL final · Night") {
    PaperworkBolFinalScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("273 · Paperwork · BOL final · Afternoon") {
    PaperworkBolFinalScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
