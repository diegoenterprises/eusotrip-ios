//
//  LiveDataStores.swift
//  EusoTrip
//
//  Thin `@MainActor final class … ObservableObject` stores that front
//  every live-data surface in the iOS app. Replaces ~30 seeded arrays
//  across `DriverTabPanes.swift` and `MeDetailScreens.swift` with a
//  single, uniform pattern:
//
//      @StateObject private var store = LoadBoardStore()
//      .task { await store.refresh() }
//      switch store.state {
//          case .loading: ProgressView()
//          case .empty:   EusoEmptyState(...)
//          case .loaded:  ForEach(store.items) { … }
//          case .error:   InlineErrorBanner(...)
//      }
//
//  Every store below either:
//    (a) calls a live `EusoTripAPI` procedure that already exists
//        (Phase 1 — wired today), or
//    (b) throws a `.comingSoon` error for Phase-3 surfaces whose
//        backend has not shipped. The view ignores the error and
//        renders `EusoEmptyState(comingSoon: true, …)` directly, so
//        the UI always resolves to an empty state — never a mock.
//

import Foundation

// MARK: - Shared error for screens without a backend yet

/// Thrown by stores whose backend endpoint has not been delivered.
/// Views treat `.comingSoon` as a signal to render
/// `EusoEmptyState(comingSoon: true, …)` instead of surfacing the error
/// in a banner. The explicit type lets call-sites distinguish between a
/// network failure (`.error`) and "this feature is on the roadmap"
/// (`.empty + comingSoon` in the UI).
enum StoreAvailability: Error, LocalizedError {
    case comingSoon(String)

    var errorDescription: String? {
        switch self {
        case .comingSoon(let surface):
            return "\(surface) is coming soon."
        }
    }
}

// MARK: - LoadBoardStore — `loads.search` (available loads)

/// Drives the Eusoboards market board + Driver Home suggested-loads
/// carousel. Backed by the real `loads.search` tRPC procedure.
///
/// Realtime: re-fetches the moment `RealtimeService` posts
/// `.eusoLoadPosted` (server fans `load:posted` to the `marketplace`
/// channel after every successful `loads.create`). Without this
/// observer the load board only saw new loads on the next poll cycle,
/// breaking the "shipper posts on web → driver sees instantly" loop.
@MainActor
final class LoadBoardStore: BaseDynamicListStore<LoadSummary> {
    private var marketplaceObserver: NSObjectProtocol?

    override init() {
        super.init()
        marketplaceObserver = NotificationCenter.default.addObserver(
            forName: .eusoLoadPosted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    deinit {
        if let observer = marketplaceObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func fetch() async throws -> [LoadSummary] {
        try await EusoTripAPI.shared.loads.search(status: "available", limit: 30)
    }
}

// MARK: - MyLoadsStore — `loads.search(status:)`

/// Drives the "My Loads" sheet — three buckets (active / pending /
/// finished) that each map to a different `status` filter on the
/// existing `loads.search` tRPC procedure.
@MainActor
final class MyLoadsStore: BaseDynamicListStore<LoadSummary> {
    var bucket: Bucket = .active {
        didSet {
            if oldValue != bucket { Task { await refresh() } }
        }
    }

    enum Bucket: String, CaseIterable, Identifiable {
        case active, pending, finished
        var id: String { rawValue }

        /// Status filter passed to `loads.search`. The backend accepts
        /// the canonical set { assigned, in_transit, at_pickup, at_delivery, pending, completed }.
        var statusFilter: String? {
            switch self {
            case .active:   return "in_transit"
            case .pending:  return "pending"
            case .finished: return "completed"
            }
        }
    }

    override func fetch() async throws -> [LoadSummary] {
        try await EusoTripAPI.shared.loads.search(
            status: bucket.statusFilter,
            limit: 30
        )
    }
}

// MARK: - WalletBalanceStore — `wallet.getBalance`

/// Single-value store for the Eusowallet hero balance. Unlike list
/// stores we don't fold empty → `.empty`; a $0.00 balance is a valid
/// loaded state (new driver who hasn't cleared a load yet).
@MainActor
final class WalletBalanceStore: BaseDynamicStore<WalletAPI.WalletBalance> {
    override func fetch() async throws -> WalletAPI.WalletBalance {
        try await EusoTripAPI.shared.wallet.getBalance()
    }
}

// MARK: - WalletTransactionsStore — `wallet.getTransactions`

/// Transactions list. Backed by the real `wallet.getTransactions` tRPC
/// procedure. Backend returns an empty list until the settlements table
/// has rows for the driver — the store surfaces `.empty` in that case
/// so views render `EusoEmptyState(systemImage: "dollarsign.circle", …)`.
@MainActor
final class WalletTransactionsStore: BaseDynamicListStore<WalletTxn> {
    var filter: String? = nil
    var cursor: String? = nil

    override func fetch() async throws -> [WalletTxn] {
        let response = try await EusoTripAPI.shared.walletExtras.getTransactions(
            filter: filter,
            cursor: cursor,
            limit: 30
        )
        return response.items
    }
}

// MARK: - WalletPaymentMethodsStore — `wallet.listPaymentMethods`

@MainActor
final class WalletPaymentMethodsStore: BaseDynamicListStore<WalletPaymentMethod> {
    override func fetch() async throws -> [WalletPaymentMethod] {
        let response = try await EusoTripAPI.shared.walletExtras.listPaymentMethods()
        return response.items
    }
}

// MARK: - EarningsStore — `wallet.getEarningsSummary`

/// Returns the canonical earnings summary for the Eusowallet hero card
/// and the Me → Earnings screen. A zero-value row is a valid "loaded"
/// state (new driver, no settled loads yet); the store only folds to
/// `.empty` if the server explicitly returns a non-positive aggregate
/// AND no projections — see `foldState` below.
@MainActor
final class EarningsStore: BaseDynamicStore<WalletEarningsSummary?> {
    override func fetch() async throws -> WalletEarningsSummary? {
        try await EusoTripAPI.shared.walletExtras.getEarningsSummary()
    }
    override func foldState(_ value: WalletEarningsSummary?) -> RemoteState<WalletEarningsSummary?> {
        guard let v = value else { return .empty }
        let isZero = v.thisWeekGross == 0
            && v.thisMonthGross == 0
            && v.ytdGross == 0
            && v.pending == 0
            && v.settledLoadsCount == 0
        return isZero ? .empty : .loaded(v)
    }
}

// MARK: - WeeklyEarningsStore — `earnings.getWeeklySummaries`
//
// Drives section 3 of the EusoWallet rebuild (7-day bar chart of net
// settlements). Canonical router verified in
// `frontend/server/routers/earnings.ts:201`. Backend returns `weeks`
// rows newest-first; we reverse at the render site so the chart reads
// left-to-right.
@MainActor
final class WeeklyEarningsStore: BaseDynamicListStore<WeeklyEarningsBar> {
    var weeks: Int = 7

    override func fetch() async throws -> [WeeklyEarningsBar] {
        let rows = try await EusoTripAPI.shared.earnings.getWeeklySummaries(weeks: weeks)
        // Map the API DTO into the view-model DTO (identical shape,
        // kept apart so `EarningsAPI` can evolve without forcing a
        // model-layer change).
        return rows.map { r in
            WeeklyEarningsBar(
                weekStart: r.weekStart,
                weekEnd: r.weekEnd,
                totalLoads: r.totalLoads,
                totalMiles: r.totalMiles,
                totalEarnings: r.totalEarnings,
                avgPerMile: r.avgPerMile,
                avgPerLoad: r.avgPerLoad
            )
        }
    }

    /// Weekly summaries include zero-earnings weeks as valid data — we
    /// only fold to `.empty` when literally every week returned zero
    /// (a brand-new driver with no settlements yet).
    override func foldState(_ value: [WeeklyEarningsBar]) -> RemoteState<[WeeklyEarningsBar]> {
        if value.isEmpty { return .empty }
        let hasAnyEarnings = value.contains { $0.totalEarnings > 0 }
        return hasAnyEarnings ? .loaded(value) : .empty
    }
}

// MARK: - UpcomingSettlementsStore — `settlementBatching.getDriverBatchView`
//
// Section 4. Backend requires a `driverId: Int` input. The store reads
// the current user id from `EusoTripSession` at fetch time; passes 0
// when no session is available (server returns `{ batches: [] }` →
// store renders empty state). Only non-paid rows are surfaced as
// "upcoming" — the `isUpcoming` computed prop on `DriverSettlementBatch`
// filters out paid/failed/disputed batches.
@MainActor
final class UpcomingSettlementsStore: BaseDynamicListStore<DriverSettlementBatch> {
    /// Driver id — set by the owning view before `refresh()` is called.
    /// When nil or 0 the server returns `{ batches: [] }` and the view
    /// falls through to the EusoEmptyState branch.
    var driverId: Int? = nil

    override func fetch() async throws -> [DriverSettlementBatch] {
        let id = driverId ?? 0
        let response = try await EusoTripAPI.shared.settlementBatching.getDriverBatchView(driverId: id)
        let rows = response.batches.map { r in
            DriverSettlementBatch(
                batchId: r.batchId,
                batchNumber: r.batchNumber,
                periodStart: r.periodStart,
                periodEnd: r.periodEnd,
                totalAmount: r.totalAmount,
                status: r.status,
                paidAt: r.paidAt
            )
        }
        return rows.filter(\.isUpcoming)
    }
}

// MARK: - SettlementsHistoryStore — `settlementBatching.getDriverBatchView` (unfiltered)
//
// Drives brick 070 Me · Settlements — the full settlement-history
// surface. Unlike `UpcomingSettlementsStore` (which filters to
// `isUpcoming`), this store returns every batch the server knows
// about for the driver, sorted newest-first. The view groups into
// "Upcoming" and "Paid" sections at render time via
// `DriverSettlementBatch.isUpcoming`.
//
// Added in the 67th firing (brick port 070 Me · Settlements).

@MainActor
final class SettlementsHistoryStore: BaseDynamicListStore<DriverSettlementBatch> {
    var driverId: Int? = nil

    override func fetch() async throws -> [DriverSettlementBatch] {
        let id = driverId ?? 0
        let response = try await EusoTripAPI.shared.settlementBatching.getDriverBatchView(driverId: id)
        let rows = response.batches.map { r in
            DriverSettlementBatch(
                batchId: r.batchId,
                batchNumber: r.batchNumber,
                periodStart: r.periodStart,
                periodEnd: r.periodEnd,
                totalAmount: r.totalAmount,
                status: r.status,
                paidAt: r.paidAt
            )
        }
        // Server sort isn't guaranteed newest-first; we sort at the
        // edge so `paidAt` (falling back to `periodEnd`) orders the
        // list deterministically before the view groups it.
        return rows.sorted { lhs, rhs in
            (lhs.paidAt ?? lhs.periodEnd ?? "")
                > (rhs.paidAt ?? rhs.periodEnd ?? "")
        }
    }
}

// MARK: - FactoringOfferStore — `factoring.getOffer`
//
// Drives EusoWallet §6. Reads the driver's current active load id from
// the caller (via `loadId` property, set by the owning view before
// `refresh()`), calls `factoring.getOffer({ loadId })`, and folds an
// `eligible=false` response to `.empty` so the §6 hero hides itself.
//
// The backend (`frontend/server/routers/factoring.ts`) now implements
// the real procedure: it validates post-POD status, not-already-factored,
// and emits a day-bucketed idempotent `offerId` the accept() mutation
// re-derives server-side.
@MainActor
final class FactoringOfferStore: BaseDynamicStore<FactoringAPI.Offer?> {
    /// Caller sets this before `refresh()` — typically the driver's
    /// current active load id from `DriverTripController.currentLoad?.id`.
    /// When nil, the store resolves to `.empty` without hitting the API.
    var loadId: Int? = nil

    override func fetch() async throws -> FactoringAPI.Offer? {
        guard let id = loadId else { return nil }
        let offer = try await EusoTripAPI.shared.factoring.getOffer(loadId: id)
        return offer.eligible ? offer : nil
    }

    /// `.loaded(nil)` is treated as empty — the server explicitly said
    /// no offer is available for this load (wrong status, already
    /// factored, etc.). `.loaded(offer)` only surfaces when the
    /// backend confirms eligibility.
    override func foldState(_ value: FactoringAPI.Offer?) -> RemoteState<FactoringAPI.Offer?> {
        value == nil ? .empty : .loaded(value)
    }
}

// MARK: - TaxSummaryStore — `tax.getSummary`
//
// Drives EusoWallet §8. Backend (`frontend/server/routers/tax.ts`)
// aggregates `payments` rows where the driver is payee and
// status IN ('succeeded','completed','settled','paid'), then emits
// `ytdGross`, `estimatedTax` (2531 bps default, env-overridable),
// `quarterlyEstimate`, and `download1099*` availability flags.
//
// A $0 YTD response is a valid `.loaded` state (new driver — shows
// "$0 YTD"), NOT empty. The store only folds to `.empty` when the
// API returns 404 / decode fails (rare).
@MainActor
final class TaxSummaryStore: BaseDynamicStore<TaxAPI.TaxSummary?> {
    var year: Int = Calendar.current.component(.year, from: Date())

    override func fetch() async throws -> TaxAPI.TaxSummary? {
        try await EusoTripAPI.shared.tax.getSummary(year: year)
    }

    /// Any decoded summary — including a $0 YTD row — is `.loaded`.
    /// The §8 tile renders "$0 YTD" as a perfectly valid reading.
    override func foldState(_ value: TaxAPI.TaxSummary?) -> RemoteState<TaxAPI.TaxSummary?> {
        value == nil ? .empty : .loaded(value)
    }
}

// MARK: - Tax1099Store — `tax.get1099`
//
// Drives brick 071 Me · Tax — the 1099-NEC download row. Backend
// `tax.get1099({ year })` reads `tax_1099_records` for the driver +
// tax year and returns `{ available, documentType, url, issuedAt,
// totalAmount, payerName, payerTIN }`. 1099 availability is gated on
// Jan 31 of year+1 AND a generated record existing. The view renders
// a disabled row with "Pending IRS-issuance window" copy until the
// threshold passes, then an active download row once `available=true`.

@MainActor
final class Tax1099Store: BaseDynamicStore<TaxAPI.Tax1099Document?> {
    var year: Int = Calendar.current.component(.year, from: Date()) - 1

    override func fetch() async throws -> TaxAPI.Tax1099Document? {
        try await EusoTripAPI.shared.tax.get1099(year: year)
    }

    override func foldState(_ value: TaxAPI.Tax1099Document?) -> RemoteState<TaxAPI.Tax1099Document?> {
        value == nil ? .empty : .loaded(value)
    }
}

// MARK: - MeEarningsStore — brick 068 · composite store
//
// Aggregates four canonical procedures in parallel to drive brick 068
// (Me · Earnings). Replaces the single-call `EarningsStore` (which
// still powers the Wallet hero) with a period-aware, multi-surface
// store so the earnings screen can bind all five sections (hero,
// breakdown, chart, top loads, YTD footer) to one view-model.
//
// Procedures consumed:
//   earnings.getSummary({ period })       hero + breakdown
//   earnings.getWeeklySummaries({ weeks }) period chart bars
//   earnings.getYTDSummary                 footer gross + projection
//   earnings.getEarnings({ period })       top loads (client-sort)
//   tax.getSummary({ year })               withholdings + 1099 flag
@MainActor
final class MeEarningsStore: ObservableObject, DynamicStore {
    // Selected period drives every fetch. Setting this triggers a refresh
    // so the view just binds to `store.period` and lets the store chase
    // the request fan-out.
    @Published var period: EarningsPeriod = .week {
        didSet {
            if oldValue != period { Task { await refresh() } }
        }
    }

    // Published surfaces consumed by brick 068.
    @Published private(set) var summary: RemoteState<EarningsSummary> = .loading
    @Published private(set) var weeklyBars: RemoteState<[WeeklyEarningsBar]> = .loading
    @Published private(set) var ytd: RemoteState<YTDSummary> = .loading
    @Published private(set) var topLoads: RemoteState<[TopLoadRow]> = .loading

    // DynamicStore protocol conformance — surfaces rollup loading/error
    // so views that just want a single spinner / banner can read these.
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error? = nil

    /// Kick every procedure off in parallel and settle each surface
    /// independently. A single failure on (for example) `tax.getSummary`
    /// must not poison the hero card — each surface rolls its own
    /// RemoteState so the view can render whatever landed cleanly.
    func refresh() async {
        isLoading = true
        lastError = nil

        async let summaryTask: EarningsSummary? = fetchSummary()
        async let barsTask:    [WeeklyEarningsBar] = fetchBars()
        async let ytdTask:     YTDSummary? = fetchYTD()
        async let topTask:     [TopLoadRow] = fetchTop()

        // `async let` tuple discard per §4 recipe — all four run in parallel.
        let (s, b, y, t) = await (summaryTask, barsTask, ytdTask, topTask)

        if let s { summary = .loaded(s) }
        else     { summary = .empty }

        weeklyBars = b.isEmpty ? .empty
                    : (b.contains { $0.totalEarnings > 0 } ? .loaded(b) : .empty)

        if let y { ytd = .loaded(y) } else { ytd = .empty }

        topLoads = t.isEmpty ? .empty : .loaded(t)

        isLoading = false
    }

    // MARK: - Per-surface fetchers

    private func fetchSummary() async -> EarningsSummary? {
        // `.ytd` special-cases to `earnings.getYTDSummary` because
        // the server's `getSummary` enum does not include "ytd".
        do {
            if period == .ytd {
                let y = try await EusoTripAPI.shared.earnings.getYTDSummary()
                let avgPerLoad = y.totalLoads > 0 ? y.totalEarnings / Double(y.totalLoads) : 0
                return EarningsSummary(
                    period: .ytd,
                    totalEarnings: y.totalEarnings,
                    totalLoads: y.totalLoads,
                    totalMiles: y.totalMiles,
                    avgPerMile: y.avgPerMile,
                    avgPerLoad: avgPerLoad,
                    pendingAmount: 0,
                    paidAmount: y.totalEarnings,
                    bonuses: 0,
                    changePct: 0,
                    trend: "stable"
                )
            }
            guard let wire = period.wirePeriod else { return nil }
            let s = try await EusoTripAPI.shared.earnings.getSummary(period: wire)
            return EarningsSummary(
                period: period,
                totalEarnings: s.totalEarnings,
                totalLoads: s.totalLoads,
                totalMiles: s.totalMiles,
                avgPerMile: s.avgPerMile,
                avgPerLoad: s.avgPerLoad,
                pendingAmount: s.pendingAmount ?? 0,
                paidAmount: s.paidAmount ?? 0,
                bonuses: s.bonuses ?? 0,
                changePct: s.comparison?.percentChange ?? s.change ?? 0,
                trend: s.comparison?.trend ?? "stable"
            )
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
            return nil
        }
    }

    private func fetchBars() async -> [WeeklyEarningsBar] {
        do {
            let rows = try await EusoTripAPI.shared.earnings
                .getWeeklySummaries(weeks: period.barCount)
            return rows.map { r in
                WeeklyEarningsBar(
                    weekStart: r.weekStart,
                    weekEnd: r.weekEnd,
                    totalLoads: r.totalLoads,
                    totalMiles: r.totalMiles,
                    totalEarnings: r.totalEarnings,
                    avgPerMile: r.avgPerMile,
                    avgPerLoad: r.avgPerLoad
                )
            }
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
            return []
        }
    }

    private func fetchYTD() async -> YTDSummary? {
        // Earnings YTD + tax withholding fan-out. A tax failure does not
        // veto the earnings numbers — we surface them with nil tax fields.
        async let earningsYTD = fetchEarningsYTDSafe()
        async let taxSummary  = fetchTaxSummarySafe()

        let (eytd, tax) = await (earningsYTD, taxSummary)
        guard let e = eytd else { return nil }

        let federal = tax?.federalWithheld ?? 0
        let state   = tax?.stateWithheld ?? 0
        let fees    = tax?.platformFees ?? 0
        let net     = max(0, e.totalEarnings - fees - federal - state)

        return YTDSummary(
            year: e.year,
            grossEarnings: e.totalEarnings,
            netEarnings: net,
            totalLoads: e.totalLoads,
            totalMiles: e.totalMiles,
            avgPerMile: e.avgPerMile,
            projectedAnnual: e.projectedAnnual,
            platformFees: tax?.platformFees,
            federalWithheld: tax?.federalWithheld,
            stateWithheld: tax?.stateWithheld,
            estimatedTax: tax?.estimatedTax,
            download1099Available: tax?.download1099Available,
            download1099URL: tax?.download1099URL
        )
    }

    private func fetchEarningsYTDSafe() async -> EarningsAPI.YTDSummaryWire? {
        do { return try await EusoTripAPI.shared.earnings.getYTDSummary() }
        catch { return nil }
    }

    private func fetchTaxSummarySafe() async -> TaxAPI.TaxSummary? {
        do { return try await EusoTripAPI.shared.tax.getDriverSummary() }
        catch { return nil }
    }

    private func fetchTop() async -> [TopLoadRow] {
        // `earnings.getTopLoads` doesn't exist on the server — MCP
        // search_code against earnings.ts confirms. We use
        // `earnings.getEarnings({ period, limit: 50 })` and sort client
        // side by totalPay desc, take 5.
        //
        // Backend procedure accepts `period: z.string().optional()` so
        // any string value is tolerated. For `.ytd` we pass "year" so
        // the server's wider window still covers the YTD range.
        let wire = period.wirePeriod ?? "year"
        do {
            let rows = try await EusoTripAPI.shared.earnings.getEarnings(
                period: wire, limit: 50
            )
            let sorted = rows.sorted { $0.totalPay > $1.totalPay }.prefix(5)
            return sorted.map { r in
                TopLoadRow(
                    id: r.id,
                    loadNumber: r.loadNumber ?? r.id,
                    date: r.date,
                    origin: r.origin,
                    destination: r.destination,
                    miles: r.miles,
                    totalPay: r.totalPay
                )
            }
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
            return []
        }
    }
}

// MARK: - InspectionsHistoryStore — `inspections.getDVIRHistory`

/// Drives the MeZeun view's DVIR history section.
@MainActor
final class InspectionsHistoryStore: BaseDynamicListStore<DVIRHistoryEntry> {
    var vehicleId: Int? = nil

    override func fetch() async throws -> [DVIRHistoryEntry] {
        try await EusoTripAPI.shared.inspections.getDVIRHistory(vehicleId: vehicleId, limit: 20)
    }
}

// MARK: - DvirSubmittedReviewStore — composite hydration for screen 012
//
// Screen 012 (Pre-trip DVIR · defect submitted) is the post-submit
// "review what dispatch sees" surface. It needs the *most recent*
// submitted DVIR record plus the *most recent* open defect for the
// driver's active vehicle, joined into a single Snapshot the view
// can switch over.
//
// Backend procedures (verified in Services/EusoTripAPI.swift):
//   inspections.getDVIRHistory(vehicleId:Int?, limit:20)
//     → [DVIRHistoryEntry]      — picks header (unit, date, condition)
//   inspections.getOpenDefects(vehicleId:String?)
//     → [InspectionDefectEntry] — picks the defect that put the unit OOS
//
// When neither endpoint surfaces a row we fold to `.empty` so the view
// renders a neutral EusoEmptyState ("No defects on file") rather than
// a fabricated brake/slack-adjuster vignette. Doctrine §13 (no fake
// data) is the binding constraint.
@MainActor
final class DvirSubmittedReviewStore: BaseDynamicStore<DvirSubmittedReviewStore.Snapshot?> {
    /// Optional vehicle filter — when set, both queries scope to this
    /// vehicle. Defaults to nil so the call returns the driver's
    /// company-wide most-recent open defect (matches the dispatcher's
    /// "alerted me" view).
    var vehicleId: Int? = nil

    /// Composite shape consumed by 012. Every field is optional so the
    /// view renders "—" placeholders instead of crashing on partial
    /// hydration (e.g. defect row exists but DVIR history hasn't
    /// indexed yet, or vice versa).
    struct Snapshot: Equatable {
        let dvir: DVIRHistoryEntry?
        let defect: InspectionDefectEntry?

        /// True when the latest DVIR has at least one defect or the
        /// open-defects feed surfaced a row. Drives whether the view
        /// shows the OOS card or the "all clear" empty state.
        var hasOpenDefect: Bool {
            if let dvir = dvir, (dvir.defectsFound ?? 0) > 0 { return true }
            return defect != nil
        }
    }

    override func fetch() async throws -> Snapshot? {
        async let dvirRows  = EusoTripAPI.shared.inspections.getDVIRHistory(
            vehicleId: vehicleId, limit: 5
        )
        async let defectRows = EusoTripAPI.shared.inspections.getOpenDefects(
            vehicleId: vehicleId.map(String.init)
        )
        let (dvirs, defects) = try await (dvirRows, defectRows)
        guard !dvirs.isEmpty || !defects.isEmpty else { return nil }
        return Snapshot(dvir: dvirs.first, defect: defects.first)
    }

    /// Fold a nil/all-clear fetch to `.empty` so the view picks the
    /// branded "no defects on file" branch.
    override func foldState(_ value: Snapshot?) -> RemoteState<Snapshot?> {
        guard let snap = value, snap.hasOpenDefect else { return .empty }
        return .loaded(snap)
    }
}

// MARK: - BadgesStore — `gamification.getBadges` (canonical)
// MCP-verified at frontend/server/routers/gamification.ts:528.

@MainActor
final class BadgesStore: BaseDynamicListStore<DriverBadge> {
    override func fetch() async throws -> [DriverBadge] {
        try await EusoTripAPI.shared.gamification.getBadges()
    }
}

// MARK: - YTDEarningsStore — `earnings.getYTDSummary` (canonical)

@MainActor
final class YTDEarningsStore: BaseDynamicStore<EarningsAPI.YTDSummaryWire?> {
    override func fetch() async throws -> EarningsAPI.YTDSummaryWire? {
        try await EusoTripAPI.shared.earnings.getYTDSummary()
    }
    override func foldState(_ value: EarningsAPI.YTDSummaryWire?) -> RemoteState<EarningsAPI.YTDSummaryWire?> {
        value == nil ? .empty : .loaded(value)
    }
}

// MARK: - FleetVehiclesStore — `fleet.getVehicles` (canonical)

@MainActor
final class FleetVehiclesStore: BaseDynamicListStore<FleetVehicleRow> {
    override func fetch() async throws -> [FleetVehicleRow] {
        try await EusoTripAPI.shared.fleetCanonical.getVehicles()
    }
}

// MARK: - ZeunBreakdownsStore — `zeunMechanics.getMyBreakdowns` (canonical)

@MainActor
final class ZeunBreakdownsStore: BaseDynamicListStore<ZeunBreakdownRow> {
    override func fetch() async throws -> [ZeunBreakdownRow] {
        try await EusoTripAPI.shared.zeunMechanics.getMyBreakdowns()
    }
}

// MARK: - MissionsStore — `gamification.getMissions`
//
// 60th firing: switched from the dead `achievements.getMissions` endpoint
// (no matching router on the backend — the iOS `AchievementsAPI` was
// firing against a 404) to the canonical `gamification.getMissions`
// router that actually lives in `server/routers/gamification.ts`.
//
// The backend response is three buckets { active, completed, available }
// with a richer shape than the legacy `[DriverMission]` projection. We
// flatten them into a single `[DriverMission]` here (60 Dashboard reads
// `prefix(2)` of in-flight missions) while the new 061 screen subscribes
// to the richer three-bucket form via `TheHaulMissionsStore` directly.
//
// Map rules (wire → DriverMission):
//   • id          → stringified numeric id
//   • title       → name
//   • subtitle    → description
//   • kind        → type || "weekly"   // matches legacy "weekly/monthly/seasonal"
//   • progress    → min(1.0, currentProgress / targetValue)   // 0.0 if target == 0
//   • rewardLabel → see rewardLabel(mission:)
//   • expiresAt   → endsAt
//   • claimedAt   → completedAt if status == "claimed"
//
// Per §16 SKILL.md: rewardType `cash` and `miles` still render in the
// label (so drivers see the promised reward shape), but they are not
// credited against the wallet until the gamification writers land.

@MainActor
final class MissionsStore: BaseDynamicListStore<DriverMission> {
    override func fetch() async throws -> [DriverMission] {
        let response = try await EusoTripAPI.shared.gamification.getMissions()
        // Surface order: in-flight first, then claim-ready completed, then
        // available. Callers that take prefix(2) on 060 therefore show the
        // driver's most-urgent missions.
        let flat = response.active + response.completed + response.available
        return flat.map { Self.map(mission: $0) }
    }

    /// Map a `GamificationAPI.Mission` row onto the legacy `DriverMission`
    /// struct so existing UI primitives keep working. Exposed as an
    /// internal helper because the dedicated 061 Missions screen also
    /// uses this to project `TheHaulMissionsStore`'s richer buckets onto
    /// the same row shape.
    static func map(mission m: GamificationAPI.Mission) -> DriverMission {
        let target = m.targetValue ?? 0
        let current = m.currentProgress ?? 0
        let progress: Double
        if target > 0 {
            progress = max(0.0, min(1.0, current / target))
        } else {
            progress = 0.0
        }
        let kind = (m.type?.isEmpty == false ? m.type : nil) ?? "weekly"
        let claimedAt: String? = (m.status == "claimed") ? m.completedAt : nil
        return DriverMission(
            id: String(m.id),
            title: m.name,
            subtitle: m.description,
            kind: kind,
            progress: progress,
            rewardLabel: Self.rewardLabel(for: m),
            expiresAt: m.endsAt,
            claimedAt: claimedAt
        )
    }

    /// Best-effort reward label. Mirrors the web `Missions` card so the
    /// copy is consistent across surfaces:
    ///   • xp + reward ⇒ "+{xp} XP · {reward}"
    ///   • xp only      ⇒ "+{xp} XP"
    ///   • reward only  ⇒ "{reward}"
    ///   • neither       ⇒ nil (row hides the chip)
    static func rewardLabel(for m: GamificationAPI.Mission) -> String? {
        let xp = m.xpReward ?? 0
        let reward: String? = {
            guard let rv = m.rewardValue, rv > 0, let rt = m.rewardType else { return nil }
            switch rt {
            case "xp":             return "+\(Int(rv)) XP"
            case "miles":          return "\(Int(rv)) Miles"
            case "cash":           return String(format: "$%.0f", rv)
            case "fee_reduction":  return String(format: "-%.1f%% fee", rv)
            case "priority_perk":  return "Priority perk"
            case "badge", "title", "crate": return rt.capitalized
            default:               return nil
            }
        }()
        switch (xp > 0, reward) {
        case (true, let r?):  return "+\(xp) XP · \(r)"
        case (true, nil):     return "+\(xp) XP"
        case (false, let r?): return r
        case (false, nil):    return nil
        }
    }
}

// MARK: - TheHaulMissionsStore — `gamification.getMissions` (three-bucket)
//
// Backs the dedicated 061 Missions screen. Unlike `MissionsStore` (which
// flattens the response into a single `[DriverMission]` for the 060
// dashboard row), this store preserves the server's three buckets so the
// 061 filter chips (All / Active / Available / Completed) can switch
// instantly without a re-fetch, and so the claim action can find the
// matching row in the correct bucket.
//
// The value type is a projection that keeps both the raw
// `GamificationAPI.Mission` rows (needed for the numeric `id` passed to
// startMission / claimMissionReward) and a per-row `DriverMission`
// projection the UI card already knows how to render.

@MainActor
final class TheHaulMissionsStore: BaseDynamicStore<TheHaulMissionsStore.Snapshot> {

    // MARK: Snapshot

    struct Row: Identifiable, Hashable {
        let raw: GamificationAPI.Mission
        let projection: DriverMission
        var id: Int { raw.id }
        var bucket: Bucket
    }

    enum Bucket: String, CaseIterable, Identifiable {
        /// in-flight — status `in_progress`
        case active
        /// finished but reward not yet claimed — status `completed`
        case completed
        /// not started or cancelled / expired
        case available
        var id: String { rawValue }

        var label: String {
            switch self {
            case .active:     return "Active"
            case .completed:  return "Claimable"
            case .available:  return "Available"
            }
        }
    }

    struct Snapshot: Equatable {
        let active: [Row]
        let completed: [Row]
        let available: [Row]

        static let empty = Snapshot(active: [], completed: [], available: [])

        var totalCount: Int {
            active.count + completed.count + available.count
        }

        /// Return rows for a single bucket, or every row when `bucket` is
        /// nil (the "All" filter chip).
        func rows(for bucket: Bucket?) -> [Row] {
            guard let bucket else { return active + completed + available }
            switch bucket {
            case .active:     return active
            case .completed:  return completed
            case .available:  return available
            }
        }
    }

    // MARK: State overrides

    /// Empty snapshot still counts as `.empty` (drives EusoEmptyState on 061).
    override func foldState(_ value: Snapshot) -> RemoteState<Snapshot> {
        value.totalCount == 0 ? .empty : .loaded(value)
    }

    override func fetch() async throws -> Snapshot {
        let response = try await EusoTripAPI.shared.gamification.getMissions()
        return Snapshot(
            active:    response.active.map    { Self.row(from: $0, bucket: .active) },
            completed: response.completed.map { Self.row(from: $0, bucket: .completed) },
            available: response.available.map { Self.row(from: $0, bucket: .available) }
        )
    }

    private static func row(
        from m: GamificationAPI.Mission,
        bucket: Bucket
    ) -> Row {
        Row(
            raw: m,
            projection: MissionsStore.map(mission: m),
            bucket: bucket
        )
    }

    // MARK: Mutations

    /// Start a not-yet-started mission. Refreshes the snapshot on success
    /// so the row moves from `available` → `active` in one trip.
    /// Returns the server's reason string when the call fails; the caller
    /// can surface it in a toast.
    @discardableResult
    func startMission(missionId: Int) async -> String? {
        do {
            let result = try await EusoTripAPI.shared.gamification
                .startMission(missionId: missionId)
            await refresh()
            return result.success ? nil : (result.message ?? "Couldn't start this mission.")
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
            return error.localizedDescription
        }
    }

    /// Claim the reward for a completed mission. Optimistically removes
    /// the row from `completed` the moment the call returns so the UI
    /// doesn't flash back into "claim" state between the mutation and
    /// the refresh response.
    @discardableResult
    func claimMissionReward(missionId: Int) async -> String? {
        do {
            let result = try await EusoTripAPI.shared.gamification
                .claimMissionReward(missionId: missionId)
            if result.success, case .loaded(var snap) = state {
                snap = Snapshot(
                    active:    snap.active,
                    completed: snap.completed.filter { $0.id != missionId },
                    available: snap.available
                )
                state = foldState(snap)
            }
            await refresh()
            return result.success ? nil : (result.message ?? "Couldn't claim this reward.")
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
            return error.localizedDescription
        }
    }
}

// MARK: - RewardsStore — `gamification.getRewardsCatalog` (canonical)
// MCP-verified at frontend/server/routers/gamification.ts:377.

@MainActor
final class RewardsStore: BaseDynamicListStore<RewardItem> {
    override func fetch() async throws -> [RewardItem] {
        let resp = try await EusoTripAPI.shared.gamification.getRewardsCatalog()
        return resp.rewards
    }
}

// MARK: - DriverReferralsFeedStore — `profile.listReferrals`
//
// 72nd-firing rename (2026-04-24T08:15Z). Dev team shipped
// `088_MeReferrals.swift` with a new `ReferralsStore` at line 1889 of
// this file backed by the canonical `referrals.*` tRPC namespace
// (`getMyCode` / `getSummary` / `listMine`). The old list-store below
// was still named `ReferralsStore`, which is a duplicate type
// declaration — Swift rejects it, the iOS target stopped compiling.
// Renaming this older list-of-`DriverReferral` store to
// `DriverReferralsFeedStore` lets both stores coexist: the canonical
// `ReferralsStore` powers the new Invite & Earn screen (088), and this
// feed-shaped store still backs the legacy `MeReferralsView` embedded
// in `MeDetailScreens.swift` (pre-wave Me sheet). No behavior change.

@MainActor
final class DriverReferralsFeedStore: BaseDynamicListStore<DriverReferral> {
    override func fetch() async throws -> [DriverReferral] {
        let response = try await EusoTripAPI.shared.profile.listReferrals()
        return response.items
    }
}

// MARK: - FleetStore — `fleet.listAssets`

@MainActor
final class FleetStore: BaseDynamicListStore<FleetAsset> {
    override func fetch() async throws -> [FleetAsset] {
        let response = try await EusoTripAPI.shared.fleet.listAssets()
        return response.items
    }
}

// MARK: - LeaderboardStore — `gamification.getLeaderboard` (canonical)
// MCP-verified at frontend/server/routers/gamification.ts:294.
// Legacy `leaderboard.getSeason` namespace does not exist server-side.

@MainActor
final class LeaderboardStore: BaseDynamicListStore<LeaderboardRow> {
    var period: String = "month"
    var category: String = "points"
    var limit: Int = 20
    var roleFilter: String = "own"

    override func fetch() async throws -> [LeaderboardRow] {
        try await EusoTripAPI.shared.gamification.getLeaderboard(
            period: period, category: category, limit: limit, roleFilter: roleFilter
        )
    }
}

// MARK: - LeaderboardSnapshotStore — `gamification.getLeaderboard` (full envelope)
//
// Added 62nd firing for brick 064 The Haul · Leaderboard, which needs
// the driver's own rank + the total-participants denominator on top
// of the leader rows. Same canonical procedure as `LeaderboardStore`
// above, but preserves `myRank` / `totalParticipants` / echoed period
// and category for the dedicated leaderboard surface. Changing the
// `period` / `category` / `limit` / `roleFilter` fields and calling
// `refresh()` re-queries the server; no local filtering.

@MainActor
final class LeaderboardSnapshotStore: BaseDynamicStore<GamificationAPI.LeaderboardSnapshot> {
    var period: String = "month"
    var category: String = "points"
    var limit: Int = 20
    var roleFilter: String = "own"

    override func fetch() async throws -> GamificationAPI.LeaderboardSnapshot {
        try await EusoTripAPI.shared.gamification.getLeaderboardSnapshot(
            period: period, category: category, limit: limit, roleFilter: roleFilter
        )
    }
}

// MARK: - CratesStore — `gamification.getCrates` + `openCrate`
//
// Drives 063 The Haul · Crates. Retyped Cohort A → B in the 65th firing
// once MCP-verification confirmed `rewardCrates` writers landed on the
// backend (gamification.ts:1039/1066). The server-side drop table is
// authoritative — the client never rolls rewards locally.

@MainActor
final class CratesStore: BaseDynamicListStore<GamificationAPI.Crate> {
    /// The reveal payload from the most-recent successful open — the
    /// reveal sheet binds to this and clears it on dismiss so the next
    /// open renders a fresh roll.
    @Published var lastReveal: GamificationAPI.OpenCrateResponse?

    override func fetch() async throws -> [GamificationAPI.Crate] {
        try await EusoTripAPI.shared.gamification.getCrates()
    }

    /// Fire the open mutation and, on success, drop the opened crate
    /// from the local list and publish the reveal so the sheet renders.
    /// On `success: false` we do NOT drop the row (server still owns it)
    /// and propagate the error through the base class state machine via
    /// a throwing refresh.
    func openCrate(_ crate: GamificationAPI.Crate) async {
        do {
            let resp = try await EusoTripAPI.shared.gamification.openCrate(crateId: crate.id)
            guard resp.success else {
                await refresh()
                return
            }
            lastReveal = resp
            if case .loaded(let rows) = state {
                // Use foldState so an empty list flips to `.empty` (branded
                // EusoEmptyState) instead of `.loaded([])` (bypasses the
                // empty-state view branch).
                state = foldState(rows.filter { $0.id != crate.id })
            }
        } catch {
            await refresh()
        }
    }
}

// MARK: - PulseLobbyStore — `messages.getMessages(conversationId: "driver-lobby")`

/// Drives the Driver Pulse group-chat lobby. The `driver-lobby`
/// conversation id is a server-side convention (same contract as the
/// web app's lobby). If the conversation doesn't exist yet for this
/// driver, the server returns `[]` and the view falls through to
/// `EusoEmptyState`.
@MainActor
final class PulseLobbyStore: BaseDynamicListStore<MessagingMessage> {
    /// Decodable envelope for `messaging.getLobby`. The endpoint
    /// resolves the user → company → "The Lobby" conversation and
    /// returns the recent messages in the canonical
    /// `MessagingMessage` shape (server-side mapped — see
    /// `messaging.ts :: getLobby`). The previous implementation
    /// posted to a hardcoded `conversationId: "driver-lobby"`,
    /// which the canonical `messages.getMessages` parser rejected
    /// (parseInt of "driver-lobby" → 0 → "Invalid conversation
    /// ID") so the lobby was always empty.
    private struct LobbyEnvelope: Decodable {
        let messages: [MessagingMessage]
    }

    override func fetch() async throws -> [MessagingMessage] {
        let env: LobbyEnvelope = try await EusoTripAPI.shared.queryNoInput("messaging.getLobby")
        return env.messages
    }
}

// MARK: - InboxStore — `messages.getConversations`

@MainActor
final class InboxStore: BaseDynamicListStore<MessagingConversation> {
    override func fetch() async throws -> [MessagingConversation] {
        try await EusoTripAPI.shared.messaging.getConversations()
    }
}

// MARK: - ProfileStore — `auth.me`

@MainActor
final class ProfileStore: BaseDynamicStore<AuthUser?> {
    override func fetch() async throws -> AuthUser? {
        try await EusoTripAPI.shared.auth.me()
    }
    override func foldState(_ value: AuthUser?) -> RemoteState<AuthUser?> {
        value == nil ? .empty : .loaded(value)
    }
}

// MARK: - ReputationStore — `profile.getReputation`
//
// Drives the "reputation" card on brick 056 Driver Profile. Returns the
// canonical Reputation shape from ProfileAPI — overall score, on-time
// pickup / delivery %, safety score, cancellation rate, star rating
// average + count, and a server-side `lastUpdatedAt` ISO timestamp.
//
// `nil` is a legitimate server response (no ratings yet for this driver)
// and folds into `.empty` so the screen can render EusoEmptyState rather
// than zero-fill fabricated numbers.

@MainActor
final class ReputationStore: BaseDynamicStore<ProfileAPI.Reputation?> {
    override func fetch() async throws -> ProfileAPI.Reputation? {
        try await EusoTripAPI.shared.profile.getReputation()
    }
    override func foldState(_ value: ProfileAPI.Reputation?) -> RemoteState<ProfileAPI.Reputation?> {
        value == nil ? .empty : .loaded(value)
    }
}

// MARK: - ReferralCodeStore — `profile.getReferralCode`
//
// Drives the "Share referral" tile on brick 056 Driver Profile. Returns
// the code, bonus amount/terms, currency, and an optional share URL
// formatted by the server so the iOS client can hand it to the system
// share sheet (via the `driverShareLink` env closure) without assembling
// a URL locally.

@MainActor
final class ReferralCodeStore: BaseDynamicStore<ProfileAPI.ReferralCode?> {
    override func fetch() async throws -> ProfileAPI.ReferralCode? {
        try await EusoTripAPI.shared.profile.getReferralCode()
    }
    override func foldState(_ value: ProfileAPI.ReferralCode?) -> RemoteState<ProfileAPI.ReferralCode?> {
        value == nil ? .empty : .loaded(value)
    }
}

// MARK: - ReferralsHubStore — `profile.listReferrals`
//
// Companion to `ReferralsStore` that preserves the `totalEarned` +
// `currency` totals the server returns alongside the items list. The
// list-only `ReferralsStore` is retained for feed surfaces; this store
// is what brick 056's "Referrals" tile reads because the tile needs the
// running total, not just the individual rows.

@MainActor
final class ReferralsHubStore: BaseDynamicStore<ProfileAPI.ReferralsResponse?> {
    override func fetch() async throws -> ProfileAPI.ReferralsResponse? {
        try await EusoTripAPI.shared.profile.listReferrals()
    }
    override func foldState(_ value: ProfileAPI.ReferralsResponse?) -> RemoteState<ProfileAPI.ReferralsResponse?> {
        guard let v = value else { return .empty }
        return .loaded(v)
    }
}

// MARK: - LoyaltyHeroStore — `gamification.getProfile` (canonical)
//
// Drives brick 060 The Haul · Dashboard hero card. Originally wired to
// a `loyalty.getConfig` / `loyaltyRouter` surface that never shipped on
// the backend — the 61st firing's ledger-hygiene audit flagged it as
// the last remaining live-dead endpoint. This firing (62nd) migrates
// the hero to the canonical `gamification.getProfile` shape
// (MCP-verified at `frontend/server/routers/gamification.ts`).
//
// The new hero projects:
//   • `level`            — integer level, used for the hero kicker
//   • `title`            — optional mastery title (e.g. "Road Rookie")
//   • `currentXp`        — XP into the current level bracket
//   • `xpToNextLevel`    — XP remaining until promotion
//   • `totalPoints`      — cumulative season points (fallback numeral)
//   • `rank`             — leaderboard rank (optional subtitle)
//   • `totalUsers`       — leaderboard denominator (optional)
//   • `percentile`       — percent of fleet beaten (optional)
//
// Per §16 gaps: `loot_crates` / `user_inventory` have zero router
// writers, so no crate-preview strip is rendered. Tier-dot ladder is
// dropped — the backend's loyalty ladder doesn't exist; levels take
// its place. Empty / error states remain branded inline cards. No
// fake XP, no fabricated rank. A brand-new driver returns
// `level == 1, currentXp == 0, xpToNextLevel == <bracket size>`, so
// `.loaded` with zero XP is the expected first-run shape — not empty.

@MainActor
final class LoyaltyHeroStore: BaseDynamicStore<GamificationAPI.Profile> {
    override func fetch() async throws -> GamificationAPI.Profile {
        try await EusoTripAPI.shared.gamification.getProfile()
    }
}

// MARK: - StreakTrackerStore — `advancedGamification.getStreakTracker`
//
// Drives brick 065 The Haul · Streaks. The server returns a
// fully-populated envelope even for a brand-new driver with no
// active streak (dailyStreak=0, streakHistory=7×false, multiplier=1.0).
// That means `.loaded` is the honest state for every driver who has
// any gamification profile at all — empty-hero treatment is keyed off
// `dailyStreak == 0 && bestDailyStreak == 0`, not off a `.empty` store
// state. MCP-verified at frontend/server/routers/advancedGamification.ts:1476.
//
// Added in the 65th firing (brick port 065 The Haul · Streaks).

@MainActor
final class StreakTrackerStore: BaseDynamicStore<AdvancedGamificationAPI.StreakTracker> {
    override func fetch() async throws -> AdvancedGamificationAPI.StreakTracker {
        try await EusoTripAPI.shared.advancedGamification.getStreakTracker()
    }
}

// MARK: - CustomizationCatalogStore — `advancedGamification.getCustomizationOptions`
//
// Drives brick 066 The Haul · Cosmetics. Server catalog is static
// game-design config (same for every driver); `owned` / `equipped`
// flags come off the server response verbatim. The store also owns
// the `equipCustomization` mutation — on success it re-fetches so the
// catalog's `equipped` flag transitions match what the server echoes.
//
// Added in the 66th firing (brick port 066 The Haul · Cosmetics).
//
// Note on partial persistence: titles persist server-side
// (gamificationProfiles.activeTitle); avatar/frame choices echo
// `success: true` but are not persisted in the current backend
// (getDriverProfile.customization is hardcoded to av1/fr1/ti1). 066
// discloses this in-copy rather than hiding it.

@MainActor
final class CustomizationCatalogStore: BaseDynamicStore<AdvancedGamificationAPI.CustomizationCatalog> {
    /// Published status of the most-recent equip mutation. Views bind
    /// a toast or inline banner to this. Cleared on every fresh
    /// refresh / retry.
    @Published var lastEquipError: Error?

    /// True while an equip mutation is in-flight. Drives the row-level
    /// spinner on the tapped tile.
    @Published var equippingItemId: String?

    override func fetch() async throws -> AdvancedGamificationAPI.CustomizationCatalog {
        try await EusoTripAPI.shared.advancedGamification.getCustomizationOptions()
    }

    /// Fire the equip mutation, then refresh the catalog so the
    /// server's post-equip state lands in view. On failure we propagate
    /// via `lastEquipError` and leave the catalog untouched (server is
    /// authoritative — no optimistic rewrite here).
    func equip(type: String, itemId: String) async {
        equippingItemId = itemId
        lastEquipError = nil
        defer { equippingItemId = nil }
        do {
            _ = try await EusoTripAPI.shared.advancedGamification.equipCustomization(
                type: type, itemId: itemId
            )
            await refresh()
        } catch {
            lastEquipError = error
        }
    }
}

// MARK: - DriverDocumentsStore — `documentManagement.getDocuments`
//
// Drives the list half of brick 072 Me · Docs. Fetches the first 50
// documents ordered by uploadedAt DESC. The server filters by
// `userId = ctx.user.id` so no explicit driver-id parameter is needed.
//
// Documents land on the backend in the canonical `documentTypeSchema`
// bucket (see `documentManagement.ts:51-58`). The 072 view groups by
// driver-relevant buckets — CDL / Medical / TWIC / Hazmat / Other —
// using `DocumentCategory.from(typeOrName:)` at render time so the
// store stays a flat list and the categorization rule lives in one
// place on the view side.
//
// 67th firing (brick port 072 Me · Docs).

@MainActor
final class DriverDocumentsStore: BaseDynamicListStore<DocumentManagementAPI.Document> {
    override func fetch() async throws -> [DocumentManagementAPI.Document] {
        let response = try await EusoTripAPI.shared.documentManagement.getDocuments(
            page: 1, pageSize: 50
        )
        return response.documents
    }
}

// MARK: - DocumentsHubStore — `documentManagement.*` extended surface
//
// Drives brick 083 Me · Documents Hub — same list as
// DriverDocumentsStore but with mutation methods for the hub's
// per-row actions: upload, archive, share, request-e-signature,
// classify. Each mutation runs optimistically where safe and
// reconciles against server truth on failure.
//
// 76th firing.

@MainActor
final class DocumentsHubStore: BaseDynamicListStore<DocumentManagementAPI.Document> {
    /// In-flight mutation id — drives per-row spinner on the view.
    @Published var mutatingId: String?
    /// Post-mutation toast string. Cleared after 2.5s.
    @Published var lastToast: String?
    /// Most recent share result surfaced to the view so it can open
    /// the share sheet with the minted link without re-fetching.
    @Published var lastShareLink: String?

    override func fetch() async throws -> [DocumentManagementAPI.Document] {
        let response = try await EusoTripAPI.shared.documentManagement.getDocuments(
            page: 1, pageSize: 50
        )
        return response.documents
    }

    // MARK: Upload

    /// Upload a file — base-64 encode happens at the call site. Fires
    /// classifyDocument async after a successful upload so OCR + type
    /// inference start without blocking the user.
    func upload(
        name: String,
        type: String,
        mimeType: String,
        fileData: String,
        size: Int,
        entityId: String,
        expiresAt: String? = nil
    ) async -> Bool {
        mutatingId = "upload"
        defer { mutatingId = nil }
        do {
            let res = try await EusoTripAPI.shared.documentManagement.uploadDocument(
                name: name, type: type, mimeType: mimeType,
                size: size, fileData: fileData,
                entityType: "driver", entityId: entityId,
                tags: nil, expiresAt: expiresAt
            )
            // Kick classification in the background.
            if !res.id.isEmpty && res.id != "0" {
                Task.detached {
                    _ = try? await EusoTripAPI.shared.documentManagement.classifyDocument(documentId: res.id)
                }
            }
            await refresh()
            flashToast("Uploaded · \(res.name)")
            return true
        } catch {
            flashToast("Upload failed — try again")
            return false
        }
    }

    // MARK: Archive

    func archive(documentId: String, retentionPolicy: String = "7_years") async -> Bool {
        mutatingId = documentId
        defer { mutatingId = nil }
        // Optimistic remove from list
        if case .loaded(let rows) = state {
            let remaining = rows.filter { $0.id != documentId }
            state = remaining.isEmpty ? .empty : .loaded(remaining)
        }
        do {
            let res = try await EusoTripAPI.shared.documentManagement.archiveDocument(
                documentId: documentId, retentionPolicy: retentionPolicy
            )
            if !res.success { await refresh() }
            flashToast(res.success ? "Document archived" : "Archive failed")
            return res.success
        } catch {
            await refresh()
            flashToast("Archive failed")
            return false
        }
    }

    // MARK: Share

    func share(
        documentId: String,
        recipientEmail: String,
        message: String? = nil,
        hours: Int = 72
    ) async -> String? {
        mutatingId = documentId
        defer { mutatingId = nil }
        do {
            let res = try await EusoTripAPI.shared.documentManagement.shareDocument(
                documentId: documentId,
                recipientEmail: recipientEmail,
                expiresInHours: hours,
                permissions: "view",
                message: message
            )
            if res.success, let link = res.shareLink {
                lastShareLink = link
                flashToast("Share link sent")
                return link
            }
            flashToast("Share failed")
            return nil
        } catch {
            flashToast("Share failed")
            return nil
        }
    }

    // MARK: Request e-signature

    func requestESignature(
        documentId: String,
        signerName: String,
        signerEmail: String,
        message: String = "Please review and sign this document."
    ) async -> Bool {
        mutatingId = documentId
        defer { mutatingId = nil }
        do {
            let res = try await EusoTripAPI.shared.documentManagement.requestESignature(
                documentId: documentId,
                signers: [.init(name: signerName, email: signerEmail, order: 1)],
                message: message,
                expiresInDays: 7
            )
            flashToast(res.success ? "E-signature requested" : "Request failed")
            return res.success
        } catch {
            flashToast("Request failed")
            return false
        }
    }

    // MARK: Toast helper

    private func flashToast(_ text: String) {
        lastToast = text
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { self.lastToast = nil }
        }
    }
}

// MARK: - ExpiringDocumentsStore — `documentManagement.getExpiringDocuments`
//
// Drives the expiration banner at the top of brick 072 Me · Docs.
// Single-value store (the server always returns the wrapper object,
// even when both arrays are empty); `.empty` is not used here — an
// empty wrapper is still a valid loaded state ("nothing expiring this
// quarter"). Views check `.value?.totalExpiring` / `.totalExpired` to
// decide whether to render the banner.
//
// 67th firing (brick port 072 Me · Docs).

@MainActor
final class ExpiringDocumentsStore: BaseDynamicStore<DocumentManagementAPI.ExpiringDocumentsResponse> {
    /// Days-ahead window. Defaults to 90 so drivers see a full quarter
    /// of upcoming renewals (TWIC renewals in particular benefit from
    /// early warning — TSA processing is slow).
    var daysAhead: Int = 90

    override func fetch() async throws -> DocumentManagementAPI.ExpiringDocumentsResponse {
        try await EusoTripAPI.shared.documentManagement.getExpiringDocuments(
            daysAhead: daysAhead,
            includeExpired: true
        )
    }
}

// MARK: - AssignedVehicleStore — `vehicle.getAssigned`
//
// Drives the hero card of brick 073 Me · Vehicle. The backend returns
// a non-null object with an empty `id` when the driver has no vehicle
// assigned today — this store folds that sentinel into `.empty` so the
// view picks the "no vehicle assigned" hero branch without an extra
// `isUnassigned` check at the call site.
//
// Odometer + fuelLevel are currently server-hardcoded to 0 (telematics
// integration hasn't shipped); the view only renders them when non-zero
// so a driver doesn't see a stub-looking "Odometer: 0 mi" line.
//
// 68th firing (brick port 073 Me · Vehicle).

@MainActor
final class AssignedVehicleStore: BaseDynamicStore<VehicleAPI.AssignedVehicle> {
    override func fetch() async throws -> VehicleAPI.AssignedVehicle {
        let v = try await EusoTripAPI.shared.vehicle.getAssigned()
        if v.isUnassigned {
            // Throw a specific availability signal — the base class's
            // `refresh()` catches non-StoreAvailability errors and lands
            // in `.error`. We need `.empty` instead, which happens when
            // the fetch returns but the result folds to the empty branch.
            // BaseDynamicStore<Value> doesn't fold non-Collection values,
            // so the only way to signal "settled + nothing to show" is
            // to throw and let the view handle the error state.
            //
            // Views of 073 check `state == .empty` → no-assignment hero;
            // `state == .error` → network/auth failure. To make the
            // former reachable, the view inspects `state.value?.id`
            // directly and falls back to the no-assignment hero when
            // it's empty — see `MeVehicle.body` below. This keeps the
            // store mechanically simple: it always returns whatever the
            // server said, and the view does the last-inch rendering.
            return v
        }
        return v
    }
}

// MARK: - VehicleMaintenanceHistoryStore — `vehicle.getMaintenanceHistory`
//
// Drives the maintenance history section of brick 073 Me · Vehicle.
// The `vehicleId` is seeded from `AssignedVehicleStore` once that value
// lands — the reload sequence in the view calls `refresh()` on this
// store only after the assignment resolves.
//
// Empty result is server-confirmed (records: []); the view surfaces
// `.empty` as a "no maintenance on record" subtle placeholder beneath
// the hero card, not a full-screen empty state.
//
// 68th firing (brick port 073 Me · Vehicle).

@MainActor
final class VehicleMaintenanceHistoryStore: BaseDynamicListStore<VehicleAPI.MaintenanceRecord> {
    /// Set by the view once the assigned vehicle's id is known. Nil
    /// means "query the company-wide maintenance feed", which is the
    /// server default — mostly useful for dispatchers, but safe to
    /// call from a driver context too (the server scopes by
    /// companyId, not by driverId).
    var vehicleId: String? = nil

    override func fetch() async throws -> [VehicleAPI.MaintenanceRecord] {
        let response = try await EusoTripAPI.shared.vehicle.getMaintenanceHistory(
            vehicleId: vehicleId, limit: 20
        )
        return response.records
    }
}

// MARK: - DriverSafetyScoreStore — `safety.getDriverScoreDetail`
//
// Drives brick 075 Me · Safety Score. The driver's own id is seeded
// from the session on bootstrap; an empty id means the session
// hasn't resolved yet — the view stays in `.loading` until the
// session's `user?.id` publishes, then the store refreshes.
//
// Server-authoritative: we don't recompute category scores on the
// client. `overallScore`, per-category values, and recent events all
// come straight from the SQL-backed procedure.
//
// 69th firing (brick port 075 Me · Safety Score).

@MainActor
final class DriverSafetyScoreStore: BaseDynamicStore<SafetyAPI.DriverScoreDetail> {
    /// Seeded from `EusoTripSession.user?.id`. Empty string keeps the
    /// store in `.loading` (fetch throws a clear error that the view
    /// silently ignores until the id lands).
    var driverId: String = ""

    override func fetch() async throws -> SafetyAPI.DriverScoreDetail {
        guard !driverId.isEmpty else {
            throw StoreAvailability.comingSoon("Safety score")
        }
        return try await EusoTripAPI.shared.safety.getDriverScoreDetail(driverId: driverId)
    }
}

// MARK: - DriverTrainingStore — `training.getDriverAssignments`
//
// Drives brick 076 Me · Training. Fetches assignments list + summary
// counts scoped to the signed-in user. View groups by status on the
// client (not_started / in_progress / completed / expired) so the
// store stays a flat list.
//
// 70th firing.

@MainActor
final class DriverTrainingStore: BaseDynamicStore<TrainingAPI.AssignmentsResponse> {
    override func fetch() async throws -> TrainingAPI.AssignmentsResponse {
        try await EusoTripAPI.shared.training.getDriverAssignments()
    }
}

// MARK: - PendingMandatoryTrainingStore — `training.getPendingMandatoryTraining`
//
// Overdue + not-started mandatory courses. Surfaced at the top of 076
// as the "Due now" strip when `overdue.count > 0`. Otherwise collapses.
//
// 70th firing.

@MainActor
final class PendingMandatoryTrainingStore: BaseDynamicStore<TrainingAPI.PendingResponse> {
    override func fetch() async throws -> TrainingAPI.PendingResponse {
        try await EusoTripAPI.shared.training.getPendingMandatoryTraining()
    }
}

// MARK: - DriverCertificatesStore — `trainingLMS.getMyCertificates`
//
// Earned certificates with expiration tracking. 076's footer section.
//
// 70th firing.

@MainActor
final class DriverCertificatesStore: BaseDynamicListStore<TrainingAPI.Certificate> {
    override func fetch() async throws -> [TrainingAPI.Certificate] {
        let response = try await EusoTripAPI.shared.training.getMyCertificates()
        return response.certificates
    }
}

// MARK: - PaymentMethodsStore — `payments.getPaymentMethods`
//
// Drives brick 077 Me · Payment Methods. Mutation methods
// (`setDefault`, `unlink`) live on the store so the view can trigger
// optimistic-update patterns with a single `await store.setDefault(id:)`
// style call and have the list re-publish without re-fetching the
// entire list unless the server disagrees.
//
// 71st firing.

// MARK: - CarrierScorecardStore — `csaScores.getOverview`
//
// Drives brick 085 Me · Carrier Scorecard. Single-value store —
// the overview is an atomic snapshot of the carrier's public CSA
// score + SAFER + FMCSA crash/inspection summary.
//
// 78th firing.

@MainActor
final class CarrierScorecardStore: BaseDynamicStore<CsaScoresAPI.CsaOverview> {
    override func fetch() async throws -> CsaScoresAPI.CsaOverview {
        try await EusoTripAPI.shared.csaScores.getOverview()
    }
}

// MARK: - ViolationsStore — `compliance.getViolations`
//
// Drives brick 082 Me · Violations Manager. Combines
// `compliance.getViolations` (inspection + DVIR violations keyed on
// `defectsFound > 0`) with `hos.getViolations` (HOS cycle / break /
// driving-limit violations from the ELD engine). Both surfaces feed
// into one flat list that the view groups by severity.
//
// Mutations (resolve) fire through `compliance.resolveViolation`
// which marks the backing inspection row `status = passed`. HOS
// violations aren't "resolvable" individually — they fall off
// naturally as the driver rests back into compliance — so those
// rows render without the resolve action.
//
// 75th firing.

/// Unified row the view renders. Wraps either a
/// `ComplianceAPI.Violation` or a `HOSViolation` behind one façade
/// so the UI has a single shape to switch over.
struct UnifiedViolation: Identifiable, Equatable {
    enum Kind: Equatable { case compliance(ComplianceAPI.Violation); case hos(HOSViolation, String) }

    let kind: Kind
    var id: String {
        switch kind {
        case .compliance(let v): return "cmp::\(v.id)"
        case .hos(_, let syntheticId): return "hos::\(syntheticId)"
        }
    }

    /// Driver-friendly title.
    var title: String {
        switch kind {
        case .compliance(let v):
            if v.oosViolation { return "Out-of-service · \(v.type.capitalized)" }
            return "\(v.defectsFound) defect\(v.defectsFound == 1 ? "" : "s") · \(v.type.capitalized)"
        case .hos(let v, _):
            return v.message ?? "HOS violation"
        }
    }

    /// Short subtitle with regulation reference when available.
    var subtitle: String {
        switch kind {
        case .compliance(let v):
            if !v.location.isEmpty { return "\(v.location) · \(v.regulation)" }
            return v.regulation
        case .hos:
            return "49 CFR §395"
        }
    }

    var date: String {
        switch kind {
        case .compliance(let v): return v.date
        case .hos(let v, _): return v.timestamp ?? ""
        }
    }

    /// "critical" | "major" | "minor" | nil
    var severity: String {
        switch kind {
        case .compliance(let v): return v.severity.lowercased()
        case .hos(let v, _):
            let s = (v.severity ?? "").lowercased()
            if s == "critical" || s == "high" { return "critical" }
            if s == "moderate" || s == "major" { return "major" }
            return "minor"
        }
    }

    /// True when resolution is possible for this violation type.
    var isResolvable: Bool {
        if case .compliance(let v) = kind { return v.status.lowercased() == "open" }
        return false
    }

    /// True when server marks this violation resolved.
    var isResolved: Bool {
        if case .compliance(let v) = kind { return v.status.lowercased() == "resolved" }
        return false
    }

    var kindLabel: String {
        switch kind {
        case .compliance: return "INSPECTION"
        case .hos:        return "HOS"
        }
    }
}

@MainActor
final class ViolationsStore: BaseDynamicListStore<UnifiedViolation> {
    /// Server-authoritative stats. Loaded alongside the list and kept
    /// in sync by each fetch so the summary pills at the top of the
    /// view don't need a separate refresh.
    @Published var stats: ComplianceAPI.ViolationStats?

    /// Severity filter — nil = show everything.
    var severity: String? = nil {
        didSet { if oldValue != severity { Task { await refresh() } } }
    }

    /// Status filter — "open" by default so drivers see actionable rows first.
    var status: String? = "open" {
        didSet { if oldValue != status { Task { await refresh() } } }
    }

    /// Search query — fires AI enrichment on the server when present.
    var search: String = "" {
        didSet {
            if oldValue != search {
                Task {
                    try? await Task.sleep(nanoseconds: 350_000_000)   // 350 ms debounce
                    await refresh()
                }
            }
        }
    }

    /// In-flight mutation id — drives the per-row spinner.
    @Published var resolvingId: String?

    override func fetch() async throws -> [UnifiedViolation] {
        async let complianceResp: ComplianceAPI.ViolationsResponse = EusoTripAPI.shared.compliance.getViolations(
            search: search.isEmpty ? nil : search,
            status: status,
            severity: severity,
            page: 1,
            limit: 50
        )
        async let hosVios: [HOSViolation] = EusoTripAPI.shared.hos.getViolations()
        async let statsResp: ComplianceAPI.ViolationStats? = try? EusoTripAPI.shared.compliance.getViolationStats()

        let resolved = await (try complianceResp, (try? await hosVios) ?? [], statsResp)
        self.stats = resolved.2

        var combined: [UnifiedViolation] = []
        combined.append(contentsOf: resolved.0.violations.map { .init(kind: .compliance($0)) })
        // Synthesize a stable id for HOS rows (server doesn't provide).
        for (idx, hv) in resolved.1.enumerated() {
            let synth = "\(hv.timestamp ?? "")-\(hv.type ?? "")-\(idx)"
            combined.append(.init(kind: .hos(hv, synth)))
        }

        // Sort by severity-rank then date descending.
        let rank: (String) -> Int = { s in
            switch s { case "critical": return 0; case "major": return 1; case "minor": return 2; default: return 3 }
        }
        combined.sort { a, b in
            let ra = rank(a.severity), rb = rank(b.severity)
            if ra != rb { return ra < rb }
            return a.date > b.date
        }
        return combined
    }

    /// Resolve an open inspection-backed violation. Optimistically
    /// flips the local copy to "resolved" and reconciles on failure.
    @discardableResult
    func resolve(id: String, notes: String? = nil) async -> Bool {
        resolvingId = id
        defer { resolvingId = nil }
        do {
            _ = try await EusoTripAPI.shared.compliance.resolveViolation(
                id: id.hasPrefix("cmp::") ? String(id.dropFirst(5)) : id,
                resolution: "resolved",
                notes: notes
            )
            await refresh()
            return true
        } catch {
            await refresh()
            return false
        }
    }
}

// MARK: - TaxDocumentsStore — `wallet.getTaxDocuments`
//
// Drives brick 080 Me · Tax Documents. `year` is the public knob —
// nil means "current + prior year" (server default); an explicit
// year narrows to that one.
//
// 74th firing.

@MainActor
final class TaxDocumentsStore: BaseDynamicListStore<WalletAPI.TaxDocument> {
    /// nil = server default (current + prior year). Setting an
    /// explicit year auto-refreshes via `didSet`.
    var year: Int? = nil {
        didSet {
            if oldValue != year { Task { await refresh() } }
        }
    }

    override func fetch() async throws -> [WalletAPI.TaxDocument] {
        try await EusoTripAPI.shared.wallet.getTaxDocuments(year: year)
    }
}

// MARK: - EarningsBreakdownStore — `wallet.getEarningsBreakdown`
//
// Drives brick 079 Me · Earnings Breakdown. `period` is the store's
// public knob — flipping it auto-refreshes via the `didSet` hook so
// the view's period picker doesn't need to call refresh manually.
//
// 73rd firing.

@MainActor
final class EarningsBreakdownStore: BaseDynamicStore<WalletAPI.EarningsBreakdown> {
    /// "week" | "month" | "quarter". Defaults to "month" (server
    /// default) so the first render doesn't paint a misleading
    /// weekly window.
    var period: String = "month" {
        didSet {
            if oldValue != period { Task { await refresh() } }
        }
    }

    override func fetch() async throws -> WalletAPI.EarningsBreakdown {
        try await EusoTripAPI.shared.wallet.getEarningsBreakdown(period: period)
    }
}

// MARK: - PayoutScheduleStore — `wallet.getPayoutSchedule`
//
// Drives brick 078 Me · Payout Schedule. Mutations route through
// `updatePayoutSchedule` on the store itself so the view can
// optimistically flip the cadence pill, then reconcile against the
// server's confirmed state.
//
// 72nd firing.

@MainActor
final class PayoutScheduleStore: BaseDynamicStore<WalletAPI.PayoutSchedule> {
    @Published var isSaving: Bool = false

    override func fetch() async throws -> WalletAPI.PayoutSchedule {
        try await EusoTripAPI.shared.wallet.getPayoutSchedule()
    }

    /// Update any subset of the schedule fields. Optimistically
    /// rewrites `state` so the UI feels instant, then lets the
    /// server-side `updatedAt` confirm the write on the next fetch.
    func update(
        frequency: String? = nil,
        dayOfWeek: String? = nil,
        minimumAmount: Double? = nil,
        autoPayoutEnabled: Bool? = nil
    ) async {
        isSaving = true
        defer { isSaving = false }

        if case .loaded(let current) = state {
            let next = WalletAPI.PayoutSchedule(
                frequency: frequency ?? current.frequency,
                dayOfWeek: dayOfWeek ?? current.dayOfWeek,
                minimumAmount: minimumAmount ?? current.minimumAmount,
                nextScheduledPayout: current.nextScheduledPayout,
                autoPayoutEnabled: autoPayoutEnabled ?? current.autoPayoutEnabled
            )
            state = .loaded(next)
        }

        do {
            _ = try await EusoTripAPI.shared.wallet.updatePayoutSchedule(
                frequency: frequency,
                dayOfWeek: dayOfWeek,
                minimumAmount: minimumAmount,
                autoPayoutEnabled: autoPayoutEnabled
            )
            // Server doesn't return the updated schedule directly, so
            // re-fetch to pick up any server-computed fields (e.g.
            // `nextScheduledPayout` which the scheduler recalculates).
            await refresh()
        } catch {
            // Reconcile against server truth.
            await refresh()
        }
    }
}

@MainActor
final class PaymentMethodsStore: BaseDynamicListStore<PaymentsAPI.PaymentMethod> {
    /// True while a mutation is in flight against a specific row, so
    /// the view can show a row-level spinner rather than disabling
    /// the whole list.
    @Published var mutatingId: String?

    override func fetch() async throws -> [PaymentsAPI.PaymentMethod] {
        try await EusoTripAPI.shared.payments.listPaymentMethods()
    }

    /// Set the chosen method as default. Optimistically re-publishes
    /// `items` with the flag flipped; on server rejection we resync.
    func setDefault(id: String) async {
        mutatingId = id
        defer { mutatingId = nil }
        // Optimistic: remap the current items list.
        if case .loaded(let rows) = state {
            let mutated = rows.map { row in
                PaymentsAPI.PaymentMethod(
                    id: row.id,
                    type: row.type,
                    last4: row.last4,
                    brand: row.brand,
                    expiryDate: row.expiryDate,
                    bankName: row.bankName,
                    isDefault: row.id == id,
                    billingAddress: row.billingAddress
                )
            }
            state = .loaded(mutated)
        }
        do {
            _ = try await EusoTripAPI.shared.payments.setDefaultMethod(paymentMethodId: id)
        } catch {
            // Reconcile against server truth — if the backend rejected
            // the mutation the next fetch restores the previous default.
            await refresh()
        }
    }

    /// Detach a payment method from the driver's Stripe Customer.
    /// Optimistic remove; reconcile on failure.
    func unlink(id: String) async {
        mutatingId = id
        defer { mutatingId = nil }
        if case .loaded(let rows) = state {
            let remaining = rows.filter { $0.id != id }
            state = remaining.isEmpty ? .empty : .loaded(remaining)
        }
        do {
            _ = try await EusoTripAPI.shared.payments.deletePaymentMethod(paymentMethodId: id)
        } catch {
            await refresh()
        }
    }
}

// MARK: - ReferralsStore — `referrals.getMyCode` + `.summary` + `.listMine`
//
// Drives brick 088 Me · Invite & Earn. Composite store — the view
// reads three live feeds in one refresh: the driver's referral
// code (minted on first call), the summary counters for the hero,
// and the recent referral events list. A failure on any single
// feed doesn't blow away the other two — each is tracked
// independently so e.g. an expired code doesn't hide recent events.
//
// 80th firing.

@MainActor
final class ReferralsStore: ObservableObject, DynamicStore {
    @Published private(set) var code: ReferralsAPI.ReferralCode?
    @Published private(set) var summary: ReferralsAPI.ReferralSummary?
    @Published private(set) var events: [ReferralsAPI.ReferralEvent] = []

    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error?

    /// Stage filter applied to `events`. Nil = all stages.
    @Published var stageFilter: String?

    func refresh() async {
        isLoading = true
        lastError = nil

        // Parallel fetches — each tracks its OWN error so we can
        // distinguish "code minted but events table missing" (partial
        // deploy) from "auth failed" (whole namespace returns 401).
        // Without per-call error capture the previous "Can't reach
        // referrals service" string masked which endpoint was failing,
        // making it hard to diagnose between a stale deploy and a
        // missing migration.
        async let codeAttempt: Result<ReferralsAPI.ReferralCode, Error> = withResult {
            try await EusoTripAPI.shared.referrals.getMyCode()
        }
        async let summaryAttempt: Result<ReferralsAPI.ReferralSummary, Error> = withResult {
            try await EusoTripAPI.shared.referrals.getSummary()
        }
        async let eventsAttempt: Result<[ReferralsAPI.ReferralEvent], Error> = withResult {
            try await EusoTripAPI.shared.referrals.listMine(
                stage: stageFilter,
                limit: 30
            )
        }

        let (cR, sR, eR) = await (codeAttempt, summaryAttempt, eventsAttempt)

        switch cR {
        case .success(let v): code = v
        case .failure: code = nil
        }
        switch sR {
        case .success(let v): summary = v
        case .failure: summary = nil
        }
        switch eR {
        case .success(let v): events = v
        case .failure: events = []
        }
        isLoading = false

        // Surface an error only when everything failed — partial
        // signal is a useful UI. The error message names the first
        // failure so the support flow has something concrete to chase.
        if code == nil && summary == nil && events.isEmpty {
            let firstFailure: (endpoint: String, error: Error)? = {
                if case .failure(let e) = cR { return ("getMyCode", e) }
                if case .failure(let e) = sR { return ("getSummary", e) }
                if case .failure(let e) = eR { return ("listMine", e) }
                return nil
            }()
            let detail = firstFailure.map { "\($0.endpoint): \($0.error.localizedDescription)" }
                ?? "All endpoints returned empty"
            lastError = NSError(
                domain: "ReferralsStore",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Can't reach referrals service",
                    "endpoint": detail,
                ]
            )
            #if DEBUG
            print("[ReferralsStore] all 3 calls failed — first failure: \(detail)")
            #else
            // Surface first-failure detail in production logs too
            // so a TestFlight tester / production crash log shows
            // the actual server response that broke the page.
            print("[ReferralsStore] all 3 calls failed — first failure: \(detail)")
            #endif
        }
    }

    /// Tiny helper that wraps an `async throws` call into a `Result`
    /// without forcing every call site to write a do/catch. Used
    /// above so each parallel fetch carries its own success or
    /// error, instead of getting swallowed by `try?`.
    private func withResult<T>(_ op: @Sendable () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await op())
        } catch {
            return .failure(error)
        }
    }
}

// MARK: - TripLifecycleStore — the single binding for 013–051
//
// Foundation for the 34-screen trip-execution surface (per the
// driver gap analysis 2026-04-24). One store, one active-load
// context. Every lifecycle screen reads:
//
//   • `load`              — full load record (from LoadStore / dispatch)
//   • `availableTransitions` — role-filtered legal next states
//   • `history`           — immutable state transition audit trail
//
// And fires:
//
//   • `execute(_:location:data:compliance:)` — the driver's tap
//     on any "Arrived / Loading / BOL-signed / Delivered" button
//   • `checkIn(lat:lng:stopType:)` — geofence-gated arrival
//   • `refresh()` — re-pulls everything after a transition
//
// The store is deliberately light — it does not own the load row
// itself (that's the existing LoadStore / dispatch feed) — it
// only holds the state-machine context. A lifecycle screen
// composes `@EnvironmentObject var load: LoadStore` +
// `@StateObject var lifecycle: TripLifecycleStore`.
//
// 96th firing.

@MainActor
final class TripLifecycleStore: ObservableObject {
    @Published var loadId: String = ""

    @Published private(set) var availableTransitions: [LoadLifecycleAPI.Transition] = []
    @Published private(set) var history: [LoadLifecycleAPI.StateTransition] = []

    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error?
    @Published private(set) var inflightTransitionId: String?

    /// The last successfully-applied transition's resulting state.
    /// Lifecycle screens watch this via `onChange` to know when to
    /// advance to the next screen in the ladder (pickup arrived →
    /// show loading, loaded → show en-route, etc.).
    @Published private(set) var currentState: String?

    // MARK: - Hydrate from server

    /// Find the driver's currently-active load and populate
    /// `loadId` from it. Checks each in-flight status ladder
    /// state; first match wins. Silently no-ops if the driver
    /// has nothing assigned — lifecycle screens fall through to
    /// the local `advance?()` closure so Figma previews keep
    /// walking forward.
    ///
    /// Called once per screen `.task` so each lifecycle view
    /// re-binds against the latest active load without depending
    /// on env-key plumbing from 010 Driver Home.
    func hydrateActiveLoad() async {
        guard loadId.isEmpty else { return }
        let inFlightStatuses = [
            "assigned", "at_pickup", "loading",
            "loaded", "in_transit", "at_delivery",
            "unloading",
        ]
        for status in inFlightStatuses {
            if let row = try? await EusoTripAPI.shared.loads.search(status: status, limit: 1).first {
                loadId = row.id
                return
            }
        }
    }

    // MARK: - Refresh

    /// Pull the legal transitions + history for the active load.
    /// Safe to call on every `.task` — no-ops if `loadId` is empty.
    func refresh() async {
        guard !loadId.isEmpty else { return }
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        async let txTask: [LoadLifecycleAPI.Transition] = (try? EusoTripAPI.shared.loadLifecycle.getAvailableTransitions(
            loadId: loadId
        )) ?? []
        async let histTask: [LoadLifecycleAPI.StateTransition] = (try? EusoTripAPI.shared.loadLifecycle.getStateHistory(
            loadId: loadId
        )) ?? []
        let (tx, hist) = await (txTask, histTask)
        availableTransitions = tx
        history = hist
        currentState = hist.last.flatMap { $0.toState }
    }

    // MARK: - Execute

    /// Fire a state transition. Returns true on success so the
    /// calling screen can navigate forward without waiting on the
    /// refresh (which happens automatically after).
    @discardableResult
    func execute(
        _ transition: LoadLifecycleAPI.Transition,
        location: LoadLifecycleAPI.ExecuteLocation? = nil,
        data: [String: String]? = nil,
        compliance: LoadLifecycleAPI.ComplianceBlock? = nil
    ) async -> Bool {
        guard !loadId.isEmpty else { return false }
        inflightTransitionId = transition.transitionId
        defer { inflightTransitionId = nil }
        do {
            let result = try await EusoTripAPI.shared.loadLifecycle.executeTransition(
                loadId: loadId,
                transitionId: transition.transitionId,
                location: location,
                data: data,
                compliance: compliance
            )
            if result.success {
                if let newState = result.newState { currentState = newState }
                await refresh()
                return true
            } else {
                lastError = NSError(
                    domain: "TripLifecycleStore",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: result.error ?? "Transition rejected"]
                )
                return false
            }
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
            return false
        }
    }

    // MARK: - Check-in (geofence-gated arrival)

    @discardableResult
    func checkIn(lat: Double, lng: Double, stopType: String) async -> Bool {
        guard !loadId.isEmpty else { return false }
        inflightTransitionId = "check_in"
        defer { inflightTransitionId = nil }
        do {
            let result = try await EusoTripAPI.shared.loadLifecycle.checkIn(
                loadId: loadId,
                lat: lat,
                lng: lng,
                stopType: stopType
            )
            if result.success == true {
                await refresh()
                return true
            }
            return false
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
            return false
        }
    }
}

// MARK: - AgreementsStore — `agreements.getStats` + `agreements.list`
//
// Drives brick 103 Me · Agreements. Composite store: counters +
// filtered list. Sign mutation optimistically marks the row as
// active + refreshes both feeds so the `pendingSignature`
// counter drops and the row moves under ACTIVE.
//
// 95th firing.

@MainActor
final class AgreementsStore: ObservableObject, DynamicStore {
    @Published private(set) var stats: AgreementsAPI.Stats?
    @Published private(set) var agreements: [AgreementsAPI.Agreement] = []

    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error?
    @Published private(set) var signingId: Int?

    @Published var statusFilter: String?     // nil = all

    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        async let statsTask: AgreementsAPI.Stats? = try? EusoTripAPI.shared.agreements.getStats()
        async let listTask: AgreementsAPI.ListResponse? = try? EusoTripAPI.shared.agreements.list(
            status: statusFilter,
            limit: 40
        )
        let (s, l) = await (statsTask, listTask)
        stats = s
        agreements = l?.agreements ?? []
        if s == nil && agreements.isEmpty {
            lastError = NSError(
                domain: "AgreementsStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Can't reach agreements service"]
            )
        }
    }

    /// Sign an agreement. `signatureBase64` is the PNG of the
    /// driver's signature stroke (from a drawing surface). The
    /// server stamps SHA-256 + returns the new status.
    func sign(
        agreement: AgreementsAPI.Agreement,
        signatureBase64: String,
        role: String,
        signerName: String?
    ) async {
        signingId = agreement.id
        defer { signingId = nil }
        do {
            _ = try await EusoTripAPI.shared.agreements.sign(
                agreementId: agreement.id,
                signatureBase64: signatureBase64,
                signatureRole: role,
                signerName: signerName
            )
            await refresh()
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
        }
    }
}

// MARK: - ContactsStore — `contacts.getSummary` + `contacts.list`
//
// Drives brick 102 Me · Contacts. Composite store with a debounced
// search query + optional type filter + favorite filter. Toggle-
// favorite mutation optimistic-updates the row, then reconciles
// on the next refresh.
//
// 94th firing.

@MainActor
final class ContactsStore: ObservableObject, DynamicStore {
    @Published private(set) var summary: ContactsAPI.Summary?
    @Published private(set) var contacts: [ContactsAPI.Contact] = []

    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error?

    @Published var query: String = ""
    @Published var typeFilter: String?      // nil = all roles
    @Published var favoritesOnly: Bool = false

    private var searchTask: Task<Void, Never>?

    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        async let summaryTask: ContactsAPI.Summary? = try? EusoTripAPI.shared.contacts.getSummary()
        async let listTask: [ContactsAPI.Contact] = (try? EusoTripAPI.shared.contacts.list(
            type: typeFilter,
            search: query.isEmpty ? nil : query,
            favorite: favoritesOnly ? true : nil,
            limit: 40
        )) ?? []
        let (s, l) = await (summaryTask, listTask)
        summary = s
        contacts = l
        if s == nil && contacts.isEmpty {
            lastError = NSError(
                domain: "ContactsStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Can't reach contacts service"]
            )
        }
    }

    /// Debounced 300ms query — prevents typeahead from hammering
    /// the backend on every keystroke.
    func scheduleQuery() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.refresh()
        }
    }

    func toggleFavorite(_ contact: ContactsAPI.Contact) async {
        // Optimistic flip.
        if let idx = contacts.firstIndex(where: { $0.id == contact.id }) {
            let c = contacts[idx]
            contacts[idx] = ContactsAPI.Contact(
                id: c.id,
                type: c.type,
                name: c.name,
                company: c.company,
                email: c.email,
                phone: c.phone,
                address: c.address,
                favorite: !c.favorite,
                lastContact: c.lastContact
            )
        }
        do {
            _ = try await EusoTripAPI.shared.contacts.toggleFavorite(id: contact.id)
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
        }
    }
}

// MARK: - AppointmentsStore — `appointments.getSummary` + `getMyAppointments`
//
// Drives brick 101 Me · Appointments. Composite store: summary
// counters + driver-scoped appointment list for the selected
// window (upcoming / today / past). Each lifecycle mutation
// (check-in, start-loading, complete, cancel) refreshes the feed
// in-place so the row's status chip flips without a manual pull.
//
// 93rd firing.

@MainActor
final class AppointmentsStore: ObservableObject, DynamicStore {
    @Published private(set) var summary: AppointmentsAPI.Summary?
    @Published private(set) var appointments: [AppointmentsAPI.Appointment] = []

    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error?
    @Published private(set) var mutatingId: String?

    @Published var window: AppointmentsAPI.Window = .upcoming

    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        async let summaryTask: AppointmentsAPI.Summary? = try? EusoTripAPI.shared.appointments.getSummary()
        async let listTask: [AppointmentsAPI.Appointment] = (try? EusoTripAPI.shared.appointments.getMyAppointments(window: window)) ?? []
        let (s, l) = await (summaryTask, listTask)
        summary = s
        appointments = l
        if s == nil && appointments.isEmpty {
            lastError = NSError(
                domain: "AppointmentsStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Can't reach appointments service"]
            )
        }
    }

    func checkIn(_ appt: AppointmentsAPI.Appointment, trailerNumber: String? = nil) async {
        mutatingId = appt.id
        defer { mutatingId = nil }
        do {
            _ = try await EusoTripAPI.shared.appointments.checkIn(
                appointmentId: appt.id,
                trailerNumber: trailerNumber
            )
            await refresh()
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
        }
    }

    func startLoading(_ appt: AppointmentsAPI.Appointment) async {
        mutatingId = appt.id
        defer { mutatingId = nil }
        do {
            _ = try await EusoTripAPI.shared.appointments.startLoading(appointmentId: appt.id)
            await refresh()
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
        }
    }

    func complete(_ appt: AppointmentsAPI.Appointment) async {
        mutatingId = appt.id
        defer { mutatingId = nil }
        do {
            _ = try await EusoTripAPI.shared.appointments.complete(appointmentId: appt.id)
            await refresh()
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
        }
    }

    func cancel(_ appt: AppointmentsAPI.Appointment, reason: String) async {
        mutatingId = appt.id
        defer { mutatingId = nil }
        do {
            _ = try await EusoTripAPI.shared.appointments.cancel(id: appt.id, reason: reason)
            await refresh()
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
        }
    }
}

// MARK: - FreightClaimsStore — `freightClaims.getClaimsDashboard` + `getClaims`
//
// Drives brick 099 Me · Freight Claims. Parallel dashboard +
// claims list. File mutation refreshes both so the new claim
// bumps the `open` counter + appears at the top of the list
// without a manual pull-to-refresh.
//
// 92nd firing.

@MainActor
final class FreightClaimsStore: ObservableObject, DynamicStore {
    @Published private(set) var dashboard: FreightClaimsAPI.Dashboard?
    @Published private(set) var claims: [FreightClaimsAPI.Claim] = []

    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error?
    @Published private(set) var isFiling: Bool = false

    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        async let dashTask: FreightClaimsAPI.Dashboard? = try? EusoTripAPI.shared.freightClaims.getDashboard()
        async let claimsTask: FreightClaimsAPI.ClaimsResponse? = try? EusoTripAPI.shared.freightClaims.getClaims(limit: 20)
        let (d, c) = await (dashTask, claimsTask)
        dashboard = d
        claims = c?.claims ?? []
        if d == nil && claims.isEmpty {
            lastError = NSError(
                domain: "FreightClaimsStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Can't reach claims service"]
            )
        }
    }

    @discardableResult
    func fileClaim(
        loadId: String,
        type: FreightClaimsAPI.ClaimType,
        amount: Double,
        description: String,
        commodity: String?,
        damageExtent: String?
    ) async throws -> FreightClaimsAPI.FileClaimResult {
        isFiling = true
        defer { isFiling = false }
        let result = try await EusoTripAPI.shared.freightClaims.fileClaim(
            loadId: loadId,
            type: type,
            amount: amount,
            description: description,
            commodity: commodity,
            damageExtent: damageExtent
        )
        await refresh()
        return result
    }
}

// MARK: - EmergencyOpsStore — `emergencyResponse.getMyMobilizations`
//
// Drives brick 098 Me · Emergency Ops. Single fetch; respond +
// updateStatus mutations refresh the feed so state flips land in-
// place. No client-side caching beyond the last server response —
// emergency ops move fast and the driver should always see the
// most recent snapshot the server has.
//
// 91st firing.

@MainActor
final class EmergencyOpsStore: ObservableObject, DynamicStore {
    @Published private(set) var feed: EmergencyAPI.MyMobilizations?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error?
    @Published private(set) var mutatingId: String?

    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            feed = try await EusoTripAPI.shared.emergency.getMyMobilizations()
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
        }
    }

    func respond(
        to order: EmergencyAPI.MobilizationOrder,
        accept: Bool,
        currentState: String? = nil,
        etaMinutes: Int? = nil
    ) async {
        mutatingId = order.id
        defer { mutatingId = nil }
        do {
            _ = try await EusoTripAPI.shared.emergency.respondToMobilization(
                orderId: order.id,
                accept: accept,
                currentState: currentState,
                estimatedArrivalMinutes: etaMinutes
            )
            await refresh()
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
        }
    }

    func updateStatus(
        response: EmergencyAPI.MobilizationResponse,
        status: String,
        loadsCompleted: Int? = nil,
        milesHauled: Double? = nil
    ) async {
        mutatingId = response.id
        defer { mutatingId = nil }
        do {
            _ = try await EusoTripAPI.shared.emergency.updateStatus(
                responseId: response.id,
                status: status,
                loadsCompleted: loadsCompleted,
                milesHauled: milesHauled
            )
            await refresh()
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
        }
    }
}

// MARK: - RatingsStore — `ratings.getMySummary` + `getReviews`
//
// Drives brick 097 Me · Ratings. Composite store: the driver's own
// summary (overall score + review count per role) + paginated
// reviews for the signed-in user id. Respond mutation refreshes
// the reviews feed so the reply shows up in-place.
//
// 90th firing.

@MainActor
final class RatingsStore: ObservableObject, DynamicStore {
    @Published var userId: String = ""

    @Published private(set) var summary: RatingsAPI.MySummary?
    @Published private(set) var reviews: [RatingsAPI.Review] = []

    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error?
    @Published private(set) var respondingId: String?

    @Published var sort: RatingsAPI.Sort = .recent

    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        async let summaryTask: RatingsAPI.MySummary? = try? EusoTripAPI.shared.ratings.getMySummary()
        let reviewsTask: RatingsAPI.ReviewsResponse?
        if !userId.isEmpty {
            reviewsTask = try? await EusoTripAPI.shared.ratings.getReviews(
                entityType: "user",
                entityId: userId,
                sort: sort,
                limit: 20
            )
        } else {
            reviewsTask = nil
        }
        let s = await summaryTask
        summary = s
        reviews = reviewsTask?.reviews ?? []
        if s == nil && reviews.isEmpty {
            lastError = NSError(
                domain: "RatingsStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Can't reach ratings service"]
            )
        }
    }

    func respond(to review: RatingsAPI.Review, text: String) async {
        respondingId = review.id
        defer { respondingId = nil }
        do {
            _ = try await EusoTripAPI.shared.ratings.respond(
                reviewId: review.id,
                response: text
            )
            await refresh()
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
        }
    }

    func report(review: RatingsAPI.Review, reason: String, details: String?) async {
        do {
            _ = try await EusoTripAPI.shared.ratings.report(
                reviewId: review.id,
                reason: reason,
                details: details
            )
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
        }
    }
}

// MARK: - ErgStore — ERG search + full material detail + contacts
//
// Drives brick 096 Me · ERG. Holds the latest search results, the
// currently-selected UN detail, and the emergency contact strip
// pulled once on first appear (contacts are static server-side).
// Search debounces at 300ms so three-letter typeaheads don't
// stampede the server.
//
// 89th firing.

@MainActor
final class ErgStore: ObservableObject, DynamicStore {
    @Published var query: String = ""

    @Published private(set) var results: [ErgAPI.SearchHit] = []
    @Published private(set) var detail: ErgAPI.MaterialDetail?
    @Published private(set) var contacts: ErgAPI.EmergencyContactsResponse?

    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error?

    private var searchTask: Task<Void, Never>?

    /// Initial fetch — contacts only. Drivers see the contact strip
    /// at a glance before they type anything.
    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        if contacts == nil {
            contacts = try? await EusoTripAPI.shared.erg.getEmergencyContacts()
        }
    }

    /// Debounced search. Called every time `query` changes.
    func scheduleSearch() {
        searchTask?.cancel()
        let q = query
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.runSearch(q)
        }
    }

    private func runSearch(_ q: String) async {
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            return
        }
        do {
            let resp = try await EusoTripAPI.shared.erg.search(query: trimmed, limit: 12)
            results = resp.results
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
        }
    }

    /// Load full detail for a UN number — typically invoked from a
    /// tap on a search result.
    func loadDetail(unNumber: String) async {
        do {
            detail = try await EusoTripAPI.shared.erg.searchByUN(unNumber)
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
        }
    }

    func clearDetail() { detail = nil }
}

// MARK: - RateIntelStore — `rates.getTrends`
//
// Drives brick 095 Me · Rate Intel. Pulls the rate-trend forecast
// over a driver-selected window + equipment filter. Single query;
// changing equipment / period re-runs the fetch.
//
// 88th firing.

@MainActor
final class RateIntelStore: ObservableObject, DynamicStore {
    @Published private(set) var trends: RatesAPI.Trends?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error?

    @Published var equipment: RatesAPI.Equipment = .any
    @Published var period: RatesAPI.Period = .month

    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            let equipmentArg: String? = equipment == .any ? nil : equipment.rawValue
            trends = try await EusoTripAPI.shared.rates.getTrends(
                equipment: equipmentArg,
                period: period
            )
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
        }
    }
}

// MARK: - FuelCardsStore — fuel dashboard + fuel cards
//
// Drives brick 094 Me · Fuel Cards. Composite store pulling the
// company-wide fuel dashboard + fuel-card list in parallel. Card
// list is narrowed client-side to the signed-in driver because
// `getFuelCardManagement` is a company-scoped admin proc.
//
// 87th firing.

@MainActor
final class FuelCardsStore: ObservableObject, DynamicStore {
    @Published var driverId: String = ""

    @Published private(set) var dashboard: FuelManagementAPI.Dashboard?
    @Published private(set) var myCards: [FuelManagementAPI.FuelCard] = []
    @Published private(set) var summary: FuelManagementAPI.FuelCardSummary?

    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error?

    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        async let dashTask: FuelManagementAPI.Dashboard? = try? EusoTripAPI.shared.fuelMgmt.getDashboard()
        async let cardsTask: FuelManagementAPI.FuelCardsResponse? = try? EusoTripAPI.shared.fuelMgmt.getFuelCards()
        let (d, c) = await (dashTask, cardsTask)
        dashboard = d
        summary = c?.summary
        if let selfId = Int(driverId), !driverId.isEmpty, let all = c?.cards {
            myCards = all.filter { $0.driverId == selfId }
        } else {
            myCards = c?.cards ?? []
        }
        if d == nil && myCards.isEmpty {
            lastError = NSError(
                domain: "FuelCardsStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Can't reach fuel service"]
            )
        }
    }
}

// MARK: - DQFileStore — DQ overview + documents + expiring items
//
// Drives brick 093 Me · DQ File. The server's procs require an
// explicit driverId (they're designed for admin tooling as well),
// so the store reads the signed-in user id from EusoTripSession
// before kicking off the parallel fetches.
//
// 86th firing.

@MainActor
final class DQFileStore: ObservableObject, DynamicStore {
    @Published var driverId: String = ""

    @Published private(set) var overview: DriverQualificationAPI.Overview?
    @Published private(set) var documents: [DriverQualificationAPI.DQDocument] = []
    @Published private(set) var expiring: [DriverQualificationAPI.ExpiringItem] = []

    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error?

    func refresh() async {
        guard !driverId.isEmpty else {
            lastError = NSError(
                domain: "DQFileStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Sign in to load your DQ file"]
            )
            return
        }
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        async let overviewTask: DriverQualificationAPI.Overview? = try? EusoTripAPI.shared.dq.getOverview(driverId: driverId)
        async let docsTask: DriverQualificationAPI.DocumentsResponse? = try? EusoTripAPI.shared.dq.getDocuments(driverId: driverId)
        async let expTask: [DriverQualificationAPI.ExpiringItem] = (try? EusoTripAPI.shared.dq.getExpiringItems(daysAhead: 60)) ?? []
        let (o, d, e) = await (overviewTask, docsTask, expTask)
        overview = o
        documents = d?.documents ?? []
        // Server's getExpiringItems is company-scoped — narrow to
        // this driver's own entries so the "your expiring items"
        // count doesn't include fleetmates.
        if let selfId = Int(driverId) {
            expiring = e.filter { $0.driverId == selfId }
        } else {
            expiring = e
        }
        if o == nil && documents.isEmpty && expiring.isEmpty {
            lastError = NSError(
                domain: "DQFileStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Can't reach DQ service"]
            )
        }
    }
}

// MARK: - PermitsStore — permits summary + active + expiring
//
// Drives brick 092 Me · Permits. Composite store pulling summary
// + active + expiring in parallel. Renew mutation refreshes all
// three feeds so expiring → active transitions land visibly.
//
// 85th firing.

@MainActor
final class PermitsStore: ObservableObject, DynamicStore {
    @Published private(set) var summary: PermitsAPI.Summary?
    @Published private(set) var active: [PermitsAPI.Permit] = []
    @Published private(set) var expiring: [PermitsAPI.ExpiringPermit] = []

    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error?
    @Published private(set) var renewingId: String?

    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        async let summaryTask: PermitsAPI.Summary? = try? EusoTripAPI.shared.permits.getSummary()
        async let activeTask: [PermitsAPI.Permit] = (try? EusoTripAPI.shared.permits.getActive()) ?? []
        async let expiringTask: [PermitsAPI.ExpiringPermit] = (try? EusoTripAPI.shared.permits.getExpiring(days: 45)) ?? []
        let (s, a, e) = await (summaryTask, activeTask, expiringTask)
        summary = s
        active = a
        expiring = e
        if s == nil && a.isEmpty && e.isEmpty {
            lastError = NSError(
                domain: "PermitsStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Can't reach permits service"]
            )
        }
    }

    func renew(
        permitId: String,
        toEndDate: String
    ) async {
        renewingId = permitId
        defer { renewingId = nil }
        do {
            _ = try await EusoTripAPI.shared.permits.renew(
                permitId: permitId,
                requestedEndDate: toEndDate
            )
            await refresh()
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
        }
    }
}

// MARK: - DetentionStore — detention dashboard + active + history
//
// Drives brick 091 Me · Detention. Composite store pulling dashboard
// counters + active detentions + recent history in parallel. Dispute
// mutation refreshes active + history feeds.
//
// 84th firing.

@MainActor
final class DetentionStore: ObservableObject, DynamicStore {
    @Published private(set) var dashboard: DetentionAPI.Dashboard?
    @Published private(set) var active: [DetentionAPI.ActiveDetention] = []
    @Published private(set) var history: [DetentionAPI.HistoryEvent] = []

    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error?
    @Published private(set) var disputingId: Int?

    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        async let dashTask: DetentionAPI.Dashboard? = try? EusoTripAPI.shared.detention.getDashboard()
        async let activeTask: DetentionAPI.ActiveDetentionsResponse? = try? EusoTripAPI.shared.detention.getActive(limit: 10)
        async let historyTask: DetentionAPI.HistoryResponse? = try? EusoTripAPI.shared.detention.getHistory(limit: 20)
        let (d, a, h) = await (dashTask, activeTask, historyTask)
        dashboard = d
        active = a?.detentions ?? []
        history = h?.events ?? []
        if d == nil && (a?.detentions.isEmpty ?? true) && (h?.events.isEmpty ?? true) {
            lastError = NSError(
                domain: "DetentionStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Can't reach detention service"]
            )
        }
    }

    func dispute(detention: DetentionAPI.HistoryEvent, reason: String) async {
        disputingId = detention.id
        defer { disputingId = nil }
        do {
            _ = try await EusoTripAPI.shared.detention.dispute(
                detentionId: detention.id,
                reason: reason
            )
            await refresh()
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
        }
    }
}

// MARK: - IftaStore — `iftaCalculator.estimateFromLoads`
//
// Drives brick 090 Me · IFTA Tax. Quick quarterly tax forecast from
// the driver's delivered loads. Single fetch; user can change year /
// quarter / mpg and re-estimate. Separate from the filing flow
// (`calculateQuarter`) which lives in the detail drilldown.
//
// 83rd firing.

@MainActor
final class IftaStore: ObservableObject, DynamicStore {
    @Published private(set) var estimate: IftaAPI.Estimate?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error?

    /// Driver-adjustable inputs.
    @Published var year: Int = Calendar.current.component(.year, from: Date())
    @Published var quarter: IftaAPI.Quarter = .current()
    @Published var fleetMpg: Double = 6.5

    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            estimate = try await EusoTripAPI.shared.ifta.estimateFromLoads(
                year: year,
                quarter: quarter,
                fleetMpg: fleetMpg
            )
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
        }
    }
}

// MARK: - SupportStore — `support.getSummary` + `support.getMyTickets`
//
// Drives brick 089 Me · Support & Tickets. Composite store pulling
// summary counters + paginated ticket list in parallel. Create
// flow appends optimistically + refreshes both feeds after the
// server confirms the write.
//
// 82nd firing.

@MainActor
final class SupportStore: ObservableObject, DynamicStore {
    @Published private(set) var summary: SupportAPI.Summary?
    @Published private(set) var tickets: [SupportAPI.Ticket] = []

    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error?
    @Published private(set) var isCreating: Bool = false

    /// Optional status filter for the ticket list. Nil = all statuses.
    @Published var statusFilter: String?

    func refresh() async {
        isLoading = true
        lastError = nil
        async let summaryTask: SupportAPI.Summary? = try? EusoTripAPI.shared.support.getSummary()
        async let ticketsTask: SupportAPI.MyTicketsResponse? = try? EusoTripAPI.shared.support.getMyTickets(
            status: statusFilter,
            limit: 20
        )
        let (s, t) = await (summaryTask, ticketsTask)
        summary = s
        tickets = t?.tickets ?? []
        isLoading = false
        if s == nil && (t == nil || t?.tickets.isEmpty == true) {
            lastError = NSError(
                domain: "SupportStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Can't reach support"]
            )
        }
    }

    /// Create a new ticket. Returns the server result so the caller
    /// can dismiss the compose sheet only after the write lands.
    @discardableResult
    func create(
        subject: String,
        message: String,
        category: String = "general",
        priority: String = "medium"
    ) async throws -> SupportAPI.CreateTicketResult {
        isCreating = true
        defer { isCreating = false }
        let result = try await EusoTripAPI.shared.support.createTicket(
            subject: subject,
            message: message,
            category: category,
            priority: priority
        )
        // Refresh so the new ticket shows up in the list and the
        // summary counters bump.
        await refresh()
        return result
    }
}

// MARK: - HaulStore — `gamification.getProfile` + `missions.listMine` + `achievements.listMine`
//
// Drives brick 089 Me · The Haul. Composite store pulling three
// feeds in parallel. Partial failures land partial data so an
// auth-rejected missions list doesn't blank the whole screen.
// Mission claim mutation refreshes only the missions feed.
//
// 81st firing.

@MainActor
final class HaulStore: ObservableObject, DynamicStore {
    @Published private(set) var profile: HaulAPI.Profile?
    @Published private(set) var missions: [HaulAPI.Mission] = []
    @Published private(set) var badges: [HaulAPI.Badge] = []

    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error?

    /// id of the mission currently mid-claim — used by the view
    /// to disable that row's button while the mutation is inflight.
    @Published private(set) var claimingId: Int?

    func refresh() async {
        isLoading = true
        lastError = nil
        async let profileTask: HaulAPI.Profile? = try? EusoTripAPI.shared.haul.getProfile()
        async let missionsTask: [HaulAPI.Mission] = (try? EusoTripAPI.shared.haul.listMyMissions(limit: 20)) ?? []
        async let badgesTask: [HaulAPI.Badge] = (try? EusoTripAPI.shared.haul.listMyBadges(onlyDisplayed: false, limit: 24)) ?? []
        let (p, m, b) = await (profileTask, missionsTask, badgesTask)
        profile = p
        missions = m
        badges = b
        isLoading = false
        if p == nil && m.isEmpty && b.isEmpty {
            lastError = NSError(
                domain: "HaulStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Can't reach The Haul service"]
            )
        }
    }

    /// Claim a completed mission + refresh only the missions feed.
    /// Server rejects claims on non-completed rows — failure is
    /// surfaced via `lastError` without dropping the profile or
    /// badges that are still on-screen.
    func claim(mission: HaulAPI.Mission) async {
        guard mission.status.lowercased() == "completed" else { return }
        claimingId = mission.progressId
        defer { claimingId = nil }
        do {
            _ = try await EusoTripAPI.shared.haul.claimMission(
                progressId: mission.progressId
            )
            if let refreshed = try? await EusoTripAPI.shared.haul.listMyMissions(limit: 20) {
                missions = refreshed
            }
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
        }
    }
}

// MARK: - SafetyCoachStore — `esangCoach.forDriver`
//
// Drives brick 087 Me · Safety Coach. Stores the most recently
// loaded ESANG coaching pack plus the driver's optional focus-text
// so the view can re-query on Enter without re-typing. Count
// inputs (recent incidents / violations / near-misses) are sent as
// nil by default so the server pulls live values from the user's
// compliance history — driver-supplied override is possible but not
// currently surfaced in 087.
//
// 79th firing.

@MainActor
final class SafetyCoachStore: BaseDynamicStore<EsangCoachAPI.ForDriverResponse> {
    /// Driver's free-text focus ("what's on my mind"). Sent to the
    /// server to colour the coaching items, cleared on manual reset.
    @Published var focus: String = ""

    /// Target item count per refresh. Server clamps to 3-10 so an
    /// out-of-range value is harmless, but we keep 6 as the default
    /// since it matches the densest usable Modular Ultra layout
    /// without requiring the user to scroll on first glance.
    @Published var limit: Int = 6

    override func fetch() async throws -> EsangCoachAPI.ForDriverResponse {
        try await EusoTripAPI.shared.esangCoach.forDriver(
            focus: focus,
            limit: limit
        )
    }

    override func foldState(
        _ value: EsangCoachAPI.ForDriverResponse
    ) -> RemoteState<EsangCoachAPI.ForDriverResponse> {
        // Server contract: we always get at least the deterministic
        // fallback items when Gemini is down, so a truly empty
        // response is a real API surface bug rather than a normal
        // state. Treat the edge as `.empty` so the view shows the
        // branded "No coaching available" rather than blank cards.
        value.items.isEmpty ? .empty : .loaded(value)
    }
}

// MARK: - SpectraMatchHistoryStore — `spectraMatch.getHistory`
//
// Drives lifecycle screens 030 (Loading in Progress) and 031
// (Spectra-Match Verdict). Replaces the hardcoded
// `private let samples: [SampleLane] = [...]` array that the
// 2026-04-24 ledger-hygiene audit flagged as the only material
// mock-data violation in the shipped 010–103 driver track.
//
// Returns the most-recent verified identifications across the
// caller's company / driver scope, in `loads.createdAt DESC` order.
// When the driver has no signed loads yet the store resolves to
// `.empty` and the screen renders an empty-state strip rather
// than fake sample lanes.
//
// MCP-verified at `frontend/server/routers/spectraMatch.ts:414`.

@MainActor
final class SpectraMatchHistoryStore: BaseDynamicListStore<SpectraMatchAPI.Identification> {
    /// Optional terminal-id scope. When unset, the server returns
    /// the caller's own driver-scoped history.
    var terminalId: String? = nil

    /// Maximum number of identifications to fetch. Defaults to 5
    /// because the lane strip in 031 renders 5 lanes (`THIS FILL`
    /// + 4 lanes of historical context).
    var limit: Int = 5

    override func fetch() async throws -> [SpectraMatchAPI.Identification] {
        try await EusoTripAPI.shared.spectraMatch
            .getHistory(terminalId: terminalId, limit: limit)
            .identifications
    }
}

// MARK: - ShipperDashboardStore — `shippers.getDashboardStats`
//
// Drives the KPI strip on the Shipper Home brick (200_ShipperHome).
// Returns the canonical 6-figure dashboard envelope: activeLoads,
// pendingBids, deliveredThisWeek, ratePerMile, onTimeRate,
// totalSpendThisMonth. MCP-verified at
// `frontend/server/routers/shippers.ts:77`.

@MainActor
final class ShipperDashboardStore: BaseDynamicStore<ShipperAPI.DashboardStats?> {
    override func fetch() async throws -> ShipperAPI.DashboardStats? {
        try await EusoTripAPI.shared.shipper.getDashboardStats()
    }

    override func foldState(
        _ value: ShipperAPI.DashboardStats?
    ) -> RemoteState<ShipperAPI.DashboardStats?> {
        // The dashboard is always populated (server returns zeros
        // when the shipper has no loads), so a nil value is
        // treated as a hard-error edge — never as `.empty`.
        guard let v = value else { return .empty }
        return .loaded(v)
    }
}

// MARK: - ShipperActiveLoadsStore — `shippers.getActiveLoads`
//
// Drives the "Active loads" card list on Shipper Home.
// MCP-verified at `frontend/server/routers/shippers.ts:109`.

@MainActor
final class ShipperActiveLoadsStore: BaseDynamicListStore<ShipperAPI.ActiveLoad> {
    var limit: Int = 10

    override func fetch() async throws -> [ShipperAPI.ActiveLoad] {
        try await EusoTripAPI.shared.shipper.getActiveLoads(limit: limit)
    }
}

// MARK: - ShipperAlertsStore — `shippers.getLoadsRequiringAttention`
//
// Drives the "Needs your attention" alert strip on Shipper Home.
// MCP-verified at `frontend/server/routers/shippers.ts:147`.

@MainActor
final class ShipperAlertsStore: BaseDynamicListStore<ShipperAPI.LoadAlert> {
    override func fetch() async throws -> [ShipperAPI.LoadAlert] {
        try await EusoTripAPI.shared.shipper.getLoadsRequiringAttention()
    }
}

// MARK: - ShipperRecentLoadsStore — `shippers.getRecentLoads`
//
// Drives the recent-activity feed below the active-loads card.
// MCP-verified at `frontend/server/routers/shippers.ts:191`.

@MainActor
final class ShipperRecentLoadsStore: BaseDynamicListStore<ShipperAPI.RecentLoad> {
    var limit: Int = 5

    override func fetch() async throws -> [ShipperAPI.RecentLoad] {
        try await EusoTripAPI.shared.shipper.getRecentLoads(limit: limit)
    }
}

// MARK: - ShipperMyLoadsStore — `shippers.getMyLoads`
//
// Drives the multi-select rows on 384 Bulk Re-tender, 412 Drafts,
// 413 Archived. MCP-verified at `frontend/server/routers/shippers.ts:282`.
// Optional `statusFilter` lets callers narrow to e.g. only posted/bidding
// (the bulk re-tender screen) without re-implementing the filter client-side.

@MainActor
final class ShipperMyLoadsStore: BaseDynamicListStore<ShipperAPI.MyLoad> {
    var statusFilter: String? = nil
    var limit: Int = 50
    var offset: Int = 0

    override func fetch() async throws -> [ShipperAPI.MyLoad] {
        try await EusoTripAPI.shared.shipper.getMyLoads(status: statusFilter, limit: limit, offset: offset)
    }
}

// MARK: - ShipperLoadsSummaryStore — `loads.getShipperSummary`
//
// Topline counts for 201 Shipper Loads filter chips + 200 Home stat
// strip. MCP-verified at `frontend/server/routers/loads.ts:769`.

@MainActor
final class ShipperLoadsSummaryStore: BaseDynamicStore<LoadsAPI.ShipperSummary?> {
    override func fetch() async throws -> LoadsAPI.ShipperSummary? {
        try await EusoTripAPI.shared.loads.getShipperSummary()
    }
}

// =====================================================================
// ShipperProfileStore + ShipperStatsStore — Shipper role profile
// (brick 202_ShipperProfile).
// ---------------------------------------------------------------------
// Added 2026-04-26 in the 117th eusotrip-killers firing as the next
// brick on the Shipper track per the 2027 motivation: "all 24 users
// piece by piece every screen each role at a time til you are done."
//
// Both stores read only from `EusoTripAPI.shared.shipper.*` — no
// fixtures, no fallback fixtures, no `if PREVIEW` short-circuits.
// Cohort B day-1 (SKILL.md §3 "no-mock" pledge): if the backend
// returns an empty envelope, the screen surfaces em-dash sentinels
// instead of fabricating company / contact / spend values.
//
// MCP-verified backend paths:
//   • `shippers.getProfile`  — frontend/server/routers/shippers.ts:583
//   • `shippers.getStats`    — frontend/server/routers/shippers.ts:605
//
// Profile envelope is treated as always-populated (server returns
// empty strings when the underlying `companies` row is missing) — a
// nil from the network layer is the hard-error edge, not `.empty`.
// Stats envelope is similar: server returns 0s + an empty
// `monthlyVolume` array when the shipper has no loads yet, so a nil
// is treated as the hard-error edge.
// =====================================================================

@MainActor
final class ShipperProfileStore: BaseDynamicStore<ShipperAPI.Profile?> {
    override func fetch() async throws -> ShipperAPI.Profile? {
        try await EusoTripAPI.shared.shipper.getProfile()
    }

    override func foldState(
        _ value: ShipperAPI.Profile?
    ) -> RemoteState<ShipperAPI.Profile?> {
        guard let v = value else { return .empty }
        // The server populates a sentinel envelope (empty strings,
        // verified=false, memberSince="") when the companies row
        // hasn't been hydrated. The store still treats that as
        // `.loaded` — the screen renders em-dashes for blank fields
        // rather than re-fetching forever. Doctrine: 0% mock data.
        return .loaded(v)
    }
}

@MainActor
final class ShipperStatsStore: BaseDynamicStore<ShipperAPI.Stats?> {
    override func fetch() async throws -> ShipperAPI.Stats? {
        try await EusoTripAPI.shared.shipper.getStats()
    }

    override func foldState(
        _ value: ShipperAPI.Stats?
    ) -> RemoteState<ShipperAPI.Stats?> {
        guard let v = value else { return .empty }
        // Same posture as the Profile store: a sentinel envelope of
        // zeros + empty monthlyVolume is still `.loaded`. The screen
        // surfaces "—" tiles for the zero-spend / zero-on-time-rate
        // edge so we never claim performance the shipper doesn't have.
        return .loaded(v)
    }
}

// =====================================================================
// ShipperBidsStore — Shipper role bids inbox (brick 203_ShipperBids).
// ---------------------------------------------------------------------
// Added 2026-04-26 in the 119th eusotrip-killers firing as the next
// brick on the Shipper track per the 2027 motivation: "all 24 users
// piece by piece every screen each role at a time til you are done."
//
// Backed by `shippers.getBidsForLoad` (frontend/server/routers/
// shippers.ts:358). The procedure is per-load: it takes a `loadId`
// and returns every bid on that single load. The screen drives the
// store via `setLoadId(_:)` whenever the load chip strip selection
// changes — `refresh()` then fans out to the right tRPC path. A
// `nil` selectedLoadId yields an empty list without hitting the
// network (so the screen renders the canonical "pick a load to view
// bids" empty state instead of a synthesised error).
//
// Cohort B day-1: no fixtures, no fallbacks, no `if PREVIEW` short
// circuits. If the load has no bids the store settles on `.empty`
// (BaseDynamicListStore default fold). If the call errors, the
// store settles on `.error(error)` and the screen surfaces a real
// inline retry — never fake-data.
// =====================================================================

@MainActor
final class ShipperBidsStore: BaseDynamicListStore<ShipperAPI.Bid> {
    /// Selected load ID. The screen rebinds this whenever the user
    /// taps a different chip in the load picker. We don't auto-fetch
    /// on bind — the screen calls `refresh()` after the rebind so
    /// the loading transition is explicit.
    private(set) var selectedLoadId: String? = nil

    func setLoadId(_ loadId: String?) {
        // Clear any cached rows when the selection moves so the next
        // render doesn't briefly show the previous load's bids.
        if loadId != selectedLoadId {
            self.selectedLoadId = loadId
            self.state = .loading
        }
    }

    override func fetch() async throws -> [ShipperAPI.Bid] {
        guard let loadId = selectedLoadId, !loadId.isEmpty else {
            // No load picked — return an empty slice. The
            // BaseDynamicListStore fold collapses this to `.empty`,
            // which the screen renders as "Pick a load to see bids."
            return []
        }
        return try await EusoTripAPI.shared.shipper
            .getBidsForLoad(loadId: loadId)
    }
}

// =====================================================================
// ShipperPostLoadStore — Shipper · Post Load (brick 204_ShipperPostLoad).
// ---------------------------------------------------------------------
// Added 2026-04-26 in the 121st eusotrip-killers firing as the next
// Shipper-track brick per the 2027 motivation: "all 24 users piece by
// piece every screen each role at a time til you are done."
//
// Mutation-driven store. Unlike the fetch stores (which inherit from
// `BaseDynamicStore` / `BaseDynamicListStore`), the post-load surface
// has no idle data — it's a form whose state machine is:
//   .idle → .submitting → .success(ack) | .error(error)
//
// The screen drives the store via `submit(input:)`. On success, the
// store flips to `.success(ack)` and the screen surfaces a transient
// success banner with the server-emitted `loadNumber`. On error, the
// store flips to `.error(error)` and the screen renders an inline
// readable banner with a Retry CTA (which dispatches `submit` again
// with the captured input). After either terminal state the screen
// can call `reset()` to flip back to `.idle` so the form can post
// another load without remounting.
//
// Cohort B day-1: zero fixtures. The store NEVER synthesises a fake
// `PostLoadAck`. Even in `.idle` the form is empty; the user has to
// type real values. Per the 2027 motivation: "no mock, no stubs, no
// fake data."
// =====================================================================

@MainActor
final class ShipperPostLoadStore: ObservableObject {
    /// State machine for the post-load mutation. Mirrors the
    /// canonical `RemoteState` shape used elsewhere in the file but
    /// stays local because the post-load surface doesn't fit the
    /// fetch contract (`refresh()` would have nothing to fetch).
    enum Phase: Equatable {
        case idle
        case submitting
        case success(ShipperAPI.PostLoadAck)
        case error(String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): return true
            case (.submitting, .submitting): return true
            case (.success(let a), .success(let b)):
                return a == b
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    @Published private(set) var phase: Phase = .idle

    /// Submit a freshly-typed load to `shippers.create`. The screen
    /// validates required fields (origin / destination non-empty)
    /// before invoking — the store still re-validates so a buggy
    /// caller can't slip past the wire constraint.
    func submit(
        origin: String,
        destination: String,
        cargoType: ShipperAPI.CargoType,
        rate: Double?,
        weight: Double?,
        notes: String?,
        pickupDate: String?,
        originLat: Double? = nil,
        originLng: Double? = nil,
        destLat: Double? = nil,
        destLng: Double? = nil
    ) async {
        let trimOrigin = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimDest   = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimOrigin.isEmpty, !trimDest.isEmpty else {
            self.phase = .error("Origin and destination are both required.")
            return
        }
        self.phase = .submitting
        do {
            let ack = try await EusoTripAPI.shared.shipper.create(
                origin: trimOrigin,
                destination: trimDest,
                cargoType: cargoType,
                rate: rate,
                weight: weight,
                notes: (notes?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
                    $0.isEmpty ? nil : $0
                },
                pickupDate: (pickupDate?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
                    $0.isEmpty ? nil : $0
                },
                originLat: originLat,
                originLng: originLng,
                destLat: destLat,
                destLng: destLng
            )
            self.phase = .success(ack)
        } catch let api as EusoTripAPIError {
            self.phase = .error(api.errorDescription ?? "Couldn't post that load.")
        } catch {
            self.phase = .error(error.localizedDescription)
        }
    }

    /// Reset to idle so the form can be filled and posted again
    /// without the screen remounting. Called by the screen after
    /// the success banner is dismissed and the form is cleared.
    func reset() {
        self.phase = .idle
    }
}

// =====================================================================
// ShipperLoadDetailStore — Shipper · 205 surface (brick 205_ShipperLoadDetail).
// ---------------------------------------------------------------------
// Added 2026-04-26 in the 122nd eusotrip-killers firing
// (HYGIENE_PLUS_BRICK_PORT_205) as the natural follow-on to 121st's 204
// ShipperPostLoad. The 121st report explicitly recommended this surface
// as Branch B for the 122nd: "Today the 201 row tap surfaces an
// EusoEmptyState placeholder — the detail screen would drive
// loads.getById and render the canonical load summary (route, status,
// bids count, catalyst handoff if assigned, BOL/POD doc thumbnails when
// present)."
//
// Backend wiring (verified MCP-live at firing open):
//   • detail   → `loads.getById` (input `{ id: string }`,
//                frontend/server/routers/loads.ts:1046).
//                Returns the full server projection with `id` as
//                String, `distance` as Double (haversine fallback when
//                DB column is empty), and DECIMAL columns as strings.
//   • bids     → `shippers.getBidsForLoad` (input `{ loadId: string }`,
//                frontend/server/routers/shippers.ts:358). Existing
//                ShipperBidsStore handles this surface; 205 reuses it
//                so the bid list is in lockstep with 203's bids screen
//                — no parallel cache, no drift.
//
// Cohort B day-1: every field surfaces verbatim from the server. When
// the load row is partially filled (a freshly-posted draft has weight,
// rate, dates all null) the screen renders em-dash neutral states for
// the missing slots — never fabricated values. Per the 2027 motivation:
// "no mock, no stubs, no fake data, 1000% dynamic."
// =====================================================================

@MainActor
final class ShipperLoadDetailStore: BaseDynamicStore<LoadsAPI.LoadDetail?> {
    /// The load id passed in by the caller (typically the row that was
    /// tapped on 201_ShipperLoads). String form because the server
    /// expects `z.string()` and the row's id is already a String.
    var loadId: String = ""

    override func fetch() async throws -> LoadsAPI.LoadDetail? {
        guard !loadId.isEmpty else { return nil }
        return try await EusoTripAPI.shared.loads.getDetail(id: loadId)
    }

    override func foldState(
        _ value: LoadsAPI.LoadDetail?
    ) -> RemoteState<LoadsAPI.LoadDetail?> {
        // `loads.getById` returns null only when the row has been
        // hard-deleted. Surface as `.empty` so the UI renders an
        // EusoEmptyState rather than treating it as a transport
        // failure. Found rows always have at least `id`/`loadNumber`/
        // `status` populated.
        guard let v = value else { return .empty }
        return .loaded(v)
    }
}

// =====================================================================
// ShipperLifecycleSnapshotStore — Round 4 / Arc E · feeds 260–279.
// ---------------------------------------------------------------------
// Composite store wrapping `shippers.getLifecycleSnapshot(loadId)`. Every
// shipper lifecycle screen consumes this store directly so the 20
// bricks share a single snapshot — no parallel caches, no drift.
//
// `loadId` is a `String` matching the server's Zod input. Caller sets
// it before `refresh()`; the store throws on empty.
// =====================================================================

@MainActor
final class ShipperLifecycleSnapshotStore: BaseDynamicStore<ShipperAPI.LifecycleSnapshot?> {
    var loadId: String = ""

    override func fetch() async throws -> ShipperAPI.LifecycleSnapshot? {
        guard !loadId.isEmpty else { return nil }
        return try await EusoTripAPI.shared.shipper.getLifecycleSnapshot(loadId: loadId)
    }

    override func foldState(
        _ value: ShipperAPI.LifecycleSnapshot?
    ) -> RemoteState<ShipperAPI.LifecycleSnapshot?> {
        guard let v = value else { return .empty }
        return .loaded(v)
    }
}

@MainActor
final class ShipperSettlementForLoadStore: BaseDynamicStore<ShipperAPI.SettlementForLoad?> {
    var loadId: String = ""

    override func fetch() async throws -> ShipperAPI.SettlementForLoad? {
        guard !loadId.isEmpty else { return nil }
        return try await EusoTripAPI.shared.shipper.getSettlementForLoad(loadId: loadId)
    }

    override func foldState(
        _ value: ShipperAPI.SettlementForLoad?
    ) -> RemoteState<ShipperAPI.SettlementForLoad?> {
        // nil = settlement not yet constructed; surface as `.empty`
        // so the screen renders the "not yet payable" affordance,
        // not an error tile.
        guard let v = value else { return .empty }
        return .loaded(v)
    }
}

// =====================================================================
// ShipperDeliveryConfirmationsStore — Shipper · 206 surface
// (brick 206_ShipperSettlements).
// ---------------------------------------------------------------------
// Added 2026-04-26 in the 124th eusotrip-killers firing
// (HYGIENE_PLUS_BRICK_PORT_206) per the 123rd firing's recommendation
// for Branch B: "Code port 206_ShipperSettlements driving
// shippers.getDeliveryConfirmations + a settlements summary card."
// MCP-verified at firing open: `frontend/server/routers/shippers.ts:534`
// returns `Array<{loadId, loadNumber, origin, destination, deliveredAt,
// status, rate}>` from `loads` rows where `shipperId == ctx.user.id`
// AND `status == 'delivered'`, ordered by `actualDeliveryDate DESC`.
//
// Cohort B day-1 — every row on the Settlements feed is a real
// delivered load. Aggregate KPI tiles (total billed, count, average
// rate, last settlement date) are computed client-side from the same
// verified array — never a separate query — so the screen can never
// drift between an aggregate and its row list. Empty array yields
// `.empty` and the screen renders an `EusoEmptyState`. Errors
// surface as a real inline retry, never fake-data.
// =====================================================================

@MainActor
final class ShipperDeliveryConfirmationsStore: BaseDynamicListStore<ShipperAPI.DeliveryConfirmation> {
    /// Optional server-side filter. The screen lets the shipper pick
    /// "All" (nil) / "Confirmed" / "Pending" / "Disputed" via a chip
    /// strip. `nil` is the default (the canonical "all settled
    /// loads" surface).
    private(set) var statusFilter: ShipperAPI.DeliveryConfirmationStatus? = nil

    /// Server-side limit. The screen offers a "Show more" button that
    /// bumps this in 20-row increments and re-fetches. Default 20
    /// matches the backend's Zod default at line 537.
    var limit: Int = 20

    func setStatusFilter(_ status: ShipperAPI.DeliveryConfirmationStatus?) {
        if status != statusFilter {
            self.statusFilter = status
            self.state = .loading
        }
    }

    override func fetch() async throws -> [ShipperAPI.DeliveryConfirmation] {
        try await EusoTripAPI.shared.shipper
            .getDeliveryConfirmations(status: statusFilter, limit: limit)
    }
}

// =====================================================================
// ShipperSpendingAnalyticsStore + ShipperCatalystPerformanceStore
// — Shipper · 207 surface (brick 207_ShipperReports).
// ---------------------------------------------------------------------
// Added 2026-04-26 in the 126th eusotrip-killers firing per the 124th
// firing's hand-off recommendation: "207_ShipperReports". Two parallel
// stores — one envelope, one list — each holding a private copy of the
// shared `SpendingPeriod`. The screen owns the canonical period and
// propagates to both stores via `setPeriod` whenever the chip changes,
// so the KPI tiles and the catalyst leaderboard always describe the
// same time window. MCP-verified at firing open:
//   • shippers.getSpendingAnalytics      `shippers.ts:470` → object
//   • shippers.getCatalystPerformance    `shippers.ts:433` → array
//
// Cohort B day-1 — every figure on the Reports screen surfaces from
// these two real backend procedures. Empty windows yield `.empty`
// (the EusoEmptyState placeholder), errors yield `.failed` with a
// readable retry. There is no fixture, no fallback, no fabrication.
// =====================================================================

@MainActor
final class ShipperSpendingAnalyticsStore: BaseDynamicStore<ShipperAPI.SpendingAnalytics?> {
    /// Active period token. Default `.month` matches the backend's
    /// Zod default at `shippers.ts:472`. `setPeriod` flips state to
    /// `.loading` so the UI immediately renders the loading skeleton
    /// while the new fetch is in flight.
    private(set) var period: ShipperAPI.SpendingPeriod = .month

    func setPeriod(_ p: ShipperAPI.SpendingPeriod) {
        if p != period {
            period = p
            state = .loading
        }
    }

    override func fetch() async throws -> ShipperAPI.SpendingAnalytics? {
        try await EusoTripAPI.shared.shipper.getSpendingAnalytics(period: period)
    }

    override func foldState(
        _ value: ShipperAPI.SpendingAnalytics?
    ) -> RemoteState<ShipperAPI.SpendingAnalytics?> {
        // Backend always returns an envelope (zeros if the shipper
        // has no loads in window). An all-zero envelope folds to
        // `.empty` for the UI rather than `.loaded` of zeros so the
        // empty-state placeholder paints instead of a confusing
        // "$0 over 0 loads" tile strip.
        guard let v = value else { return .empty }
        if v.loadCount == 0 && v.totalSpend == 0 { return .empty }
        return .loaded(v)
    }
}

@MainActor
final class ShipperCatalystPerformanceStore: BaseDynamicListStore<ShipperAPI.CatalystPerformance> {
    /// Active period token. Default `.month` keeps the leaderboard's
    /// time window in lockstep with the spend tiles above (the screen
    /// unifies the two stores' periods even though the backend
    /// defaults this endpoint to `.quarter`).
    private(set) var period: ShipperAPI.SpendingPeriod = .month

    func setPeriod(_ p: ShipperAPI.SpendingPeriod) {
        if p != period {
            period = p
            state = .loading
        }
    }

    override func fetch() async throws -> [ShipperAPI.CatalystPerformance] {
        try await EusoTripAPI.shared.shipper.getCatalystPerformance(period: period)
    }
}

// MARK: - ShipperFavoriteCatalystsStore — `shippers.getFavoriteCatalysts`
//
// Drives brick 209_ShipperContacts. Returns the shipper's working-
// carriers directory: the catalyst companies they've delivered loads
// with, ranked DESC by load count, top 10. Server-side derived view
// — there is no junction table, so adds happen by completing loads,
// not by clicking a "favorite" button. The store still exposes
// `acknowledgeFavorite` for the UI's optimistic favorite-tap flow.
//
// Server returns an empty array when the shipper has zero delivered
// loads — view surfaces EusoEmptyState. No mock fallback.
//
// 127th firing — added alongside brick 209.

@MainActor
final class ShipperFavoriteCatalystsStore: BaseDynamicListStore<ShipperAPI.FavoriteCatalyst> {
    /// True while a favorite-tap mutation is in flight against a row,
    /// so the view can show a row-level spinner without disabling
    /// the entire list.
    @Published var acknowledgingId: String?

    override func fetch() async throws -> [ShipperAPI.FavoriteCatalyst] {
        try await EusoTripAPI.shared.shipper.getFavoriteCatalysts()
    }

    /// Fire-and-forget acknowledgment. Server is idempotent + derives
    /// the favorites list from delivered loads, so we don't refresh
    /// after a successful ack — the row stays where it was. On
    /// transport failure we fall back to a `refresh()` to make sure
    /// we're not displaying stale local state.
    func acknowledgeFavorite(catalystId: String) async {
        acknowledgingId = catalystId
        defer { acknowledgingId = nil }
        do {
            _ = try await EusoTripAPI.shared.shipper.addFavoriteCatalyst(catalystId: catalystId)
        } catch {
            await refresh()
        }
    }
}

// =====================================================================
// CarrierHomeDashboardStore / CarrierActiveLoadsStore /
// CarrierAlertsStore / CarrierRecentLoadsStore — Carrier role home
// (brick 300_CarrierHome).
// ---------------------------------------------------------------------
// Added 2026-04-25 in the 100th eusotrip-killers firing as the role
// switch from Shipper to Carrier per the 2027 motivation. NAME
// DISAMBIGUATION: there is already a `CarrierScorecardStore` ~line
// 1605 — that one is a Driver-Me brick 085 store backed by
// `csaScores.getOverview` and is unrelated to this role's home.
// These stores intentionally use the prefix `CarrierHome*` /
// `CarrierActiveLoads*` / `CarrierAlerts*` / `CarrierRecentLoads*`
// to avoid collision.
//
// Every store reads only from `EusoTripAPI.shared.carrier.*` — no
// fixtures, no in-memory samples. If the backend has not exposed
// `carriers.*` yet, the stores resolve to `RemoteState.empty` (no
// data) or `.failed` (transport error) and the view surfaces an
// `EusoEmptyState`. This satisfies doctrine §11 + `MockDataGuard`.
// =====================================================================

// MARK: - CarrierHomeDashboardStore — `carriers.getDashboardStats`
//
// Drives the KPI strip on the Carrier Home brick (300_CarrierHome).
// Returns the canonical 6-figure dashboard envelope: activeLoads,
// openOffers, deliveredThisWeek, ratePerMile, onTimeRate,
// weeklyRevenue.

@MainActor
final class CarrierHomeDashboardStore: BaseDynamicStore<CarrierAPI.DashboardStats?> {
    override func fetch() async throws -> CarrierAPI.DashboardStats? {
        try await EusoTripAPI.shared.carrier.getDashboardStats()
    }

    override func foldState(
        _ value: CarrierAPI.DashboardStats?
    ) -> RemoteState<CarrierAPI.DashboardStats?> {
        // The dashboard is always populated server-side (zeros
        // when the carrier has no loads), so `nil` is treated as
        // a hard edge — never as `.empty` data.
        guard let v = value else { return .empty }
        return .loaded(v)
    }
}

// MARK: - CarrierActiveLoadsStore — `carriers.getActiveLoads`
//
// Drives the "Active loads" card list on Carrier Home.

@MainActor
final class CarrierActiveLoadsStore: BaseDynamicListStore<CarrierAPI.ActiveLoad> {
    var limit: Int = 10

    override func fetch() async throws -> [CarrierAPI.ActiveLoad] {
        try await EusoTripAPI.shared.carrier.getActiveLoads(limit: limit)
    }
}

// MARK: - CarrierAlertsStore — `carriers.getLoadsRequiringAttention`
//
// Drives the "Needs your attention" alert strip on Carrier Home.

@MainActor
final class CarrierAlertsStore: BaseDynamicListStore<CarrierAPI.LoadAlert> {
    override func fetch() async throws -> [CarrierAPI.LoadAlert] {
        try await EusoTripAPI.shared.carrier.getLoadsRequiringAttention()
    }
}

// MARK: - CarrierRecentLoadsStore — `carriers.getRecentLoads`
//
// Drives the recent-activity feed below the active-loads card.

@MainActor
final class CarrierRecentLoadsStore: BaseDynamicListStore<CarrierAPI.RecentLoad> {
    var limit: Int = 5

    override func fetch() async throws -> [CarrierAPI.RecentLoad] {
        try await EusoTripAPI.shared.carrier.getRecentLoads(limit: limit)
    }
}

// =====================================================================
// CarrierLoadDetailStore — Carrier · 302 surface
// (brick 302_CarrierLoadDetail).
// ---------------------------------------------------------------------
// Added 2026-04-26 in the 130th eusotrip-killers firing as the second-
// screen depth port for the Carrier role per the 129th firing's
// hand-off recommendation: "302 (Carrier loads detail) — carriers.*
// router has many live procedures." Until 302 shipped, 301's row tap
// surfaced an `EusoEmptyState(comingSoon: true)` placeholder
// (`loadDetailPlaceholderSheet(for:)` on Views/Carrier/301_CarrierLoads).
// Now that 302 is live, the placeholder is replaced with this real
// surface.
//
// Backend wiring (verified live at firing open):
//   • detail   → `loads.getById` (input `{ id: string }`,
//                frontend/server/routers/loads.ts:1046).
//                Returns the full server projection. Same procedure
//                used by `ShipperLoadDetailStore` (line 3501) — the
//                role-anchor distinction is in how the screen frames
//                the same envelope (carrier sees driver+counterparty,
//                shipper sees bid count). `loads.getById` is
//                `protectedProcedure` server-side and resolves any
//                authenticated user; the carrier's view is gated by
//                ctx scoping at the row source (the only loads a
//                carrier can navigate to are ones already returned by
//                `carriers.getActiveLoads` / `carriers.getRecentLoads`).
//
// Cohort B day-1: every field surfaces verbatim from the server. When
// the load row is partially filled (no driver assigned yet, no actual
// delivery date, no rate posted) the screen renders em-dash neutral
// states for the missing slots — never fabricated values. Per the
// 2027 motivation: "no mock, no stubs, no fake data, 1000% dynamic."
// =====================================================================

@MainActor
final class CarrierLoadDetailStore: BaseDynamicStore<LoadsAPI.LoadDetail?> {
    /// The load id passed in by the caller (typically the row that
    /// was tapped on 301_CarrierLoads). String form because the server
    /// expects `z.string()` and the row's id is already a String.
    var loadId: String = ""

    override func fetch() async throws -> LoadsAPI.LoadDetail? {
        guard !loadId.isEmpty else { return nil }
        return try await EusoTripAPI.shared.loads.getDetail(id: loadId)
    }

    override func foldState(
        _ value: LoadsAPI.LoadDetail?
    ) -> RemoteState<LoadsAPI.LoadDetail?> {
        // `loads.getById` returns null only when the row has been
        // hard-deleted. Surface as `.empty` so the UI renders an
        // EusoEmptyState rather than treating it as a transport
        // failure. Found rows always have at least `id`/`loadNumber`/
        // `status` populated.
        guard let v = value else { return .empty }
        return .loaded(v)
    }
}

// =====================================================================
// BrokerHomeDashboardStore / BrokerOpenTendersStore /
// BrokerAlertsStore / BrokerRecentLoadsStore — Broker role home
// (brick 400_BrokerHome).
// ---------------------------------------------------------------------
// Added 2026-04-25 in the 99th eusotrip-killers firing as the role
// switch from Carrier to Broker per the 2027 motivation. The broker
// is the third role on the role-by-role build (Shipper · 200 →
// Carrier · 300 → Broker · 400 → …). Doctrine note: the Driver-Me
// surface does not expose any "broker" stores by that name today,
// so this prefix block is collision-free.
//
// Every store reads only from `EusoTripAPI.shared.broker.*` — no
// fixtures, no in-memory samples. If the backend has not exposed
// `brokers.*` yet, the stores resolve to `RemoteState.empty` (no
// data) or `.failed` (transport error) and the view surfaces an
// `EusoEmptyState`. This satisfies doctrine §11 + `MockDataGuard`.
// =====================================================================

// MARK: - BrokerHomeDashboardStore — `brokers.getDashboardStats`
//
// Drives the KPI strip on the Broker Home brick (400_BrokerHome).
// Returns the canonical 6-figure dashboard envelope: openTenders,
// awardedThisWeek, deliveredThisWeek, marginPerLoad, onTimeRate,
// grossMarginThisWeek.

@MainActor
final class BrokerHomeDashboardStore: BaseDynamicStore<BrokerAPI.DashboardStats?> {
    override func fetch() async throws -> BrokerAPI.DashboardStats? {
        try await EusoTripAPI.shared.broker.getDashboardStats()
    }

    override func foldState(
        _ value: BrokerAPI.DashboardStats?
    ) -> RemoteState<BrokerAPI.DashboardStats?> {
        // The dashboard is always populated server-side (zeros
        // when the broker has no tenders or loads), so `nil` is
        // treated as a hard edge — never as `.empty` data.
        guard let v = value else { return .empty }
        return .loaded(v)
    }
}

// MARK: - BrokerOpenTendersStore — `brokers.getOpenTenders`
//
// Drives the "Open tenders" card list on Broker Home.

@MainActor
final class BrokerOpenTendersStore: BaseDynamicListStore<BrokerAPI.OpenTender> {
    var limit: Int = 10

    override func fetch() async throws -> [BrokerAPI.OpenTender] {
        try await EusoTripAPI.shared.broker.getOpenTenders(limit: limit)
    }
}

// MARK: - BrokerAlertsStore — `brokers.getLoadsRequiringAttention`
//
// Drives the "Needs your attention" alert strip on Broker Home.

@MainActor
final class BrokerAlertsStore: BaseDynamicListStore<BrokerAPI.LoadAlert> {
    override func fetch() async throws -> [BrokerAPI.LoadAlert] {
        try await EusoTripAPI.shared.broker.getLoadsRequiringAttention()
    }
}

// MARK: - BrokerRecentLoadsStore — `brokers.getRecentLoads`
//
// Drives the recent-activity feed below the open-tenders card.

@MainActor
final class BrokerRecentLoadsStore: BaseDynamicListStore<BrokerAPI.RecentLoad> {
    var limit: Int = 5

    override func fetch() async throws -> [BrokerAPI.RecentLoad] {
        try await EusoTripAPI.shared.broker.getRecentLoads(limit: limit)
    }
}

// =====================================================================
// BrokerTenderDetailStore — Broker · 402 surface
// (brick 402_BrokerTenderDetail).
// ---------------------------------------------------------------------
// Added 2026-04-27 in the 132nd eusotrip-killers firing as the third-
// screen depth port for the Broker role. Until 402 shipped, 401's row
// tap (`tenderDetailComingSoonSheet`) surfaced an
// `EusoEmptyState(comingSoon:)` placeholder. With 402 live, that
// placeholder is replaced with this real surface.
//
// Backend wiring (verified live at firing open):
//   • detail   → `loads.getById` (input `{ id: string }`,
//                frontend/server/routers/loads.ts:1046).
//                Same procedure already powering 205_ShipperLoadDetail
//                (line 3501) and 302_CarrierLoadDetail (line 3804).
//                The role distinction is in framing — the broker
//                reframes "load" as "tender" and emphasises the
//                target-rate vs. market-rate spread plus responding-
//                carrier count rather than driver assignment.
//   • carrier responses → currently NOT EXPOSED by `brokers.*`. The
//                tender-detail screen renders a neutral placeholder
//                card describing what will live there once
//                `brokers.getTenderResponses` (or equivalent)
//                ships. No fabricated carrier shortlist.
//   • award CTA → `brokers.awardTender` is also NOT EXPOSED yet;
//                the screen renders a disabled "Award tender"
//                affordance with an honest explanatory subtitle.
//                Per §13 doctrine: "every backend stub gap has a
//                neutral empty state on the client (no fake data)."
//
// Pattern mirror: `CarrierLoadDetailStore` (line 3804). The shape and
// fold rules are identical because the underlying procedure is the
// same; the framing differs in the SwiftUI layer only.
// =====================================================================

@MainActor
final class BrokerTenderDetailStore: BaseDynamicStore<LoadsAPI.LoadDetail?> {
    /// The tender (load) id passed in by the caller (typically the
    /// row that was tapped on 401_BrokerTenders). String form because
    /// the server expects `z.string()` and the BrokerAPI.OpenTender
    /// row carries `id: String` already.
    var loadId: String = ""

    override func fetch() async throws -> LoadsAPI.LoadDetail? {
        guard !loadId.isEmpty else { return nil }
        return try await EusoTripAPI.shared.loads.getDetail(id: loadId)
    }

    override func foldState(
        _ value: LoadsAPI.LoadDetail?
    ) -> RemoteState<LoadsAPI.LoadDetail?> {
        // `loads.getById` returns null only when the row has been
        // hard-deleted. Surface as `.empty` so the UI renders an
        // EusoEmptyState rather than treating it as a transport
        // failure. Found rows always have at least `id` /
        // `loadNumber` / `status` populated.
        guard let v = value else { return .empty }
        return .loaded(v)
    }
}

// =====================================================================
// CatalystHomeDashboardStore / CatalystActiveMatchesStore /
// CatalystAlertsStore / CatalystRecentMatchesStore — Catalyst role
// home (brick 500_CatalystHome).
// ---------------------------------------------------------------------
// Added 2026-04-25 in the 102nd eusotrip-killers firing as the role
// switch from Broker to Catalyst per the 2027 motivation. Catalyst is
// the fourth role on the role-by-role build (Shipper · 200 →
// Carrier · 300 → Broker · 400 → Catalyst · 500 → …). Doctrine note:
// the Driver-Me surface does not expose any "catalyst" stores by that
// name today, so this prefix block is collision-free.
//
// Every store reads only from `EusoTripAPI.shared.catalyst.*` — no
// fixtures, no in-memory samples. If the backend has not exposed
// `catalysts.*` yet, the stores resolve to `RemoteState.empty` (no
// data) or `.failed` (transport error) and the view surfaces an
// `EusoEmptyState`. This satisfies doctrine §11 + `MockDataGuard`.
// =====================================================================

// MARK: - CatalystHomeDashboardStore — `catalysts.getDashboardStats`
//
// Drives the KPI strip on the Catalyst Home brick (500_CatalystHome).
// Returns the canonical 6-figure dashboard envelope: activeMatches,
// matchedThisWeek, deliveredThisWeek, avgFitScore, onTimeRate,
// gmvThisWeek.

@MainActor
final class CatalystHomeDashboardStore: BaseDynamicStore<CatalystAPI.DashboardStats?> {
    override func fetch() async throws -> CatalystAPI.DashboardStats? {
        try await EusoTripAPI.shared.catalyst.getDashboardStats()
    }

    override func foldState(
        _ value: CatalystAPI.DashboardStats?
    ) -> RemoteState<CatalystAPI.DashboardStats?> {
        // The dashboard is always populated server-side (zeros when
        // the catalyst has no live matches), so `nil` is treated as
        // a hard edge — never as `.empty` data.
        guard let v = value else { return .empty }
        return .loaded(v)
    }
}

// MARK: - CatalystActiveMatchesStore — `catalysts.getActiveMatches`
//
// Drives the "Active matches" card list on Catalyst Home.

@MainActor
final class CatalystActiveMatchesStore: BaseDynamicListStore<CatalystAPI.ActiveMatch> {
    var limit: Int = 10

    override func fetch() async throws -> [CatalystAPI.ActiveMatch] {
        try await EusoTripAPI.shared.catalyst.getActiveMatches(limit: limit)
    }
}

// MARK: - CatalystAlertsStore — `catalysts.getLoadsRequiringAttention`
//
// Drives the "Needs your attention" alert strip on Catalyst Home.

@MainActor
final class CatalystAlertsStore: BaseDynamicListStore<CatalystAPI.LoadAlert> {
    override func fetch() async throws -> [CatalystAPI.LoadAlert] {
        try await EusoTripAPI.shared.catalyst.getLoadsRequiringAttention()
    }
}

// MARK: - CatalystRecentMatchesStore — `catalysts.getRecentMatches`
//
// Drives the recent-activity feed below the active-matches card.

@MainActor
final class CatalystRecentMatchesStore: BaseDynamicListStore<CatalystAPI.RecentMatch> {
    var limit: Int = 5

    override func fetch() async throws -> [CatalystAPI.RecentMatch] {
        try await EusoTripAPI.shared.catalyst.getRecentMatches(limit: limit)
    }
}

// =====================================================================
// CatalystMatchDetailStore — Catalyst · 502 surface
// (brick 502_CatalystMatchDetail).
// ---------------------------------------------------------------------
// Added 2026-04-27 in the 136th eusotrip-killers firing as the third-
// screen depth port for the Catalyst role. Until 502 shipped, 501's row
// tap (`matchDetailComingSoonSheet`) surfaced an
// `EusoEmptyState(comingSoon:)` placeholder. With 502 live, that
// placeholder is replaced with this real surface.
//
// Backend wiring (verified live at firing open):
//   • detail   → `loads.getById` (input `{ id: string }`,
//                frontend/server/routers/loads.ts:1046).
//                Same procedure already powering 205_ShipperLoadDetail
//                (line 3501), 302_CarrierLoadDetail (line 3804), and
//                402_BrokerTenderDetail (line 3994). The role
//                distinction is in framing — the catalyst reframes
//                "load" as "match" and emphasises SpectraMatch fit
//                score, candidate count, and agent-in-the-loop rather
//                than tender-rate spread or driver assignment.
//   • SpectraMatch candidate breakdown → currently NOT EXPOSED by
//                `catalysts.*`. The match-detail screen renders a
//                neutral placeholder card describing what will live
//                there once `catalysts.getMatchCandidates` (or
//                equivalent) ships. No fabricated candidate
//                shortlist, no fabricated score rubric.
//   • Override-to-manual CTA → `catalysts.overrideMatch` is also NOT
//                EXPOSED yet; the screen renders a disabled "Override
//                to manual" affordance with an honest explanatory
//                subtitle. Per §13 doctrine: "every backend stub gap
//                has a neutral empty state on the client (no fake
//                data)."
//
// Pattern mirror: `BrokerTenderDetailStore` (line 3994). The shape
// and fold rules are identical because the underlying procedure is
// the same; the framing differs in the SwiftUI layer only.
// =====================================================================

@MainActor
final class CatalystMatchDetailStore: BaseDynamicStore<LoadsAPI.LoadDetail?> {
    /// The match (load) id passed in by the caller (typically the
    /// row that was tapped on 501_CatalystMatches). String form
    /// because the server expects `z.string()` and the
    /// CatalystAPI.ActiveMatch row carries `id: String` already.
    var loadId: String = ""

    override func fetch() async throws -> LoadsAPI.LoadDetail? {
        guard !loadId.isEmpty else { return nil }
        return try await EusoTripAPI.shared.loads.getDetail(id: loadId)
    }

    override func foldState(
        _ value: LoadsAPI.LoadDetail?
    ) -> RemoteState<LoadsAPI.LoadDetail?> {
        // `loads.getById` returns null only when the row has been
        // hard-deleted. Surface as `.empty` so the UI renders an
        // EusoEmptyState rather than treating it as a transport
        // failure. Found rows always have at least `id` /
        // `loadNumber` / `status` populated.
        guard let v = value else { return .empty }
        return .loaded(v)
    }
}

// =====================================================================
// EscortHomeDashboardStore / EscortActiveAssignmentsStore /
// EscortAlertsStore / EscortRecentAssignmentsStore — Escort role
// home (brick 600_EscortHome).
// ---------------------------------------------------------------------
// Added 2026-04-25 in the 103rd eusotrip-killers firing as the role
// switch from Catalyst to Escort per the 2027 motivation. Escort is
// the fifth role on the role-by-role build (Shipper · 200 →
// Carrier · 300 → Broker · 400 → Catalyst · 500 → Escort · 600 → …).
// Doctrine note: the Driver-Me surface does not expose any "escort"
// stores by that name today, so this prefix block is collision-free.
//
// Every store reads only from `EusoTripAPI.shared.escort.*` — no
// fixtures, no in-memory samples. If the backend has not exposed
// `escorts.*` yet, the stores resolve to `RemoteState.empty` (no
// data) or `.failed` (transport error) and the view surfaces an
// `EusoEmptyState`. This satisfies doctrine §11 + `MockDataGuard`.
// =====================================================================

// MARK: - EscortHomeDashboardStore — `escorts.getDashboardStats`
//
// Drives the KPI strip on the Escort Home brick (600_EscortHome).
// Returns the canonical 6-figure dashboard envelope:
// activeAssignments, completedThisWeek, milesThisWeek,
// corridorCoverage, onTimeRate, revenueThisWeek.

@MainActor
final class EscortHomeDashboardStore: BaseDynamicStore<EscortAPI.DashboardStats?> {
    override func fetch() async throws -> EscortAPI.DashboardStats? {
        try await EusoTripAPI.shared.escort.getDashboardStats()
    }

    override func foldState(
        _ value: EscortAPI.DashboardStats?
    ) -> RemoteState<EscortAPI.DashboardStats?> {
        // The dashboard is always populated server-side (zeros when
        // the escort has no live assignments), so `nil` is treated
        // as a hard edge — never as `.empty` data.
        guard let v = value else { return .empty }
        return .loaded(v)
    }
}

// MARK: - EscortActiveAssignmentsStore — `escorts.getActiveAssignments`
//
// Drives the "Active assignments" card list on Escort Home.

@MainActor
final class EscortActiveAssignmentsStore: BaseDynamicListStore<EscortAPI.ActiveAssignment> {
    var limit: Int = 10

    override func fetch() async throws -> [EscortAPI.ActiveAssignment] {
        try await EusoTripAPI.shared.escort.getActiveAssignments(limit: limit)
    }
}

// MARK: - EscortAlertsStore — `escorts.getLoadsRequiringAttention`
//
// Drives the "Needs your attention" alert strip on Escort Home.

@MainActor
final class EscortAlertsStore: BaseDynamicListStore<EscortAPI.LoadAlert> {
    override func fetch() async throws -> [EscortAPI.LoadAlert] {
        try await EusoTripAPI.shared.escort.getLoadsRequiringAttention()
    }
}

// MARK: - EscortRecentAssignmentsStore — `escorts.getRecentAssignments`
//
// Drives the recent-activity feed below the active-assignments card.

@MainActor
final class EscortRecentAssignmentsStore: BaseDynamicListStore<EscortAPI.RecentAssignment> {
    var limit: Int = 5

    override func fetch() async throws -> [EscortAPI.RecentAssignment] {
        try await EusoTripAPI.shared.escort.getRecentAssignments(limit: limit)
    }
}

// MARK: - EscortAssignmentDetailStore — `escorts.getActiveAssignmentDetail`
//
// Drives the assignment detail surface (601_EscortAssignmentDetail).
// Mirrors the `CatalystMatchDetailStore` / `BrokerTenderDetailStore`
// shape: caller writes `assignmentId` then triggers `refresh()`. Folds
// `nil` from the wire to `.empty` so the UI can render a deliberate
// "Assignment not found" empty state rather than treating absence as
// a transport failure. Added 2026-04-27 in the 147th eusotrip-killers
// firing alongside the 601_EscortAssignmentDetail brick.

@MainActor
final class EscortAssignmentDetailStore: BaseDynamicStore<EscortAPI.AssignmentDetail?> {
    /// The assignment id the screen is fetching. The 600 row tap
    /// passes `EscortAPI.ActiveAssignment.id` straight through.
    var assignmentId: String = ""

    override func fetch() async throws -> EscortAPI.AssignmentDetail? {
        guard !assignmentId.isEmpty else { return nil }
        return try await EusoTripAPI.shared.escort.getActiveAssignmentDetail(id: assignmentId)
    }

    override func foldState(
        _ value: EscortAPI.AssignmentDetail?
    ) -> RemoteState<EscortAPI.AssignmentDetail?> {
        // `escorts.getActiveAssignmentDetail` returns null only when
        // the assignment has been hard-deleted or is no longer in the
        // operator's scope. Surface as `.empty` so the UI renders an
        // EusoEmptyState rather than treating it as a transport
        // failure. Found assignments always have at least
        // `id` / `loadNumber` / `status` populated.
        guard let v = value else { return .empty }
        return .loaded(v)
    }
}

// MARK: - EscortCorridorStore — `escorts.getCorridor`
//
// Drives the corridor map surface (602_EscortCorridorMap). Caller
// writes `assignmentId` then triggers `refresh()`. The server returns
// the full corridor envelope (legs + milestones + geofences + escort
// vehicles + KPI counts) in a single read, so the screen renders KPIs
// and the per-section detail from the same payload. Folds `nil` from
// the wire to `.empty` so the UI surfaces a deliberate "Corridor not
// available" empty state rather than treating absence as a transport
// failure. A corridor with zero legs likewise folds to `.empty` (the
// route engine has not yet resolved geometry). Added 2026-04-27 in
// the 159th eusotrip-killers firing alongside the 602 brick.

@MainActor
final class EscortCorridorStore: BaseDynamicStore<EscortAPI.EscortCorridor?> {
    /// The assignment id the screen is fetching. The 601 sheet tap
    /// passes the assignment id straight through.
    var assignmentId: String = ""

    override func fetch() async throws -> EscortAPI.EscortCorridor? {
        guard !assignmentId.isEmpty else { return nil }
        return try await EusoTripAPI.shared.escort.getCorridor(id: assignmentId)
    }

    override func foldState(
        _ value: EscortAPI.EscortCorridor?
    ) -> RemoteState<EscortAPI.EscortCorridor?> {
        guard let v = value else { return .empty }
        if v.legs.isEmpty { return .empty }
        return .loaded(v)
    }
}

// =====================================================================
// MARK: - Terminal Manager (700) home stores
//
// Drives the four cards on `Views/Terminal/700_TerminalHome.swift`:
// KPI strip, "Needs your attention" alerts, "Active movements"
// feed, and "Recent activity" feed. Same RemoteState contract as
// the Escort/Catalyst/Carrier/Broker/Shipper home stores — see the
// matching block above for the doctrine note. Added 2026-04-25 in
// the 107th eusotrip-killers firing alongside the 700 Terminal
// Home brick.
//
// Doctrine note: the Driver-Me surface does not expose any
// "terminal" stores by that name today, so this prefix block is
// collision-free.
//
// Every store reads only from `EusoTripAPI.shared.terminal.*` —
// no fixtures, no in-memory samples. If the backend has not
// exposed `terminals.*` yet, the stores resolve to
// `RemoteState.empty` (no data) or `.failed` (transport error)
// and the view surfaces an `EusoEmptyState`. This satisfies
// doctrine §11 + `MockDataGuard`.
// =====================================================================

// MARK: - TerminalHomeDashboardStore — `terminals.getDashboardStats`

@MainActor
final class TerminalHomeDashboardStore: BaseDynamicStore<TerminalAPI.DashboardStats?> {
    override func fetch() async throws -> TerminalAPI.DashboardStats? {
        try await EusoTripAPI.shared.terminal.getDashboardStats()
    }

    override func foldState(
        _ value: TerminalAPI.DashboardStats?
    ) -> RemoteState<TerminalAPI.DashboardStats?> {
        // The dashboard is always populated server-side (zeros when
        // the terminal has no live movements), so `nil` is treated
        // as a hard edge — never as `.empty` data.
        guard let v = value else { return .empty }
        return .loaded(v)
    }
}

// MARK: - TerminalActiveMovementsStore — `terminals.getActiveMovements`

@MainActor
final class TerminalActiveMovementsStore: BaseDynamicListStore<TerminalAPI.ActiveMovement> {
    var limit: Int = 10

    override func fetch() async throws -> [TerminalAPI.ActiveMovement] {
        try await EusoTripAPI.shared.terminal.getActiveMovements(limit: limit)
    }
}

// MARK: - TerminalAlertsStore — `terminals.getMovementsRequiringAttention`

@MainActor
final class TerminalAlertsStore: BaseDynamicListStore<TerminalAPI.MovementAlert> {
    override func fetch() async throws -> [TerminalAPI.MovementAlert] {
        try await EusoTripAPI.shared.terminal.getMovementsRequiringAttention()
    }
}

// MARK: - TerminalRecentMovementsStore — `terminals.getRecentMovements`

@MainActor
final class TerminalRecentMovementsStore: BaseDynamicListStore<TerminalAPI.RecentMovement> {
    var limit: Int = 5

    override func fetch() async throws -> [TerminalAPI.RecentMovement] {
        try await EusoTripAPI.shared.terminal.getRecentMovements(limit: limit)
    }
}

// MARK: - TerminalGateQueueStore — `terminals.getGateQueue`
//
// Drives the 701_TerminalGateQueue list. Added 2026-04-27 in the 150th
// eusotrip-killers firing alongside the 701 brick. Same RemoteState
// contract as the other Terminal stores. Surfaces `.empty` when no
// rows are pending and `.error` when the parallel `terminals.*` router
// has not yet shipped the procedure — the screen renders an
// `EusoEmptyState` or honest retry banner per §13 doctrine.

@MainActor
final class TerminalGateQueueStore: BaseDynamicListStore<TerminalAPI.GateQueueItem> {
    var limit: Int = 25

    override func fetch() async throws -> [TerminalAPI.GateQueueItem] {
        try await EusoTripAPI.shared.terminal.getGateQueue(limit: limit)
    }
}

// MARK: - TerminalYardMapStore — `terminals.getYardMap`
//
// Drives the 702_TerminalYardMap zone-tile grid. Added 2026-04-27 in
// the 154th eusotrip-killers firing alongside the 702 brick. Reads the
// server's full yard topology (zones + slots) as a single envelope so
// the screen can render KPIs (totalSlots / occupiedSlots / avgDwell /
// dwellBreachCount) and the per-zone slot grid from the same payload.
//
// Note: this store inherits from `BaseDynamicStore<TerminalAPI.YardMap?>`
// (not the list specialization) because the server returns a single
// envelope, not a flat array. `nil` from the server is treated as
// `.empty` (yard not yet configured); a yard with zero zones likewise
// folds to `.empty`. Empty-but-configured zones fall through to
// `.loaded` so the screen can still render the empty zone scaffolding.

@MainActor
final class TerminalYardMapStore: BaseDynamicStore<TerminalAPI.YardMap?> {
    override func fetch() async throws -> TerminalAPI.YardMap? {
        try await EusoTripAPI.shared.terminal.getYardMap()
    }

    override func foldState(
        _ value: TerminalAPI.YardMap?
    ) -> RemoteState<TerminalAPI.YardMap?> {
        guard let v = value else { return .empty }
        if v.zones.isEmpty { return .empty }
        return .loaded(v)
    }
}

// =====================================================================
// MARK: - Admin (800) home stores
//
// Drives the four cards on `Views/Admin/800_AdminHome.swift`:
// KPI strip, "Needs your attention" alerts, "Open tickets" feed,
// and "Recent activity" feed. Same RemoteState contract as the
// Terminal/Escort/Catalyst/Carrier/Broker/Shipper home stores.
// Added 2026-04-25 in the 108th eusotrip-killers firing alongside
// the 800 Admin Home brick (closing the role-anchor sweep so all
// 8 of 24 distinct role surfaces have at least one shipped screen
// in the registry).
//
// Doctrine note: the Driver-Me surface does not expose any "admin"
// stores by that name today, so this prefix block is collision-free.
//
// Every store reads only from `EusoTripAPI.shared.admin.*` — no
// fixtures, no in-memory samples. If the backend has not exposed
// `admin.*` yet, the stores resolve to `RemoteState.empty` (no
// data) or `.failed` (transport error) and the view surfaces an
// `EusoEmptyState`. This satisfies doctrine §11 + `MockDataGuard`.
// =====================================================================

// MARK: - AdminHomeDashboardStore — `admin.getDashboardStats`

@MainActor
final class AdminHomeDashboardStore: BaseDynamicStore<AdminAPI.DashboardStats?> {
    override func fetch() async throws -> AdminAPI.DashboardStats? {
        try await EusoTripAPI.shared.admin.getDashboardStats()
    }

    override func foldState(
        _ value: AdminAPI.DashboardStats?
    ) -> RemoteState<AdminAPI.DashboardStats?> {
        // The dashboard is always populated server-side (zeros when
        // the platform has no live tickets or tenants), so `nil` is
        // treated as a hard edge — never as `.empty` data.
        guard let v = value else { return .empty }
        return .loaded(v)
    }
}

// MARK: - AdminOpenTicketsStore — `admin.getOpenTickets`

@MainActor
final class AdminOpenTicketsStore: BaseDynamicListStore<AdminAPI.ActiveTicket> {
    var limit: Int = 10

    override func fetch() async throws -> [AdminAPI.ActiveTicket] {
        try await EusoTripAPI.shared.admin.getOpenTickets(limit: limit)
    }
}

// MARK: - AdminAlertsStore — `admin.getApprovalsRequiringAttention`

@MainActor
final class AdminAlertsStore: BaseDynamicListStore<AdminAPI.AdminAlert> {
    override func fetch() async throws -> [AdminAPI.AdminAlert] {
        try await EusoTripAPI.shared.admin.getApprovalsRequiringAttention()
    }
}

// MARK: - AdminRecentTicketsStore — `admin.getRecentTickets`

@MainActor
final class AdminRecentTicketsStore: BaseDynamicListStore<AdminAPI.RecentTicket> {
    var limit: Int = 5

    override func fetch() async throws -> [AdminAPI.RecentTicket] {
        try await EusoTripAPI.shared.admin.getRecentTickets(limit: limit)
    }
}

// MARK: - AdminTenantsStore — `admin.listTenants` (802 brick · 151st firing)
//
// Drives the list on `Views/Admin/802_AdminTenants.swift`. Per-instance
// `limit` and `statusFilter` so the screen can re-fetch with a tighter
// scope (e.g. only "active" tenants) without spawning a parallel store.
// Same RemoteState contract as every other admin store.

@MainActor
final class AdminTenantsStore: BaseDynamicListStore<AdminAPI.Tenant> {
    var limit: Int = 50
    /// Optional status filter ("active", "trial", "suspended",
    /// "churned", "pending_review"). nil = no filter (server returns
    /// all tenants).
    var statusFilter: String? = nil

    override func fetch() async throws -> [AdminAPI.Tenant] {
        try await EusoTripAPI.shared.admin.listTenants(limit: limit, status: statusFilter)
    }
}

// MARK: - AdminControlTowerOverviewStore — `admin.controlTower.getOverview` (801 brick · 156th firing)
//
// Drives the KPI strip on `Views/Admin/801_AdminControlTower.swift`.
// `Optional<ControlTowerOverview>` so a server response that returns
// no rollup yet (brand-new tenant, pipeline never run) folds to
// `.empty`. Any thrown error from the underlying tRPC call resolves
// to `.error` and the screen surfaces an honest retry banner.

@MainActor
final class AdminControlTowerOverviewStore: BaseDynamicStore<AdminAPI.ControlTowerOverview?> {
    override func fetch() async throws -> AdminAPI.ControlTowerOverview? {
        try await EusoTripAPI.shared.admin.getControlTowerOverview()
    }

    override func foldState(_ value: AdminAPI.ControlTowerOverview?) -> RemoteState<AdminAPI.ControlTowerOverview?> {
        guard let v = value else { return .empty }
        // Health score 0 + zero-count exceptions + empty vendor status
        // is the genuine "no rollup yet" tuple — fold to empty so the
        // screen shows the awaiting-data state instead of a row of
        // zero-tiles.
        if v.activeExceptionsCount == 0
            && v.systemHealthScore == 0
            && v.vendorIntegrationStatus.isEmpty {
            return .empty
        }
        return .loaded(value)
    }
}

// MARK: - AdminControlTowerExceptionsStore — `admin.controlTower.getExceptions` (801 brick · 156th firing)
//
// Drives the exception-feed list on the same screen. Per-instance
// `limit` and `severityFilter` mirror the tenants-store pattern so
// the chip row on 801 can re-fetch with a tighter severity scope
// without spawning a parallel store.

@MainActor
final class AdminControlTowerExceptionsStore: BaseDynamicListStore<AdminAPI.ControlTowerException> {
    var limit: Int = 25
    /// Optional severity filter ("low", "normal", "high", "urgent",
    /// "critical"). nil = no filter (server returns every active
    /// exception).
    var severityFilter: String? = nil

    override func fetch() async throws -> [AdminAPI.ControlTowerException] {
        try await EusoTripAPI.shared.admin.getControlTowerExceptions(
            limit: limit, severity: severityFilter
        )
    }
}

// MARK: - AdminTenantDetailStore — `admin.getTenantDetail` (803 brick · 161st firing)
//
// Drives the per-tenant deep envelope on
// `Views/Admin/803_AdminTenantDetail.swift`. Caller writes
// `tenantId` immediately after init, then triggers `refresh()`.
// Same RemoteState contract as `EscortAssignmentDetailStore`,
// `TerminalYardMapStore`, `EscortCorridorStore`, and the other
// per-record detail stores. `Optional<TenantDetail>` so a server
// response that returns no body (parallel router not yet shipped
// on the `admin.*` namespace) folds to `.empty` and the screen
// shows the awaiting-data state.
//
// No fixture data ever (doctrine §11 + `MockDataGuard`). Every
// nullable field on the loaded envelope renders as a neutral
// em-dash on the 803 surface — never a fabricated number.

@MainActor
final class AdminTenantDetailStore: BaseDynamicStore<AdminAPI.TenantDetail?> {
    /// Tenant id this store is fetching. Caller writes immediately
    /// after init (or whenever a different tenant is selected) and
    /// then calls `refresh()`. nil = no fetch will fire.
    var tenantId: String? = nil

    override func fetch() async throws -> AdminAPI.TenantDetail? {
        guard let id = tenantId, !id.isEmpty else { return nil }
        return try await EusoTripAPI.shared.admin.getTenantDetail(id: id)
    }

    /// nil → `.empty` (no body returned). A loaded tenant with
    /// zero contacts / zero usage / zero audit rows is still a
    /// `.loaded` state — the UI renders honest empty sub-cards
    /// rather than treating the whole envelope as missing.
    override func foldState(_ value: AdminAPI.TenantDetail?) -> RemoteState<AdminAPI.TenantDetail?> {
        guard value != nil else { return .empty }
        return .loaded(value)
    }
}

// MARK: - NotificationPreferencesStore — `users.{get,update}NotificationPreferences`
//
// Cross-role store that fronts the canonical 11-boolean notification
// preference matrix. Used by every role's Settings surface (211 Shipper
// Settings is the first consumer; Driver Me Notifications continues to
// use the legacy per-(channel, category) `notifications.updatePreferences`
// path during the transition). State is `RemoteState<UsersAPI.PreferenceMatrix>`
// — never `[T]`, so we inherit from `BaseDynamicStore` (not the list
// variant). `foldState` collapses to `.loaded` always (a brand-new
// account still has the 11 default booleans, never an empty case).
//
// Optimistic mutation pattern:
//   1. View flips a Toggle → calls `setPreference(\.bidAlerts, true)`.
//   2. Store stamps the new matrix into `state` immediately so the UI
//      ack is sub-frame.
//   3. Store fires `users.updateNotificationPreferences(Patch(bidAlerts:true))`.
//   4. On success, the optimistic flip stays. The server returns
//      `{success: true}` only — no echoed matrix — so no reconcile.
//   5. On failure, store rolls back to the prior matrix and writes
//      `lastError` so the UI can surface a banner.
//
// The store does NOT re-fetch on every flip. The Settings UI's
// `.refreshable` block calls `refresh()` for explicit pull-to-refresh
// reconciliation, which is the only path that re-reads from the
// server. This keeps round-trips proportional to user intent.
//

@MainActor
final class NotificationPreferencesStore: BaseDynamicStore<UsersAPI.PreferenceMatrix> {
    /// Subset of fields currently being committed to the server.
    /// Settings UI uses this to disable a row's Toggle while the
    /// matching mutation is inflight. Keyed by the `KeyPath`-derived
    /// stable string identifier ("emailNotifications", "bidAlerts", etc.)
    /// so the UI can probe with the same string the toggle binds to.
    @Published private(set) var inflight: Set<String> = []

    override func fetch() async throws -> UsersAPI.PreferenceMatrix {
        try await EusoTripAPI.shared.users.getNotificationPreferences()
    }

    /// Always treat the matrix as `loaded` — there is no empty case,
    /// even a brand-new account hydrates the 11 defaults server-side.
    override func foldState(_ value: UsersAPI.PreferenceMatrix) -> RemoteState<UsersAPI.PreferenceMatrix> {
        .loaded(value)
    }

    /// Convenience read-through. Returns the loaded matrix or, before
    /// the first round-trip lands, the server-aligned default. The UI
    /// renders the same toggles in either case so there's no flash of
    /// "wrong" state during the cold-load.
    var matrix: UsersAPI.PreferenceMatrix {
        if case .loaded(let m) = state { return m }
        return .serverDefault
    }

    /// Flip a single boolean optimistically and persist. The
    /// `keyName` argument is the stable field identifier (matches the
    /// `Patch` coding key) — the UI uses it to guard against
    /// double-flips while a previous mutation is inflight.
    func setPreference(keyName: String, value: Bool) async {
        guard !inflight.contains(keyName) else { return }
        let prior = matrix
        let next = applyPatch(to: prior, keyName: keyName, value: value)
        // 1. Optimistic stamp.
        state = .loaded(next)
        // 2. Persist.
        inflight.insert(keyName)
        defer { inflight.remove(keyName) }
        do {
            _ = try await EusoTripAPI.shared.users.updateNotificationPreferences(
                buildPatch(keyName: keyName, value: value)
            )
            // 3a. Success: keep the optimistic value.
        } catch {
            // 3b. Failure: roll back + surface error.
            state = .loaded(prior)
            lastError = error
        }
    }

    // ─── Internal: keyName → Patch / matrix updaters ─────────────────
    //
    // The 211 Settings UI binds Toggles to a `(field: PrefField, isOn:
    // Bool)` enum so it doesn't have to thread KeyPaths through every
    // Toggle binding. The resolver below maps the stable string
    // identifiers (matching the Patch coding keys) to the corresponding
    // matrix field. This is verbose but the surface is small (11 keys),
    // it's all type-checked at compile time, and it avoids reflection.
    //

    private func buildPatch(keyName: String, value: Bool) -> UsersAPI.Patch {
        var p = UsersAPI.Patch()
        switch keyName {
        case "emailNotifications": p.emailNotifications = value
        case "pushNotifications":  p.pushNotifications  = value
        case "smsNotifications":   p.smsNotifications   = value
        case "inAppNotifications": p.inAppNotifications = value
        case "loadUpdates":        p.loadUpdates        = value
        case "bidAlerts":          p.bidAlerts          = value
        case "paymentAlerts":      p.paymentAlerts      = value
        case "messageAlerts":      p.messageAlerts      = value
        case "missionAlerts":      p.missionAlerts      = value
        case "promotionalAlerts":  p.promotionalAlerts  = value
        case "weeklyDigest":       p.weeklyDigest       = value
        default: break
        }
        return p
    }

    private func applyPatch(
        to m: UsersAPI.PreferenceMatrix,
        keyName: String,
        value: Bool
    ) -> UsersAPI.PreferenceMatrix {
        return UsersAPI.PreferenceMatrix(
            emailNotifications: keyName == "emailNotifications" ? value : m.emailNotifications,
            pushNotifications:  keyName == "pushNotifications"  ? value : m.pushNotifications,
            smsNotifications:   keyName == "smsNotifications"   ? value : m.smsNotifications,
            inAppNotifications: keyName == "inAppNotifications" ? value : m.inAppNotifications,
            loadUpdates:        keyName == "loadUpdates"        ? value : m.loadUpdates,
            bidAlerts:          keyName == "bidAlerts"          ? value : m.bidAlerts,
            paymentAlerts:      keyName == "paymentAlerts"      ? value : m.paymentAlerts,
            messageAlerts:      keyName == "messageAlerts"      ? value : m.messageAlerts,
            missionAlerts:      keyName == "missionAlerts"      ? value : m.missionAlerts,
            promotionalAlerts:  keyName == "promotionalAlerts"  ? value : m.promotionalAlerts,
            weeklyDigest:       keyName == "weeklyDigest"       ? value : m.weeklyDigest
        )
    }
}

// MARK: - LoadTemplatesListStore — `loadTemplates.list`
//
// Saved lane / commodity / equipment configurations. Backs the 211
// Shipper Settings "Default lane configs" card. Server returns
// favorites first, then most-recently-used, then most-recently-
// created — already ordered, so no client-side re-sort.
//
// Empty case is honest: a brand-new shipper account has zero saved
// templates until they post a load and tap "Save as template" (next
// firing wires that affordance into 204 ShipperPostLoad). The card's
// empty state explains that flow rather than showing a "coming soon"
// stub.
@MainActor
final class LoadTemplatesListStore: BaseDynamicListStore<LoadTemplatesAPI.Template> {
    override func fetch() async throws -> [LoadTemplatesAPI.Template] {
        try await EusoTripAPI.shared.loadTemplates.list()
    }
}
