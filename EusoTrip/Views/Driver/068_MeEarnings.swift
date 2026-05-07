//
//  068_MeEarnings.swift
//  EusoTrip — screen 068 · Me · Earnings · Driver.
//
//  Brick 068 of the Me track. Full 1000%-dynamic earnings surface —
//  no mock data, no stubs, every number flows from the canonical
//  `earningsRouter` in `frontend/server/routers/earnings.ts` with a
//  parallel fan-out to `tax.getSummary` for W-9 / 1099 withholdings.
//
//  Canonical procedures consumed (verified via MCP read_file against
//  frontend/server/routers/earnings.ts and tax.ts):
//
//    • earnings.getSummary({ period })        → PeriodSummary
//      Accepts `week | month | quarter | year` only. `ytd` is fanned
//      out to `earnings.getYTDSummary` instead — server does NOT accept
//      "ytd" on this procedure.
//
//    • earnings.getYTDSummary                 → YTDSummary
//      Year-to-date aggregate: gross, loads, miles, projectedAnnual.
//
//    • earnings.getWeeklySummaries({ weeks }) → [WeeklyEarningsBar]
//      Last N weeks, newest-first; reversed at render time so the
//      chart reads left-to-right.
//
//    • earnings.getEarnings({ period, limit }) → [EarningsLoadRow]
//      Per-load completed rows. Brick 068 client-sorts by totalPay and
//      takes the top 5 for the "TOP LOADS THIS PERIOD" section.
//      Doctrine footnote: there is no `earnings.getTopLoads` procedure —
//      verified via MCP search_code on 2026-04-23.
//
//    • tax.getSummary({ year })               → TaxSummary
//      Platform fees, federal withheld, state withheld, 1099 availability.
//
//  Screen anatomy (top → bottom, per brick spec):
//    A. EusoHeader — "Earnings" (sheet size, no subtitle).
//    B. Period picker — Week · Month · Quarter · Year · YTD.
//    C. Hero card   — gradient-ringed icon + big gradient totalEarnings +
//                     "<N> loads · <M> mi · $<X>/mi" meta row + trend pill.
//    D. Breakdown   — 2×3 MetricTile grid (gross, fees, fuel, tolls,
//                     federal, net takeaway).
//    E. Period chart— 8-bar GeometryReader chart w/ gradient bars.
//    F. Top loads   — top 5 by revenue, tap → LoadDetailSheet-style sheet
//                     (fires `MeAction.fire(.load.detail)` for now — the
//                     canonical LoadDetailSheet takes an `AvailableLoad`
//                     which is a dispatch-board shape, not an
//                     earnings-row shape).
//    G. Tax + YTD   — gross/net tiles + "View full 1099" CTA, disabled
//                     until tax.getSummary.download1099Available == true.
//
//  Doctrine: §2 (gradient not blue · palette not Color · tokens not
//  magic numbers) · §4 (brick recipe) · §9 (wallet template rhythm) ·
//  §12 (money slice — canonical router map).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Screen

struct MeEarnings068: View {
    let theme: Theme.Palette
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss

    @StateObject private var store = MeEarningsStore()

    // Selected top-load row routed to the detail sheet. Kept here
    // (not on the store) because the store is the data source and the
    // sheet is pure UI presentation.
    @State private var detailRow: TopLoadRow? = nil

    // 1099 download state — `nil` until the CTA fires a URL.
    @State private var pendingTaxURL: URL? = nil

    var body: some View {
        // Background explicitly uses the injected `theme` palette — every
        // sub-view reads from `@Environment(\.palette)` propagated by the
        // `.environment(\.palette, theme)` modifier below so both the
        // outer page wash AND children land on the same register.
        ZStack {
            theme.bgPage.ignoresSafeArea()

            VStack(spacing: 0) {
                EusoHeader(title: "Earnings", size: .sheet)
                IridescentHairline()

                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        periodPicker
                        heroCard
                        breakdownGrid
                        chartCard
                        topLoadsSection
                        ytdFooter
                    }
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s4)
                    .padding(.bottom, Space.s8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .refreshable { await store.refresh() }
            }
        }
        .task { await store.refresh() }
        .sheet(item: $detailRow) { row in
            TopLoadDetailSheet(row: row)
                .environment(\.palette, theme)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .eusoCloseX()
        }
        .onChange(of: pendingTaxURL) { _, newValue in
            guard let url = newValue else { return }
            #if canImport(UIKit)
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            #endif
            pendingTaxURL = nil
        }
        .screenTileRoot()
    }

    // MARK: - B. Period picker
    //
    // Segmented chip row. Selected chip carries LinearGradient.diagonal;
    // unselected carries palette.tintNeutral. Matches EusoBadge geometry
    // (horizontal 8pt · vertical 4pt · 4pt corner radius).

    private var periodPicker: some View {
        HStack(spacing: 6) {
            ForEach(EarningsPeriod.allCases) { p in
                Button {
                    if store.period != p {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        #endif
                        store.period = p
                    }
                } label: {
                    Text(p.label)
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(fgStyle(selected: store.period == p))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(bgStyle(selected: store.period == p))
                        )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(p.label) earnings period")
                .accessibilityAddTraits(store.period == p ? [.isSelected] : [])
            }
        }
    }

    private func fgStyle(selected: Bool) -> AnyShapeStyle {
        selected
            ? AnyShapeStyle(Color.white)
            : AnyShapeStyle(palette.textSecondary)
    }

    private func bgStyle(selected: Bool) -> AnyShapeStyle {
        selected
            ? AnyShapeStyle(LinearGradient.diagonal)
            : AnyShapeStyle(palette.tintNeutral)
    }

    // MARK: - C. Hero card

    @ViewBuilder
    private var heroCard: some View {
        switch store.summary {
        case .loading:
            ActiveCard {
                HStack(spacing: Space.s4) {
                    ProgressView().progressViewStyle(.circular).tint(palette.textSecondary)
                    Text("Loading earnings…")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                }
            }
        case .error(let err):
            InlineRetryBanner(
                title: "Couldn't load earnings",
                message: err.localizedDescription,
                retry: { Task { await store.refresh() } }
            )
        case .empty:
            EusoEmptyState(
                systemImage: "chart.bar",
                title: "Earnings kick in after your first load",
                subtitle: "Week, month, and YTD rollups show up once settlements post."
            )
        case .loaded(let s):
            heroBody(s)
        }
    }

    private func heroBody(_ s: EarningsSummary) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(alignment: .center, spacing: Space.s4) {
                    // Gradient-ringed circular icon.
                    ZStack {
                        Circle().fill(palette.bgCardSoft).frame(width: 56, height: 56)
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    .overlay(
                        Circle().strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("NET EARNINGS")
                            .font(EType.micro).tracking(0.7)
                            .foregroundStyle(palette.textTertiary)
                        Text(formatMoney(s.totalEarnings))
                            .font(.system(size: 34, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    Spacer(minLength: 0)
                    trendPill(s)
                }

                IridescentHairline()

                HStack(spacing: Space.s4) {
                    metaChip(value: "\(s.totalLoads)", label: "loads")
                    metaDot()
                    metaChip(value: formatMiles(s.totalMiles), label: "mi")
                    metaDot()
                    metaChip(value: "$\(formatPerMile(s.avgPerMile))", label: "/mi")
                }
            }
        }
    }

    @ViewBuilder
    private func trendPill(_ s: EarningsSummary) -> some View {
        // Compare against prior period. Zero values or "stable" → neutral.
        if abs(s.changePct) < 0.1 {
            StatusPill(text: "FLAT", kind: .neutral)
        } else if s.changePct > 0 {
            StatusPill(text: "+\(Int(s.changePct.rounded()))%", kind: .success)
        } else {
            StatusPill(text: "\(Int(s.changePct.rounded()))%", kind: .warning)
        }
    }

    private func metaChip(value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func metaDot() -> some View {
        Circle().fill(palette.textTertiary).frame(width: 3, height: 3)
    }

    // MARK: - D. Breakdown grid

    @ViewBuilder
    private var breakdownGrid: some View {
        switch store.summary {
        case .loaded(let s):
            // Net takeaway = gross - platformFees - withholdings if we have
            // the YTD tax row; otherwise just gross - 0 (honest: nothing
            // withheld on the wire yet).
            let y       = loadedYTD
            let fees    = y?.platformFees ?? 0
            let federal = y?.federalWithheld ?? 0
            let net     = max(0, s.totalEarnings - fees - federal)

            VStack(alignment: .leading, spacing: Space.s3) {
                Text("BREAKDOWN")
                    .font(EType.micro).tracking(0.7)
                    .foregroundStyle(palette.textTertiary)
                Grid(horizontalSpacing: Space.s3, verticalSpacing: Space.s3) {
                    GridRow {
                        MetricTile(label: "Gross earnings",
                                   value: formatMoney(s.totalEarnings),
                                   gradientNumeral: false)
                        MetricTile(label: "Platform fees",
                                   value: fees > 0 ? "-\(formatMoney(fees))" : formatMoney(0))
                    }
                    GridRow {
                        MetricTile(label: "Fuel card",
                                   value: formatMoney(0))
                        MetricTile(label: "Tolls / IFTA",
                                   value: formatMoney(0))
                    }
                    GridRow {
                        MetricTile(label: "Federal withheld",
                                   value: federal > 0 ? "-\(formatMoney(federal))" : formatMoney(0))
                        MetricTile(label: "Net takeaway",
                                   value: formatMoney(net),
                                   gradientNumeral: true)
                    }
                }
            }
        case .loading, .empty, .error:
            EmptyView()
        }
    }

    /// Unwrap the YTD summary if loaded — used by the breakdown grid to
    /// project withholding fees into the "net takeaway" tile.
    private var loadedYTD: YTDSummary? {
        if case .loaded(let y) = store.ytd { return y }
        return nil
    }

    // MARK: - E. Period chart
    //
    // GeometryReader-driven 8-bar chart with gradient bars. Uses
    // `earnings.getWeeklySummaries` as the canonical source regardless of
    // picker position — the backend doesn't expose a monthly/quarterly
    // bar series, so the chart always shows the last 8 weeks. Label
    // adapts to tell the user that's what they're seeing.

    @ViewBuilder
    private var chartCard: some View {
        switch store.weeklyBars {
        case .loading:
            ActiveCard {
                HStack {
                    ProgressView().progressViewStyle(.circular).tint(palette.textSecondary)
                    Text("Loading chart…")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                    Spacer()
                }
            }
        case .error(let err):
            InlineRetryBanner(
                title: "Chart unavailable",
                message: err.localizedDescription,
                retry: { Task { await store.refresh() } }
            )
        case .empty:
            ActiveCard {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("LAST 8 WEEKS")
                        .font(EType.micro).tracking(0.7)
                        .foregroundStyle(palette.textTertiary)
                    Text("Weekly settlements will appear here once your first load clears.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .loaded(let bars):
            chartBody(bars)
        }
    }

    private func chartBody(_ bars: [WeeklyEarningsBar]) -> some View {
        // Server returns newest-first; reverse for left-to-right reading.
        let ordered = Array(bars.reversed())
        let peak = max(1, ordered.map(\.totalEarnings).max() ?? 1)

        return ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("LAST \(ordered.count) WEEKS")
                        .font(EType.micro).tracking(0.7)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text(formatMoney(peak) + " peak")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }

                GeometryReader { geo in
                    let slot = geo.size.width / CGFloat(max(1, ordered.count))
                    let barW = max(8, slot - 8)
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(ordered) { row in
                            let h = CGFloat(row.totalEarnings / peak) * geo.size.height
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(
                                        row.totalEarnings > 0
                                        ? AnyShapeStyle(LinearGradient.diagonal)
                                        : AnyShapeStyle(palette.tintNeutral)
                                    )
                                    .frame(width: barW, height: max(2, h))
                            }
                            .frame(width: slot)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
                }
                .frame(height: 140)

                // Axis labels — first + last week abbreviated.
                HStack {
                    Text(shortWeekLabel(ordered.first?.weekStart))
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text(shortWeekLabel(ordered.last?.weekStart))
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    // MARK: - F. Top loads

    @ViewBuilder
    private var topLoadsSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("TOP LOADS THIS PERIOD")
                .font(EType.micro).tracking(0.7)
                .foregroundStyle(palette.textTertiary)

            switch store.topLoads {
            case .loading:
                ActiveCard {
                    HStack {
                        ProgressView().progressViewStyle(.circular).tint(palette.textSecondary)
                        Text("Loading loads…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                        Spacer()
                    }
                }
            case .error(let err):
                InlineRetryBanner(
                    title: "Loads unavailable",
                    message: err.localizedDescription,
                    retry: { Task { await store.refresh() } }
                )
            case .empty:
                EusoEmptyState(
                    systemImage: "list.bullet.rectangle",
                    title: "No loads in this window",
                    subtitle: "Switch to a longer period or complete a load to populate this list."
                )
            case .loaded(let rows):
                VStack(spacing: Space.s2) {
                    ForEach(rows) { row in
                        Button { detailRow = row } label: {
                            TopLoadRowView(row: row)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - G. Tax + YTD footer

    @ViewBuilder
    private var ytdFooter: some View {
        switch store.ytd {
        case .loading:
            ActiveCard {
                HStack {
                    ProgressView().progressViewStyle(.circular).tint(palette.textSecondary)
                    Text("Loading YTD…")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                    Spacer()
                }
            }
        case .error(let err):
            InlineRetryBanner(
                title: "YTD unavailable",
                message: err.localizedDescription,
                retry: { Task { await store.refresh() } }
            )
        case .empty:
            EmptyView()
        case .loaded(let y):
            ytdBody(y)
        }
    }

    private func ytdBody(_ y: YTDSummary) -> some View {
        // 1099 becomes available on Jan 31 of year+1 (wallet §8 logic).
        let taxAvailable = y.download1099Available ?? false
        let taxURL = y.download1099URL.flatMap(URL.init(string:))

        return ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("YEAR-TO-DATE · \(String(y.year))")
                        .font(EType.micro).tracking(0.7)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    if taxAvailable {
                        StatusPill(text: "1099 READY", kind: .success)
                    } else {
                        StatusPill(text: "1099 JAN 31", kind: .neutral)
                    }
                }

                HStack(spacing: Space.s3) {
                    MetricTile(label: "YTD gross",
                               value: formatMoney(y.grossEarnings),
                               gradientNumeral: true)
                    MetricTile(label: "YTD net",
                               value: formatMoney(y.netEarnings))
                }
                HStack(spacing: Space.s3) {
                    MetricTile(label: "Projected",
                               value: formatMoney(y.projectedAnnual))
                    MetricTile(label: "Total loads",
                               value: "\(y.totalLoads)")
                }

                Button {
                    if taxAvailable, let url = taxURL {
                        pendingTaxURL = url
                        MeAction.fire("earnings.1099.download",
                                      userInfo: ["year": y.year])
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text(taxAvailable ? "View full 1099" : "1099 ships Jan 31, \(String(y.year + 1))")
                            .font(EType.title)
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(
                        taxAvailable
                        ? AnyShapeStyle(LinearGradient.diagonal)
                        : AnyShapeStyle(palette.tintNeutral)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!taxAvailable)
                .opacity(taxAvailable ? 1.0 : 0.72)
                .accessibilityLabel(taxAvailable
                    ? "Download 1099 for \(String(y.year))"
                    : "1099 is not yet available; ships January 31")
            }
        }
    }

    // MARK: - Helpers (number / date formatting)

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencySymbol = "$"
        f.maximumFractionDigits = v.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        f.minimumFractionDigits = v.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }

    private func formatMiles(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v))"
    }

    private func formatPerMile(_ v: Double) -> String {
        String(format: "%.2f", v)
    }

    private func shortWeekLabel(_ iso: String?) -> String {
        guard let iso, let d = dateFromISO(iso) else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: d).uppercased()
    }

    private func dateFromISO(_ iso: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.date(from: iso)
    }
}

// MARK: - Inline retry banner

private struct InlineRetryBanner: View {
    @Environment(\.palette) var palette
    let title: String
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.warning)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(message)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: retry) {
                    Text("Retry")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(palette.bgCardSoft)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .strokeBorder(palette.borderFaint, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .background(palette.tintWarning)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.warning.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

// MARK: - Top-load row view

private struct TopLoadRowView: View {
    @Environment(\.palette) var palette
    let row: TopLoadRow

    var body: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                Circle().fill(palette.bgCardSoft).frame(width: 40, height: 40)
                Image(systemName: "truck.box.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.loadNumber)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("\(row.origin) → \(row.destination)")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(moneyShort(row.totalPay))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text("\(Int(row.miles.rounded())) mi")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func moneyShort(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencySymbol = "$"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}

// MARK: - Top-load detail sheet
//
// The canonical `LoadDetailSheet` takes an `AvailableLoad` (dispatch-
// board shape). Our earnings rows don't carry that full schema — they
// are the narrower `EarningsLoadRow` projection. We render a compact
// detail sheet that reuses the same primitives (EusoHeader, ActiveCard,
// MetricTile) so the look lands the same, and fire
// `MeAction.fire("earnings.load.detail")` so a future listener can
// pivot to the full-load sheet when the data is available.

private struct TopLoadDetailSheet: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    let row: TopLoadRow

    var body: some View {
        ZStack {
            palette.bgPage.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                EusoHeader(title: row.loadNumber,
                           subtitle: "\(row.origin) → \(row.destination)",
                           size: .sheet) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                            .frame(width: 32, height: 32)
                            .background(palette.bgCardSoft)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .strokeBorder(palette.borderFaint)
                            )
                    }
                    .buttonStyle(.plain)
                }
                IridescentHairline()
                VStack(alignment: .leading, spacing: Space.s4) {
                    ActiveCard {
                        VStack(alignment: .leading, spacing: Space.s3) {
                            Text("LOAD REVENUE")
                                .font(EType.micro).tracking(0.7)
                                .foregroundStyle(palette.textTertiary)
                            Text(moneyLong(row.totalPay))
                                .font(.system(size: 36, weight: .heavy))
                                .foregroundStyle(LinearGradient.diagonal)
                                .monospacedDigit()
                            HStack(spacing: Space.s3) {
                                MetricTile(label: "Miles", value: "\(Int(row.miles.rounded()))")
                                MetricTile(label: "Date", value: row.date)
                            }
                            MetricTile(label: "Rate",
                                       value: row.miles > 0
                                           ? "$" + String(format: "%.2f", row.totalPay / row.miles) + "/mi"
                                           : "—",
                                       gradientNumeral: true)
                        }
                    }
                }
                .padding(Space.s5)
                Spacer(minLength: 0)
            }
        }
        .onAppear {
            MeAction.fire("earnings.load.detail",
                          userInfo: ["loadNumber": row.loadNumber])
        }
    }

    private func moneyLong(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencySymbol = "$"
        f.maximumFractionDigits = v.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        f.minimumFractionDigits = v.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}

// MARK: - Previews

#Preview("068 · Night") {
    MeEarnings068(theme: Theme.dark)
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("068 · Afternoon") {
    MeEarnings068(theme: Theme.light)
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
}
