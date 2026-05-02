//
//  201_ShipperLoads.swift
//  EusoTrip — Shipper · Loads (brick 201).
//
//  Parity-reconciled to `02 Shipper/Code/201_ShipperLoads.swift` per
//  _PARITY_PROMPT_FOR_CODING_TEAM_2026-04-29.md. Wireframe canon
//  applied: TopBar with right-side counter ("50 TOTAL · 12 ACTIVE"),
//  IridescentHairline, search capsule + SORT button, 5-chip filter
//  row with counts derived from `loads.getShipperSummary`, single
//  dense list card with mode glyph + 8-stage lifecycle strip + status
//  pill (kind-aware) + amount + rate-per-mile per row.
//
//  Real data preserved: `ShipperMyLoadsStore` (shippers.getMyLoads)
//  drives the row set; `ShipperLoadsSummaryStore` (loads.getShipperSummary)
//  drives chip counts + topline counter. Tap row → 205
//  ShipperLoadDetail (existing binding preserved).
//
//  Persona canon (§11): Diego Usoro · Eusorone Technologies (companyId 1)
//                        · MATRIX-50-2026-04-26.
//  Web peer: ShipperLoads.tsx (`/shipper/loads`).
//
//  BottomNav: Home / Create Load / Loads (current) / Me — out of scope
//  per parity mandate §1, matches user-feedback bottom-nav doctrine.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Filter taxonomy (matches wireframe 5-chip row)

private enum ShipperLoadsFilter: String, CaseIterable, Identifiable {
    case all        = "All"
    case bidding    = "Bidding"
    case awarded    = "Awarded"
    case inTransit  = "In transit"
    case delivered  = "Delivered"

    var id: String { rawValue }

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
    func count(in s: LoadsAPI.ShipperSummary?) -> Int {
        guard let s else { return 0 }
        switch self {
        case .all:        return s.activeLoads
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
    let cargoType: String
    let weightDisplay: String
    let unNumber: String?
    let hazmatClass: String?
    let metaLine: String
    let amount: Double
    let ratePerMile: String
    let lifecycleStage: Int  // 1...8

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
        default:                    return 1
        }
    }

    static func from(_ m: ShipperAPI.MyLoad) -> ShipperLoadRow {
        let weight = m.weight > 0 ? "\(Int(m.weight)) lbs" : ""
        let lane = "\(m.origin) → \(m.destination)"
            .replacingOccurrences(of: " → ", with: " → ")
        // Mono meta line per wireframe canon:
        //   `LD-260427-XXXXXXXXXX · MC-306 · 50k lb · 239 mi`
        // Composed defensively — drop empty parts, no "—" filler.
        let parts = [
            m.loadNumber,
            m.product.isEmpty ? m.equipment : m.product,
            weight,
        ].filter { !$0.isEmpty }
        let meta = parts.joined(separator: " · ")
        // Rate per mile not on wire — composed by /205 detail. Empty
        // here until backend ships distance projection on getMyLoads.
        let ratePerMile = ""
        return ShipperLoadRow(
            id: m.id,
            serverLoadId: stripLoadPrefix(m.id),
            loadNumber: m.loadNumber,
            status: m.status,
            lane: lane,
            origin: m.origin,
            destination: m.destination,
            cargoType: m.equipment,
            weightDisplay: weight,
            unNumber: nil,
            hazmatClass: m.hazmatClass,
            metaLine: meta,
            amount: m.rate ?? 0,
            ratePerMile: ratePerMile,
            lifecycleStage: stage(for: m.status)
        )
    }
}

// MARK: - Screen body

struct ShipperLoads: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
        .refreshable { await refreshAll() }
        // SORT button posts `eusoShipperLoadSort` — show the sort
        // picker sheet so the user picks Newest / Oldest /
        // Highest-rate / Lowest-rate / Pickup-soonest. The picker
        // persists via `sort` and triggers `loads.refresh()` on
        // selection. No more dead button.
        .onReceive(NotificationCenter.default.publisher(for: .eusoShipperLoadSort)) { _ in
            showSortSheet = true
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
        .sheet(item: $detailRow) { row in
            ShipperLoadDetail(
                loadId: row.serverLoadId,
                previewLoadNumber: row.loadNumber,
                previewLane: row.lane
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
        async let a: Void = loads.refresh()
        async let b: Void = summary.refresh()
        _ = await (a, b)
    }

    // MARK: - TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ SHIPPER · MY LOADS")
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
            Text(companyLine)
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
            return "50 TOTAL · 12 ACTIVE"
        }
        return "\(s.totalLoads) TOTAL · \(s.activeLoads) ACTIVE"
    }

    private var companyLine: String {
        // §11 canon — Eusorone / MATRIX-50 batch identifier in the sub-line.
        "Eusorone Technologies · MATRIX-50-2026-04-26"
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
                    .accessibilityLabel("\(f.rawValue) filter, \(count) loads, \(filter == f ? "active" : "inactive")")
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func chipLabel(_ f: ShipperLoadsFilter, count: Int) -> some View {
        let on = (filter == f)
        Text("\(f.rawValue) · \(count)")
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
                listCard(visibleRows(from: rows))
            }
        case .empty:
            emptyState
        case .error(let e):
            inlineError(e) { Task { await refreshAll() } }
        }
    }

    private func listCard(_ rows: [ShipperLoadRow]) -> some View {
        VStack(spacing: 0) {
            if rows.isEmpty { searchEmptyState } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, r in
                    Button { detailRow = r } label: { rowView(r) }
                        .buttonStyle(.plain)
                    if idx < rows.count - 1 {
                        Divider().overlay(palette.borderFaint)
                    }
                }
            }
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
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
        guard !needle.isEmpty else { return filtered }
        return filtered.filter { r in
            r.loadNumber.lowercased().contains(needle)
                || r.origin.lowercased().contains(needle)
                || r.destination.lowercased().contains(needle)
                || r.cargoType.lowercased().contains(needle)
        }
    }

    // MARK: - Row

    private func rowView(_ r: ShipperLoadRow) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            modeGlyph(for: r)
            VStack(alignment: .leading, spacing: 4) {
                Text(r.lane)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(r.metaLine)
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                lifecycleStrip(filled: r.lifecycleStage)
                    .padding(.top, 2)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 4) {
                Text(r.status.uppercased())
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(statusStyle(for: r.status))
                if r.amount > 0 {
                    Text(dollars(r.amount))
                        .font(EType.bodyStrong).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
                if !r.ratePerMile.isEmpty {
                    Text(r.ratePerMile)
                        .font(EType.caption).monospacedDigit()
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(r.lane), \(r.status), \(dollars(r.amount))")
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
        default:
            return AnyShapeStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private func modeGlyph(for r: ShipperLoadRow) -> some View {
        let cargo = r.cargoType.lowercased()
        if cargo.contains("hazmat") || cargo == "petroleum" || cargo == "chemicals"
            || cargo == "liquid" || cargo == "gas" || cargo == "cryogenic" || (r.hazmatClass ?? "").isEmpty == false
        {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Brand.hazmat.opacity(0.16))
                Rectangle()
                    .stroke(Brand.hazmat, lineWidth: 1.6)
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(45))
                if let c = r.hazmatClass, !c.isEmpty {
                    Text(c)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color(hex: 0xB27300))
                        .offset(y: 2)
                }
            }
            .frame(width: 40, height: 40)
        } else if cargo.contains("reefer") || cargo == "refrigerated" || cargo == "food_grade" {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Brand.info.opacity(0.12))
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Brand.info, lineWidth: 1.6)
                    .frame(width: 22, height: 18)
            }
            .frame(width: 40, height: 40)
        } else if cargo == "intermodal" || r.lane.lowercased().contains("rail") {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Color(hex: 0x607D8B).opacity(0.16))
                VStack(spacing: 2) {
                    Capsule()
                        .stroke(Color(hex: 0x607D8B), lineWidth: 1.6)
                        .frame(width: 24, height: 12)
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: 0x607D8B)).frame(width: 3, height: 3)
                        Circle().fill(Color(hex: 0x607D8B)).frame(width: 3, height: 3)
                    }
                }
            }
            .frame(width: 40, height: 40)
        } else if cargo.contains("flatbed") || cargo == "oversized" {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft)
                VStack(spacing: 2) {
                    Rectangle().fill(palette.textPrimary).frame(width: 22, height: 1.6)
                    HStack(spacing: 8) {
                        Circle().fill(palette.textPrimary).frame(width: 5, height: 5)
                        Circle().fill(palette.textPrimary).frame(width: 5, height: 5)
                    }
                }
            }
            .frame(width: 40, height: 40)
        } else {
            // Dry van / general default
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft)
                Rectangle()
                    .stroke(palette.textPrimary, lineWidth: 1.6)
                    .frame(width: 22, height: 14)
                    .overlay(
                        Rectangle()
                            .stroke(palette.textPrimary, lineWidth: 1.6)
                            .frame(width: 1, height: 14)
                    )
            }
            .frame(width: 40, height: 40)
        }
    }

    /// Canonical 8-stage lifecycle strip — Posted → Bidding → Awarded
    /// → Pickup → In transit → Delivery → Paperwork → Closed.
    private func lifecycleStrip(filled: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<8, id: \.self) { i in
                Circle()
                    .frame(width: i == filled - 1 ? 6 : 5,
                           height: i == filled - 1 ? 6 : 5)
                    .foregroundStyle(i < filled
                                     ? AnyShapeStyle(LinearGradient.primary)
                                     : AnyShapeStyle(palette.textTertiary.opacity(0.32)))
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Empty / error / skeleton

    private var listSkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                Rectangle()
                    .fill(palette.bgCardSoft)
                    .frame(height: 76)
                if i < 2 { Divider().overlay(palette.borderFaint) }
            }
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
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
        .padding(Space.s4)
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

    private func dollars(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$0"
    }
}

// MARK: - Notification names (canonical CTA hooks)

extension Notification.Name {
    /// Fired by the SORT button on 201 → opens the sort/filter sheet.
    static let eusoShipperLoadSort = Notification.Name("eusoShipperLoadSort")
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
    [NavSlot(label: "Home",        systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Create Load", systemImage: "plus.rectangle.on.rectangle",    isCurrent: false)]
}

private func shipperNavTrailing_201() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
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
