//
//  661_RailDemurrageChargeGeneration.swift
//  EusoTrip — Rail · Rail Engineer · Demurrage Charge Run (brick 661).
//
//  PURPOSE. The carrier-side surface where accrued rail dwell turns into a
//  billable demurrage charge: what is on the clock right now, which cars are
//  past free time, the hours x rate math behind every accrued dollar, and the
//  run that commits new charges — one shipment at a time, through the only verb
//  on the server that actually writes the charge row and its audit entry.
//
//  Verbatim port of 05 Rail/Light-SVG/661 Rail Demurrage Charge Generation.svg
//  (Light + Dark). Composition mirrored block for block:
//    eyebrow + mono right register -> back-chevron breadcrumb -> gradient
//    tabular money hero + subline -> iridescent hairline -> past-free-time
//    attention band (danger wash + count chip) -> ACCRUAL LEDGER card (per-car
//    hours x rate · free · accrued, status pill, right-rail money) -> RUN
//    TOTALS card (three cells split by rules) -> FREE-TIME REGIME · BY COUNTRY
//    strip -> CTA pair -> Rail Engineer BottomNav.
//
//  ARCHETYPE = MONEY. The SVG demands it and the job demands it: a tabular
//  amount hero, a line-item ledger whose right rail is money, a totals card,
//  and a currency register. The three-cell block is a TOTALS FOOTER under a
//  ledger — not a hero-card -> 3-KPI stamp. A charge run reads like a ledger.
//
//  ── WIRING MANIFEST (every line re-confirmed first-hand in the router) ──────
//  BOARD (reads)
//    EXISTS · railDemurrageAuto.ts:47   (query · protectedProcedure) NO INPUT
//             railDemurrageAuto.dashboard
//             out {forecastSeries[{hours,cumUsd}], perCarRunway[{demurrageId,
//                  railcarNumber,freeTimeHours,chargeableHours,ratePerHour,
//                  usdToday,usdProjected}], summary{activeAccruals,
//                  totalChargesAccruing,disputesOpen,waiversPending,
//                  avgDwellHoursByYard}, topDwellReasons[], costliestYards[], note}
//             -> the hero figure, the attention band, the whole ACCRUAL LEDGER,
//                the RUN TOTALS card, and the 72h line. Tenant-scoped on
//                rail_shipments.companyId.
//    EXISTS · railDemurrageAuto.ts:151  (query · protectedProcedure) pure compute, no DB
//             railDemurrageAuto.calculateAccrual
//             in {placementTime, releaseTime?, country:"US"|"CA"|"MX",
//                 railcarCount, freeTimeHoursOverride?, ratePerHourOverride?}
//             -> the FREE-TIME REGIME strip. Called three times (US · CA · MX)
//                purely to READ BACK the constants that live at
//                railDemurrageAuto.ts:16-17 (FREE_TIME_HOURS {US:48,CA:48,MX:24},
//                RATE_PER_HOUR {US:35,CA:35,MX:40}). This file types NEITHER.
//    EXISTS · railShipments.ts:290      (query · railProcedure)
//             railShipments.getRailShipments in {limit,offset,status?,...}
//             -> the run-sheet candidate list (active consists).
//    EXISTS · railDemurrageAuto.ts:697  (query · protectedProcedure)
//             railDemurrageAuto.reportByDwellReason in {periodDays?}
//             -> the Analytics sheet. Its reasons[] are STRUCTURAL ZEROS (no
//                dwellReason column exists on rail_demurrage), so the sheet
//                says so and renders the server's own weatherHold.reason
//                verbatim instead of inventing a cause split.
//
//  COMMIT (the only write on this screen)
//    EXISTS · railShipments.ts:1567     (MUTATION · railProcedure)
//             railShipments.calculateRailDemurrage in {shipmentId:number}
//             out {demurrage,dwellHours,freeTimeHours,chargeableHours,
//                  facilityLat,facilityLon,facilityState,placedAt,releasedAt}
//                  | {demurrage:0,dwellHours:0,freeTimeHours:48,message}
//             DB ROW: upserts rail_demurrage, idempotent on (shipmentId,placedAt)
//                     — UPDATE railShipments.ts:1667 · INSERT railShipments.ts:1672.
//             AUDIT ROW: blockchainAuditTrail eventType "rail.demurrage_recorded"
//                     — railShipments.ts:1755 (eventType literal :1757).
//             WS: emits WS_EVENTS.RAIL_DEMURRAGE_START ('rail:demurrage_start',
//                     shared/websocket-events.ts:410) at railShipments.ts:1687 —
//                     ONLY on the true INSERT branch. A refresh of an already
//                     accruing row broadcasts NOTHING, so this screen never
//                     waits on a socket: it re-reads the board after every run.
//
//  NOT CALLED — AND WHY (product defect, stated plainly)
//    railDemurrageAuto.ts:249 (MUTATION · protectedProcedure) runBulkAccrual
//             IS A NO-OP. Its body has no getDb(), no query, no insert, no audit
//             row and no broadcast; it returns {processed, updated:0,
//             totalNewCharges:0, note}. The SVG <desc> claims it "writes
//             demurrageCharge rows + blockchainAuditTrail; broadcast
//             WS_CHANNELS.SETTLEMENT/WS_EVENTS.CHARGE_GENERATED" — that is FALSE
//             against this code, and WS_EVENTS.CHARGE_GENERATED does not exist
//             anywhere in the repo. Calling it and reporting success would be a
//             fabricated charge run, so this screen does not call it at all and
//             commits car-by-car through the per-shipment writer above.
//
//  WS_EVENTS broadcast BY THIS SCREEN'S CTA: RAIL_DEMURRAGE_START on first
//  accrual only. There is NO charge-generated event; NONE is emitted for a
//  refresh. The board re-reads instead of listening.
//
//  RBAC. Board reads are protectedProcedure (any signed-in user, tenant-scoped
//  to rail_shipments.companyId). The commit and the candidate list are
//  railProcedure = requireUser + requireRailMode (_core/trpc.ts:267) — the
//  account must carry RAIL mode. The writer additionally gates per shipment via
//  assertOwnsRailShipment (railShipments.ts:111): ADMIN/SUPER_ADMIN, or owner by
//  user, or owner by company — a non-owner gets FORBIDDEN, which this screen
//  reports per car instead of swallowing.
//
//  transportMode = rail. COUNTRY IS CONTENT, NOT A FILE FORK: one screen shows
//  all three regimes side by side — US and CA 48h free under STB · FRA and
//  Transport Canada Rail, MX 24h free under ARTF · SICT — and the applied rate
//  and currency (USD · CAD · MXN) follow the destination yard's country, which
//  the server derives; nothing about the regime is typed here.
//
//  OFFLINE POLICY (Encyclopedia v2): READ_CACHED(10m) for the ledger — a
//  demurrage clock moves by the hour, so the last good serve stays on screen and
//  stamps its own age in a monospaced register that flips to Brand.warning past
//  10 minutes and to Brand.danger when the link is down; every commit is
//  ONLINE_ONLY because it posts a billable charge and its audit row — the CTA
//  disables with an explicit on-screen reason instead of queueing. No rail path
//  is offline-eligible (Services/EusoTripAPI.swift:1684 lists the only six), so
//  a rail charge can never be enqueued today and this screen never implies it.
//
//  PRODUCTIVITY. It replaces the manual per-car day-count spreadsheet with a
//  live ledger that shows the hours x rate math behind every accrued dollar and
//  commits the charges in one pass, so the carrier bills dwell the day it
//  happens instead of the month after.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Decode boundary
//
// rail_demurrage.ratePerHour / totalCharge are MySQL `decimal`; the driver can
// serialize them as JSON STRINGS. railDemurrageAuto.dashboard Number()-coerces
// every numeric before it leaves the server, but a future change upstream must
// not silently blank a money line — so every money field decodes through this
// string-OR-number box.

private struct FlexNum661: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d; return }
        if let i = try? c.decode(Int.self) { value = Double(i); return }
        if let s = try? c.decode(String.self) { value = Double(s); return }
        value = nil
    }
}

// MARK: - Board shapes (railDemurrageAuto.dashboard)

private struct RunwayCar661: Decodable, Identifiable {
    let id: Int
    let railcarNumber: String?
    let freeTimeHours: FlexNum661?
    let chargeableHours: FlexNum661?
    let ratePerHour: FlexNum661?
    let usdToday: FlexNum661?
    let usdProjected: FlexNum661?

    private enum CodingKeys: String, CodingKey {
        case id = "demurrageId"
        case railcarNumber, freeTimeHours, chargeableHours, ratePerHour, usdToday, usdProjected
    }

    var freeHours: Double { freeTimeHours?.value ?? 0 }
    var chargeHours: Double { chargeableHours?.value ?? 0 }
    var rate: Double { ratePerHour?.value ?? 0 }
    var today: Double { usdToday?.value ?? 0 }
    var projected: Double { usdProjected?.value ?? 0 }
    var pastFreeTime: Bool { chargeHours > 0 }
}

private struct BoardSummary661: Decodable {
    let activeAccruals: Int?
    let totalChargesAccruing: FlexNum661?
    let disputesOpen: Int?
    let waiversPending: Int?
}

private struct ForecastPoint661: Decodable, Identifiable {
    let hours: Int?
    let cumUsd: FlexNum661?
    var id: Int { hours ?? -1 }
}

private struct DemurrageBoard661: Decodable {
    let forecastSeries: [ForecastPoint661]?
    let perCarRunway: [RunwayCar661]?
    let summary: BoardSummary661?
    let note: String?
}

// MARK: - Regime shape (railDemurrageAuto.calculateAccrual)

private struct RegimeQuote661: Decodable {
    let country: String?
    let freeTimeHours: FlexNum661?
    let ratePerHour: FlexNum661?
}

// MARK: - Run candidates (railShipments.getRailShipments)

private struct RunCandidate661: Decodable, Identifiable {
    let id: String
    let railRef: String?
    let origin: String?
    let destination: String?
    let status: String?
    let meta: String?
}

// MARK: - Commit shape (railShipments.calculateRailDemurrage)

private struct AccrualWrite661: Decodable {
    let demurrage: FlexNum661?
    let dwellHours: FlexNum661?
    let freeTimeHours: FlexNum661?
    let chargeableHours: FlexNum661?
    let facilityState: String?
    let placedAt: String?
    let releasedAt: String?
    /// Present only on the early-return branch (no car_placed event on file).
    let message: String?
}

// MARK: - Analytics shape (railDemurrageAuto.reportByDwellReason)

private struct DwellBucket661: Decodable, Identifiable {
    let reason: String?
    let count: Int?
    let totalCharges: FlexNum661?
    let avgHours: FlexNum661?
    var id: String { reason ?? "unclassified" }
}

private struct WeatherHold661: Decodable {
    let enabled: Bool?
    let reason: String?
    let carsReviewed: Int?
    let carsWithDocumentedHold: Int?
    let excludableMinutes: Int?
    let excludableCharge: FlexNum661?
}

private struct DwellReport661: Decodable {
    let reasons: [DwellBucket661]?
    let weatherHold: WeatherHold661?
}

// MARK: - Run-target + result models (local composition, not server rows)

private struct RunTarget661: Identifiable, Hashable {
    let id: Int
    let label: String
    let sub: String?
    let manual: Bool
}

private struct CommitLine661: Identifiable {
    let id: Int
    let label: String
    let posted: Double?
    let chargeableHours: Double?
    let freeTimeHours: Double?
    let facilityState: String?
    let serverMessage: String?
    let failure: String?
}

// MARK: - Encodable inputs
//
// Every field below is NON-optional, so the synthesized encoder can never emit
// a `null` into a zod `.optional()` slot.

private struct RegimeIn661: Encodable {
    let placementTime: String
    let country: String
    let railcarCount: Int
}
private struct CandidatesIn661: Encodable {
    let limit: Int
    let offset: Int
}
private struct ShipmentIdIn661: Encodable { let shipmentId: Int }
private struct DwellReportIn661: Encodable { let periodDays: Int }

// MARK: - Screen

struct RailDemurrageChargeGeneration_661: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            RailDemurrageChargeRunBody661()
        } nav: {
            // COMPLIANCE is current: generating a demurrage charge is a
            // tariff-regulated billing act (STB / FRA · Transport Canada Rail ·
            // ARTF / SICT), and the SVG's own nav marks COMPLIANCE as the
            // current tab for this surface.
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",         systemImage: "person",           isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct RailDemurrageChargeRunBody661: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var reach = OfflineReachabilityHub.shared

    // Board
    @State private var board: DemurrageBoard661? = nil
    @State private var regimes: [String: RegimeQuote661] = [:]
    @State private var loading = true
    @State private var loadError: String? = nil
    /// READ_CACHED(10m) — the last good serve stays on screen and stamps its age.
    @State private var lastSyncedAt: Date? = nil

    // Run sheet (ONLINE_ONLY commit)
    @State private var showRunSheet = false
    @State private var candidates: [RunCandidate661] = []
    @State private var candidatesError: String? = nil
    @State private var loadingCandidates = false
    @State private var manualIds: [Int] = []
    @State private var manualEntry: String = ""
    @State private var selection: Set<Int> = []
    @State private var committing = false
    @State private var commitDone = 0
    @State private var commitTotal = 0
    @State private var commitLines: [CommitLine661] = []
    @State private var commitBlocked: String? = nil

    // Analytics sheet
    @State private var showAnalytics = false
    @State private var report: DwellReport661? = nil
    @State private var reportError: String? = nil
    @State private var loadingReport = false

    @State private var toast: String? = nil

    private static let cacheTTL: TimeInterval = 10 * 60      // READ_CACHED(10m)
    private static let regimeCountries = ["US", "CA", "MX"]

    // MARK: Derived board figures

    private var cars: [RunwayCar661] { board?.perCarRunway ?? [] }
    private var pastFreeTimeCars: [RunwayCar661] { cars.filter { $0.pastFreeTime } }
    private var accruingTotal: Double { board?.summary?.totalChargesAccruing?.value ?? 0 }
    private var activeAccruals: Int { board?.summary?.activeAccruals ?? 0 }
    private var disputesOpen: Int { board?.summary?.disputesOpen ?? 0 }
    private var projected24: Double { cars.reduce(0) { $0 + $1.projected } }
    private var horizon72: Double? { board?.forecastSeries?.last?.cumUsd?.value }
    private var hasBoard: Bool { !cars.isEmpty || activeAccruals > 0 || accruingTotal > 0 }

    /// The regime a car sits in, named by matching the car's own free-time and
    /// rate against the three quotes the server returned. Never typed here.
    private func regimeCode(for car: RunwayCar661) -> String? {
        for code in Self.regimeCountries {
            guard let q = regimes[code],
                  let free = q.freeTimeHours?.value,
                  let rate = q.ratePerHour?.value else { continue }
            if abs(free - car.freeHours) < 0.5 && abs(rate - car.rate) < 0.01 { return code }
        }
        return nil
    }

    /// ISO currency register for the board. rail_demurrage carries NO currency
    /// column (the writer derives it from the destination yard's country), so
    /// US and CA are indistinguishable from a stored row — the register says so
    /// rather than picking one.
    private var currencyRegister: String {
        let codes = boardRegimeCodes
        if codes.isEmpty { return cars.isEmpty ? "—" : "UNMATCHED" }
        if codes == Set(["MX"]) { return "MXN" }
        if codes.isSubset(of: Set(["US", "CA"])) { return "USD/CAD" }
        return "MIXED"
    }

    private var boardRegimeCodes: Set<String> {
        Set(cars.compactMap { regimeCode(for: $0) })
    }

    /// The single free-time rule to headline in the attention band, when the
    /// whole board sits in one regime. Read back off calculateAccrual.
    private var boardRegime: RegimeQuote661? {
        let codes = boardRegimeCodes
        if codes.isEmpty { return nil }
        if codes == Set(["MX"]) { return regimes["MX"] }
        if codes.isSubset(of: Set(["US", "CA"])) { return regimes["US"] ?? regimes["CA"] }
        return nil
    }

    private var linkRegister: (String, Color) {
        if !reach.isOnline { return ("LINK DOWN", Brand.danger) }
        guard let synced = lastSyncedAt else { return ("LIVE", palette.textTertiary) }
        let age = Date().timeIntervalSince(synced)
        if age > Self.cacheTTL { return ("CACHED \(Int(age / 60))M", Brand.warning) }
        return ("LIVE", palette.textTertiary)
    }

    private var selectedTargets: [RunTarget661] {
        runTargets.filter { selection.contains($0.id) }
    }

    private var runTargets: [RunTarget661] {
        var out: [RunTarget661] = []
        var seen = Set<Int>()
        for c in candidates {
            guard let sid = Int(c.id), !seen.contains(sid) else { continue }
            seen.insert(sid)
            var subParts: [String] = []
            if let o = c.origin, let d = c.destination { subParts.append("\(o) → \(d)") }
            if let s = c.status, !s.isEmpty { subParts.append(s.replacingOccurrences(of: "_", with: " ")) }
            if let m = c.meta, !m.isEmpty { subParts.append(m) }
            out.append(RunTarget661(id: sid,
                                    label: c.railRef ?? "Shipment #\(sid)",
                                    sub: subParts.isEmpty ? nil : subParts.joined(separator: " · "),
                                    manual: false))
        }
        for m in manualIds where !seen.contains(m) {
            seen.insert(m)
            out.append(RunTarget661(id: m, label: "Shipment #\(m)", sub: "Added by ID", manual: true))
        }
        return out
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topRegister
                breadcrumb
                hero
                IridescentHairline()
                boardSection
                regimeStrip
                ctaPair
                policyNote
                footNotes
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
        .overlay(alignment: .bottom) { toastView }
        .sheet(isPresented: $showRunSheet) { runSheet }
        .sheet(isPresented: $showAnalytics) { analyticsSheet }
    }

    /// The ledger stack itself — loading, hard-fail, honest-empty, or the real
    /// attention band + line-item ledger + totals.
    @ViewBuilder
    private var boardSection: some View {
        if loading && board == nil {
            LifecycleCard {
                Text("Loading the accrual ledger…")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        } else if let err = loadError, board == nil {
            LifecycleCard(accentDanger: true) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Couldn't load the accrual ledger")
                        .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text(err).font(EType.caption).foregroundStyle(Brand.danger).lineLimit(4)
                }
            }
        } else if !hasBoard {
            EusoEmptyState(
                systemImage: "clock.badge.checkmark",
                title: "Nothing accruing right now",
                subtitle: "The clock starts when a car is placed and free time runs out. Run the charge generation below to accrue any shipment that has already tripped its free time."
            )
        } else {
            VStack(alignment: .leading, spacing: Space.s4) {
                attentionBand
                accrualLedger
                runTotals
            }
        }
    }

    /// Honesty law: the server's own note, the degraded-read reason, and the
    /// cache-age stamp are always visibly distinct from live figures.
    @ViewBuilder
    private var footNotes: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if let n = board?.note, !n.isEmpty { serverNote(n) }
            if let err = loadError, board != nil { staleNote(err, danger: true) }
            if let stamp = cacheAgeLine { staleNote(stamp, danger: false) }
        }
    }

    // MARK: - TopBar (the screen's single eyebrow + mono link register)

    private var topRegister: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ RAIL ENGINEER · CHARGE RUN")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text(linkRegister.0)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(linkRegister.1)
                .lineLimit(1)
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: Space.s2) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Text("Demurrage")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Money hero (tabular amount + currency register)

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(money(accruingTotal))
                    .font(.system(size: 32, weight: .bold)).kerning(-0.6)
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("on the clock")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 4)
                Text(currencyRegister)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(palette.tintNeutral))
            }
            Text(heroSubline)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var heroSubline: String {
        var parts: [String] = []
        parts.append("\(activeAccruals) car\(activeAccruals == 1 ? "" : "s") accruing")
        parts.append("\(pastFreeTimeCars.count) past free time")
        if disputesOpen > 0 { parts.append("\(disputesOpen) disputed") }
        if let h = horizon72 { parts.append("72h if nothing moves \(money(h))") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Past-free-time attention band

    private var attentionBand: some View {
        let n = pastFreeTimeCars.count
        let hot = n > 0
        return HStack(spacing: Space.s3) {
            Image(systemName: hot ? "exclamationmark.triangle" : "checkmark.seal")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(hot ? Brand.danger : Brand.success)
            VStack(alignment: .leading, spacing: 3) {
                Text(hot
                     ? "\(n) car\(n == 1 ? "" : "s") past free time"
                     : "No car is past free time")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(bandSubline)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Text("\(n)")
                .font(.system(size: 18, weight: .bold)).monospacedDigit()
                .foregroundStyle(hot ? Brand.danger : Brand.success)
                .frame(width: 54, height: 34)
                .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill((hot ? Brand.danger : Brand.success).opacity(0.14)))
        }
        .padding(Space.s4)
        .background(
            LinearGradient(colors: hot
                           ? [Brand.danger.opacity(0.10), Brand.warning.opacity(0.10)]
                           : [Brand.success.opacity(0.08), Brand.blue.opacity(0.06)],
                           startPoint: .leading, endPoint: .trailing)
        )
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(hot ? Brand.danger.opacity(0.28) : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var bandSubline: String {
        if let q = boardRegime,
           let free = q.freeTimeHours?.value,
           let rate = q.ratePerHour?.value {
            let code = q.country ?? ""
            let countryPrefix = code.isEmpty ? "" : "\(code) · "
            return "\(countryPrefix)\(trimHours(free)) free · \(money(rate))/h after · charges post only when this run commits them"
        }
        return "Free time and rate follow the destination yard's country — charges post only when this run commits them."
    }

    // MARK: - Accrual ledger (the line-item register)

    private var accrualLedger: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("ACCRUAL LEDGER")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 8)
                Text("hours × rate · accrued")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(cars.enumerated()), id: \.element.id) { idx, car in
                    ledgerRow(car)
                    if idx < cars.count - 1 {
                        Rectangle().fill(palette.borderFaint)
                            .frame(height: 1).padding(.horizontal, Space.s4)
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            Text("The charge row carries no currency column — the code above is inferred from the free-time and rate regime the server applied.")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func ledgerRow(_ car: RunwayCar661) -> some View {
        let hot = car.pastFreeTime
        let tint = hot ? Brand.danger : Brand.info
        return HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "clock")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(car.railcarNumber ?? "Charge #\(car.id)")
                    .font(.system(size: 14, weight: .bold)).monospaced()
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(mathLine(car))
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                StatusPill(text: hot ? "On clock" : "In free time", kind: hot ? .danger : .info)
                Text(money(car.today))
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("+24h \(money(car.projected))")
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
    }

    private func mathLine(_ car: RunwayCar661) -> String {
        var s = "\(trimHours(car.chargeHours)) × \(money(car.rate))/h · \(trimHours(car.freeHours)) free"
        if let code = regimeCode(for: car) { s += " · \(code)" }
        return s
    }

    // MARK: - Run totals (three cells, split by rules — the SVG's totals card)

    private var runTotals: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("RUN TOTALS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top, spacing: 0) {
                    totalCell("On the clock", money(accruingTotal), gradient: true, tint: nil)
                    verticalRule
                    totalCell("+24h projected", money(projected24), gradient: false, tint: nil)
                    verticalRule
                    totalCell("Disputes open", "\(disputesOpen)", gradient: false, tint: disputesOpen > 0 ? Brand.danger : nil)
                }
                if let h = horizon72 {
                    Text("72h horizon if every car stays put · \(money(h))")
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            Text("Billed-to-date is not on the board read, so no billed figure is shown here rather than an invented one.")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var verticalRule: some View {
        Rectangle().fill(palette.borderFaint).frame(width: 1, height: 44)
    }

    private func totalCell(_ label: String, _ value: String, gradient: Bool, tint: Color?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Group {
                if gradient { Text(value).foregroundStyle(LinearGradient.diagonal) }
                else if let tint { Text(value).foregroundStyle(tint) }
                else { Text(value).foregroundStyle(palette.textPrimary) }
            }
            .font(.system(size: 20, weight: .bold)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s2)
    }

    // MARK: - Free-time regime strip (tri-country, read off the server)

    private var regimeStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("FREE-TIME REGIME · BY COUNTRY")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                ForEach(Self.regimeCountries, id: \.self) { code in
                    regimeChip(code)
                }
            }
            Text(regimeFooter)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func regimeChip(_ code: String) -> some View {
        let q = regimes[code]
        let active = boardRegimeCodes == Set([code])
        let currency = code == "MX" ? "MXN" : (code == "CA" ? "CAD" : "USD")
        let regulator = code == "MX" ? "ARTF · SICT" : (code == "CA" ? "Transport Canada" : "STB · FRA")
        let ruleLine: String = {
            guard let free = q?.freeTimeHours?.value else { return "\(code) · rule pending" }
            return "\(code) · \(trimHours(free)) free"
        }()
        let rateLine: String = {
            guard let rate = q?.ratePerHour?.value else { return "rate pending" }
            return "\(money(rate))/h · \(currency)"
        }()

        return VStack(alignment: .leading, spacing: 2) {
            Text(ruleLine)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(active ? Color.white : palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(rateLine)
                .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                .foregroundStyle(active ? Color.white.opacity(0.9) : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(regulator)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(active ? Color.white.opacity(0.8) : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(active ? Color.clear : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var regimeFooter: String {
        if regimes.isEmpty {
            return "Free time and rate are read off the server's own regime table — they are never typed into this screen. The table did not answer on this load."
        }
        return "Free time and rate are read off the server's regime table, never typed here. The applied regime follows the destination yard's country; this screen highlights it only when every car on the board resolves to the same one."
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button {
                commitBlocked = nil
                commitLines = []
                selection = []
                manualEntry = ""
                showRunSheet = true
                Task { await loadCandidates() }
            } label: {
                Text(reach.isOnline ? "Generate charges" : "Offline · can't generate")
                    .font(EType.title)
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!reach.isOnline)
            .opacity(reach.isOnline ? 1 : 0.45)

            Button {
                showAnalytics = true
                Task { await loadReport() }
            } label: {
                Text("Analytics")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132, minHeight: 52)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Honesty notes (the no-op + the online-only refusal, in plain words)

    private var policyNote: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            noteRow(icon: "exclamationmark.triangle", tint: Brand.warning, text: bulkGapText)
            if !reach.isOnline {
                noteRow(icon: "wifi.exclamationmark", tint: Brand.danger,
                        text: "Offline — generating a charge posts money and its audit entry, so it never queues. Nothing has been held for later. Reconnect to commit the run live.")
            }
        }
    }

    private var bulkGapText: String {
        "The server's bulk accrual pass writes nothing — it returns a zero result with no charge row, no audit entry and no broadcast. So this run commits one shipment at a time through the writer that actually posts the charge row and its immutable audit entry, and reports each car's result on its own."
    }

    private func noteRow(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func serverNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.textTertiary)
            Text(text)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var cacheAgeLine: String? {
        guard let synced = lastSyncedAt else { return nil }
        let age = Date().timeIntervalSince(synced)
        guard age > Self.cacheTTL else { return nil }
        return "Ledger is \(Int(age / 60))m old — pull down to re-read the accruals."
    }

    private func staleNote(_ text: String, danger: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: danger ? "wifi.exclamationmark" : "clock.arrow.circlepath")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(danger ? Brand.danger : Brand.warning)
            Text(text)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Run sheet (ONLINE_ONLY commit, per shipment, real progress)

    private var runSheet: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    runSheetHeader
                    if !commitLines.isEmpty { commitResults }
                    if committing { commitProgressBar }

                    if !reach.isOnline {
                        LifecycleCard(accentDanger: true) {
                            Text("Offline. A demurrage charge and its audit entry never queue — reconnect to commit this run.")
                                .font(EType.caption).foregroundStyle(Brand.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let blocked = commitBlocked {
                        LifecycleCard(accentDanger: true) {
                            Text(blocked).font(EType.caption).foregroundStyle(Brand.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    manualEntryRow
                    candidateList
                    commitButton
                    Color.clear.frame(height: 24)
                }
                .padding(Space.s5)
            }
            .background(palette.bgPage.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showRunSheet = false }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var runSheetHeader: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CHARGE RUN · COMMIT PER SHIPMENT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Generate charges")
                .font(.system(size: 22, weight: .heavy)).kerning(-0.3)
                .foregroundStyle(palette.textPrimary)
            Text("Each selected shipment is accrued on its own. The write is idempotent on the car's placement time, so re-running a shipment refreshes its open charge instead of duplicating it. Results come back car by car, including failures.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var commitProgressBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Committing \(commitDone) of \(commitTotal)")
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.tintNeutral)
                    Capsule().fill(LinearGradient.primary)
                        .frame(width: commitTotal > 0
                               ? geo.size.width * CGFloat(commitDone) / CGFloat(commitTotal)
                               : 0)
                }
            }
            .frame(height: 6)
        }
    }

    private var commitResults: some View {
        let posted = commitLines.filter { ($0.posted ?? 0) > 0 }
        let nothingDue = commitLines.filter { $0.failure == nil && ($0.posted ?? 0) <= 0 }
        let failed = commitLines.filter { $0.failure != nil }
        let total = posted.reduce(0.0) { $0 + ($1.posted ?? 0) }

        return VStack(alignment: .leading, spacing: Space.s2) {
            Text("RUN RESULT")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            LifecycleCard(accentDanger: !failed.isEmpty, accentGradient: failed.isEmpty) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(posted.count) posted \(money(total)) · \(nothingDue.count) no charge · \(failed.count) failed")
                        .font(.system(size: 14, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("The board below re-reads after every run — there is no charge-generated broadcast on the server to listen for.")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(commitLines) { line in commitResultRow(line) }
        }
    }

    private func commitResultRow(_ line: CommitLine661) -> some View {
        let ok = line.failure == nil
        let charged = (line.posted ?? 0) > 0
        let tint: Color = ok ? (charged ? Brand.success : Brand.info) : Brand.danger
        return HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: ok ? (charged ? "checkmark.seal.fill" : "minus.circle") : "xmark.octagon.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(line.label)
                    .font(.system(size: 13, weight: .bold)).monospaced()
                    .foregroundStyle(palette.textPrimary)
                Text(commitDetail(line))
                    .font(EType.mono(.caption))
                    .foregroundStyle(ok ? palette.textSecondary : Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if charged {
                Text(money(line.posted ?? 0))
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(ok ? palette.borderFaint : Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func commitDetail(_ line: CommitLine661) -> String {
        if let f = line.failure { return f }
        if let m = line.serverMessage, !m.isEmpty { return m }
        var parts: [String] = []
        if let c = line.chargeableHours { parts.append("\(trimHours(c)) chargeable") }
        if let f = line.freeTimeHours { parts.append("\(trimHours(f)) free") }
        if let s = line.facilityState, !s.isEmpty { parts.append(s) }
        if (line.posted ?? 0) <= 0 { parts.append("still inside free time — nothing posted") }
        return parts.isEmpty ? "Accrual recalculated." : parts.joined(separator: " · ")
    }

    private var manualEntryRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ADD A SHIPMENT BY ID")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s3) {
                Image(systemName: "number")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                TextField("Shipment ID", text: $manualEntry)
                    .keyboardType(.numberPad)
                    .font(.system(size: 15, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                    .submitLabel(.done)
                    .onSubmit { addManualId() }
                Button { addManualId() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 12, weight: .heavy))
                        Text("Add").font(.system(size: 12, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(LinearGradient.diagonal))
                }
                .buttonStyle(.plain)
                .disabled(Int(manualEntry.trimmingCharacters(in: .whitespaces)) == nil)
                .opacity(Int(manualEntry.trimmingCharacters(in: .whitespaces)) == nil ? 0.45 : 1)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private var candidateList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("SHIPMENTS IN SCOPE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 8)
                if !runTargets.isEmpty {
                    Button(selection.count == runTargets.count ? "Clear all" : "Select all") {
                        if selection.count == runTargets.count { selection = [] }
                        else { selection = Set(runTargets.map { $0.id }) }
                    }
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.blue)
                    .buttonStyle(.plain)
                }
            }

            if loadingCandidates {
                LifecycleCard {
                    Text("Loading shipments…").font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            } else if runTargets.isEmpty {
                LifecycleCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No shipment came back in scope")
                            .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        Text(candidatesError ?? "The shipment list is scoped to the signed-in user's own shipments, while the ledger above is scoped to the whole company — so a carrier-side account can hold accruals it cannot list. Add the shipment by ID above to run it.")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                ForEach(runTargets) { target in candidateRow(target) }
            }
        }
    }

    private func candidateRow(_ target: RunTarget661) -> some View {
        let on = selection.contains(target.id)
        // The select target and the remove target are SIBLING buttons, never
        // nested — a button inside another button's label swallows one of them.
        return HStack(alignment: .top, spacing: Space.s3) {
            Button {
                if on { selection.remove(target.id) } else { selection.insert(target.id) }
            } label: {
                HStack(alignment: .top, spacing: Space.s3) {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(on ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(target.label)
                            .font(.system(size: 13, weight: .bold)).monospaced()
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        if let sub = target.sub {
                            Text(sub)
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if target.manual {
                Button {
                    manualIds.removeAll { $0 == target.id }
                    selection.remove(target.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Brand.danger)
                        .padding(.top, 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove shipment \(target.id) from the run")
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(on ? Brand.blue.opacity(0.45) : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var commitButton: some View {
        let ready = reach.isOnline && !committing && !selection.isEmpty
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                Task { await commitRun() }
            } label: {
                HStack {
                    Spacer()
                    if committing {
                        ProgressView().tint(.white)
                    } else {
                        Text(commitButtonTitle)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!ready)
            .opacity(ready ? 1 : 0.5)

            Text(commitButtonReason)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var commitButtonTitle: String {
        if !reach.isOnline { return "Offline · can't commit" }
        if selection.isEmpty { return "Select a shipment to run" }
        return "Commit \(selection.count) shipment\(selection.count == 1 ? "" : "s")"
    }

    private var commitButtonReason: String {
        if !reach.isOnline {
            return "Blocked: the device is offline and a billable charge never queues."
        }
        if selection.isEmpty {
            return "Blocked: nothing is selected."
        }
        return "Each shipment is written on its own, in order, with its own audit entry. A failure on one car stops nothing else and is reported above."
    }

    // MARK: - Analytics sheet (honest about the structural zeros)

    private var analyticsSheet: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.bar.doc.horizontal")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(LinearGradient.diagonal)
                            Text("DWELL CAUSE · 30 DAYS")
                                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                                .foregroundStyle(LinearGradient.diagonal)
                        }
                        Text("Run analytics")
                            .font(.system(size: 22, weight: .heavy)).kerning(-0.3)
                            .foregroundStyle(palette.textPrimary)
                    }

                    if loadingReport {
                        LifecycleCard {
                            Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    } else if let err = reportError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        LifecycleCard(accentWarning: true) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("No cause split exists to show")
                                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                                Text("The charge row has no dwell-reason column, so every operational bucket comes back at zero by construction. Those zeros are printed below exactly as the server returned them — they are not a measurement, and nothing has been apportioned across them.")
                                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        bucketList
                        weatherHoldCard
                    }
                    Color.clear.frame(height: 24)
                }
                .padding(Space.s5)
            }
            .background(palette.bgPage.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showAnalytics = false }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var bucketList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("BUCKETS AS RETURNED")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            ForEach(report?.reasons ?? []) { bucket in
                HStack {
                    Text(bucket.reason ?? "—")
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 8)
                    Text("\(bucket.count ?? 0) cars · \(money(bucket.totalCharges?.value ?? 0))")
                        .font(EType.mono(.caption)).monospacedDigit()
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
        }
    }

    private var weatherHoldCard: some View {
        let wh = report?.weatherHold
        return VStack(alignment: .leading, spacing: Space.s2) {
            Text("WEATHER-HOLD EVIDENCE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text((wh?.enabled ?? false)
                         ? "\(wh?.carsWithDocumentedHold ?? 0) of \(wh?.carsReviewed ?? 0) cars reviewed carry a documented severe-weather hold"
                         : "No weather evidence was pulled on this read")
                        .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let r = wh?.reason, !r.isEmpty {
                        Text("Server reason · \(r)")
                            .font(EType.mono(.caption))
                            .foregroundStyle(palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if (wh?.enabled ?? false) {
                        Text("\(wh?.excludableMinutes ?? 0) excludable minutes · \(money(wh?.excludableCharge?.value ?? 0)) movable to dispute")
                            .font(EType.mono(.caption)).monospacedDigit()
                            .foregroundStyle(palette.textSecondary)
                    } else {
                        Text("Nothing is excluded without a real documented hold overlapping the car's dwell window.")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Toast

    private var toastView: some View {
        Group {
            if let t = toast {
                Text(t)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Brand.success))
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func showToast(_ msg: String) {
        withAnimation(.easeOut(duration: 0.18)) { toast = msg }
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            withAnimation(.easeOut(duration: 0.18)) { toast = nil }
        }
    }

    // MARK: - Data

    /// Board + regime table in one fan-out. A dead regime probe degrades the
    /// country strip alone; a dead board keeps the last good serve on screen
    /// with its age stamped, per READ_CACHED(10m).
    private func load() async {
        loading = true
        loadError = nil

        let placement = isoNow661()
        async let boardTask: DemurrageBoard661 = EusoTripAPI.shared.queryNoInput("railDemurrageAuto.dashboard")
        async let usTask: RegimeQuote661? = EusoTripAPI.shared.query(
            "railDemurrageAuto.calculateAccrual",
            input: RegimeIn661(placementTime: placement, country: "US", railcarCount: 1))
        async let caTask: RegimeQuote661? = EusoTripAPI.shared.query(
            "railDemurrageAuto.calculateAccrual",
            input: RegimeIn661(placementTime: placement, country: "CA", railcarCount: 1))
        async let mxTask: RegimeQuote661? = EusoTripAPI.shared.query(
            "railDemurrageAuto.calculateAccrual",
            input: RegimeIn661(placementTime: placement, country: "MX", railcarCount: 1))

        let us = (try? await usTask) ?? nil
        let ca = (try? await caTask) ?? nil
        let mx = (try? await mxTask) ?? nil
        var table = regimes
        if let us { table["US"] = us }
        if let ca { table["CA"] = ca }
        if let mx { table["MX"] = mx }
        regimes = table

        do {
            let fresh = try await boardTask
            board = fresh
            lastSyncedAt = Date()
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }

        loading = false
    }

    private func loadCandidates() async {
        loadingCandidates = true
        candidatesError = nil
        do {
            let rows: [RunCandidate661] = try await EusoTripAPI.shared.query(
                "railShipments.getRailShipments",
                input: CandidatesIn661(limit: 50, offset: 0))
            candidates = rows
        } catch {
            candidates = []
            candidatesError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loadingCandidates = false
    }

    private func loadReport() async {
        loadingReport = true
        reportError = nil
        do {
            let r: DwellReport661 = try await EusoTripAPI.shared.query(
                "railDemurrageAuto.reportByDwellReason",
                input: DwellReportIn661(periodDays: 30))
            report = r
        } catch {
            reportError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loadingReport = false
    }

    private func addManualId() {
        let trimmed = manualEntry.trimmingCharacters(in: .whitespaces)
        guard let sid = Int(trimmed), sid > 0 else { return }
        if !manualIds.contains(sid) && !candidates.contains(where: { Int($0.id) == sid }) {
            manualIds.append(sid)
        }
        selection.insert(sid)
        manualEntry = ""
    }

    /// MUTATION · POST · ONLINE_ONLY.
    ///
    /// The bulk verb on the server writes nothing, so the run is committed one
    /// shipment at a time through the writer that actually upserts the charge
    /// row and inserts its audit entry. Sequential on purpose: the progress
    /// counter, the per-car result and the per-car failure are all real, and a
    /// FORBIDDEN on one shipment never masks a success on another.
    private func commitRun() async {
        guard reach.isOnline else {
            commitBlocked = "Offline — a billable demurrage charge and its audit entry never queue. Nothing was sent and nothing was held."
            return
        }
        let targets = selectedTargets
        guard !targets.isEmpty else {
            commitBlocked = "Select at least one shipment before committing the run."
            return
        }

        commitBlocked = nil
        commitLines = []
        commitDone = 0
        commitTotal = targets.count
        committing = true

        for target in targets {
            do {
                let out: AccrualWrite661 = try await EusoTripAPI.shared.mutation(
                    "railShipments.calculateRailDemurrage",
                    input: ShipmentIdIn661(shipmentId: target.id))
                commitLines.append(CommitLine661(
                    id: target.id,
                    label: target.label,
                    posted: out.demurrage?.value,
                    chargeableHours: out.chargeableHours?.value,
                    freeTimeHours: out.freeTimeHours?.value,
                    facilityState: out.facilityState,
                    serverMessage: out.message,
                    failure: nil))
            } catch {
                let msg = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
                commitLines.append(CommitLine661(
                    id: target.id,
                    label: target.label,
                    posted: nil,
                    chargeableHours: nil,
                    freeTimeHours: nil,
                    facilityState: nil,
                    serverMessage: nil,
                    failure: msg))
            }
            commitDone += 1
        }

        committing = false

        let postedCount = commitLines.filter { ($0.posted ?? 0) > 0 }.count
        let postedTotal = commitLines.reduce(0.0) { $0 + max(0, $1.posted ?? 0) }
        showToast(postedCount > 0
                  ? "Posted \(money(postedTotal)) across \(postedCount) shipment\(postedCount == 1 ? "" : "s")"
                  : "Run complete — nothing was chargeable")

        // No charge-generated broadcast exists on the server, so the board is
        // re-read rather than waited on.
        await load()
    }

    // MARK: - Formatting

    private func money(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = (v.rounded() == v) ? 0 : 2
        let n = f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
        return "$\(n)"
    }

    private func trimHours(_ v: Double) -> String {
        if v.rounded() == v { return "\(Int(v))h" }
        return String(format: "%.1fh", v)
    }
}

// MARK: - ISO helper

private func isoNow661() -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.string(from: Date())
}

#Preview("661 · Rail Demurrage Charge Run · Night") {
    RailDemurrageChargeGeneration_661(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("661 · Rail Demurrage Charge Run · Light") {
    RailDemurrageChargeGeneration_661(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
