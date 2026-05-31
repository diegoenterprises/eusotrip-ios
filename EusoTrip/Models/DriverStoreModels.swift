//
//  DriverStoreModels.swift
//  EusoTrip
//
//  Minimal DTOs used by the live-data stores in
//  `ViewModels/LiveDataStores.swift`. Each `struct` below mirrors the
//  shape the backend procedure WILL return once the corresponding
//  `TODO(backend)` router ships (see `mock_data_audit/backend_map.md`).
//
//  Every type is `Codable` + `Identifiable` + `Hashable` so the stores
//  can decode wire payloads without a bespoke mapping layer and views
//  can use `ForEach` without an `.id(\.id)` annotation.
//
//  These types exist purely so consuming view code type-checks today —
//  the stores currently return `[]` for every backend-missing surface,
//  but the view compiles against the real shape, so the day the
//  backend procedure lands the only change is the store's `fetch()`.
//

import Foundation

// MARK: - Wallet

struct WalletTxn: Codable, Identifiable, Hashable {
    let id: String
    let kind: String            // "load_payout" | "instant_payout" | "fuel" | "fee" | "factoring"
    let title: String
    let subtitle: String?
    let amount: Double
    let currency: String?
    let timestamp: String?      // ISO-8601
    let loadId: String?
    let iconHint: String?       // optional SF Symbol hint from server
}

struct WalletPaymentMethod: Codable, Identifiable, Hashable {
    let id: String
    let kind: String            // "bank" | "card" | "debit"
    let institution: String     // "Chase" | "Visa" | "Stripe"
    let mask: String            // "4921"
    let isDefault: Bool
    let isInstant: Bool
    let addedAt: String?
}

struct WalletEarningsSummary: Codable, Hashable {
    let thisWeekGross: Double
    let thisMonthGross: Double
    let ytdGross: Double
    let pending: Double
    let settledLoadsCount: Int
    let avgRatePerMile: Double?
    let deadheadPct: Double?
    let detentionDollars: Double?
    let projectedAnnual: Double?
    let currency: String?
}

/// Snapshot of the driver's live wallet balance used by the
/// EusoWallet rebuild hero card. Mirrors the canonical
/// `wallet.getBalance` wire shape; we keep it here (rather than burying
/// inside `WalletAPI`) so stores elsewhere can import the same type.
struct WalletBalanceSnapshot: Codable, Hashable {
    let available: Double
    let pending: Double
    let reserved: Double
    let escrow: Double
    let total: Double
    let currency: String
    let lastUpdated: String?
    let paymentMethods: Int?
}

/// Driver-facing settlement batch row projected from
/// `settlementBatching.getDriverBatchView`.
/// `totalAmount` arrives as a DECIMAL-string on the wire — we keep it
/// as `String` and parse at the render site so the raw response isn't
/// mangled.
struct DriverSettlementBatch: Codable, Identifiable, Hashable {
    let batchId: Int
    let batchNumber: String
    let periodStart: String?
    let periodEnd: String?
    let totalAmount: String
    let status: String
    let paidAt: String?
    var id: Int { batchId }

    /// Numeric projection of the wire-format total. Fails soft to 0 so
    /// list rendering never crashes on an unexpected shape.
    var amount: Double { Double(totalAmount) ?? 0 }

    /// True for rows the wallet should surface as "upcoming" (not
    /// already paid). Matches the canonical status set from the router.
    var isUpcoming: Bool {
        switch status.lowercased() {
        case "paid", "failed", "disputed": return false
        default: return true
        }
    }
}

/// Weekly aggregate for the EusoWallet bar chart. Mirrors
/// `earnings.getWeeklySummaries` one-to-one; the chart reads
/// `totalEarnings` as the bar height.
struct WeeklyEarningsBar: Codable, Identifiable, Hashable {
    let weekStart: String
    let weekEnd: String
    let totalLoads: Int
    let totalMiles: Double
    let totalEarnings: Double
    let avgPerMile: Double
    let avgPerLoad: Double
    var id: String { weekStart }
}

// MARK: - Brick 068 · Me · Earnings
//
// Canonical procedures consumed:
//   earnings.getSummary({ period })     → EarningsSummary  (week/month/quarter/year only)
//   earnings.getYTDSummary              → YTDSummary        (current year)
//   earnings.getWeeklySummaries         → [WeeklyEarningsBar]
//   earnings.getEarnings({ period })    → [TopLoadRow] (sort + truncate client-side)
//
// `ytd` is a first-class iOS period — the screen's segmented picker lets
// the driver swap between the 4 server-native buckets AND a YTD rollup,
// which iOS fans out into `getYTDSummary` under the hood. The server
// itself does not accept `ytd` on `earnings.getSummary`.

/// Period bucket backing brick 068's segmented picker. `.ytd` does not
/// round-trip directly to `earnings.getSummary` — the store special-cases
/// it to read `earnings.getYTDSummary` instead.
enum EarningsPeriod: String, Codable, CaseIterable, Hashable, Identifiable {
    case week, month, quarter, year, ytd
    var id: String { rawValue }

    /// Short label rendered inside the EusoBadge-sized chip. Uppercased
    /// to match the app-wide StatusPill/EusoBadge typography.
    var label: String {
        switch self {
        case .week:    return "WEEK"
        case .month:   return "MONTH"
        case .quarter: return "QUARTER"
        case .year:    return "YEAR"
        case .ytd:     return "YTD"
        }
    }

    /// Wire value for `earnings.getSummary({ period })`. Only defined
    /// for the four server-native buckets — `.ytd` returns nil because
    /// the store fans out to a different procedure for that case.
    var wirePeriod: String? {
        switch self {
        case .week:    return "week"
        case .month:   return "month"
        case .quarter: return "quarter"
        case .year:    return "year"
        case .ytd:     return nil
        }
    }

    /// How many chart buckets to request for this period. Matches the
    /// "last 8" resolution called for in the brick spec — week → 8
    /// weeks, month → 8 months (approx via weekly summaries fall-back
    /// rolled into month groups at render), etc. Store uses 8 uniformly.
    var barCount: Int { 8 }
}

/// Local DTO for the screen's hero/breakdown cards. Mirrors the shape of
/// `EarningsAPI.PeriodSummary` but exposes just the fields brick 068
/// actually renders, plus a `period` tag so the view can assert the
/// summary matches the currently-selected picker position.
struct EarningsSummary: Codable, Hashable {
    let period: EarningsPeriod
    let totalEarnings: Double
    let totalLoads: Int
    let totalMiles: Double
    let avgPerMile: Double
    let avgPerLoad: Double
    let pendingAmount: Double
    let paidAmount: Double
    let bonuses: Double
    let changePct: Double
    let trend: String           // "up" | "down" | "stable"
}

/// Year-to-date rollup for the footer card. Mirrors
/// `earnings.getYTDSummary` — keeps `projectedAnnual` alongside because
/// the footer shows "YTD gross" + "projected annual" as paired metrics.
///
/// Note: the canonical `tax.getSummary` surface carries W-9/1099 fields
/// (`federalWithheld`, `stateWithheld`, `download1099Available`). Brick
/// 068 reads YTD dollars from `earnings.getYTDSummary` AND withholding
/// from `tax.getSummary` — the two calls are fanned out in parallel.
struct YTDSummary: Codable, Hashable {
    let year: Int
    let grossEarnings: Double
    let netEarnings: Double
    let totalLoads: Int
    let totalMiles: Double
    let avgPerMile: Double
    let projectedAnnual: Double

    // Populated from `tax.getSummary` at the store layer — kept optional
    // so a tax-service hiccup never blocks the earnings surface.
    let platformFees: Double?
    let federalWithheld: Double?
    let stateWithheld: Double?
    let estimatedTax: Double?
    let download1099Available: Bool?
    let download1099URL: String?
}

/// Top-earning load row for the "TOP LOADS THIS PERIOD" section.
/// Mirrors the projection `EarningsAPI.getEarnings` emits, but narrowed
/// to the fields brick 068 renders. Tap → `LoadDetailSheet` via
/// `loadNumber` + `loadId`.
struct TopLoadRow: Codable, Identifiable, Hashable {
    let id: String            // backend `e<loadId>`
    let loadNumber: String
    let date: String          // ISO yyyy-MM-dd
    let origin: String
    let destination: String
    let miles: Double
    let totalPay: Double
}

// MARK: - Gamification

struct DriverBadge: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let iconName: String        // SF Symbol or asset id
    let earnedAt: String?       // ISO-8601 — nil means locked
    let description: String?
    let tier: String?           // "bronze" | "silver" | "gold" | "platinum"
}

struct DriverMission: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let kind: String            // "weekly" | "monthly" | "seasonal"
    let progress: Double        // 0.0 … 1.0
    let rewardLabel: String?    // "$250 bonus" | "2x XP" | ...
    let expiresAt: String?
    let claimedAt: String?
}

struct RewardItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let pointsCost: Int
    let category: String?       // "fuel" | "gear" | "cash" | "experience"
    let imageUrl: String?
    let inStock: Bool?
    let tierRequired: String?
}

struct LeaderboardRow: Codable, Identifiable, Hashable {
    let id: String              // driver id
    let rank: Int
    let displayName: String
    let avatarUrl: String?
    let score: Int
    let isCurrentDriver: Bool
    let changeVsLastWeek: Int?
}

// MARK: - Profile / referrals

struct DriverReferral: Codable, Identifiable, Hashable {
    let id: String
    let inviteeName: String?
    let inviteeEmail: String?
    let status: String          // "pending" | "completed"
    let bonusAmount: Double?
    let invitedAt: String?
    let activatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case inviteeName = "refereeName"
        case inviteeEmail
        case status = "refereeStatus"
        case bonusAmount
        case invitedAt = "signedUpAt"
        case activatedAt = "firstLoadAt"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        inviteeName = try container.decodeIfPresent(String.self, forKey: .inviteeName)
        inviteeEmail = try container.decodeIfPresent(String.self, forKey: .inviteeEmail)
        status = try container.decode(String.self, forKey: .status)
        // Server sends bonusAmount as non-optional number; coerce to optional
        bonusAmount = try container.decodeIfPresent(Double.self, forKey: .bonusAmount)
        invitedAt = try container.decodeIfPresent(String.self, forKey: .invitedAt)
        activatedAt = try container.decodeIfPresent(String.self, forKey: .activatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(inviteeName, forKey: .inviteeName)
        try container.encodeIfPresent(inviteeEmail, forKey: .inviteeEmail)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(bonusAmount, forKey: .bonusAmount)
        try container.encodeIfPresent(invitedAt, forKey: .invitedAt)
        try container.encodeIfPresent(activatedAt, forKey: .activatedAt)
    }
}

// MARK: - Fleet

struct FleetAsset: Codable, Identifiable, Hashable {
    let id: String
    let kind: String            // "tractor" | "trailer" | "apu" | "other"
    let unitNumber: String
    let make: String?
    let model: String?
    let year: Int?
    let plate: String?
    let odometerMiles: Int?
    let homeBase: String?
    let status: String?         // "active" | "in_maintenance" | "out_of_service"
}

// MARK: - Fleet vehicle row (canonical `fleet.getVehicles`)
// Backs `FleetVehiclesStore` and the Me · Fleet card. Mirrors the
// minimum fields iOS renders — richer fleet.getVehicles payload is
// decoded on demand by the ViewModel when needed.

struct FleetVehicleRow: Codable, Identifiable, Hashable {
    let id: String
    let unitNumber: String
    let kind: String            // "tractor" | "trailer" | etc
    let make: String?
    let model: String?
    let year: Int?
    let plate: String?
    let status: String?
    let odometer: Int?
}

// MARK: - Zeun breakdown row (canonical `zeunMechanics.getMyBreakdowns`)
// Shape matches `reports.map((r)=>({...}))` at zeunMechanics.ts:421.

struct ZeunBreakdownRow: Codable, Identifiable, Hashable {
    let id: Int
    let issueCategory: String
    let severity: String
    let status: String
    let canDrive: Bool?
    let symptoms: [String]?
    let createdAt: String?
    let resolvedAt: String?
    let actualCost: Double?
}

// MARK: - HOS summary (for Me → ELD hero card)
//
// The Me tab's "ELD HOS" hero card needs a compact summary distinct
// from the full `HOSStatus` returned by `hos.getStatus`. Until a
// dedicated `hos.getDriverCard` endpoint ships the hero just reads
// directly from `HOSLiveStore`, but the DTO is declared here so any
// future store can decode into it.
struct HOSDriverCard: Codable, Hashable {
    let currentStatus: String
    let driveRemainingMinutes: Int
    let shiftRemainingMinutes: Int
    let cycleRemainingMinutes: Int
    let violationCount: Int
    let lastCertifiedDate: String?
}
