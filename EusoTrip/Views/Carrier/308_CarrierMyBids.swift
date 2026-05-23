//
//  308_CarrierMyBids.swift
//  EusoTrip — Carrier · My bids (active + history).
//
//  Reshaped 2026-05-23 from a chip-filter linear list
//  (All / Active / Won / Lost — outcome bucketing) into a true
//  5-column Kanban over the raw bid status field. The chip-filter
//  was lossy: it merged `countered` into Active (hiding the "your
//  move" CTA) and merged `rejected`/`withdrawn` into Lost (no way
//  to tell who killed the bid).
//
//  Columns map to the canonical bid status enum:
//    PENDING     — bid submitted, awaiting shipper response
//    COUNTERED   — shipper countered, your move (tap View counter)
//    ACCEPTED    — won
//    REJECTED    — shipper picked someone else
//    WITHDRAWN   — you walked away
//
//  Drag-to-withdraw: drag a PENDING card onto the WITHDRAWN column
//  fires the real `catalysts.cancelBid(bidId)` mutation. The server
//  enforces the same constraint (only `pending` bids can be
//  cancelled), so dragging a COUNTERED card onto WITHDRAWN is a
//  client-side no-op that mirrors the server policy.
//

import SwiftUI

struct CarrierMyBidsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { MyBidsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Bids", systemImage: "hand.raised.fill", isCurrent: true),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct MyBid: Decodable, Identifiable, Hashable {
    let id: String
    let loadId: String
    let loadNumber: String?
    let lane: String?
    let amount: Double
    let status: String       // pending / accepted / rejected / countered / withdrawn
    let createdAt: String?
}

private struct BidKanbanColumn: Identifiable, Hashable {
    let id: String           // matches raw status value
    let label: String
    let icon: String
    let tint: ColorTint

    enum ColorTint { case warning, info, success, danger, neutral }
}

private let bidKanbanColumns: [BidKanbanColumn] = [
    .init(id: "pending",   label: "PENDING",   icon: "hourglass",                       tint: .warning),
    .init(id: "countered", label: "COUNTERED", icon: "arrow.left.arrow.right",          tint: .info),
    .init(id: "accepted",  label: "ACCEPTED",  icon: "checkmark.seal.fill",             tint: .success),
    .init(id: "rejected",  label: "REJECTED",  icon: "xmark.octagon.fill",              tint: .danger),
    .init(id: "withdrawn", label: "WITHDRAWN", icon: "arrow.uturn.backward.circle.fill", tint: .neutral),
]

private struct MyBidsBody: View {
    @Environment(\.palette) private var palette
    @State private var bids: [MyBid] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var selected: String = "pending"
    @State private var dragHoverColumn: String? = nil
    @State private var cancelling: String? = nil
    @State private var actionError: String? = nil
    @State private var lastCancelled: String? = nil

    private var byColumn: [String: [MyBid]] {
        Dictionary(grouping: bids) { $0.status.lowercased() }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    header
                    scrubber
                    if loading && bids.isEmpty {
                        LifecycleCard {
                            Text("Loading bids…")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    } else if bids.isEmpty {
                        EusoEmptyState(
                            systemImage: "hand.raised",
                            title: "No bids yet",
                            subtitle: "Bid on loads from the marketplace; outcomes show up here."
                        )
                    } else {
                        columnPager
                            .frame(minHeight: 480)
                    }
                    if let m = lastCancelled {
                        LifecycleCard(accentGradient: true) {
                            Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
                        }
                    }
                    if let e = actionError {
                        LifecycleCard(accentDanger: true) {
                            Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, 14).padding(.top, 8)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CARRIER · MY BIDS · LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("My bids")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Drag a PENDING card to WITHDRAWN to cancel it. Tap COUNTERED to view + reply.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scrubber: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(bidKanbanColumns) { col in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { selected = col.id }
                    } label: {
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: col.icon).font(.system(size: 9, weight: .heavy))
                                Text(col.label).font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            }
                            Text("\(byColumn[col.id]?.count ?? 0)")
                                .font(.system(size: 13, weight: .heavy)).monospacedDigit()
                        }
                        .foregroundStyle(selected == col.id ? .white : palette.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(selected == col.id ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var columnPager: some View {
        TabView(selection: $selected) {
            ForEach(bidKanbanColumns) { col in
                column(col).tag(col.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func column(_ col: BidKanbanColumn) -> some View {
        let cards = byColumn[col.id] ?? []
        let isHover = dragHoverColumn == col.id
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text(col.label)
                        .font(.system(size: 13, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textPrimary)
                    Text("\(cards.count)")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                    Spacer(minLength: 0)
                    if col.id == "withdrawn" {
                        Text("DROP PENDING HERE TO WITHDRAW")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                if cards.isEmpty {
                    EusoEmptyState(
                        systemImage: col.icon,
                        title: emptyTitle(col),
                        subtitle: emptySubtitle(col)
                    )
                } else {
                    ForEach(cards) { b in
                        cardView(b, col: col)
                            .draggable(b.id) {
                                cardView(b, col: col)
                                    .frame(maxWidth: 320)
                                    .opacity(0.92)
                                    .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
                            }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    isHover ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(Color.clear),
                    lineWidth: isHover ? 2 : 0
                )
                .padding(.horizontal, 8)
                .animation(.easeOut(duration: 0.12), value: isHover)
        )
        .dropDestination(for: String.self) { droppedIds, _ in
            guard let droppedId = droppedIds.first else { return false }
            guard let bid = bids.first(where: { $0.id == droppedId }) else { return false }
            // Only one transition is user-driven: pending → withdrawn.
            // Server enforces the same policy in catalysts.cancelBid, so
            // a stale client view that tries other transitions still
            // gets the right answer; the no-op here just spares the
            // wasted round-trip.
            guard col.id == "withdrawn", bid.status.lowercased() == "pending" else {
                return false
            }
            Task { await cancel(bid: bid) }
            return true
        } isTargeted: { hovering in
            dragHoverColumn = hovering ? col.id : (dragHoverColumn == col.id ? nil : dragHoverColumn)
        }
    }

    private func cardView(_ b: MyBid, col: BidKanbanColumn) -> some View {
        LifecycleCard(
            accentDanger: col.id == "rejected",
            accentWarning: col.id == "countered",
            accentGradient: col.id == "accepted"
        ) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(col.label)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(tintColor(col).opacity(0.18)))
                        .foregroundStyle(tintColor(col))
                    Spacer()
                    if cancelling == b.id {
                        ProgressView().scaleEffect(0.6)
                        Text("WITHDRAWING…")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                LifecycleSection(label: dashIfEmpty(b.loadNumber).uppercased(), icon: "doc.text")
                LifecycleRow(label: "Lane",      value: dashIfEmpty(b.lane))
                LifecycleRow(label: "Amount",    value: usd(b.amount))
                LifecycleRow(label: "Submitted", value: humanISO(b.createdAt))
                if col.id == "countered" {
                    Button {
                        NotificationCenter.default.post(
                            name: .eusoCarrierNavSwap,
                            object: nil,
                            userInfo: ["screenId": "305", "bidId": b.id]
                        )
                    } label: {
                        Text("View counter →")
                            .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(LinearGradient.diagonal).clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func tintColor(_ col: BidKanbanColumn) -> Color {
        switch col.tint {
        case .warning: return .orange
        case .info:    return .blue
        case .success: return Brand.success
        case .danger:  return Brand.danger
        case .neutral: return palette.textSecondary
        }
    }

    private func emptyTitle(_ col: BidKanbanColumn) -> String {
        switch col.id {
        case "pending":   return "No pending bids"
        case "countered": return "No counter offers"
        case "accepted":  return "Nothing won yet"
        case "rejected":  return "No rejections"
        case "withdrawn": return "No withdrawn bids"
        default:          return "Empty"
        }
    }

    private func emptySubtitle(_ col: BidKanbanColumn) -> String {
        switch col.id {
        case "pending":   return "Bids awaiting shipper response will land here."
        case "countered": return "If a shipper counters your bid, the card appears here."
        case "accepted":  return "Wins land here — load goes to your dispatch board."
        case "rejected":  return "Bids the shipper picked someone else on land here."
        case "withdrawn": return "Drag a pending bid here to cancel it."
        default:          return ""
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [MyBid] = try await EusoTripAPI.shared.queryNoInput("catalysts.getMyBids")
            bids = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func cancel(bid: MyBid) async {
        await MainActor.run { cancelling = bid.id; actionError = nil }
        struct In: Encodable { let bidId: String }
        struct Out: Decodable { let success: Bool?; let bidId: String? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "catalysts.cancelBid",
                input: In(bidId: bid.id)
            )
            await MainActor.run {
                lastCancelled = "\(bid.loadNumber ?? "LD-\(bid.id)") · bid withdrawn"
            }
            await load()
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.18)) { selected = "withdrawn" }
            }
        } catch {
            await MainActor.run {
                actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
        }
        await MainActor.run { cancelling = nil }
    }
}

#Preview("308 · My bids · Night") { CarrierMyBidsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("308 · My bids · Afternoon") { CarrierMyBidsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
