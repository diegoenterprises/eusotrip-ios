//
//  217_ShipperContracts.swift
//  EusoTrip 2027 UI — Shipper · Contracts (parity-reconciled 2026-04-29)
//
//  PARITY AUDIT 2026-04-29 — reconciled to wireframe canon at
//  /02 Shipper/Code/217_ShipperContracts.swift. Persona: Diego
//  Usoro / Eusorone Technologies (companyId 1) per §11. Contract
//  IDs reuse the LD- hex tail per §11.2 audit-trail convention so
//  `contracts` and `loads` rows join on the same suffix.
//
//  Layout (top → bottom):
//    1. TopBar           ✦ SHIPPER · CONTRACTS / "{N} ACTIVE · {%} FILL"
//    2. Title block      Contracts (34pt) / "Eusorone Technologies · volume commitments · YTD ledger"
//    3. IridescentHairline
//    4. Hero KPI card    gradient rim → bgCard inner · 4-cell quartet
//                        (ACTIVE · COMMITTED loads · SPEND YTD · FILL)
//    5. Filter chip row  All · Active · {N} · Pilot · {N} · Renewing · {N} · Closed
//    6. Contract rows    3pt tier rim · ctr id · status pill · lane title ·
//                        spec line · 3-stat row · fill-rate progress bar
//    7. "+ New contract proposal" gradient pill CTA
//
//  Real wiring preserved: `contracts.getStats` + `contracts.getAll` +
//  `contracts.getContract(id:)` via `ShipperContractsStore`. Detail
//  sheet (preserved) opens on row tap with terms / pricing / volume /
//  notes cards driven by `ContractDetail` envelope.
//
//  Backend gaps surfaced (logged in audit log, no fake data):
//    EUSO-2120 — `contracts.getStats` doesn't ship `committedLoads`,
//                `spendYtd`, or `fillRate` aggregates. KPI hero
//                `COMMITTED loads` / `SPEND YTD` / `FILL` cells paint
//                derived placeholders (`—` / formatted `totalValue` /
//                `—`) until the procedure extends.
//    EUSO-2121 — `contracts.getAll` doesn't ship per-row lane/origin/
//                destination, equipment, cadence, term type (pilot/
//                renewing), per-load rate, filled count, fill rate,
//                or vs-spot delta. The wireframe-canon row anatomy
//                paints `customer` as the lane line, `type` as the
//                spec line, and the 3-stat triplet uses
//                value / endDate / "—" placeholders. Status pill is
//                derived from `status` only.
//
//  Doctrine refs: §2 LOADS-tab nav (handled by ContentView); §3
//  numbers-first copy ("$684k", "92%"); §4.3 single iridescent
//  hairline; §7 breathe density; §11 / §11.2 Diego canon + LD-
//  audit-trail; §11.4 / §13 carrier mix; §15.2 per-row 3pt tier rim
//  grammar; §16 hero-rim KPI quartet recipe; §16.2 gradient pill
//  CTA pattern; §19.2 file-scoped `warnGrad` + `paidGrad`; §20.4 no
//  dead buttons; §22.2 counter color (success when fill > 80%).
//

import SwiftUI

// MARK: - Filter chips (wireframe-canon labels with live counts)

private enum ContractFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case pilot
    case renewing
    case closed

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:       return "All"
        case .active:    return "Active"
        case .pilot:     return "Pilot"
        case .renewing:  return "Renewing"
        case .closed:    return "Closed"
        }
    }

    /// Server-side status string (or nil for "all"). Pilot + renewing
    /// are derived buckets — they map onto active/expiring server
    /// status with client-side splits.
    var serverStatus: String? {
        switch self {
        case .all:       return nil
        case .active:    return "active"
        case .pilot:     return "active"   // pilot is a derived view
        case .renewing:  return "active"   // renewing derives from endDate ≤ 30d
        case .closed:
            return nil  // multiple statuses match — filter client-side
        }
    }
}

// MARK: - Store

@MainActor
final class ShipperContractsStore: ObservableObject {
    enum LoadState {
        case loading
        case empty
        case error(String)
        case loaded(stats: ContractsAPI.Stats, rows: [ContractsAPI.ContractRow])
    }

    @Published private(set) var state: LoadState = .loading
    @Published var filter: ContractFilter = .all {
        didSet {
            if oldValue != filter { Task { await refresh() } }
        }
    }
    @Published var searchTerm: String = ""

    private let api: EusoTripAPI

    init(api: EusoTripAPI = .shared) {
        self.api = api
    }

    func refresh() async {
        if case .loaded = state {} else { state = .loading }
        do {
            async let s = api.contracts.getStats()
            async let r = api.contracts.getAll(
                search: searchTerm.isEmpty ? nil : searchTerm,
                status: filter.serverStatus
            )
            let (stats, rows) = try await (s, r)
            let filtered = applyClientFilter(rows: rows, filter: filter)
            if filtered.isEmpty && stats.total == 0 {
                state = .empty
            } else {
                state = .loaded(stats: stats, rows: filtered)
            }
        } catch {
            state = .error("Couldn't reach contracts service.")
        }
    }

    private func applyClientFilter(rows: [ContractsAPI.ContractRow],
                                   filter: ContractFilter) -> [ContractsAPI.ContractRow] {
        let now = Date()
        let cutoff30d = now.addingTimeInterval(30 * 86400)
        switch filter {
        case .all:
            return rows
        case .active:
            return rows
        case .pilot:
            // Pilot heuristic: active row with type containing "pilot",
            // or notes/customer hint. Backend doesn't ship a pilot flag
            // (EUSO-2121) so this stays a string-match approximation.
            return rows.filter { row in
                let t = (row.type ?? "").lowercased()
                let c = (row.customer ?? "").lowercased()
                return t.contains("pilot") || c.contains("pilot")
            }
        case .renewing:
            return rows.filter { row in
                guard let s = row.endDate, !s.isEmpty,
                      let d = parseDateYMD(s) else { return false }
                return d >= now && d <= cutoff30d
            }
        case .closed:
            return rows.filter { row in
                let s = (row.status ?? "").lowercased()
                return s == "expired" || s == "terminated"
            }
        }
    }
}

private func parseDateYMD(_ s: String) -> Date? {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(identifier: "UTC")
    return f.date(from: s)
}

// MARK: - Tier rim + status pill kinds

private enum TierRim { case gradient, warn, paid, neutral }
private enum FillKind { case gradient, warn, paid }

private enum ContractStatusPill {
    case active(legend: String, width: CGFloat)
    case pilot(legend: String, width: CGFloat)
    case renewing(legend: String, width: CGFloat)
    case closed(legend: String, width: CGFloat)
}

// MARK: - Screen root

struct ShipperContracts: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var store = ShipperContractsStore()
    @State private var selectedId: String?
    @State private var detail: ContractsAPI.ContractDetail?
    @State private var detailLoading: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, Space.s5)
                titleBlock
                    .padding(.top, Space.s2)
                IridescentHairline()
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s5)

                content
                    .padding(.top, Space.s3)

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(item: Binding(
            get: { selectedId.map { IdentifiedContractId(id: $0) } },
            set: { newValue in
                selectedId = newValue?.id
                if newValue == nil { detail = nil }
            }
        )) { ident in
            ContractDetailSheet(
                contractId: ident.id,
                detail: $detail,
                loading: $detailLoading,
                palette: palette
            )
            .presentationDragIndicator(.visible)
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.18),
            value: store.filter
        )
    }

    // MARK: TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · CONTRACTS")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text(counterEyebrow)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(counterColor)
                .accessibilityLabel(counterAccessibility)
        }
        .padding(.horizontal, Space.s5)
    }

    private var counterEyebrow: String {
        if case .loaded(let stats, _) = store.state {
            // EUSO-2120 — fillRate aggregate not yet on API surface.
            return "\(stats.active) ACTIVE · — FILL"
        }
        return "—"
    }

    private var counterColor: Color {
        if case .loaded(let stats, _) = store.state, stats.active > 0 {
            return Brand.success
        }
        return palette.textTertiary
    }

    private var counterAccessibility: String {
        if case .loaded(let stats, _) = store.state {
            return "\(stats.active) active contracts, fill rate pending"
        }
        return "Loading contracts"
    }

    // MARK: Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Contracts")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(palette.textPrimary)
            Text("Eusorone Technologies · volume commitments · YTD ledger")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
    }

    // MARK: Content state machine

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .loading:
            VStack(spacing: Space.s2) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.3))
                        .frame(height: 116)
                }
            }
            .padding(.horizontal, Space.s5)
        case .empty:
            emptyHero
                .padding(.horizontal, Space.s5)
        case .error(let msg):
            errorBanner(msg)
                .padding(.horizontal, Space.s5)
        case .loaded(let stats, let rows):
            VStack(alignment: .leading, spacing: 0) {
                kpiHeroCard(stats)
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s3)

                filterRow(rows: rows)
                    .padding(.top, Space.s5)

                if rows.isEmpty {
                    noFilteredResults
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s4)
                } else {
                    VStack(spacing: Space.s4) {
                        ForEach(rows) { row in
                            contractRowView(row)
                        }
                    }
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s4)
                }

                newContractButton
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s5)
            }
        }
    }

    // MARK: Hero KPI card

    private func kpiHeroCard(_ s: ContractsAPI.Stats) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                .fill(palette.bgCard)
                .padding(1.5)

            VStack(alignment: .leading, spacing: 0) {
                Text("CONTRACT PORTFOLIO · 2026 YTD")
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.top, 22)
                    .padding(.leading, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                HStack(spacing: 0) {
                    kpiCell(label: "ACTIVE",
                            value: "\(s.active)",
                            valueStyle: .gradient,
                            trailingUnit: nil)
                    kpiDivider
                    // EUSO-2120 — committedLoads aggregate pending.
                    kpiCell(label: "COMMITTED",
                            value: "—",
                            valueStyle: .primary,
                            trailingUnit: "loads")
                    kpiDivider
                    kpiCell(label: "SPEND YTD",
                            value: formatMoney(s.totalValue),
                            valueStyle: .primary,
                            trailingUnit: nil)
                    kpiDivider
                    // EUSO-2120 — fillRate aggregate pending.
                    kpiCell(label: "FILL",
                            value: "—",
                            valueStyle: .success,
                            trailingUnit: nil)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
        }
        .frame(height: 92)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Contract portfolio. \(s.active) active. Spend year to date \(formatMoney(s.totalValue)). Committed loads + fill rate pending.")
    }

    private var kpiDivider: some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(width: 1, height: 38)
    }

    private enum KpiValueStyle { case gradient, primary, success }

    @ViewBuilder
    private func kpiCell(label: String,
                         value: String,
                         valueStyle: KpiValueStyle,
                         trailingUnit: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(0.4)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Group {
                    switch valueStyle {
                    case .gradient: Text(value).foregroundStyle(LinearGradient.diagonal)
                    case .primary:  Text(value).foregroundStyle(palette.textPrimary)
                    case .success:  Text(value).foregroundStyle(Brand.success)
                    }
                }
                .font(.system(size: 22, weight: .bold).monospacedDigit())
                if let trailingUnit {
                    Text(trailingUnit)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    // MARK: Filter row

    private func filterRow(rows: [ContractsAPI.ContractRow]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ContractFilter.allCases) { f in
                    filterChip(f, count: count(for: f, rows: rows))
                }
            }
            .padding(.horizontal, Space.s5)
        }
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [palette.bgPage.opacity(0), palette.bgPage],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 28)
            .allowsHitTesting(false)
        }
    }

    private func count(for filter: ContractFilter, rows: [ContractsAPI.ContractRow]) -> Int? {
        if filter == .all { return nil }
        if case .loaded(_, let allRows) = store.state {
            return store.applyClientFilterPublic(rows: allRows, filter: filter).count
        }
        return rows.count
    }

    private func filterChip(_ f: ContractFilter, count: Int?) -> some View {
        let isActive = (store.filter == f)
        let label: String = {
            if let c = count, c > 0 { return "\(f.label) · \(c)" }
            return f.label
        }()
        return Button(action: { tapFilter(f) }) {
            Text(label)
                .font(.system(size: 11, weight: isActive ? .bold : .semibold))
                .foregroundStyle(isActive ? Color.white : palette.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background {
                    if isActive {
                        Capsule().fill(LinearGradient.primary)
                    } else {
                        Capsule().fill(palette.bgCard)
                    }
                }
                .overlay {
                    if !isActive {
                        Capsule().strokeBorder(palette.borderFaint)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(f.label) filter")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func tapFilter(_ f: ContractFilter) {
        store.filter = f
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
        NotificationCenter.default.post(
            name: .eusoShipperContractsFilter,
            object: nil,
            userInfo: [
                "source": "217_ShipperContracts",
                "filter": f.rawValue,
                "shipperCompanyId": 1
            ]
        )
    }

    // MARK: Contract row (wireframe canon: tier rim · pill · lane · spec · 3-stat · fill bar)

    @ViewBuilder
    private func contractRowView(_ row: ContractsAPI.ContractRow) -> some View {
        let canon = canonStatus(for: row)
        Button(action: { tapRow(row) }) {
            HStack(spacing: 0) {
                tierRimShape(canon.tier)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        Text(rowDisplayId(row))
                            .font(EType.mono(.micro))
                            .tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Spacer()
                        statusPillView(canon.pillKind, legend: canon.pillLegend, width: canon.pillWidth)
                    }
                    .padding(.top, Space.s4)

                    Text(laneTitle(row))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .padding(.top, Space.s2 + 2)

                    Text(specLine(row))
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.top, 4)

                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        statCell(value: row.value > 0 ? formatMoney(row.value) : "—", unit: "/ load")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        // EUSO-2121 — filled-count not on row envelope.
                        statCell(value: "—", unit: "filled")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        // EUSO-2121 — vs-spot delta not on row envelope.
                        statCell(value: "—", unit: "vs spot")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, Space.s2 + 2)

                    fillRateBar(canon: canon)
                        .padding(.top, Space.s2 + 2)
                        .padding(.bottom, Space.s4)
                }
                .padding(.leading, Space.s4)
                .padding(.trailing, Space.s4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .contentShape(Rectangle())
        }
        .buttonStyle(ContractRowStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibility(row, canon: canon))
    }

    private struct CanonStatus {
        let tier: TierRim
        let pillKind: PillKind
        let pillLegend: String
        let pillWidth: CGFloat
        let fill: FillKind
        enum PillKind { case active, pilot, renewing, closed }
    }

    private func canonStatus(for row: ContractsAPI.ContractRow) -> CanonStatus {
        let s = (row.status ?? "").lowercased()
        let now = Date()
        let cutoff30d = now.addingTimeInterval(30 * 86400)
        let endDate = row.endDate.flatMap(parseDateYMD)

        // Renewing: active + endDate within 30 days
        if s == "active", let end = endDate, end >= now, end <= cutoff30d {
            let days = max(0, Int(end.timeIntervalSince(now) / 86400))
            return CanonStatus(tier: .paid,
                               pillKind: .renewing,
                               pillLegend: "RENEWING · \(days)D",
                               pillWidth: 100,
                               fill: .paid)
        }
        // Pilot: type contains "pilot" or notes contain "pilot"
        let t = (row.type ?? "").lowercased()
        let c = (row.customer ?? "").lowercased()
        if s == "active", t.contains("pilot") || c.contains("pilot") {
            return CanonStatus(tier: .warn,
                               pillKind: .pilot,
                               pillLegend: "PILOT",
                               pillWidth: 76,
                               fill: .warn)
        }
        switch s {
        case "active", "approved":
            return CanonStatus(tier: .gradient,
                               pillKind: .active,
                               pillLegend: "ACTIVE",
                               pillWidth: 84,
                               fill: .gradient)
        case "expired", "terminated":
            return CanonStatus(tier: .neutral,
                               pillKind: .closed,
                               pillLegend: s == "terminated" ? "TERMINATED" : "CLOSED",
                               pillWidth: s == "terminated" ? 100 : 84,
                               fill: .gradient)
        case "draft", "pending_review":
            return CanonStatus(tier: .neutral,
                               pillKind: .closed,
                               pillLegend: s == "draft" ? "DRAFT" : "PENDING",
                               pillWidth: 84,
                               fill: .gradient)
        default:
            return CanonStatus(tier: .neutral,
                               pillKind: .closed,
                               pillLegend: (row.status ?? "—").uppercased(),
                               pillWidth: 84,
                               fill: .gradient)
        }
    }

    private func rowDisplayId(_ row: ContractsAPI.ContractRow) -> String {
        let raw = row.number ?? row.id
        return raw.uppercased().hasPrefix("CTR-") ? raw : "CTR-\(raw)"
    }

    private func laneTitle(_ row: ContractsAPI.ContractRow) -> String {
        // EUSO-2121 — backend doesn't ship per-row lane / origin / destination.
        // Fall back to customer (notes column) which often carries the lane
        // hint, then to the contract number.
        if let customer = row.customer, !customer.isEmpty {
            return customer
        }
        return row.number ?? row.id
    }

    private func specLine(_ row: ContractsAPI.ContractRow) -> String {
        var parts: [String] = []
        if let t = row.type, !t.isEmpty {
            parts.append(t.replacingOccurrences(of: "_", with: " ").capitalized)
        }
        if let end = row.endDate, !end.isEmpty {
            parts.append("expires \(end)")
        }
        return parts.isEmpty ? "Contract details on tap" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func statCell(value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(palette.textPrimary)
            Text(unit)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func rowAccessibility(_ row: ContractsAPI.ContractRow, canon: CanonStatus) -> String {
        let pill = canon.pillLegend.replacingOccurrences(of: "·", with: ",")
        return "\(rowDisplayId(row)), \(pill), \(laneTitle(row)), \(specLine(row)), value \(row.value > 0 ? formatMoney(row.value) : "unknown")"
    }

    // MARK: Fill-rate progress bar

    @ViewBuilder
    private func fillRateBar(canon: CanonStatus) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Spacer()
                // EUSO-2121 — per-row fill rate not shipped.
                Text("— FILL")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            GeometryReader { geo in
                let trackWidth = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.borderFaint)
                        .frame(height: 6)
                    Capsule()
                        .fill(fillStyle(for: canon.fill))
                        .frame(width: trackWidth * 0, height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private func fillStyle(for kind: FillKind) -> AnyShapeStyle {
        switch kind {
        case .gradient: return AnyShapeStyle(LinearGradient.primary)
        case .warn:     return AnyShapeStyle(LinearGradient.warnGrad)
        case .paid:     return AnyShapeStyle(LinearGradient.paidGrad)
        }
    }

    // MARK: Tier rim shape

    @ViewBuilder
    private func tierRimShape(_ kind: TierRim) -> some View {
        switch kind {
        case .gradient:
            RoundedRectangle(cornerRadius: 1.5).fill(LinearGradient.diagonal)
        case .warn:
            RoundedRectangle(cornerRadius: 1.5).fill(LinearGradient.warnGrad)
        case .paid:
            RoundedRectangle(cornerRadius: 1.5).fill(LinearGradient.paidGrad)
        case .neutral:
            RoundedRectangle(cornerRadius: 1.5).fill(palette.textTertiary)
        }
    }

    // MARK: Status pills

    @ViewBuilder
    private func statusPillView(_ kind: CanonStatus.PillKind, legend: String, width: CGFloat) -> some View {
        switch kind {
        case .active:
            Text(legend)
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(.white)
                .frame(width: width, height: 20)
                .background(Capsule().fill(LinearGradient.primary))
        case .pilot:
            Text(legend)
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(.white)
                .frame(width: width, height: 20)
                .background(Capsule().fill(LinearGradient.warnGrad))
        case .renewing:
            Text(legend)
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(Brand.blue)
                .frame(width: width, height: 20)
                .background(Capsule().fill(Brand.blue.opacity(0.14)))
        case .closed:
            Text(legend)
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(palette.textSecondary)
                .frame(width: width, height: 20)
                .overlay(Capsule().strokeBorder(palette.textTertiary, lineWidth: 1))
                .background(Capsule().fill(palette.bgCard))
        }
    }

    // MARK: New contract proposal CTA

    private var newContractButton: some View {
        Button(action: tapNewContract) {
            Text("+ New contract proposal")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Capsule().fill(LinearGradient.primary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create a new contract proposal")
    }

    // MARK: Notification posts (§20.4)

    private func tapRow(_ row: ContractsAPI.ContractRow) {
        selectedId = row.id
        Task {
            detailLoading = true
            detail = try? await EusoTripAPI.shared.contracts.getContract(id: row.id)
            detailLoading = false
        }
        NotificationCenter.default.post(
            name: .eusoShipperContractsRow,
            object: nil,
            userInfo: [
                "source": "217_ShipperContracts",
                "contractId": row.id,
                "shipperCompanyId": 1
            ]
        )
    }

    private func tapNewContract() {
        NotificationCenter.default.post(
            name: .eusoShipperContractsCreate,
            object: nil,
            userInfo: [
                "source": "217_ShipperContracts",
                "shipperCompanyId": 1
            ]
        )
    }

    // MARK: Empty + error states

    private var emptyHero: some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "doc.text")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(LinearGradient.diagonal)
            Text("No contracts yet")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text("Once an RFP is awarded, the resulting carrier contract lands here. Master agreements can also be drafted directly from the +button below.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.s4)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: tapNewContract) {
                Text("+ New contract proposal")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s5)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var noFilteredResults: some View {
        Text("No contracts match this filter.")
            .font(EType.caption)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s4)
            .background(palette.bgCard.opacity(0.6))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func errorBanner(_ msg: String) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Contracts service offline")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                Task { await store.refresh() }
            } label: {
                Text("Retry")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func formatMoney(_ value: Double) -> String {
        let n = Int(value.rounded())
        if n >= 1_000_000 { return String(format: "$%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000    { return String(format: "$%.0fk", Double(n) / 1_000) }
        if n >= 1_000     { return String(format: "$%.1fk", Double(n) / 1_000) }
        if n == 0          { return "—" }
        return "$\(n)"
    }
}

// MARK: - Public client-side filter helper (so the chip count can recompute)

extension ShipperContractsStore {
    func applyClientFilterPublic(rows: [ContractsAPI.ContractRow], filter: ContractFilter) -> [ContractsAPI.ContractRow] {
        let now = Date()
        let cutoff30d = now.addingTimeInterval(30 * 86400)
        switch filter {
        case .all, .active:
            return rows
        case .pilot:
            return rows.filter { row in
                let t = (row.type ?? "").lowercased()
                let c = (row.customer ?? "").lowercased()
                return t.contains("pilot") || c.contains("pilot")
            }
        case .renewing:
            return rows.filter { row in
                guard let s = row.endDate, !s.isEmpty,
                      let d = parseDateYMD(s) else { return false }
                return d >= now && d <= cutoff30d
            }
        case .closed:
            return rows.filter { row in
                let s = (row.status ?? "").lowercased()
                return s == "expired" || s == "terminated"
            }
        }
    }
}

// MARK: - Press feedback

private struct ContractRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Identifiable wrapper for sheet binding

private struct IdentifiedContractId: Identifiable {
    let id: String
}

// MARK: - File-scoped paints (§19.2)

private extension LinearGradient {
    static let warnGrad = LinearGradient(
        colors: [Brand.hazmat, Color(hex: 0xFF7A00)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let paidGrad = LinearGradient(
        colors: [Brand.success, Color(hex: 0x00A07B)],
        startPoint: .top, endPoint: .bottom
    )
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// Filter chip tap (All / Active / Pilot / Renewing / Closed).
    static let eusoShipperContractsFilter = Notification.Name("eusoShipperContractsFilter")
    /// Contract row tap — opens the detail sheet.
    static let eusoShipperContractsRow    = Notification.Name("eusoShipperContractsRow")
    /// "+ New contract proposal" gradient pill tap.
    static let eusoShipperContractsCreate = Notification.Name("eusoShipperContractsCreate")
}

// MARK: - Detail sheet (preserved)

private struct ContractDetailSheet: View {
    let contractId: String
    @Binding var detail: ContractsAPI.ContractDetail?
    @Binding var loading: Bool
    let palette: Theme.Palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                if loading && detail == nil {
                    skeleton
                } else if let d = detail {
                    heroCard(d)
                    if let t = d.terms       { termsCard(t) }
                    if let p = d.pricing     { pricingCard(p) }
                    if let v = d.volume      { volumeCard(v) }
                    if let n = d.notes, !n.isEmpty { notesCard(n) }
                }
                Color.clear.frame(height: 48)
            }
            .padding(Space.s4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.bgPage.ignoresSafeArea())
    }

    private var skeleton: some View {
        VStack(spacing: Space.s3) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.3))
                    .frame(height: 80)
            }
        }
    }

    private func heroCard(_ d: ContractsAPI.ContractDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CONTRACT")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            Text(d.contractNumber ?? "—")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
            HStack(spacing: 6) {
                if let t = d.type, !t.isEmpty {
                    chip(label: t.replacingOccurrences(of: "_", with: " ").uppercased(),
                         color: Brand.info)
                }
                let style = sheetStatusStyle(d.status, palette: palette)
                chip(label: style.label.uppercased(), color: style.color)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func chip(label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.18)))
            .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 0.75))
    }

    private func termsCard(_ t: ContractsAPI.ContractDetail.Terms) -> some View {
        sectionCard(title: "TERMS") {
            VStack(spacing: 6) {
                kvRow("Effective", value: t.startDate?.isEmpty == false ? t.startDate! : "—")
                kvRow("Expires", value: t.endDate?.isEmpty == false ? t.endDate! : "—")
                kvRow("Auto-renew", value: t.autoRenew ? "Enabled" : "Disabled")
            }
        }
    }

    private func pricingCard(_ p: ContractsAPI.ContractDetail.Pricing) -> some View {
        sectionCard(title: "PRICING") {
            VStack(spacing: 6) {
                kvRow("Base rate", value: formatMoney(p.baseRate))
                kvRow("Rate type", value: p.rateType.isEmpty ? "—" : p.rateType.capitalized)
                kvRow("Fuel surcharge", value: p.fuelSurcharge.isEmpty ? "—" : p.fuelSurcharge.capitalized)
            }
        }
    }

    private func volumeCard(_ v: ContractsAPI.ContractDetail.Volume) -> some View {
        sectionCard(title: "VOLUME COMMITMENT") {
            VStack(spacing: 6) {
                kvRow("Commitment", value: v.commitment > 0 ? "\(v.commitment) loads" : "—")
                kvRow("Period", value: v.period.isEmpty ? "—" : v.period.capitalized)
            }
        }
    }

    private func notesCard(_ notes: String) -> some View {
        sectionCard(title: "NOTES") {
            Text(notes)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title)
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            content()
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func kvRow(_ key: String, value: String) -> some View {
        HStack {
            Text(key)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func formatMoney(_ value: Double) -> String {
        let n = Int(value.rounded())
        if n >= 1_000_000 { return String(format: "$%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000    { return String(format: "$%.0fk", Double(n) / 1_000) }
        if n >= 1_000     { return String(format: "$%.1fk", Double(n) / 1_000) }
        if n == 0          { return "—" }
        return "$\(n)"
    }
}

private struct SheetStatusStyle {
    let label: String
    let color: Color
}

private func sheetStatusStyle(_ status: String?, palette: Theme.Palette) -> SheetStatusStyle {
    switch (status ?? "").lowercased() {
    case "active":          return SheetStatusStyle(label: "Active",   color: Brand.success)
    case "draft":           return SheetStatusStyle(label: "Draft",    color: palette.textSecondary)
    case "pending_review":  return SheetStatusStyle(label: "Pending",  color: Brand.warning)
    case "approved":        return SheetStatusStyle(label: "Approved", color: Brand.info)
    case "expired":         return SheetStatusStyle(label: "Expired",  color: Brand.danger)
    case "terminated":      return SheetStatusStyle(label: "Terminated", color: Brand.danger)
    default:                 return SheetStatusStyle(label: status?.capitalized ?? "—", color: palette.textTertiary)
    }
}

// MARK: - Previews

#Preview("217 · Shipper Contracts · Dark") {
    ShipperContracts()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("217 · Shipper Contracts · Light") {
    ShipperContracts()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
