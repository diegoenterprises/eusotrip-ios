//
//  213_ShipperCatalystScorecard.swift
//  EusoTrip 2027 UI — Shipper · Catalyst Scorecards (parity-reconciled 2026-04-29)
//
//  PARITY AUDIT 2026-04-29 — reconciled to wireframe canon at
//  /02 Shipper/Code/213_ShipperCatalystScorecard.swift. Persona:
//  Diego Usoro / Eusorone Technologies (companyId 1) per §11. Row 1
//  is the §8 owner-op seam carrier Eusotrans LLC USDOT 3 194 882
//  (Michael Eusorone) when present in the merged set. The composite
//  formula is the §9.1 canon:
//
//    score = onTime · 0.5 + completion · 0.3 + log₁₀(loads+1)/log₁₀(50) · 0.2
//
//  Layout (top → bottom):
//    1. TopBar           ✦ SHIPPER · CATALYST SCORECARDS / "{N} CARRIERS · {M} FAVORITED"
//    2. Title block      Catalyst scorecards / "Eusorone Technologies · ranked by composite score"
//    3. IridescentHairline
//    4. KPI summary card AVG GRADE · ON-TIME AVG · FAVORITES (3-cell)
//    5. Filter chip row  All · Favorites · Tanker · Reefer · Flatbed (equipment placeholders pending EUSO-2111)
//    6. Period chip row  30 days · 90 days · 12 months (real period selector — drives ShipperAPI.SpendingPeriod)
//    7. Carrier list     single rounded card · monogram avatar + name + ★ + mono creds + 3-stat + 56pt grade badge
//    8. Tap-hint footer  "Tap a carrier to see trend & lane history" (LinearGradient.primary)
//    9. Formula footer   FORMULA + composite definition (mono caption)
//
//  Real wiring preserved: `shippers.getCatalystPerformance(period)`
//  + `shippers.getFavoriteCatalysts()` merged into one ranked list
//  via `ShipperCatalystScorecardStore`. Tap-row opens the detail sheet
//  with hero card + lifetime / period / why-this-grade breakdowns.
//
//  Backend gaps surfaced (logged in audit log, no fake data):
//    EUSO-2110 — `shippers.getCatalystPerformance` doesn't return MC
//                numbers / equipment type / region. Mono credentials
//                line falls back to "DOT {N}" only until backend
//                extends.
//    EUSO-2111 — Equipment-type filter chips (Tanker/Reefer/Flatbed)
//                have no backend-derived counts. They paint "—" until
//                an `equipmentType` join ships.
//
//  Doctrine refs: §2 LOADS-tab nav (handled by ContentView); §3
//  numbers-first copy ("12 CARRIERS · 4 FAVORITED" / "0.99" / "47");
//  §4.3 single iridescent hairline; §7 breathe density; §8 owner-op
//  seam (Eusotrans LLC row 1 when present); §9.1 composite formula;
//  §11 Diego canon; §17.2 chip + KPI tile width-locked grammar;
//  §19.2 file-scoped Star + monogram + grade badge helpers; §20.4 no
//  dead buttons (filter chip + period chip + row tap all post
//  notifications); §22.2 textTertiary counter color (informational).
//

import SwiftUI

// MARK: - Store (preserved verbatim — real backend wiring)

@MainActor
final class ShipperCatalystScorecardStore: ObservableObject {
    enum LoadState {
        case loading
        case empty
        case error(String)
        case loaded(merged: [MergedRow])
    }

    /// One row in the merged directory — period KPIs from
    /// `getCatalystPerformance` joined with all-time DOT from
    /// `getFavoriteCatalysts`.
    struct MergedRow: Identifiable, Hashable {
        let catalystId: String
        let name: String
        let dotNumber: String?
        let totalLoads: Int
        let delivered: Int
        let onTimeRate: Int
        let totalSpend: Double
        let lifetimeLoads: Int
        let lifetimeSpend: Double

        var id: String { catalystId }

        /// 0–1 composite per §9.1: onTime · 0.5 + completion · 0.3 +
        /// volume · 0.2 (log-scaled vs log₁₀(50)).
        var composite: Double {
            let completion = totalLoads > 0
                ? Double(delivered) / Double(totalLoads)
                : 0
            let onTime = Double(onTimeRate) / 100.0
            let volume = min(1.0, log10(Double(max(totalLoads, 1)) + 1) / log10(50.0))
            return onTime * 0.5 + completion * 0.3 + volume * 0.2
        }

        var compositeFormatted: String {
            String(format: "%.2f", composite)
        }

        /// 4-tier letter grade derived from composite. The §9.1 +
        /// wireframe binning: ≥0.96 A+ · ≥0.92 A · ≥0.88 A− · ≥0.84
        /// B+ · ≥0.78 B · else B−. (B− maps to goldHollow tier visually
        /// — anything below 0.78 in production logs an exception.)
        var letterGrade: String {
            switch composite {
            case 0.96...: return "A+"
            case 0.92..<0.96: return "A"
            case 0.88..<0.92: return "A−"
            case 0.84..<0.88: return "B+"
            case 0.78..<0.84: return "B"
            default: return "B−"
            }
        }

        /// Visual tier for the 56pt grade badge.
        var gradeTier: GradeTier {
            switch composite {
            case 0.96...: return .gradientHero
            case 0.88..<0.96: return .gradientHollow
            case 0.84..<0.88: return .goldHero
            default: return .goldHollow
            }
        }

        /// On-time formatted as "%5.1f%%" — but iOS backend ships an
        /// Int 0–100, so render plainly.
        var onTimeFormatted: String {
            totalLoads > 0 ? "\(onTimeRate)%" : "—"
        }

        var completionFormatted: String {
            guard totalLoads > 0 else { return "—" }
            let pct = Double(delivered) / Double(totalLoads) * 100.0
            return String(format: "%.0f%%", pct)
        }

        var loadsFormatted: String {
            totalLoads > 0 ? "\(totalLoads)" : "\(lifetimeLoads)"
        }

        /// Avatar tone derived from carrier name keywords. Eusotrans
        /// is the §8 owner-op seam → gradient; everything else falls
        /// through to keyword-driven palette.
        var avatarTone: AvatarTone {
            let n = name.lowercased()
            if n.contains("eusotrans") || n.contains("eusorone") { return .gradient }
            if n.contains("hazmat") || n.contains("petroleum")
                || n.contains("fuel")  || n.contains("tanker") { return .hazmat }
            if n.contains("cold") || n.contains("reefer")
                || n.contains("refriger") { return .info }
            if n.contains("cryogenic") || n.contains("nh3")
                || n.contains("nh₃") || n.contains("ammonia")
                || n.contains("escort") { return .escort }
            return .rail
        }

        var monogram: String {
            let words = name.split(separator: " ").prefix(2)
            let chars = words.compactMap { $0.first }
            let mono = String(chars).uppercased()
            return mono.isEmpty ? "EU" : mono
        }

        /// Falls back to "DOT {n}" when backend hasn't shipped MC /
        /// equipment / region yet (EUSO-2110).
        var credentialLine: String {
            if let dot = dotNumber, !dot.isEmpty {
                return "USDOT \(dot)"
            }
            return "USDOT pending"
        }
    }

    enum GradeTier { case gradientHero, gradientHollow, goldHero, goldHollow }
    enum AvatarTone { case gradient, hazmat, info, escort, rail }

    @Published private(set) var state: LoadState = .loading
    @Published private(set) var favoritesCount: Int = 0
    @Published var period: ShipperAPI.SpendingPeriod = .month {
        didSet {
            if oldValue != period { Task { await refresh() } }
        }
    }

    private let api: EusoTripAPI

    init(api: EusoTripAPI = .shared) {
        self.api = api
    }

    func refresh() async {
        if case .loaded = state {} else { state = .loading }
        do {
            async let perfTask = api.shipper.getCatalystPerformance(period: period)
            async let favTask  = api.shipper.getFavoriteCatalysts()
            let (perf, fav) = try await (perfTask, favTask)

            favoritesCount = fav.count

            let favById: [String: ShipperAPI.FavoriteCatalyst] = Dictionary(
                uniqueKeysWithValues: fav.map { ($0.catalystId, $0) }
            )

            var merged: [MergedRow] = perf.map { p in
                let f = favById[p.catalystId]
                return MergedRow(
                    catalystId:    p.catalystId,
                    name:          p.name,
                    dotNumber:     f?.dotNumber,
                    totalLoads:    p.totalLoads,
                    delivered:     p.delivered,
                    onTimeRate:    p.onTimeRate,
                    totalSpend:    p.totalSpend,
                    lifetimeLoads: f?.loadsCompleted ?? p.totalLoads,
                    lifetimeSpend: f?.totalSpend ?? p.totalSpend
                )
            }
            let perfIds = Set(perf.map(\.catalystId))
            for f in fav where !perfIds.contains(f.catalystId) {
                merged.append(MergedRow(
                    catalystId:    f.catalystId,
                    name:          f.name,
                    dotNumber:     f.dotNumber,
                    totalLoads:    0,
                    delivered:     0,
                    onTimeRate:    0,
                    totalSpend:    0,
                    lifetimeLoads: f.loadsCompleted,
                    lifetimeSpend: f.totalSpend
                ))
            }
            // §8 — pin the Eusotrans owner-op seam to row 1 when
            // present, then sort the rest by composite desc.
            merged.sort { lhs, rhs in
                let lIsHouse = lhs.name.lowercased().contains("eusotrans")
                let rIsHouse = rhs.name.lowercased().contains("eusotrans")
                if lIsHouse != rIsHouse { return lIsHouse }
                return lhs.composite > rhs.composite
            }

            state = merged.isEmpty ? .empty : .loaded(merged: merged)
        } catch {
            state = .error("Couldn't reach catalyst performance service.")
        }
    }
}

// MARK: - Filter chip

private enum ScorecardFilter: String, CaseIterable, Identifiable {
    case all, favorites, tanker, reefer, flatbed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:       return "All"
        case .favorites: return "Favorites"
        case .tanker:    return "Tanker"
        case .reefer:    return "Reefer"
        case .flatbed:   return "Flatbed"
        }
    }
    var withStar: Bool { self == .favorites }
}

// MARK: - Screen root

struct ShipperCatalystScorecard: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var store = ShipperCatalystScorecardStore()
    @State private var selected: ShipperCatalystScorecardStore.MergedRow?
    @State private var filter: ScorecardFilter = .all

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, Space.s5)
                titleBlock
                    .padding(.top, Space.s2)
                IridescentHairline()
                    .padding(.top, Space.s3)

                content
                    .padding(.top, Space.s3)

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(item: $selected) { row in
            CatalystDetailSheet(row: row)
                .environment(\.palette, palette)
                .presentationDragIndicator(.visible)
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.18),
            value: store.period
        )
    }

    // MARK: TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · CATALYST SCORECARDS")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text(counterEyebrow)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .accessibilityLabel(counterAccessibility)
        }
        .padding(.horizontal, Space.s5)
    }

    private var counterEyebrow: String {
        if case .loaded(let merged) = store.state {
            return "\(merged.count) CARRIERS · \(store.favoritesCount) FAVORITED"
        }
        return "—"
    }

    private var counterAccessibility: String {
        if case .loaded(let merged) = store.state {
            return "\(merged.count) carriers, \(store.favoritesCount) favorited"
        }
        return "Loading scorecards"
    }

    // MARK: Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Catalyst scorecards")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Eusorone Technologies · ranked by composite score")
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
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.3))
                        .frame(height: 80)
                }
            }
            .padding(.horizontal, Space.s5)
        case .empty:
            EusoEmptyState(
                systemImage: "rosette",
                title: "No carrier history yet",
                subtitle: "Once catalysts start delivering your loads, their scorecards land here — letter grades, on-time %, and composite ranking.",
                comingSoon: false
            )
            .padding(.horizontal, Space.s5)
        case .error(let msg):
            errorBanner(msg)
                .padding(.horizontal, Space.s5)
        case .loaded(let merged):
            VStack(alignment: .leading, spacing: 0) {
                kpiSummaryCard(merged)
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s3)

                filterChipRow(merged)
                    .padding(.top, Space.s3)

                periodChipRow
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s2)

                carrierList(filteredRows(merged))
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s4)

                formulaFooter
            }
        }
    }

    private func filteredRows(
        _ rows: [ShipperCatalystScorecardStore.MergedRow]
    ) -> [ShipperCatalystScorecardStore.MergedRow] {
        switch filter {
        case .all:        return rows
        case .favorites:  return rows.filter { $0.lifetimeLoads > 0 }
        case .tanker, .reefer, .flatbed:
            // EUSO-2111 — equipment classification not yet shipped from
            // backend. Filter falls back to all rows so the user still
            // sees data; the chip count stays "—" to signal the gap.
            return rows
        }
    }

    // MARK: KPI summary card (AVG GRADE · ON-TIME AVG · FAVORITES)

    private func kpiSummaryCard(
        _ merged: [ShipperCatalystScorecardStore.MergedRow]
    ) -> some View {
        let avgComposite: Double = {
            let active = merged.filter { $0.totalLoads > 0 }
            guard !active.isEmpty else { return 0 }
            return active.reduce(0.0) { $0 + $1.composite } / Double(active.count)
        }()
        let avgGradeLetter = letterGradeFor(composite: avgComposite)
        let avgOnTime: Int = {
            let active = merged.filter { $0.totalLoads > 0 }
            guard !active.isEmpty else { return 0 }
            return active.reduce(0) { $0 + $1.onTimeRate } / active.count
        }()

        return HStack(spacing: 0) {
            kpiCell(label: "AVG GRADE",
                    value: avgGradeLetter,
                    valueStyle: .gradient,
                    trail: String(format: "%.2f", avgComposite),
                    trailColor: palette.textSecondary,
                    showStar: false)
            kpiDivider
            kpiCell(label: "ON-TIME AVG",
                    value: "\(avgOnTime)%",
                    valueStyle: .neutral,
                    trail: avgOnTime > 0 ? "rolling \(periodWindowLabel)" : "—",
                    trailColor: palette.textSecondary,
                    showStar: false)
            kpiDivider
            kpiCell(label: "FAVORITES",
                    value: "\(store.favoritesCount)",
                    valueStyle: .neutral,
                    trail: "starred",
                    trailColor: palette.textSecondary,
                    showStar: true)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var periodWindowLabel: String {
        switch store.period {
        case .month:   return "30d"
        case .quarter: return "90d"
        case .year:    return "12mo"
        }
    }

    private func letterGradeFor(composite c: Double) -> String {
        switch c {
        case 0.96...: return "A+"
        case 0.92..<0.96: return "A"
        case 0.88..<0.92: return "A−"
        case 0.84..<0.88: return "B+"
        case 0.78..<0.84: return "B"
        default: return c > 0 ? "B−" : "—"
        }
    }

    private enum ValueStyle { case gradient, neutral }

    private func kpiCell(label: String,
                         value: String,
                         valueStyle: ValueStyle,
                         trail: String,
                         trailColor: Color,
                         showStar: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Group {
                    switch valueStyle {
                    case .gradient: Text(value).foregroundStyle(LinearGradient.diagonal)
                    case .neutral:  Text(value).foregroundStyle(palette.textPrimary)
                    }
                }
                .font(.system(size: 22, weight: .bold).monospacedDigit())
                if showStar {
                    Star().fill(Brand.hazmat).frame(width: 10, height: 10)
                }
                Text(trail)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(trailColor)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kpiDivider: some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(width: 1, height: 36)
            .padding(.horizontal, 4)
    }

    // MARK: Filter chip row (All / Favorites / Tanker / Reefer / Flatbed)

    private func filterChipRow(
        _ merged: [ShipperCatalystScorecardStore.MergedRow]
    ) -> some View {
        let allCount = merged.count
        let favCount = merged.filter { $0.lifetimeLoads > 0 }.count
        let chips: [(ScorecardFilter, String)] = [
            (.all,       "\(allCount)"),
            (.favorites, "\(favCount)"),
            (.tanker,    "—"),
            (.reefer,    "—"),
            (.flatbed,   "—")
        ]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(chips, id: \.0) { (kind, count) in
                    filterChip(kind: kind, count: count)
                }
                Color.clear.frame(width: 16, height: 1)
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

    @ViewBuilder
    private func filterChip(kind: ScorecardFilter, count: String) -> some View {
        let isActive = (kind == filter)
        let label = "\(kind.label) · \(count)"
        Button(action: { tapFilterChip(kind) }) {
            if isActive {
                HStack(spacing: 6) {
                    if kind.withStar {
                        Star().fill(.white).frame(width: 10, height: 10)
                    }
                    Text(label)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(LinearGradient.primary))
            } else {
                HStack(spacing: 6) {
                    if kind.withStar {
                        Star().fill(Brand.hazmat).frame(width: 10, height: 10)
                    }
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(palette.bgCard))
                .overlay(Capsule().strokeBorder(palette.borderSoft))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Period chip row (real period selector — drives the store)

    private var periodChipRow: some View {
        HStack(spacing: 6) {
            ForEach([ShipperAPI.SpendingPeriod.month, .quarter, .year], id: \.self) { p in
                periodChip(p)
            }
            Spacer(minLength: 0)
        }
    }

    private func periodChip(_ p: ShipperAPI.SpendingPeriod) -> some View {
        let isActive = (store.period == p)
        let label: String = {
            switch p {
            case .month:   return "30 days"
            case .quarter: return "90 days"
            case .year:    return "12 months"
            }
        }()
        return Button(action: { tapPeriod(p) }) {
            Text(label)
                .font(.system(size: 11, weight: isActive ? .bold : .semibold))
                .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(palette.textSecondary))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isActive
                              ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.92))
                              : AnyShapeStyle(palette.bgCard))
                )
                .overlay(Capsule().strokeBorder(palette.borderFaint))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Period: \(label)\(isActive ? ", selected" : "")")
    }

    // MARK: Carrier list — single rounded card with tap-hint footer

    private func carrierList(
        _ rows: [ShipperCatalystScorecardStore.MergedRow]
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, r in
                carrierRow(r)
                if idx < rows.count - 1 {
                    Rectangle()
                        .fill(palette.borderFaint)
                        .frame(height: 1)
                        .padding(.horizontal, Space.s4)
                }
            }
            // Footer prompt inside the card (wireframe canon).
            Text("Tap a carrier to see trend & lane history")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(LinearGradient.primary)
                .padding(.vertical, Space.s2)
                .frame(maxWidth: .infinity)
        }
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
    }

    private func carrierRow(_ c: ShipperCatalystScorecardStore.MergedRow) -> some View {
        Button(action: { selected = c }) {
            HStack(alignment: .top, spacing: Space.s3) {
                avatarBadge(monogram: c.monogram, tone: c.avatarTone)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(c.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                        if c.lifetimeLoads > 0 {
                            Star().fill(Brand.hazmat).frame(width: 10, height: 10)
                        }
                    }
                    Text(c.credentialLine)
                        .font(EType.mono(.caption))
                        .tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .padding(.bottom, 2)

                    HStack(spacing: Space.s5) {
                        statCell(label: "ON-TIME",     value: c.onTimeFormatted)
                        statCell(label: "COMPLETION",  value: c.completionFormatted)
                        statCell(label: "LOADS",       value: c.loadsFormatted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                gradeBadge(grade: c.letterGrade,
                           composite: c.compositeFormatted,
                           tier: c.gradeTier)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .contentShape(Rectangle())
        }
        .buttonStyle(CatalystRowButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(c.name)\(c.lifetimeLoads > 0 ? ", favorited" : ""), \(c.credentialLine), " +
            "on-time \(c.onTimeFormatted), completion \(c.completionFormatted), \(c.loadsFormatted) loads, " +
            "grade \(c.letterGrade), composite \(c.compositeFormatted)"
        )
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.micro).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private func avatarBadge(
        monogram: String,
        tone: ShipperCatalystScorecardStore.AvatarTone
    ) -> some View {
        switch tone {
        case .gradient:
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 44, height: 44)
                Text(monogram)
                    .font(.system(size: 14, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(.white)
            }
        case .hazmat:
            tintedAvatar(monogram: monogram,
                         fill:  Brand.hazmat.opacity(0.18),
                         text:  Brand.hazmat)
        case .info:
            tintedAvatar(monogram: monogram,
                         fill:  Brand.info.opacity(0.16),
                         text:  Brand.info)
        case .escort:
            tintedAvatar(monogram: monogram,
                         fill:  Brand.escort.opacity(0.14),
                         text:  Brand.escort)
        case .rail:
            tintedAvatar(monogram: monogram,
                         fill:  Brand.rail.opacity(0.16),
                         text:  Brand.rail)
        }
    }

    private func tintedAvatar(monogram: String, fill: Color, text: Color) -> some View {
        ZStack {
            Circle().fill(fill).frame(width: 44, height: 44)
            Text(monogram)
                .font(.system(size: 14, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(text)
        }
    }

    @ViewBuilder
    private func gradeBadge(
        grade: String,
        composite: String,
        tier: ShipperCatalystScorecardStore.GradeTier
    ) -> some View {
        let badgeShape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let goldFade = LinearGradient(
            colors: [Color(hex: 0xFFB100), Color(hex: 0xFFA726)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        ZStack {
            switch tier {
            case .gradientHero:
                badgeShape.fill(LinearGradient.diagonal)
                gradeText(grade, composite,
                          color: .white,
                          subColor: .white.opacity(0.85))
            case .gradientHollow:
                badgeShape.fill(palette.bgCard)
                badgeShape.strokeBorder(LinearGradient.primary, lineWidth: 2)
                gradeTextGradient(grade, composite,
                                  subColor: palette.textSecondary)
            case .goldHero:
                badgeShape.fill(goldFade)
                gradeText(grade, composite,
                          color: .white,
                          subColor: .white.opacity(0.85))
            case .goldHollow:
                badgeShape.fill(palette.bgCard)
                badgeShape.strokeBorder(goldFade, lineWidth: 2)
                gradeText(grade, composite,
                          color: Color(hex: 0xB27300),
                          subColor: palette.textSecondary)
            }
        }
        .frame(width: 56, height: 56)
    }

    private func gradeText(_ grade: String,
                           _ composite: String,
                           color: Color,
                           subColor: Color) -> some View {
        VStack(spacing: 1) {
            Text(grade)
                .font(.system(size: grade.count > 1 ? 20 : 22, weight: .heavy))
                .tracking(-0.4)
                .foregroundStyle(color)
                .monospacedDigit()
            Text(composite)
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(subColor)
        }
    }

    private func gradeTextGradient(_ grade: String,
                                   _ composite: String,
                                   subColor: Color) -> some View {
        VStack(spacing: 1) {
            Text(grade)
                .font(.system(size: grade.count > 1 ? 20 : 22, weight: .heavy))
                .tracking(-0.4)
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
            Text(composite)
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(subColor)
        }
    }

    // MARK: Formula footer

    private var formulaFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("FORMULA")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text("score = onTime · 0.5 + completion · 0.3 + log₁₀(loads+1)/log₁₀(50) · 0.2")
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s2)
    }

    // MARK: Error banner

    private func errorBanner(_ msg: String) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Scorecards unavailable")
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

    // MARK: - Notification posts (§20.4)

    private func tapFilterChip(_ kind: ScorecardFilter) {
        withAnimation(.easeOut(duration: 0.18)) { filter = kind }
        // observability post — telemetry only; real local effect is the
        // filter mutation above which drives the row predicate.
        NotificationCenter.default.post(
            name: .eusoShipperScorecardFilter,
            object: nil,
            userInfo: [
                "source": "213_ShipperCatalystScorecard",
                "filter": kind.rawValue,
                "shipperCompanyId": 1
            ]
        )
    }

    private func tapPeriod(_ p: ShipperAPI.SpendingPeriod) {
        store.period = p
        // observability post — telemetry only; real local effect is the
        // store.period mutation above which triggers re-fetch.
        NotificationCenter.default.post(
            name: .eusoShipperScorecardPeriod,
            object: nil,
            userInfo: [
                "source": "213_ShipperCatalystScorecard",
                "period": String(describing: p),
                "shipperCompanyId": 1
            ]
        )
    }
}

// MARK: - Press feedback

private struct CatalystRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Star (file-scoped per §19.2 — 5-point glyph, scales to bounds)

private struct Star: Shape {
    func path(in rect: CGRect) -> Path {
        let pts: [CGPoint] = [
            CGPoint(x: 5,   y: 0),
            CGPoint(x: 6.2, y: 3.6),
            CGPoint(x: 10,  y: 3.6),
            CGPoint(x: 7,   y: 5.8),
            CGPoint(x: 8.2, y: 9.4),
            CGPoint(x: 5,   y: 7.2),
            CGPoint(x: 1.8, y: 9.4),
            CGPoint(x: 3,   y: 5.8),
            CGPoint(x: 0,   y: 3.6),
            CGPoint(x: 3.8, y: 3.6),
        ]
        let sx = rect.width / 10.0
        let sy = rect.height / 9.4
        var path = Path()
        for (i, p) in pts.enumerated() {
            let x = rect.minX + p.x * sx
            let y = rect.minY + p.y * sy
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else      { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// Filter chip tap — All / Favorites / Tanker / Reefer / Flatbed.
    static let eusoShipperScorecardFilter = Notification.Name("eusoShipperScorecardFilter")
    /// Period chip tap — month / quarter / year (drives the store).
    static let eusoShipperScorecardPeriod = Notification.Name("eusoShipperScorecardPeriod")
}

// MARK: - Detail sheet (preserved — opens when a row is tapped)

private struct CatalystDetailSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let row: ShipperCatalystScorecardStore.MergedRow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                heroCard
                lifetimeCard
                periodCard
                whyThisGradeCard
                Color.clear.frame(height: 48)
            }
            .padding(Space.s4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.bgPage.ignoresSafeArea())
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.letterGrade)
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(row.compositeFormatted)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
            }
            Text(row.name)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text(row.credentialLine)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(LinearGradient(
                    colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.22)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var periodCard: some View {
        sectionCard(title: "THIS WINDOW") {
            VStack(spacing: 6) {
                kvRow("Loads", value: row.totalLoads > 0 ? "\(row.totalLoads)" : "—")
                kvRow("Delivered", value: row.totalLoads > 0 ? "\(row.delivered)" : "—")
                kvRow("On-time rate", value: row.onTimeFormatted)
                kvRow("Total spend", value: row.totalSpend > 0 ? formatMoney(row.totalSpend) : "—")
            }
        }
    }

    private var lifetimeCard: some View {
        sectionCard(title: "LIFETIME") {
            VStack(spacing: 6) {
                kvRow("Loads completed", value: "\(row.lifetimeLoads)")
                kvRow("Lifetime spend", value: formatMoney(row.lifetimeSpend))
            }
        }
    }

    private var whyThisGradeCard: some View {
        sectionCard(title: "WHY THIS GRADE") {
            VStack(alignment: .leading, spacing: 6) {
                Text("score = onTime · 0.5 + completion · 0.3 + log₁₀(loads+1)/log₁₀(50) · 0.2")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("≥0.96 A+ · ≥0.92 A · ≥0.88 A− · ≥0.84 B+ · ≥0.78 B · else B−")
                    .font(EType.micro).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
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
        }
    }

    private func formatMoney(_ value: Double) -> String {
        let n = Int(value.rounded())
        if n >= 1_000_000 { return String(format: "$%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000    { return String(format: "$%.0fk", Double(n) / 1_000) }
        return "$\(n)"
    }
}

// MARK: - Previews

#Preview("213 · Catalyst Scorecards · Dark") {
    ShipperCatalystScorecard()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("213 · Catalyst Scorecards · Light") {
    ShipperCatalystScorecard()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
