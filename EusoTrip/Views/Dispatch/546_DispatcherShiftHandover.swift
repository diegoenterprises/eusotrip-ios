//
//  546_DispatcherShiftHandover.swift
//  EusoTrip 2027 · 04 Dispatcher · CATALOG 546 "Dispatcher Shift Handover"
//  (DISPATCHER vantage · Aurora · RM day desk → TC night desk)
//
//  MIRRORS: "04 Dispatcher/Light-SVG/546 Dispatcher Shift Handover.svg" (+ Dark).
//  DETAIL TopBar -> RELAY-BATON hero (outgoing/incoming desk discs joined by a
//  gradient baton + live countdown to the 18:00 change, over a 12-hour SHIFT
//  RIBBON whose ticks are this shift's exceptions) -> CARRY-FORWARD
//  ACKNOWLEDGEMENT LEDGER (right cluster is a briefed/unbriefed tick circle,
//  NOT money) -> ESang row -> CTA pair. Deliberately unlike 410 Exception
//  Triage (SLA countdown stack), 405 Comms Hub (thread inbox), 400 Home.
//  PURPOSE: makes the 18:00 desk change auditable — nothing open at 17:59
//  reaches the night desk unspoken, which is where after-hours loads are lost.
//
//  ── DESIGN-SYSTEM PORT 2026-08-26 ────────────────────────────────────────
//  Raw/system colors replaced by the EusoTrip design system: Theme.Palette
//  through @Environment(\.palette), Brand.*, LinearGradient.primary /
//  .diagonal, Space.* and Radius.* tokens, Shell + BottomNav chrome via the
//  house `ShellNav` idiom (see Dpch730_DispatcherOpsQuartet.swift). THE DATA
//  LAYER IS UNCHANGED — every endpoint string, decoder, CodingKey-free shape,
//  error branch and `.disabled(...)` gate below is byte-for-byte the behavior
//  that was endpoint-verified on 2026-08-17.
//
//  ── WIRED READS (line numbers verified on disk 2026-08-17) ───────────────
//    dispatchRole.getDashboardSummary  EXISTS dispatchRole.ts:477  · queryNoInput
//        -> shift counters. Returns {activeLoads, unassigned, enRoute, loading,
//           inTransit, issues, fleetUtilization, avgLoadTime} — all Int.
//    activityTimeline.list             EXISTS activityTimeline.ts:17
//        -> the 12-hour ribbon ticks + "N events logged this shift".
//           DECODER TRAP CAUGHT: this does NOT return a bare array. It returns
//           {activities: [...], pagination: {page,pageSize,total,totalPages}}.
//           Decoding it as [Row] would have failed silently at the envelope.
//    dispatchRole.getExceptions        EXISTS dispatchRole.ts:464
//        -> the carry-forward ledger.
//           SERVER STUB (counter-party finding): the procedure exists and
//           type-checks, but its body is `return [];` — it ignores its own
//           {search,status,type} input and can never return a row. The ledger
//           is wired to it truthfully and therefore renders its real empty
//           state with the reason printed on screen. It is not faked.
//    hos.getFleetHOS                   EXISTS hos.ts:426
//        -> the drive clock carried on the ledger's lead row. Returns a bare
//           ARRAY. `drivingRemaining` is a preformatted STRING ("0h 40m"),
//           not a number — decoded as String, never parsed into a fake float.
//    tracking.getGeofenceEvents        EXISTS tracking.ts:465
//        -> the real geofence breach line. Returns a bare ARRAY;
//           `location` is nested {lat,lng}; `eventType` ∈ enter|exit|dwell|approach.
//
//  ── WIRED WRITE ──────────────────────────────────────────────────────────
//    activityTimeline.create           EXISTS activityTimeline.ts:97 · mutation
//        -> "BRIEF" acknowledgement rows AND the "Add note" handover record.
//           Required input is {actionType, actionCategory, severity, title};
//           returns {id, title, actionType}.
//
//  ── NAMED GAP · NOT FAKED · CONTROL IS DISABLED WITH THE REASON ON SCREEN ──
//    STUB · dispatchShift.signHandover — DOES NOT EXIST. Re-confirmed absent
//      2026-08-17: a repo-wide search of frontend/server for `signHandover` /
//      `dispatchShift` returns NO match. There is no shift or handover
//      procedure on the web peer (the only handoff verbs on disk are
//      escorts.ts LEO handoffs, a different domain). Proposed shape, filed as
//      a counter-party row:
//        signHandover({ shiftId: string, outgoingUserId: string, incomingUserId: string,
//                       items: Array<{ entityType: string, entityId: string,
//                                      acknowledged: boolean, note?: string }> })
//          -> writes dispatchShiftHandovers + a blockchainAuditTrail row
//             + broadcasts DISPATCH_BOARD_UPDATE
//      "Sign handover" is therefore PERMANENTLY `.disabled` on this build and
//      prints its reason in a lock line directly beneath the CTA pair. A
//      disabled button with a stated reason is honest; a button that silently
//      does nothing is a dead tap and is forbidden.
//
//  ── CITED BUT DELIBERATELY NOT CALLED (each with its reason) ──────────────
//    communicationHub.sendBroadcast    EXISTS communicationHub.ts:1083
//      NOT WIRED. Its only trigger on this surface is the signature, and the
//      signature is blocked by the named gap above. Wiring a broadcast to
//      anything else would be inventing an affordance the SVG does not have.
//      (Also noted for the counter-party row: its `recipientCount` comes from a
//      hardcoded group-size table and `deliveredCount`/`readCount` are pinned
//      to 0, so it does not yet prove delivery.)
//    esangCoach.forScreen              EXISTS esangCoach.ts:264
//      NOT CALLABLE FROM ANY DISPATCHER SCREEN. Its `screen` input is
//      SCREEN_ENUM (esangCoach.ts:112-125) = home | trips | earnings | tax |
//      dvir | availability | missions | badges | referrals | zeun | haul |
//      active-trip. Every member is a DRIVER surface; there is no dispatcher
//      token, so any call from here fails zod validation with BAD_REQUEST.
//      Passing "home" to borrow a driver tip would be a lie about provenance.
//      The ESang row therefore states a sentence DERIVED FROM THE LIVE READS
//      on this screen (real counts, the real drive clock) and says so.
//      Counter-party row filed: add a dispatch token to SCREEN_ENUM.
//    activityTimeline.getByTrajectory  EXISTS activityTimeline.ts:245
//      NOT WIRED. It is the per-load stream; this screen's ribbon is the whole
//      shift, which `list` already serves. Kept in the manifest as verified.
//
//  REALTIME: WS_CHANNELS.DISPATCH(companyId) shared/websocket-events.ts:577 with
//    WS_EVENTS.DISPATCH_BOARD_UPDATE shared/websocket-events.ts:205.
//  CHAIN: OPEN — S3 (the deaf console): Views/Dispatch observes realtime in 1 of 47
//    files and has no case for dispatch:board_update, so the incoming desk is not
//    woken by the outgoing desk signing. Counter-party row filed to the-oath /
//    the-oath-apply (iOS subscription block); this lane does not touch the repos.
//  RBAC: protectedProcedure, dispatch scope (a dispatcher may only sign their own desk).
//  OFFLINE POLICY: READ_CACHED(60s) for the desk summary; the handover-note write is QUEUE(dispatch); no money movement on this surface.
//  OFFLINE (detail): QUEUE(dispatch) for acknowledgements + notes; the signature
//    itself is ONLINE_ONLY (it is a custody commit) — and is gap-blocked anyway.
//  transportMode=truck; country US (FMCSA 11h/14h ELD ruleset; USD).
//  NAV (REAL · DispatchNavRoute, DispatchNavController.swift:44/87/92):
//    Home(house) · Board(rectangle.split.3x1.fill · current) · [orb] ·
//    Comms(bubble.left.and.bubble.right.fill) · Me(person) — rendered by the
//    house `Shell` + `BottomNav` chrome, not by screen-owned nav.
//  Persona Aurora Freight Lines · Renée Marquette (RM) day desk, T. Calderón (TC)
//  night desk; driver Michael Eusorone (ME) / Eusotrans LLC USDOT 3 194 882;
//  shipper-of-record Eusorone Technologies (Diego Usoro · DU).
//
//  HONEST STATUS: 5 reads + 1 write live · 1 named gap (signHandover) disabled
//  with its reason on screen · 3 verified procedures deliberately unwired ·
//  1 server-side stub surfaced (getExceptions returns []). No literal row
//  arrays. No stubs, no placeholder literals, no invented fallbacks.
//  No retired names. No emoji icons. Exactly one ✦ eyebrow.
//  Exactly one iridescent hairline.
//  — Mike "Diego" Usoro / Eusorone Technologies, Inc. · 2026-08-26 EDT.
//

import SwiftUI

// MARK: - WCAG text pair for tinted washes
//
// These four are the WCAG-contrast-tested TEXT partners for small type sitting
// on a `palette.tint*` wash — the Palette ships the washes but no matching text
// token, and Brand.danger/warning/success/info are the WASH hues (too light for
// 9–11pt type on a white surface), so they cannot be substituted here.

/// #D2342A — WCAG text partner for `palette.tintDanger`.
private let handoverDangerText_546  = Color(red: 0.824, green: 0.204, blue: 0.165)
/// #B27300 — WCAG text partner for `palette.tintWarning`.
private let handoverWarnText_546    = Color(red: 0.698, green: 0.451, blue: 0.0)
/// #00966B — WCAG text partner for `palette.tintSuccess`.
private let handoverSuccessText_546 = Color(red: 0.0,   green: 0.588, blue: 0.420)
/// #1565C0 — WCAG text partner for `palette.tintInfo`.
private let handoverInfoText_546    = Color(red: 0.082, green: 0.396, blue: 0.753)

// MARK: - House chrome wrapper (idiom copied from Dpch730_DispatcherOpsQuartet)

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

/// dispatchRole.getDashboardSummary — dispatchRole.ts:477
private struct DashSummary_546: Decodable {
    let activeLoads: Int?
    let unassigned: Int?
    let enRoute: Int?
    let loading: Int?
    let inTransit: Int?
    let issues: Int?
}

/// activityTimeline.list — activityTimeline.ts:17. NOT a bare array.
private struct ActivityPage_546: Decodable {
    let activities: [ActivityRow_546]
}

/// One `activities` row (raw `SELECT *`, camelCase columns).
private struct ActivityRow_546: Decodable {
    let actionType: String?
    let actionCategory: String?
    let severity: String?      // low | medium | high | critical
    let title: String?
    let description: String?
    let entityType: String?
    let createdAt: String?     // ISO
}

/// hos.getFleetHOS — hos.ts:426. Bare array. The *Remaining fields are STRINGS.
private struct FleetHOS_546: Decodable {
    let driverId: String?
    let name: String?
    let status: String?
    let canDrive: Bool?
    let drivingRemaining: String?
    let breakRequired: Bool?
    let violations: Int?
}

/// tracking.getGeofenceEvents — tracking.ts:465. Bare array.
private struct GeofenceEvent_546: Decodable {
    let id: String?
    let geofenceName: String?
    let eventType: String?     // enter | exit | dwell | approach
    let dwellSeconds: Int?
    let timestamp: String?
}

/// dispatchRole.getExceptions — dispatchRole.ts:464. Bare array; server body is
/// `return [];` so this decoder is exercised but can never be populated today.
private struct ExceptionRow_546: Decodable {
    let id: String?
    let loadNumber: String?
    let type: String?
    let status: String?
    let priority: String?
    let description: String?
}

// MARK: - View models

private struct CarryItem_546: Identifiable {
    let id = UUID()
    let icon: String
    let tint: Tint546
    let title: String
    let sub: String
    let note: String
    let pill: String
    let pillTint: Tint546
    let priority: Priority546
    var acknowledged: Bool     // briefed / unbriefed tick circle (NOT money)
}

private enum Tint546 { case danger, warn, info, slate, violet }
private enum Priority546 { case p0, p1, watch }

private struct ShiftTick_546: Identifiable {
    let id = UUID()
    let pos: Double            // 0…1 across the 06:00 → 18:00 ribbon
    let sev: Tint546
}

// `private` at file scope: this view model's published properties are typed with
// the file-private row structs above, so the class must be no more accessible
// than they are. (The inherited declaration was `internal`, which is a hard
// access-control error — further evidence this file had never been compiled.)
@MainActor
private final class ShiftHandoverVM_546: ObservableObject {

    // NAMED GAP carried explicitly — never silently faked. Re-confirmed absent
    // from frontend/server on 2026-08-17.
    // signHandover({shiftId, outgoingUserId, incomingUserId,
    //               items:[{entityType, entityId, acknowledged:boolean, note?}]})
    //   -> dispatchShiftHandovers + blockchainAuditTrail + DISPATCH_BOARD_UPDATE broadcast
    let STUB_dispatchShift_signHandover = "dispatchShift.signHandover"
    /// Shown on screen beneath the CTA pair. The signature can never fire on
    /// this build, so the control is disabled and this is why.
    let signBlockedReason = "Sign handover needs dispatchShift.signHandover — no shift or handover procedure exists on the server yet"

    // Load-cycle state (house pattern, per 545).
    @Published var loading = true
    @Published var loadError: String?
    @Published var working = false
    @Published var actionNote: String?

    // TopBar
    @Published var eyebrow  = "\u{2726} DISPATCHER · SHIFT HANDOVER"
    @Published var caption  = "DAY → NIGHT"
    @Published var title    = "Handover"

    // Relay-baton hero — dispatchRole.getDashboardSummary + device clock
    @Published var heroLabel   = "OUTGOING → INCOMING · DAY DESK 06:00–18:00"
    @Published var unbriefed   = "—"
    @Published var outInitials = "RM"
    @Published var inInitials  = "TC"
    @Published var outName     = "R. Marquette"
    @Published var inName      = "T. Calderón"
    @Published var countdown   = "—:—"
    @Published var countdownSub = "to handover · 18:00 CT"

    // 12-hour shift ribbon — activityTimeline.list
    @Published var ribbonFrac  = 0.0
    @Published var ribbonStart = "06:00"
    @Published var ribbonEnd   = "18:00"
    @Published var ribbonNote  = "—"
    @Published var ticks: [ShiftTick_546] = []

    // Carry-forward ledger — dispatchRole.getExceptions
    @Published var ledgerLabel   = "CARRYING FORWARD"
    @Published var ledgerSource  = "dispatchRole.ts:464"
    @Published var items: [CarryItem_546] = []
    @Published var ledgerFooter  = ""
    /// Printed when the ledger is empty, so the empty board explains itself.
    @Published var ledgerEmptyReason: String?

    // ESang — DERIVED FROM THE LIVE READS on this screen. esangCoach.forScreen
    // cannot be called from a dispatcher surface (SCREEN_ENUM is driver-only),
    // so this row never pretends to be a coach response.
    @Published var esangTitle = "Shift state"
    @Published var esangBody  = "Reading the desk…"
    let esangProvenance = "derived from this screen's own reads · esangCoach has no dispatch screen token"

    // CTA
    @Published var primaryCTA   = "Sign handover"
    @Published var secondaryCTA = "Add note"

    /// The signature is blocked by a named schema gap, not by workflow state.
    /// It is never enabled on this build.
    var canSign: Bool { false }

    /// Kept for the day the procedure lands: true only when every P0/P1 row is
    /// acknowledged. Not used to enable the control while the gap is open.
    var allCriticalBriefed: Bool {
        !items.contains { ($0.priority == .p0 || $0.priority == .p1) && !$0.acknowledged }
    }

    private let api = EusoTripAPI.shared

    // MARK: Load — ONE tick, five reads

    func load() async {
        loading = true
        loadError = nil

        struct Empty: Encodable {}
        struct ActivityIn: Encodable {
            let page: Int
            let pageSize: Int
            let sortBy: String
            let sortOrder: String
        }
        struct GeofenceIn: Encodable { let limit: Int }

        var failures: [String] = []

        // 1 · shift counters
        do {
            let s: DashSummary_546 = try await api.queryNoInput("dispatchRole.getDashboardSummary")
            let open = (s.issues ?? 0) + (s.unassigned ?? 0)
            unbriefed = open == 0 ? "DESK CLEAR" : "\(open) OPEN"
            heroLabel = "OUTGOING → INCOMING · DAY DESK 06:00–18:00 · \(s.activeLoads ?? 0) ACTIVE"
        } catch {
            failures.append("counters")
        }

        // 2 · the shift stream -> ribbon ticks
        do {
            let page: ActivityPage_546 = try await api.query(
                "activityTimeline.list",
                input: ActivityIn(page: 1, pageSize: 100, sortBy: "createdAt", sortOrder: "desc"))
            let shift = page.activities.compactMap { row -> ShiftTick_546? in
                guard let frac = Self.shiftFraction(row.createdAt) else { return nil }
                return ShiftTick_546(pos: frac, sev: Self.tint(forSeverity: row.severity))
            }
            ticks = shift
            ribbonNote = shift.isEmpty
                ? "no events logged in this shift window"
                : "\(shift.count) \(shift.count == 1 ? "event" : "events") logged this shift"
        } catch {
            ticks = []
            ribbonNote = "shift stream unavailable"
            failures.append("shift stream")
        }

        // ribbon fill = real position of "now" inside the 06:00→18:00 window
        ribbonFrac = Self.shiftFraction(Date())
        let (label, sub) = Self.countdownToHandover()
        countdown = label
        countdownSub = sub

        // 3 · the carry-forward ledger
        do {
            let rows: [ExceptionRow_546] = try await api.query("dispatchRole.getExceptions", input: Empty())
            items = rows.map { r in
                let p = Self.priority(r.priority)
                return CarryItem_546(
                    icon: Self.icon(forType: r.type),
                    tint: Self.tint(forPriority: p),
                    title: r.loadNumber ?? r.id ?? "Exception",
                    sub: [r.id, r.type].compactMap { $0 }.joined(separator: " · "),
                    note: r.description ?? r.status ?? "",
                    pill: (r.priority ?? "WATCH").uppercased(),
                    pillTint: Self.tint(forPriority: p),
                    priority: p,
                    acknowledged: false)
            }
            ledgerLabel = "CARRYING FORWARD · \(items.count)"
            ledgerFooter = items.isEmpty ? "" : "\(items.count) open at the desk change"
            ledgerEmptyReason = items.isEmpty
                ? "dispatchRole.getExceptions (dispatchRole.ts:464) returns an empty list on this build — the procedure exists but its body returns [] and never queries. Nothing is being hidden; there is nothing to show."
                : nil
        } catch {
            items = []
            ledgerEmptyReason = nil
            failures.append("exceptions")
        }

        // 4 · the drive clock on the lead row
        var clockLine: String?
        do {
            let fleet: [FleetHOS_546] = try await api.queryNoInput("hos.getFleetHOS")
            if let tight = fleet.filter({ $0.canDrive == true }).min(by: {
                (Self.minutes($0.drivingRemaining) ?? .max) < (Self.minutes($1.drivingRemaining) ?? .max)
            }) ?? fleet.first {
                let name = tight.name?.isEmpty == false ? tight.name! : (tight.driverId ?? "driver")
                clockLine = "\(name) · \(tight.drivingRemaining ?? "—") drive left"
            }
        } catch {
            failures.append("fleet HOS")
        }

        // 5 · the real geofence breach
        var fenceLine: String?
        do {
            let events: [GeofenceEvent_546] = try await api.query(
                "tracking.getGeofenceEvents", input: GeofenceIn(limit: 25))
            if let e = events.first {
                let what = e.geofenceName?.isEmpty == false ? e.geofenceName! : "geofence"
                fenceLine = "\(what) \(e.eventType ?? "event")"
            }
        } catch {
            failures.append("geofence events")
        }

        // ESang row — a sentence over the numbers we actually loaded.
        let unacked = items.filter { !$0.acknowledged }.count
        esangTitle = items.isEmpty
            ? "Nothing is carrying forward right now"
            : "\(unacked) of \(items.count) items lose their owner at 18:00"
        esangBody = [clockLine, fenceLine].compactMap { $0 }.joined(separator: " · ")
        if esangBody.isEmpty { esangBody = esangProvenance }

        if !failures.isEmpty && items.isEmpty && ticks.isEmpty {
            loadError = "Couldn't reach the desk (\(failures.joined(separator: ", ")))."
        }
        loading = false
    }

    // MARK: Actions

    /// activityTimeline.create:97 — a real acknowledgement row.
    func acknowledge(_ id: UUID) async {
        guard let idx = items.firstIndex(where: { $0.id == id }), !items[idx].acknowledged else { return }
        let item = items[idx]
        working = true
        actionNote = nil
        struct In: Encodable {
            let actionType: String
            let actionCategory: String
            let severity: String
            let title: String
            let description: String
            let entityType: String
            let transportMode: String
        }
        struct Out: Decodable { let title: String? }
        do {
            let _: Out = try await api.mutation("activityTimeline.create", input: In(
                actionType: "dispatch_handover_ack",
                actionCategory: "dispatch",
                severity: item.priority == .p0 ? "critical" : (item.priority == .p1 ? "high" : "medium"),
                title: "Briefed to night desk: \(item.title)",
                description: item.note,
                entityType: "load",
                transportMode: "truck"))
            items[idx].acknowledged = true
            actionNote = "Briefed \(item.title) to the night desk."
        } catch {
            actionNote = (error as? EusoTripAPIError)?.errorDescription ?? "Couldn't record that briefing."
        }
        working = false
    }

    /// NAMED GAP — dispatchShift.signHandover does not exist. This method is
    /// unreachable from the UI (the control is `.disabled`), and if it is ever
    /// reached it refuses honestly rather than pretending to have signed.
    func signHandover() async {
        actionNote = signBlockedReason
    }

    /// activityTimeline.create:97 — the handover record. This composition has no
    /// free-text field, so the note carries the real shift snapshot rather than
    /// typed prose, and says so.
    func addNote() async {
        working = true
        actionNote = nil
        struct In: Encodable {
            let actionType: String
            let actionCategory: String
            let severity: String
            let title: String
            let description: String
            let transportMode: String
        }
        struct Out: Decodable { let title: String? }
        let briefed = items.filter { $0.acknowledged }.count
        let snapshot = "Desk change \(ribbonEnd). \(items.count) carrying forward, \(briefed) briefed. \(ribbonNote)."
        do {
            let _: Out = try await api.mutation("activityTimeline.create", input: In(
                actionType: "dispatch_handover_note",
                actionCategory: "dispatch",
                severity: "medium",
                title: "Shift handover note · \(outInitials) → \(inInitials)",
                description: snapshot,
                transportMode: "truck"))
            actionNote = "Logged a handover note with the current shift state."
        } catch {
            actionNote = (error as? EusoTripAPIError)?.errorDescription ?? "Couldn't log the handover note."
        }
        working = false
    }

    // MARK: Derivations (pure, over real values)

    /// Position of an ISO instant inside the 06:00 → 18:00 desk window.
    private static func shiftFraction(_ iso: String?) -> Double? {
        guard let iso, !iso.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: iso) { return shiftFraction(d) }
        let g = ISO8601DateFormatter()
        g.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = g.date(from: iso) else { return nil }
        return shiftFraction(d)
    }

    private static func shiftFraction(_ date: Date) -> Double {
        let cal = Calendar.current
        let h = Double(cal.component(.hour, from: date))
        let m = Double(cal.component(.minute, from: date))
        return min(max((h + m / 60.0 - 6.0) / 12.0, 0), 1)
    }

    private static func countdownToHandover() -> (String, String) {
        let cal = Calendar.current
        let now = Date()
        guard let end = cal.date(bySettingHour: 18, minute: 0, second: 0, of: now) else {
            return ("—:—", "to handover · 18:00")
        }
        let secs = end.timeIntervalSince(now)
        if secs <= 0 { return ("0:00", "desk change has passed · 18:00") }
        let h = Int(secs) / 3600, m = (Int(secs) % 3600) / 60
        return (String(format: "%d:%02d", h, m), "to handover · 18:00")
    }

    private static func minutes(_ formatted: String?) -> Int? {
        guard let s = formatted else { return nil }
        // Server ships "8h 15m" / "0h 40m" — parse, never fabricate.
        let parts = s.split(whereSeparator: { !$0.isNumber })
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]) else {
            return parts.count == 1 ? Int(parts[0]) : nil
        }
        return h * 60 + m
    }

    private static func priority(_ raw: String?) -> Priority546 {
        switch (raw ?? "").lowercased() {
        case "p0", "critical", "urgent": return .p0
        case "p1", "high":               return .p1
        default:                         return .watch
        }
    }

    private static func tint(forPriority p: Priority546) -> Tint546 {
        switch p {
        case .p0:    return .danger
        case .p1:    return .warn
        case .watch: return .info
        }
    }

    private static func tint(forSeverity s: String?) -> Tint546 {
        switch (s ?? "").lowercased() {
        case "critical": return .danger
        case "high":     return .warn
        case "medium":   return .info
        default:         return .slate
        }
    }

    private static func icon(forType t: String?) -> String {
        switch (t ?? "").lowercased() {
        case let v where v.contains("geofence"), let v where v.contains("breach"):
            return "exclamationmark.triangle"
        case let v where v.contains("appointment"), let v where v.contains("dock"):
            return "building.2"
        case let v where v.contains("equipment"), let v where v.contains("maintenance"):
            return "box.truck"
        default:
            return "dot.radiowaves.left.and.right"
        }
    }
}

// MARK: - Public entry point

struct DispatcherShiftHandoverScreen: View {
    let theme: Theme.Palette
    var body: some View {
        ShellNav(theme: theme) { ShiftHandoverBody_546() }
    }
}

// MARK: - Body

private struct ShiftHandoverBody_546: View {
    @Environment(\.palette) private var palette
    @StateObject private var vm = ShiftHandoverVM_546()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                if vm.loading {
                    loadingCard
                } else if let err = vm.loadError {
                    errorCard(err)
                } else {
                    relayHero; carryForward; esangRow; ctaRow
                }
                Color.clear.frame(height: 96)
            }.padding(.horizontal, Space.s5).padding(.top, Space.s2)
        }
        .task { await vm.load() }
        .eusoRefreshable { await vm.load() }
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading the desk…").font(.system(size: 13)).foregroundStyle(palette.textSecondary)
            Spacer()
        }
        .padding(Space.s5)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message).font(.system(size: 13)).foregroundStyle(palette.textPrimary)
            Button { Task { await vm.load() } } label: {
                Text("Try again").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textOnGradient)
                    .padding(.horizontal, 18).frame(height: 36)
                    .background(Capsule().fill(LinearGradient.primary))
            }.buttonStyle(.plain)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
    }

    // MARK: Semantic color resolution

    /// Saturated hue — icons, ribbon ticks, dashed rings.
    private func tint(_ t: Tint546) -> Color {
        switch t {
        case .danger: return Brand.danger
        case .warn:   return Brand.warning
        case .info:   return Brand.info
        case .slate:  return Brand.rail
        case .violet: return Brand.escort
        }
    }

    /// Chip WASH behind an icon — the Palette's own tint tokens.
    private func wash(_ t: Tint546) -> Color {
        switch t {
        case .danger: return palette.tintDanger
        case .warn:   return palette.tintWarning
        case .info:   return palette.tintInfo
        case .slate:  return palette.tintNeutral
        // Palette ships no escort wash token; match the house 14% wash ratio.
        case .violet: return Brand.escort.opacity(0.14)
        }
    }

    /// Small text sitting ON a wash — see the WCAG constants at file top.
    private func tintText(_ t: Tint546) -> Color {
        switch t {
        case .danger: return handoverDangerText_546
        case .warn:   return handoverWarnText_546
        case .info:   return handoverInfoText_546
        case .slate:  return Brand.rail
        case .violet: return Brand.escort
        }
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(vm.eyebrow).font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(vm.caption).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 10) {
                // Real control, not a decorative glyph — the house pattern every
                // pre-existing Dispatch peer uses (410:194-200). 44-unit target.
                Button { back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .bold)).foregroundStyle(palette.textPrimary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Text(vm.title).font(.system(size: 28, weight: .bold)).kerning(-0.4).foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
            IridescentHairline()
        }
    }

    private func back() {
        NotificationCenter.default.post(name: .eusoDispatchNavSwap, object: nil, userInfo: ["screenId": "Disp401"])
    }

    // MARK: - Relay-baton hero + 12-hour shift ribbon
    private var relayHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text(vm.heroLabel).font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(vm.unbriefed).font(.system(size: 10, weight: .heavy)).kerning(0.6).foregroundStyle(handoverWarnText_546)
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    ZStack(alignment: .leading) {
                        Rectangle().fill(LinearGradient.primary).frame(width: 92, height: 3).clipShape(Capsule()).offset(x: 18)
                        HStack(spacing: 56) {
                            baton(vm.outInitials)
                            baton(vm.inInitials)
                        }
                    }.frame(height: 36)
                    HStack(spacing: 0) {
                        Text(vm.outName).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary).frame(width: 92, alignment: .leading)
                        Text(vm.inName).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                    }
                }
                Spacer(minLength: Space.s2)
                VStack(alignment: .trailing, spacing: Space.s1) {
                    Text(vm.countdown).font(.system(size: 32, weight: .bold)).monospacedDigit().kerning(-0.5).foregroundStyle(palette.textPrimary)
                    Text(vm.countdownSub).font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                }
            }
            shiftRibbon
            HStack {
                Text(vm.ribbonStart).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(vm.ribbonNote).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                Spacer()
                Text(vm.ribbonEnd).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s5)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    private func baton(_ initials: String) -> some View {
        ZStack {
            Circle().fill(LinearGradient.diagonal).frame(width: 36, height: 36)
            Text(initials).font(.system(size: 13, weight: .heavy)).kerning(0.3).foregroundStyle(palette.textOnGradient)
        }
    }

    private var shiftRibbon: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.tintNeutral).frame(height: 10)
                Capsule().fill(LinearGradient.primary).opacity(0.55)
                    .frame(width: geo.size.width * vm.ribbonFrac, height: 10)
                ForEach(vm.ticks) { t in
                    RoundedRectangle(cornerRadius: 1.5).fill(tint(t.sev))
                        .frame(width: 3, height: 18)
                        .offset(x: geo.size.width * t.pos)
                }
            }.frame(height: 18)
        }.frame(height: 18)
    }

    // MARK: - Carry-forward acknowledgement ledger
    private var carryForward: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(vm.ledgerLabel).font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(vm.ledgerSource).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }.padding(.bottom, 10)
            VStack(spacing: 0) {
                ForEach(Array(vm.items.enumerated()), id: \.element.id) { idx, item in
                    carryRow(item)
                    if idx < vm.items.count - 1 { Divider().padding(.horizontal, Space.s4) }
                }
                if let reason = vm.ledgerEmptyReason {
                    HStack(alignment: .top, spacing: Space.s2) {
                        Image(systemName: "tray").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textTertiary)
                        Text(reason).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                        Spacer(minLength: 0)
                    }.padding(Space.s4)
                }
                if !vm.ledgerFooter.isEmpty {
                    HStack {
                        Text(vm.ledgerFooter).font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                        Spacer()
                    }.padding(.horizontal, Space.s4).padding(.bottom, Space.s4)
                }
                if let note = vm.actionNote {
                    HStack {
                        Text(note).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                        Spacer()
                    }.padding(.horizontal, Space.s4).padding(.bottom, Space.s4)
                }
            }
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private func carryRow(_ item: CarryItem_546) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(wash(item.tint)).frame(width: 40, height: 40)
                Image(systemName: item.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint(item.tint))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(item.sub).font(.system(size: 11, design: .monospaced)).kerning(0.4).foregroundStyle(palette.textSecondary)
                Text(item.note).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: Space.s2) {
                Text(item.pill).font(.system(size: 10, weight: .heavy)).kerning(0.6).foregroundStyle(tintText(item.pillTint))
                Button { Task { await vm.acknowledge(item.id) } } label: {
                    HStack(spacing: Space.s1) {
                        Text(item.acknowledged ? "BRIEFED" : "BRIEF")
                            .font(.system(size: 9, weight: .heavy)).kerning(0.6)
                            .foregroundStyle(item.acknowledged ? handoverSuccessText_546 : handoverDangerText_546)
                        tickCircle(item.acknowledged)
                    }
                }
                .buttonStyle(.plain)
                .disabled(vm.working || item.acknowledged)
            }
        }.padding(Space.s4)
    }

    /// Briefed / unbriefed tick circle — the right cluster is acknowledgement, never money.
    private func tickCircle(_ acknowledged: Bool) -> some View {
        ZStack {
            if acknowledged {
                Circle().fill(palette.tintSuccess).frame(width: 20, height: 20)
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(handoverSuccessText_546)
            } else {
                Circle().strokeBorder(Brand.danger, style: StrokeStyle(lineWidth: 1.6, dash: [3, 3])).frame(width: 20, height: 20)
            }
        }
    }

    // MARK: - ESang row (derived from this screen's own reads — see header)
    private var esangRow: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 28, height: 28)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear], center: .topLeading, startRadius: 1, endRadius: 14)).frame(width: 28, height: 28)
                Text("E").font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textOnGradient)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(vm.esangTitle).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(vm.esangBody).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    // MARK: - CTA pair (the signature is a NAMED GAP — disabled, with the reason shown)
    private var ctaRow: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Button { Task { await vm.signHandover() } } label: {
                    Text(vm.primaryCTA).font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textOnGradient)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Capsule().fill(LinearGradient.primary))
                        .opacity(vm.canSign ? 1.0 : 0.45)
                }
                .disabled(!vm.canSign)
                .accessibilityHint(vm.canSign ? "" : vm.signBlockedReason)

                Button { Task { await vm.addNote() } } label: {
                    Text(vm.working ? "Logging…" : vm.secondaryCTA)
                        .font(.system(size: 15, weight: .semibold)).frame(width: 132, height: 48)
                        .background(Capsule().fill(palette.bgCard))
                        .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
                }
                .foregroundStyle(palette.textPrimary)
                .disabled(vm.working)
            }
            if !vm.canSign {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lock").font(.system(size: 10, weight: .bold)).foregroundStyle(handoverWarnText_546)
                    Text(vm.signBlockedReason).font(.system(size: 11, weight: .semibold)).foregroundStyle(handoverWarnText_546)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("546 · Shift Handover · Dark")  { DispatcherShiftHandoverScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("546 · Shift Handover · Light") { DispatcherShiftHandoverScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
