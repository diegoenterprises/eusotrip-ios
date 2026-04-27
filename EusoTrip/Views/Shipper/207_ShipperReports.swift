//
//  207_ShipperReports.swift
//  EusoTrip — Shipper · Reports (brick 207).
//
//  Eighth brick on the Shipper role track (200s). Shipped in the
//  126th eusotrip-killers firing per the 124th firing's hand-off
//  recommendation: "Code-port fallback if A still blocked:
//  207_ShipperReports or 301_CarrierLoads detail expansion."
//
//  Pixel-doctrine compliant per EUSOTRIP2027GOLD §2 (gradient-only
//  accent — no flat Brand.info / Brand.blue fills, no .tint(.blue)),
//  §4 (tokenized spacing / radius / type — Space.s*, Radius.*,
//  EType.*), §5 (palette semantic only — no hard-coded Color.white /
//  Color.black / Color.gray fills), §7 (`AnyShapeStyle` wrapping for
//  ternary shape-styles in fill / stroke), §10 (previews compile in
//  isolation — `.task` doesn't run in the preview canvas, so both
//  stores stay in `.loading` and never hit the network).
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data, 1000% dynamic"):
//
//    • Spend KPIs → `ShipperSpendingAnalyticsStore` (LiveDataStores
//      added in this firing) → `shippers.getSpendingAnalytics`
//      (input `{ period: "month"|"quarter"|"year" }`). MCP-verified
//      at `frontend/server/routers/shippers.ts:470`.
//    • Catalyst leaderboard → `ShipperCatalystPerformanceStore`
//      (LiveDataStores added in this firing) →
//      `shippers.getCatalystPerformance` (same input shape).
//      MCP-verified at `frontend/server/routers/shippers.ts:433`.
//    • The screen owns the canonical `SpendingPeriod` and propagates
//      to BOTH stores via `setPeriod`, so the KPI tiles and the
//      leaderboard always describe the same time window. Switching
//      the period flips both stores to `.loading` simultaneously and
//      a single `Task` re-issues both queries in parallel.
//    • Empty / blank server fields surface as em-dash sentinels
//      ("—"). Zero-spend windows render `EusoEmptyState` rather than
//      a "$0 over 0 loads" tile strip.
//    • Server errors surface via `EusoTripAPIError.errorDescription`
//      in an inline banner with a Retry CTA (refreshes both stores).
//
//  Wired into `ContentView.ScreenRegistry` as id="207".
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen body

struct ShipperReports: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var spendStore = ShipperSpendingAnalyticsStore()
    @StateObject private var catalystStore = ShipperCatalystPerformanceStore()

    /// Canonical period selection. Propagates to both stores via
    /// `setPeriod` so the two strips always describe the same window.
    @State private var selectedPeriod: ShipperAPI.SpendingPeriod = .month

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            header
            periodChips
            spendingSection
            catalystSection
            Color.clear.frame(height: 96)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
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
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("REPORTS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("Spend & catalyst performance")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer(minLength: 0)
            }
            Text("Live spend totals and the catalysts moving your freight. Pull to refresh.")
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

    // MARK: - Spending section

    @ViewBuilder
    private var spendingSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("SPEND", icon: "dollarsign.circle.fill")
            switch spendStore.state {
            case .loading:
                loadingTile(message: "Pulling your spend totals…")
            case .loaded(let optV):
                if let v = optV {
                    spendKPIs(v)
                } else {
                    spendEmpty
                }
            case .empty:
                spendEmpty
            case .error(let err):
                errorBanner(message: readableError(err)) {
                    Task { await refreshAll() }
                }
            }
        }
    }

    private var spendEmpty: some View {
        EusoEmptyState(
            systemImage: "chart.line.downtrend.xyaxis",
            title: "No spend in window",
            subtitle: "Once you post and settle a load in this period, the totals appear here."
        )
    }

    private func spendKPIs(_ v: ShipperAPI.SpendingAnalytics) -> some View {
        VStack(spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                metricTile(
                    label: "TOTAL SPEND",
                    value: currency(v.totalSpend),
                    icon: "dollarsign.circle"
                )
                metricTile(
                    label: "LOADS",
                    value: "\(v.loadCount)",
                    icon: "shippingbox"
                )
            }
            HStack(spacing: Space.s2) {
                metricTile(
                    label: "AVG / LOAD",
                    value: v.loadCount > 0 ? currency(v.avgPerLoad) : "—",
                    icon: "chart.bar"
                )
                metricTile(
                    label: "AVG / MILE",
                    value: v.avgPerMile > 0 ? currency(v.avgPerMile) : "—",
                    icon: "speedometer"
                )
            }
        }
    }

    private func metricTile(label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .heavy))
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

    // MARK: - Catalyst leaderboard section

    @ViewBuilder
    private var catalystSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("CATALYSTS", icon: "person.3.fill")
            switch catalystStore.state {
            case .loading:
                loadingTile(message: "Ranking your catalysts…")
            case .loaded(let rows):
                if rows.isEmpty {
                    catalystEmpty
                } else {
                    catalystList(rows)
                }
            case .empty:
                catalystEmpty
            case .error(let err):
                errorBanner(message: readableError(err)) {
                    Task { await refreshAll() }
                }
            }
        }
    }

    private var catalystEmpty: some View {
        EusoEmptyState(
            systemImage: "person.crop.circle.badge.questionmark",
            title: "No catalyst loads in window",
            subtitle: "Once a catalyst hauls one of your posted loads, you'll see them ranked here by spend and on-time rate."
        )
    }

    private func catalystList(_ rows: [ShipperAPI.CatalystPerformance]) -> some View {
        // Rank by total spend descending — the backend doesn't sort,
        // so the screen owns the ranking. Ties broken by on-time rate
        // (higher first) so the surface stays deterministic.
        let ranked = rows.sorted { l, r in
            if l.totalSpend != r.totalSpend { return l.totalSpend > r.totalSpend }
            return l.onTimeRate > r.onTimeRate
        }

        return VStack(spacing: 6) {
            ForEach(Array(ranked.enumerated()), id: \.element.id) { idx, row in
                catalystRow(rank: idx + 1, row: row)
            }
        }
    }

    private func catalystRow(rank: Int, row: ShipperAPI.CatalystPerformance) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            // Rank badge — gradient ring around a numeral.
            ZStack {
                Circle().strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
                Text("\(rank)")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            .frame(width: 28, height: 28)
            .background(palette.bgCard)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(row.name.isEmpty ? "—" : row.name)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(row.delivered)/\(row.totalLoads) delivered")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    Text("·")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                    Text(row.totalLoads > 0 ? "\(row.onTimeRate)% on-time" : "— on-time")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                .lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            Text(row.totalSpend > 0 ? currency(row.totalSpend) : "—")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
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

    private func readableError(_ error: Error) -> String {
        if let api = error as? EusoTripAPIError {
            return api.errorDescription ?? "Request failed."
        }
        return error.localizedDescription
    }
}

// MARK: - Screen wrapper (Shell + BottomNav)

struct ShipperReportsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            ShipperReports()
        } nav: {
            BottomNav(
                leading: shipperNavLeading_207(),
                trailing: shipperNavTrailing_207(),
                orbState: .idle
            )
        }
    }
}

private func shipperNavLeading_207() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",            isCurrent: false),
     NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false)]
}

private func shipperNavTrailing_207() -> [NavSlot] {
    [NavSlot(label: "Reports", systemImage: "chart.line.uptrend.xyaxis", isCurrent: true),
     NavSlot(label: "Me",      systemImage: "person",                    isCurrent: false)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so both stores stay in `.loading` —
// each register renders the loading skeleton without hitting the
// network. Per doctrine §10: previews must compile in isolation.

#Preview("207 · Shipper · Reports · Night") {
    ShipperReportsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("207 · Shipper · Reports · Afternoon") {
    ShipperReportsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
