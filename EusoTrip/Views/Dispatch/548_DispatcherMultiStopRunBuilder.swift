//
//  548_DispatcherMultiStopRunBuilder.swift
//  EusoTrip 2027 · App target · LIVE DATA LAYER
//
//  CATALOG IDENTITY: 548 Dispatcher Multi-Stop Run Builder
//  (04 Dispatcher · DISPATCHER vantage · Aurora · RM)
//  MIRRORS: "04 Dispatcher/Light-SVG/548 Dispatcher Multi-Stop Run Builder.svg"
//  (+ the Dark twin). The Swift below is a faithful mirror of that SVG:
//  DETAIL TopBar -> HOS BUDGET-CONSUMPTION hero (the 11h drive and 14h duty
//  clocks drawn as segmented budget tracks the run eats leg by leg, under the
//  planned-drive figure — its caption sits BELOW the figure as an 11pt tertiary
//  line, "planned drive against an 11h clock", instead of beside it where the
//  two collided — and the slack cluster) -> live CONFLICT STRIP -> numbered STOP
//  LADDER (icon chips are the sequence nodes, gradient rail connects them, right
//  cluster is distance + dwell, never money) -> ESang row -> CTA pair. 532
//  assigns ONE load; nothing on the platform composed a run. Deliberately unlike
//  401 Kanban (stage lanes), 532 Assign Driver (single-load commit), 536 Fleet
//  Map (map hero), 545 Maintenance Due (depletion roster).
//
//  ── DESIGN-SYSTEM PORT 2026-08-26 ────────────────────────────────────────
//  Raw/system colors converted to the EusoTrip design system (Theme.Palette,
//  Brand, LinearGradient.primary/.diagonal, Space, Radius) and the screen
//  rehomed onto the house Shell + BottomNav idiom (see
//  Dpch730_DispatcherOpsQuartet.swift). The hand-rolled bottom nav, which
//  called DispatchNavDispatcher.handle(_:) directly, is replaced by the
//  canonical BottomNav(leading: DispatchNavRoute.leading(current: .board),
//  trailing: DispatchNavRoute.trailing(current: .board)) — same four labels,
//  same dispatcher, routed through the injected dispatchNavHandler.
//  NOTHING in the data layer moved: every endpoint string, every Decodable and
//  its shape, every error branch and every .disabled(...) gate survives.
//
//  ── LOAD CONTEXT (the defect under the defect) ───────────────────────────
//  Every read on this screen keys off a loadId, and the screen had no way to
//  obtain one — which is part of why it could only ever have been a mockup. The
//  view takes an optional `loadId` so a real navigation can hand one in, and
//  falls back to resolving the first active load from:
//    dispatchRole.getDispatchBoard      EXISTS dispatchRole.ts:506
//        -> {loads:[{id, loadNumber, status, shipper, origin, destination, rate,
//           pickupDate, catalystId}], summary:{total, byStatus:{…}}}.
//  This read is NOT in the original manifest; it was added because without it
//  nothing on this surface can be real, and it is verified on disk like the rest.
//
//  WIRED READS (every line number re-verified on disk 2026-08-17; all confirmed
//  at the cited line, no citation was stale):
//    loadStops.getByLoadId                     EXISTS loadStops.ts:45
//        -> the STOP LADDER. Returns a BARE ARRAY of full load_stops rows. The
//           router explicitly coerces `lat`,`lng`,`estimatedWeight`,
//           `actualWeight`,`distanceFromPrev` from DECIMAL strings to numbers,
//           so those are Doubles here — but ONLY on this endpoint. `dwellMinutes`
//           is an int column and is not coerced.
//    loadStops.getSummary                      EXISTS loadStops.ts:341
//        -> the draft caption and the run total.
//           {totalStops, completedStops, pickups, deliveries, progress}.
//    hos.getCurrentStatus                      EXISTS hos.ts:179
//        -> the driver clock the budget starts from.
//           TRAP CAUGHT: this payload carries BOTH shapes at once —
//           `limits.driving/onDuty/cycle` are {used, limit, remaining} in
//           MINUTES as numbers, while the sibling top-level `drivingRemaining` /
//           `onDutyRemaining` / `cycleRemaining` are preformatted STRINGS
//           ("10h 30m"). The budget maths uses the minute numbers; the display
//           strings are shown verbatim and never parsed into a fake float.
//           (Flagged for the counter-party row: `statusStartTime` is always
//           "now" and `lastRestartDate` is a hardcoded "" — neither is read.)
//    routeOptimization.getHosCompliantRouting  EXISTS routeOptimization.ts:1086
//        -> the BUDGET SEGMENTS and the conflict strip. Its `segments` are
//           {type: drive|break|rest|fuel, startMile, endMile, durationMinutes,
//           note, estimatedTime?} — a real, per-segment consumption series,
//           which is exactly what the two tracks draw.
//           TRAP CAUGHT: it has TWO structurally different returns. The geocode-
//           failure path returns only {error, segments, totalMiles, compliant,
//           violations} — `totalDrivingHours`, `summary` and `hosLimits` are
//           ABSENT, not null. Every field outside that five is Optional here.
//           That optionality is load-bearing and is NOT tidied into one shape.
//
//  WIRED WRITES:
//    routeOptimization.optimizeMultiStop       EXISTS routeOptimization.ts:625
//        -> the "Optimize" CTA. Real TSP resequence; returns `orderedStops`
//           with a real `sequence`, plus `savings` (NULL on the error path) and
//           `hosWarning` (String OR null). The ladder is reordered to match.
//           (Flagged for the counter-party row: its `priority` and `vehicleType`
//           inputs are accepted by the schema and silently ignored, and
//           `returnToOrigin: false` does not actually suppress the depot leg.)
//    loadStops.setStops                        EXISTS loadStops.ts:122
//        -> the "Commit run" CTA. This is the real composition commit: it
//           persists the ordered stop rows. Requires min(2) stops.
//    loadStops.reorder                         EXISTS loadStops.ts:280
//        -> a single-stop resequence against the real numeric stopId.
//
//  ── HONEST RE-SOURCING (composition preserved, provenance corrected) ─────
//  1. THE LEG COLUMN. The SVG literals read "+0:34 · 28 mi" — a per-leg DRIVE
//     TIME the stop row does not carry. `load_stops` returns a real
//     `distanceFromPrev` and a real `dwellMinutes`, so the right cluster prints
//     those two real figures. A per-leg drive time would need one hereMaps.route
//     call per leg, which this screen does not make; rather than print an
//     invented duration it prints the distance the server does return.
//  2. THE CONFLICT STRIP is driven by the HOS violations
//     getHosCompliantRouting actually computes — see the unsourceable note below
//     for why it is no longer a trailer-compatibility strip.
//
//  ── UNSOURCEABLE · STATED · NOT FAKED ────────────────────────────────────
//  THE TRAILER-COMPATIBILITY CONFLICT ("food-grade after UN1203 — wash
//  required") HAS NO SERVER SOURCE. Both cited procedures were read in full:
//    trailerRegulatory.getProductsByTrailerType     EXISTS trailerRegulatory.ts:17
//    trailerRegulatory.getFoodGradeTankRegulations  EXISTS trailerRegulatory.ts:312
//  Neither takes a stop sequence, and neither can detect an incompatibility
//  between consecutive commodities. They are pure static-content lookups with no
//  DB, no ctx and no async: getProductsByTrailerType is a Record lookup whose
//  `supportsOther` is hardcoded `true`, and getFoodGradeTankRegulations returns
//  `alerts: []` UNCONDITIONALLY (trailerRegulatory.ts:370) with only `isDairy` /
//  `isKosher` / `isOrganic` toggling which static paragraphs appear. There is no
//  sequence-compatibility verb anywhere on the server. The strip therefore
//  reports the conflict the platform CAN compute — the HOS violations from
//  getHosCompliantRouting — and the commit gate keys off that real signal.
//  Proposed server shape, filed as a counter-party row and NOT built here:
//    trailerRegulatory.checkSequenceCompatibility: protectedProcedure
//      .input(z.object({ trailerType: z.string(),
//                        sequence: z.array(z.object({ stopId: z.number(),
//                                                     productId: z.string() })) }))
//      .query(): Array<{ afterStopId: number, beforeStopId: number,
//                        severity: 'wash_required'|'prohibited'|'advisory',
//                        reason: string, remedy: string }>
//
//  ── CITED BUT DELIBERATELY NOT CALLED (each with its reason) ─────────────
//    dispatchPlanner.assignLoad     EXISTS dispatchPlanner.ts:187
//      NOT WIRED — THE HONEST GAP ON THIS SURFACE. It requires {driverId, date
//      (strict YYYY-MM-DD), slotIndex, loadId}. This composition collects NO
//      driver and NO planner slot — there is no driver picker and no slot picker
//      on 548, and the SVG has none. Binding a driver to a run using a driverId
//      and slot the client invented is precisely the forbidden move, and it
//      would run the FMCSA out-of-service / hazmat-insurance / CDL-expiry
//      PRODUCTION GATES against fabricated input. Driver binding stays where it
//      already lives (532 Assign Driver); this board commits the SEQUENCE. The
//      gap is stated on screen, not papered over.
//    loadStops.add / update / remove EXISTS loadStops.ts:69 / :188 / :318
//      NOT WIRED. This composition has no add, edit or delete control — the SVG
//      has none. They are verified and left for the editor surface that has them.
//    hereMaps.route                 EXISTS hereMaps.ts:220
//    hereMaps.trafficFlow           EXISTS hereMaps.ts:406
//      NOT WIRED. getHosCompliantRouting already returns the routed mileage and
//      the per-segment durations the tracks need, and per-leg re-quoting would
//      be one call per leg. Kept in the manifest as verified.
//    hos.getFleetHOS                EXISTS hos.ts:426
//      NOT WIRED. This screen budgets ONE driver's clock; getCurrentStatus is
//      the right scope. Kept in the manifest as verified.
//    esangCoach.forScreen           EXISTS esangCoach.ts:264
//      NOT CALLABLE FROM ANY DISPATCHER SCREEN. Its `screen` input is
//      SCREEN_ENUM (esangCoach.ts:112-125) = home | trips | earnings | tax |
//      dvir | availability | missions | badges | referrals | zeun | haul |
//      active-trip — every member a DRIVER surface, so any call from here fails
//      zod validation with BAD_REQUEST. The ESang row is a Button in this
//      composition, so it is `.disabled` and states why rather than being a dead
//      tap; its text is derived from this screen's own live reads.
//      Counter-party row filed: add a dispatch token to SCREEN_ENUM.
//
//  DOCTRINE DRIFT (reported, not silently followed): the 2026-06-02 operator
//  directive cites hereMaps.route:89, hereMaps.evaluateFences:177 and
//  tracking.getGeofenceEvents:439; on disk this fire those sit at
//  hereMaps.ts:220, hereMaps.ts:372 and tracking.ts:465. Real code wins, and
//  all three were re-confirmed at the corrected lines on 2026-08-17.
//  PERSISTENCE + REALTIME: setStops persists the ordered stop rows; the
//  assignment write (elsewhere) emits WS_EVENTS.DISPATCH_ASSIGNMENT_NEW
//  shared/websocket-events.ts:201 + WS_EVENTS.DISPATCH_BOARD_UPDATE
//  shared/websocket-events.ts:205 on WS_CHANNELS.DISPATCH(companyId)
//  shared/websocket-events.ts:577.
//  CHAIN: PARTIAL — a stop reordered after the driver has the run does not
//  re-notify. STUB carried below (never silently faked):
//    // shared/websocket-events.ts:209
//    DISPATCH_RESCHEDULE: 'dispatch:reschedule',
//    // loadStops.ts — inside setStops, after the ordered rows persist:
//    emitToChannel(WS_CHANNELS.DISPATCH(companyId), WS_EVENTS.DISPATCH_RESCHEDULE, {
//      loadId: string; driverId: string; stops: Array<{ sequence: number; stopId: string }>;
//      resequencedAt: string;
//    })
//  RBAC: protectedProcedure, dispatch scope.
//  OFFLINE POLICY: READ_CACHED(120s) for the board and stop list; stop reorder and setStops are QUEUE(dispatch); route optimization is ONLINE_ONLY because HOS-compliant routing must not be extrapolated.
//  transportMode=truck; country US (FMCSA 11h/14h ELD ruleset).
//  NAV (REAL · DispatchNavRoute, DispatchNavController.swift:44/87/92):
//    Home(house) · Board(rectangle.split.3x1.fill · current) · [orb] ·
//    Comms(bubble.left.and.bubble.right.fill) · Me(person), rendered by the
//    house BottomNav through Shell.
//  Persona Aurora Freight Lines · Renée Marquette (RM) composing; shipper-of-
//  record Eusorone Technologies (Diego Usoro · DU). Truck IDs LD-YYMMDD-XXXXX.
//
//  HONEST STATUS: 5 reads + 3 writes live (1 read added to resolve load
//  context) · 1 named gap (DISPATCH_RESCHEDULE emit) carried · 1 measurement
//  (trailer-compatibility conflict) UNSOURCEABLE and re-sourced to real HOS
//  violations with the reason stated · 8 verified procedures deliberately
//  unwired with reasons, dispatchPlanner.assignLoad chief among them. No
//  literal row arrays. No stubs, no placeholder literals, no invented fallbacks.
//  One ✦ eyebrow. One iridescent hairline. No emoji icons. No retired names.
//  — Mike "Diego" Usoro / Eusorone Technologies, Inc. · 2026-08-26 EDT.
//

import SwiftUI

// MARK: - WCAG text pairs for tinted washes
//
// These are the WCAG-contrast-tested TEXT pair for small text sitting on a
// tinted wash: the Palette exposes the washes (tintDanger / tintWarning /
// tintSuccess / tintInfo) but no matching text token, so replacing these with
// Brand.* would drop small-text contrast on light surfaces. Values are the
// SVG's own. `violetText_548` is the fifth member of the same family — the
// escort/violet pair the SVG uses for the pickup chip numeral (line 65); the
// Palette has neither a tintEscort wash nor its text pair, so both are mixed
// locally below.
private let dangerText_548  = Color(red: 0.824, green: 0.204, blue: 0.165) // #D2342A
private let warnText_548    = Color(red: 0.698, green: 0.451, blue: 0.0)   // #B27300
private let successText_548 = Color(red: 0.0,   green: 0.588, blue: 0.420) // #00966B
private let violetText_548  = Color(red: 0.482, green: 0.122, blue: 0.635) // #7B1FA2
private let infoText_548    = Color(red: 0.084, green: 0.396, blue: 0.753) // #1565C0

// MARK: - House shell (idiom copied from Dpch730_DispatcherOpsQuartet.swift)

private struct ShellNav<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: DispatchNavRoute.leading(current: .board),
                trailing: DispatchNavRoute.trailing(current: .board),
                orbState: .idle
            )
        }
    }
}

// MARK: - Wire decoders (shapes copied from the server's own return statements)

/// dispatchRole.getDispatchBoard — dispatchRole.ts:506. Resolves load context.
private struct DispatchBoard_548: Decodable {
    let loads: [BoardLoad_548]
}

private struct BoardLoad_548: Decodable {
    let id: String?
    let loadNumber: String?
    let status: String?
    let origin: String?
    let destination: String?
}

/// loadStops.getByLoadId — loadStops.ts:45. Bare array of full load_stops rows.
/// lat/lng/estimatedWeight/distanceFromPrev are coerced to numbers BY THIS
/// ENDPOINT ONLY; dwellMinutes is an int column and is not coerced.
private struct StopRow_548: Decodable {
    let id: Int
    let loadId: Int?
    let sequence: Int?
    /// pickup|delivery|fuel|rest|scale|inspection|crossdock|relay|customs
    let stopType: String?
    let facilityName: String?
    let address: String?
    let city: String?
    let state: String?
    let zipCode: String?
    let lat: Double?
    let lng: Double?
    let appointmentStart: String?
    let appointmentEnd: String?
    /// pending|en_route|arrived|loading|unloading|completed|skipped
    let status: String?
    let notes: String?
    let referenceNumber: String?
    let estimatedWeight: Double?
    let dwellMinutes: Int?
    let distanceFromPrev: Double?
}

/// loadStops.getSummary — loadStops.ts:341.
private struct StopSummary_548: Decodable {
    let totalStops: Int?
    let completedStops: Int?
    let pickups: Int?
    let deliveries: Int?
    let progress: Double?
}

/// hos.getCurrentStatus — hos.ts:179. Carries minute-numbers AND display strings.
private struct HosStatus_548: Decodable {
    let currentStatus: String?
    let limits: HosLimits_548?
    let canDrive: Bool?
    let breakRequired: Bool?
    let drivingRemaining: String?     // preformatted, e.g. "10h 30m"
    let onDutyRemaining: String?
    let cycleRemaining: String?
    let violations: [HosViolation_548]?
}

private struct HosLimits_548: Decodable {
    let driving: HosBucket_548?
    let onDuty: HosBucket_548?
    let cycle: HosBucket_548?
}

/// All three values are MINUTES.
private struct HosBucket_548: Decodable {
    let used: Double?
    let limit: Double?
    let remaining: Double?
}

private struct HosViolation_548: Decodable {
    let type: String?
    let description: String?
    let severity: String?             // warning | violation
}

/// routeOptimization.getHosCompliantRouting — routeOptimization.ts:1086.
/// The geocode-failure path OMITS most of these, so everything outside
/// {error, segments, totalMiles, compliant, violations} is Optional.
private struct HosRouting_548: Decodable {
    let error: String?
    let totalMiles: Double?
    let totalDrivingHours: Double?
    let totalTripHours: Double?
    let totalTripDuration: String?
    let compliant: Bool?
    let violations: [String]?
    let segments: [RouteSegment_548]?
    let hosLimits: RoutingLimits_548?
}

private struct RouteSegment_548: Decodable {
    let type: String?                 // drive | break | rest | fuel
    let startMile: Double?
    let endMile: Double?
    let durationMinutes: Double?
    let note: String?
    let estimatedTime: String?
}

private struct RoutingLimits_548: Decodable {
    let drivingLimit: Double?
    let dutyLimit: Double?
    let cycleRemaining: Double?
}

/// routeOptimization.optimizeMultiStop — routeOptimization.ts:625.
/// `savings` and `hosWarning` are null on the error path.
private struct OptimizeResult_548: Decodable {
    let error: String?
    let orderedStops: [OrderedStop_548]?
    let totalMiles: Double?
    let totalHours: Double?
    let totalDuration: String?
    let hosCompliant: Bool?
    let hosWarning: String?
    let savings: OptimizeSavings_548?
}

private struct OrderedStop_548: Decodable {
    let sequence: Int?
    let name: String?
    let lat: Double?
    let lng: Double?
}

private struct OptimizeSavings_548: Decodable {
    let milesSaved: Double?
    let timeSaved: String?
    let fuelCostSaved: Double?
}

private struct SetStopsResult_548: Decodable { let count: Int? }
private struct SuccessResult_548: Decodable { let success: Bool? }

// MARK: - View models

/// What the drive-clock slack figure actually says, so its colour can be
/// derived from that state instead of being hardcoded to success:
/// `.healthy` = real minutes left and no break due · `.over` = the clock is
/// already negative · `.neutral` = nothing left, a break is due first, or the
/// clock was not read. Zero and unknown are NOT healthy.
private enum SlackTone_548 { case healthy, over, neutral }

/// One block the run eats out of an HOS budget track. Sourced from
/// routeOptimization.getHosCompliantRouting segments (routeOptimization.ts:1086).
private struct BudgetSegment_548: Identifiable {
    let id = UUID()
    let hours: Double
    enum Kind { case drive, dwell, conflict }
    let kind: Kind
}

/// One rung of the stop ladder. loadStops.getByLoadId (loadStops.ts:45).
private struct Stop_548: Identifiable {
    let id = UUID()
    let stopId: Int          // the REAL numeric stopId, for reorder/setStops
    let seq: String
    let sequence: Int
    let stopType: String
    let title: String
    let detail: String
    let leg: String          // real distanceFromPrev
    let dwell: String        // real dwellMinutes
    enum Tone { case load, drop, conflict }
    let tone: Tone
    // Carried so setStops can persist the row without losing its fields.
    let facilityName: String?
    let address: String?
    let city: String?
    let state: String?
    let zipCode: String?
    let lat: Double?
    let lng: Double?
    let appointmentStart: String?
    let appointmentEnd: String?
    let notes: String?
    let referenceNumber: String?
    let estimatedWeight: Double?
}

// `private` at file scope: this view model's published properties are typed with
// the file-private row structs above, so the class must be no more accessible
// than they are. (The inherited declaration was `internal`, which is a hard
// access-control error — further evidence this file had never been compiled.)
@MainActor
private final class RunBuilderVM_548: ObservableObject {

    // MISSING EMIT — carried explicitly, never silently faked.
    // A stop resequenced AFTER the driver already holds the run does not
    // re-notify, so the driver can arrive at the old stop 2 (CHAIN: PARTIAL).
    let STUB_DISPATCH_RESCHEDULE_EMIT = "loadStops.setStops needs DISPATCH_RESCHEDULE (shared/websocket-events.ts:209)"
    let esangBlockedReason = "ESang has no dispatch screen token — esangCoach.forScreen only accepts driver surfaces"

    // ---- Load-cycle state (house pattern, per 545) ------------------------
    @Published var loading = true
    @Published var loadError: String?
    @Published var working = false
    @Published var actionNote: String?

    // ---- TopBar · loadStops.getSummary loadStops.ts:341 -------------------
    @Published var draftCaption = "—"

    // ---- Clock budget hero ------------------------------------------------
    @Published var budgetLabel   = "CLOCK BUDGET"
    @Published var plannedDrive  = "—"
    // Caption sits BELOW the figure (11pt tertiary) — beside it, the two collided.
    @Published var plannedCaption = "planned drive against an 11h clock"
    @Published var slack         = "—"
    @Published var slackNote     = ""
    /// The state the drive clock is ACTUALLY in, taken from the minute number
    /// the server sends beside the display string. The slack figure's colour is
    /// derived from this and never hardcoded, so "0h 00m", a negative clock, a
    /// required break or an unread clock cannot paint as healthy.
    @Published var slackTone: SlackTone_548 = .neutral

    @Published var driveLabel    = "DRIVE · 11h"
    @Published var driveRatio    = "—"
    @Published var driveBudgetHours: Double = 11.0
    @Published var driveSegments: [BudgetSegment_548] = []

    @Published var dutyLabel     = "DUTY · 14h"
    @Published var dutyRatio     = "—"
    @Published var dutyBudgetHours: Double = 14.0
    @Published var dutySegments: [BudgetSegment_548] = []

    // ---- Conflict strip ---------------------------------------------------
    // Driven by the HOS violations getHosCompliantRouting actually computes.
    // The trailer-compatibility conflict has no server source — see the header.
    @Published var conflictOpen = false
    @Published var conflictText = ""

    // ---- Stop ladder ------------------------------------------------------
    @Published var ladderLabel   = "STOP LADDER"
    @Published var ladderSource  = "loadStops.ts:45"
    @Published var stops: [Stop_548] = []
    @Published var runTotal      = ""
    /// Set once "Optimize" has changed the order and the change is uncommitted.
    @Published var pendingResequence = false

    // ---- ESang row (derived from this screen's own reads) ------------------
    @Published var esangTitle    = "Run state"
    @Published var esangBody     = "Reading the run…"

    // ---- CTA pair ---------------------------------------------------------
    @Published var commitTitle   = "Commit run"
    @Published var optimizeTitle = "Optimize"

    /// The load this board is composing.
    private(set) var activeLoadId: Int?
    private var originLabel: String?
    private var destinationLabel: String?

    private let api = EusoTripAPI.shared

    /// Committing needs at least two stops (loadStops.setStops enforces min(2))
    /// and refuses while a real HOS violation is open.
    var canCommit: Bool { activeLoadId != nil && stops.count >= 2 && !conflictOpen }

    var commitBlockedReason: String {
        if activeLoadId == nil { return "No load in context — open this board from a load on the dispatch board." }
        if stops.count < 2 { return "A run needs at least two stops before it can be committed (loadStops.setStops enforces a minimum of 2)." }
        if conflictOpen { return conflictText }
        return ""
    }

    // MARK: Load — ONE tick

    func load(loadId: Int?) async {
        loading = true
        loadError = nil
        var failures: [String] = []

        struct ByLoadIn: Encodable { let loadId: Int }
        struct BoardIn: Encodable { let priority: String }
        struct HosIn: Encodable { let driverId: String? }
        struct RoutingIn: Encodable {
            let origin: String
            let destination: String
            let currentDrivingHours: Double
            let currentDutyHours: Double
        }

        // 0 · resolve the load context
        if let loadId {
            activeLoadId = loadId
        } else {
            do {
                let board: DispatchBoard_548 = try await api.query(
                    "dispatchRole.getDispatchBoard", input: BoardIn(priority: "all"))
                if let first = board.loads.first {
                    activeLoadId = first.id.flatMap { Int($0) }
                    originLabel = first.origin
                    destinationLabel = first.destination
                    budgetLabel = "CLOCK BUDGET · \(first.loadNumber ?? "LOAD \(first.id ?? "—")")"
                }
            } catch {
                failures.append("dispatch board")
            }
        }

        guard let activeLoadId else {
            loadError = "No load in context. Open the run builder from a load on the dispatch board."
            loading = false
            return
        }

        // 1 · the stop ladder
        do {
            let rows: [StopRow_548] = try await api.query(
                "loadStops.getByLoadId", input: ByLoadIn(loadId: activeLoadId))
            stops = rows
                .sorted { ($0.sequence ?? 0) < ($1.sequence ?? 0) }
                .map { Self.stop(from: $0) }
            if originLabel == nil { originLabel = Self.place(rows.first) }
            if destinationLabel == nil { destinationLabel = Self.place(rows.last) }
            ladderLabel = "STOP LADDER · \(stops.count) STOP\(stops.count == 1 ? "" : "S")"
        } catch {
            stops = []
            failures.append("stops")
        }

        // 2 · the draft caption + run total
        do {
            let s: StopSummary_548 = try await api.query(
                "loadStops.getSummary", input: ByLoadIn(loadId: activeLoadId))
            let total = s.totalStops ?? stops.count
            draftCaption = "DRAFT · \(total) STOP\(total == 1 ? "" : "S")"
            var parts: [String] = ["\(s.pickups ?? 0) pickup\((s.pickups ?? 0) == 1 ? "" : "s")",
                                   "\(s.deliveries ?? 0) deliver\((s.deliveries ?? 0) == 1 ? "y" : "ies")"]
            if let done = s.completedStops, done > 0 { parts.append("\(done) done") }
            if let p = s.progress { parts.append(String(format: "%.0f%% complete", p)) }
            runTotal = "Run total " + parts.joined(separator: " · ")
        } catch {
            draftCaption = "DRAFT · \(stops.count) STOP\(stops.count == 1 ? "" : "S")"
            failures.append("summary")
        }

        // 3 · the driver clock the budget starts from
        var drivingUsedMin: Double = 0
        var dutyUsedMin: Double = 0
        // Neutral until the clock is actually read, so a stale healthy tone can
        // never outlive the figure it was derived from.
        slackTone = .neutral
        do {
            let hos: HosStatus_548 = try await api.query("hos.getCurrentStatus", input: HosIn(driverId: nil))
            drivingUsedMin = hos.limits?.driving?.used ?? 0
            dutyUsedMin = hos.limits?.onDuty?.used ?? 0
            if let dl = hos.limits?.driving?.limit, dl > 0 { driveBudgetHours = dl / 60.0 }
            if let ol = hos.limits?.onDuty?.limit, ol > 0 { dutyBudgetHours = ol / 60.0 }
            driveLabel = String(format: "DRIVE · %.0fh", driveBudgetHours)
            dutyLabel = String(format: "DUTY · %.0fh", dutyBudgetHours)
            // Display strings verbatim — never parsed into a fake float.
            slack = hos.drivingRemaining ?? "—"
            slackNote = hos.breakRequired == true ? "break required first" : "drive clock remaining"
            // The TONE comes from the minute number the same payload carries
            // (limits.driving.remaining), not from scraping the display string
            // and not from a hardcoded colour. No number, no verdict.
            if let remainingMin = hos.limits?.driving?.remaining {
                if remainingMin < 0 {
                    slackTone = .over
                } else if remainingMin > 0 && hos.breakRequired != true {
                    slackTone = .healthy
                } else {
                    slackTone = .neutral      // nothing left, or a break is due first
                }
            } else {
                slackTone = .neutral          // the clock did not report a figure
            }
        } catch {
            failures.append("driver clock")
        }

        // 4 · the budget segments + the real conflict signal
        if let origin = originLabel, let destination = destinationLabel,
           !origin.isEmpty, !destination.isEmpty {
            do {
                let r: HosRouting_548 = try await api.query(
                    "routeOptimization.getHosCompliantRouting",
                    input: RoutingIn(origin: origin, destination: destination,
                                     currentDrivingHours: drivingUsedMin / 60.0,
                                     currentDutyHours: dutyUsedMin / 60.0))
                if let err = r.error {
                    conflictOpen = true
                    conflictText = "Route could not be planned: \(err)"
                } else {
                    let segs = r.segments ?? []
                    driveSegments = segs
                        .filter { ($0.type ?? "") == "drive" }
                        .map { BudgetSegment_548(hours: ($0.durationMinutes ?? 0) / 60.0, kind: .drive) }
                    dutySegments = segs.map {
                        BudgetSegment_548(hours: ($0.durationMinutes ?? 0) / 60.0,
                                          kind: Self.kind(for: $0.type))
                    }
                    if let dl = r.hosLimits?.drivingLimit, dl > 0 { driveBudgetHours = dl }
                    if let ul = r.hosLimits?.dutyLimit, ul > 0 { dutyBudgetHours = ul }
                    driveLabel = String(format: "DRIVE · %.0fh", driveBudgetHours)
                    dutyLabel = String(format: "DUTY · %.0fh", dutyBudgetHours)

                    let driveHours = r.totalDrivingHours ?? driveSegments.reduce(0) { $0 + $1.hours }
                    let tripHours = r.totalTripHours ?? dutySegments.reduce(0) { $0 + $1.hours }
                    plannedDrive = Self.hm(driveHours)
                    plannedCaption = String(format: "planned drive against an %.0fh clock", driveBudgetHours)
                    driveRatio = "\(Self.hm(driveHours)) / \(String(format: "%.0fh", driveBudgetHours))"
                    dutyRatio = "\(Self.hm(tripHours)) / \(String(format: "%.0fh", dutyBudgetHours))"
                    if let miles = r.totalMiles {
                        runTotal = String(format: "Run total %.0f mi · ", miles) + runTotal.replacingOccurrences(of: "Run total ", with: "")
                    }

                    let violations = r.violations ?? []
                    if r.compliant == false || !violations.isEmpty {
                        conflictOpen = true
                        conflictText = violations.first ?? "This run does not fit the driver's HOS clock"
                    } else {
                        conflictOpen = false
                        conflictText = ""
                    }
                }
            } catch {
                failures.append("HOS routing")
            }
        }

        // ESang row — over the numbers actually loaded on this screen.
        esangTitle = stops.isEmpty
            ? "No stops on this run yet"
            : "\(stops.count) stop\(stops.count == 1 ? "" : "s") composed"
        esangBody = conflictOpen
            ? conflictText
            : [plannedDrive.isEmpty ? nil : "\(plannedDrive) planned drive",
               slack == "—" ? nil : "\(slack) left on the clock"]
                .compactMap { $0 }.joined(separator: " · ")
        if esangBody.isEmpty { esangBody = esangBlockedReason }

        if !failures.isEmpty && stops.isEmpty {
            loadError = "Couldn't build the run (\(failures.joined(separator: ", ")))."
        }
        loading = false
    }

    // MARK: Actions

    /// routeOptimization.optimizeMultiStop:625 — a real TSP resequence. The
    /// ladder is reordered to the returned order; nothing persists until commit.
    func optimize() async {
        guard stops.count >= 2 else {
            actionNote = "Nothing to optimize — a run needs at least two stops."
            return
        }
        working = true
        actionNote = nil
        struct StopIn: Encodable {
            let location: String
            let name: String
            let serviceMinutes: Int
        }
        struct In: Encodable {
            let origin: String
            let stops: [StopIn]
            let maxDrivingHours: Double
        }
        let origin = originLabel ?? stops.first?.title ?? ""
        let payload = stops.map {
            StopIn(location: Self.locationString($0), name: $0.title, serviceMinutes: Self.dwellMinutes($0))
        }
        do {
            let r: OptimizeResult_548 = try await api.mutation(
                "routeOptimization.optimizeMultiStop",
                input: In(origin: origin, stops: payload, maxDrivingHours: driveBudgetHours))
            if let err = r.error {
                actionNote = "Couldn't optimize: \(err)"
            } else if let ordered = r.orderedStops, !ordered.isEmpty {
                // Reorder the ladder to the returned sequence, matching by name.
                var remaining = stops
                var reordered: [Stop_548] = []
                for o in ordered.sorted(by: { ($0.sequence ?? 0) < ($1.sequence ?? 0) }) {
                    if let idx = remaining.firstIndex(where: { $0.title == (o.name ?? "") }) {
                        reordered.append(remaining.remove(at: idx))
                    }
                }
                reordered.append(contentsOf: remaining)
                stops = reordered.enumerated().map { Self.renumber($0.element, to: $0.offset + 1) }
                pendingResequence = true
                var bits: [String] = []
                if let m = r.savings?.milesSaved, m > 0 { bits.append(String(format: "%.0f mi saved", m)) }
                if let t = r.savings?.timeSaved, !t.isEmpty { bits.append("\(t) saved") }
                if let w = r.hosWarning, !w.isEmpty { bits.append(w) }
                actionNote = (bits.isEmpty ? "Resequenced." : "Resequenced · " + bits.joined(separator: " · "))
                    + " Commit to persist the new order."
            } else {
                actionNote = "Optimizer returned no order."
            }
        } catch {
            actionNote = (error as? EusoTripAPIError)?.errorDescription ?? "Couldn't optimize this run."
        }
        working = false
    }

    /// loadStops.setStops:122 — THE COMMIT. Persists the ordered stop rows.
    /// This board commits the SEQUENCE; binding a driver needs a driverId and a
    /// planner slot this composition does not collect (see the header).
    func commitRun() async {
        guard let loadId = activeLoadId, canCommit else {
            actionNote = commitBlockedReason
            return
        }
        working = true
        actionNote = nil
        struct StopIn: Encodable {
            let stopType: String
            let facilityName: String?
            let address: String?
            let city: String?
            let state: String?
            let zipCode: String?
            let lat: Double?
            let lng: Double?
            let appointmentStart: String?
            let appointmentEnd: String?
            let notes: String?
            let referenceNumber: String?
            let estimatedWeight: Double?
        }
        struct In: Encodable { let loadId: Int; let stops: [StopIn] }
        let payload = stops.map {
            StopIn(stopType: $0.stopType,
                   facilityName: $0.facilityName, address: $0.address,
                   city: $0.city, state: $0.state, zipCode: $0.zipCode,
                   lat: $0.lat, lng: $0.lng,
                   appointmentStart: $0.appointmentStart, appointmentEnd: $0.appointmentEnd,
                   notes: $0.notes, referenceNumber: $0.referenceNumber,
                   estimatedWeight: $0.estimatedWeight)
        }
        do {
            let r: SetStopsResult_548 = try await api.mutation(
                "loadStops.setStops", input: In(loadId: loadId, stops: payload))
            pendingResequence = false
            actionNote = "Committed \(r.count ?? payload.count) stops. Note: the driver is not re-notified of a resequence — DISPATCH_RESCHEDULE is not emitted yet."
            await load(loadId: loadId)
        } catch {
            actionNote = (error as? EusoTripAPIError)?.errorDescription ?? "Couldn't commit the run."
        }
        working = false
    }

    /// loadStops.reorder:280 — a single-stop resequence against the real stopId.
    func reorder(from: Int, to: Int) async {
        guard let loadId = activeLoadId,
              stops.indices.contains(from), to >= 1, to <= stops.count else { return }
        let moved = stops[from]
        working = true
        actionNote = nil
        struct In: Encodable { let loadId: Int; let stopId: Int; let newSequence: Int }
        do {
            let _: SuccessResult_548 = try await api.mutation(
                "loadStops.reorder", input: In(loadId: loadId, stopId: moved.stopId, newSequence: to))
            actionNote = "Moved \(moved.title) to position \(to)."
            await load(loadId: loadId)
        } catch {
            actionNote = (error as? EusoTripAPIError)?.errorDescription ?? "Couldn't move that stop."
        }
        working = false
    }

    /// NAMED GAP — esangCoach.forScreen admits no dispatcher screen token. The
    /// control is `.disabled`; the row's text comes from this screen's reads.
    func openEsangProposal() async {
        actionNote = esangBlockedReason
    }

    // NOTE — loadStops.add (:69), loadStops.update (:188), loadStops.remove
    // (:318) and dispatchPlanner.assignLoad (:187) are verified and deliberately
    // NOT wired here. See the header for each reason.

    // MARK: Derivations

    private static func stop(from r: StopRow_548) -> Stop_548 {
        let type = r.stopType ?? "delivery"
        let place = [r.city, r.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        let title = [place.isEmpty ? nil : place, r.facilityName]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        var detailParts: [String] = [type.uppercased()]
        if let appt = shortTime(r.appointmentStart) { detailParts.append("APPT \(appt)") }
        if let w = r.estimatedWeight, w > 0 { detailParts.append(String(format: "%.0f lb", w)) }
        if let ref = r.referenceNumber, !ref.isEmpty { detailParts.append(ref) }
        return Stop_548(
            stopId: r.id,
            seq: "\(r.sequence ?? 0)",
            sequence: r.sequence ?? 0,
            stopType: type,
            title: title.isEmpty ? "Stop \(r.sequence ?? r.id)" : title,
            detail: detailParts.joined(separator: " · "),
            leg: r.distanceFromPrev.map { String(format: "%.0f mi", $0) } ?? "start",
            dwell: r.dwellMinutes.map { "dwell \($0)m" } ?? "dwell —",
            tone: tone(for: type, status: r.status),
            facilityName: r.facilityName, address: r.address,
            city: r.city, state: r.state, zipCode: r.zipCode,
            lat: r.lat, lng: r.lng,
            appointmentStart: r.appointmentStart, appointmentEnd: r.appointmentEnd,
            notes: r.notes, referenceNumber: r.referenceNumber,
            estimatedWeight: r.estimatedWeight)
    }

    private static func renumber(_ s: Stop_548, to n: Int) -> Stop_548 {
        Stop_548(stopId: s.stopId, seq: "\(n)", sequence: n, stopType: s.stopType,
                 title: s.title, detail: s.detail, leg: s.leg, dwell: s.dwell, tone: s.tone,
                 facilityName: s.facilityName, address: s.address, city: s.city,
                 state: s.state, zipCode: s.zipCode, lat: s.lat, lng: s.lng,
                 appointmentStart: s.appointmentStart, appointmentEnd: s.appointmentEnd,
                 notes: s.notes, referenceNumber: s.referenceNumber,
                 estimatedWeight: s.estimatedWeight)
    }

    private static func tone(for type: String, status: String?) -> Stop_548.Tone {
        if (status ?? "") == "skipped" { return .conflict }
        switch type.lowercased() {
        case "pickup": return .load
        default:       return .drop
        }
    }

    private static func kind(for segType: String?) -> BudgetSegment_548.Kind {
        switch (segType ?? "").lowercased() {
        case "drive":         return .drive
        case "break", "rest": return .dwell
        default:              return .conflict
        }
    }

    private static func place(_ r: StopRow_548?) -> String? {
        guard let r else { return nil }
        let p = [r.city, r.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return p.isEmpty ? r.address : p
    }

    private static func locationString(_ s: Stop_548) -> String {
        let p = [s.city, s.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        if !p.isEmpty { return p }
        if let a = s.address, !a.isEmpty { return a }
        return s.title
    }

    private static func dwellMinutes(_ s: Stop_548) -> Int {
        // "dwell 45m" -> 45. Falls back to the server's own default of 30.
        let digits = s.dwell.filter { $0.isNumber }
        return Int(digits) ?? 30
    }

    private static func hm(_ hours: Double) -> String {
        guard hours.isFinite, hours > 0 else { return "0h 00m" }
        let totalMinutes = Int((hours * 60).rounded())
        return String(format: "%dh %02dm", totalMinutes / 60, totalMinutes % 60)
    }

    private static func shortTime(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        var date = f.date(from: iso)
        if date == nil {
            let g = ISO8601DateFormatter()
            g.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = g.date(from: iso)
        }
        guard let d = date else { return nil }
        let out = DateFormatter()
        out.dateFormat = "HH:mm"
        return out.string(from: d)
    }
}

// MARK: - Screen (house form: theme in, Shell + BottomNav around the body)

struct DispatcherMultiStopRunBuilderScreen: View {
    let theme: Theme.Palette
    /// A real navigation hands the load in; nil resolves the first active load
    /// from dispatchRole.getDispatchBoard (see the header).
    let loadId: Int?

    init(theme: Theme.Palette, loadId: Int? = nil) {
        self.theme = theme
        self.loadId = loadId
    }

    var body: some View {
        ShellNav(theme: theme) { MultiStopRunBuilderBody_548(loadId: loadId) }
    }
}

// MARK: - Body

private struct MultiStopRunBuilderBody_548: View {
    let loadId: Int?
    @Environment(\.palette) private var palette
    @StateObject private var vm = RunBuilderVM_548()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                if vm.loading {
                    loadingCard
                } else if let err = vm.loadError {
                    errorCard(err)
                } else {
                    clockBudgetHero
                    if vm.conflictOpen { conflictStrip }
                    stopLadder
                    esangRow
                    ctaRow
                }
                Color.clear.frame(height: 96)
            }.padding(.horizontal, Space.s5).padding(.top, Space.s2)
        }
        .task { await vm.load(loadId: loadId) }
        // Same closure, three triggers (pull / top-edge / stale foreground).
        // This is the READ_CACHED(120s) refresh path for the board and the
        // stop list — it re-invokes the existing load, nothing new.
        .eusoRefreshable { await vm.load(loadId: loadId) }
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Building the run…").font(.system(size: 13)).foregroundStyle(palette.textSecondary)
            Spacer()
        }
        .padding(Space.s5)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message).font(.system(size: 13)).foregroundStyle(palette.textPrimary)
            Button { Task { await vm.load(loadId: loadId) } } label: {
                Text("Try again").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textOnGradient)
                    .padding(.horizontal, 18).frame(height: 36)
                    .background(Capsule().fill(LinearGradient.primary))
            }.buttonStyle(.plain)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
    }

    // MARK: - tone maps

    private func segColor(_ k: BudgetSegment_548.Kind) -> Color {
        switch k {
        case .drive:    return Brand.info
        case .dwell:    return Brand.escort
        case .conflict: return Brand.danger
        }
    }
    /// Chip WASH behind the sequence numeral. The Palette ships tintInfo and
    /// tintDanger; it ships no tintEscort, so the pickup chip is the one wash
    /// mixed locally at the SVG's own 12%.
    private func chipWash(_ t: Stop_548.Tone) -> Color {
        switch t {
        case .load:     return Brand.escort.opacity(0.12)
        case .drop:     return palette.tintInfo
        case .conflict: return palette.tintDanger
        }
    }
    private func chipNumeral(_ t: Stop_548.Tone) -> Color {
        switch t {
        case .load:     return violetText_548
        case .drop:     return infoText_548
        case .conflict: return dangerText_548
        }
    }

    // MARK: - DETAIL TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                EusoTripEyebrow(verbatim: "DISPATCHER · RUN BUILDER")
                    .font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(vm.draftCaption)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).kerning(1.0).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 10) {
                // Real control, not a decorative glyph — the house pattern every
                // pre-existing Dispatch peer uses (410:194-200). 44-unit target.
                Button { back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Text("Run builder").font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
            IridescentHairline()
        }
    }

    private func back() {
        NotificationCenter.default.post(name: .eusoDispatchNavSwap, object: nil, userInfo: ["screenId": "Disp401"])
    }

    /// The slack figure takes its colour from the clock state that produced it.
    /// There is no neutral member of this file's WCAG text family, so the flat
    /// case uses the palette's own secondary ink.
    private func slackColor(_ t: SlackTone_548) -> Color {
        switch t {
        case .healthy: return successText_548
        case .over:    return dangerText_548
        case .neutral: return palette.textSecondary
        }
    }

    // MARK: - HOS budget-consumption hero

    private var clockBudgetHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(vm.budgetLabel)
                .font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .top, spacing: 10) {
                // The caption hangs BELOW the figure — an 11pt tertiary line, not a
                // 13/bold sibling crowding the 32pt numeral.
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(vm.plannedDrive)
                        .font(.system(size: 32, weight: .bold)).monospacedDigit().kerning(-0.5)
                        .foregroundStyle(palette.textPrimary)
                    Text(vm.plannedCaption).font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: Space.s2)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(vm.slack).font(.system(size: 13, weight: .bold)).monospacedDigit()
                        .foregroundStyle(slackColor(vm.slackTone))
                    Text(vm.slackNote).font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                }
                .padding(.top, 6)
            }
            .padding(.top, 14)

            budgetTrack(label: vm.driveLabel, ratio: vm.driveRatio,
                        segments: vm.driveSegments, budget: vm.driveBudgetHours)
                .padding(.top, Space.s4)
            budgetTrack(label: vm.dutyLabel, ratio: vm.dutyRatio,
                        segments: vm.dutySegments, budget: vm.dutyBudgetHours)
                .padding(.top, Space.s4)
        }
        .padding(Space.s5)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    private func budgetTrack(label: String, ratio: String,
                             segments: [BudgetSegment_548], budget: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.system(size: 9, weight: .heavy)).kerning(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(ratio).font(.system(size: 10, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.tintNeutral).frame(height: 10)
                    HStack(spacing: 1.2) {
                        ForEach(segments) { seg in
                            Capsule()
                                .fill(segColor(seg.kind).opacity(0.85))
                                .frame(width: max(0, geo.size.width * CGFloat(seg.hours / max(budget, 0.1)) - 1.2), height: 10)
                        }
                    }
                }
            }.frame(height: 10)
        }
    }

    // MARK: - live conflict strip (real HOS violations — see header)

    private var conflictStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(dangerText_548)
            Text(vm.conflictText).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.85)
            Spacer()
        }
        .padding(.horizontal, Space.s5).frame(minHeight: 30)
        .background(
            // The SVG's `dangerWash` gradient, built from the palette's own
            // wash tokens so it re-tints with the theme.
            Capsule().fill(LinearGradient(colors: [palette.tintDanger, palette.tintWarning],
                                          startPoint: .leading, endPoint: .trailing))
        )
    }

    // MARK: - numbered stop ladder

    private var stopLadder: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(vm.ladderLabel).font(.system(size: 9, weight: .heavy)).kerning(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(vm.ladderSource).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
            }.padding(.bottom, Space.s3)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(vm.stops.enumerated()), id: \.element.id) { idx, s in
                    stopRow(s, isLast: idx == vm.stops.count - 1)
                }
                if vm.stops.isEmpty {
                    HStack(alignment: .top, spacing: Space.s2) {
                        Image(systemName: "tray").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text("This load has no stops on it yet.").font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                        Spacer(minLength: 0)
                    }
                }
                if !vm.runTotal.isEmpty {
                    Text(vm.runTotal)
                        .font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                        .padding(.top, Space.s3)
                }
                if vm.pendingResequence {
                    Text("Resequenced but not committed.")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(warnText_548)
                        .padding(.top, 6)
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private func stopRow(_ s: Stop_548, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(chipWash(s.tone))
                        .frame(width: 40, height: 40)
                    Text(s.seq)
                        .font(.system(size: 15, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(chipNumeral(s.tone))
                }
                if !isLast {
                    // gradient rail connecting consecutive sequence nodes
                    Capsule().fill(LinearGradient.primary).frame(width: 2, height: 22)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(s.title).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(s.detail)
                    .font(.system(size: 11, design: .monospaced)).kerning(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }.padding(.top, Space.s1)
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 5) {
                Text(s.leg).font(.system(size: 12, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text(s.dwell).font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(palette.textTertiary)
            }.padding(.top, Space.s1)
        }
    }

    // MARK: - ESang row (NAMED GAP — disabled, with the reason on screen)

    private var esangRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { Task { await vm.openEsangProposal() } } label: {
                HStack(spacing: Space.s4) {
                    ZStack {
                        Circle().fill(LinearGradient.diagonal).frame(width: 28, height: 28)
                        Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear],
                                                     center: .topLeading, startRadius: 1, endRadius: 14))
                            .frame(width: 28, height: 28)
                        Text("E").font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(palette.textOnGradient)
                    }
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text(vm.esangTitle).font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Text(vm.esangBody).font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary).lineLimit(2)
                    }
                    Spacer(minLength: Space.s2)
                    Image(systemName: "lock")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textTertiary)
                }
                .padding(.horizontal, Space.s4).frame(height: 56)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
                .opacity(0.6)
            }
            .buttonStyle(.plain)
            .disabled(true)
            .accessibilityHint(vm.esangBlockedReason)
            Text(vm.esangBlockedReason).font(.system(size: 11)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - CTA pair

    private var ctaRow: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                // Blocked while a real HOS violation is open, or while the run
                // is too short for loadStops.setStops (min 2).
                Button { Task { await vm.commitRun() } } label: {
                    Text(vm.working ? "Working…" : "\(vm.commitTitle) · \(vm.stops.count) stop\(vm.stops.count == 1 ? "" : "s")")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textOnGradient)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Capsule().fill(LinearGradient.primary))
                        .opacity(vm.canCommit ? 1.0 : 0.45)
                }
                .disabled(!vm.canCommit || vm.working)
                .accessibilityHint(vm.canCommit ? "" : vm.commitBlockedReason)

                Button { Task { await vm.optimize() } } label: {
                    Text(vm.optimizeTitle).font(.system(size: 15, weight: .semibold))
                        .frame(width: 132, height: 48)
                        .background(Capsule().fill(palette.bgCard))
                        .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
                }
                .foregroundStyle(palette.textPrimary)
                .disabled(vm.working || vm.stops.count < 2)
            }
            if !vm.canCommit && !vm.commitBlockedReason.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lock").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(warnText_548)
                    Text(vm.commitBlockedReason).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(warnText_548)
                }
            }
            if let note = vm.actionNote {
                Text(note).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
        }
    }
}

// MARK: - The single iridescent hairline (theme-aware house token)

// MARK: - Previews

#Preview("548 · Multi-Stop Run Builder · Dark")  { DispatcherMultiStopRunBuilderScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("548 · Multi-Stop Run Builder · Light") { DispatcherMultiStopRunBuilderScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
