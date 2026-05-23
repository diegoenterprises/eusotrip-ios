//
//  404_BrokerCommissionQueue.swift
//  EusoTrip — Broker · Commission queue (brick 404).
//
//  Cross-role chain: load delivers → settlement-builder cron splits
//  shipper-broker contract from broker-carrier contract → broker
//  commission row appears here → on payable date the wallet credits
//  fire (financial:commission_paid event).
//
//  Reshaped 2026-05-23 from a flat list into a 3-column Kanban with
//  drag-to-approve, backed by a real persisted broker_commissions
//  table (migration 0312) and real `brokers.approveCommission`
//  mutation. The prior implementation called `getCommissionQueue`
//  which didn't exist server-side — the screen silently failed.
//
//  Lifecycle:
//    PENDING   — created by settlement-builder when a brokered load
//                delivers. Drag a card to APPROVED to fire
//                `brokers.approveCommission` (stamps approvedAt +
//                approvedBy + blockchain_audit_trail row).
//    APPROVED  — awaiting payable_date. Cron-only transition to PAID;
//                drag onto PAID is a no-op (the cron owns the wallet
//                credit + paidAt stamp).
//    PAID      — terminal. paidAt populated. Wallet credit landed.
//

import SwiftUI

private struct Commission: Decodable, Identifiable, Hashable {
    let id: String
    let loadNumber: String?
    let shipperPay: Double?
    let carrierPay: Double?
    let margin: Double?
    let payableDate: String?
    let paidAt: String?
    let status: String       // "pending" / "approved" / "paid"
}

private struct CommissionKanbanColumn: Identifiable, Hashable {
    let id: String           // "pending" / "approved" / "paid"
    let label: String
    let icon: String
    let tint: ColorTint

    enum ColorTint { case warning, info, success }
}

private let commissionKanbanColumns: [CommissionKanbanColumn] = [
    .init(id: "pending",  label: "PENDING",  icon: "hourglass",         tint: .warning),
    .init(id: "approved", label: "APPROVED", icon: "checkmark.seal",    tint: .info),
    .init(id: "paid",     label: "PAID",     icon: "creditcard.fill",   tint: .success),
]

struct BrokerCommissionQueueScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { CommissionQueueBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Carriers", systemImage: "person.3.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

private struct CommissionQueueBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @State private var rows: [Commission] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var showSignOutConfirm: Bool = false

    @State private var selected: String = "pending"
    @State private var dragHoverColumn: String? = nil
    @State private var approving: String? = nil
    @State private var actionError: String? = nil
    @State private var lastApproved: String? = nil

    private var byColumn: [String: [Commission]] {
        Dictionary(grouping: rows) { (($0.status).lowercased()) }
    }

    private var totalPending: Double {
        (byColumn["pending"] ?? []).compactMap { $0.margin }.reduce(0, +)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    header
                    if !rows.isEmpty {
                        LifecycleCard(accentGradient: true) {
                            LifecycleSection(label: "PENDING COMMISSION", icon: "creditcard.fill")
                            Text(usd(totalPending))
                                .font(.system(size: 32, weight: .heavy))
                                .foregroundStyle(palette.textPrimary)
                                .monospacedDigit()
                        }
                    }
                    scrubber
                    if loading && rows.isEmpty {
                        LifecycleCard {
                            Text("Loading commissions…")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    } else if rows.isEmpty {
                        EusoEmptyState(
                            systemImage: "tray",
                            title: "No commissions yet",
                            subtitle: "When loads you brokered close, your margin shows up here."
                        )
                    } else {
                        columnPager
                            .frame(minHeight: 480)
                    }
                    if let m = lastApproved {
                        LifecycleCard(accentGradient: true) {
                            Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
                        }
                    }
                    if let e = actionError {
                        LifecycleCard(accentDanger: true) {
                            Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    }
                    meSection
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, 14).padding(.top, 8)
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .alert("Sign out?", isPresented: $showSignOutConfirm) {
            Button("Sign out", role: .destructive) { Task { await session.signOut() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign back in to see broker tenders + commissions.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("BROKER · COMMISSION QUEUE · LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Commission queue")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Drag a PENDING card to APPROVED to release for cron settlement.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var scrubber: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(commissionKanbanColumns) { col in
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
                Spacer(minLength: 0)
            }
        }
    }

    private var columnPager: some View {
        TabView(selection: $selected) {
            ForEach(commissionKanbanColumns) { col in
                column(col).tag(col.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func column(_ col: CommissionKanbanColumn) -> some View {
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
                    if col.id == "pending" {
                        Text("→ APPROVED")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                    } else if col.id == "approved" {
                        Text("CRON → PAID")
                            .font(.system(size: 9, weight: .heavy))
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
                    ForEach(cards) { c in
                        cardView(c, col: col)
                            .draggable(c.id) {
                                cardView(c, col: col)
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
            guard let src = rows.first(where: { $0.id == droppedId }) else { return false }
            // Only one transition is user-driven: pending → approved.
            // approved → paid is cron-only (wallet credit lands first).
            // Same-column drop or any other transition is a no-op.
            guard src.status.lowercased() == "pending", col.id == "approved" else {
                return false
            }
            Task { await approve(commission: src) }
            return true
        } isTargeted: { hovering in
            dragHoverColumn = hovering ? col.id : (dragHoverColumn == col.id ? nil : dragHoverColumn)
        }
    }

    private func cardView(_ c: Commission, col: CommissionKanbanColumn) -> some View {
        LifecycleCard(accentGradient: col.id == "paid") {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(col.label)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(tintColor(col).opacity(0.18)))
                        .foregroundStyle(tintColor(col))
                    Spacer()
                    if approving == c.id {
                        ProgressView().scaleEffect(0.6)
                        Text("APPROVING…")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                LifecycleSection(label: dashIfEmpty(c.loadNumber).uppercased(), icon: "doc.text")
                LifecycleRow(label: "Shipper pay",  value: usd(c.shipperPay))
                LifecycleRow(label: "Carrier pay",  value: usd(c.carrierPay))
                LifecycleRow(label: "Margin",       value: usd(c.margin))
                LifecycleRow(label: "Payable",      value: humanISO(c.payableDate))
                LifecycleRow(label: "Paid",         value: humanISO(c.paidAt))
            }
        }
    }

    private func tintColor(_ col: CommissionKanbanColumn) -> Color {
        switch col.tint {
        case .warning: return .orange
        case .info:    return .blue
        case .success: return .green
        }
    }

    private func emptyTitle(_ col: CommissionKanbanColumn) -> String {
        switch col.id {
        case "pending":  return "Nothing pending"
        case "approved": return "Nothing approved"
        case "paid":     return "Nothing paid yet"
        default:         return "Empty"
        }
    }

    private func emptySubtitle(_ col: CommissionKanbanColumn) -> String {
        switch col.id {
        case "pending":  return "Delivered brokered loads land here for your approval."
        case "approved": return "Approved commissions wait for the cron settlement to fire."
        case "paid":     return "Settled commissions show here with the wallet credit timestamp."
        default:         return ""
        }
    }

    /// "Me" section — sign-out CTA mirrors the legacy layout. Kept
    /// because the bottom-nav `Me` slot routes to this screen until a
    /// dedicated 420_BrokerMe surface ships.
    private var meSection: some View {
        LifecycleCard {
            LifecycleSection(label: "ME · ACCOUNT", icon: "person.crop.circle")
            VStack(spacing: 8) {
                if let name = session.user?.firstName, !name.isEmpty {
                    HStack {
                        Text("Signed in as")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                        Spacer(minLength: 0)
                        Text(name)
                            .font(EType.body.weight(.semibold))
                            .foregroundStyle(palette.textPrimary)
                    }
                }
                Button { showSignOutConfirm = true } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundStyle(Brand.danger)
                        Text("Sign out")
                            .font(EType.body.weight(.semibold))
                            .foregroundStyle(Brand.danger)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sign out of broker account")
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [Commission] = try await EusoTripAPI.shared.queryNoInput("brokers.getCommissionQueue")
            rows = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func approve(commission: Commission) async {
        await MainActor.run { approving = commission.id; actionError = nil }
        struct In: Encodable { let commissionId: String }
        struct Out: Decodable { let success: Bool?; let alreadyApproved: Bool?; let status: String? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "brokers.approveCommission",
                input: In(commissionId: commission.id)
            )
            await MainActor.run {
                lastApproved = "\(commission.loadNumber ?? "LD-\(commission.id)") → APPROVED"
            }
            await load()
        } catch {
            await MainActor.run {
                actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
        }
        await MainActor.run { approving = nil }
    }
}

#Preview("404 · Commission · Night") { BrokerCommissionQueueScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("404 · Commission · Afternoon") { BrokerCommissionQueueScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
