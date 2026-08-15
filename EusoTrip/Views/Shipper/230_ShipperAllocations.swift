//
//  230_ShipperWeeklyAllocations.swift
//  EusoTrip 2027 UI — Shipper · Allocations (live-bound 2026-06-06)
//
//  ZERO-FABRICATION REBUILD 2026-06-06 — the prior file painted a
//  `canonRows` array of invented lanes (Houston→Dallas / KC→Omaha),
//  carriers (Eusotrans LLC · Michael Eusorone · MC-306), rates
//  ($1,840 / $3,180) and a §11 "Eusorone Technologies · MATRIX-50"
//  persona. ALL of it is removed. This board now reads the SAME live
//  store as its sibling 229 — `ShipperAllocationsStore().load()` →
//  `allocationTracker.getDailyDashboard` — and computes the hero KPI
//  quartet (ALLOCATED · AT-RISK · FILL · AVG RATE), filter-chip
//  counts and the allocation rows off the real `DailyContractRow`
//  envelope. No `?? <invented value>` anywhere — missing values
//  render honest "—". Empty / loading / error states are explicit.
//
//  The visual layout / chrome / nav is preserved verbatim from the
//  wireframe canon: TopBar quartet counter, 34pt title, iridescent
//  hairline, gradient-rim hero KPI card, filter chip row, 3pt tier-
//  rim allocation rows with status pill + 3-stat line + capacity bar,
//  and the "+ Allocate" gradient pill CTA. Only the data source
//  changed — every business value is now sourced from the named proc.
//
//  Mode mapping (petroleum / refined-products daily nomination, the
//  real shape of the allocation_tracker proc):
//    • "ALLOCATED" hero / row count  = contracts.count
//    • "AT-RISK"                     = contracts whose derived phase is
//                                      at-risk or behind
//    • "FILL"                        = summaryBar.fulfillmentPercent
//    • "AVG RATE"                    = mean ratePerBbl across contracts
//                                      ("$X / bbl"), "—" when none post a rate
//    • row lane title                = contractName (or "Contract #id")
//    • row spec line                 = buyer · product · loads-needed
//    • row 3-stat                    = rate / coverage(del÷nom) / remaining
//    • capacity bar fill             = deliveredBbl ÷ nominatedBbl
//
//  Doctrine refs: §2 LOADS-tab nav (handled by ContentView); §3
//  numbers-first copy; §4.3 single iridescent hairline; §15.2 status-
//  aware tier rim; §16 hero-rim KPI quartet; §16.2 gradient pill CTA;
//  §17.2 status pill grammar; §19.2 file-scoped warnGrad / dangerGrad;
//  §20.4 no dead buttons; §22.2 Brand.danger counter when at-risk > 0.
//

import SwiftUI

// MARK: - Row view model (derived from the live DailyContractRow)

private struct AllocRow: Identifiable {
    let id: Int
    let contractId: Int
    let pillKind: PillKind
    let pillLegend: String
    let pillWidth: CGFloat
    let tierRim: TierRim
    let lane: String
    let specLine: String
    let stats: [Stat]
    let fillRate: CGFloat
    let fillKind: FillKind
    let fillLegend: String
    let timing: TimingChip

    enum PillKind { case allocated, atRisk, reallocate, delivered }
    enum TierRim { case gradient, danger, warn, neutral }
    enum FillKind { case gradient, warn, danger }
    struct TimingChip { let text: String; let kind: Kind; enum Kind { case neutral, warn, danger } }
    struct Stat: Identifiable {
        let id = UUID()
        let value: String
        let unit: String
        var color: ValueColor = .primary
        enum ValueColor { case primary, success, warn, danger }
    }
}

// MARK: - Filter

private enum AllocFilter: String, CaseIterable, Identifiable {
    case all
    case allocated
    case atRisk
    case reallocate
    case closed

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:        return "All"
        case .allocated:  return "Allocated"
        case .atRisk:     return "At-Risk"
        case .reallocate: return "Reallocate"
        case .closed:     return "Closed"
        }
    }
}

// MARK: - Derivation
//
// Maps the live `DailyContractRow` onto the wireframe row grammar.
// Phase is derived the SAME way the sibling 229 derives it
// (`ContractStatusStyle.from`) so both boards agree on what's at-risk:
// server status wins; otherwise the delivered÷nominated ratio decides.

private enum AllocPhase { case complete, onTrack, atRisk, behind, pending }

private func derivePhase(_ c: AllocationsAPI.DailyContractRow) -> AllocPhase {
    let s = (c.status ?? "").lowercased()
    if s == "complete" { return .complete }
    let ratio = c.nominatedBbl > 0 ? c.deliveredBbl / c.nominatedBbl : 0
    if ratio >= 0.95 { return .complete }
    if ratio >= 0.70 { return .onTrack }
    if ratio >= 0.40 { return .atRisk }
    if c.nominatedBbl > 0 { return .behind }
    return .pending
}

private func bblShort(_ v: Double) -> String {
    if v >= 10_000 { return String(format: "%.1fK bbl", v / 1000) }
    return String(format: "%.0f bbl", v)
}

private func makeRow(_ c: AllocationsAPI.DailyContractRow) -> AllocRow {
    let phase = derivePhase(c)

    let coveredPct: Int = c.nominatedBbl > 0
        ? Int((c.deliveredBbl / c.nominatedBbl) * 100.0)
        : 0

    let pillKind: AllocRow.PillKind
    let tierRim: AllocRow.TierRim
    let fillKind: AllocRow.FillKind
    let pillLegendLead: String
    switch phase {
    case .complete:
        pillKind = .delivered; tierRim = .neutral; fillKind = .gradient; pillLegendLead = "COMPLETE"
    case .onTrack:
        pillKind = .allocated; tierRim = .gradient; fillKind = .gradient; pillLegendLead = "ON TRACK"
    case .atRisk:
        pillKind = .atRisk;    tierRim = .warn;     fillKind = .warn;     pillLegendLead = "AT-RISK"
    case .behind:
        pillKind = .atRisk;    tierRim = .danger;   fillKind = .danger;   pillLegendLead = "BEHIND"
    case .pending:
        pillKind = .allocated; tierRim = .gradient; fillKind = .gradient; pillLegendLead = "PENDING"
    }

    // Spec line: buyer · product · loads-needed. Each segment only
    // appears when its source field is present — no invented filler.
    var specParts: [String] = []
    if let buyer = c.buyerName?.trimmingCharacters(in: .whitespaces), !buyer.isEmpty { specParts.append(buyer) }
    if let product = c.product?.trimmingCharacters(in: .whitespaces), !product.isEmpty { specParts.append(product) }
    if c.loadsNeeded > 0 { specParts.append("\(c.loadsNeeded) loads needed") }
    let specLine = specParts.isEmpty ? "—" : specParts.joined(separator: " · ")

    // Rate stat — honest "—" when the contract carries no posted rate.
    let rateStat: AllocRow.Stat
    if let raw = c.ratePerBbl?.trimmingCharacters(in: .whitespaces),
       !raw.isEmpty, let r = Double(raw) {
        rateStat = .init(value: String(format: "$%.2f", r), unit: "/ bbl")
    } else {
        rateStat = .init(value: "—", unit: "/ bbl")
    }

    let fillRate = c.nominatedBbl > 0
        ? CGFloat(min(c.deliveredBbl / c.nominatedBbl, 1.0))
        : 0

    // Timing chip mirrors the real fulfillment posture.
    let timing: AllocRow.TimingChip
    switch phase {
    case .behind:
        timing = .init(text: "BEHIND · \(bblShort(c.remainingBbl)) LEFT", kind: .danger)
    case .atRisk:
        timing = .init(text: "AT-RISK · \(bblShort(c.remainingBbl)) LEFT", kind: .warn)
    case .complete:
        timing = .init(text: "DELIVERED · \(coveredPct)%", kind: .neutral)
    default:
        timing = .init(text: c.remainingBbl > 0 ? "OPEN · \(bblShort(c.remainingBbl)) LEFT" : "FULFILLED",
                       kind: .neutral)
    }

    return AllocRow(
        id: c.contractId,
        contractId: c.contractId,
        pillKind: pillKind,
        pillLegend: "\(pillLegendLead) · \(coveredPct)%",
        pillWidth: 120,
        tierRim: tierRim,
        lane: c.contractName?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? "Contract #\(c.contractId)",
        specLine: specLine,
        stats: [
            rateStat,
            .init(value: "\(coveredPct)%", unit: "covered"),
            .init(value: bblShort(c.remainingBbl), unit: "remaining",
                  color: c.remainingBbl > 0 ? .warn : .success)
        ],
        fillRate: fillRate,
        fillKind: fillKind,
        fillLegend: "\(bblShort(c.deliveredBbl)) / \(bblShort(c.nominatedBbl))",
        timing: timing
    )
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Screen root

struct ShipperWeeklyAllocations: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    @StateObject private var store = ShipperAllocationsStore()
    @State private var filter: AllocFilter = .all

    /// Live rows derived from the loaded dashboard. Empty until the
    /// proc resolves — no anchor / canon fallback.
    private var liveRows: [AllocRow] {
        guard case .loaded(let d) = store.phase else { return [] }
        return d.contracts.map(makeRow)
    }

    private var isLoaded: Bool {
        if case .loaded = store.phase { return true }
        return false
    }

    private var loadError: String? {
        if case .error(let m) = store.phase { return m }
        return nil
    }

    /// Honest account subline — the session user's name / company,
    /// NEVER the founder persona. Falls back to a neutral "—" label.
    private var accountSubline: String {
        let who = session.user?.name?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        if let who { return "\(who) · this week" }
        return "—"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, Space.s5)
                titleBlock
                    .padding(.top, Space.s2)
                IridescentHairline()
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s5)

                kpiHeroCard
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s3)

                filterRow
                    .padding(.top, Space.s5)

                contentSection
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s4)

                allocateButton
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s5)

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.load() }
        .eusoRefreshable { await store.load() }
    }

    // MARK: Content (loading / error / empty / rows)

    @ViewBuilder
    private var contentSection: some View {
        switch store.phase {
        case .idle, .loading:
            loadingCard
        case .error(let m):
            errorCard(m)
        case .loaded:
            let rows = filtered()
            if liveRows.isEmpty {
                EusoEmptyState(
                    systemImage: "fuelpump",
                    title: "No allocations this week",
                    subtitle: "No daily-nomination contracts are open for your account yet. Tap “+ Allocate” to start one."
                )
            } else if rows.isEmpty {
                noMatchCard
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(rows) { row in
                        allocRowView(row)
                    }
                }
            }
        }
    }

    private var loadingCard: some View {
        HStack(spacing: Space.s2) {
            ProgressView()
            Text("Loading allocations…")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer()
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func errorCard(_ m: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Brand.warning)
            Text(m)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Button("Retry") { Task { await store.load() } }
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Brand.info)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: TopBar

    private var topBar: some View {
        let rows = liveRows
        let atRisk = rows.filter { $0.pillKind == .atRisk }.count
        let counter: String = {
            guard isLoaded else { return loadError != nil ? "UNAVAILABLE" : "LOADING…" }
            return "\(rows.count) ALLOCATED · \(atRisk) AT-RISK"
        }()
        return HStack(alignment: .firstTextBaseline) {
            EusoTripEyebrow(verbatim: "SHIPPER · ALLOCATIONS")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text(counter)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(atRisk > 0 ? Brand.danger : palette.textTertiary)
                .accessibilityLabel(isLoaded
                    ? "\(rows.count) allocated, \(atRisk) at risk"
                    : "Allocations \(counter.lowercased())")
        }
        .padding(.horizontal, Space.s3)
    }

    // MARK: Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Allocations")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(palette.textPrimary)
            Text(accountSubline)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3)
    }

    // MARK: KPI hero card

    private var kpiHeroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                .fill(palette.bgCard)
                .padding(1.5)

            VStack(alignment: .leading, spacing: 0) {
                Text("ALLOCATION LEDGER · \(ledgerLabel)")
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.top, 22)
                    .padding(.leading, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    kpiCell(label: "ALLOCATED", value: allocatedValue,
                            valueStyle: .gradient, trailingUnit: nil)
                    kpiDivider
                    kpiCell(label: "AT-RISK",
                            value: atRiskValue,
                            valueStyle: .danger, trailingUnit: nil)
                    kpiDivider
                    kpiCell(label: "FILL", value: fillValue,
                            valueStyle: .primary, trailingUnit: nil)
                    kpiDivider
                    kpiCell(label: "AVG RATE", value: avgRateValue,
                            valueStyle: .success, trailingUnit: nil)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
        }
        .frame(height: 92)
    }

    /// Ledger label sourced from the loaded dashboard's date, not a
    /// hardcoded week number.
    private var ledgerLabel: String {
        if case .loaded(let d) = store.phase { return d.date }
        return "—"
    }

    private var allocatedValue: String {
        isLoaded ? "\(liveRows.count)" : "—"
    }

    private var atRiskValue: String {
        guard isLoaded else { return "—" }
        return "\(liveRows.filter { $0.pillKind == .atRisk }.count)"
    }

    /// FILL = the server-computed fulfillment percent on the summary
    /// bar. Honest "—" before the dashboard resolves.
    private var fillValue: String {
        guard case .loaded(let d) = store.phase else { return "—" }
        return "\(d.summaryBar.fulfillmentPercent)%"
    }

    /// AVG RATE = mean of the contracts' posted ratePerBbl. "—" when
    /// no contract posts a rate (no invented fallback number).
    private var avgRateValue: String {
        guard case .loaded(let d) = store.phase else { return "—" }
        let rates = d.contracts.compactMap { c -> Double? in
            guard let raw = c.ratePerBbl?.trimmingCharacters(in: .whitespaces),
                  !raw.isEmpty else { return nil }
            return Double(raw)
        }
        guard !rates.isEmpty else { return "—" }
        let avg = rates.reduce(0, +) / Double(rates.count)
        return String(format: "$%.2f", avg)
    }

    private var kpiDivider: some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(width: 1, height: 38)
    }

    private enum KpiValueStyle { case gradient, primary, danger, success }

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
                    case .danger:   Text(value).foregroundStyle(Brand.danger)
                    case .success:  Text(value).foregroundStyle(Brand.success)
                    }
                }
                .font(.system(size: 22, weight: .bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AllocFilter.allCases) { f in
                    filterChip(f, count: count(for: f))
                }
            }
            .padding(.horizontal, Space.s3)
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

    private func count(for filter: AllocFilter) -> Int? {
        guard isLoaded else { return nil }
        let rows = liveRows
        switch filter {
        case .all:        return nil
        case .allocated:  return rows.filter { $0.pillKind == .allocated }.count
        case .atRisk:     return rows.filter { $0.pillKind == .atRisk }.count
        case .reallocate: return rows.filter { $0.pillKind == .atRisk }.count
        case .closed:     return rows.filter { $0.pillKind == .delivered }.count
        }
    }

    private func filterChip(_ f: AllocFilter, count: Int?) -> some View {
        let isActive = (filter == f)
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

    private func tapFilter(_ f: AllocFilter) {
        filter = f
        NotificationCenter.default.post(
            name: .eusoShipperAllocFilter,
            object: nil,
            userInfo: [
                "source": "230_ShipperWeeklyAllocations",
                "filter": f.rawValue
            ]
        )
    }

    private func filtered() -> [AllocRow] {
        let rows = liveRows
        switch filter {
        case .all:
            return rows
        case .allocated:
            return rows.filter { $0.pillKind == .allocated }
        case .atRisk, .reallocate:
            return rows.filter { $0.pillKind == .atRisk }
        case .closed:
            return rows.filter { $0.pillKind == .delivered }
        }
    }

    // MARK: Allocation row

    @ViewBuilder
    private func allocRowView(_ row: AllocRow) -> some View {
        Button(action: { tapRow(row) }) {
            HStack(spacing: 0) {
                tierRimShape(row.tierRim)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        Text("CONTRACT #\(row.contractId)")
                            .font(EType.mono(.micro))
                            .tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Spacer()
                        statusPillView(row)
                    }
                    .padding(.top, Space.s4)

                    Text(row.lane)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .padding(.top, Space.s2 + 2)

                    Text(row.specLine)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.top, 4)

                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        ForEach(row.stats) { stat in
                            statCell(stat)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, Space.s2 + 2)

                    capacityBar(row)
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
        .buttonStyle(AllocRowStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibility(row))
    }

    private func rowAccessibility(_ row: AllocRow) -> String {
        let pill = row.pillLegend.replacingOccurrences(of: "·", with: ",")
        return "Contract \(row.contractId), \(pill), \(row.lane), \(row.specLine), \(row.fillLegend)"
    }

    @ViewBuilder
    private func tierRimShape(_ kind: AllocRow.TierRim) -> some View {
        switch kind {
        case .gradient: RoundedRectangle(cornerRadius: 1.5).fill(LinearGradient.diagonal)
        case .danger:   RoundedRectangle(cornerRadius: 1.5).fill(LinearGradient.allocDangerGrad)
        case .warn:     RoundedRectangle(cornerRadius: 1.5).fill(LinearGradient.allocWarnGrad)
        case .neutral:  RoundedRectangle(cornerRadius: 1.5).fill(palette.textTertiary)
        }
    }

    @ViewBuilder
    private func statusPillView(_ row: AllocRow) -> some View {
        switch row.pillKind {
        case .allocated:
            Text(row.pillLegend)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(.white)
                .frame(width: row.pillWidth, height: 20)
                .background(Capsule().fill(LinearGradient.primary))
        case .atRisk:
            Text(row.pillLegend)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(.white)
                .frame(width: row.pillWidth, height: 20)
                .background(Capsule().fill(LinearGradient.allocDangerGrad))
        case .reallocate:
            Text(row.pillLegend)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(Brand.danger)
                .frame(width: row.pillWidth, height: 20)
                .overlay(Capsule().strokeBorder(Brand.danger, lineWidth: 1))
                .background(Capsule().fill(palette.bgCard))
        case .delivered:
            Text(row.pillLegend)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(.white)
                .frame(width: row.pillWidth, height: 20)
                .background(Capsule().fill(Brand.success))
        }
    }

    @ViewBuilder
    private func statCell(_ stat: AllocRow.Stat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(stat.value)
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(statColor(stat.color))
            Text(stat.unit)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func statColor(_ c: AllocRow.Stat.ValueColor) -> Color {
        switch c {
        case .primary: return palette.textPrimary
        case .success: return Brand.success
        case .warn:    return Brand.warning
        case .danger:  return Brand.danger
        }
    }

    @ViewBuilder
    private func capacityBar(_ row: AllocRow) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                timingChipView(row.timing)
                Spacer()
                Text(row.fillLegend)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(legendColor(for: row))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.borderFaint)
                        .frame(height: 6)
                    Capsule()
                        .fill(fillStyle(for: row.fillKind))
                        .frame(width: geo.size.width * row.fillRate, height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private func legendColor(for row: AllocRow) -> Color {
        switch row.fillKind {
        case .gradient: return palette.textSecondary
        case .warn:     return Brand.warning
        case .danger:   return Brand.danger
        }
    }

    private func fillStyle(for kind: AllocRow.FillKind) -> AnyShapeStyle {
        switch kind {
        case .gradient: return AnyShapeStyle(LinearGradient.primary)
        case .warn:     return AnyShapeStyle(LinearGradient.allocWarnGrad)
        case .danger:   return AnyShapeStyle(LinearGradient.allocDangerGrad)
        }
    }

    @ViewBuilder
    private func timingChipView(_ chip: AllocRow.TimingChip) -> some View {
        let (fg, bg): (Color, Color) = {
            switch chip.kind {
            case .neutral: return (palette.textTertiary, palette.bgCardSoft)
            case .warn:    return (Brand.warning, Brand.warning.opacity(0.15))
            case .danger:  return (Brand.danger, Brand.danger.opacity(0.15))
            }
        }()
        Text(chip.text)
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.4)
            .foregroundStyle(fg)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(bg))
    }

    // MARK: + Allocate CTA

    private var allocateButton: some View {
        Button(action: tapAllocate) {
            Text("+ Allocate")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.primary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Allocate new contract")
    }

    // MARK: Notification posts + nav

    private func tapRow(_ row: AllocRow) {
        NotificationCenter.default.post(
            name: .eusoShipperAllocRow,
            object: nil,
            userInfo: [
                "source": "230_ShipperWeeklyAllocations",
                "contractId": row.contractId
            ]
        )
        // Native nav into the canonical Allocations board (229b) where
        // the per-contract detail + create flow live.
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap, object: nil,
            userInfo: ["screenId": "230b"]
        )
    }

    private func tapAllocate() {
        NotificationCenter.default.post(
            name: .eusoShipperAllocCreate,
            object: nil,
            userInfo: ["source": "230_ShipperWeeklyAllocations"]
        )
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap, object: nil,
            userInfo: ["screenId": "230b"]
        )
    }

    // MARK: No-match card

    private var noMatchCard: some View {
        Text("No allocations match this filter.")
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
}

// MARK: - Press feedback

private struct AllocRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - File-scoped paint extensions (§19.2 · named to avoid clashes)

private extension LinearGradient {
    static let allocWarnGrad = LinearGradient(
        colors: [Brand.hazmat, Color(hex: 0xFF7A00)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let allocDangerGrad = LinearGradient(
        colors: [Brand.danger, Color(hex: 0xC62828)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// Filter chip tap (All / Allocated / At-Risk / Reallocate / Closed).
    static let eusoShipperAllocFilter = Notification.Name("eusoShipperAllocFilter")
    /// Allocation row tap — opens detail.
    static let eusoShipperAllocRow    = Notification.Name("eusoShipperAllocRow")
    /// "+ Allocate" gradient pill tap.
    static let eusoShipperAllocCreate = Notification.Name("eusoShipperAllocCreate")
}

// MARK: - Previews

#Preview("230 · Allocations · Dark") {
    ShipperWeeklyAllocations()
        .environmentObject(EusoTripSession())
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("230 · Allocations · Light") {
    ShipperWeeklyAllocations()
        .environmentObject(EusoTripSession())
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
