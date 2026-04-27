//
//  210_ShipperAnalyticsDeepDive.swift
//  EusoTrip — Shipper · Analytics Deep-Dive (brick 210).
//
//  Eleventh brick on the Shipper role track (200s). Shipped in the
//  128th eusotrip-killers firing per the 127th firing's hand-off
//  recommendation: "210_ShipperAnalyticsDeepDive — extended analytics
//  on top of `shippers.getSpendingAnalytics` with cohort drill-downs
//  (carrier, lane, equipment-type breakdowns). Reuses existing
//  ShipperSpendingAnalyticsStore."
//
//  Pixel-doctrine compliant per EUSOTRIP2027GOLD §1 (LinearGradient.
//  diagonal accent — no flat Brand.info / Brand.blue fills, no
//  .tint(.blue)), §2 (no Toggle widgets on this brick — no
//  GradientToggleStyle obligation), §4 (tokenized spacing / radius /
//  type — Space.s*, Radius.*, EType.*), §5 (palette semantic only —
//  no hard-coded Color.white / Color.black / Color.gray fills), §7
//  (`AnyShapeStyle` wrapping for ternary shape-styles in fill /
//  stroke), §10 (previews compile in isolation — `.task` doesn't run
//  in the preview canvas, so both stores stay in `.loading` and never
//  hit the network).
//
//  Cohort B day-1 — fully dynamic (SKILL.md §3 "no-mock" pledge ·
//  2027 motivation directive "no fake data, 1000% dynamic"):
//
//    • ZERO new API or store code added this firing. Reuses the two
//      stores instantiated for brick 207_ShipperReports — same
//      backend procedures, different lens. Where 207 surfaces a flat
//      KPI strip + ranked leaderboard, 210 pivots the same data into
//      an analytics drill-down: efficiency tiles, share-of-spend
//      visualization, on-time-rate distribution buckets, and
//      derived-insight callouts.
//
//    • Spend KPIs → `ShipperSpendingAnalyticsStore` (LiveDataStores
//      `:3594`) → `shippers.getSpendingAnalytics` (input
//      `{ period: "month"|"quarter"|"year" }`). MCP-verified in
//      127th firing at `frontend/server/routers/shippers.ts:470`.
//
//    • Carrier breakdown → `ShipperCatalystPerformanceStore`
//      (LiveDataStores `:3627`) → `shippers.getCatalystPerformance`
//      (same input shape). MCP-verified in 127th firing at
//      `frontend/server/routers/shippers.ts:433`.
//
//    • The screen owns the canonical `SpendingPeriod` and propagates
//      to BOTH stores via `setPeriod` whenever the chip changes, so
//      every lens on the page describes the same time window.
//      Switching the period flips both stores to `.loading`
//      simultaneously and a single `Task` re-issues both queries in
//      parallel.
//
//    • Lane and equipment-type cohort drill-downs render
//      `EusoEmptyState(comingSoon: true)` because the backend's
//      `byLane` / `byCatalyst` arrays are reserved future fields
//      (currently empty per `shippers.ts:489-493`). Per the §13
//      no-fake-data rule in the codebase doctrine: render the UI but
//      surface a neutral empty state — do not fake data.
//
//    • Insights are programmatically derived from the live data
//      (top-3 share of spend, average on-time rate, avg-vs-market
//      variance) — no hard-coded copy that pretends to be analysis.
//      An empty / single-carrier window collapses the insights block
//      gracefully.
//
//    • Server errors surface via `EusoTripAPIError.errorDescription`
//      in an inline banner with a Retry CTA (refreshes both stores).
//
//  Wired into `ContentView.ScreenRegistry` as id="210".
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen body

struct ShipperAnalyticsDeepDive: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var spendStore = ShipperSpendingAnalyticsStore()
    @StateObject private var catalystStore = ShipperCatalystPerformanceStore()

    /// Canonical period selection. Propagates to both stores via
    /// `setPeriod` so every lens always describes the same window.
    @State private var selectedPeriod: ShipperAPI.SpendingPeriod = .month

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                periodChips
                efficiencySection
                carrierDistributionSection
                onTimeBucketsSection
                insightsSection
                cohortPlaceholdersSection
                disclosureFooter
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s2)
        }
        .task { await refreshAll() }
        .refreshable { await refreshAll() }
    }

    // MARK: - Refresh both stores in parallel

    private func refreshAll() async {
        async let a: Void = spendStore.refresh()
        async let b: Void = catalystStore.refresh()
        _ = await (a, b)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("DEEP DIVE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("Spend efficiency & carrier mix")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer(minLength: 0)
                OrbESang(state: spendStore.isLoading || catalystStore.isLoading ? .thinking : .idle, diameter: 36)
            }
            Text("Live cohort breakdowns. Pull to refresh — every figure resolves from the same time window across both queries.")
                .font(EType.body)
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - Period chips

    private var periodChips: some View {
        HStack(spacing: 8) {
            periodChip("Month",   .month)
            periodChip("Quarter", .quarter)
            periodChip("Year",    .year)
            Spacer(minLength: 0)
        }
    }

    private func periodChip(_ label: String, _ value: ShipperAPI.SpendingPeriod) -> some View {
        let isOn = (value == selectedPeriod)
        let bg: AnyShapeStyle = isOn
            ? AnyShapeStyle(LinearGradient.diagonal)
            : AnyShapeStyle(palette.bgCard)
        let fg: Color = isOn ? .white : palette.textPrimary
        let border: AnyShapeStyle = isOn
            ? AnyShapeStyle(Color.clear)
            : AnyShapeStyle(palette.borderFaint)

        return Button {
            guard !isOn else { return }
            selectedPeriod = value
            spendStore.setPeriod(value)
            catalystStore.setPeriod(value)
            Task { await refreshAll() }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .heavy)).tracking(0.4)
                .foregroundStyle(fg)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(bg)
                .overlay(
                    Capsule().strokeBorder(border, lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Efficiency lens section

    @ViewBuilder
    private var efficiencySection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("EFFICIENCY", icon: "speedometer")
            switch spendStore.state {
            case .loading:
                loadingTile(message: "Pulling efficiency metrics…")
            case .loaded(let optV):
                if let v = optV {
                    efficiencyGrid(v)
                } else {
                    efficiencyEmpty
                }
            case .empty:
                efficiencyEmpty
            case .error(let err):
                errorBanner(message: readableError(err)) {
                    Task { await refreshAll() }
                }
            }
        }
    }

    private var efficiencyEmpty: some View {
        EusoEmptyState(
            systemImage: "chart.line.downtrend.xyaxis",
            title: "No spend in window",
            subtitle: "Once you post and settle a load in this period, the efficiency breakdown appears here."
        )
    }

    private func efficiencyGrid(_ v: ShipperAPI.SpendingAnalytics) -> some View {
        VStack(spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                statTile(
                    label: "TOTAL SPEND",
                    value: currency(v.totalSpend),
                    glyph: "dollarsign.circle.fill"
                )
                statTile(
                    label: "LOADS",
                    value: "\(v.loadCount)",
                    glyph: "shippingbox.fill"
                )
            }
            HStack(spacing: Space.s2) {
                statTile(
                    label: "AVG / LOAD",
                    value: v.loadCount > 0 ? currency(v.avgPerLoad) : "—",
                    glyph: "scalemass"
                )
                statTile(
                    label: "AVG / MILE",
                    value: v.avgPerMile > 0 ? currency4(v.avgPerMile) : "—",
                    glyph: "speedometer"
                )
            }
            // vs-market variance is the highlight metric of the deep
            // dive — gets its own emphasis tile spanning full width.
            marketVarianceTile(v)
        }
    }

    private func statTile(label: String, value: String, glyph: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: glyph)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(label)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }
            Text(value)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// Backend `vsMarketRate` is signed: positive = premium paid over
    /// market, negative = below market (favorable). The tile color-
    /// codes directionally without using flat brand-blue: gradient
    /// glyph for favorable, neutral for at-market, palette-warning
    /// tint for premium. Doctrine §1: gradient remains the only brand
    /// accent.
    private func marketVarianceTile(_ v: ShipperAPI.SpendingAnalytics) -> some View {
        let isFavorable = v.vsMarketRate < 0
        let isPremium   = v.vsMarketRate > 0
        let glyph: String = isFavorable ? "arrow.down.right.circle.fill"
                          : isPremium   ? "arrow.up.right.circle.fill"
                                        : "equal.circle.fill"
        let display: String = v.loadCount == 0
            ? "—"
            : "\(formatPctSigned(v.vsMarketRate))"
        let detail: String = v.loadCount == 0
            ? "Variance vs national average rate-per-mile."
            : isFavorable
                ? "Below market — you're shipping efficiently."
                : isPremium
                    ? "Above market — premium paid for this window."
                    : "On par with market — no variance this window."

        return HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: glyph)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 44, height: 44)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("VS MARKET RATE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text(display)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Carrier distribution (share-of-spend bars)

    @ViewBuilder
    private var carrierDistributionSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("BY CARRIER", icon: "person.3.sequence.fill")
            switch catalystStore.state {
            case .loading:
                loadingTile(message: "Building carrier mix…")
            case .loaded(let rows):
                if rows.isEmpty {
                    carrierEmpty
                } else {
                    carrierDistribution(rows)
                }
            case .empty:
                carrierEmpty
            case .error(let err):
                errorBanner(message: readableError(err)) {
                    Task { await refreshAll() }
                }
            }
        }
    }

    private var carrierEmpty: some View {
        EusoEmptyState(
            systemImage: "person.crop.circle.badge.questionmark",
            title: "No carrier mix to chart",
            subtitle: "Once a catalyst hauls one of your posted loads, the share-of-spend distribution appears here."
        )
    }

    private func carrierDistribution(_ rows: [ShipperAPI.CatalystPerformance]) -> some View {
        // Rank by total spend descending (server doesn't sort).
        // Compute the maximum spend for the bar-width normalization
        // and the grand total for the percent-of-spend label.
        let ranked = rows.sorted { l, r in
            if l.totalSpend != r.totalSpend { return l.totalSpend > r.totalSpend }
            return l.onTimeRate > r.onTimeRate
        }
        let grandTotal = ranked.reduce(0.0) { $0 + $1.totalSpend }
        let maxSpend = ranked.map { $0.totalSpend }.max() ?? 1

        return VStack(spacing: 6) {
            ForEach(Array(ranked.enumerated()), id: \.element.id) { idx, row in
                shareBar(
                    rank: idx + 1,
                    row: row,
                    maxSpend: maxSpend,
                    grandTotal: grandTotal
                )
            }
        }
    }

    /// Horizontal share-of-spend row: rank pip + name + on-time pill +
    /// gradient bar whose width is normalized against the top spender,
    /// trailing %-of-total label. Per doctrine §7: ternary
    /// shape-styles wrapped in `AnyShapeStyle`.
    private func shareBar(
        rank: Int,
        row: ShipperAPI.CatalystPerformance,
        maxSpend: Double,
        grandTotal: Double
    ) -> some View {
        let widthFraction: Double = maxSpend > 0
            ? max(0.04, min(1.0, row.totalSpend / maxSpend))
            : 0.04
        let pctOfTotal: Double = grandTotal > 0
            ? (row.totalSpend / grandTotal) * 100.0
            : 0.0
        let rankBg: AnyShapeStyle = rank <= 3
            ? AnyShapeStyle(LinearGradient.diagonal)
            : AnyShapeStyle(palette.tintNeutral.opacity(0.5))
        let rankFg: AnyShapeStyle = rank <= 3
            ? AnyShapeStyle(Color.white)
            : AnyShapeStyle(palette.textPrimary)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Space.s2) {
                Text("\(rank)")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(rankFg)
                    .frame(width: 24, height: 24)
                    .background(rankBg)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                Text(row.name.isEmpty ? "—" : row.name)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Space.s2)
                Text(row.totalLoads > 0 ? "\(row.onTimeRate)% OT" : "— OT")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                Text(row.totalSpend > 0 ? currency(row.totalSpend) : "—")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
            }
            // Bar track + fill — gradient remains the only brand
            // accent; track uses palette.tintNeutral.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.6))
                    RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                        .fill(LinearGradient.diagonal)
                        .frame(width: max(8, geo.size.width * CGFloat(widthFraction)))
                }
            }
            .frame(height: 8)
            HStack {
                Text("\(row.delivered)/\(row.totalLoads) delivered")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text(grandTotal > 0 ? "\(formatPct(pctOfTotal)) of total" : "—")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - On-time-rate distribution

    @ViewBuilder
    private var onTimeBucketsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("ON-TIME DISTRIBUTION", icon: "clock.badge.checkmark")
            switch catalystStore.state {
            case .loading:
                loadingTile(message: "Bucketing on-time rates…")
            case .loaded(let rows):
                let qualifying = rows.filter { $0.totalLoads > 0 }
                if qualifying.isEmpty {
                    onTimeEmpty
                } else {
                    onTimeBuckets(qualifying)
                }
            case .empty:
                onTimeEmpty
            case .error:
                // Error already surfaced in the carrier-distribution
                // section above; suppress duplicate banner.
                EmptyView()
            }
        }
    }

    private var onTimeEmpty: some View {
        EusoEmptyState(
            systemImage: "clock.arrow.circlepath",
            title: "No on-time data yet",
            subtitle: "Carrier on-time rates appear here once delivered loads accumulate in this window."
        )
    }

    private func onTimeBuckets(_ rows: [ShipperAPI.CatalystPerformance]) -> some View {
        let excellent = rows.filter { $0.onTimeRate >= 95 }.count
        let solid     = rows.filter { $0.onTimeRate >= 80 && $0.onTimeRate < 95 }.count
        let watch     = rows.filter { $0.onTimeRate < 80 }.count
        let total = max(1, excellent + solid + watch)

        return VStack(spacing: Space.s2) {
            bucketRow(label: "≥ 95%",   subtitle: "Excellent",      count: excellent, total: total)
            bucketRow(label: "80-94%",  subtitle: "Solid",          count: solid,     total: total)
            bucketRow(label: "< 80%",   subtitle: "Needs watching", count: watch,     total: total)
        }
    }

    private func bucketRow(label: String, subtitle: String, count: Int, total: Int) -> some View {
        let pct: Double = (Double(count) / Double(total)) * 100.0
        return HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            .frame(width: 84, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.6))
                    RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                        .fill(LinearGradient.diagonal)
                        .frame(width: max(8, geo.size.width * CGFloat(pct / 100.0)))
                }
            }
            .frame(height: 10)
            Text("\(count)")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .frame(width: 28, alignment: .trailing)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Insights

    @ViewBuilder
    private var insightsSection: some View {
        // Insights derive from BOTH stores. They render only when both
        // are .loaded with non-empty payloads — no fabricated copy
        // when the data is missing or partial.
        if case .loaded(let optSpend) = spendStore.state,
           let spend = optSpend,
           case .loaded(let carriers) = catalystStore.state,
           !carriers.isEmpty {
            let derived = derivedInsights(spend: spend, carriers: carriers)
            VStack(alignment: .leading, spacing: Space.s2) {
                sectionHeader("INSIGHTS", icon: "sparkles")
                VStack(spacing: 6) {
                    ForEach(derived, id: \.self) { line in
                        insightRow(line)
                    }
                }
            }
        } else {
            EmptyView()
        }
    }

    private func derivedInsights(
        spend: ShipperAPI.SpendingAnalytics,
        carriers: [ShipperAPI.CatalystPerformance]
    ) -> [String] {
        var out: [String] = []
        let ranked = carriers.sorted { $0.totalSpend > $1.totalSpend }
        let grand = ranked.reduce(0.0) { $0 + $1.totalSpend }
        if grand > 0 {
            let topThree = ranked.prefix(3).reduce(0.0) { $0 + $1.totalSpend }
            let pct = (topThree / grand) * 100.0
            if ranked.count >= 3 {
                out.append("\(formatPct(pct)) of spend goes to your top 3 carriers.")
            } else if ranked.count > 0 {
                out.append("All spend is concentrated across \(ranked.count) carrier\(ranked.count == 1 ? "" : "s").")
            }
        }
        let withDeliveries = carriers.filter { $0.totalLoads > 0 }
        if !withDeliveries.isEmpty {
            let avg = withDeliveries.map { Double($0.onTimeRate) }.reduce(0.0, +) / Double(withDeliveries.count)
            out.append("Average on-time rate across active carriers: \(formatPct(avg)).")
        }
        if spend.loadCount > 0 {
            if spend.vsMarketRate < -1 {
                out.append("You're paying \(formatPctSigned(spend.vsMarketRate)) vs the national rate-per-mile — favorable window.")
            } else if spend.vsMarketRate > 1 {
                out.append("This window is \(formatPctSigned(spend.vsMarketRate)) above market — review premium loads.")
            } else {
                out.append("Spend is on par with the national rate-per-mile this window.")
            }
        }
        return out
    }

    private func insightRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "sparkle")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .padding(.top, 2)
            Text(text)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Cohort placeholders (lane / equipment-type)

    /// Backend reserves `byLane` and equipment-type breakdowns for
    /// future expansion — they are not yet returned by
    /// `shippers.getSpendingAnalytics`. Per the §13 no-fake-data rule
    /// in the codebase doctrine: render the UI but surface a neutral
    /// `comingSoon: true` empty state. The screen wiring is ready —
    /// when the backend ships those projections, only the empty
    /// states swap to live cohort rows.
    private var cohortPlaceholdersSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("MORE LENSES", icon: "rectangle.3.group")
            EusoEmptyState(
                systemImage: "map",
                title: "By lane",
                subtitle: "Origin-destination breakdown lands here when the backend ships the byLane projection.",
                comingSoon: true
            )
            EusoEmptyState(
                systemImage: "shippingbox.and.arrow.backward",
                title: "By equipment",
                subtitle: "Dry van, reefer, flatbed and tanker mix lands here when the backend ships the byEquipment projection.",
                comingSoon: true
            )
        }
    }

    // MARK: - Disclosure

    private var disclosureFooter: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("How this drill-down is built")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text("Every figure resolves from two live tRPC procedures (`shippers.getSpendingAnalytics` and `shippers.getCatalystPerformance`) against the same period selection, so cross-tile numbers always agree. Lane and equipment-type cohorts ship when the backend exposes them.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Loading + error

    private func loadingTile(message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("LOADING")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func errorBanner(message: String, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.danger)
                Text("COULDN'T LOAD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.danger)
            }
            Text(message)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text(text)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.diagonal)
        }
    }

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    /// Currency with cents — used for $/mile values where rounding to
    /// whole dollars destroys signal (a $2.34/mi vs $2.41/mi gap is
    /// the entire conversation in shipper analytics).
    private func currency4(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    private func formatPct(_ value: Double) -> String {
        return String(format: "%.0f%%", value)
    }

    private func formatPctSigned(_ value: Double) -> String {
        let sign = value > 0 ? "+" : (value < 0 ? "" : "")
        return String(format: "\(sign)%.1f%%", value)
    }

    private func readableError(_ error: Error) -> String {
        if let api = error as? EusoTripAPIError {
            return api.errorDescription ?? "Request failed."
        }
        return error.localizedDescription
    }
}

// MARK: - Screen wrapper (Shell + BottomNav)

struct ShipperAnalyticsDeepDiveScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            ShipperAnalyticsDeepDive()
        } nav: {
            BottomNav(
                leading: shipperNavLeading_210(),
                trailing: shipperNavTrailing_210(),
                orbState: .idle
            )
        }
    }
}

private func shipperNavLeading_210() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",            isCurrent: false),
     NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false)]
}

private func shipperNavTrailing_210() -> [NavSlot] {
    [NavSlot(label: "Reports",  systemImage: "chart.line.uptrend.xyaxis",   isCurrent: false),
     NavSlot(label: "Insights", systemImage: "chart.bar.doc.horizontal",    isCurrent: true)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so both stores stay in `.loading` —
// each register renders the loading skeleton without hitting the
// network. Per doctrine §10: previews must compile in isolation.

#Preview("210 · Shipper · Analytics Deep-Dive · Night") {
    ShipperAnalyticsDeepDiveScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("210 · Shipper · Analytics Deep-Dive · Afternoon") {
    ShipperAnalyticsDeepDiveScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
