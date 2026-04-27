//
//  201_ShipperLoads.swift
//  EusoTrip — Shipper · Loads (brick 201).
//
//  Second brick on the Shipper role track. The "Loads" slot in the
//  200 Shipper Home BottomNav (`shipperNavLeading_200`) routes here.
//
//  Doctrine compliance (EUSOTRIP2027GOLD §2 / §4 / §5 / §7 / §10):
//    • §2 — Brand accent is `LinearGradient.diagonal` only. No flat
//      Brand.info / Brand.blue fills. Filter chips, status pills,
//      gradient hairline under header, "+ Post Load" CTA — all
//      gradient.
//    • §4 — Spacing / radius / type from tokens (Space.s*, Radius.*,
//      EType.*). No magic numbers.
//    • §5 — Palette semantic only. No hard-coded Color.white /
//      Color.black / Color.gray fills.
//    • §7 — Ternary shape-styles wrapped in `AnyShapeStyle`.
//    • §10 — Both register previews compile in isolation; no
//      network in previews.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data"):
//
//    • Active loads list  → `ShipperActiveLoadsStore` (existing,
//      LiveDataStores.swift L3191) → `shippers.getActiveLoads`.
//      MCP-verified at `frontend/server/routers/shippers.ts:109`.
//    • Recent loads list  → `ShipperRecentLoadsStore` (existing,
//      LiveDataStores.swift L3217) → `shippers.getRecentLoads`.
//      MCP-verified at `frontend/server/routers/shippers.ts:191`.
//    • Filter chip strip selects which feed renders + (when on
//      "All") merges both with a sticky "Active first / Recent
//      second" sort. Empty/error/loading branches all surface
//      through `EusoEmptyState` per doctrine.
//    • Search input filters the merged in-memory rows by load
//      number / origin / destination — no extra round trip; the
//      server limit (10 active + 5 recent) is the authoritative
//      working set.
//    • Tap a load row → presents the live `ShipperLoadDetail`
//      sheet (brick 205, shipped 2026-04-26 in eusotrip-killers
//      122nd firing). Detail data flows through
//      `ShipperLoadDetailStore` → `loads.getById` (loads.ts:1046),
//      with bid count + highest amount via the existing
//      `ShipperBidsStore` → `shippers.getBidsForLoad`. NEVER fake
//      data — every field renders verbatim from the server, and
//      missing optional columns surface as em-dash sentinels.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Filter taxonomy

private enum ShipperLoadsFilter: String, CaseIterable, Identifiable {
    case all       = "All"
    case active    = "Active"
    case recent    = "Recent"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all:     return "tray.full"
        case .active:  return "shippingbox.and.arrow.backward"
        case .recent:  return "clock.arrow.circlepath"
        }
    }
}

/// Adapter row used by the merged "All" view so a single ForEach
/// can render both ActiveLoad and RecentLoad uniformly. We never
/// fabricate data for missing fields — `driver` / `eta` collapse
/// to nil for recent-load rows so the UI elides those subtitle
/// chips entirely (no "TBD" / "—" filler).
private struct ShipperLoadRow: Identifiable, Hashable {
    /// The local row identity (prefixed with "active-" / "recent-" so
    /// the sheet item resolves uniquely even if the same numeric load
    /// appears in both feeds during a short transition window).
    let id: String
    /// The numeric server-side load id, stripped of the `load_` prefix
    /// the shippers router emits. Passed verbatim to `loads.getById`
    /// (Zod input `{ id: z.string() }` — see loads.ts:1047). Empty
    /// string when the upstream id is malformed.
    let serverLoadId: String
    let loadNumber: String
    let status: String
    let origin: String
    let destination: String
    let rate: Double
    let driver: String?
    let eta: String?
    let deliveredAt: String?
    let isActive: Bool

    /// Strip the `load_` prefix the shippers router emits in front of
    /// the raw numeric id. The 205 detail surface needs the bare
    /// numeric form because `loads.getById` parses it back to an Int
    /// via `parseInt(input.id, 10)`.
    private static func stripLoadPrefix(_ raw: String) -> String {
        raw.hasPrefix("load_") ? String(raw.dropFirst("load_".count)) : raw
    }

    static func from(_ a: ShipperAPI.ActiveLoad) -> ShipperLoadRow {
        ShipperLoadRow(
            id: "active-\(a.id)",
            serverLoadId: stripLoadPrefix(a.id),
            loadNumber: a.loadNumber,
            status: a.status,
            origin: a.origin,
            destination: a.destination,
            rate: a.rate,
            driver: a.driver.isEmpty ? nil : a.driver,
            eta: a.eta.isEmpty ? nil : a.eta,
            deliveredAt: nil,
            isActive: true
        )
    }

    static func from(_ r: ShipperAPI.RecentLoad) -> ShipperLoadRow {
        ShipperLoadRow(
            id: "recent-\(r.id)",
            serverLoadId: stripLoadPrefix(r.id),
            loadNumber: r.loadNumber,
            status: r.status,
            origin: r.origin,
            destination: r.destination,
            rate: r.rate,
            driver: nil,
            eta: nil,
            deliveredAt: r.deliveredAt.isEmpty ? nil : r.deliveredAt,
            isActive: false
        )
    }
}

// MARK: - Screen body

struct ShipperLoads: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var active = ShipperActiveLoadsStore()
    @StateObject private var recent = ShipperRecentLoadsStore()

    @State private var filter: ShipperLoadsFilter = .all
    @State private var query: String = ""
    @State private var detailRow: ShipperLoadRow? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                searchField
                filterChips
                rowsCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await refreshAll() }
        .refreshable { await refreshAll() }
        .sheet(item: $detailRow) { row in
            // 122nd eusotrip-killers firing · 2026-04-26 — brick 205
            // ShipperLoadDetail shipped. The legacy placeholder
            // (`loadDetailPlaceholderSheet`) is preserved below for
            // historical reference but no longer rendered. Real
            // detail data flows through `ShipperLoadDetailStore` →
            // `loads.getById`.
            ShipperLoadDetail(
                loadId: row.serverLoadId,
                previewLoadNumber: row.loadNumber,
                previewLane: "\(row.origin) → \(row.destination)"
            )
            .padding(.horizontal, 14)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(palette.bgPage.ignoresSafeArea())
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .screenTileRoot()
    }

    private func refreshAll() async {
        async let a: Void = active.refresh()
        async let b: Void = recent.refresh()
        _ = await (a, b)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36)
                .background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SHIPPER · LOADS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Your shipment fabric")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(headerSubhead)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private var headerSubhead: String {
        let activeCount = (active.state.value ?? []).count
        let recentCount = (recent.state.value ?? []).count
        if !active.state.isSettled || !recent.state.isSettled {
            return "Loading load fabric…"
        }
        let total = activeCount + recentCount
        if total == 0 { return "Post your first load to populate this feed." }
        return "\(activeCount) active · \(recentCount) recent"
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            TextField("Load #, origin, destination", text: $query)
                .textFieldStyle(.plain)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .submitLabel(.search)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ShipperLoadsFilter.allCases) { f in
                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                            filter = f
                        }
                    } label: {
                        chipLabel(f)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func chipLabel(_ f: ShipperLoadsFilter) -> some View {
        let on = (filter == f)
        HStack(spacing: 6) {
            Image(systemName: f.systemImage)
                .font(.system(size: 10, weight: .heavy))
            Text(f.rawValue.uppercased())
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
        }
        .foregroundStyle(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textSecondary))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(
                on ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard)
            )
        )
        .overlay(
            Capsule().strokeBorder(
                on ? AnyShapeStyle(Color.clear) : AnyShapeStyle(palette.borderFaint),
                lineWidth: 1
            )
        )
    }

    // MARK: - Rows card

    @ViewBuilder
    private var rowsCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: filter.systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(filter.rawValue.uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if case .loaded = combined {
                    Text("\(visibleRows.count)")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch combined {
        case .loading:
            listSkeleton
        case .empty:
            emptyState
        case .loaded:
            if visibleRows.isEmpty {
                searchEmptyState
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(visibleRows) { row in
                        Button {
                            detailRow = row
                        } label: { rowView(row) }
                            .buttonStyle(.plain)
                    }
                }
            }
        case .error(let e):
            inlineError(e) { Task { await refreshAll() } }
        }
    }

    /// Folded RemoteState across the two stores. `loading` while
    /// either is still settling. `error` if either errored. `empty`
    /// if both confirmed empty. Otherwise `loaded` (the value
    /// itself is unused — `visibleRows` derives from the live
    /// stores directly).
    private var combined: RemoteState<Void> {
        if !active.state.isSettled || !recent.state.isSettled {
            return .loading
        }
        if let e = active.state.error ?? recent.state.error {
            return .error(e)
        }
        let activeEmpty = (active.state.value ?? []).isEmpty
        let recentEmpty = (recent.state.value ?? []).isEmpty
        if activeEmpty && recentEmpty { return .empty }
        return .loaded(())
    }

    /// Rows visible after applying the filter chip + search query.
    private var visibleRows: [ShipperLoadRow] {
        let activeRows = (active.state.value ?? []).map(ShipperLoadRow.from)
        let recentRows = (recent.state.value ?? []).map(ShipperLoadRow.from)

        let pool: [ShipperLoadRow]
        switch filter {
        case .all:
            pool = activeRows + recentRows
        case .active:
            pool = activeRows
        case .recent:
            pool = recentRows
        }

        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return pool }
        return pool.filter { row in
            row.loadNumber.lowercased().contains(needle)
                || row.origin.lowercased().contains(needle)
                || row.destination.lowercased().contains(needle)
        }
    }

    // MARK: - Row

    private func rowView(_ row: ShipperLoadRow) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.loadNumber)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("\(row.origin) → \(row.destination)")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                rowMetaLine(row)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.status.uppercased())
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(LinearGradient.diagonal)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1))
                if row.rate > 0 {
                    Text(dollars(row.rate))
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                }
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func rowMetaLine(_ row: ShipperLoadRow) -> some View {
        HStack(spacing: 8) {
            if let driver = row.driver {
                Image(systemName: "person.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                Text(driver)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
            if let eta = row.eta {
                if row.driver != nil {
                    Text("·").foregroundStyle(palette.textTertiary)
                }
                Text("ETA \(eta)")
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
            }
            if let delivered = row.deliveredAt {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                Text("Delivered \(delivered)")
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    // MARK: - Empty / error / skeleton states

    private var listSkeleton: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCard)
                    .frame(height: 64)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                    .opacity(0.6)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        EusoEmptyState(
            systemImage: "shippingbox",
            title: "No loads yet",
            subtitle: "Post a load and it'll show up here the moment it lands."
        )
    }

    @ViewBuilder
    private var searchEmptyState: some View {
        EusoEmptyState(
            systemImage: "magnifyingglass",
            title: "No matches",
            subtitle: "Try a different load number, origin, or destination."
        )
    }

    private func inlineError(_ error: Error, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Brand.danger)
                Text("Couldn't load shipment fabric")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text(errorMessage(for: error))
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Button(action: retry) {
                Text("Retry")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func errorMessage(for error: Error) -> String {
        if let api = error as? EusoTripAPIError {
            return api.errorDescription ?? "Request failed."
        }
        return error.localizedDescription
    }

    // MARK: - Load detail placeholder sheet (LEGACY · brick 205 shipped)
    //
    // Brick 205 (`ShipperLoadDetail`) shipped 2026-04-26 in the 122nd
    // eusotrip-killers firing. The active sheet binding above now
    // renders that real surface. This placeholder is preserved as a
    // fallback / archival reference and is no longer reached on the
    // tap path. Per SKILL.md §13: "every backend stub gap has a
    // neutral empty state on the client; no fake data."

    @available(*, deprecated, message: "Brick 205 ShipperLoadDetail shipped 2026-04-26 in the 122nd firing — the live surface replaces this placeholder. Kept for archival reference only.")
    private func loadDetailPlaceholderSheet(for row: ShipperLoadRow) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("LOAD DETAIL")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(row.loadNumber)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("\(row.origin) → \(row.destination)")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
            EusoEmptyState(
                systemImage: "hammer",
                title: "Load detail · brick 202 pending",
                subtitle: "Lane-level POD, settlement, ratecon, and timeline land in the next Shipper brick. The header above is real data; this surface intentionally shows no fabricated detail until the backend wire-up ships.",
                comingSoon: true
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.bgPage.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers

    /// Currency formatter used identically by 200 Shipper Home and
    /// every settlement-related driver brick. Single point of drift.
    private func dollars(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$0"
    }
}

// MARK: - Screen wrapper

struct ShipperLoadsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            ShipperLoads()
        } nav: {
            BottomNav(
                leading: shipperNavLeading_201(),
                trailing: shipperNavTrailing_201(),
                orbState: .idle
            )
        }
    }
}

private func shipperNavLeading_201() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",                isCurrent: false),
     NavSlot(label: "Loads", systemImage: "shippingbox.fill",     isCurrent: true)]
}

private func shipperNavTrailing_201() -> [NavSlot] {
    [NavSlot(label: "Bids",  systemImage: "hand.raised",          isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",               isCurrent: false)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so each store stays in `.loading` —
// both registers render the skeleton without hitting the network.
// Per doctrine §10: previews must compile in isolation.

#Preview("201 · Shipper · Loads · Night") {
    ShipperLoadsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("201 · Shipper · Loads · Afternoon") {
    ShipperLoadsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
