//
//  406_BrokerCatalystVetting.swift
//  EusoTrip — Broker · Catalyst Vetting (brick 406).
//
//  iOS port of the web `frontend/client/src/pages/CatalystVetting.tsx`.
//  Plugs the broker into the catalyst-onboarding-review queue that
//  the eusotrip-killers scheduled team built on the web side. Server-
//  side stub functions were upgraded to real DB writes in the same
//  commit pair (`brokers.{getVettingStats, approveCatalyst,
//  rejectCatalyst}`) so this screen never renders fake data.
//
//  Reshaped 2026-05-23 from a flat pending list (with per-card
//  Approve / Reject buttons) into a stat-tile-drop-zone pattern.
//  The APPROVED + REJECTED stat tiles at the top now double as
//  .dropDestination targets: drag a pending applicant card up onto
//  either tile to fire the canonical brokers.{approveCatalyst,
//  rejectCatalyst} mutation in one gesture. Per-card buttons stay
//  as tap fallbacks.
//
//  Drag-on-stat-tile is a different shape than the column-pager
//  Kanban (301/308/404/426/435/902) and the carousel/list pair-
//  drop pattern (702). It fits surfaces where the destination
//  buckets are tiny summary cards rather than full column views.
//
//  Doctrine refs:
//    • feedback_zero_stubs_doctrine — every button must wire to a
//      real action.
//    • feedback_cross_role_action_chain — approval flips the
//      target company's `companies.complianceStatus = 'compliant'`
//      and emits a `brokers.catalyst_approved` audit row.
//    • feedback_pulse_role_wiring — server-side endpoints exist;
//      Pulse can ride the same `brokers.getPendingVetting` query.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire models (mirror server return shapes)

struct BrokerPendingVettingItem: Decodable, Identifiable, Hashable {
    var id: String { catalystId }
    let catalystId: String
    let name: String
    let dotNumber: String
    let mcNumber: String
    let status: String
    let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case catalystId = "id"
        case name, dotNumber, mcNumber, status, createdAt
    }
}

struct BrokerVettingStats: Decodable, Hashable {
    let pending: Int
    let approved: Int
    let rejected: Int
    let total: Int
}

// MARK: - Screen

struct BrokerCatalystVettingScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { CatalystVettingBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Loads",    systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Carriers", systemImage: "person.3.fill",   isCurrent: true),
                           NavSlot(label: "Me",       systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct CatalystVettingBody: View {
    @Environment(\.palette) private var palette
    @State private var search: String = ""
    @State private var items: [BrokerPendingVettingItem] = []
    @State private var stats: BrokerVettingStats?
    @State private var loading: Bool = true
    @State private var error: String?
    @State private var actingCatalystId: String? = nil
    @State private var actionError: String? = nil
    @State private var lastAction: String? = nil
    /// Drop-target highlight state. `"approved"` / `"rejected"` when a
    /// card is hovering over the matching stat tile; nil otherwise.
    @State private var dragHoverTile: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let s = stats {
                    statsRow(s)
                }
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
                searchField
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    // MARK: subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("BROKER · CATALYST VETTING · LIVE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Pending applications")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Drag a card onto the APPROVED or REJECTED tile to decide in one gesture. Tap-buttons stay on every card.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statsRow(_ s: BrokerVettingStats) -> some View {
        HStack(spacing: Space.s2) {
            statTile(
                id: "pending",
                label: "PENDING",
                value: "\(s.pending)",
                icon: "clock",
                tint: .orange,
                isDropTarget: false
            )
            statTile(
                id: "approved",
                label: "APPROVED",
                value: "\(s.approved)",
                icon: "checkmark.seal.fill",
                tint: Brand.success,
                isDropTarget: true
            )
            statTile(
                id: "rejected",
                label: "REJECTED",
                value: "\(s.rejected)",
                icon: "xmark.octagon.fill",
                tint: Brand.danger,
                isDropTarget: true
            )
        }
    }

    private func statTile(
        id: String,
        label: String,
        value: String,
        icon: String,
        tint: Color,
        isDropTarget: Bool
    ) -> some View {
        let isHover = dragHoverTile == id
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }
            Text(value)
                .font(.system(size: 22, weight: .heavy).monospacedDigit())
                .foregroundStyle(tint)
            if isDropTarget {
                Text(isHover ? "RELEASE TO \(label)" : "DROP CARDS HERE")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(isHover ? tint : palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(palette.bgCard, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(
                    isHover ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(tint.opacity(isDropTarget ? 0.3 : 0.18)),
                    lineWidth: isHover ? 2 : 1
                )
                .animation(.easeOut(duration: 0.12), value: isHover)
        )
        .dropDestination(for: String.self) { droppedIds, _ in
            guard isDropTarget else { return false }
            guard let catalystId = droppedIds.first else { return false }
            guard items.contains(where: { $0.catalystId == catalystId }) else { return false }
            switch id {
            case "approved":
                Task { await approve(catalystId) }
                return true
            case "rejected":
                Task { await reject(catalystId) }
                return true
            default:
                return false
            }
        } isTargeted: { hovering in
            guard isDropTarget else { return }
            dragHoverTile = hovering ? id : (dragHoverTile == id ? nil : dragHoverTile)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.callout.weight(.semibold))
                .foregroundStyle(palette.textTertiary)
            TextField("Search by company name", text: $search)
                .textInputAutocapitalization(.words)
                .onSubmit { Task { await loadList() } }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderSoft)
        )
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            LifecycleCard {
                Text("Loading pending vettings…")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        } else if let err = error {
            LifecycleCard(accentDanger: true) {
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            }
        } else if items.isEmpty {
            EusoEmptyState(
                systemImage: "checkmark.circle",
                title: "Nothing pending",
                subtitle: "All catalyst applications are reviewed. New submissions land here automatically."
            )
        } else {
            ForEach(items) { item in
                Button {
                    // Tap a row → drill into 407 (per-applicant details).
                    NotificationCenter.default.post(
                        name: .eusoBrokerNavSwap,
                        object: nil,
                        userInfo: ["screenId": "407", "catalystId": item.catalystId]
                    )
                } label: {
                    vettingCard(item)
                }
                .buttonStyle(.plain)
                .draggable(item.catalystId) {
                    vettingCard(item)
                        .frame(maxWidth: 320)
                        .opacity(0.92)
                        .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
                }
            }
        }
    }

    @ViewBuilder
    private func vettingCard(_ item: BrokerPendingVettingItem) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 10) {
                LifecycleSection(label: item.name.uppercased(), icon: "person.2.crop.square.stack")
                LifecycleRow(label: "USDOT",  value: dashIfEmpty(item.dotNumber))
                LifecycleRow(label: "MC",     value: dashIfEmpty(item.mcNumber))
                LifecycleRow(label: "Status", value: item.status.capitalized)
                if !item.createdAt.isEmpty {
                    LifecycleRow(label: "Applied", value: shortDate(item.createdAt))
                }
                HStack(spacing: 10) {
                    Button {
                        Task { await approve(item.catalystId) }
                    } label: {
                        HStack(spacing: 6) {
                            if actingCatalystId == item.catalystId {
                                ProgressView().controlSize(.mini)
                            }
                            Text("Approve")
                                .font(EType.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(LinearGradient.diagonal)
                        .foregroundStyle(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(actingCatalystId != nil)

                    Button {
                        Task { await reject(item.catalystId) }
                    } label: {
                        Text("Reject")
                            .font(EType.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(palette.textPrimary)
                            .background(palette.bgCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .strokeBorder(Brand.danger.opacity(0.5))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(actingCatalystId != nil)
                }
            }
        }
    }

    // MARK: pipeline

    private func loadAll() async {
        loading = true; error = nil
        async let listTask: Void = loadList()
        async let statsTask: Void = loadStats()
        _ = await (listTask, statsTask)
        loading = false
    }

    private func loadList() async {
        struct In: Encodable { let search: String? }
        do {
            let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
            let rows: [BrokerPendingVettingItem] = try await EusoTripAPI.shared.query(
                "brokers.getPendingVetting",
                input: In(search: q.isEmpty ? nil : q)
            )
            self.items = rows
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func loadStats() async {
        do {
            let s: BrokerVettingStats = try await EusoTripAPI.shared.queryNoInput(
                "brokers.getVettingStats"
            )
            self.stats = s
        } catch {
            // Silent — stats are optional context.
        }
    }

    private func approve(_ catalystId: String) async {
        await MainActor.run { actingCatalystId = catalystId; actionError = nil }
        defer { Task { await MainActor.run { actingCatalystId = nil } } }
        let label = items.first(where: { $0.catalystId == catalystId })?.name ?? "catalyst \(catalystId)"
        struct In: Encodable { let catalystId: String }
        struct Out: Decodable { let success: Bool; let catalystId: String }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "brokers.approveCatalyst",
                input: In(catalystId: catalystId)
            )
            await MainActor.run { lastAction = "\(label) → APPROVED" }
            await loadAll()
        } catch {
            await MainActor.run {
                actionError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
        }
    }

    private func reject(_ catalystId: String) async {
        await MainActor.run { actingCatalystId = catalystId; actionError = nil }
        defer { Task { await MainActor.run { actingCatalystId = nil } } }
        let label = items.first(where: { $0.catalystId == catalystId })?.name ?? "catalyst \(catalystId)"
        struct In: Encodable { let catalystId: String; let reason: String? }
        struct Out: Decodable { let success: Bool; let catalystId: String }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "brokers.rejectCatalyst",
                input: In(catalystId: catalystId, reason: nil)
            )
            await MainActor.run { lastAction = "\(label) → REJECTED" }
            await loadAll()
        } catch {
            await MainActor.run {
                actionError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
        }
    }

    // MARK: helpers

    private func dashIfEmpty(_ s: String?) -> String {
        let trimmed = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    private func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.dateStyle = .medium
        return out.string(from: d)
    }
}

// MARK: - Previews

#Preview("Loading · Dark") {
    BrokerCatalystVettingScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("Loading · Light") {
    BrokerCatalystVettingScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
