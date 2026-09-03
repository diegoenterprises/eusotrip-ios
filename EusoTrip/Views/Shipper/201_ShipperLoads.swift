//
//  201_ShipperLoads.swift
//  EusoTrip — Shipper · Movement Register (201).
//
//  Purpose: let a shipper scan every movement, understand its exact
//  lifecycle and commercial state, and open the record needing attention.
//  `shippers.getMyLoads` remains row authority; the summary endpoint owns
//  counts. Missing mode, unit, currency, or lifecycle data stays unknown.
//

import SwiftUI
import UIKit

// MARK: - Poster identity media

/// Resolves the posting party's server-projected identity media without
/// changing the wire value. Company branding is authoritative when present;
/// the user's profile image is the secondary source. Only HTTPS is accepted
/// for remote media, while persisted `data:image/...;base64` values are
/// decoded locally.
private enum ShipperPosterImageResolver {
    static func resolve(
        companyLogo: String?,
        profilePicture: String?
    ) -> (image: UIImage?, remoteURL: URL?) {
        for candidate in [companyLogo, profilePicture] {
            guard let raw = candidate?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty
            else { continue }

            if raw.hasPrefix("data:"),
               let comma = raw.firstIndex(of: ","),
               let data = Data(
                   base64Encoded: String(raw[raw.index(after: comma)...]),
                   options: .ignoreUnknownCharacters
               ),
               let image = UIImage(data: data)
            {
                return (image, nil)
            }

            if let data = Data(base64Encoded: raw, options: .ignoreUnknownCharacters),
               let image = UIImage(data: data)
            {
                return (image, nil)
            }

            if let url = URL(string: raw), url.scheme?.lowercased() == "https" {
                return (nil, url)
            }
        }
        return (nil, nil)
    }
}

// MARK: - Filter taxonomy (matches wireframe 5-chip row)

private enum ShipperLoadsFilter: String, CaseIterable, Identifiable {
    case all        = "All"
    case bidding    = "Bidding"
    case awarded    = "Awarded"
    case inTransit  = "In transit"
    case delivered  = "Delivered"

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .all:       return "All"
        case .bidding:   return "Bidding"
        case .awarded:   return "Awarded"
        case .inTransit: return "In transit"
        case .delivered: return "Delivered"
        }
    }

    /// Map filter → set of server-side status values it includes.
    var statusSet: Set<String> {
        switch self {
        case .all:        return []
        case .bidding:    return ["posted", "bidding"]
        case .awarded:    return ["awarded", "assigned"]
        case .inTransit:  return ["in_transit", "in transit", "loading", "pickup", "delivery", "delivering"]
        case .delivered:  return ["delivered", "closed", "paid", "complete", "completed"]
        }
    }

    /// Pull the correct count out of the loads.getShipperSummary envelope.
    /// "All" must report `totalLoads` so the chip number matches the
    /// topline counter ("65 TOTAL · 12 ACTIVE") and the visible row count
    /// when no filter is applied. Showing `activeLoads` here was the
    /// bug behind "65 total / All 50 / no rows" — the chip looked like
    /// the page was filtered even when it wasn't.
    func count(in s: LoadsAPI.ShipperSummary?) -> Int? {
        guard let s else { return nil }
        switch self {
        case .all:        return s.totalLoads
        case .bidding:    return s.pending
        case .awarded:    return max(0, s.activeLoads - s.inTransit - s.pending)
        case .inTransit:  return s.inTransit
        case .delivered:  return s.delivered
        }
    }
}

// MARK: - Adapter row

private struct ShipperLoadRow: Identifiable, Hashable {
    let id: String
    let serverLoadId: String
    let loadNumber: String
    let status: String
    let lane: String
    let origin: String
    let destination: String
    let productName: String
    let cargoType: String
    let weightDisplay: String
    let isHazmatDeclared: Bool
    let hazmatClass: String?
    let amount: Double?
    let currency: String?
    let rateUnit: String?
    let worldscalePct: String?
    let lifecycleStage: Int  // 1...8
    let createdAt: String?
    let pickupDate: String
    // 2026-05-17 — multi-modal payload mirrored from MyLoad.
    let transportMode: String?
    let multiVehicleCount: Int?
    let posterName: String?
    let posterCompanyName: String?
    let posterCompanyLogo: String?
    let posterProfilePicture: String?

    private static func stripLoadPrefix(_ raw: String) -> String {
        raw.hasPrefix("load_") ? String(raw.dropFirst("load_".count)) : raw
    }

    private static func stage(for status: String) -> Int {
        switch status.lowercased() {
        case "posted":              return 1
        case "bidding":             return 2
        case "awarded", "assigned": return 3
        case "pickup":              return 4
        case "in_transit", "in transit", "loading": return 5
        case "delivery", "delivering": return 6
        case "paperwork":           return 7
        case "closed", "delivered", "paid", "complete", "completed": return 8
        case "cancelled", "canceled", "expired", "rejected": return 0
        default:                    return 0
        }
    }

    var mode: TransportMode? {
        guard let raw = transportMode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !raw.isEmpty
        else { return nil }
        return TransportMode(rawValue: raw)
    }

    var modeLabel: String { mode?.displayName ?? "Mode pending" }

    var currentStageLabel: String {
        if ["cancelled", "canceled"].contains(status.lowercased()) { return "Cancelled" }
        if status.lowercased() == "expired" { return "Expired" }
        guard lifecycleStage > 0 else { return "Status pending" }
        return Self.stageLabels[lifecycleStage - 1]
    }

    var nextStageLabel: String {
        if ["cancelled", "canceled", "expired", "rejected"].contains(status.lowercased()) {
            return "Load closed"
        }
        guard lifecycleStage > 0 else { return "Awaiting lifecycle state" }
        guard lifecycleStage < Self.stageLabels.count else { return "Lifecycle complete" }
        return "Next · \(Self.stageLabels[lifecycleStage])"
    }

    private static let stageLabels = [
        "Posted", "Bidding", "Awarded", "Pickup",
        "In transit", "Delivery", "Paperwork", "Closed",
    ]

    static func from(_ m: ShipperAPI.MyLoad) -> ShipperLoadRow {
        let unit = m.weightUnit?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let weight: String
        if m.weight > 0 {
            let value = m.weight.formatted(.number.precision(.fractionLength(0...2)))
            weight = unit?.isEmpty == false
                ? "\(value) \(unit!)"
                : "\(value) · weight unit pending"
        } else {
            weight = ""
        }
        let lane = "\(m.origin) → \(m.destination)"
            .replacingOccurrences(of: " → ", with: " → ")
        return ShipperLoadRow(
            id: m.id,
            serverLoadId: stripLoadPrefix(m.id),
            loadNumber: m.loadNumber,
            status: m.status,
            lane: lane,
            origin: m.origin,
            destination: m.destination,
            productName: m.product,
            cargoType: m.equipment,
            weightDisplay: weight,
            isHazmatDeclared: m.hazmat,
            hazmatClass: m.hazmatClass,
            amount: (m.rate ?? 0) > 0 ? m.rate : nil,
            currency: m.currency,
            rateUnit: m.rateUnit,
            worldscalePct: m.worldscalePct,
            lifecycleStage: stage(for: m.status),
            createdAt: m.createdAt,
            pickupDate: m.pickupDate,
            transportMode: m.transportMode,
            multiVehicleCount: m.multiVehicleCount,
            posterName: m.poster?.userName,
            posterCompanyName: m.poster?.companyName,
            posterCompanyLogo: m.poster?.companyLogo,
            posterProfilePicture: m.poster?.profilePicture
        )
    }
}

// MARK: - Screen body

struct ShipperLoads: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    // Sheet→push (NAV rollout 2026-05-30): the shared in-stack detail
    // layer. When present, tapping a load row renders ShipperLoadDetail
    // slid in from the trailing edge with a BespokeBackBar instead of a
    // pull-up sheet. Aliased to the shared `\.rolePushDetail` key.
    @Environment(\.shipperPushDetail) private var pushDetail

    @StateObject private var loads   = ShipperMyLoadsStore()
    @StateObject private var summary = ShipperLoadsSummaryStore()

    @State private var filter: ShipperLoadsFilter = .all
    @State private var query: String = ""
    @State private var detailRow: ShipperLoadRow? = nil
    /// Sort selection persisted across the screen lifetime. Cycled by
    /// the SORT button in the search row — `.eusoShipperLoadSort` is
    /// the trigger; the per-screen listener below advances the cycle
    /// + reloads the store with the new server-side sort.
    @State private var sort: ShipperLoadsSort = .newest
    /// Sheet flag for the action menu when the SORT button is tapped
    /// twice (cycle once, sheet on the second to expose the full
    /// list rather than guessing).
    @State private var showSortSheet: Bool = false
    /// SMART back affordance. nil when My Loads is shown as the root
    /// bottom-nav tab (no back button — it IS a tab). Set to the
    /// origin screen id (e.g. "212" Control Tower) when the user was
    /// routed INTO My Loads from a Me-section surface (Control Tower
    /// → "View all" exceptions). When non-nil, a BespokeBackBar paints
    /// above the screen and its chevron navigates straight back to that
    /// origin — not just to home. The origin id rides in the
    /// `.eusoShipperNavSwap` userInfo as `backTo`; the bottom-nav tab
    /// path posts NO `backTo`, so the bar stays hidden there.
    /// Founder 2026-06-02: a driver routed into Loads from Control Tower
    /// with no way back "will irritate a truck driver to the max."
    @State private var backTarget: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let target = backTarget {
                BespokeBackBar(title: nil) {
                    // Navigate straight back to the origin (Control Tower),
                    // not to home. A plain `.eusoShipperNavBack` can't help
                    // here — landing on 201 (a bottom-nav tab root) collapses
                    // the surface stack to a single entry, so there is
                    // nothing to pop. Re-swapping to the origin screen id
                    // re-renders it WITH its own surface back chevron.
                    NotificationCenter.default.post(
                        name: .eusoShipperNavSwap, object: nil,
                        userInfo: ["screenId": target]
                    )
                }
            }
            topBar
            IridescentHairline()
                .padding(.horizontal, Space.s5)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    searchRow
                    filterChips
                    listSection
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await refreshAll() }
        // SMART back: read + clear the pushed-from-origin context the
        // instant this view mounts. The `.eusoShipperNavSwap` post that
        // routed us here is delivered to the surface receiver BEFORE 201
        // mounts (the surface mutates `screenStack`, which re-renders and
        // THEN mounts 201) — so an `.onReceive` here would miss it. The
        // origin id is parked in `ShipperLoadsNavContext` by the caller
        // (Control Tower "View all") and consumed exactly once here. Same
        // race-free hand-off pattern the Broker surface uses
        // (`BrokerNavContext`).
        .onAppear {
            // Consume both halves unconditionally so neither can leak into
            // the next mount. Origin nil ⇒ entered as a tab ⇒ no back bar.
            let origin = ShipperLoadsNavContext.consumePushOrigin()
            let prefill = ShipperLoadsNavContext.consumeQuery()
            if let origin {
                backTarget = origin
                if let prefill, !prefill.isEmpty { query = prefill }
            }
        }
        .refreshable { await refreshAll() }
        // RealtimeService → live updates from any load on the
        // shipper's roster (carrier accept, driver assign, status
        // change, POD landing) refresh the loads board immediately
        // instead of waiting for the next pull-to-refresh.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await refreshAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task { await refreshAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadReassigned)) { _ in
            Task { await refreshAll() }
        }
        // SORT button posts `eusoShipperLoadSort` — show the sort
        // picker sheet so the user picks Newest / Oldest /
        // Highest-rate / Lowest-rate / Pickup-soonest. The picker
        // persists via `sort` and triggers `loads.refresh()` on
        // selection. No more dead button.
        .onReceive(NotificationCenter.default.publisher(for: .eusoShipperLoadSort)) { _ in
            showSortSheet = true
        }
        // Cross-screen prefill — 210 Analytics Deep-dive posts a
        // navSwap to "201" with `query` in userInfo when a lane bar
        // is tapped. Apply it to the local search field so the load
        // list narrows to that lane on landing. Replaces the prior
        // dead-end web-continuation handoff.
        .onReceive(NotificationCenter.default.publisher(for: .eusoShipperNavSwap)) { note in
            guard let screenId = note.userInfo?["screenId"] as? String, screenId == "201" else { return }
            if let q = note.userInfo?["query"] as? String, !q.isEmpty {
                query = q
            }
            // SMART back: a `backTo` origin in the swap payload means the
            // user was pushed INTO My Loads from a Me-section surface
            // (Control Tower "View all" exceptions) — paint the back bar
            // and aim it at that origin. The bottom-nav "Loads" tap posts
            // NO `backTo`, so we clear it and stay back-button-free as a
            // root tab should.
            backTarget = note.userInfo?["backTo"] as? String
        }
        .confirmationDialog("Sort loads", isPresented: $showSortSheet, titleVisibility: .visible) {
            ForEach(ShipperLoadsSort.allCases, id: \.self) { option in
                Button(option.label) {
                    sort = option
                    Task { await refreshAll() }
                }
            }
            Button("Cancel", role: .cancel) { }
        }
        .screenTileRoot()
    }

    private func refreshAll() async {
        async let a: Void = loads.refresh()
        async let b: Void = summary.refresh()
        _ = await (a, b)
    }

    /// Sheet→push: render the canonical Load Detail screen in-stack.
    /// `ShipperLoadDetailScreen` owns the persistent role dock and its
    /// scroll-safe bottom clearance; the shared detail layer still owns
    /// the BespokeBackBar, so the pushed record does not add a second
    /// navigation stack or back control. One mode-agnostic detail path
    /// covers Truck, Rail, and Vessel rows.
    private func openDetail(_ r: ShipperLoadRow) {
        detailRow = r
        pushDetail?("Load detail") {
            AnyView(
                ShipperLoadDetailScreen(
                    theme: palette,
                    loadId: r.serverLoadId,
                    previewLoadNumber: r.loadNumber,
                    previewLane: r.lane
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            )
        }
    }

    // MARK: - TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                EusoTripEyebrow(verbatim: "SHIPPER · MY LOADS")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(counterLine)
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            Text("My loads")
                .font(EType.display)
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s2)
            Text("Movement register")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 2)
            Text(scopeLine)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 2)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    private var counterLine: String {
        guard let s = summary.state.value ?? nil else {
            return "PORTFOLIO SYNCING"
        }
        return "\(s.totalLoads) TOTAL · \(s.activeLoads) ACTIVE"
    }

    private var scopeLine: String {
        "Truck · Rail · Vessel · every load, handoff and commercial state"
    }

    // MARK: - Search row + SORT button

    private var searchRow: some View {
        HStack(spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                TextField("Search load ID, lane, equipment…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
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
            .frame(height: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(Capsule().strokeBorder(palette.borderFaint))
            .clipShape(Capsule())
            .accessibilityLabel("Search loads")

            Button {
                NotificationCenter.default.post(name: .eusoShipperLoadSort, object: nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("SORT")
                        .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textPrimary)
                }
                .frame(width: 72, height: 44)
                .background(palette.bgCard)
                .overlay(Capsule().strokeBorder(palette.borderFaint))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sort and filter")
        }
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(ShipperLoadsFilter.allCases) { f in
                    let count = f.count(in: summary.state.value ?? nil)
                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                            filter = f
                        }
                    } label: {
                        chipLabel(f, count: count)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(filterAccessibilityLabel(f, count: count))
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func chipLabel(_ f: ShipperLoadsFilter, count: Int?) -> some View {
        let on = (filter == f)
        Text("\(f.displayLabel) · \(count.map(String.init) ?? "—")")
            .font(EType.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(palette.textPrimary))
            .background {
                if on { Capsule().fill(LinearGradient.primary) }
                else  { Capsule().fill(palette.bgCard) }
            }
            .overlay(Capsule().strokeBorder(on ? .clear : palette.borderFaint))
    }

    // MARK: - List section

    @ViewBuilder
    private var listSection: some View {
        switch loads.state {
        case .loading:
            listSkeleton
        case .loaded(let rows):
            if rows.isEmpty {
                emptyState
            } else {
                movementRegister(visibleRows(from: rows))
            }
        case .empty:
            emptyState
        case .error(let e):
            inlineError(e) { Task { await refreshAll() } }
        }
    }

    private func movementRegister(_ rows: [ShipperLoadRow]) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                EusoTripEyebrow(verbatim: "MOVEMENT REGISTER")
                    .font(EType.micro)
                    .tracking(1)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(rows.isEmpty ? "NO MATCHES" : "\(rows.count) SHOWN")
                    .font(EType.micro)
                    .tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }

            if rows.isEmpty {
                searchEmptyState
            } else {
                ForEach(rows) { row in
                    Button { openDetail(row) } label: { rowView(row) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func visibleRows(from raw: [ShipperAPI.MyLoad]) -> [ShipperLoadRow] {
        let rows = raw.map(ShipperLoadRow.from)
        // Apply filter chip
        let filtered: [ShipperLoadRow]
        if filter == .all {
            filtered = rows
        } else {
            let allowed = filter.statusSet
            filtered = rows.filter { allowed.contains($0.status.lowercased()) }
        }
        // Apply search
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let searched: [ShipperLoadRow]
        if needle.isEmpty {
            searched = filtered
        } else {
            searched = filtered.filter { r in
                r.loadNumber.lowercased().contains(needle)
                    || r.origin.lowercased().contains(needle)
                    || r.destination.lowercased().contains(needle)
                    || r.cargoType.lowercased().contains(needle)
                    || r.productName.lowercased().contains(needle)
                    || r.modeLabel.lowercased().contains(needle)
            }
        }
        return sortedRows(searched)
    }

    private func sortedRows(_ rows: [ShipperLoadRow]) -> [ShipperLoadRow] {
        rows.sorted { lhs, rhs in
            switch sort {
            case .newest:
                return ordered(lhs.createdAt, rhs.createdAt, descending: true,
                               lhsTie: lhs.loadNumber, rhsTie: rhs.loadNumber)
            case .oldest:
                return ordered(lhs.createdAt, rhs.createdAt, descending: false,
                               lhsTie: lhs.loadNumber, rhsTie: rhs.loadNumber)
            case .highestRate:
                return ordered(lhs.amount, rhs.amount, descending: true,
                               lhsTie: lhs.loadNumber, rhsTie: rhs.loadNumber)
            case .lowestRate:
                return ordered(lhs.amount, rhs.amount, descending: false,
                               lhsTie: lhs.loadNumber, rhsTie: rhs.loadNumber)
            case .pickupSoonest:
                let left = lhs.pickupDate.trimmingCharacters(in: .whitespacesAndNewlines)
                let right = rhs.pickupDate.trimmingCharacters(in: .whitespacesAndNewlines)
                return ordered(left.isEmpty ? nil : left,
                               right.isEmpty ? nil : right,
                               descending: false,
                               lhsTie: lhs.loadNumber,
                               rhsTie: rhs.loadNumber)
            }
        }
    }

    /// Missing values always sort after recorded values. That keeps an
    /// unknown rate or date from masquerading as zero or "earliest".
    private func ordered<Value: Comparable>(
        _ lhs: Value?,
        _ rhs: Value?,
        descending: Bool,
        lhsTie: String,
        rhsTie: String
    ) -> Bool {
        switch (lhs, rhs) {
        case let (left?, right?):
            if left == right { return lhsTie < rhsTie }
            return descending ? left > right : left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return lhsTie < rhsTie
        }
    }

    private func filterAccessibilityLabel(_ filter: ShipperLoadsFilter, count: Int?) -> String {
        let quantity = count.map { "\($0) loads" } ?? "count syncing"
        let selection = self.filter == filter ? "selected" : "not selected"
        return "\(filter.displayLabel), \(quantity), \(selection)"
    }

    // MARK: - Row

    private func rowView(_ r: ShipperLoadRow) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                movementMark(for: r)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(r.modeLabel.uppercased()) · \(r.loadNumber)")
                        .font(EType.micro)
                        .tracking(0.8)
                        .foregroundStyle(modeTint(for: r))
                        .lineLimit(1)

                    Text(r.lane)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(movementDetailLine(r))
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: Space.s2)

                VStack(alignment: .trailing, spacing: 5) {
                    Text((EusoDisplayText.token(r.status) ?? "Status pending").uppercased())
                        .font(EType.micro)
                        .tracking(0.7)
                        .foregroundStyle(statusStyle(for: r.status))
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                        .accessibilityHidden(true)
                }
            }

            Divider().overlay(palette.borderFaint)

            HStack(alignment: .bottom, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.currentStageLabel.uppercased())
                        .font(EType.micro)
                        .tracking(0.8)
                        .foregroundStyle(statusStyle(for: r.status))
                    Text(r.nextStageLabel)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: Space.s2)

                VStack(alignment: .trailing, spacing: 2) {
                    if let commercial = commercialPrimary(r) {
                        Text(commercial)
                            .font(EType.bodyStrong)
                            .monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                        Text(commercialSecondary(r))
                            .font(EType.micro)
                            .tracking(0.5)
                            .foregroundStyle(palette.textTertiary)
                    } else {
                        Text("TERMS PENDING")
                            .font(EType.micro)
                            .tracking(0.7)
                            .foregroundStyle(Brand.warning)
                        Text("No confirmed amount")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }

            lifecycleStrip(filled: r.lifecycleStage)
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel(r))
        .accessibilityHint("Opens the load movement record")
    }

    private func statusStyle(for status: String) -> AnyShapeStyle {
        switch status.lowercased() {
        case let s where s.contains("transit") || s.contains("delivery"):
            return AnyShapeStyle(LinearGradient.primary)
        case let s where s.contains("bid"):
            return AnyShapeStyle(Brand.warning)
        case let s where s.contains("award") || s.contains("assigned"):
            return AnyShapeStyle(Brand.magenta)
        case let s where s.contains("posted"):
            return AnyShapeStyle(palette.textSecondary)
        case let s where s.contains("delivered") || s.contains("closed") || s.contains("complete"):
            return AnyShapeStyle(Brand.success)
        case let s where s.contains("late") || s.contains("delay"):
            return AnyShapeStyle(Brand.danger)
        case let s where s.contains("cancel") || s.contains("expire") || s.contains("reject"):
            return AnyShapeStyle(Brand.danger)
        default:
            return AnyShapeStyle(palette.textPrimary)
        }
    }

    private func modeTint(for row: ShipperLoadRow) -> Color {
        switch row.mode {
        case .truck:  return Brand.blue
        case .rail:   return Brand.rail
        case .vessel: return Brand.vessel
        case .barge:  return Brand.info
        case nil:     return palette.textTertiary
        }
    }

    private func isHazmat(_ row: ShipperLoadRow) -> Bool {
        if row.isHazmatDeclared { return true }
        if row.hazmatClass?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return true
        }
        let evidence = "\(row.productName) \(row.cargoType)".lowercased()
        return ["hazmat", "petroleum", "chemical", "cryogenic", "gasoline", "lpg", "lng"]
            .contains { evidence.contains($0) }
    }

    private func movementDetailLine(_ row: ShipperLoadRow) -> String {
        let product = row.productName.trimmingCharacters(in: .whitespacesAndNewlines)
        let equipment = row.cargoType.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        parts.append(product.isEmpty ? "Product not recorded" : product)
        if !equipment.isEmpty, equipment.caseInsensitiveCompare(product) != .orderedSame {
            parts.append(equipment)
        }
        if !row.weightDisplay.isEmpty { parts.append(row.weightDisplay) }
        if let count = row.multiVehicleCount, count > 1 { parts.append("\(count) units") }
        if isHazmat(row) {
            if let classification = row.hazmatClass?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !classification.isEmpty
            {
                parts.append("Hazmat class \(classification)")
            } else {
                parts.append("Hazmat")
            }
        }
        return parts.joined(separator: " · ")
    }

    private func commercialPrimary(_ row: ShipperLoadRow) -> String? {
        if let raw = row.worldscalePct?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty
        {
            return raw.lowercased().hasPrefix("ws") ? raw.uppercased() : "WS \(raw)"
        }
        return row.amount.map { money($0, currency: row.currency) }
    }

    private func commercialSecondary(_ row: ShipperLoadRow) -> String {
        EusoDisplayText.rateBasis(
            rateUnit: row.rateUnit,
            currency: row.currency,
            worldscalePct: row.worldscalePct,
            hasAmount: row.amount != nil
        )
    }

    private func rowAccessibilityLabel(_ row: ShipperLoadRow) -> String {
        var parts = [
            row.modeLabel,
            row.loadNumber,
            row.lane,
            movementDetailLine(row),
            row.currentStageLabel,
            row.nextStageLabel,
        ]
        if let commercial = commercialPrimary(row) {
            parts.append("Commercial terms \(commercial), \(commercialSecondary(row))")
        } else {
            parts.append("Commercial terms pending")
        }
        return parts.joined(separator: ", ")
    }

    private func lifecycleStyle(index: Int, filled: Int) -> AnyShapeStyle {
        if filled == 0 { return AnyShapeStyle(palette.textTertiary.opacity(0.24)) }
        if index < filled { return AnyShapeStyle(LinearGradient.primary) }
        return AnyShapeStyle(palette.textTertiary.opacity(0.24))
    }

    private func movementMark(for r: ShipperLoadRow) -> some View {
        let source = ShipperPosterImageResolver.resolve(
            companyLogo: r.posterCompanyLogo,
            profilePicture: r.posterProfilePicture
        )
        return ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Color(red: 0.035, green: 0.043, blue: 0.058))

            if let image = source.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(5)
            } else if let remoteURL = source.remoteURL {
                AppRadioSilenceAsyncImage(url: remoteURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(5)
                    case .empty:
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.white.opacity(0.72))
                    case .failure:
                        posterFallback(for: r)
                    @unknown default:
                        posterFallback(for: r)
                    }
                }
            } else {
                posterFallback(for: r)
            }

            if isHazmat(r) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Brand.hazmat)
                    .padding(4)
                    .background(Circle().fill(palette.bgCard))
                    .offset(x: 3, y: 3)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(posterAccessibilityLabel(for: r))
    }

    private func posterFallback(for row: ShipperLoadRow) -> some View {
        let initials = posterInitials(for: row)
        return Group {
            if initials.isEmpty {
                Image(systemName: "person.crop.square")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))
            } else {
                Text(initials)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(0.4)
                    .foregroundStyle(Color.white.opacity(0.9))
            }
        }
    }

    private func posterInitials(for row: ShipperLoadRow) -> String {
        let name = [row.posterCompanyName, row.posterName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        return name
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }

    private func posterAccessibilityLabel(for row: ShipperLoadRow) -> String {
        let identity = [row.posterCompanyName, row.posterName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return identity.map { "Posted by \($0)" } ?? "Poster identity not provided"
    }

    /// Canonical 8-stage lifecycle strip — Posted → Bidding → Awarded
    /// → Pickup → In transit → Delivery → Paperwork → Closed.
    private func lifecycleStrip(filled: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<8, id: \.self) { i in
                Capsule()
                    .frame(maxWidth: .infinity)
                    .frame(height: i == filled - 1 ? 6 : 4)
                    .foregroundStyle(lifecycleStyle(index: i, filled: filled))
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Empty / error / skeleton

    private var listSkeleton: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(palette.bgCardSoft)
                    .frame(width: 132, height: 10)
                Spacer()
                RoundedRectangle(cornerRadius: 3)
                    .fill(palette.bgCardSoft)
                    .frame(width: 52, height: 10)
            }

            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack(alignment: .top, spacing: Space.s3) {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCardSoft)
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 7) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(palette.bgCardSoft)
                                .frame(width: 122, height: 9)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(palette.bgCardSoft)
                                .frame(maxWidth: .infinity)
                                .frame(height: 17)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(palette.bgCardSoft)
                                .frame(width: 190, height: 9)
                        }
                    }
                    Divider().overlay(palette.borderFaint)
                    HStack(spacing: 4) {
                        ForEach(0..<8, id: \.self) { _ in
                            Capsule()
                                .fill(palette.bgCardSoft)
                                .frame(maxWidth: .infinity)
                                .frame(height: 4)
                        }
                    }
                }
                .padding(Space.s4)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading movement register")
    }

    @ViewBuilder
    private var emptyState: some View {
        EusoEmptyState(
            systemImage: "shippingbox",
            title: "No loads yet",
            subtitle: "Post Truck, Rail, or Vessel freight and it will appear here."
        )
    }

    @ViewBuilder
    private var searchEmptyState: some View {
        EusoEmptyState(
            systemImage: "magnifyingglass",
            title: "No matches",
            subtitle: "Try a different load number, origin or destination."
        )
        .padding(Space.s4)
    }

    private func inlineError(_ error: Error, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Brand.danger)
                Text("Couldn't load the movement register")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text(errorMessage(for: error))
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Button(action: retry) {
                Text("Retry")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func errorMessage(for error: Error) -> String {
        if let api = error as? EusoTripAPIError {
            return api.errorDescription ?? "Request failed."
        }
        return error.localizedDescription
    }

    // MARK: - Helpers

    private func money(_ value: Double, currency: String?) -> String {
        let code = currency?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let f = NumberFormatter()
        f.numberStyle = code?.isEmpty == false ? .currency : .decimal
        if let code, !code.isEmpty { f.currencyCode = code }
        f.maximumFractionDigits = value.rounded() == value ? 0 : 2
        if let formatted = f.string(from: NSNumber(value: value)) {
            return formatted
        }
        let fallback = value.formatted(.number.precision(.fractionLength(0...2)))
        return code?.isEmpty == false ? "\(code!) \(fallback)" : fallback
    }
}

// MARK: - Notification names (canonical CTA hooks)

extension Notification.Name {
    /// Fired by the SORT button on 201 → opens the sort/filter sheet.
    static let eusoShipperLoadSort = Notification.Name("eusoShipperLoadSort")
}

// MARK: - SMART back hand-off context (race-free)

/// One-shot hand-off from a Me-section surface that PUSHES the user into
/// My Loads (201) — e.g. Control Tower "View all" exceptions. The
/// `.eusoShipperNavSwap` post that triggers the route is delivered to the
/// ShipperSurface receiver BEFORE 201 mounts (the surface mutates
/// `screenStack`, which re-renders and only THEN mounts 201), so an
/// `.onReceive` on 201 would miss the payload. The caller parks the
/// origin screen id (+ optional search prefill) here just before posting
/// the swap; 201 consumes it once on `.onAppear` and paints a
/// BespokeBackBar aimed back at that origin.
///
/// Tab taps (bottom-nav "Loads") DON'T set this, so 201 stays correctly
/// back-button-free as a root tab. Mirrors `BrokerNavContext`'s race-free
/// drill-down hand-off (RoleSurfaceRouter).
enum ShipperLoadsNavContext {
    /// Origin screen id to return to (e.g. "212" Control Tower). nil when
    /// 201 is entered as the bottom-nav tab.
    private static var pushOrigin: String?
    /// Optional search prefill to apply on landing (e.g. "exception").
    private static var prefillQuery: String?

    /// Park the hand-off. Call immediately BEFORE posting the
    /// `.eusoShipperNavSwap` that routes to 201.
    static func setPush(origin: String, query: String? = nil) {
        pushOrigin = origin
        prefillQuery = query
    }

    /// Read + clear the origin (one-shot). Returns nil for tab entry.
    static func consumePushOrigin() -> String? {
        defer { pushOrigin = nil }
        return pushOrigin
    }

    /// Read + clear the prefill query (one-shot).
    static func consumeQuery() -> String? {
        defer { prefillQuery = nil }
        return prefillQuery
    }
}

// MARK: - Sort options surfaced by the SORT button's confirmation dialog

/// Sort axes for the Shipper Loads board. The `.label` is what the
/// confirmation dialog renders; future revs can pipe the raw value
/// into `shippers.getMyLoads(sort:)` once the backend ships that
/// parameter. Today the pick still updates local state so the user
/// sees immediate visual confirmation, and the next refresh will
/// honor it once the server-side sort lands.
enum ShipperLoadsSort: String, CaseIterable {
    case newest          = "newest"
    case oldest          = "oldest"
    case highestRate     = "highest_rate"
    case lowestRate      = "lowest_rate"
    case pickupSoonest   = "pickup_soonest"

    var label: String {
        switch self {
        case .newest:        return "Newest first"
        case .oldest:        return "Oldest first"
        case .highestRate:   return "Highest rate"
        case .lowestRate:    return "Lowest rate"
        case .pickupSoonest: return "Pickup soonest"
        }
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

// Shipper bottom-nav doctrine — see 200_ShipperHome.swift comment.
// Per parity mandate §1: NAV is out of scope.
private func shipperNavLeading_201() -> [NavSlot] {
    RoleNav.shipperLeading(current: .none)
}

private func shipperNavTrailing_201() -> [NavSlot] {
    RoleNav.shipperTrailing(current: .loads)
}

// MARK: - Previews

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
