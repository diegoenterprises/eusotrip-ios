//
//  305_CarrierCounterResponse.swift
//  EusoTrip — Carrier · Counter-response inbox.
//
//  Cross-role chain (closes the counter-bid loop):
//    loadBidding.counter (append-only counter evidence)
//      → THIS SCREEN reads loadBidding.getMyBids + getBidChain
//      → loadBidding.accept / reject (atomic award or decline)
//      → durable notification, audit outbox, and counterpart readback
//
//  Without this surface the carrier never sees the shipper's counter
//  and the loop dies. Every counter-bid flow on the platform routes
//  through here.
//
//  Reshaped 2026-05-23 from per-card Accept/Reject buttons into a
//  twin drop-zone bar at the top of the page (mirrors the 406
//  stat-tile-drop-zone shape, with pure drop tiles since this
//  surface has no live stats card). Drag a pending counter card
//  up onto either tile to fire the canonical
//  loadBidding.accept / loadBidding.reject mutation in one gesture. Per-card
//  Accept / Reject buttons stay as tap fallback.
//

import SwiftUI

struct CarrierCounterResponseScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { CounterResponseBody() } nav: {
            BottomNav(
                leading: CarrierNavRoute.leading(current: .loads),
                trailing: CarrierNavRoute.trailing(current: .loads),
                orbState: .idle
            )
        }
    }
}

private struct CounteredBid: Identifiable {
    let original: LoadBiddingAPI.MyBid
    let counter: LoadBiddingAPI.ChainRow

    var id: String { counter.opaqueID }
    var bidId: String { counter.opaqueID }
    var loadId: String { counter.opaqueLoadID }
    var originalAmount: Double? { original.bidAmount.flatMap(Double.init) }
    var counterAmount: Double? { counter.bidAmount.flatMap(Double.init) }
    var notes: String? { counter.conditions }
    var status: String { counter.status ?? "" }
    var createdAt: String? { counter.createdAt }
}

private struct CounterResponseBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [CounteredBid] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var responding: String? = nil
    @State private var actionError: String? = nil
    @State private var lastAction: String? = nil
    @State private var requestKeys: [String: String] = [:]
    /// Drop-target highlight state. `"accept"` / `"reject"` when a card
    /// is hovering over the matching tile; nil otherwise.
    @State private var dragHoverTile: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let m = lastAction {
                    LifecycleCard(accentGradient: true) {
                        Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
                    }
                }
                if let e = actionError {
                    LifecycleCard(accentDanger: true) {
                        Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                }
                if !rows.isEmpty { dropZones }
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var dropZones: some View {
        HStack(spacing: Space.s2) {
            dropTile(
                id: "accept",
                label: "ACCEPT COUNTER",
                hint: "Take the shipper's rate",
                icon: "checkmark.seal.fill",
                tint: Brand.success
            )
            dropTile(
                id: "reject",
                label: "REJECT COUNTER",
                hint: "Decline this counter",
                icon: "xmark.octagon.fill",
                tint: Brand.danger
            )
        }
    }

    private func dropTile(id: String, label: String, hint: String, icon: String, tint: Color) -> some View {
        let isHover = dragHoverTile == id
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
            }
            Text(isHover ? "RELEASE TO \(label)" : hint)
                .font(EType.caption)
                .foregroundStyle(isHover ? tint : palette.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
        .padding(10)
        .background(palette.bgCard, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(
                    isHover ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(tint.opacity(0.3)),
                    lineWidth: isHover ? 2 : 1
                )
                .animation(.easeOut(duration: 0.12), value: isHover)
        )
        .dropDestination(for: String.self) { droppedIds, _ in
            guard let bidId = droppedIds.first else { return false }
            guard let bid = rows.first(where: { $0.bidId == bidId }) else { return false }
            Task { await respond(bid: bid, accept: id == "accept") }
            return true
        } isTargeted: { hovering in
            dragHoverTile = hovering ? id : (dragHoverTile == id ? nil : dragHoverTile)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.swap").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CARRIER · COUNTER-OFFERS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Pending counters").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Review the persisted counter round. Accept to award the load to your company, or decline the counter.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading counters…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if rows.isEmpty { EusoEmptyState(systemImage: "tray", title: "No pending counters", subtitle: "When a shipper counters one of your bids, it lands here.") }
        else {
            ForEach(rows) { bid in
                counterCard(bid)
                    .draggable(bid.bidId) {
                        counterCard(bid)
                            .frame(maxWidth: 320)
                            .opacity(0.92)
                            .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
                    }
            }
        }
    }

    private func counterCard(_ bid: CounteredBid) -> some View {
            LifecycleCard(accentGradient: true) {
            LifecycleSection(label: bid.bidId.uppercased(), icon: "doc.text")
            LifecycleRow(label: "Load",            value: bid.loadId)
            LifecycleRow(label: "Original amount", value: bid.originalAmount.map(usd) ?? "Not recorded")
            LifecycleRow(label: "Counter rate",    value: bid.counterAmount.map(usd) ?? "Not recorded")
            LifecycleRow(label: "Round",           value: bid.counter.bidRound.map(String.init) ?? "Not recorded")
            LifecycleRow(label: "Status",           value: bid.status.uppercased())
            LifecycleRow(label: "Submitted",        value: humanISO(bid.createdAt))
            if let notes = bid.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("CONDITIONS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary).padding(.top, 6)
                Text(notes).font(EType.mono(.micro)).tracking(0.4).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button { Task { await respond(bid: bid, accept: true) } } label: {
                    HStack {
                        if responding == bid.bidId+":a" { ProgressView().tint(.white) }
                        Text(responding == bid.bidId+":a" ? "Accepting…" : "Accept counter").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
                }.buttonStyle(.plain).disabled(responding != nil)
                Button { Task { await respond(bid: bid, accept: false) } } label: {
                    Text(responding == bid.bidId+":r" ? "Rejecting…" : "Reject").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(Brand.danger)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(palette.bgCard)
                        .overlay(Capsule().strokeBorder(Brand.danger.opacity(0.5), lineWidth: 1))
                        .clipShape(Capsule())
                }.buttonStyle(.plain).disabled(responding != nil)
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let envelope = try await EusoTripAPI.shared.loadBidding.getMyBids(
                status: "countered",
                limit: 100
            )
            var resolved: [CounteredBid] = []
            for original in envelope.bids {
                let chain = try await EusoTripAPI.shared.loadBidding.getBidChain(
                    loadId: original.opaqueLoadID
                )
                guard let counter = chain.last(where: {
                    $0.parentBidId.map(String.init) == original.opaqueID
                        && $0.status?.lowercased() == "pending"
                }) else { continue }
                resolved.append(CounteredBid(original: original, counter: counter))
            }
            rows = resolved
        } catch {
            loadError = EusoTripAPIError.bidActionMessage(for: error, noun: "counter list")
        }
        loading = false
    }

    private func respond(bid: CounteredBid, accept: Bool) async {
        await MainActor.run {
            responding = bid.bidId + (accept ? ":a" : ":r")
            actionError = nil
        }
        let requestKey = requestKeys[bid.bidId] ?? UUID().uuidString.lowercased()
        requestKeys[bid.bidId] = requestKey
        do {
            let ack: LoadBiddingAPI.SubmitAck
            if accept {
                ack = try await EusoTripAPI.shared.loadBidding.accept(
                    bidId: bid.bidId,
                    requestKey: requestKey
                )
            } else {
                ack = try await EusoTripAPI.shared.loadBidding.reject(
                    bidId: bid.bidId,
                    reason: "Carrier declined the counter-offer",
                    requestKey: requestKey
                )
            }
            let expectedStatus = accept ? "accepted" : "rejected"
            guard ack.confirmedStatus?.lowercased() == expectedStatus,
                  ack.opaqueID == bid.bidId,
                  ack.opaqueLoadID == bid.loadId else {
                throw EusoTripAPIError.decodingFailed(
                    "Counter response did not match the persisted bid chain."
                )
            }
            await MainActor.run {
                requestKeys.removeValue(forKey: bid.bidId)
                lastAction = "Load \(bid.loadId) · counter \(accept ? "accepted and booked" : "declined")"
            }
            await load()
        } catch {
            await MainActor.run {
                actionError = EusoTripAPIError.bidActionMessage(for: error, noun: "counter response")
            }
        }
        await MainActor.run { responding = nil }
    }
}

#Preview("305 · Carrier counter-response · Night") { CarrierCounterResponseScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("305 · Carrier counter-response · Afternoon") { CarrierCounterResponseScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
