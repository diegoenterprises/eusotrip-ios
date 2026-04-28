//
//  414_BidDetailSheet.swift
//  EusoTrip — Shipper · Bid detail sheet (Arc C deepening).
//

import SwiftUI

struct BidDetailSheetScreen: View {
    let theme: Theme.Palette
    let loadId: String
    let bidId: String
    var body: some View {
        Shell(theme: theme) { BidDetailBody(loadId: loadId, bidId: bidId) } nav: { shipperLifecycleNav() }
    }
}

private struct BidDetailBody: View {
    @Environment(\.palette) private var palette
    let loadId: String
    let bidId: String
    @StateObject private var bids = ShipperBidsStore()
    @State private var processing: String? = nil
    @State private var actionError: String? = nil

    private var bid: ShipperAPI.Bid? {
        (bids.state.value ?? []).first(where: { $0.id == bidId })
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                if let b = bid {
                    bidCard(b)
                    scoreCard(b)
                    actionRow(b)
                } else {
                    LifecycleCard { Text("Bid not found in cache. Pull-to-refresh the bids list and tap again.").font(EType.caption).foregroundStyle(palette.textSecondary) }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task {
            bids.setLoadId(loadId)
            await bids.refresh()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · BID DETAIL").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(bid?.catalystName ?? "—").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func bidCard(_ b: ShipperAPI.Bid) -> some View {
        LifecycleCard(accentGradient: b.recommended) {
            LifecycleSection(label: "BID", icon: "dollarsign.circle")
            LifecycleRow(label: "Carrier",       value: b.catalystName)
            LifecycleRow(label: "USDOT",         value: dashIfEmpty(b.dotNumber))
            LifecycleRow(label: "Bid amount",    value: usd(b.amount))
            LifecycleRow(label: "Transit time",  value: dashIfEmpty(b.transitTime))
            LifecycleRow(label: "Submitted",     value: humanISO(b.submittedAt))
            if !b.message.isEmpty {
                Text("MESSAGE").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary).padding(.top, 4)
                Text(b.message).font(EType.body).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func scoreCard(_ b: ShipperAPI.Bid) -> some View {
        LifecycleCard {
            LifecycleSection(label: "SAFETY + SCORE", icon: "shield")
            LifecycleRow(label: "Safety score", value: b.safetyScore > 0 ? String(format: "%.2f", b.safetyScore) : "—")
            if b.recommended {
                Text("ESANG ★ RECOMMENDED").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }
        }
    }

    private func actionRow(_ b: ShipperAPI.Bid) -> some View {
        HStack(spacing: 10) {
            Button { Task { await accept(b.id) } } label: {
                HStack(spacing: 6) {
                    if processing == b.id + ":accept" { ProgressView().tint(.white) }
                    Text(processing == b.id + ":accept" ? "Accepting…" : "Accept").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain).disabled(processing != nil)
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "415", "loadId": loadId, "bidId": b.id])
            } label: {
                Text("Counter").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(palette.tintNeutral)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "416", "loadId": loadId, "bidId": b.id])
            } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Brand.danger)
                    .frame(width: 44, height: 44).background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.danger.opacity(0.5), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    private func accept(_ id: String) async {
        processing = id + ":accept"; actionError = nil
        do {
            _ = try await EusoTripAPI.shared.shippers.acceptBid(loadId: loadId, bidId: id)
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "417", "loadId": loadId, "bidId": id])
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        processing = nil
    }
}

#Preview("414 · Bid detail · Night") { BidDetailSheetScreen(theme: Theme.dark, loadId: "1", bidId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("414 · Bid detail · Afternoon") { BidDetailSheetScreen(theme: Theme.light, loadId: "1", bidId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
