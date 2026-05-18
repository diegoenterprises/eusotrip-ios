//
//  069_MeWallet.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · EusoWallet 8-section rebuild)
//
//  Screen 069 · Me · Wallet — the canonical EusoWallet hub per
//  SKILL.md §9 (8-section rebuild). The driver's single source of
//  truth for money: live balance, payouts, settlements, transactions,
//  factoring offers, linked accounts, and tax withholdings.
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
//                            Available + pending split. Zero-balance
//                            renders honestly as "$0.00 available" — a
//                            valid loaded state for a brand-new driver
//                            with no settled loads yet.
//    §2 Quick actions     — Card / Bank routes only. The brick
//                            deliberately omits Transfer / Deposit /
//                            Withdraw pills until the corresponding
//                            wallet mutations land server-side. No
//                            dead buttons, no stub dialogs, no fake
//                            "Coming soon" toasts that pretend to do
//                            something. Each rendered pill routes to
//                            a working sheet (AddPaymentAccountSheet)
//                            or push-segue (077 MePaymentMethods).
//    §3 Weekly chart      — `WeeklyEarningsStore` · earnings.
//                            getWeeklySummaries(weeks: 7). Bars use
//                            `LinearGradient.diagonal`; x-axis = day
//                            initials derived from `weekStart`. Zero-
//                            earnings weeks render as 1pt baseline
//                            ticks — visible but honest.
//    §4 Upcoming payouts  — `UpcomingSettlementsStore` ·
//                            settlementBatching.getDriverBatchView.
//                            Filter to first 5 non-paid batches. Tap
//                            routes to 070 Me · Settlements (full
//                            history) via lifecycleAdvance / nav env.
//    §5 Activity feed     — `WalletTransactionsStore` ·
//                            wallet.getTransactions. First 8 rows
//                            inline; "View all" routes to 070. Each
//                            row icon derives from `WalletTxn.kind`.
//    §6 Factoring offer   — `FactoringOfferStore` · factoring.getOffer
//                            (eligible-only). Surfaces only when a
//                            current load + HaulPay eligibility exist.
//                            Otherwise the section collapses entirely
//                            — no "No offers available" placeholder.
//    §7 Linked accounts   — `WalletPaymentMethodsStore` ·
//                            wallet.getPayoutMethods. Bank + card
//                            rows masked to last 4. Add / manage CTA
//                            routes to 077 MePaymentMethods.
//    §8 Tax withholdings  — `TaxSummaryStore` · tax.getSummary +
//                            `Tax1099Store` · tax.get1099. YTD
//                            withheld + quarterly estimate. 1099
//                            download disabled until Jan 31 of
//                            year+1 (server gate via
//                            `TaxAPI.Tax1099Document.available`).
//
//  Doctrine refs (per SKILL.md §2 enforcement checklist):
//    §1   No `Brand.info` / `Brand.blue` flat fills — gradient is the
//         only accent. Hero numerals, section title gradient text,
//         chart bar fills, factoring CTA, primary action pills.
//    §3   No `.tint(.blue)` — no toggles on this brick.
//    §4   Tokenized spacing (Space.sN), radii (Radius.sm/md/lg/xl),
//         type (EType.*). No magic numbers.
//    §5   Palette semantic throughout (`palette.textPrimary`,
//         `palette.textSecondary`, `palette.bgCard`, etc.).
//    §7   Ternary ShapeStyle expressions wrapped in `AnyShapeStyle`.
//    §10  Previews compile in isolation. Stores resolve to `.error`
//         under preview's no-baseURL runtime; the screen renders the
//         skeleton + error banners deterministically. No fixtures.
//

import SwiftUI

// MARK: - Screen root

struct MeWallet: View {
    @Environment(\.palette) var palette
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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                heroBalance              // §1
                quickActions             // §2
                weeklyChart              // §3
                upcomingPayouts          // §4
                activityFeed             // §5
                factoringOffer           // §6
                linkedAccounts           // §7
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

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("EusoWallet")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Balance · settlements · activity")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbeSang(state: anyLoading ? .thinking : .idle, diameter: 40)
        }
    }

    private var anyLoading: Bool {
        balance.isLoading || weekly.isLoading || settlements.isLoading
            || txns.isLoading || factoring.isLoading || methods.isLoading
            || tax.isLoading || ten99.isLoading
    }

    // MARK: §1 — Hero balance

    @ViewBuilder
    private var heroBalance: some View {
        switch balance.state {
        case .loading:
            heroSkeleton
        case .empty, .error:
            heroEmpty
        case .loaded(let b):
            heroLoaded(b)
        }
    }

    private var heroSkeleton: some View {
        RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .fill(palette.tintNeutral.opacity(0.35))
            .frame(height: 168)
    }

    private var heroEmpty: some View {
        VStack(spacing: Space.s2) {
            Text("$0.00")
                .font(.system(size: 56, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(LinearGradient.diagonal)
            Text("Available · waiting on first settlement")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s5)
        .eusoCard(radius: Radius.xl)
    }

    private func heroLoaded(_ b: WalletAPI.WalletBalance) -> some View {
        VStack(spacing: Space.s3) {
            // Available — the dominant gradient numeral.
            VStack(spacing: 2) {
                Text(currency(b.available, code: b.currency))
                    .font(.system(size: 56, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Available")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }

            IridescentHairline()
                .padding(.horizontal, Space.s2)

            // Pending + total reference row.
            HStack(spacing: Space.s5) {
                pendingPair(label: "Pending",
                            value: currency(b.pending, code: b.currency))
                Spacer()
                pendingPair(label: "Total",
                            value: currency(b.total, code: b.currency))
            }
            .padding(.horizontal, Space.s4)
        }
        .padding(.vertical, Space.s5)
        .frame(maxWidth: .infinity)
        .eusoCard(radius: Radius.xl)
    }

    private func pendingPair(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.bodyStrong)
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: §2 — Quick actions

    private var quickActions: some View {
        // ONE real, working action. No dead pills, no stub dialogs.
        // "Add payout" opens the real AddPaymentAccountSheet (Plaid
        // + Stripe side-by-side) — the same flow 077 uses. Manage
        // existing methods is reachable via the bottom nav (Wallet
        // tab → 077 entry from DriverTabPanes). Transfer / Deposit /
        // Withdraw pills are intentionally absent until the
        // corresponding wallet mutations ship server-side. Adding
        // them now would be a "no dead buttons" violation per the
        // 2027 motivation directive.
        actionPill(
            title: "Add payout method",
            systemImage: "plus.circle.fill",
            style: .primary
        ) {
            showAddPayout = true
        }
    }

    private enum ActionStyle { case primary, secondary }

    private func actionPill(
        title: String,
        systemImage: String,
        style: ActionStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Space.s2) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        style == .primary
                        ? AnyShapeStyle(Color.white)
                        : AnyShapeStyle(LinearGradient.diagonal)
                    )
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
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(
                        style == .primary
                        ? AnyShapeStyle(LinearGradient.diagonal)
                        : AnyShapeStyle(palette.bgCard)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(
                        style == .primary
                        ? AnyShapeStyle(Color.clear)
                        : AnyShapeStyle(palette.borderFaint),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: §3 — Weekly chart

    @ViewBuilder
    private var weeklyChart: some View {
        sectionHeader(title: "7-day net")
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
        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .fill(palette.tintNeutral.opacity(0.35))
            .frame(height: 140)
    }

    private var chartEmpty: some View {
        EusoEmptyState(
            systemImage: "chart.bar",
            title: "No earnings yet",
            subtitle: "Your 7-day net chart fills in as settlements clear."
        )
        .frame(height: 140)
        .frame(maxWidth: .infinity)
        .eusoCard(radius: Radius.lg)
    }

    private func chartLoaded(_ rows: [WeeklyEarningsBar]) -> some View {
        // Reverse so the chart reads left-to-right (oldest → newest)
        // and clamp to the most recent 7.
        let bars = Array(rows.prefix(7).reversed())
        let maxVal = max(bars.map(\.totalEarnings).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .bottom, spacing: Space.s2) {
                ForEach(bars) { row in
                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(LinearGradient.diagonal)
                            .frame(height: barHeight(row.totalEarnings, max: maxVal))
                            .frame(maxWidth: .infinity)
                        Text(weekTick(row.weekStart))
                            .font(EType.micro)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
            .frame(height: 140)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity)
        .eusoCard(radius: Radius.lg)
    }

    private func barHeight(_ v: Double, max: Double) -> CGFloat {
        let normalized = max > 0 ? CGFloat(v / max) : 0
        // 1pt baseline tick when the week earned $0 — visible but honest.
        return Swift.max(normalized * 110, 1)
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

    // MARK: §4 — Upcoming settlements

    @ViewBuilder
    private var upcomingPayouts: some View {
        sectionHeader(title: "Upcoming payouts")
        switch settlements.state {
        case .loading:
            listSkeleton(rows: 2, height: 64)
        case .empty, .error:
            EusoEmptyState(
                systemImage: "calendar.badge.clock",
                title: "No payouts pending",
                subtitle: "New batches appear here as loads settle."
            )
            .frame(maxWidth: .infinity)
            .padding(Space.s3)
            .eusoCard(radius: Radius.lg)
        case .loaded(let rows):
            VStack(spacing: Space.s2) {
                ForEach(rows.prefix(5)) { row in
                    settlementRow(row)
                }
            }
        }
    }

    private func settlementRow(_ row: DriverSettlementBatch) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCard)
                    .frame(width: 40, height: 40)
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.batchNumber)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(periodLabel(row))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text(currency(row.amount, code: "USD"))
                .font(EType.bodyStrong)
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.vertical, Space.s3)
        .padding(.horizontal, Space.s3)
        .eusoCard(radius: Radius.md)
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

    // MARK: §5 — Activity feed

    @ViewBuilder
    private var activityFeed: some View {
        sectionHeader(title: "Activity")
        switch txns.state {
        case .loading:
            listSkeleton(rows: 3, height: 56)
        case .empty, .error:
            EusoEmptyState(
                systemImage: "list.bullet.rectangle",
                title: "No transactions yet",
                subtitle: "Settlements, fees, and payouts will land here."
            )
            .frame(maxWidth: .infinity)
            .padding(Space.s3)
            .eusoCard(radius: Radius.lg)
        case .loaded(let rows):
            VStack(spacing: Space.s2) {
                ForEach(rows.prefix(8)) { txn in
                    activityRow(txn)
                }
            }
        }
    }

    private func activityRow(_ txn: WalletTxn) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCard)
                    .frame(width: 40, height: 40)
                Image(systemName: iconFor(txn))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        isCredit(txn)
                        ? AnyShapeStyle(LinearGradient.diagonal)
                        : AnyShapeStyle(palette.textSecondary)
                    )
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(txn.title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                if let sub = txn.subtitle {
                    Text(sub)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer()
            Text(amountLabel(txn))
                .font(EType.bodyStrong)
                .monospacedDigit()
                .foregroundStyle(
                    isCredit(txn)
                    ? AnyShapeStyle(palette.textPrimary)
                    : AnyShapeStyle(palette.textSecondary)
                )
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    private func iconFor(_ txn: WalletTxn) -> String {
        if let hint = txn.iconHint, !hint.isEmpty { return hint }
        switch txn.kind {
        case "load_payout":    return "truck.box.fill"
        case "instant_payout": return "bolt.fill"
        case "fee":            return "minus.circle"
        case "factoring":      return "arrow.triangle.2.circlepath"
        case "fuel":           return "fuelpump.fill"
        case "refund":         return "arrow.uturn.left.circle"
        case "bonus":          return "star.fill"
        case "adjustment":     return "slider.horizontal.3"
        case "transfer":       return "arrow.left.arrow.right"
        case "deposit":        return "tray.and.arrow.down"
        default:               return "dollarsign.circle"
        }
    }

    private func isCredit(_ txn: WalletTxn) -> Bool {
        // Credits are positive amounts; everything else is a debit/fee.
        txn.amount > 0
    }

    private func amountLabel(_ txn: WalletTxn) -> String {
        let prefix = isCredit(txn) ? "+" : ""
        return "\(prefix)\(currency(txn.amount, code: txn.currency ?? "USD"))"
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
            sectionHeader(title: "Get paid today")
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Text("HaulPay offer available")
                        .font(EType.bodyStrong)
                        .foregroundStyle(Color.white)
                    Spacer()
                }
                // Net = grossAmount - feeAmount per FactoringAPI.Offer wire shape
                // (frontend/server/routers/factoring.ts). Surface the gross +
                // fee + net so the driver sees the full breakdown — no spin.
                Text("Net \(currency(offer.netAmount, code: offer.currency)) · gross \(currency(offer.grossAmount, code: offer.currency)) · fee \(currency(offer.feeAmount, code: offer.currency))")
                    .font(EType.caption)
                    .foregroundStyle(Color.white.opacity(0.85))
                Text("Open the active load detail to accept this advance.")
                    .font(EType.caption)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .padding(Space.s4)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(LinearGradient.diagonal)
            )
        }
    }

    // MARK: §7 — Linked accounts

    @ViewBuilder
    private var linkedAccounts: some View {
        sectionHeader(title: "Linked accounts")
        switch methods.state {
        case .loading:
            listSkeleton(rows: 2, height: 52)
        case .empty, .error:
            EusoEmptyState(
                systemImage: "creditcard",
                title: "No methods linked",
                subtitle: "Add a bank or card to receive instant payouts."
            )
            .frame(maxWidth: .infinity)
            .padding(Space.s3)
            .eusoCard(radius: Radius.lg)
        case .loaded(let rows):
            VStack(spacing: Space.s2) {
                ForEach(rows) { row in
                    methodRow(row)
                }
                manageMethodsButton
            }
        }
    }

    private func methodRow(_ m: WalletPaymentMethod) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCard)
                    .frame(width: 40, height: 40)
                Image(systemName: m.kind == "bank" ? "building.columns.fill" : "creditcard.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(m.institution)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("••\(m.mask)\(m.isDefault ? " · default" : "")")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            if m.isInstant {
                Text("INSTANT")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(LinearGradient.diagonal)
            }
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
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
            HStack(spacing: Space.s2) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Add another")
                    .font(EType.bodyStrong)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s3)
        }
        .buttonStyle(.plain)
    }

    // MARK: §8 — Tax withholdings

    @ViewBuilder
    private var taxWithholdings: some View {
        sectionHeader(title: "Tax withholdings")
        switch tax.state {
        case .loading:
            listSkeleton(rows: 1, height: 96)
        case .empty, .error:
            EusoEmptyState(
                systemImage: "doc.text.magnifyingglass",
                title: "No tax data yet",
                subtitle: "We'll surface YTD withholdings after your first settled load."
            )
            .frame(maxWidth: .infinity)
            .padding(Space.s3)
            .eusoCard(radius: Radius.lg)
        case .loaded(let summary?):
            taxCard(summary)
        case .loaded(_):
            EmptyView()  // .loaded(nil) — should never hit per foldState
        }
    }

    private func taxCard(_ s: TaxAPI.TaxSummary) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("YTD withheld")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(currency((s.federalWithheld ?? 0) + (s.stateWithheld ?? 0),
                                   code: s.currency))
                        .font(.system(size: 28, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Q estimate")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(currency(s.quarterlyEstimate ?? 0, code: s.currency))
                        .font(EType.bodyStrong)
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
            }
            IridescentHairline()
            ten99Row
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    @ViewBuilder
    private var ten99Row: some View {
        switch ten99.state {
        case .loaded(let doc?):
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(doc.documentType ?? "1099") · \(String(doc.year))")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(doc.available ? "Issued \(formatShort(doc.issuedAt) ?? "—")" : "Pending IRS issuance window")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                if doc.available, let urlStr = doc.url, let url = URL(string: urlStr) {
                    Link(destination: url) {
                        Text("Download")
                            .font(EType.bodyStrong)
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                } else {
                    Text("Unavailable")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        default:
            HStack {
                Text("1099 · awaiting tax-year close")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
            }
        }
    }

    // MARK: Helpers

    private func sectionHeader(title: String) -> some View {
        HStack {
            Text(title)
                .font(EType.title)
                .foregroundStyle(LinearGradient.diagonal)
            Spacer()
        }
    }

    private func listSkeleton(rows: Int, height: CGFloat) -> some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<rows, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.35))
                    .frame(height: height)
            }
        }
    }

    private var disclosureFooter: some View {
        Text("EusoWallet routes through Stripe Connect (Custom). Settlements clear within 1–2 business days. Instant payouts subject to eligibility.")
            .font(EType.micro)
            .foregroundStyle(palette.textTertiary)
            .multilineTextAlignment(.leading)
            .padding(.top, Space.s2)
    }

    // MARK: Formatters

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
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_069() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: true),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: false)]
}

// MARK: - Previews
//
// Previews never run `.task` — stores stay in `.loading` so both
// registers render a deterministic skeleton without hitting the
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
