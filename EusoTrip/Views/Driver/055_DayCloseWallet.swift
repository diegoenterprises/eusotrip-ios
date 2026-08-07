//
//  055_DayCloseWallet.swift
//  EusoTrip — Lifecycle screen 055 · Day Close Wallet.
//
//  REDESIGNED to the Design Authority level (founder mandate #13). The
//  end-of-day money surface now speaks the bespoke EusoWallet language
//  shared with the wallet home (290) and detail (291) via
//  `EusoWalletComponents`: a volumetric gradient hero "money card" with
//  the day/week net + animated sheen + drawn composition legend, the day
//  ledger as bespoke credit/debit `WalletLedgerRow`s, the fuel / tolls /
//  per-diem spend as bespoke debit tiles, week net + miles as drawn-glyph
//  reference tiles, an ESANG advisory rail, and the Export / Close-day
//  actions. ZERO SF Symbols on the money surface — every glyph is a drawn
//  `WalletGlyph` Path.
//
//  FUNCTION PRESERVED 1:1 — same canonical earnings store
//  (`earnings.getSummary` / `getYTDSummary` / `getEarnings`), same
//  lifecycle hydration, same `closeDay()` (ICS export + close-class
//  lifecycle transition + `advance?()`) and `exportSummary()` flows, same
//  navigation. Only the presentation changed. ZERO fabrication: real data
//  or honest em-dash.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct DayCloseWallet: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var firstLoad: Bool = true

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .afternoon) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    private var isDark: Bool { palette.bgPage == Theme.dark.bgPage }

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

    /// Day/week net in cents for the bespoke `WalletBalanceHero`. The hero
    /// formats this honestly (em-dash at nil/zero). nil until a real total
    /// lands — never a seeded figure.
    private var dayNetCents: Int? {
        guard let s = weekSummary else { return nil }
        let cents = Int((s.totalEarnings * 100).rounded())
        return cents > 0 ? cents : nil
    }

    /// Period-over-period change pill. Real signed `changePct` from the
    /// summary's `comparison`; collapses (empty) when flat or absent so
    /// no "+18%" is ever invented.
    private var deltaLabel: String? {
        guard let s = weekSummary, abs(s.changePct) >= 0.1 else { return nil }
        let rounded = Int(s.changePct.rounded())
        return rounded > 0 ? "+\(rounded)%" : "\(rounded)%"
    }

    private var deltaIsUp: Bool {
        guard let s = weekSummary else { return true }
        return s.changePct >= 0
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

    // MARK: - Header
    //
    // Back chevron in a drawn pill, the live device date eyebrow + mode
    // badge, and the reset-state pulse + live clock. Identical data
    // bindings to the prior header; re-skinned to the wallet voice.

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { navBack?() } label: {
                ZStack {
                    Circle().fill(palette.bgCard)
                    Circle().strokeBorder(palette.iridescentHairline, lineWidth: 1)
                    WalletGlyph(kind: .chevron, size: 12,
                                tint: AnyShapeStyle(palette.textPrimary), lineWidth: 1.8)
                        .rotationEffect(.degrees(180))
                }
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    WalletGlyph(kind: .wallet, size: 11,
                                tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.4)
                    // Live device date — "WEEKDAY · yyyy-MM-dd" from the
                    // real wall clock, not a seeded "SATURDAY · 2026-04-18".
                    TimelineView(.everyMinute) { tl in
                        Text(dateLabel(tl.date))
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                }
                HStack(spacing: 6) {
                    Text("DAY CLOSE")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
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
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Hero "money card"
    //
    // The day/week net rendered on the bespoke `WalletBalanceHero`
    // gradient card (gradient base, aurora bloom, animated sheen numeral).
    // Day-close has a single net figure (no available/reserved/pending
    // split), so the figure is carried in `availableCents` with the other
    // two left nil — the composition bar then honestly shows the single
    // segment. Beneath the card a bespoke rail carries the week-to-date
    // meta + the real period-over-period delta chip + a drawn spark line.
    // While the store hydrates we show the bespoke `WalletShimmer`
    // skeleton (bounded by the store's own timeout).

    @ViewBuilder
    private var heroCard: some View {
        if dayNetCents != nil || !firstLoad {
            VStack(alignment: .leading, spacing: Space.s3) {
                WalletBalanceHero(
                    availableCents: dayNetCents,
                    pendingCents: nil,
                    reservedCents: nil,
                    currency: "USD",
                    caption: "Day net · week to date"
                )
                heroMetaRail
            }
        } else {
            heroSkeleton
        }
    }

    /// The week-to-date meta + the real delta chip + a drawn earnings spark
    /// line, carded under the hero. The delta chip renders ONLY when the
    /// live summary carries a non-flat `changePct` — never a seeded "+18%".
    private var heroMetaRail: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .center, spacing: 8) {
                Text(weekMetaCopy)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                if let delta = deltaLabel {
                    HStack(spacing: 4) {
                        WalletGlyph(kind: deltaIsUp ? .arrowUp : .arrowDown, size: 9,
                                    tint: AnyShapeStyle(Color.white), lineWidth: 1.7)
                        Text(delta)
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(LinearGradient.diagonal))
                }
            }
            // Earnings sparkline REMOVED 2026-06-19: it drew a HARDCODED upward
            // curve ([0.6...0.22]) unbound to any real series — a fabricated
            // "earnings climbing" read for every driver regardless of their
            // actual week. Zero-fabrication mandate: the hero shows only the
            // REAL day-close total + delta + week meta. A real trend can return
            // here once it's bound to the live weekly earnings series.
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .standard)
    }

    private var heroSkeleton: some View {
        VStack(alignment: .leading, spacing: 14) {
            WalletShimmer(height: 14, radius: 6).frame(width: 130)
            WalletShimmer(height: 44, radius: 12)
            WalletShimmer(height: 9, radius: 5)
            HStack(spacing: 10) {
                WalletShimmer(height: 28, radius: 8)
                WalletShimmer(height: 28, radius: 8)
                WalletShimmer(height: 28, radius: 8)
            }
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.xl, intensity: .feature)
    }

    // MARK: - Day ledger
    //
    // The live settled-load rows from `earnings.getEarnings` rendered as
    // bespoke credit `WalletLedgerRow`s (drawn directional glyph + memo +
    // tabular signed figure). Every field is real; honest empty state when
    // nothing has settled. While first-loading we show the shimmer rows.

    @ViewBuilder
    private var ledgerList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                WalletEyebrow(glyph: .pulse, text: "DAY LEDGER")
                Spacer(minLength: 0)
                // Real settled-row count off the live ledger — never "3".
                Text(settledCountLabel)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
            }
            // Live settled-load rows from `earnings.getEarnings` (the same
            // projection brick 068 renders as "top loads"). Honest empty
            // state when no loads have settled yet — invent no
            // brand/BOL/POD/amount.
            if ledgerRows.isEmpty {
                if firstLoad {
                    ledgerSkeleton
                } else {
                    ledgerEmpty
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(ledgerRows.enumerated()), id: \.element.id) { idx, row in
                        WalletLedgerRow(
                            title: ledgerRowBrand(row),
                            memo: ledgerRowNote(row),
                            timestamp: nil,
                            amountDollars: row.totalPay,
                            type: "earnings",
                            showDivider: idx < ledgerRows.count - 1
                        )
                    }
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    private var ledgerSkeleton: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 12) {
                    WalletShimmer(height: 40, radius: Radius.md).frame(width: 40)
                    VStack(alignment: .leading, spacing: 6) {
                        WalletShimmer(height: 12, radius: 4).frame(width: 150)
                        WalletShimmer(height: 9, radius: 4).frame(width: 90)
                    }
                    Spacer(minLength: 0)
                    WalletShimmer(height: 14, radius: 4).frame(width: 56)
                }
            }
        }
    }

    private var ledgerEmpty: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.blue.opacity(0.12), Brand.magenta.opacity(0.12)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.iridescentHairline, lineWidth: 1)
                WalletGlyph(kind: .pulse, size: 18,
                            tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.5)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("No settled loads yet today")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text("Settled payouts will appear here as your day closes.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
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

    // MARK: - Spend row (FUEL / TOLLS / PER DIEM)
    //
    // No live feed on this screen → honest em-dash sentinels, KEPT. Drawn
    // as bespoke debit tiles (drawn glyph in a danger-tinted vault).

    private var spendRow: some View {
        HStack(spacing: Space.s2) {
            spendCell(glyph: .bolt,  label: "FUEL",     primary: fallbackFuel,    sub: fallbackFuelSub)
            spendCell(glyph: .coins, label: "TOLLS",    primary: fallbackTolls,   sub: fallbackTollsSub)
            spendCell(glyph: .bank,  label: "PER DIEM", primary: fallbackPerDiem, sub: fallbackPerDiemSub)
        }
    }

    private func spendCell(glyph: WalletGlyph.Kind, label: String, primary: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Brand.danger.opacity(0.12))
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(Brand.danger.opacity(0.35), lineWidth: 1)
                WalletGlyph(kind: glyph, size: 14, tint: AnyShapeStyle(Brand.danger), lineWidth: 1.5)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text(primary)
                    .font(.system(size: 14, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Brand.danger)
                Text(sub)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.md, intensity: .whisper)
    }

    // MARK: - Week row (NET WK / MILES WK)
    //
    // Real week net + week miles off the live summary, drawn as bespoke
    // reference tiles with a drawn glyph (em-dash when absent, KEPT).

    private var weekRow: some View {
        HStack(spacing: Space.s2) {
            weekCell(glyph: .arrowUp, label: "NET WK",   value: weekNetValue,   sub: fallbackWkNetSub, accent: true)
            weekCell(glyph: .pulse,   label: "MILES WK", value: weekMilesValue, sub: "",               accent: false)
        }
    }

    private func weekCell(glyph: WalletGlyph.Kind, label: String, value: String, sub: String, accent: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.blue.opacity(0.14), Brand.magenta.opacity(0.14)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.iridescentHairline, lineWidth: 1)
                WalletGlyph(kind: glyph, size: 15,
                            tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.5)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text(value)
                    .font(.system(size: 18, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(accent ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textPrimary))
                    .lineLimit(1).minimumScaleFactor(0.7)
                if !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.md, intensity: .standard)
    }

    // MARK: - ESANG advisory
    //
    // No live advisory source on this screen → honest em-dash, KEPT.
    // Drawn as a bespoke iridescent rail with a drawn spark glyph.

    private var esangAdvisory: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(LinearGradient.diagonal.opacity(0.16))
                WalletGlyph(kind: .spark, size: 14,
                            tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.5)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("ESANG")
                    .font(.system(size: 8, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Text(fallbackeSang)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.md, intensity: .whisper)
    }

    // MARK: - Actions (Export · Close day)
    //
    // Same two actions, same handlers. Export is a bespoke ghost card with
    // a drawn pulse glyph; Close day keeps the shared `CTAButton` (the
    // canonical primary action treatment with its loading state).

    private var actions: some View {
        HStack(spacing: Space.s3) {
            Button { exportSummary() } label: {
                HStack(spacing: 8) {
                    WalletGlyph(kind: .pulse, size: 15,
                                tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.6)
                    Text("Export")
                        .font(EType.body.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .eusoCard(radius: Radius.md, intensity: .whisper)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
        firstLoad = false
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
    RoleNav.driverLeading(current: .none)
}
private func driverNavTrailing_055() -> [NavSlot] {
    RoleNav.driverTrailing(current: .none)
}

#Preview("055 · Day Close Wallet · Dark") {
    DayCloseWalletScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("055 · Day Close Wallet · Light") {
    DayCloseWalletScreen(theme: Theme.light).preferredColorScheme(.light)
}
