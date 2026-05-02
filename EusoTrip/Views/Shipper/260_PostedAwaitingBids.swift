// SHELVED 2026-05-01 — pre-existing references to APIs that don't
// exist on the current iOS client (e.g. LoadsAPI.cancel,
// OrbESang.State.alert). Not registered in ScreenRegistry, so the
// file is dead-coded today. Wrapped in `#if false` so the file
// reference stays in the Xcode target but the body skips
// compilation. Resurrect when the role-by-role audit reaches this
// surface and the missing API endpoints are added.
#if false
//
//  260_PostedAwaitingBids.swift
//  EusoTrip — Shipper · Lifecycle Stage 1 · POSTED · awaiting bids.
//
//  Round 4 / Arc E. Refactored 2026-04-28 to consume
//  `shippers.getLifecycleSnapshot(loadId)` via `ShipperLifecycleSnapshotStore`.
//  Every field renders from the server snapshot — no fabricated values.
//
//  Surfaces:
//    • Reach card  — server-side bidsSummary (count) + recommendedBidId.
//    • CTA row     — Edit load (mutates `shippers.update`) · Cancel
//                    (mutates `loads.cancel`). Buttons fire real async
//                    mutations and refresh the snapshot.
//

import SwiftUI

struct PostedAwaitingBidsScreen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            LifecycleScaffold(
                loadId: loadId,
                eyebrow: "SHIPPER · POSTED · STAGE 1 OF 8",
                cycleStatus: "posted"
            ) { live in
                PostedBody(live: live, loadId: loadId)
            }
        } nav: {
            shipperLifecycleNav()
        }
    }
}

private struct PostedBody: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot
    let loadId: String

    @State private var isCancelling: Bool = false
    @State private var cancelError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            reachCard
            metricsRow
            ctaRow
            if let err = cancelError { errorBanner(err) }
        }
    }

    private var reachCard: some View {
        LifecycleCard {
            LifecycleSection(label: "REACH", icon: "antenna.radiowaves.left.and.right")
            HStack(spacing: Space.s2) {
                LifecycleStatTile(
                    label: "BIDS",
                    value: "\(live.bidsSummary.count)",
                    icon: "hand.raised"
                )
                LifecycleStatTile(
                    label: "TOP BID",
                    value: usd0(live.bidsSummary.topBid),
                    icon: "arrow.down.circle"
                )
                LifecycleStatTile(
                    label: "AVERAGE",
                    value: usd0(live.bidsSummary.averageBid),
                    icon: "scalemass"
                )
            }
            if live.bidsSummary.count == 0 {
                Text("No bids yet — carriers will surface offers here as they come in. Live updates over the lifecycle socket channel.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(live.recommendedBidId != nil
                     ? "ESANG flagged a recommended bid — open the bids feed to review."
                     : "Bids in flight. Open the bids feed for full triage.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var metricsRow: some View {
        LifecycleCard {
            LifecycleSection(label: "LOAD", icon: "doc.text")
            LifecycleRow(label: "Posted rate",  value: usd(live.load.rate))
            LifecycleRow(label: "Distance",     value: live.load.distance.map { "\(Int($0)) mi" } ?? "—")
            LifecycleRow(label: "Equipment",    value: dashIfEmpty(live.load.equipmentType))
            LifecycleRow(label: "Pickup window", value: humanISO(live.load.pickupDate))
            if let bidEnd = live.load.biddingEnds {
                LifecycleRow(label: "Bidding ends", value: humanISO(bidEnd))
            }
        }
    }

    private var ctaRow: some View {
        HStack(spacing: 10) {
            Button {
                // Open the load editor via NotificationCenter — the
                // shipper screen registry maps "204_edit" to the
                // post-load wizard pre-filled with this load row.
                NotificationCenter.default.post(
                    name: .eusoShipperNavSwap,
                    object: nil,
                    userInfo: ["screenId": "204", "loadId": loadId, "mode": "edit"]
                )
            } label: {
                Text("Edit load")
                    .font(.system(size: 13, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
            Button {
                Task { await cancelLoad() }
            } label: {
                if isCancelling {
                    ProgressView().tint(Brand.danger).frame(width: 44, height: 44)
                } else {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Brand.danger)
                        .frame(width: 44, height: 44)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.danger.opacity(0.5), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
            }.buttonStyle(.plain).disabled(isCancelling)
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
            Text(msg).font(EType.caption).foregroundStyle(Brand.danger)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func cancelLoad() async {
        isCancelling = true
        cancelError = nil
        do {
            _ = try await EusoTripAPI.shared.loads.cancel(loadId: loadId, reason: nil)
            NotificationCenter.default.post(
                name: .eusoShipperNavSwap,
                object: nil,
                userInfo: ["screenId": "201"]
            )
        } catch {
            cancelError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        isCancelling = false
    }
}

#Preview("260 · Posted · Awaiting bids · Night") {
    PostedAwaitingBidsScreen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("260 · Posted · Awaiting bids · Afternoon") {
    PostedAwaitingBidsScreen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}

#endif
