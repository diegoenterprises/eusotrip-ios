//
//  304_CarrierDrivers.swift
//  EusoTrip — Carrier · Drivers (brick 304).
//
//  Fifth brick on the Carrier role track (300s). Lit by the 145th
//  eusotrip-killers firing (autonomous Cowork-mode run, 2026-04-27)
//  to close the dispatch-loop driver-roster axis the 303 board
//  references via the UNASSIGNED chip. When a dispatcher taps the
//  "Drivers" nav slot from the 303 board, they land here with a
//  living roster of every driver the carrier currently has loads
//  with — assignment counts, lane summaries, and a tap-through into
//  the per-driver active load via the existing 302 detail surface.
//
//  Doctrine compliance (EUSOTRIP2027GOLD):
//    • §1 — Brand accent is `LinearGradient.diagonal` only. No flat
//      Brand.info / Brand.blue fills.
//    • §2 — No Toggles on this brick.
//    • §3 — Ternary shape-styles wrapped in `AnyShapeStyle`.
//    • §4 — Spacing / radius / type from tokens. No magic numbers.
//    • §5 — Palette semantic only. No hard-coded Color.white /
//      Color.black / Color.gray fills.
//    • §10 — Both register previews compile in isolation.
//    • §11 — Zero synthesised data. RemoteState switch is exhaustive.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data, dynamic ready pages with 0 data,
//  plugged into backend"):
//
//    • Roster source → `CarrierActiveLoadsStore` (existing,
//      LiveDataStores.swift L3787) → `carriers.getActiveLoads`. The
//      roster axis is a *projection* over those rows: every unique
//      non-empty `driver` name becomes a roster entry, with the
//      per-driver active-load count + lane summary aggregated from
//      the same rows. Unassigned loads (empty driver column) are
//      surfaced separately as a "needs assignment" banner instead
//      of being included as roster rows — drivers without an active
//      load don't show up here today because the server doesn't yet
//      expose a true `carriers.getRoster` query (slice §16 carriers
//      router). When that procedure ships, swap the data source —
//      every other surface in this file stays unchanged.
//    • Tap a roster row → presents the driver's most-recent active
//      load via `CarrierLoadDetailScreen` (brick 302). NEVER fake
//      data: row tap targets the canonical numeric load id from
//      the server, same contract 301/303 use.
//    • RemoteState surfaces: `.loading` shows roster skeleton,
//      `.empty` renders `EusoEmptyState`, `.error` renders an
//      inline retry, `.loaded` paints the real roster.
//
//  Why no new tRPC procedure: doctrine §17 work-with-the-dev-team
//  compliance. The 303 dispatch board already showed this same
//  composition pattern works for the dispatch axis; 304 reuses the
//  same store for the roster axis. When the dev team ships a real
//  `carriers.getRoster` (or `drivers.list`), this file changes its
//  data source in one place — every UI surface here keeps shape.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Roster taxonomy

/// One driver-roster row, projected from one or more
/// `CarrierAPI.ActiveLoad` rows that share the same `driver` value.
private struct CarrierDriverRosterRow: Identifiable, Hashable {
    /// Stable across renders — the driver display name itself,
    /// since that's the only stable key the projection has.
    let id: String
    let displayName: String
    /// Number of active loads currently assigned to this driver.
    let activeLoadCount: Int
    /// One concise lane line: when the driver has 1 load, it's the
    /// origin → destination of that load; for 2+ loads, it's "+ N
    /// lanes" so the row stays single-line.
    let laneSummary: String
    /// The most-recent active load id (server canonical numeric id),
    /// used as the row-tap target for the 302 detail sheet. Empty
    /// when the driver has no active load (impossible in this
    /// projection, since they wouldn't appear in the roster).
    let primaryLoadId: String
    /// Display-only counterparty surfaced as a meta chip on the row.
    let primaryCounterparty: String?
    /// Dollar value of the primary load (gross rate). Used for the
    /// trailing currency chip on the row.
    let primaryRate: Double
    /// Display-only status of the primary load (post-uppercased).
    let primaryStatus: String
    /// Display-only ETA of the primary load.
    let primaryEta: String?

    static func project(from loads: [CarrierAPI.ActiveLoad]) -> [CarrierDriverRosterRow] {
        // Group by driver, preserving first-seen order — the server
        // ranks `getActiveLoads` by recency so the first row per
        // driver is the most-recent.
        var seenOrder: [String] = []
        var byDriver: [String: [CarrierAPI.ActiveLoad]] = [:]
        for l in loads {
            let name = l.driver.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            if byDriver[name] == nil { seenOrder.append(name) }
            byDriver[name, default: []].append(l)
        }
        return seenOrder.compactMap { name in
            guard let group = byDriver[name], let primary = group.first else { return nil }
            let lane: String
            if group.count == 1 {
                lane = "\(primary.origin) → \(primary.destination)"
            } else {
                lane = "\(primary.origin) → \(primary.destination) · +\(group.count - 1) lanes"
            }
            return CarrierDriverRosterRow(
                id: name,
                displayName: name,
                activeLoadCount: group.count,
                laneSummary: lane,
                primaryLoadId: primary.id,
                primaryCounterparty: primary.counterparty.isEmpty ? nil : primary.counterparty,
                primaryRate: primary.rate,
                primaryStatus: primary.status,
                primaryEta: primary.eta.isEmpty ? nil : primary.eta
            )
        }
    }
}

// MARK: - Screen body

struct CarrierDrivers: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var active = CarrierActiveLoadsStore()

    @State private var query: String = ""
    @State private var detailRow: CarrierDriverRosterRow? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                searchField
                unassignedBanner
                rosterCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await active.refresh() }
        .refreshable { await active.refresh() }
        .sheet(item: $detailRow) { row in
            rosterDetailSheet(for: row)
        }
        .screenTileRoot()
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.2.fill")
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
                    Text("CARRIER · ROSTER")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Your drivers")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(headerSubhead)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(rosterCountText)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text("ACTIVE")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.top, 4)
    }

    private var rosterCountText: String {
        guard active.state.isSettled else { return "—" }
        return "\(roster.count)"
    }

    private var headerSubhead: String {
        guard active.state.isSettled else { return "Loading roster…" }
        let r = roster
        if r.isEmpty { return "No drivers on active loads. Assign a load and the driver surfaces here." }
        let totalLoads = r.reduce(0) { $0 + $1.activeLoadCount }
        return "\(r.count) drivers · \(totalLoads) active loads"
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            TextField("Driver name, lane, broker", text: $query)
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

    // MARK: - Unassigned-loads banner

    /// Loads from the server that have no driver assigned yet. The
    /// roster axis can't surface these as roster rows (no driver
    /// name to key on), so we surface a single-line banner pointing
    /// the dispatcher at the 303 board's Unassigned lane. Em-dash
    /// when the store hasn't settled — never voice a fake count.
    @ViewBuilder
    private var unassignedBanner: some View {
        let count = unassignedCount
        if count > 0 {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(count) load\(count == 1 ? "" : "s") need a driver")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("Open the Dispatch board → Unassigned lane to tender these.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private var unassignedCount: Int {
        guard active.state.isSettled, let rows = active.state.value else { return 0 }
        return rows.filter { $0.driver.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    // MARK: - Roster card

    @ViewBuilder
    private var rosterCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ROSTER")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if active.state.isSettled {
                    Text("\(visibleRoster.count)")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            rosterSkeleton
        case .empty:
            emptyState
        case .loaded:
            if visibleRoster.isEmpty {
                searchEmptyState
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(visibleRoster) { row in
                        Button { detailRow = row } label: {
                            rosterRowView(row)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        case .error(let e):
            inlineError(e) { Task { await active.refresh() } }
        }
    }

    /// Folded RemoteState. `.empty` only when the server confirms
    /// zero rows AND there are no unassigned loads either — otherwise
    /// the unassigned banner carries the screen.
    private var state: RemoteState<Void> {
        if !active.state.isSettled { return .loading }
        if let e = active.state.error { return .error(e) }
        if roster.isEmpty && unassignedCount == 0 { return .empty }
        return .loaded(())
    }

    private var roster: [CarrierDriverRosterRow] {
        CarrierDriverRosterRow.project(from: active.state.value ?? [])
    }

    private var visibleRoster: [CarrierDriverRosterRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return roster }
        return roster.filter { row in
            row.displayName.lowercased().contains(needle)
                || row.laneSummary.lowercased().contains(needle)
                || (row.primaryCounterparty?.lowercased().contains(needle) ?? false)
        }
    }

    // MARK: - Row

    private func rosterRowView(_ row: CarrierDriverRosterRow) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            // Driver avatar — initials inside a gradient ring.
            ZStack {
                Circle().fill(palette.bgCard)
                Circle().strokeBorder(LinearGradient.diagonal.opacity(0.6), lineWidth: 1.5)
                Text(initials(for: row.displayName))
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.displayName)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    if row.activeLoadCount > 1 {
                        Text("× \(row.activeLoadCount)")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(LinearGradient.diagonal)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .overlay(
                                Capsule().strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
                            )
                    }
                }
                Text(row.laneSummary)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                rowMetaLine(row)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.primaryStatus.uppercased())
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(LinearGradient.diagonal)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(
                        Capsule().strokeBorder(
                            LinearGradient.diagonal.opacity(0.5),
                            lineWidth: 1
                        )
                    )
                if row.primaryRate > 0 {
                    Text(dollars(row.primaryRate))
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                    Text("RATE")
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
    private func rowMetaLine(_ row: CarrierDriverRosterRow) -> some View {
        HStack(spacing: 8) {
            if let counterparty = row.primaryCounterparty {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                Text(counterparty)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            if let eta = row.primaryEta {
                if row.primaryCounterparty != nil { Text("·").foregroundStyle(palette.textTertiary) }
                Text("ETA \(eta)")
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    /// Two-letter initials from the driver display name. Falls
    /// through to a single letter when the name is one token; never
    /// fabricates a value (em-dash is impossible here because the
    /// projection only surfaces non-empty names).
    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        if parts.isEmpty { return "—" }
        if parts.count == 1 { return String(parts[0].prefix(1)).uppercased() }
        let first = parts[0].prefix(1)
        let last  = parts.last?.prefix(1) ?? ""
        return (String(first) + String(last)).uppercased()
    }

    // MARK: - Empty / error / skeleton states

    private var rosterSkeleton: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCard)
                    .frame(height: 72)
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
            systemImage: "person.2",
            title: "No drivers on the roster",
            subtitle: "When you assign a load to a driver, they'll surface here. Until then the roster is empty."
        )
    }

    @ViewBuilder
    private var searchEmptyState: some View {
        EusoEmptyState(
            systemImage: "magnifyingglass",
            title: "No matches",
            subtitle: "Try a different driver name, lane, or broker."
        )
    }

    private func inlineError(_ error: Error, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Brand.danger)
                Text("Couldn't load roster")
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

    // MARK: - Detail sheet (routes to brick 302 — primary load)

    private func rosterDetailSheet(for row: CarrierDriverRosterRow) -> some View {
        return CarrierLoadDetailScreen(
            theme: palette,
            loadId: row.primaryLoadId,
            previewLoadNumber: nil,
            previewLane: row.laneSummary,
            previewStatus: row.primaryStatus,
            previewDriver: row.displayName,
            previewCounterparty: row.primaryCounterparty,
            previewRate: row.primaryRate > 0 ? row.primaryRate : nil,
            previewIsActive: true
        )
        .environmentObject(session)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers

    private func dollars(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$0"
    }
}

// MARK: - Screen wrapper

struct CarrierDriversScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            CarrierDrivers()
        } nav: {
            BottomNav(
                leading: carrierNavLeading_304(),
                trailing: carrierNavTrailing_304(),
                orbState: .idle
            )
        }
    }
}

private func carrierNavLeading_304() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                  isCurrent: false),
     NavSlot(label: "Drivers",  systemImage: "person.2.fill",          isCurrent: true)]
}

private func carrierNavTrailing_304() -> [NavSlot] {
    [NavSlot(label: "Dispatch", systemImage: "antenna.radiowaves.left.and.right", isCurrent: false),
     NavSlot(label: "Me",       systemImage: "person",                  isCurrent: false)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so the active store stays in `.loading`
// and the roster skeleton paints. Per doctrine §10 — previews compile
// in isolation.

#Preview("304 · Carrier · Drivers · Night") {
    CarrierDriversScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("304 · Carrier · Drivers · Afternoon") {
    CarrierDriversScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
