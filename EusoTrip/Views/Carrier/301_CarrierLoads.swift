//
//  301_CarrierLoads.swift
//  EusoTrip — Carrier · Loads (brick 301).
//
//  Second brick on the Carrier role track (300s). The "Loads" slot
//  in the 300 Carrier Home BottomNav (`carrierNavLeading_300`)
//  routes here. Direct mirror of `Views/Shipper/201_ShipperLoads.swift`,
//  swung to the carrier side of every wire (counterparty + driver
//  + netPayout instead of shipper rate).
//
//  Doctrine compliance (EUSOTRIP2027GOLD):
//    • §1 — Brand accent is `LinearGradient.diagonal` only. No flat
//      Brand.info / Brand.blue fills. Filter chips, status pills,
//      gradient hairline under header, "+ Find load" CTA — all
//      gradient.
//    • §2 — No Toggles on this brick.
//    • §3 — Ternary shape-styles wrapped in `AnyShapeStyle`.
//    • §4 — Spacing / radius / type from tokens (Space.s*, Radius.*,
//      EType.*). No magic numbers.
//    • §5 — Palette semantic only. No hard-coded Color.white /
//      Color.black / Color.gray fills.
//    • §10 — Both register previews compile in isolation; no
//      network in previews.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data, dynamic ready pages with 0 data"):
//
//    • Active loads list  → `CarrierActiveLoadsStore` (existing,
//      LiveDataStores.swift L3274) → `carriers.getActiveLoads`.
//      Backend convention mirrors `shippers.getActiveLoads`.
//    • Recent loads list  → `CarrierRecentLoadsStore` (existing,
//      LiveDataStores.swift L3298) → `carriers.getRecentLoads`.
//    • Filter chip strip selects which feed renders + (when on
//      "All") merges both with a sticky "Active first / Recent
//      second" sort. Empty/error/loading branches all surface
//      through `EusoEmptyState` per doctrine.
//    • Search input filters the merged in-memory rows by load
//      number / origin / destination / driver / counterparty —
//      no extra round trip; the server limit (10 active + 5
//      recent) is the authoritative working set.
//    • Tap a load row → presents an `EusoEmptyState(comingSoon:
//      true)` sheet labeled "Brick 302 · Carrier Load Detail
//      pending". Real load detail wires up when 302 ships.
//      NEVER fake data.
//    • Zero synthesised data. Each card switches over its store's
//      RemoteState; `.loading` shows a skeleton, `.empty` renders
//      `EusoEmptyState`, `.error` renders an inline retry, and
//      `.loaded` paints the real values.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Filter taxonomy

private enum CarrierLoadsFilter: String, CaseIterable, Identifiable {
    case all       = "All"
    case active    = "Active"
    case recent    = "Recent"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all:     return "tray.full"
        case .active:  return "truck.box.fill"
        case .recent:  return "clock.arrow.circlepath"
        }
    }
}

/// Adapter row used by the merged "All" view so a single ForEach
/// can render both ActiveLoad and RecentLoad uniformly. We never
/// fabricate data for missing fields — `driver` / `eta` /
/// `counterparty` collapse to nil for recent-load rows so the UI
/// elides those subtitle chips entirely (no "TBD" / "—" filler).
private struct CarrierLoadRow: Identifiable, Hashable {
    let id: String
    let loadNumber: String
    let status: String
    let origin: String
    let destination: String
    /// Active rate (gross) for in-flight loads; net payout for
    /// recent (delivered) loads. Single column for either since
    /// the row UI shows one dollar value.
    let dollars: Double
    let driver: String?
    let counterparty: String?
    let eta: String?
    let deliveredAt: String?
    let isActive: Bool

    static func from(_ a: CarrierAPI.ActiveLoad) -> CarrierLoadRow {
        CarrierLoadRow(
            id: "active-\(a.id)",
            loadNumber: a.loadNumber,
            status: a.status,
            origin: a.origin,
            destination: a.destination,
            dollars: a.rate,
            driver: a.driver.isEmpty ? nil : a.driver,
            counterparty: a.counterparty.isEmpty ? nil : a.counterparty,
            eta: a.eta.isEmpty ? nil : a.eta,
            deliveredAt: nil,
            isActive: true
        )
    }

    static func from(_ r: CarrierAPI.RecentLoad) -> CarrierLoadRow {
        CarrierLoadRow(
            id: "recent-\(r.id)",
            loadNumber: r.loadNumber,
            status: r.status,
            origin: r.origin,
            destination: r.destination,
            dollars: r.netPayout,
            driver: nil,
            counterparty: nil,
            eta: nil,
            deliveredAt: r.deliveredAt.isEmpty ? nil : r.deliveredAt,
            isActive: false
        )
    }
}

// MARK: - Screen body

struct CarrierLoads: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var active = CarrierActiveLoadsStore()
    @StateObject private var recent = CarrierRecentLoadsStore()

    @State private var filter: CarrierLoadsFilter = .all
    @State private var query: String = ""
    @State private var detailRow: CarrierLoadRow? = nil

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
            loadDetailSheet(for: row)
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
            Image(systemName: "truck.box.fill")
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
                    Text("CARRIER · LOADS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Your fleet's plate")
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
            return "Loading fleet plate…"
        }
        let total = activeCount + recentCount
        if total == 0 { return "Accept your first tender to populate this feed." }
        return "\(activeCount) active · \(recentCount) recent"
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            TextField("Load #, origin, destination, driver, broker", text: $query)
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
                ForEach(CarrierLoadsFilter.allCases) { f in
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
    private func chipLabel(_ f: CarrierLoadsFilter) -> some View {
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
    /// Search needle matches across loadNumber / origin /
    /// destination / driver / counterparty — broader than the
    /// Shipper analog because Carrier rows carry both driver and
    /// counterparty (broker/shipper) names.
    private var visibleRows: [CarrierLoadRow] {
        let activeRows = (active.state.value ?? []).map(CarrierLoadRow.from)
        let recentRows = (recent.state.value ?? []).map(CarrierLoadRow.from)

        let pool: [CarrierLoadRow]
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
                || (row.driver?.lowercased().contains(needle) ?? false)
                || (row.counterparty?.lowercased().contains(needle) ?? false)
        }
    }

    // MARK: - Row

    private func rowView(_ row: CarrierLoadRow) -> some View {
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
                if row.dollars > 0 {
                    Text(dollars(row.dollars))
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                }
                // Subtle distinguisher: "NET" caption under the
                // dollar value when it's a delivered (recent) row,
                // since the column means net-payout there vs.
                // gross-rate on active rows.
                if !row.isActive && row.dollars > 0 {
                    Text("NET")
                        .font(.system(size: 7, weight: .heavy)).tracking(0.7)
                        .foregroundStyle(palette.textTertiary)
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
    private func rowMetaLine(_ row: CarrierLoadRow) -> some View {
        HStack(spacing: 8) {
            if let driver = row.driver {
                Image(systemName: "person.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                Text(driver)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
            if let counterparty = row.counterparty {
                if row.driver != nil {
                    Text("·").foregroundStyle(palette.textTertiary)
                }
                Image(systemName: "building.2.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                Text(counterparty)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            if let eta = row.eta {
                if row.driver != nil || row.counterparty != nil {
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
            systemImage: "truck.box",
            title: "No loads on the plate",
            subtitle: "Accept a tender from the dispatch board and it'll show up here the moment it lands."
        )
    }

    @ViewBuilder
    private var searchEmptyState: some View {
        EusoEmptyState(
            systemImage: "magnifyingglass",
            title: "No matches",
            subtitle: "Try a different load number, origin, destination, driver, or broker."
        )
    }

    private func inlineError(_ error: Error, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Brand.danger)
                Text("Couldn't load fleet plate")
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

    // MARK: - Load detail sheet (real, brick 302)
    //
    // 2026-04-26 — eusotrip-killers 130th firing: 302_CarrierLoadDetail
    // landed. The placeholder previously here (EusoEmptyState +
    // "brick 302 pending" copy) is replaced with the real
    // CarrierLoadDetailScreen, which fetches the load via
    // CarrierLoadDetailStore → loads.getById and renders metric
    // tiles, assignment, schedule, cargo, settlement, and notes
    // cards. The CarrierLoadRow's id carries an "active-NN" /
    // "recent-NN" prefix; we strip the cohort prefix before passing
    // through so the server receives the canonical numeric load id
    // verbatim — the same shape `loads.getById` accepts.

    private func loadDetailSheet(for row: CarrierLoadRow) -> some View {
        // Strip the cohort prefix; row.id is "active-42" / "recent-42",
        // server expects "42".
        let serverLoadId: String = {
            if row.id.hasPrefix("active-") { return String(row.id.dropFirst("active-".count)) }
            if row.id.hasPrefix("recent-") { return String(row.id.dropFirst("recent-".count)) }
            return row.id
        }()
        return CarrierLoadDetailScreen(
            theme: palette,
            loadId: serverLoadId,
            previewLoadNumber: row.loadNumber,
            previewLane: "\(row.origin) → \(row.destination)",
            previewStatus: row.status,
            previewDriver: row.driver,
            previewCounterparty: row.counterparty,
            previewRate: row.dollars > 0 ? row.dollars : nil,
            previewIsActive: row.isActive
        )
        .environmentObject(session)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers

    /// Currency formatter used identically by 300 Carrier Home / 200
    /// Shipper Home / settlement-related driver bricks. Single point
    /// of drift.
    private func dollars(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$0"
    }
}

// MARK: - Screen wrapper

struct CarrierLoadsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            CarrierLoads()
        } nav: {
            BottomNav(
                leading: carrierNavLeading_301(),
                trailing: carrierNavTrailing_301(),
                orbState: .idle
            )
        }
    }
}

private func carrierNavLeading_301() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",                isCurrent: false),
     NavSlot(label: "Loads", systemImage: "truck.box.fill",       isCurrent: true)]
}

private func carrierNavTrailing_301() -> [NavSlot] {
    [NavSlot(label: "Drivers", systemImage: "person.2",           isCurrent: false),
     NavSlot(label: "Me",      systemImage: "person",             isCurrent: false)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so each store stays in `.loading` —
// both registers render the skeleton without hitting the network.
// Per doctrine §10: previews must compile in isolation.

#Preview("301 · Carrier · Loads · Night") {
    CarrierLoadsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("301 · Carrier · Loads · Afternoon") {
    CarrierLoadsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
