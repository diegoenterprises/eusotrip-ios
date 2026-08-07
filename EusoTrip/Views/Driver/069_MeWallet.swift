//
//  069_MeWallet.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · EusoWallet 8-section rebuild)
//
//  Screen 069 · Me · Wallet — the canonical EusoWallet hub per
//  SKILL.md §9 (8-section rebuild). The driver's single source of
//  truth for money: live balance, payouts, settlements, transactions,
//  factoring offers, linked accounts, and tax withholdings.
//
//  ── DESIGN AUTHORITY RE-SKIN (founder mandate #722) ──
//  The founder called the prior layout "ai coded and basic looking."
//  This screen is now re-skinned 1:1 to the FOUNDER-APPROVED bespoke
//  wallet language shared with 290_WalletHome / 291_EusoWalletDetail and
//  defined in `Views/Components/EusoWalletComponents.swift`:
//    • Hero balance → `WalletBalanceHero` (volumetric money card, gradient
//      numeral + animated sheen + drawn `WalletCompositionBar`).
//    • Section headers → `WalletEyebrow` (drawn-glyph small-caps eyebrow).
//    • Activity rows → `WalletLedgerRow` (drawn directional credit/debit
//      glyph + intention spark + signed tabular amount).
//    • Payouts/settlements → `WalletHoldTile`-styled bespoke vault rows.
//    • Skeletons → `WalletShimmer` (bounded brand shimmer).
//    • Every glyph is a drawn `WalletGlyph` Path — ZERO SF Symbols on the
//      money surface; gradient (1473FF→BE01FF) is the only accent.
//  SVG/design owns the LOOK; iOS owns the FUNCTION — every store, proc,
//  @State, action, sheet, and navigation below is PRESERVED unchanged.
//  Zero fabrication: real data or honest em-dash.
//
//  Brick port history:
//    • 69th firing (2026-04-24, eusotrip-killers scheduled task) —
//      ported per SKILL.md §9 spec, 8 sections wired to existing
//      live stores in `ViewModels/LiveDataStores.swift`. All 12
//      backend endpoints verified LIVE by the 68th firing's
//      `scripts/verify-trpc-endpoints.sh` sweep:
//        wallet.getBalance · wallet.getInstantPayoutEligibility
//        wallet.getTransactions · wallet.getPayoutMethods
//        wallet.attachStripePaymentMethod · wallet.createPlaidLinkToken
//        wallet.createStripeSetupIntent · wallet.exchangePlaidPublicToken
//        settlementBatching.getDriverBatchView · factoring.getOffer
//        tax.getSummary · tax.get1099
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data, dynamic ready pages with 0 data"):
//
//    §1 Hero balance      — `WalletBalanceStore` · wallet.getBalance.
//                            Available + pending + reserved split rendered
//                            on the bespoke money card. Zero-balance
//                            renders honestly (em-dash) — a valid loaded
//                            state for a brand-new driver with no settled
//                            loads yet.
//    §2 Quick actions     — Cash out / Add method only. The brick
//                            deliberately omits Transfer / Deposit until
//                            the corresponding wallet mutations land
//                            server-side. No dead buttons, no stub
//                            dialogs. Cash out → DriverCashOutSheet (live
//                            wallet.requestPayout); Add method →
//                            AddPaymentAccountSheet (Plaid + Stripe).
//    §3 Weekly chart      — `WeeklyEarningsStore` · earnings.
//                            getWeeklySummaries(weeks: 7). Bars use
//                            `LinearGradient.diagonal`; x-axis = day
//                            initials derived from `weekStart`. Zero-
//                            earnings weeks render as 1pt baseline
//                            ticks — visible but honest.
//    §4 Upcoming payouts  — `UpcomingSettlementsStore` ·
//                            settlementBatching.getDriverBatchView.
//                            Filter to first 5 non-paid batches.
//    §5 Activity feed     — `WalletTransactionsStore` ·
//                            wallet.getTransactions. First 8 rows
//                            inline as bespoke ledger entries.
//    §6 Factoring offer   — `FactoringOfferStore` · factoring.getOffer
//                            (eligible-only). Surfaces only when a
//                            current load + HaulPay eligibility exist.
//                            Otherwise the section collapses entirely.
//    §7 Linked accounts   — `WalletPaymentMethodsStore` ·
//                            wallet.getPayoutMethods. Bank + card
//                            rows masked to last 4. Add / manage CTA
//                            opens AddPaymentAccountSheet.
//    §8 Tax withholdings  — `TaxSummaryStore` · tax.getSummary +
//                            `Tax1099Store` · tax.get1099. YTD
//                            withheld + quarterly estimate. 1099
//                            download disabled until the IRS issuance
//                            window (server gate via
//                            `TaxAPI.Tax1099Document.available`).
//

import SwiftUI

// MARK: - Screen root

struct MeWallet: View {
    @Environment(\.palette) var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var session: EusoTripSession

    // §1 hero balance
    @StateObject private var balance = WalletBalanceStore()
    // §3 chart
    @StateObject private var weekly = WeeklyEarningsStore()
    // §4 upcoming payouts
    @StateObject private var settlements = UpcomingSettlementsStore()
    // §5 activity feed
    @StateObject private var txns = WalletTransactionsStore()
    // §6 factoring offer
    @StateObject private var factoring = FactoringOfferStore()
    // §7 linked accounts
    @StateObject private var methods = WalletPaymentMethodsStore()
    // §8 tax withholdings
    @StateObject private var tax = TaxSummaryStore()
    @StateObject private var ten99 = Tax1099Store()

    @State private var showAddPayout: Bool = false
    @State private var showCashOut: Bool = false

    private var isDark: Bool { palette.bgPage == Theme.dark.bgPage }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s5) {
                header
                heroBalance              // §1
                quickActions             // §2
                EusoCardIssuePanel(
                    title: "EusoCard",
                    subtitle: "Virtual spend card for fuel, tolls and settlement cash"
                )
                weeklyChart              // §3
                upcomingPayouts          // §4
                activityFeed             // §5
                factoringOffer           // §6
                linkedAccounts           // §7
                walletCardStyleRow       // §7b — pickup-pass look picker
                taxWithholdings          // §8
                disclosureFooter
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(isPresented: $showAddPayout) {
            AddPaymentAccountSheet(onLinked: {
                Task { await reload() }
            })
            .eusoSheetX()
        }
        .sheet(isPresented: $showCashOut) {
            DriverCashOutSheet(
                available: availableBalance,
                currencyCode: balanceCurrency,
                methods: linkedMethods,
                onAddMethod: {
                    showCashOut = false
                    showAddPayout = true
                },
                onCompleted: {
                    Task { await reload() }
                }
            )
            .eusoSheetX()
        }
    }

    /// Live available balance for the cash-out validator. Falls back to
    /// 0 in any non-loaded state so the sheet caps the amount honestly
    /// rather than letting a stale/optimistic value through.
    private var availableBalance: Double {
        if case .loaded(let b) = balance.state { return b.available }
        return 0
    }

    private var balanceCurrency: String {
        if case .loaded(let b) = balance.state { return b.currency }
        return "USD"
    }

    /// Linked payout methods sourced from the §7 store (wallet.getPayoutMethods).
    /// Empty when nothing is linked — the sheet shows the "add a method first"
    /// state in that case.
    private var linkedMethods: [WalletPaymentMethod] {
        if case .loaded(let rows) = methods.state { return rows }
        return []
    }

    // Fan out every store in parallel. UpcomingSettlements + factoring
    // require seed values from the session before they can fetch — the
    // store contract is "if seed is nil, fetch returns nil and the
    // store folds to .empty"; we still kick off the call so the empty
    // branch resolves rather than hanging on .loading.
    private func reload() async {
        // Settlements: seed driverId from the live session. AuthUser.id
        // is a String on the wire; settlementBatching.getDriverBatchView
        // wants an Int. Same pattern as 055_DayCloseWallet.swift:175 and
        // 070_MeSettlements.swift:85. Server returns { batches: [] } when
        // 0 / unset, which folds to .empty.
        settlements.driverId = Int(session.user?.id ?? "0") ?? 0

        // Factoring: only call when an active loadId exists. Active
        // load is owned upstream of this brick (DriverTripController);
        // until that env wiring lands here we leave loadId nil and the
        // store collapses §6 cleanly.
        // factoring.loadId = trip.activeLoadId  (wired in 70th firing)

        async let a: Void  = balance.refresh()
        async let b: Void  = weekly.refresh()
        async let c: Void  = settlements.refresh()
        async let d: Void  = txns.refresh()
        async let e: Void  = factoring.refresh()
        async let f: Void  = methods.refresh()
        async let g: Void  = tax.refresh()
        async let h: Void  = ten99.refresh()
        _ = await (a, b, c, d, e, f, g, h)
    }

    // MARK: Header — bespoke eyebrow + drawn wallet brand mark

    private var header: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 6) {
                WalletEyebrow(glyph: .wallet, text: "DRIVER · EUSOWALLET")
                Text("EusoWallet")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("Balance · settlements · activity")
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
            // Iridescent brand mark — drawn wallet glyph (no SF Symbol).
            // ESANG thinking pulse rides on top while any store loads.
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 40, height: 40)
                if anyLoading {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.55), lineWidth: 2)
                        .frame(width: 40, height: 40)
                        .opacity(0.0)
                }
                WalletGlyph(kind: .wallet, size: 19, tint: AnyShapeStyle(Color.white), lineWidth: 1.6)
            }
            .shadow(color: Brand.magenta.opacity(isDark ? 0.45 : 0.22), radius: 10, x: 0, y: 4)
        }
    }

    private var anyLoading: Bool {
        balance.isLoading || weekly.isLoading || settlements.isLoading
            || txns.isLoading || factoring.isLoading || methods.isLoading
            || tax.isLoading || ten99.isLoading
    }

    // MARK: §1 — Hero balance (bespoke WalletBalanceHero money card)

    @ViewBuilder
    private var heroBalance: some View {
        switch balance.state {
        case .loading:
            heroSkeleton
        case .empty, .error:
            // Honest zero / degrade — the bespoke card with nil cents
            // renders an em-dash hero + "no funds yet" composition track.
            WalletBalanceHero(
                availableCents: nil,
                pendingCents: nil,
                reservedCents: nil,
                currency: balanceCurrency,
                caption: "Waiting on first settlement"
            )
        case .loaded(let b):
            heroLoaded(b)
        }
    }

    /// Bounded bespoke shimmer skeleton (mirrors 290/291 hero skeleton).
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

    /// The hero takes cents; the driver `wallet.getBalance` store hands back
    /// dollars (`available`/`pending`/`reserved`). Convert to cents at the
    /// render site — no fabrication, just a unit change. The hero's internal
    /// composition total is available+pending+reserved (the real split). The
    /// server's own `total` (which can fold escrow in) is surfaced honestly
    /// as a companion reference row below so nothing is invented or hidden.
    private func heroLoaded(_ b: WalletAPI.WalletBalance) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            WalletBalanceHero(
                availableCents: cents(b.available),
                pendingCents: cents(b.pending),
                reservedCents: cents(b.reserved),
                currency: b.currency,
                caption: "Available to cash out"
            )
            totalReferenceRow(b)
        }
    }

    /// The server-authoritative `total` (incl. escrow) shown as an honest
    /// companion to the composition card — a single drawn-glyph reference
    /// row, em-dash at zero.
    private func totalReferenceRow(_ b: WalletAPI.WalletBalance) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.blue.opacity(0.14), Brand.magenta.opacity(0.14)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.iridescentHairline, lineWidth: 1)
                WalletGlyph(kind: .pie, size: 16, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.5)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text("Total wallet balance")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text("Available + pending + reserved + escrow")
                    .font(EType.micro).foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
            Text(currency(b.total, code: b.currency))
                .font(.system(size: 15, weight: .heavy, design: .rounded)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.md, intensity: .whisper)
    }

    // MARK: §2 — Quick actions (bespoke drawn-glyph pills)

    private var quickActions: some View {
        // TWO real, working actions. No dead pills, no stub dialogs.
        // "Cash out" opens the real DriverCashOutSheet — pick a linked
        // payout method, enter an amount (capped at available balance,
        // min $1), choose instant vs standard, and call the live
        // `wallet.requestPayout` Stripe Connect mutation. "Add payout
        // method" opens AddPaymentAccountSheet (Plaid + Stripe). Both
        // back working flows; nothing here is a stub.
        HStack(spacing: Space.s2) {
            actionPill(
                glyph: .arrowDown,
                title: "Cash out",
                style: .primary
            ) {
                showCashOut = true
            }
            actionPill(
                glyph: .bank,
                title: "Add method",
                style: .secondary
            ) {
                showAddPayout = true
            }
        }
    }

    private enum ActionStyle { case primary, secondary }

    private func actionPill(
        glyph: WalletGlyph.Kind,
        title: String,
        style: ActionStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Space.s2) {
                ZStack {
                    Circle()
                        .fill(style == .primary
                              ? AnyShapeStyle(Color.white.opacity(0.18))
                              : AnyShapeStyle(LinearGradient(colors: [Brand.blue.opacity(0.16), Brand.magenta.opacity(0.16)],
                                                            startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .frame(width: 30, height: 30)
                    WalletGlyph(
                        kind: glyph,
                        size: 16,
                        tint: style == .primary
                            ? AnyShapeStyle(Color.white)
                            : AnyShapeStyle(LinearGradient.diagonal),
                        lineWidth: 1.7
                    )
                }
                Text(title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(
                        style == .primary
                        ? AnyShapeStyle(Color.white)
                        : AnyShapeStyle(palette.textPrimary)
                    )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s3)
            .background {
                if style == .primary {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(LinearGradient.diagonal)
                        .overlay(alignment: .top) {
                            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.04)],
                                                             startPoint: .top, endPoint: .bottom), lineWidth: 1)
                        }
                        .shadow(color: Brand.blue.opacity(isDark ? 0.32 : 0.15), radius: 12, x: 0, y: 7)
                }
            }
            .modifier(SecondaryPillCard(active: style == .secondary))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Whisper-card surface for the secondary pill so it reads as a card
    /// (not a flat fill) while the primary keeps its gradient.
    private struct SecondaryPillCard: ViewModifier {
        let active: Bool
        func body(content: Content) -> some View {
            if active {
                content.eusoCard(radius: Radius.lg, intensity: .whisper)
            } else {
                content
            }
        }
    }

    // MARK: §3 — Weekly chart (bespoke eyebrow + gradient bars)

    @ViewBuilder
    private var weeklyChart: some View {
        switch weekly.state {
        case .loading:
            chartSkeleton
        case .empty, .error:
            chartEmpty
        case .loaded(let bars):
            chartLoaded(bars)
        }
    }

    private var chartSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            WalletEyebrow(glyph: .pulse, text: "7-DAY NET")
            HStack(alignment: .bottom, spacing: Space.s2) {
                ForEach(0..<7, id: \.self) { i in
                    WalletShimmer(height: CGFloat(40 + (i % 3) * 28), radius: 4)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 120)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    private var chartEmpty: some View {
        VStack(alignment: .leading, spacing: 12) {
            WalletEyebrow(glyph: .pulse, text: "7-DAY NET")
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(LinearGradient(colors: [Brand.blue.opacity(0.12), Brand.magenta.opacity(0.12)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.iridescentHairline, lineWidth: 1)
                    WalletGlyph(kind: .pulse, size: 18, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.5)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No earnings yet").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text("Your 7-day net chart fills in as settlements clear.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .standard)
    }

    private func chartLoaded(_ rows: [WeeklyEarningsBar]) -> some View {
        // Reverse so the chart reads left-to-right (oldest → newest)
        // and clamp to the most recent 7.
        let bars = Array(rows.prefix(7).reversed())
        let maxVal = max(bars.map(\.totalEarnings).max() ?? 0, 1)
        let netTotal = bars.map(\.totalEarnings).reduce(0, +)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                WalletEyebrow(glyph: .pulse, text: "7-DAY NET")
                Spacer(minLength: 0)
                Text(WalletMoney.usdDollarsPrecise(netTotal > 0 ? netTotal : nil))
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
            }
            HStack(alignment: .bottom, spacing: Space.s2) {
                ForEach(bars) { row in
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(LinearGradient.diagonal)
                            .frame(height: barHeight(row.totalEarnings, max: maxVal))
                            .frame(maxWidth: .infinity)
                            .shadow(color: Brand.blue.opacity(isDark ? 0.30 : 0.12), radius: 6, x: 0, y: 3)
                        Text(weekTick(row.weekStart))
                            .font(EType.micro)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
            .frame(height: 132)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    private func barHeight(_ v: Double, max: Double) -> CGFloat {
        let normalized = max > 0 ? CGFloat(v / max) : 0
        // 1pt baseline tick when the week earned $0 — visible but honest.
        return Swift.max(normalized * 108, 1)
    }

    /// Two-letter day initial from an ISO `weekStart`. Falls back to
    /// the trailing two characters of the string when parsing fails so
    /// the bar always has a label rather than rendering a gap.
    private func weekTick(_ iso: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: String(iso.prefix(10))) {
            let f2 = DateFormatter()
            f2.dateFormat = "MMM d"
            return f2.string(from: date)
        }
        return String(iso.suffix(5))
    }

    // MARK: §4 — Upcoming settlements (bespoke vault rows)

    @ViewBuilder
    private var upcomingPayouts: some View {
        switch settlements.state {
        case .loading:
            payoutsSkeleton
        case .empty, .error:
            sectionEmpty(
                eyebrowGlyph: .coins,
                eyebrowText: "UPCOMING PAYOUTS",
                glyph: .coins,
                title: "No payouts pending",
                subtitle: "New batches appear here as loads settle."
            )
        case .loaded(let rows):
            let shown = Array(rows.prefix(5))
            let pendingTotal = shown.map(\.amount).reduce(0, +)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    WalletEyebrow(glyph: .coins, text: "UPCOMING PAYOUTS")
                    Spacer(minLength: 0)
                    Text(WalletMoney.usdDollarsPrecise(pendingTotal > 0 ? pendingTotal : nil))
                        .font(.system(size: 13, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                }
                VStack(spacing: 8) {
                    ForEach(shown) { row in
                        settlementRow(row)
                    }
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.lg, intensity: .standard)
        }
    }

    private var payoutsSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            WalletEyebrow(glyph: .coins, text: "UPCOMING PAYOUTS")
            VStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { _ in
                    WalletShimmer(height: 60, radius: Radius.md)
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .standard)
    }

    /// Bespoke settlement vault row — drawn coins glyph in an
    /// iridescent vault, batch + period, signed amount in tabular figures.
    private func settlementRow(_ row: DriverSettlementBatch) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.blue.opacity(0.14), Brand.magenta.opacity(0.14)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.iridescentHairline, lineWidth: 1)
                WalletGlyph(kind: .coins, size: 16, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.6)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.batchNumber)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(periodLabel(row))
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 4) {
                Text(currency(row.amount, code: "USD"))
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text(row.status.uppercased())
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.info)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Brand.info.opacity(0.14)))
            }
        }
        .padding(.horizontal, Space.s3).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.md, intensity: .whisper)
    }

    private func periodLabel(_ row: DriverSettlementBatch) -> String {
        let start = formatShort(row.periodStart)
        let end = formatShort(row.periodEnd)
        switch (start, end) {
        case (let s?, let e?): return "\(s) – \(e)"
        case (let s?, nil):    return s
        case (nil, let e?):    return e
        default:               return row.status.capitalized
        }
    }

    // MARK: §5 — Activity feed (bespoke WalletLedgerRow)

    @ViewBuilder
    private var activityFeed: some View {
        switch txns.state {
        case .loading:
            activitySkeleton
        case .empty, .error:
            sectionEmpty(
                eyebrowGlyph: .pulse,
                eyebrowText: "ACTIVITY",
                glyph: .pulse,
                title: "No transactions yet",
                subtitle: "Settlements, fees and payouts will land here."
            )
        case .loaded(let rows):
            let shown = Array(rows.prefix(8))
            VStack(alignment: .leading, spacing: 12) {
                WalletEyebrow(glyph: .pulse, text: "ACTIVITY")
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { idx, txn in
                        WalletLedgerRow(
                            title: txn.title,
                            memo: txn.subtitle,
                            timestamp: txn.timestamp,
                            amountDollars: txn.amount,
                            type: ledgerType(txn),
                            showDivider: idx < shown.count - 1
                        )
                    }
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.lg, intensity: .feature)
        }
    }

    private var activitySkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            WalletEyebrow(glyph: .pulse, text: "ACTIVITY")
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
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    /// Map the driver `WalletTxn.kind` to the ledger row's `type` hint so
    /// the bespoke directional glyph (`WalletLedgerRow.glyph`) is chosen
    /// honestly: fees/payouts → arrow-down, refunds → arrow-up, bonuses →
    /// spark, everything else by sign.
    private func ledgerType(_ txn: WalletTxn) -> String {
        switch txn.kind {
        case "fee":            return "fee"
        case "instant_payout": return "payout"
        case "refund":         return "refund"
        case "bonus":          return "bonus"
        default:               return txn.kind
        }
    }

    // MARK: §6 — Factoring offer (collapses when no offer)

    @ViewBuilder
    private var factoringOffer: some View {
        // Only render the section when the store actually has an
        // eligible offer. No "No offers" placeholder — the absence
        // of the section IS the empty state. This is per SKILL.md
        // §13 guidance: don't surface a UI for a feature that
        // doesn't apply to the current driver state.
        if case .loaded(let offer?) = factoring.state {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(.white.opacity(0.18))
                        WalletGlyph(kind: .bolt, size: 20, tint: AnyShapeStyle(Color.white), lineWidth: 1.9)
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Get paid today")
                            .font(.system(size: 17, weight: .heavy)).foregroundStyle(.white)
                        Text("HaulPay advance available")
                            .font(EType.micro).foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer(minLength: 0)
                }
                Rectangle()
                    .fill(Color.white.opacity(0.22))
                    .frame(height: 1)
                // Net = grossAmount - feeAmount per FactoringAPI.Offer wire shape
                // (frontend/server/routers/factoring.ts). Surface the gross +
                // fee + net so the driver sees the full breakdown — no spin.
                HStack(spacing: Space.s4) {
                    offerStat(label: "NET", value: currency(offer.netAmount, code: offer.currency), strong: true)
                    offerStat(label: "GROSS", value: currency(offer.grossAmount, code: offer.currency))
                    offerStat(label: "FEE", value: currency(offer.feeAmount, code: offer.currency))
                    Spacer(minLength: 0)
                }
                Text("Open the active load detail to accept this advance.")
                    .font(EType.micro)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient.diagonal)
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.04)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .shadow(color: Brand.blue.opacity(isDark ? 0.35 : 0.16), radius: 14, x: 0, y: 8)
        }
    }

    private func offerStat(label: String, value: String, strong: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(.white.opacity(0.7))
            Text(value)
                .font(.system(size: strong ? 16 : 13, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }

    // MARK: §7 — Linked accounts (bespoke method rows)

    @ViewBuilder
    private var linkedAccounts: some View {
        switch methods.state {
        case .loading:
            methodsSkeleton
        case .empty, .error:
            linkedEmpty
        case .loaded(let rows):
            VStack(alignment: .leading, spacing: 12) {
                WalletEyebrow(glyph: .bank, text: "LINKED ACCOUNTS")
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        methodRow(row)
                    }
                    manageMethodsButton
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.lg, intensity: .standard)
        }
    }

    // MARK: §7b — Wallet card style (pickup-pass look picker)
    //
    // Mirrors the shipper Wallet hub's "Wallet card style" row (290 §Manage).
    // The same pure WalletCardPickerView is registered for the driver role as
    // "WalletCardStyleDriver"; this row pushes it through the canonical driver
    // Me nav signal (`.eusoDriverMeNavSwap`) — a horizontal push, never a
    // slide-up. Same glyph/title/subtitle voice as the shipper row.

    private var walletCardStyleRow: some View {
        Button {
            NotificationCenter.default.post(
                name: .eusoDriverMeNavSwap, object: nil,
                userInfo: ["screenId": "WalletCardStyleDriver"]
            )
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(LinearGradient(colors: [Brand.blue.opacity(0.14), Brand.magenta.opacity(0.14)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.iridescentHairline, lineWidth: 1)
                    WalletGlyph(kind: .spark, size: 16,
                                tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.5)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wallet card style")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("Pick the look of your pickup pass")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                WalletGlyph(kind: .chevron, size: 13,
                            tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.5)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .eusoCard(radius: Radius.lg, intensity: .standard)
        }
        .buttonStyle(.plain)
    }

    private var methodsSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            WalletEyebrow(glyph: .bank, text: "LINKED ACCOUNTS")
            VStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { _ in
                    WalletShimmer(height: 52, radius: Radius.md)
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .standard)
    }

    private var linkedEmpty: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            WalletEyebrow(glyph: .bank, text: "LINKED ACCOUNTS")
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(LinearGradient(colors: [Brand.blue.opacity(0.12), Brand.magenta.opacity(0.12)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.iridescentHairline, lineWidth: 1)
                    WalletGlyph(kind: .bank, size: 18, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.6)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No methods linked").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text("Add a bank or card to receive instant payouts.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
            manageMethodsButton
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .standard)
    }

    /// Bespoke linked-method row — drawn bank/coins glyph in an iridescent
    /// vault, institution + masked tail, an INSTANT pill when eligible.
    private func methodRow(_ m: WalletPaymentMethod) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.blue.opacity(0.14), Brand.magenta.opacity(0.14)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.iridescentHairline, lineWidth: 1)
                WalletGlyph(kind: m.kind == "bank" ? .bank : .coins, size: 15,
                            tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.5)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.institution)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("••\(m.mask)\(m.isDefault ? " · default" : "")")
                    .font(EType.micro)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            if m.isInstant {
                HStack(spacing: 4) {
                    WalletGlyph(kind: .bolt, size: 10, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.4)
                    Text("INSTANT")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Brand.blue.opacity(0.12)))
            }
        }
        .padding(.horizontal, Space.s3).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.md, intensity: .whisper)
    }

    private var manageMethodsButton: some View {
        // "Add another" opens the same AddPaymentAccountSheet the §2
        // primary action uses. Full manage / set-default / unlink lives
        // on screen 077 and is reachable from the Wallet tab in
        // DriverTabPanes — keeping this row a single non-dead action
        // (no NotificationCenter shim, no dead nav signal).
        Button {
            showAddPayout = true
        } label: {
            HStack(spacing: 6) {
                WalletGlyph(kind: .bank, size: 13, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.5)
                Text("Add another")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                WalletGlyph(kind: .chevron, size: 11, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: §8 — Tax withholdings (bespoke card)

    @ViewBuilder
    private var taxWithholdings: some View {
        switch tax.state {
        case .loading:
            taxSkeleton
        case .empty, .error:
            sectionEmpty(
                eyebrowGlyph: .pie,
                eyebrowText: "TAX WITHHOLDINGS",
                glyph: .pie,
                title: "No tax data yet",
                subtitle: "We'll surface YTD withholdings after your first settled load."
            )
        case .loaded(let summary?):
            taxCard(summary)
        case .loaded(_):
            EmptyView()  // .loaded(nil) — should never hit per foldState
        }
    }

    private var taxSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            WalletEyebrow(glyph: .pie, text: "TAX WITHHOLDINGS")
            WalletShimmer(height: 92, radius: Radius.md)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .standard)
    }

    private func taxCard(_ s: TaxAPI.TaxSummary) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            WalletEyebrow(glyph: .pie, text: "TAX WITHHOLDINGS")
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("YTD WITHHELD")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Text(currency((s.federalWithheld ?? 0) + (s.stateWithheld ?? 0),
                                   code: s.currency))
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Q ESTIMATE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Text(currency(s.quarterlyEstimate ?? 0, code: s.currency))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
            }
            IridescentHairline()
            ten99Row
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    @ViewBuilder
    private var ten99Row: some View {
        switch ten99.state {
        case .loaded(let doc?):
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(LinearGradient(colors: [Brand.blue.opacity(0.14), Brand.magenta.opacity(0.14)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.iridescentHairline, lineWidth: 1)
                    WalletGlyph(kind: .pulse, size: 15, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.5)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(doc.documentType ?? "1099") · \(String(doc.year))")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(doc.available ? "Issued \(formatShort(doc.issuedAt) ?? "—")" : "Pending IRS issuance window")
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
                if doc.available, let urlStr = doc.url, let url = URL(string: urlStr) {
                    Link(destination: url) {
                        HStack(spacing: 5) {
                            WalletGlyph(kind: .arrowDown, size: 12, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.5)
                            Text("Download")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(LinearGradient.diagonal)
                        }
                    }
                } else {
                    Text("Unavailable")
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(.horizontal, Space.s3).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.md, intensity: .whisper)
        default:
            HStack(spacing: 6) {
                WalletGlyph(kind: .pulse, size: 12, tint: AnyShapeStyle(palette.textTertiary), lineWidth: 1.4)
                Text("1099 · awaiting tax-year close")
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Shared helpers

    /// Bespoke empty/degrade card with an eyebrow + drawn glyph vault.
    private func sectionEmpty(
        eyebrowGlyph: WalletGlyph.Kind,
        eyebrowText: String,
        glyph: WalletGlyph.Kind,
        title: String,
        subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            WalletEyebrow(glyph: eyebrowGlyph, text: eyebrowText)
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(LinearGradient(colors: [Brand.blue.opacity(0.12), Brand.magenta.opacity(0.12)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.iridescentHairline, lineWidth: 1)
                    WalletGlyph(kind: glyph, size: 18, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.5)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text(subtitle).font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .standard)
    }

    private var disclosureFooter: some View {
        HStack(spacing: 8) {
            WalletGlyph(kind: .lock, size: 12, tint: AnyShapeStyle(palette.textTertiary), lineWidth: 1.4)
            Text("EusoWallet routes through Stripe Connect (Custom). Settlements clear within 1–2 business days. Instant payouts subject to eligibility.")
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.leading)
        }
        .padding(.top, Space.s2)
    }

    // MARK: Formatters

    /// Dollars → cents for the cents-native bespoke hero/composition bar.
    /// Honest: a non-positive value maps to nil so the hero em-dashes
    /// rather than rendering a fake $0 fill.
    private func cents(_ dollars: Double) -> Int? {
        guard dollars > 0 else { return nil }
        return Int((dollars * 100).rounded())
    }

    private func currency(_ v: Double, code: String?) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code ?? "USD"
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }

    private func formatShort(_ iso: String?) -> String? {
        guard let iso = iso else { return nil }
        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyyy-MM-dd"
        if let date = inFmt.date(from: String(iso.prefix(10))) {
            let out = DateFormatter()
            out.dateFormat = "MMM d"
            return out.string(from: date)
        }
        // Try ISO-8601 with time
        let iso8601 = ISO8601DateFormatter()
        if let date = iso8601.date(from: iso) {
            let out = DateFormatter()
            out.dateFormat = "MMM d"
            return out.string(from: date)
        }
        return nil
    }
}

// MARK: - Cash-out sheet (inline)
//
// Real withdraw flow backed by `wallet.requestPayout`
// (EusoTripAPI.shared.walletExtras.requestPayout). Pick a linked payout
// method, enter an amount validated against the live available balance
// (server min $1.00), choose instant vs standard ACH, then fire the
// mutation. Stripe Connect only debits the wallet AFTER it confirms, so a
// thrown error means the balance is untouched — we surface the server
// message verbatim. On success we show the honest payout ack (fee, net,
// ETA) and signal the parent to refresh the balance.
//
// RE-SKINNED to the bespoke wallet language (WalletGlyph / WalletEyebrow /
// eusoCard intensities, drawn check/selection Paths). Every piece of LOGIC
// — parse, validation, submit, ack — is preserved unchanged.

private struct DriverCashOutSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let available: Double
    let currencyCode: String
    let methods: [WalletPaymentMethod]
    let onAddMethod: () -> Void
    let onCompleted: () -> Void

    @State private var selectedMethodId: String?
    @State private var amountText: String = ""
    @State private var instant: Bool = false
    @State private var submitting: Bool = false
    @State private var errorText: String?
    @State private var ack: WalletExtrasAPI.RequestPayoutAck?

    private var isDark: Bool { palette.bgPage == Theme.dark.bgPage }

    private var parsedAmount: Double? {
        Self.parseMonetary(amountText)
    }

    /// Robust, locale-correct monetary parse for the cash-out field.
    ///
    /// The previous `.decimal` NumberFormatter + `Double(cleaned)` fallback
    /// was buggy two ways: (1) a lone separator like "1,234" was silently
    /// read as 1234 in en_US (grouping) yet 1.234 in de_DE (decimal) — the
    /// same keystrokes meaning wildly different money; (2) the `Double()`
    /// fallback bypassed the locale entirely and accepted shapes the
    /// validator never intended (e.g. "1e3", "  5 ", a bare ".5"), which
    /// could slip a value past the min/balance gate. We instead:
    ///   • strip the locale + "$" currency symbols and all whitespace,
    ///   • accept ONLY ASCII digits, the locale grouping separator, and the
    ///     locale decimal separator (anything else → reject),
    ///   • REJECT an ambiguous lone-separator input that could be read as
    ///     either grouping or decimal (e.g. "1,234" / "1.234" with exactly
    ///     3 trailing digits and no other separator) rather than guessing,
    ///   • REJECT empty, and
    ///   • REJECT non-positive (≤ 0) results.
    /// The min ($1) and available-balance ceiling are enforced separately in
    /// `validationError` / `canSubmit` so a syntactically-valid-but-too-small
    /// amount still surfaces the right inline message.
    static func parseMonetary(_ raw: String) -> Double? {
        let locale = Locale.current
        let decimalSep = locale.decimalSeparator ?? "."
        let groupSep = locale.groupingSeparator ?? ","

        var cleaned = raw
            .replacingOccurrences(of: "$", with: "")
        if let symbol = locale.currencySymbol {
            cleaned = cleaned.replacingOccurrences(of: symbol, with: "")
        }
        cleaned = cleaned.components(separatedBy: .whitespacesAndNewlines).joined()
        if cleaned.isEmpty { return nil }

        // Reject any character that isn't an ASCII digit or a known separator.
        let allowed = Set("0123456789" + decimalSep + groupSep)
        guard cleaned.allSatisfy({ allowed.contains($0) }) else { return nil }

        let decimalCount = cleaned.components(separatedBy: decimalSep).count - 1
        let groupCount = cleaned.components(separatedBy: groupSep).count - 1

        // At most one decimal point; grouping never appears after a decimal.
        if decimalCount > 1 { return nil }
        if decimalCount == 1, let dotIdx = cleaned.range(of: decimalSep) {
            let fractional = cleaned[dotIdx.upperBound...]
            if fractional.contains(groupSep) { return nil }
        }

        // Ambiguity guard: a single separator that is BOTH the grouping and
        // a plausible decimal — "1,234" in en_US — is genuinely ambiguous.
        // When the only separator present is the grouping separator, exactly
        // once, followed by exactly 3 digits and no decimal separator, we
        // cannot tell 1,234 (=1234) from 1,234 (=1.234). Refuse rather than
        // silently pick one reading.
        if decimalSep != groupSep,
           decimalCount == 0,
           groupCount == 1,
           let gIdx = cleaned.range(of: groupSep) {
            let trailing = cleaned[gIdx.upperBound...]
            if trailing.count == 3, trailing.allSatisfy({ $0.isNumber }) {
                return nil
            }
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        // Reject trailing/garbage by requiring the formatter to consume it all.
        guard let number = formatter.number(from: cleaned) else { return nil }
        let value = number.doubleValue

        // Non-positive amounts (0, "-5" → caught above by the allowed-char
        // set, but 0 still reaches here) are never a valid cash-out.
        guard value.isFinite, value > 0 else { return nil }
        return value
    }

    private var selectedMethod: WalletPaymentMethod? {
        methods.first { $0.id == selectedMethodId }
    }

    // Instant payouts require a method flagged `instantPayoutEligible`.
    private var instantAvailable: Bool {
        selectedMethod?.isInstant ?? false
    }

    private var validationError: String? {
        guard let amt = parsedAmount else { return nil }
        if amt < 1 { return "Minimum cash-out is \(currency(1)). " }
        if amt > available { return "Amount exceeds your available balance." }
        return nil
    }

    private var canSubmit: Bool {
        !submitting
            && selectedMethodId != nil
            && parsedAmount != nil
            && (parsedAmount ?? 0) >= 1
            && (parsedAmount ?? 0) <= available
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let ack = ack {
                    successCard(ack)
                } else if methods.isEmpty {
                    noMethodState
                } else {
                    availableRow
                    methodPicker
                    amountField
                    speedPicker
                    if let v = validationError {
                        inlineError(v)
                    }
                    if let e = errorText {
                        inlineError(e)
                    }
                    submitButton
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s5)
            .padding(.bottom, Space.s8)
        }
        .onAppear {
            // Default to the linked default method, else the first.
            if selectedMethodId == nil {
                selectedMethodId = methods.first(where: { $0.isDefault })?.id
                    ?? methods.first?.id
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 4) {
                WalletEyebrow(glyph: .arrowDown, text: "DRIVER · CASH OUT")
                Text("Withdraw")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("To a linked bank or card")
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 34, height: 34)
                WalletGlyph(kind: .arrowDown, size: 16, tint: AnyShapeStyle(Color.white), lineWidth: 1.7)
            }
            .shadow(color: Brand.magenta.opacity(isDark ? 0.45 : 0.22), radius: 9, x: 0, y: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var availableRow: some View {
        HStack {
            HStack(spacing: 6) {
                WalletGlyph(kind: .wallet, size: 12, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.4)
                Text("AVAILABLE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.2)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Text(currency(available))
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    private var noMethodState: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(LinearGradient(colors: [Brand.blue.opacity(0.16), Brand.magenta.opacity(0.16)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.iridescentHairline, lineWidth: 1)
                    WalletGlyph(kind: .bank, size: 18, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.6)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add a payout method first").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text("Link a bank account or debit card to cash out your balance.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
            Button {
                onAddMethod()
            } label: {
                Text("Add a payout method")
                    .font(EType.bodyStrong)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.04)],
                                                         startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .standard)
    }

    private var methodPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TO")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: Space.s2) {
                ForEach(methods) { m in
                    methodOption(m)
                }
            }
        }
    }

    private func methodOption(_ m: WalletPaymentMethod) -> some View {
        let selected = m.id == selectedMethodId
        return Button {
            selectedMethodId = m.id
            // If the new method can't do instant, drop back to standard.
            if !(m.isInstant) { instant = false }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(LinearGradient(colors: [Brand.blue.opacity(0.16), Brand.magenta.opacity(0.16)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.iridescentHairline, lineWidth: 1)
                    WalletGlyph(kind: m.kind == "bank" ? .bank : .coins, size: 15,
                                tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.5)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.institution)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("••\(m.mask)\(m.isInstant ? " · instant" : "")")
                        .font(EType.micro)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                // Drawn selection indicator — filled gradient disc with a
                // check Path when chosen, hollow ring otherwise.
                ZStack {
                    Circle()
                        .strokeBorder(selected ? AnyShapeStyle(LinearGradient.diagonal)
                                               : AnyShapeStyle(palette.textTertiary.opacity(0.6)), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    if selected {
                        Circle().fill(LinearGradient.diagonal).frame(width: 18, height: 18)
                        Canvas { ctx, sz in
                            var p = Path()
                            let s = min(sz.width, sz.height)
                            p.move(to: CGPoint(x: 0.30 * s, y: 0.52 * s))
                            p.addLine(to: CGPoint(x: 0.44 * s, y: 0.66 * s))
                            p.addLine(to: CGPoint(x: 0.72 * s, y: 0.36 * s))
                            ctx.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        }.frame(width: 18, height: 18)
                    }
                }
            }
            .padding(.horizontal, Space.s3).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.md, intensity: selected ? .feature : .whisper)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AMOUNT")
                .font(.system(size: 9, weight: .heavy)).tracking(1.2)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 8) {
                Text("$")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textSecondary)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Button {
                    amountText = trimmedAmount(available)
                } label: {
                    Text("MAX")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(LinearGradient.diagonal)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .overlay(
                            Capsule().strokeBorder(palette.iridescentHairline, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Space.s4).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.lg, intensity: .feature)
        }
    }

    private var speedPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SPEED")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                speedOption(
                    title: "Standard",
                    subtitle: "1–2 business days",
                    isInstant: false
                )
                speedOption(
                    title: "Instant",
                    subtitle: instantAvailable ? "Fee applies · minutes" : "Not on this method",
                    isInstant: true
                )
            }
        }
    }

    private func speedOption(title: String, subtitle: String, isInstant: Bool) -> some View {
        let selected = instant == isInstant
        let disabled = isInstant && !instantAvailable
        return Button {
            guard !disabled else { return }
            instant = isInstant
        } label: {
            HStack(spacing: 8) {
                WalletGlyph(kind: isInstant ? .bolt : .pulse, size: 14,
                            filled: isInstant && selected && !disabled,
                            tint: (selected && !disabled) ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary),
                            lineWidth: 1.6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(EType.bodyStrong)
                        .foregroundStyle(disabled ? palette.textTertiary : palette.textPrimary)
                    Text(subtitle)
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s3).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.md, intensity: (selected && !disabled) ? .feature : .whisper)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
    }

    private func inlineError(_ text: String) -> some View {
        HStack(spacing: 8) {
            WalletGlyph(kind: .pulse, size: 14, tint: AnyShapeStyle(Brand.danger), lineWidth: 1.5)
            Text(text)
                .font(EType.caption)
                .foregroundStyle(Brand.danger)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.55), lineWidth: 1)
        )
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if submitting {
                    ProgressView()
                        .tint(.white)
                } else {
                    WalletGlyph(kind: .arrowDown, size: 16, tint: AnyShapeStyle(Color.white), lineWidth: 1.8)
                }
                Text(submitButtonTitle)
                    .font(EType.bodyStrong)
                    .foregroundStyle(Color.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(LinearGradient.diagonal)
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.04)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .shadow(color: Brand.blue.opacity((isDark && canSubmit) ? 0.35 : 0), radius: 14, x: 0, y: 8)
            .opacity(canSubmit ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    private var submitButtonTitle: String {
        if submitting { return "Requesting…" }
        if let amt = parsedAmount, amt >= 1 {
            return "Cash out \(currency(amt))"
        }
        return "Cash out"
    }

    private func successCard(_ ack: WalletExtrasAPI.RequestPayoutAck) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 40, height: 40)
                    // drawn checkmark Path (no SF Symbol)
                    Canvas { ctx, sz in
                        var p = Path()
                        let s = min(sz.width, sz.height)
                        p.move(to: CGPoint(x: 0.28 * s, y: 0.52 * s))
                        p.addLine(to: CGPoint(x: 0.44 * s, y: 0.68 * s))
                        p.addLine(to: CGPoint(x: 0.74 * s, y: 0.34 * s))
                        ctx.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    }.frame(width: 40, height: 40)
                }
                .shadow(color: Brand.magenta.opacity(isDark ? 0.45 : 0.2), radius: 9, x: 0, y: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Cash-out requested").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text("On its way to your linked method").font(EType.micro).foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
            }
            IridescentHairline()
            ackRow(label: "Amount", value: currency(ack.amount))
            if ack.fee > 0 {
                ackRow(label: "Instant fee", value: currency(ack.fee))
            }
            ackRow(label: "Net to you", value: currency(ack.netAmount), emphasised: true)
            ackRow(label: "Status", value: ack.status.capitalized)
            if let eta = formatEta(ack.estimatedArrival) {
                ackRow(label: "Estimated arrival", value: eta)
            }
            Button {
                onCompleted()
                dismiss()
            } label: {
                Text("Done")
                    .font(EType.bodyStrong)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(LinearGradient.diagonal)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.04)],
                                                         startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, Space.s1)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    private func ackRow(label: String, value: String, emphasised: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(emphasised ? EType.bodyStrong : EType.caption)
                .foregroundStyle(emphasised ? palette.textPrimary : palette.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: emphasised ? 16 : 14, weight: emphasised ? .heavy : .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
        }
    }

    private func submit() async {
        guard canSubmit, let amt = parsedAmount, let methodId = selectedMethodId else { return }
        submitting = true
        errorText = nil
        do {
            let result = try await EusoTripAPI.shared.walletExtras.requestPayout(
                amount: amt,
                payoutMethodId: methodId,
                instant: instant
            )
            ack = result
        } catch {
            // Surface the server message verbatim — it tells the driver
            // exactly why (insufficient balance, payouts not enabled,
            // outstanding carrier debt, etc.). The wallet is untouched
            // on failure.
            errorText = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        submitting = false
    }

    private func currency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }

    /// Plain numeric string (no symbol/grouping) for the amount field —
    /// keeps the decimal-pad input parseable when MAX is tapped.
    private func trimmedAmount(_ v: Double) -> String {
        String(format: "%.2f", v)
    }

    private func formatEta(_ iso: String?) -> String? {
        guard let iso = iso, !iso.isEmpty else { return nil }
        let iso8601 = ISO8601DateFormatter()
        if let date = iso8601.date(from: iso) {
            let out = DateFormatter()
            out.dateFormat = "MMM d"
            return out.string(from: date)
        }
        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyyy-MM-dd"
        if let date = inFmt.date(from: String(iso.prefix(10))) {
            let out = DateFormatter()
            out.dateFormat = "MMM d"
            return out.string(from: date)
        }
        return nil
    }
}

// MARK: - Screen wrapper

struct MeWalletScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeWallet()
        } nav: {
            BottomNav(
                leading: driverNavLeading_069(),
                trailing: driverNavTrailing_069(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_069() -> [NavSlot] {
    RoleNav.driverLeading(current: .none)
}
private func driverNavTrailing_069() -> [NavSlot] {
    RoleNav.driverTrailing(current: .loads)
}

// MARK: - Previews
//
// Previews never run `.task` — stores stay in `.loading` so both
// registers render a deterministic bespoke shimmer without hitting the
// network. No fixtures.

#Preview("069 · Me Wallet · Night") {
    MeWalletScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("069 · Me Wallet · Afternoon") {
    MeWalletScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
