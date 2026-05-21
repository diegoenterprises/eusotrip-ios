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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let s = stats {
                    statsRow(s)
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
                Text("BROKER · CATALYST VETTING")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Pending applications")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Approve or reject catalyst onboarding requests. Decisions chain into the audit ledger.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statsRow(_ s: BrokerVettingStats) -> some View {
        HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "PENDING",  value: "\(s.pending)",  icon: "clock")
            LifecycleStatTile(label: "APPROVED", value: "\(s.approved)", icon: "checkmark.seal.fill")
            LifecycleStatTile(label: "REJECTED", value: "\(s.rejected)", icon: "xmark.octagon.fill",
                              danger: s.rejected > 0)
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
        actingCatalystId = catalystId
        defer { actingCatalystId = nil }
        struct In: Encodable { let catalystId: String }
        struct Out: Decodable { let success: Bool; let catalystId: String }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "brokers.approveCatalyst",
                input: In(catalystId: catalystId)
            )
            await loadAll()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func reject(_ catalystId: String) async {
        actingCatalystId = catalystId
        defer { actingCatalystId = nil }
        struct In: Encodable { let catalystId: String; let reason: String? }
        struct Out: Decodable { let success: Bool; let catalystId: String }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "brokers.rejectCatalyst",
                input: In(catalystId: catalystId, reason: nil)
            )
            await loadAll()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
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
    BrokerCatalystVettingScreen(theme: Theme.makeDark())
        .preferredColorScheme(.dark)
}

#Preview("Loading · Light") {
    BrokerCatalystVettingScreen(theme: Theme.makeLight())
        .preferredColorScheme(.light)
}
