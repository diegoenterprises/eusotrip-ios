//
//  275_ClosedSettlementPreview.swift
//  EusoTrip — Shipper · Stage 8 · CLOSED · settlement preview (refactored).
//
//  Consumes both `getLifecycleSnapshot` (for escrow) and
//  `getSettlementForLoad` (for settlement row, when constructed).
//

import SwiftUI

struct ClosedSettlementPreviewScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) {
            LifecycleScaffold(loadId: loadId, eyebrow: "SHIPPER · CLOSED · SETTLEMENT PREVIEW · STAGE 8 OF 8", cycleStatus: "invoiced") { live in
                SettlementBody(live: live, loadId: loadId)
            }
        } nav: { shipperLifecycleNav() }
    }
}

private struct SettlementBody: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot
    let loadId: String
    @StateObject private var settlement = ShipperSettlementForLoadStore()

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            totalCard
            breakdownCard
            escrowCard
        }
        .task {
            settlement.loadId = loadId
            await settlement.refresh()
        }
    }

    private var totalCard: some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "PAYABLE", icon: "creditcard.fill")
            switch settlement.state {
            case .loaded(let optS):
                if let s = optS {
                    LifecycleRow(label: "Status",        value: s.status.uppercased())
                    LifecycleRow(label: "Total",         value: usd(s.amount))
                    LifecycleRow(label: "Payable date",  value: humanISO(s.payableDate))
                    LifecycleRow(label: "Paid at",       value: humanISO(s.paidAt))
                    LifecycleRow(label: "Source",        value: s.source.uppercased())
                } else {
                    Text("Settlement not yet constructed for this load.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .empty:
                Text("Settlement not yet constructed.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            case .loading:
                Text("Loading settlement…").font(EType.caption).foregroundStyle(palette.textSecondary)
            case .error(let err):
                Text((err as? EusoTripAPIError)?.errorDescription ?? err.localizedDescription)
                    .font(EType.caption).foregroundStyle(Brand.danger)
            }
        }
    }

    private var breakdownCard: some View {
        LifecycleCard {
            LifecycleSection(label: "BREAKDOWN", icon: "list.bullet")
            LifecycleRow(label: "Line haul",      value: usd(live.load.rate))
            LifecycleRow(label: "Accessorials",   value: usd0(live.accessorialTotal))
            LifecycleRow(label: "Distance",       value: live.load.distance.map { "\(Int($0)) mi" } ?? "—")
        }
    }

    private var escrowCard: some View {
        LifecycleCard {
            LifecycleSection(label: "ESCROW", icon: "lock.shield.fill")
            if let e = live.escrow {
                LifecycleRow(label: "Held",       value: usd(e.amount))
                LifecycleRow(label: "Status",     value: dashIfEmpty(e.status?.uppercased()))
                LifecycleRow(label: "Release at", value: humanISO(e.releaseAt))
            } else {
                Text("No escrow hold for this load.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }
}

#Preview("275 · Closed · Settlement preview · Night") {
    ClosedSettlementPreviewScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("275 · Closed · Settlement preview · Afternoon") {
    ClosedSettlementPreviewScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
