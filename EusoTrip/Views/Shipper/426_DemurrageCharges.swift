//
//  426_DemurrageCharges.swift
//  EusoTrip — Shipper · Demurrage charges (auto-gen + approve).
//
//  Cross-role chain: shipper-side approval here triggers
//  catalysts.acceptDemurrage on the carrier's accessorial queue +
//  emits ACCESSORIAL_APPROVED so the carrier's settlement page
//  refreshes via realtime.
//
//  Reshaped 2026-05-23 from a flat list (with per-card "Approve" /
//  "Dispute" buttons that only rendered on `pending_approval` rows)
//  into a 3-column Kanban with two real DnD transitions firing the
//  same canonical `demurrage.respond(id, approve)` mutation. First
//  Kanban on origin with two drag transitions (others were
//  single-transition).
//

import SwiftUI

struct DemurrageChargesScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { DemurrageBody() } nav: { shipperLifecycleNav() }
    }
}

private struct DemurrageRow: Decodable, Identifiable, Hashable {
    let id: String
    let loadId: String
    let loadNumber: String?
    let amount: Double
    let hoursDetained: Double?
    let rate: Double?
    let evidenceUrl: String?
    let status: String?
    let createdAt: String?
}

private struct DemurrageKanbanColumn: Identifiable, Hashable {
    let id: String
    let label: String
    let icon: String
    let statuses: [String]
}

private let demurrageKanbanColumns: [DemurrageKanbanColumn] = [
    .init(id: "pending",  label: "PENDING APPROVAL", icon: "hourglass",            statuses: ["pending_approval", "pending"]),
    .init(id: "approved", label: "APPROVED",         icon: "checkmark.seal.fill",  statuses: ["approved", "accepted"]),
    .init(id: "disputed", label: "DISPUTED",         icon: "exclamationmark.bubble.fill", statuses: ["disputed", "rejected"]),
]

private struct DemurrageBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [DemurrageRow] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var processing: String? = nil
    @State private var actionError: String? = nil
    @State private var lastAction: String? = nil
    @State private var selected: String = "pending"
    @State private var dragHoverColumn: String? = nil

    private func columnId(for status: String?) -> String {
        let s = (status ?? "pending").lowercased()
        return demurrageKanbanColumns.first(where: { $0.statuses.contains(s) })?.id ?? "pending"
    }

    private var byColumn: [String: [DemurrageRow]] {
        Dictionary(grouping: rows) { columnId(for: $0.status) }
    }

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
                scrubber
                if loading && rows.isEmpty {
                    LifecycleCard {
                        Text("Loading demurrage queue…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else if rows.isEmpty {
                    EusoEmptyState(
                        systemImage: "clock",
                        title: "No demurrage",
                        subtitle: "Detention events generate rows here automatically."
                    )
                } else {
                    columnPager
                        .frame(minHeight: 480)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · DEMURRAGE · LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Demurrage charges")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Drag a PENDING card to APPROVED to settle, or to DISPUTED to push to arbitration. Carrier sees the outcome via realtime.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scrubber: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(demurrageKanbanColumns) { col in
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
            ForEach(demurrageKanbanColumns) { col in
                column(col).tag(col.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func column(_ col: DemurrageKanbanColumn) -> some View {
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
                    if col.id == "approved" {
                        Text("DROP PENDING TO APPROVE")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                    } else if col.id == "disputed" {
                        Text("DROP PENDING TO DISPUTE")
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
                    ForEach(cards) { r in
                        cardView(r, columnId: col.id)
                            .draggable(r.id) {
                                cardView(r, columnId: col.id)
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
            // Two transitions are user-driven, both from PENDING:
            //   PENDING → APPROVED → demurrage.respond(approve: true)
            //   PENDING → DISPUTED → demurrage.respond(approve: false)
            // Drops from any non-pending row are no-ops because the
            // server doesn't expose a re-decide path.
            guard columnId(for: src.status) == "pending" else { return false }
            switch col.id {
            case "approved":
                Task { await respond(r: src, approve: true) }
                return true
            case "disputed":
                Task { await respond(r: src, approve: false) }
                return true
            default:
                return false
            }
        } isTargeted: { hovering in
            dragHoverColumn = hovering ? col.id : (dragHoverColumn == col.id ? nil : dragHoverColumn)
        }
    }

    private func cardView(_ r: DemurrageRow, columnId: String) -> some View {
        let isApproving = processing == r.id + ":a"
        let isDisputing = processing == r.id + ":d"
        return LifecycleCard(
            accentDanger: columnId == "disputed",
            accentGradient: columnId == "approved"
        ) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    LifecycleSection(label: dashIfEmpty(r.loadNumber).uppercased(), icon: "doc.text")
                    Spacer(minLength: 0)
                    Text(columnLabel(columnId))
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(columnTint(columnId).opacity(0.18)))
                        .foregroundStyle(columnTint(columnId))
                }
                LifecycleRow(label: "Hours",   value: r.hoursDetained.map { String(format: "%.1f", $0) } ?? "—")
                LifecycleRow(label: "Rate",    value: usd(r.rate))
                LifecycleRow(label: "Amount",  value: usd(r.amount))
                if columnId == "pending" {
                    HStack(spacing: 8) {
                        Button {
                            Task { await respond(r: r, approve: true) }
                        } label: {
                            HStack(spacing: 6) {
                                if isApproving { ProgressView().tint(.white) }
                                Text(isApproving ? "Approving…" : "Approve")
                                    .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(LinearGradient.diagonal).clipShape(Capsule())
                        }.buttonStyle(.plain).disabled(processing != nil)
                        Button {
                            Task { await respond(r: r, approve: false) }
                        } label: {
                            HStack(spacing: 6) {
                                if isDisputing { ProgressView().tint(.white) }
                                Text(isDisputing ? "Disputing…" : "Dispute")
                                    .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Brand.danger).clipShape(Capsule())
                        }.buttonStyle(.plain).disabled(processing != nil)
                    }
                }
            }
        }
    }

    private func columnLabel(_ id: String) -> String {
        switch id {
        case "pending":  return "PENDING"
        case "approved": return "APPROVED"
        case "disputed": return "DISPUTED"
        default:         return id.uppercased()
        }
    }

    private func columnTint(_ id: String) -> Color {
        switch id {
        case "pending":  return .orange
        case "approved": return Brand.success
        case "disputed": return Brand.danger
        default:         return palette.textSecondary
        }
    }

    private func emptyTitle(_ col: DemurrageKanbanColumn) -> String {
        switch col.id {
        case "pending":  return "No pending charges"
        case "approved": return "Nothing approved yet"
        case "disputed": return "No active disputes"
        default:         return "Empty"
        }
    }

    private func emptySubtitle(_ col: DemurrageKanbanColumn) -> String {
        switch col.id {
        case "pending":  return "ELD detention events auto-generate rows here for your review."
        case "approved": return "Drag a pending card here or tap Approve. Settlement-builder picks up next cycle."
        case "disputed": return "Drag a pending card here or tap Dispute. Carrier sees the rejection in realtime."
        default:         return ""
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [DemurrageRow] = try await EusoTripAPI.shared.queryNoInput("demurrage.listForShipper")
            rows = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func respond(r: DemurrageRow, approve: Bool) async {
        await MainActor.run {
            processing = r.id + (approve ? ":a" : ":d")
            actionError = nil
        }
        struct In: Encodable { let id: String; let approve: Bool }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "demurrage.respond",
                input: In(id: r.id, approve: approve)
            )
            await MainActor.run {
                lastAction = "\(r.loadNumber ?? r.id) → \(approve ? "APPROVED" : "DISPUTED")"
            }
            await load()
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.18)) {
                    selected = approve ? "approved" : "disputed"
                }
            }
        } catch {
            await MainActor.run {
                actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
        }
        await MainActor.run { processing = nil }
    }
}

#Preview("426 · Demurrage · Night") { DemurrageChargesScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("426 · Demurrage · Afternoon") { DemurrageChargesScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
