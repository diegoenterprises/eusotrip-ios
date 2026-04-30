//
//  276_ClosedPaid.swift
//  EusoTrip — Shipper · Stage 8 · CLOSED · paid (refactored).
//

import SwiftUI

struct ClosedPaidScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) {
            LifecycleScaffold(loadId: loadId, eyebrow: "SHIPPER · CLOSED · PAID · STAGE 8 OF 8", cycleStatus: "paid") { live in
                ClosedPaidBody(live: live, loadId: loadId)
            }
        } nav: { shipperLifecycleNav() }
    }
}

private struct ClosedPaidBody: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot
    let loadId: String
    @StateObject private var settlement = ShipperSettlementForLoadStore()
    @State private var rating: Int = 0
    @State private var ratingError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            receiptCard
            cycleCard
            rateCard
            if let err = ratingError { errorBanner(err) }
        }
        .task {
            settlement.loadId = loadId
            await settlement.refresh()
        }
    }

    private var receiptCard: some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "RECEIPT", icon: "checkmark.circle.fill")
            switch settlement.state {
            case .loaded(let s) where s != nil:
                LifecycleRow(label: "Net total", value: usd(s!.amount))
                LifecycleRow(label: "Paid at",   value: humanISO(s!.paidAt))
                LifecycleRow(label: "Source",    value: s!.source.uppercased())
                if let inv = s!.invoiceUrl, !inv.isEmpty {
                    LifecycleRow(label: "Invoice", value: inv)
                }
            default:
                LifecycleRow(label: "Carrier",   value: dashIfEmpty(live.carrier?.name))
                LifecycleRow(label: "Delivered", value: humanISO(live.load.actualDeliveryDate))
                Text("Settlement payload not yet on file. Pull-to-refresh once the carrier is paid.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var cycleCard: some View {
        LifecycleCard {
            LifecycleSection(label: "CYCLE", icon: "clock")
            LifecycleRow(label: "Pickup",    value: humanISO(live.pickup?.departedAt ?? live.pickup?.arrivedAt))
            LifecycleRow(label: "Delivered", value: humanISO(live.load.actualDeliveryDate))
            LifecycleRow(label: "Lane",      value: laneDisplay(live))
        }
    }

    private var rateCard: some View {
        LifecycleCard {
            LifecycleSection(label: "RATE THIS CARRIER", icon: "star.fill")
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { n in
                    Button { Task { await submit(rating: n) } } label: {
                        Image(systemName: rating >= n ? "star.fill" : "star")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(rating >= n ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                Text(rating > 0 ? "\(rating)/5" : "—")
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textPrimary).monospacedDigit()
            }
            Text("Rating is recorded against the carrier's composite score the moment you tap.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        LifecycleCard(accentDanger: true) {
            Text(msg).font(EType.caption).foregroundStyle(Brand.danger)
        }
    }

    private func submit(rating value: Int) async {
        rating = value
        ratingError = nil
        // The web shipper page calls `shippers.rateCatalyst`. Wire to
        // the same endpoint via a typed mutation.
        struct In: Encodable { let loadId: String; let catalystId: String; let rating: Int; let review: String? }
        guard let cId = live.carrier?.id else {
            ratingError = "Carrier not assigned — can't record rating."
            return
        }
        do {
            struct Out: Decodable { let success: Bool }
            let _ : Out = try await EusoTripAPI.shared.mutation(
                "shippers.rateCatalyst",
                input: In(loadId: loadId, catalystId: "car_\(cId)", rating: value, review: nil)
            )
        } catch {
            ratingError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("276 · Closed · Paid · Night") {
    ClosedPaidScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("276 · Closed · Paid · Afternoon") {
    ClosedPaidScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
