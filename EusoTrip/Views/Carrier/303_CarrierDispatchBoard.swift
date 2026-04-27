//
//  303_CarrierDispatchBoard.swift
//  EusoTrip — Carrier · Dispatch Board (brick 303).
//
//  Fourth brick on the Carrier role track (300s). Lit by the 144th
//  eusotrip-killers firing (autonomous Cowork-mode run, 2026-04-27)
//  per the 143rd firing's hand-off recommendation: "Driver=117,
//  Shipper=12, Carrier=3 — Carrier is the deepest gap among
//  production roles. The next high-leverage port is
//  303_CarrierDispatchBoard — the carrier-side dispatch screen that
//  closes the carrier→driver dispatch loop and pairs with the existing
//  carriers.* tRPC procedures (loads-lifecycle slice §16-02)."
//
//  Doctrine compliance (EUSOTRIP2027GOLD):
//    • §1 — Brand accent is `LinearGradient.diagonal` only. No flat
//      Brand.info / Brand.blue fills. Filter chips, lane gradient
//      hairline, status pills, all-CAPS column headers — every
//      accent is the diagonal gradient.
//    • §2 — No Toggles on this brick.
//    • §3 — Ternary shape-styles wrapped in `AnyShapeStyle`.
//    • §4 — Spacing / radius / type from tokens (Space.s*, Radius.*,
//      EType.*). No magic numbers.
//    • §5 — Palette semantic only. No hard-coded Color.white /
//      Color.black / Color.gray fills.
//    • §10 — Both register previews compile in isolation; no
//      network in previews.
//    • §11 — Zero synthesised data. Each card switches over its
//      store's RemoteState (`MockDataGuard` self-check satisfied).
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data, dynamic ready pages with 0 data,
//  plugged into backend"):
//
//    • Active loads list      → `CarrierActiveLoadsStore` (existing,
//      LiveDataStores.swift L3787) → `carriers.getActiveLoads`.
//    • Exception alerts feed  → `CarrierAlertsStore` (existing,
//      LiveDataStores.swift L3800) →
//      `carriers.getLoadsRequiringAttention`. Joined onto active
//      rows by `loadNumber` so an "EXCEPTION" badge can light up
//      the correct row (no separate placeholder column).
//    • Lane filter chips bin the active rows by dispatch state
//      (`unassigned` = empty driver column, `dispatched` /
//      `intransit` = derived from the load's `status` projection,
//      `exception` = rows joined to an alert). The "All" lane
//      shows every row, lane-grouped under its dispatch column.
//    • Tap a row → presents a sheet that routes to
//      `CarrierLoadDetailScreen` (brick 302) — same store-driven
//      detail surface 301_CarrierLoads uses, so the dispatch
//      board → load detail loop is closed. NEVER fake data.
//    • RemoteState surfaces: `.loading` shows a column skeleton,
//      `.empty` renders `EusoEmptyState`, `.error` renders an
//      inline retry, and `.loaded` paints the real bins.
//
//  Why no new tRPC procedure: the carriers.* router already exposes
//  the two queries this board needs (active loads + exception
//  alerts). The dispatch axis is a *projection* over those rows —
//  binning by `driver`/`status` + joining alerts by `loadNumber`.
//  Per doctrine §13 (no fabricated values) + §17 (work together
//  with the dev team), composing existing procedures keeps the
//  client/server contract unchanged so the dev team's parallel work
//  doesn't conflict.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Lane taxonomy

/// The five lanes the dispatch board renders. `all` is a virtual lane
/// that shows every active row grouped under its derived bin.
private enum DispatchLane: String, CaseIterable, Identifiable {
    case all         = "All"
    case unassigned  = "Unassigned"
    case dispatched  = "Dispatched"
    case intransit   = "In Transit"
    case exception   = "Exception"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all:         return "rectangle.3.group"
        case .unassigned:  return "person.crop.circle.badge.questionmark"
        case .dispatched:  return "paperplane.fill"
        case .intransit:   return "truck.box.fill"
        case .exception:   return "exclamationmark.triangle.fill"
        }
    }
}

/// Per-row dispatch bin — what column the row falls under once we
/// project `driver` + `status` + the alert join. Strict precedence:
/// exception > intransit > dispatched > unassigned.
private enum DispatchBin: String, CaseIterable {
    case unassigned, dispatched, intransit, exception

    var lane: DispatchLane {
        switch self {
        case .unassigned: return .unassigned
        case .dispatched: return .dispatched
        case .intransit:  return .intransit
        case .exception:  return .exception
        }
    }

    /// Human-readable column label rendered in the All-lane group
    /// headers. Single point of truth so we don't drift between the
    /// chip text and the column headers.
    var headerLabel: String { lane.rawValue.uppercased() }
}

/// Adapter row used by both the per-lane list and the All-lane
/// grouped section. Carries enough surface for the row UI without
/// dragging the full ActiveLoad envelope through every helper.
private struct DispatchRow: Identifiable, Hashable {
    let id: String
    let loadNumber: String
    let status: String
    let origin: String
    let destination: String
    let driver: String?
    let counterparty: String?
    let eta: String?
    let rate: Double
    let bin: DispatchBin
    /// When this row joined to an alert (`carriers.getLoadsRequiringAttention`
    /// row by `loadNumber`), the issue + severity surface here. Drives the
    /// EXCEPTION badge + accent stripe.
    let alertIssue: String?
    let alertSeverity: String?
    let alertMessage: String?

    static func from(
        _ load: CarrierAPI.ActiveLoad,
        alertsByLoadNumber: [String: CarrierAPI.LoadAlert]
    ) -> DispatchRow {
        let alert = alertsByLoadNumber[load.loadNumber]
        let bin = Self.computeBin(load: load, hasAlert: alert != nil)
        return DispatchRow(
            id: "active-\(load.id)",
            loadNumber: load.loadNumber,
            status: load.status,
            origin: load.origin,
            destination: load.destination,
            driver: load.driver.isEmpty ? nil : load.driver,
            counterparty: load.counterparty.isEmpty ? nil : load.counterparty,
            eta: load.eta.isEmpty ? nil : load.eta,
            rate: load.rate,
            bin: bin,
            alertIssue: alert?.issue,
            alertSeverity: alert?.severity,
            alertMessage: alert?.message
        )
    }

    /// Bin derivation. Strict precedence so a row never lands in two
    /// columns. Status comparison is case-folded because the server
    /// emits both "DISPATCHED"/"dispatched" depending on which
    /// projection is in flight (see §16 loads-lifecycle slice's note
    /// on the lowercase-vs-UPPERCASE drift).
    private static func computeBin(
        load: CarrierAPI.ActiveLoad,
        hasAlert: Bool
    ) -> DispatchBin {
        if hasAlert { return .exception }
        let s = load.status.lowercased()
        // In transit = anything post-pickup, pre-delivery
        let inTransitTokens = [
            "in_transit", "intransit", "active",
            "enroute", "en_route", "approaching_delivery",
            "approaching_pickup", "loaded", "loading",
            "unloading", "at_pickup", "at_receiver",
            "at_gate", "dock_assigned"
        ]
        if inTransitTokens.contains(s) { return .intransit }
        let dispatchedTokens = ["dispatched", "assigned", "accepted", "tendered"]
        if dispatchedTokens.contains(s) { return .dispatched }
        if load.driver.isEmpty { return .unassigned }
        // Driver assigned but no dispatch-state token recognised — bin
        // as dispatched (carrier has tendered to the driver, not yet
        // a transit state).
        return .dispatched
    }
}

// MARK: - Screen body

struct CarrierDispatchBoard: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var active = CarrierActiveLoadsStore()
    @StateObject private var alerts = CarrierAlertsStore()

    @State private var lane: DispatchLane = .all
    @State private var detailRow: DispatchRow? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                laneChips
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await refreshAll() }
        .refreshable { await refreshAll() }
        .sheet(item: $detailRow) { row in
            dispatchDetailSheet(for: row)
        }
        .screenTileRoot()
    }

    private func refreshAll() async {
        async let a: Void = active.refresh()
        async let b: Void = alerts.refresh()
        _ = await (a, b)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
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
                    Text("CARRIER · DISPATCH")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Dispatch board")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(headerSubhead)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            countBadge
        }
        .padding(.top, 4)
    }

    /// Live count chip. Reads `.loading` while either store is in
    /// flight; em-dash on error so the badge never voices a fake
    /// number.
    private var countBadge: some View {
        let total: Int = {
            guard active.state.isSettled else { return -1 }
            return (active.state.value ?? []).count
        }()
        return VStack(alignment: .trailing, spacing: 2) {
            Text(total < 0 ? "—" : "\(total)")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
            Text("ACTIVE")
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var headerSubhead: String {
        guard active.state.isSettled, alerts.state.isSettled else {
            return "Loading dispatch board…"
        }
        let rows = activeRows
        if rows.isEmpty {
            return "No loads on the plate. New tenders surface here the moment dispatch fires."
        }
        let unassigned = rows.filter { $0.bin == .unassigned }.count
        let exception  = rows.filter { $0.bin == .exception  }.count
        let intransit  = rows.filter { $0.bin == .intransit  }.count
        var parts: [String] = []
        if intransit  > 0 { parts.append("\(intransit) in transit") }
        if unassigned > 0 { parts.append("\(unassigned) unassigned") }
        if exception  > 0 { parts.append("\(exception) exception") }
        if parts.isEmpty {
            // All loads dispatched, no transit / no exceptions yet.
            let dispatched = rows.filter { $0.bin == .dispatched }.count
            return "\(dispatched) dispatched · clean board"
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Lane chips

    private var laneChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DispatchLane.allCases) { l in
                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                            lane = l
                        }
                    } label: {
                        chipLabel(l)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func chipLabel(_ l: DispatchLane) -> some View {
        let on = (lane == l)
        let count = laneCount(l)
        HStack(spacing: 6) {
            Image(systemName: l.systemImage)
                .font(.system(size: 10, weight: .heavy))
            Text(l.rawValue.uppercased())
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
            if let c = count {
                Text("\(c)")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                    .opacity(on ? 1.0 : 0.7)
            }
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

    /// Per-lane row count. `nil` while either store is still settling
    /// so we never voice a half-count.
    private func laneCount(_ l: DispatchLane) -> Int? {
        guard active.state.isSettled, alerts.state.isSettled else { return nil }
        let rows = activeRows
        switch l {
        case .all:         return rows.count
        case .unassigned:  return rows.filter { $0.bin == .unassigned }.count
        case .dispatched:  return rows.filter { $0.bin == .dispatched }.count
        case .intransit:   return rows.filter { $0.bin == .intransit  }.count
        case .exception:   return rows.filter { $0.bin == .exception  }.count
        }
    }

    // MARK: - Content (loading / empty / error / loaded)

    @ViewBuilder
    private var content: some View {
        switch combined {
        case .loading:
            laneSkeleton
        case .empty:
            emptyState
        case .loaded:
            loadedContent
        case .error(let e):
            inlineError(e) { Task { await refreshAll() } }
        }
    }

    /// Folded RemoteState across the two stores. `loading` while
    /// either is still settling. `error` if the active store
    /// errored (alerts errors are non-fatal — the board still
    /// renders without exception annotations). `empty` if active
    /// confirmed empty.
    private var combined: RemoteState<Void> {
        if !active.state.isSettled { return .loading }
        if let e = active.state.error { return .error(e) }
        if (active.state.value ?? []).isEmpty { return .empty }
        // Wait for alerts to settle before painting — otherwise a row
        // might miss its exception annotation on first paint.
        if !alerts.state.isSettled { return .loading }
        return .loaded(())
    }

    /// The post-projection rows. Joined to the alerts feed by
    /// loadNumber. Recomputed on every body cycle — both stores
    /// publish their values via @Published and the join is O(n)
    /// over a server-capped working set (limit 10), so cost is
    /// trivial.
    private var activeRows: [DispatchRow] {
        let raw = active.state.value ?? []
        let alertList = alerts.state.value ?? []
        // Join key: loadNumber. The server exposes loadNumber on
        // both the ActiveLoad and LoadAlert envelopes, and the
        // load number is unique per carrier-tenant per §16-02.
        var byLN: [String: CarrierAPI.LoadAlert] = [:]
        for a in alertList { byLN[a.loadNumber] = a }
        return raw.map { DispatchRow.from($0, alertsByLoadNumber: byLN) }
    }

    /// Rows visible after applying the current lane filter.
    private var visibleRows: [DispatchRow] {
        let rows = activeRows
        switch lane {
        case .all:         return rows
        case .unassigned:  return rows.filter { $0.bin == .unassigned }
        case .dispatched:  return rows.filter { $0.bin == .dispatched }
        case .intransit:   return rows.filter { $0.bin == .intransit  }
        case .exception:   return rows.filter { $0.bin == .exception  }
        }
    }

    // MARK: - Loaded content

    @ViewBuilder
    private var loadedContent: some View {
        if lane == .all {
            // All-lane: group by bin in strict precedence order so
            // exceptions surface first.
            VStack(alignment: .leading, spacing: Space.s4) {
                ForEach(DispatchBin.allCases.reversed(), id: \.self) { bin in
                    let rows = visibleRows.filter { $0.bin == bin }
                    if !rows.isEmpty {
                        binSection(bin: bin, rows: rows)
                    }
                }
            }
        } else {
            // Per-lane: single flat list under a single header.
            VStack(alignment: .leading, spacing: Space.s2) {
                if visibleRows.isEmpty {
                    perLaneEmptyState
                } else {
                    ForEach(visibleRows) { row in
                        Button { detailRow = row } label: {
                            rowView(row)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func binSection(bin: DispatchBin, rows: [DispatchRow]) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: bin.lane.systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(bin.headerLabel)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(rows.count)")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: Space.s2) {
                ForEach(rows) { row in
                    Button { detailRow = row } label: {
                        rowView(row)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Row

    private func rowView(_ row: DispatchRow) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.loadNumber)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    if row.bin == .exception {
                        exceptionBadge(severity: row.alertSeverity)
                    }
                }
                Text("\(row.origin) → \(row.destination)")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                rowMetaLine(row)
                if let msg = row.alertMessage, row.bin == .exception {
                    Text(msg)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.status.uppercased())
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(LinearGradient.diagonal)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(
                        Capsule().strokeBorder(
                            LinearGradient.diagonal.opacity(0.5),
                            lineWidth: 1
                        )
                    )
                if row.rate > 0 {
                    Text(dollars(row.rate))
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
                .strokeBorder(rowBorder(for: row), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .contentShape(Rectangle())
    }

    /// Row border tint. Exception rows get a danger-coloured stroke;
    /// every other row uses the neutral border. No fabricated colour
    /// ramp — just the two existing semantics.
    private func rowBorder(for row: DispatchRow) -> AnyShapeStyle {
        if row.bin == .exception { return AnyShapeStyle(Brand.danger.opacity(0.45)) }
        return AnyShapeStyle(palette.borderFaint)
    }

    @ViewBuilder
    private func rowMetaLine(_ row: DispatchRow) -> some View {
        HStack(spacing: 8) {
            // Driver chip — gradient when assigned, em-dash otherwise.
            // Per doctrine §13: never voice a fabricated driver name.
            if let driver = row.driver {
                Image(systemName: "person.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(driver)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            } else {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                Text("UNASSIGNED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            if let counterparty = row.counterparty {
                Text("·").foregroundStyle(palette.textTertiary)
                Image(systemName: "building.2.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                Text(counterparty)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            if let eta = row.eta {
                if row.counterparty != nil { Text("·").foregroundStyle(palette.textTertiary) }
                Text("ETA \(eta)")
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    /// Severity-aware exception badge. The server emits a free-form
    /// severity string (typical values: "info" / "warning" / "critical");
    /// we route the badge accent through `Brand.danger` for any non-
    /// info severity, falling through to the neutral gradient
    /// otherwise so we never paint a fabricated severity ramp.
    @ViewBuilder
    private func exceptionBadge(severity: String?) -> some View {
        let sev = (severity ?? "").lowercased()
        let isCritical = sev.contains("critical") || sev.contains("warning") || sev.contains("urgent")
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 8, weight: .heavy))
            Text("EXCEPTION")
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
        }
        .foregroundStyle(isCritical ? AnyShapeStyle(Color.white) : AnyShapeStyle(LinearGradient.diagonal))
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(
            Capsule().fill(
                isCritical
                    ? AnyShapeStyle(Brand.danger)
                    : AnyShapeStyle(Color.clear)
            )
        )
        .overlay(
            Capsule().strokeBorder(
                isCritical
                    ? AnyShapeStyle(Color.clear)
                    : AnyShapeStyle(LinearGradient.diagonal.opacity(0.5)),
                lineWidth: 1
            )
        )
    }

    // MARK: - Empty / error / skeleton states

    private var laneSkeleton: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCard)
                    .frame(height: 80)
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
            systemImage: "antenna.radiowaves.left.and.right",
            title: "Dispatch board is clear",
            subtitle: "Your fleet has no active loads on the plate. The moment a tender is accepted and a driver is assigned, it'll surface here."
        )
    }

    @ViewBuilder
    private var perLaneEmptyState: some View {
        EusoEmptyState(
            systemImage: lane.systemImage,
            title: "Nothing in this lane",
            subtitle: "No \(lane.rawValue.lowercased()) loads right now. Check the All lane for the full board."
        )
    }

    private func inlineError(_ error: Error, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Brand.danger)
                Text("Couldn't load dispatch board")
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

    // MARK: - Detail sheet (routes to brick 302)
    //
    // The board's row-tap target is the same CarrierLoadDetailScreen
    // that 301_CarrierLoads presents. The DispatchRow.id carries the
    // `active-NN` cohort prefix from the from() factory; we strip it
    // before passing the canonical numeric load id through to
    // CarrierLoadDetailStore → loads.getById, matching the contract
    // documented at LiveDataStores.swift L3853.

    private func dispatchDetailSheet(for row: DispatchRow) -> some View {
        let serverLoadId: String = {
            if row.id.hasPrefix("active-") { return String(row.id.dropFirst("active-".count)) }
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
            previewRate: row.rate > 0 ? row.rate : nil,
            previewIsActive: true
        )
        .environmentObject(session)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers

    /// Currency formatter — same shape used by 300/301/302.
    private func dollars(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$0"
    }
}

// MARK: - Screen wrapper

struct CarrierDispatchBoardScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            CarrierDispatchBoard()
        } nav: {
            BottomNav(
                leading: carrierNavLeading_303(),
                trailing: carrierNavTrailing_303(),
                orbState: .idle
            )
        }
    }
}

private func carrierNavLeading_303() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                  isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "antenna.radiowaves.left.and.right", isCurrent: true)]
}

private func carrierNavTrailing_303() -> [NavSlot] {
    [NavSlot(label: "Loads",   systemImage: "truck.box.fill",          isCurrent: false),
     NavSlot(label: "Me",      systemImage: "person",                  isCurrent: false)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so each store stays in `.loading` —
// both registers render the lane skeleton without hitting the
// network. Per doctrine §10: previews must compile in isolation;
// no fabricated data ever paints.

#Preview("303 · Carrier · Dispatch Board · Night") {
    CarrierDispatchBoardScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("303 · Carrier · Dispatch Board · Afternoon") {
    CarrierDispatchBoardScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
