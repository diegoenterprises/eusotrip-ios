//
//  274_PaperworkAccessorials.swift
//  EusoTrip — Shipper · Stage 7 · PAPERWORK · accessorials (refactored).
//

import SwiftUI

struct PaperworkAccessorialsScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) {
            LifecycleScaffold(loadId: loadId, eyebrow: "SHIPPER · PAPERWORK · ACCESSORIALS · STAGE 7 OF 8", cycleStatus: "paperwork") { live in
                AccessorialsBody(live: live, loadId: loadId)
            }
        } nav: { shipperLifecycleNav() }
    }
}

private struct AccessorialsBody: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot
    let loadId: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            summaryCard
            ctaRow
        }
    }

    private var summaryCard: some View {
        LifecycleCard {
            LifecycleSection(label: "ACCESSORIAL TOTAL", icon: "list.dash.header.rectangle")
            HStack(spacing: Space.s2) {
                LifecycleStatTile(label: "TOTAL",        value: usd0(live.accessorialTotal), icon: "dollarsign.circle")
                LifecycleStatTile(label: "BASE RATE",    value: usd(live.load.rate), icon: "scalemass")
                LifecycleStatTile(label: "DISTANCE",     value: live.load.distance.map { "\(Int($0)) mi" } ?? "—", icon: "ruler")
            }
            Text("Server-side accessorial total is the aggregated charge across detention, lumper, layover, TONU. Open the full builder to add or dispute line items.")
                .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ctaRow: some View {
        Button {
            // Web peer is /detention-accessorials. iOS deep-link via
            // the Documents tab on web bridge until 274's full builder
            // ships in a future round.
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "300", "loadId": loadId, "doc": "accessorials"])
        } label: {
            Text("Open accessorial builder").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain)
    }
}

#Preview("274 · Paperwork · Accessorials · Night") {
    PaperworkAccessorialsScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("274 · Paperwork · Accessorials · Afternoon") {
    PaperworkAccessorialsScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
