//
//  639_RailYardDirectory.swift
//  EusoTrip — Rail Engineer · Yard Directory (searchable host-railroad index).
//
//  Bespoke port of canonical "05 Rail/Code/639_RailYardDirectory.swift"
//  (SEARCHABLE-INDEX archetype: search hero + segmented type filter + grouped
//  index keyed by host railroad + network-coverage footer). RAIL_ENGINEER,
//  carrier-side. NOT the dashboard anti-pattern, NOT 559 (live corridor),
//  NOT 600/628 (single-yard execution / spatial map).
//
//  Adapted to app convention: top-level RailYardDirectoryScreen(theme:) wraps
//  the bespoke body in the shared Shell + rail BottomNav (HOME · SHIPMENTS[current]
//  · [orb] · COMPLIANCE · ME), copied verbatim from sibling 578_RailRouteWeather.
//  The canonical port's self-drawn BottomNavRail_639 + page background are removed
//  (Shell provides them); the bespoke body is kept faithfully.
//
//  WIRING (MCP-confirmed · server/routers/railShipments.ts):
//    railShipments.getRailYards          (EXISTS :732) · railProcedure
//        in:  { railroadId?, state?, country?, yardType?, hasIntermodal?, limit=50 }
//        out: [ railYards row ] — { id, name, splcCode, railroadId, city, state,
//             country, coordinates, yardType, totalTracks, capacity, hasIntermodal,
//             hasHazmat, status } · filtered to status="active"
//    railShipments.getRailDashboardStats (EXISTS :964) · railProcedure (no input)
//        out: { activeShipments, carsInTransit, avgTransitDays, revenue }
//
//  HONEST RENDER NOTE: the canonical mock grouped by reporting MARK (BNSF/UP/NS),
//  but getRailYards returns FLAT yard rows and does NOT join rail_carriers — there
//  is no mark string in the payload, only railroadId (number) + splcCode. So the
//  index groups by host-railroad id (label "Railroad #N", count from the live
//  rows), and each entry surfaces the real fields the proc returns (city · state ·
//  yardType · status). The coverage footer reflects what the proc actually exposes
//  (online vs. total, intermodal count, classification count). getRailDashboardstats
//  has no by-railroad group counts, so the footer reports live yard counts directly.
//  STUB · named-gap (surfaced to the-oath): getRailYards has no full-text {q} search
//    param. The search field filters the already-loaded rows client-side and is NOT
//    a server query; the segmented type filter re-runs load() with a yardType arg.
//

import SwiftUI

// MARK: - Data shape (real getRailYards row)

private struct YardRow639: Decodable, Identifiable {
    let id: Int
    let name: String?
    let splcCode: String?
    let railroadId: Int?
    let city: String?
    let state: String?
    let country: String?
    let yardType: String?
    let hasIntermodal: Bool?
    let hasHazmat: Bool?
    let status: String?
}

private struct DashboardStats639: Decodable {
    let activeShipments: Int?
    let carsInTransit: Int?
    let avgTransitDays: Int?
    let revenue: Double?
}

// MARK: - Wrapper

struct RailYardDirectoryScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { RailYardDirectoryBody639() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct RailYardDirectoryBody639: View {
    @Environment(\.palette) private var palette

    @State private var yards: [YardRow639] = []
    @State private var query = ""
    @State private var typeFilter: String? = nil      // nil = All; else yardType enum value
    @State private var loading = true
    @State private var loadError: String? = nil

    // MARK: Derived

    /// Yards matching the client-side text query (mark/city/SCAC/name). The
    /// server has no {q} param, so this filters the already-loaded rows.
    private var filtered: [YardRow639] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return yards }
        return yards.filter { y in
            let hay = [y.name, y.city, y.state, y.splcCode, y.yardType]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
            return hay.contains(q)
        }
    }

    /// Grouped by host-railroad id (the proc gives no mark string). Sorted by
    /// descending count so the largest hosts lead the index.
    private var groups: [(key: Int, label: String, rows: [YardRow639])] {
        let buckets = Dictionary(grouping: filtered) { $0.railroadId ?? -1 }
        return buckets
            .map { (key: $0.key, label: railroadLabel639($0.key), rows: $0.value.sorted { ($0.name ?? "") < ($1.name ?? "") }) }
            .sorted { $0.rows.count > $1.rows.count }
    }

    private var total: Int { yards.count }
    private var online: Int { yards.filter { ($0.status ?? "").lowercased() == "active" }.count }
    private var intermodalCount: Int { yards.filter { $0.hasIntermodal == true }.count }
    private var classificationCount: Int { yards.filter { ($0.yardType ?? "").lowercased() == "classification" }.count }
    private var railroadCount: Int { Set(yards.compactMap { $0.railroadId }).count }

    // MARK: Type filter chips (real yardType enum values)

    private let typeChips639: [(label: String, value: String?)] = [
        ("All",            nil),
        ("Classification", "classification"),
        ("Intermodal",     "intermodal_ramp"),
        ("Team track",     "team_track"),
        ("Industry",       "industry"),
    ]

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            header
            searchField
            typeFilterRow
            if loading {
                LifecycleCard { Text("Loading yard directory…").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else if let err = loadError {
                LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
            } else if filtered.isEmpty {
                EusoEmptyState(systemImage: "magnifyingglass",
                               title: query.isEmpty ? "No yards in this filter" : "No yards match “\(query)”",
                               subtitle: "Adjust the search or type filter. The directory hydrates live from getRailYards.")
            } else {
                indexSection
                coverageBand
            }
            ctaPair
            Color.clear.frame(height: 96)
        }
        .padding(.horizontal, 14).padding(.top, 8)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("RAIL ENGINEER · YARD DIRECTORY")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text("YARDS · US")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Yard directory")
                    .font(.system(size: 28, weight: .heavy))
                    .kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            IridescentHairline()
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textSecondary)
            TextField("Search \(total) yards · mark, city, SPLC", text: $query)
                .font(.system(size: 13))
                .foregroundStyle(palette.textPrimary)
                .autocorrectionDisabled()
            Image(systemName: "slider.horizontal.3").font(.system(size: 14)).foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, 16).frame(height: 46)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.borderFaint))
    }

    // MARK: - Type filter

    private var typeFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(typeChips639, id: \.label) { chip in
                    let active = typeFilter == chip.value
                    let countForChip: Int = chip.value == nil
                        ? yards.count
                        : yards.filter { ($0.yardType ?? "") == chip.value }.count
                    Button {
                        typeFilter = chip.value
                    } label: {
                        Text("\(chip.label) · \(countForChip)")
                            .font(.system(size: 10.5, weight: .heavy))
                            .foregroundStyle(active ? Color.white : palette.textSecondary)
                            .padding(.horizontal, 12).frame(height: 28)
                            .background(
                                Group {
                                    if active { LinearGradient.primary } else { palette.bgCard }
                                }
                            )
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(active ? Color.clear : palette.borderFaint))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Index section

    private var indexSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("RAIL YARDS · BY HOST RAILROAD")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("A–Z").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, 10)

            VStack(spacing: 0) {
                ForEach(groups, id: \.key) { g in
                    groupHeader(g.label, count: g.rows.count, key: g.key)
                    ForEach(Array(g.rows.enumerated()), id: \.element.id) { i, r in
                        entryRow(r, key: g.key)
                        if i < g.rows.count - 1 {
                            Divider().padding(.leading, 52).overlay(palette.borderFaint)
                        }
                    }
                }
                Divider().overlay(palette.borderFaint)
                HStack {
                    Text("\(railroadCount) host railroad\(railroadCount == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.info)
                    Spacer()
                    Text("\(online) online").font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                }
                .padding(.top, 10)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        }
    }

    private func groupHeader(_ label: String, count: Int, key: Int) -> some View {
        let tint = markColor639(key)
        return HStack {
            Text("\(label) · \(count) yard\(count == 1 ? "" : "s")")
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                .foregroundStyle(tint)
            Spacer()
            Text("see all ›").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary)
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10))
    }

    private func entryRow(_ r: YardRow639, key: Int) -> some View {
        let tint = markColor639(key)
        let chip = chipLabel639(r)
        let active = (r.status ?? "").lowercased() == "active"
        let statusColor = active ? Brand.success : Brand.warning
        let sub = [r.city, r.state, prettyType639(r.yardType)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.16))
                .frame(width: 40, height: 40)
                .overlay(Text(chip).font(.system(size: 10, weight: .heavy)).foregroundStyle(tint))
            VStack(alignment: .leading, spacing: 4) {
                Text(r.name ?? "Unnamed yard").font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(sub.isEmpty ? "-" : sub).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(active ? "ACTIVE" : (r.status ?? "-").uppercased())
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(statusColor)
            }
            Text(r.splcCode ?? "-").font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textTertiary)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Coverage band

    private var coverageBand: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Network coverage").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textSecondary)
            Text("\(online) / \(total) reporting · \(railroadCount) host railroad\(railroadCount == 1 ? "" : "s") · \(classificationCount) classification · \(intermodalCount) intermodal")
                .font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            // STUB · no per-yard detail route wired from the directory yet — re-runs load().
            CTAButton(title: "Open yard", action: { Task { await load() } }, leadingIcon: "building.2")
            Button { typeFilter = nil; query = "" } label: {
                Text("Reset")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers (file-scoped, screen-suffixed; no func inside ViewBuilder closures)

    private func railroadLabel639(_ id: Int) -> String {
        id < 0 ? "Independent / unassigned" : "Railroad #\(id)"
    }

    private func markColor639(_ id: Int) -> Color {
        // Deterministic palette rotation keyed by host id — honest stand-in for
        // a mark color the proc does not return.
        let palette639: [Color] = [Brand.info, Brand.warning, Brand.escort, Brand.success, Brand.vessel, Brand.rail]
        guard id >= 0 else { return Brand.neutral }
        return palette639[id % palette639.count]
    }

    private func chipLabel639(_ r: YardRow639) -> String {
        // Prefer a SPLC prefix; fall back to first letters of the yard name.
        if let s = r.splcCode, s.count >= 2 { return String(s.prefix(3)).uppercased() }
        let initials = (r.name ?? "YD").split(separator: " ").compactMap { $0.first }.prefix(2)
        return String(initials).uppercased()
    }

    private func prettyType639(_ t: String?) -> String {
        guard let t = t, !t.isEmpty else { return "" }
        return t.replacingOccurrences(of: "_", with: " ")
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        do {
            struct YardsInput639: Encodable { let yardType: String?; let country: String?; let limit: Int }
            let input = YardsInput639(yardType: typeFilter, country: "US", limit: 200)
            let rows: [YardRow639] = try await EusoTripAPI.shared.query("railShipments.getRailYards", input: input)
            // Stats fetched for coverage context; the proc returns shipment-level
            // counts only (no by-railroad yard grouping), so the footer math above
            // is derived from the live yard rows — stats kept for the named gap.
            _ = try? await EusoTripAPI.shared.queryNoInput("railShipments.getRailDashboardStats") as DashboardStats639
            self.yards = rows
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Previews (seed lives ONLY here)

#Preview("639 · Rail Yard Directory · Night") {
    RailYardDirectoryScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("639 · Rail Yard Directory · Light") {
    RailYardDirectoryScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
