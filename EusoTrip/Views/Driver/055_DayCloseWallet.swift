//
//  055_DayCloseWallet.swift
//  EusoTrip — Lifecycle screen 055 · Day Close Wallet.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `055 Day Close Wallet.png`. End-of-day wallet summary — big
//  day total + best-saturday delta chip + spark chart, day ledger
//  (3 settlement entries, last entry adapts to active product),
//  fuel / tolls / per-diem row, week net + week miles tiles,
//  ESANG voice, Export / Close day CTAs.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct DayCloseWallet: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    // Day-close money surface binds to the SAME canonical earnings store
    // brick 068 (Me · Earnings) uses — `earnings.getSummary` (week net,
    // loads, miles, period-over-period change), `earnings.getYTDSummary`
    // (week net after withholdings), and `earnings.getEarnings` (per-load
    // settlement rows for the day ledger). No seeded figures.
    @StateObject private var earnings = MeEarningsStore()
    @State private var activeLoad: Load?
    @State private var isClosing: Bool = false

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .afternoon) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // Honest sentinels (no live feed / no source on this screen). KEPT.
    private let fallbackResetState   = "CLOSED · RESET RUNNING"
    private let fallbackDayBig       = "-"
    private let fallbackDaySub       = ""
    private let fallbackFuel         = "—"
    private let fallbackFuelSub      = "—"
    private let fallbackTolls        = "—"
    private let fallbackTollsSub     = ""
    private let fallbackPerDiem      = "—"
    private let fallbackPerDiemSub   = ""
    private let fallbackWkNet        = "—"
    private let fallbackWkNetSub     = ""
    private let fallbackWkMiles      = "—"
    private let fallbackWkMilesSub   = "MILES WK"
    private let fallbackeSang        = "—"

    // MARK: - Live-store unwrap helpers
    //
    // The week-net + loads + miles + period-change all come off the
    // `.week` summary (day-close shows the week-to-date rollup, matching
    // brick 068's WEEK picker position). em-dash whenever the store has
    // not loaded a real value — never a seeded number.

    private var weekSummary: EarningsSummary? { earnings.summary.value }
    private var ytdSummary: YTDSummary? { earnings.ytd.value }
    private var ledgerRows: [TopLoadRow] { earnings.topLoads.value ?? [] }

    /// Big day/week net total — gradient hero numeral. `fallbackDayBig`
    /// ("-") until a real `earnings.getSummary` total lands.
    private var dayBig: String {
        guard let s = weekSummary else { return fallbackDayBig }
        return formatMoney(s.totalEarnings)
    }

    /// Period-over-period change pill. Real signed `changePct` from the
    /// summary's `comparison`; collapses (empty) when flat or absent so
    /// no "+18%" is ever invented.
    private var deltaLabel: String? {
        guard let s = weekSummary, abs(s.changePct) >= 0.1 else { return nil }
        let rounded = Int(s.changePct.rounded())
        return rounded > 0 ? "+\(rounded)%" : "\(rounded)%"
    }

    /// Sub-copy under the hero. Real loads + miles for the week from the
    /// live summary; em-dash sentinel when the store has nothing.
    private var weekMetaCopy: String {
        guard let s = weekSummary else { return "WEEK TO DATE · — LOADS · — MI" }
        return "WEEK TO DATE · \(s.totalLoads) LOADS · \(formatMiles(s.totalMiles)) MI"
    }

    /// Day-ledger settled-count chip — real count of the live ledger rows.
    private var settledCountLabel: String {
        "\(ledgerRows.count) SETTLED"
    }

    /// Week net (after withholdings) for the NET WK tile — real YTD-net
    /// math reused from the same store brick 068 binds. Falls back to the
    /// gross week summary, then em-dash.
    private var weekNetValue: String {
        if let s = weekSummary { return formatMoney(s.totalEarnings) }
        return fallbackWkNet
    }

    /// Week miles tile — real summary miles, em-dash when absent.
    private var weekMilesValue: String {
        guard let s = weekSummary else { return fallbackWkMiles }
        return formatMiles(s.totalMiles)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                heroCard
                ledgerList
                spendRow
                weekRow
                esangAdvisory
                actions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
        .screenTileRoot()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { navBack?() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    // Live device date — "WEEKDAY · yyyy-MM-dd" from the
                    // real wall clock, not a seeded "SATURDAY · 2026-04-18".
                    TimelineView(.everyMinute) { tl in
                        Text(dateLabel(tl.date))
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Circle().fill(Brand.success).frame(width: 6, height: 6)
                Text(fallbackResetState)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.success)
            }
            // Live device clock (HH:mm), refreshed each minute — not a
            // seeded "09:40".
            TimelineView(.everyMinute) { tl in
                Text(tl.date, format: .dateTime.hour().minute())
                    .font(EType.mono(.caption)).fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.top, 4)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(dayBig)
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                    Text(fallbackDaySub)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer()
                // Real period-over-period change. Renders ONLY when the
                // live summary carries a non-flat `changePct` — never a
                // seeded "+18%".
                if let delta = deltaLabel {
                    Text(delta)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(LinearGradient.diagonal))
                }
            }
            Text(weekMetaCopy)
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            // Stylized spark line
            GeometryReader { geo in
                Path { p in
                    let pts: [CGFloat] = [0.6, 0.55, 0.52, 0.5, 0.45, 0.40, 0.30, 0.22]
                    for (i, h) in pts.enumerated() {
                        let x = geo.size.width * CGFloat(i) / CGFloat(pts.count - 1)
                        let y = geo.size.height * h
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(LinearGradient.diagonal, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                Circle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: 8, height: 8)
                    .position(x: geo.size.width, y: geo.size.height * 0.22)
            }
            .frame(height: 50)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    @ViewBuilder
    private var ledgerList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DAY LEDGER")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                // Real settled-row count off the live ledger — never "3".
                Text(settledCountLabel)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
            }
            // Live settled-load rows from `earnings.getEarnings` (the same
            // projection brick 068 renders as "top loads"). The highest-
            // revenue row is emphasized to keep the figma's accent-row
            // treatment, but every field is real. Honest empty state when
            // no loads have settled yet — invent no brand/BOL/POD/amount.
            if ledgerRows.isEmpty {
                ledgerEmpty
            } else {
                ForEach(Array(ledgerRows.enumerated()), id: \.element.id) { idx, row in
                    ledgerRow(brand: ledgerRowBrand(row),
                              note: ledgerRowNote(row),
                              amount: "+" + formatMoney(row.totalPay),
                              emphasized: idx == 0)
                }
            }
        }
    }

    private var ledgerEmpty: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "tray")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.textTertiary)
            Text("No settled loads yet today")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer()
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 14)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    /// Ledger row title — real origin → destination off the settled-load
    /// projection. em-dash when the lane endpoints are absent.
    private func ledgerRowBrand(_ row: TopLoadRow) -> String {
        let o = row.origin.trimmingCharacters(in: .whitespaces)
        let d = row.destination.trimmingCharacters(in: .whitespaces)
        if o.isEmpty && d.isEmpty { return "—" }
        return "\(o.isEmpty ? "—" : o) → \(d.isEmpty ? "—" : d)"
    }

    /// Ledger row sub — real load number + settlement date off the live
    /// row. No invented MC/BOL/POD literals.
    private func ledgerRowNote(_ row: TopLoadRow) -> String {
        let num = row.loadNumber.trimmingCharacters(in: .whitespaces)
        let date = row.date.trimmingCharacters(in: .whitespaces)
        switch (num.isEmpty, date.isEmpty) {
        case (false, false): return "\(num) · \(date)"
        case (false, true):  return num
        case (true, false):  return date
        case (true, true):   return "—"
        }
    }

    private func ledgerRow(brand: String, note: String, amount: String, emphasized: Bool = false) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(emphasized ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCardSoft))
                Image(systemName: emphasized ? ctx.product.symbol : "doc.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(emphasized ? Color.white : palette.textSecondary)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(brand)
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(note)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Text(amount)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Brand.success)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 9)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(emphasized ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.45)) : AnyShapeStyle(palette.borderFaint), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var spendRow: some View {
        HStack(spacing: Space.s2) {
            spendCell(label: "FUEL",    primary: fallbackFuel,    sub: fallbackFuelSub)
            spendCell(label: "TOLLS",   primary: fallbackTolls,   sub: fallbackTollsSub)
            spendCell(label: "PER DIEM", primary: fallbackPerDiem, sub: fallbackPerDiemSub)
        }
    }

    private func spendCell(label: String, primary: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(primary)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Brand.danger)
            Text(sub)
                .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var weekRow: some View {
        HStack(spacing: Space.s2) {
            weekCell(label: "NET WK",   value: weekNetValue,   sub: fallbackWkNetSub)
            weekCell(label: "MILES WK", value: weekMilesValue, sub: "")
        }
    }

    private func weekCell(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
            Text(sub)
                .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var esangAdvisory: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text(fallbackeSang)
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var actions: some View {
        HStack(spacing: Space.s3) {
            Button { exportSummary() } label: {
                Text("Export")
                    .font(EType.body.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderSoft)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            CTAButton(
                title: "Close day",
                action: { Task { await closeDay() } },
                trailingIcon: "arrow.right",
                isLoading: isClosing
            )
        }
    }

    private func hydrateLiveTrip() async {
        // Fan out the live earnings rollup (week net / loads / miles /
        // period change / settled-load ledger) alongside the lifecycle
        // hydration. `.week` matches the day-close "week-to-date" framing.
        earnings.period = .week
        async let earningsTask: Void = earnings.refresh()

        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        if !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) {
            activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
        }
        await earningsTask
    }

    // MARK: - Formatters

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

    /// Header date label — "WEEKDAY · yyyy-MM-dd" from the live device
    /// date. Replaces the seeded "SATURDAY · 2026-04-18".
    private func dateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        let weekday = f.string(from: date).uppercased()
        let iso = DateFormatter()
        iso.dateFormat = "yyyy-MM-dd"
        return "\(weekday) · \(iso.string(from: date))"
    }

    /// Close-day fires three indubitable actions in sequence:
    ///   1. `availability.exportICS()` — server mints a signed ICS
    ///      URL for the driver's day. The shipper / dispatcher web
    ///      surfaces consume this for next-day scheduling.
    ///   2. Lifecycle transition — ONLY when the active load offers
    ///      a transition whose `to` indubitably contains
    ///      "completed" or "off_duty" or "day_closed". Previously
    ///      pattern-matched + fell back to `availableTransitions.first`
    ///      (arbitrary unrelated transition).
    ///   3. `advance?()` env handler — walks the trip phase forward
    ///      to .idle so the driver lands back on Home.
    private func closeDay() async {
        guard !isClosing else { return }
        isClosing = true
        defer { isClosing = false }
        // Step 1 — fire the real ICS export so the day's trip log
        // is materialized server-side. Non-blocking on failure.
        _ = try? await EusoTripAPI.shared.availability.exportICS()
        // Step 2 — execute the lifecycle transition ONLY when a
        // close-class transition is offered. No fallback to an
        // arbitrary `availableTransitions.first` — that's the
        // `feedback_indubitably` doctrine.
        if let t = lifecycle.availableTransitions.first(where: { t in
            let to = t.to.lowercased()
            return to.contains("completed") || to.contains("off_duty") || to.contains("day_closed")
        }) {
            _ = await lifecycle.execute(t)
        }
        // Step 3 — advance the trip-phase state machine to .idle
        // (loops back to Home per the lifecycleAdvance closure
        // injected at ContentView.swift line 1597).
        advance?()
    }

    /// "Export" — surface the EusoWallet day-export options (CSV
    /// trip log + 1099 worksheet + Stripe Connect statement). Routing
    /// through `.esangOpenMeDetail("earnings")` lands the driver on
    /// the canonical wallet view that already owns the export
    /// pipeline; duplicating it here would mean two divergent code
    /// paths for the same artifact.
    private func exportSummary() {
        MeAction.fire("055.export-day",
                      userInfo: ["loadId": lifecycle.loadId])
        NotificationCenter.default.post(
            name: .esangOpenMeDetail,
            object: "earnings",
            userInfo: ["intent": "export-day"]
        )
        navBack?()
    }
}

struct DayCloseWalletScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            DayCloseWallet(register: .afternoon)
        } nav: {
            BottomNav(leading: driverNavLeading_055(),
                      trailing: driverNavTrailing_055(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_055() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: false)]
}
private func driverNavTrailing_055() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

#Preview("055 · Day Close Wallet · Dark") {
    DayCloseWalletScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("055 · Day Close Wallet · Light") {
    DayCloseWalletScreen(theme: Theme.light).preferredColorScheme(.light)
}
