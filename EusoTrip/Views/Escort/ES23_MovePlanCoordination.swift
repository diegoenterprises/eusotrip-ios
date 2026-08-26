//
//  ES23_MovePlanCoordination.swift
//  EusoTrip — Escort · Move Plan & Coordination (ES-23).
//
//  Built from the ES-23 design-authority SVG pair
//  ("07 Escort/{Light,Dark}-SVG/ES-23 Move Plan Coordination.svg").
//
//  ARCHETYPE — BOARD. A T-MINUS SWIMLANE BOARD. Seven coordinating-party LANES
//  stacked vertically against ONE horizontal COUNTDOWN axis running T-72h at
//  the left to a hard T-0 edge at the right, plus a separate UNTIMED gutter for
//  obligations the server holds but never timestamps. What the face makes
//  legible in one look is WHICH LANE IS BEHIND as the T-0 edge approaches.
//
//  Anti-clone: NOT ES-05 Jurisdiction Handoff (a vertical relay spine of baton
//  passes with a split OUTGOING|INCOMING officer board); NOT ES-16 Active Trip
//  Console (a five-leg corridor spine beside an advisory chip rail). A spine is
//  one line of sequential states; a ruler is one axis of time; THIS SCREEN IS A
//  TWO-DIMENSIONAL BOARD — PARTIES x COUNTDOWN — AND ITS WHOLE POINT IS
//  CROSS-LANE COMPARISON AT A SHARED INSTANT. Also NOT ES-09's day-ruler, NOT
//  ES-15's calendar lattice, NOT ES-10's lifecycle spine.
//
//  WIRING (every anchor opened at the line first-hand this fire against
//  ~/Desktop/eusoronetechnologiesinc/frontend · server/routers/escorts.ts = 4745 lines)
//    EXISTS escorts.getHandoffs           escorts.ts:1635
//           {assignmentId} → [{handoffId, stateFrom, stateTo, status, agency,
//           officerRef, scheduledAt, actualAt, notes, outgoingOfficers[],
//           incomingOfficers[], checklistCompleted, locationLabel, etaMinutes}]
//           (mapper escorts.ts:1650-1664, rows from leoHandoffEvents
//           drizzle/schema.ts:1881). Ownership re-checked at escorts.ts:1643-1644.
//    EXISTS escorts.getRouteSurvey        escorts.ts:1539 — the ONLY lane the
//           platform timestamps (startedAt / completedAt / hazard loggedAt).
//           Hazard kind enum carries UTILITY_LINE at drizzle/schema.ts:1866.
//    EXISTS escorts.getPermits            escorts.ts:2178 — ESCORT-HELD
//           `certifications` rows WHERE type LIKE '%permit%' (escorts.ts:2184-2186).
//           These are NOT the load's OS/OW permit and the face says so.
//    EXISTS escorts.getPermitStats        escorts.ts:2199
//    EXISTS escorts.getOversizeChecklist  escorts.ts:3376 — but a PURE FUNCTION.
//           `.query(({ input }) => {...})` at escorts.ts:3384 takes no ctx and
//           touches no db, so TICK STATE CANNOT BE SAVED. Its 13 items feed the
//           UNTIMED gutter as GUIDANCE and no tick affordance is drawn.
//           utility_notification escorts.ts:3398 (heightFt > 16),
//           dot_notification :3396, law_enforcement :3397.
//    EXISTS escorts.notifyIncomingOfficer escorts.ts:1811 (MUT · ONLINE_ONLY)
//           {handoffId, etaMinutes 1...480}; ownership join escorts.ts:1823-1825;
//           refuses a completed handoff escorts.ts:1828 (:1827 is the NOT_FOUND
//           guard); audits escorts.ts:1830;
//           emits WS_EVENTS.ESCORT_LEO_INCOMING_ETA from escorts.ts:1847.
//    EXISTS escorts.scheduleHandoff       escorts.ts:1583 (MUT · ONLINE_ONLY)
//           inserts leoHandoffEvents at escorts.ts:1604 — NO emit, NO audit.
//    EXISTS-BUT-ROLE-BLOCKED escorts.resolveLeoNoShow escorts.ts:1857 —
//           roleProcedure(ROLES.DISPATCH, ROLES.ADMIN). AN ESCORT CANNOT CALL IT,
//           so no escort-side resolve control exists anywhere on this screen.
//    EXISTS-BUT-WRITE-ONLY escorts.recordDOTNotification escorts.ts:3407 — raw
//           `INSERT INTO system_alerts` escorts.ts:3421-3428. There is no typed
//           Drizzle table (`grep "systemAlerts = mysqlTable" drizzle/*.ts` → 0)
//           and NO procedure in the tree reads a notification back. The CBP·SICT
//           lane is therefore drawn dark: WRITE-ONLY · NO READ-BACK. A "Notified"
//           tick here would be a lie the moment the user reloads, so none exists.
//
//  T-0 ANCHOR — THERE IS NO SERVER DEPARTURE FIELD ON THE ESCORT SURFACE.
//    escorts.getActiveAssignments (escorts.ts:3580) returns startedAt through
//    relativeShort() at escorts.ts:3625 — a RELATIVE STRING, not an instant.
//    T-0 is therefore the earliest leoHandoffEvents.scheduledAt (escorts.ts:1656)
//    and the right edge is labelled T-0 · GATE 1, never "DEPART". Gates whose
//    scheduledAt falls after T-0 are drawn as an off-board arrow, never faked
//    onto the axis. If no handoff carries a scheduledAt, the board refuses to
//    draw an axis at all rather than synthesise one.
//
//  STUB LIST — `grep -rn "<pattern>" server/ drizzle/ --include=*.ts`
//    movePlan / move_plan / movePlanning       → 0
//    utilityLift / utility_lift / lineLift     → 0  ("utility lift" appears ONCE,
//                                                     seeded prose drizzle/c_oversize.cjs:13)
//    signalLift / "signal lift"                → 0
//    stagingPlan / overnightStaging            → 0
//    staggeredDeparture                        → 0
//    permitAmendment / amendPermit             → 0  no amend affordance is drawn
//    policeNotification / notifyPolice         → 0
//    policeFee / "police fee" / police_escort  → 0  the 12 policeEscort hits are a
//                                                     BOOLEAN in a hard-coded lookup at
//                                                     server/routers/convoy.ts:455-465
//    callSign                                  → 12 ALL MARITIME; call_sign → 0
//    "72-hour" in escort scope                 → 0  the axis is CLIENT-SIDE, said on glass
//    escort-side convoy composition            → dispatcher-authored.
//        dispatch.composeConvoy dispatch.ts:3589 (CITATION DRIFT CORRECTED — the
//        handed-down 3568 and 3592 are both stale; the block comment opens at
//        dispatch.ts:3580). Its own comment at dispatch.ts:3666-3671 admits
//        `escortUserId` is a dispatch-authored placeholder. No composition
//        control is drawn.
//    ES-04 permit linkage (ledger ESC-04-BE) re-grepped this fire —
//        escort.permit.getRequirements → 0, overrideSegment → 0,
//        getMySegmentRequirements → 0, flagPoliceCoordination → 0. Still absent.
//
//  PERSIST · AUDIT · REALTIME — notifyIncomingOfficer writes
//    leoHandoffEvents.etaMinutes (escorts.ts:1829); scheduleHandoff inserts a row
//    (escorts.ts:1604); recordDOTNotification raw-inserts system_alerts
//    (escorts.ts:3421). NO `blockchainAuditTrail` row is inserted by any of them —
//    the token appears ZERO times in escorts.ts and ZERO times in hazmatEscort.ts;
//    the escort tree's audit surface is recordAuditEvent() from _core/auditService
//    (imported escorts.ts:17, called at :110, 607, 1282, 1712, 1788, 1830, 1881,
//    2569, 3836, 4486), a different table. WS: ESCORT_LEO_INCOMING_ETA
//    (shared/websocket-events.ts:267) → DISPATCH_UPDATES (escorts.ts:1851) +
//    LOAD(loadId) (escorts.ts:1852). SUBSCRIBER STATUS ZERO ON BOTH CLIENTS —
//    `grep "leo_no_show|leo_officer|leo_handoff|leo_incoming" --include=*.swift` → 0,
//    `grep "escort:leo" client/src` → 0. NO LANE SELF-UPDATES; the board is
//    pull-only and says so.
//
//  RBAC — every procedure here is escortProcedure, aliased to the local name
//    protectedProcedure at escorts.ts:11, which is roleProcedure(ROLES.ESCORT) at
//    _core/trpc.ts:228 (factory at _core/trpc.ts:216) over ROLES.ESCORT at
//    _core/trpc.ts:23. Row scope via resolveEscortUserId (escorts.ts:138);
//    foreign rows return honest-empty. Zero dollars on this surface.
//
//  CHAIN — read CLOSED for lanes 1, 2, 4, 5. notifyIncomingOfficer ONE-SIDED
//    (dispatcher hears it; the escort does not, no subscriber exists).
//    scheduleHandoff CLOSED for read-back, SILENT for fan-out.
//    recordDOTNotification ONE-SIDED AND TERMINAL. Utility/signal lanes N-A.
//    resolveLeoNoShow N-A FOR THIS ROLE by RBAC.
//
//  OFFLINE (§W) — ONLINE_ONLY. Coordination state must never be served stale: a
//    cached LEO lane would hide a lane going behind, which is the one thing this
//    board exists to show. Nothing is read from EscortOfflineCache, so no
//    staleness line is drawn — there is no cached paint to qualify. There is no
//    escort outbox on the phone, so A QUEUE BADGE IS NEVER DRAWN. On a failed
//    read the board renders empty with the reason, never last-known nodes.
//
//  TYPE SEAM, carried deliberately — MySQL `decimal` columns serialize as JSON
//    STRINGS, not Doubles. escortSurveys.vehicleHeightFt / vehicleWidthFt and
//    escortSurveyHazards.lat / lng / measuredClearanceFt are all decimal, so
//    they are decoded as String? here. leoHandoffEvents.boundaryLat/Lng are
//    written as `String(...)` at escorts.ts:1600-1601 for the same reason.
//    Typing any of them as Double is how three escort screens have already died.
//

import SwiftUI

// MARK: - Wire DTOs (typed against what the producer actually emits)

private struct ES23Officer: Codable, Equatable {
    let name: String?
    let badgeNumber: String?
    let agency: String?
    let contact: String?
    let onSceneAt: String?
}

/// escorts.getHandoffs · escorts.ts:1650-1664.
private struct ES23Handoff: Codable, Equatable, Identifiable {
    let handoffId: Int
    let stateFrom: String?
    let stateTo: String?
    /// enum ["scheduled","arrived","completed","no_show"]
    let status: String?
    let agency: String?
    let officerRef: String?
    let scheduledAt: String?
    let actualAt: String?
    let notes: String?
    let outgoingOfficers: [ES23Officer]?
    let incomingOfficers: [ES23Officer]?
    let checklistCompleted: [String: Bool]?
    let locationLabel: String?
    let etaMinutes: Int?
    let etaRelayedAt: String?
    let platformRecipientCount: Int?
    let directOfficerDeliveryState: String?

    var id: Int { handoffId }
}

/// escorts.getRouteSurvey · escorts.ts:1559-1575. `vehicleHeightFt` and
/// `vehicleWidthFt` are decimal columns → JSON strings.
private struct ES23Survey: Codable, Equatable {
    let surveyId: Int?
    let status: String?
    let vehicleHeightFt: String?
    let vehicleWidthFt: String?
    let summary: String?
    let startedAt: String?
    let completedAt: String?
}

/// `lat`, `lng` and `measuredClearanceFt` are decimal columns → JSON strings.
private struct ES23Hazard: Codable, Equatable, Identifiable {
    let hazardId: Int
    let seq: Int?
    /// enum includes UTILITY_LINE · drizzle/schema.ts:1866
    let kind: String?
    let lat: String?
    let lng: String?
    let measuredClearanceFt: String?
    let photoUrl: String?
    let note: String?
    let loggedAt: String?

    var id: Int { hazardId }
}

private struct ES23SurveyEnvelope: Codable, Equatable {
    let survey: ES23Survey?
    let hazards: [ES23Hazard]?
}

/// escorts.getPermits · escorts.ts:2187-2195.
private struct ES23Permit: Codable, Equatable, Identifiable {
    let id: String
    let type: String?
    let name: String?
    let status: String?
    let expiryDate: String?
    let documentUrl: String?
    let createdAt: String?
}

private struct ES23PermitStats: Codable, Equatable {
    let activePermits: Int?
    let expiringSoon: Int?
    let statesCovered: Int?
    let certifications: Int?
}

/// escorts.getOversizeChecklist · escorts.ts:3386-3399. A PURE FUNCTION —
/// guidance only, tick state cannot be persisted.
private struct ES23ChecklistItem: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let required: Bool
    let category: String?
}

private struct ES23Checklist: Codable, Equatable {
    let items: [ES23ChecklistItem]?
    let state: String?
    let totalRequired: Int?
}

private struct ES23AssignmentIdInput: Encodable { let assignmentId: Int }
private struct ES23ChecklistInput: Encodable {
    let state: String
    let heightFt: Double?
    let widthFt: Double?
    let weightLbs: Double?
}
private struct ES23NotifyInput: Encodable {
    let handoffId: Int
    let etaMinutes: Int
    let requestKey: String
}
private struct ES23DirectOfficerDelivery: Decodable {
    let state: String
    let reason: String?
}
private struct ES23NotifyResult: Decodable {
    let relayId: Int?
    let handoffId: Int?
    let etaMinutes: Int?
    let platformRecipientCount: Int?
    let directOfficerDelivery: ES23DirectOfficerDelivery?
    let idempotent: Bool?
}
private struct ES23ScheduleInput: Encodable {
    let assignmentId: Int
    let stateFrom: String
    let stateTo: String
    let scheduledAt: String?
    let agency: String?
}
private struct ES23ScheduleResult: Decodable { let handoffId: Int?; let status: String? }

// MARK: - Board model

enum ES23Placement: Equatable {
    case timed(hoursBeforeZero: Double)
    case untimed
    case offBoard
    case notOnTheWire
}

enum ES23Verdict: Equatable { case met, open, behind, expiring, writeOnly, absent }

struct ES23Node: Identifiable, Equatable {
    let id: String
    let label: String
    let placement: ES23Placement
    let verdict: ES23Verdict
}

struct ES23Lane: Identifiable, Equatable {
    enum Wire: Equatable { case readable, writeOnly, dark }
    let id: String
    let party: String
    let sub: String
    let wire: Wire
    let verdict: ES23Verdict
    let nodes: [ES23Node]
    let note: String?
    let darkGrep: String?
    /// Set only on LEO lanes — the handoff the CTA acts on.
    let handoffId: Int?

    var isDark: Bool { wire == .dark }
}

/// Equal pitch, unequal hour spans. The near term is where coordination
/// actually breaks, so six hours get the same width as a whole day at the far
/// end — and the board prints EQUAL PITCH · UNEQUAL HOURS on its own face so
/// nobody misreads the scale.
enum ES23Axis {
    static let ticks: [Double] = [72, 48, 24, 12, 6, 0]
    static let labels: [String] = ["T-72", "T-48", "T-24", "T-12", "T-6", "T-0"]

    static func fraction(hoursBeforeZero h: Double) -> Double {
        let clamped = min(max(h, 0), 72)
        for i in 0..<(ticks.count - 1) {
            let hi = ticks[i], lo = ticks[i + 1]
            if clamped <= hi && clamped >= lo {
                let within = hi == lo ? 0 : (hi - clamped) / (hi - lo)
                return (Double(i) + within) / Double(ticks.count - 1)
            }
        }
        return 1
    }
}

// MARK: - Screen

struct EscortMovePlanES23: View {

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var session: EusoTripSession

    /// The assignment this board coordinates. Supplied by the registry; the
    /// screen never guesses one.
    let assignmentId: Int
    /// The two-letter state the oversize checklist is generated for.
    let state: String
    let heightFt: Double?
    let widthFt: Double?
    let weightLbs: Double?

    init(assignmentId: Int,
         state: String,
         heightFt: Double? = nil,
         widthFt: Double? = nil,
         weightLbs: Double? = nil) {
        self.assignmentId = assignmentId
        self.state = state
        self.heightFt = heightFt
        self.widthFt = widthFt
        self.weightLbs = weightLbs
    }

    private enum Phase: Equatable {
        case loading
        case live
        /// The read did not answer. NO last-known board is painted — a stale
        /// lane would hide a lane going behind.
        case failed(String)
        case empty
    }

    private enum Commit: Equatable { case idle, inFlight, done(String), failed(String) }

    @State private var phase: Phase = .loading
    @State private var handoffs: [ES23Handoff] = []
    @State private var survey: ES23SurveyEnvelope? = nil
    @State private var permits: [ES23Permit] = []
    @State private var stats: ES23PermitStats? = nil
    @State private var checklist: ES23Checklist? = nil
    @State private var relay: Commit = .idle
    /// Retained across failed attempts so a retry cannot create a duplicate
    /// relay, notification set, or audit intent.
    @State private var relayRequestKey = UUID()
    @State private var now = Date()

    private var isDark: Bool { scheme == .dark }
    private var greenInk: Color  { isDark ? Color(hex: 0x34D399) : Color(hex: 0x0B7A4B) }
    private var amberInk: Color  { isDark ? Color(hex: 0xFBBF24) : Color(hex: 0xB45309) }
    private var dangerInk: Color { isDark ? Color(hex: 0xF87171) : Color(hex: 0xB91C1C) }
    private var blueInk: Color   { isDark ? Color(hex: 0x60A5FA) : Brand.blue }
    private let good   = Color(hex: 0x10B981)
    private let amber  = Color(hex: 0xF59E0B)
    private let danger = Color(hex: 0xEF4444)

    private var cardRim: LinearGradient {
        LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            eyebrow
            header
            IridescentHairline()
            metaRow
            content
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s2)
        .task { await refresh() }
        .eusoRefreshable { await refresh() }
    }

    // MARK: Header

    private var eyebrow: some View {
        HStack {
            EusoTripEyebrow(verbatim: "ESCORT · MOVE PLAN")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: Space.s2)
            Text("ASSIGNMENT \(assignmentId)")
                .font(EType.mono(.micro)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headline)
                .font(.system(size: 34, weight: .bold)).tracking(-0.6)
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(subline)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
    }

    /// The H1 is the distance to the binding instant. The noun is GATE 1, not
    /// "departure", because no departure field exists on this surface. If no
    /// gate carries a scheduledAt, the H1 SAYS SO rather than inventing a clock.
    private var headline: String {
        guard let h = hoursToZero else { return "No gate scheduled" }
        return "T-\(Int(h))h to gate 1"
    }

    private var subline: String {
        guard let h = hoursToZero else {
            return "No leoHandoffEvents row carries a scheduledAt — no axis can be drawn"
        }
        let hh = Int(h), mm = Int((h - Double(hh)) * 60)
        let behind = lanes.filter { $0.verdict == .behind }.count
        return "\(hh) h \(mm) m out · \(lanes.count) coordinating parties · "
            + "\(behind) lane\(behind == 1 ? "" : "s") behind"
    }

    private var metaRow: some View {
        HStack(spacing: Space.s2) {
            chip("\(handoffs.count) GATES", ink: blueInk, tint: Brand.blue.opacity(0.12))
            if let w = weightLbs, w > 150_000 {
                chip("SUPERLOAD", ink: isDark ? Color(hex: 0xC084FC) : Color(hex: 0x7C3AED),
                     tint: Brand.magenta.opacity(0.12))
            }
            if crossesBorder {
                chip("US → MX", ink: greenInk, tint: good.opacity(0.14))
            }
            Spacer(minLength: Space.s2)
            Text(session.user?.name ?? "—")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
    }

    private func chip(_ text: String, ink: Color, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .foregroundStyle(ink)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(tint))
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            loadingBand
        case .failed(let why):
            failureBand(why)
        case .empty:
            emptyBand
        case .live:
            VStack(alignment: .leading, spacing: Space.s4) {
                sectionHeader
                boardCard
                behindBand
                honestyBlock
                ctaBand
            }
        }
    }

    private var loadingBand: some View {
        Text("Reading the coordination lanes…")
            .font(EType.body).foregroundStyle(palette.textSecondary)
            .padding(.vertical, Space.s6)
    }

    /// Fail closed, loudly. An empty board is honest; a remembered board is not.
    private func failureBand(_ why: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("The board did not load")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text(why).font(EType.caption).foregroundStyle(palette.textSecondary)
            Text("AN OLDER COPY IS NOT SHOWN BECAUSE IT COULD HIDE A DELAYED HANDOFF")
                .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .fill(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(palette.borderFaint, lineWidth: 1)))
    }

    private var emptyBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("No coordination rows on this assignment")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text("No coordination steps have been scheduled for this assignment. Ask dispatch to schedule the first jurisdiction handoff.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .fill(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(palette.borderFaint, lineWidth: 1)))
    }

    private var sectionHeader: some View {
        HStack {
            Text("T-MINUS BOARD · \(lanes.count) LANES")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: Space.s2)
            Text("\(lanes.filter { $0.verdict == .behind }.count) BEHIND · "
                 + "\(lanes.filter { $0.verdict == .expiring }.count) EXPIRING · "
                 + "\(lanes.filter { $0.wire != .readable }.count) UNAVAILABLE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    // MARK: The board

    private var boardCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            axisStrip
            Divider().overlay(palette.borderFaint)
            ForEach(Array(lanes.enumerated()), id: \.element.id) { idx, lane in
                laneRow(lane)
                if idx < lanes.count - 1 { Divider().overlay(palette.borderFaint) }
            }
            boardFooter
        }
        .padding(.vertical, Space.s2)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .fill(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(palette.borderFaint, lineWidth: 1)))
    }

    private var axisStrip: some View {
        HStack(spacing: 0) {
            Text("PARTY").font(.system(size: 7, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 76, alignment: .leading)
            Text("UNTIMED").font(.system(size: 7, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 50)
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    ForEach(Array(ES23Axis.labels.enumerated()), id: \.offset) { i, label in
                        Text(label)
                            .font(.system(size: 7.5, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(i == ES23Axis.labels.count - 1
                                             ? palette.textPrimary : palette.textTertiary)
                            .fixedSize()
                            .position(x: CGFloat(Double(i) / Double(ES23Axis.ticks.count - 1))
                                      * geo.size.width, y: 6)
                    }
                }
            }
            .frame(height: 14)
        }
        .padding(.horizontal, Space.s3)
        .padding(.bottom, Space.s1)
    }

    private func laneRow(_ lane: ES23Lane) -> some View {
        HStack(alignment: .top, spacing: 0) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 1.5).fill(railColor(lane))
                    .frame(width: 3, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(lane.party)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(labelInk(lane))
                    Text(lane.sub).font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                }
                .lineLimit(1).minimumScaleFactor(0.75)
            }
            .frame(width: 76, alignment: .leading)

            HStack(spacing: 5) {
                ForEach(lane.nodes.filter { $0.placement == .untimed
                                         || $0.placement == .notOnTheWire }) { n in
                    nodeGlyph(n, small: true)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 50, alignment: .leading)
            .overlay(alignment: .trailing) {
                Rectangle().fill(palette.textTertiary.opacity(0.45)).frame(width: 1)
                    .mask(VStack(spacing: 3) {
                        ForEach(0..<9, id: \.self) { _ in Rectangle().frame(height: 3) } })
            }

            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    if lane.isDark || lane.wire == .writeOnly {
                        darkPill(lane, width: geo.size.width)
                    }
                    ForEach(lane.nodes.filter { if case .timed = $0.placement { return true }
                                                return false }) { n in
                        plottedNode(n, width: geo.size.width)
                    }
                    if lane.nodes.contains(where: { $0.placement == .offBoard }) {
                        Text("GATE IS AFTER T-0 →")
                            .font(.system(size: 7, weight: .bold)).tracking(0.3)
                            .foregroundStyle(palette.textTertiary)
                            .position(x: geo.size.width - 52, y: 14)
                    }
                    if let note = lane.note {
                        Text(note).font(EType.mono(.micro))
                            .foregroundStyle(lane.verdict == .behind ? dangerInk
                                                                     : palette.textTertiary)
                            .fixedSize()
                            .position(x: CGFloat(note.count) * 2.1, y: 34)
                    }
                }
            }
            .frame(height: 44)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 3)
    }

    private func plottedNode(_ n: ES23Node, width: CGFloat) -> some View {
        var f = 0.0
        if case let .timed(h) = n.placement { f = ES23Axis.fraction(hoursBeforeZero: h) }
        return VStack(spacing: 3) {
            nodeGlyph(n, small: false)
            Text(n.label).font(.system(size: 7, weight: .bold)).tracking(0.3)
                .foregroundStyle(verdictInk(n.verdict)).fixedSize()
        }
        .position(x: min(max(CGFloat(f) * width, 14), width - 14), y: 18)
    }

    @ViewBuilder
    private func nodeGlyph(_ n: ES23Node, small: Bool) -> some View {
        let d: CGFloat = small ? 11 : 13
        switch n.verdict {
        case .met:
            ZStack {
                Circle().fill(good)
                Image(systemName: "checkmark")
                    .font(.system(size: d * 0.52, weight: .heavy)).foregroundStyle(.white)
            }.frame(width: d, height: d)
        case .open:
            Circle().stroke(palette.textTertiary, lineWidth: 1.6)
                .background(Circle().fill(palette.bgCard))
                .frame(width: d, height: d)
        case .behind:  bangGlyph(danger, d: d)
        case .expiring: bangGlyph(amber, d: d)
        case .writeOnly:
            Circle().strokeBorder(amber, style: StrokeStyle(lineWidth: 1.5, dash: [2.4, 2.4]))
                .overlay(Circle().fill(amber).frame(width: 3.6, height: 3.6))
                .frame(width: d, height: d)
        case .absent:
            Circle().strokeBorder(palette.textTertiary,
                                  style: StrokeStyle(lineWidth: 1.4, dash: [2.4, 2.4]))
                .frame(width: d, height: d)
        }
    }

    private func bangGlyph(_ fill: Color, d: CGFloat) -> some View {
        ZStack {
            Circle().fill(fill)
            Text("!").font(.system(size: d * 0.62, weight: .black)).foregroundStyle(.white)
        }.frame(width: d, height: d)
    }

    private func darkPill(_ lane: ES23Lane, width: CGFloat) -> some View {
        let ink = lane.wire == .writeOnly ? amberInk : palette.textTertiary
        return HStack {
            if let g = lane.darkGrep {
                Text(g).font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 6)
            Text(lane.wire == .writeOnly ? "WRITE-ONLY · NO READ-BACK" : "NOT ON THE WIRE")
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.5)
                .foregroundStyle(ink)
        }
        .lineLimit(1).minimumScaleFactor(0.7)
        .padding(.horizontal, 8)
        .frame(width: max(width - 6, 0), height: 22)
        .overlay(Capsule().strokeBorder(ink.opacity(0.7),
                                        style: StrokeStyle(lineWidth: 1.2, dash: [3, 3])))
        .position(x: width / 2 - 3, y: 15)
    }

    private var boardFooter: some View {
        HStack {
            Text("EQUAL PITCH · UNEQUAL HOURS")
                .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            Spacer(minLength: Space.s2)
            Text("T-0 · \(zeroLabel)")
                .font(.system(size: 7, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textPrimary)
        }
        .lineLimit(1).minimumScaleFactor(0.8)
        .padding(.horizontal, Space.s3).padding(.top, Space.s2)
    }

    private func railColor(_ l: ES23Lane) -> Color {
        switch l.verdict {
        case .behind: return danger
        case .expiring, .writeOnly: return amber
        case .met, .open: return l.isDark ? palette.textTertiary : good
        case .absent: return palette.textTertiary
        }
    }

    private func labelInk(_ l: ES23Lane) -> Color {
        switch l.verdict {
        case .behind: return dangerInk
        case .expiring, .writeOnly: return amberInk
        default: return palette.textPrimary
        }
    }

    private func verdictInk(_ v: ES23Verdict) -> Color {
        switch v {
        case .met: return greenInk
        case .behind: return dangerInk
        case .expiring, .writeOnly: return amberInk
        default: return palette.textTertiary
        }
    }

    // MARK: The blown-open lane — the ONE rimmed ActiveCard

    @ViewBuilder
    private var behindBand: some View {
        if let lane = behindLane {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("THE LANE THAT IS BEHIND")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Spacer(minLength: Space.s2)
                    Text(handoffOrdinal(lane))
                        .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                }
                behindCard(lane)
            }
        }
    }

    private func behindCard(_ lane: ES23Lane) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(lane.party) · lane behind")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: Space.s2)
                Text("UNMET AT NOW")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(dangerInk)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(danger.opacity(0.16)))
            }
            .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
            .background(danger.opacity(0.09))

            Text("Scheduled · target time not provided")
                .font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, Space.s4).padding(.top, Space.s3)

            Divider().overlay(palette.borderFaint)
                .padding(.horizontal, Space.s4).padding(.top, Space.s3)

            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(danger.opacity(0.14))
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(dangerInk))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Incoming officer")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("\(lane.party.uppercased()) · ARRIVAL TIME NOT PROVIDED")
                        .font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: Space.s2)
                // NO DENOMINATOR IS DRAWN. leoHandoffEvents (drizzle/schema.ts:1881)
                // has NO required-officer-count column — `incomingOfficers` is
                // json().$type<Array<{...}>>() at drizzle/schema.ts:1902, a
                // free-length array, and getHandoffs returns it as
                // `incomingOfficers ?? []` (escorts.ts:1660) with no cardinality.
                // There is nothing on this surface that could be the bottom of a
                // fraction, so the slot states the verdict and stops.
                Text("UNASSIGNED")
                    .font(.system(size: 11, weight: .bold)).tracking(0.6)
                    .foregroundStyle(dangerInk)
            }
            .lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, Space.s4).padding(.top, Space.s3)

            Text("YOU CAN NOTIFY THE INCOMING OFFICER · DISPATCH RESOLVES NO-SHOWS")
                .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s3).padding(.bottom, Space.s3)
        }
        .background(RoundedRectangle(cornerRadius: 18.5, style: .continuous).fill(palette.bgCard))
        .padding(1.5)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(cardRim))
    }

    // MARK: Honesty block

    private var honestyBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("72-HOUR VIEW · BASED ON SCHEDULED HANDOFFS")
            Text("LIFT, STAGING, AND DEPARTURE PLANS ARE NOT AVAILABLE ON THIS BOARD")
            Text("UPDATES REQUIRE A CONNECTION · FAILED CHANGES ARE NOT QUEUED")
            if case let .failed(msg) = relay {
                Text(msg.uppercased()).foregroundStyle(dangerInk)
            }
            if case let .done(msg) = relay {
                Text(msg.uppercased()).foregroundStyle(greenInk)
            }
        }
        .font(EType.mono(.micro))
        .foregroundStyle(palette.textTertiary)
        .lineLimit(1).minimumScaleFactor(0.65)
    }

    // MARK: CTA band — both verbs are real, escort-gated, ONLINE_ONLY

    /// The CTA NAMES THE GATE IT ACTUALLY RELAYS TO. The button calls
    /// notifyIncomingOfficer (escorts.ts:1811) with `behindLane.handoffId`, so
    /// the ordinal is that row's position in the server-ordered handoff list
    /// (getHandoffs orders by scheduledAt asc at escorts.ts:1648) — never a
    /// scenario literal. If no lane is behind there is no ordinal to name and
    /// the label drops it rather than guessing.
    private var relayGateLabel: String {
        guard let hid = behindLane?.handoffId,
              let idx = handoffs.firstIndex(where: { $0.handoffId == hid })
        else { return "RELAY ETA" }
        return "RELAY GATE-\(idx + 1) ETA"
    }

    private var ctaBand: some View {
        HStack(spacing: Space.s2) {
            Button {
                Task { await relayIncomingETA() }
            } label: {
                Text(relay == .inFlight ? "RELAYING…" : relayGateLabel)
                    .font(.system(size: 12, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .disabled(relay == .inFlight || behindLane?.handoffId == nil)

            Button {
                NotificationCenter.default.post(name: .esES23ScheduleGate, object: nil,
                                                userInfo: ["assignmentId": assignmentId])
            } label: {
                Text("+ SCHEDULE GATE")
                    .font(.system(size: 11.5, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 144).frame(height: 42)
                    .background(Capsule().fill(palette.bgCard)
                        .overlay(Capsule().stroke(palette.borderSoft, lineWidth: 1)))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Derived board

    /// T-0 is the earliest `scheduledAt` across the assignment's handoff rows.
    /// If none exists, there is no axis and the screen says so.
    private var zeroDate: Date? {
        handoffs.compactMap { parseISO($0.scheduledAt) }.min()
    }

    private var hoursToZero: Double? {
        guard let z = zeroDate else { return nil }
        let s = z.timeIntervalSince(now)
        return s <= 0 ? 0 : s / 3600
    }

    private var zeroLabel: String {
        guard let z = zeroDate else { return "NOT ON THE WIRE" }
        let f = DateFormatter()
        f.dateFormat = "EEE HH:mm"
        return f.string(from: z).uppercased()
    }

    /// MX terminus is CONTENT, not a fork. A handoff whose `stateTo` is not a US
    /// state code lights the border lane on the same lane structure.
    private var crossesBorder: Bool {
        handoffs.contains { ES23USStates.all.contains($0.stateTo?.uppercased() ?? "") == false
                         && ($0.stateTo?.isEmpty == false) }
    }

    private func hoursBefore(_ iso: String?) -> Double? {
        guard let d = parseISO(iso), let z = zeroDate else { return nil }
        return z.timeIntervalSince(d) / 3600
    }

    private func handoffOrdinal(_ lane: ES23Lane) -> String {
        guard let hid = lane.handoffId,
              let idx = handoffs.firstIndex(where: { $0.handoffId == hid }) else { return "—" }
        return "HANDOFF \(idx + 1) OF \(handoffs.count)"
    }

    private var behindLane: ES23Lane? { lanes.first { $0.verdict == .behind } }

    /// Lane assembly. Every placed node comes from a real server timestamp.
    /// Every obligation the server holds without one lands in the UNTIMED
    /// gutter. Everything the server does not hold at all becomes a real lane
    /// with unplaced dashed nodes and a NOT ON THE WIRE marker.
    private var lanes: [ES23Lane] {
        var out: [ES23Lane] = []

        // 1..n — one lane per LEO jurisdiction.
        for (i, h) in handoffs.enumerated() {
            let isBorder = (h.stateTo.map { !ES23USStates.all.contains($0.uppercased()) } ?? false)
            let agencySet = (h.agency?.isEmpty == false)
            let outgoing = h.outgoingOfficers?.count ?? 0
            let incoming = h.incomingOfficers?.count ?? 0
            let etaKnown = h.etaMinutes != nil
            // Behind-ness is judged on SERVER STATE AT NOW, never on an invented
            // due date, because no preparation obligation carries a due column.
            let unmet = (incoming == 0 || !etaKnown) && h.status == "scheduled"

            var nodes: [ES23Node] = [
                ES23Node(id: "h\(h.handoffId)-agency", label: "AGENCY",
                         placement: .untimed, verdict: agencySet ? .met : (unmet ? .behind : .open)),
                ES23Node(id: "h\(h.handoffId)-officers", label: "OFFICERS",
                         placement: .untimed,
                         verdict: (outgoing > 0 && incoming > 0) ? .met : (unmet ? .behind : .open)),
            ]
            if let hb = hoursBefore(h.scheduledAt) {
                if hb >= 0 {
                    nodes.append(ES23Node(id: "h\(h.handoffId)-gate", label: gateClock(h),
                                          placement: .timed(hoursBeforeZero: hb),
                                          verdict: h.status == "completed" ? .met : .open))
                } else {
                    nodes.append(ES23Node(id: "h\(h.handoffId)-gate", label: "GATE",
                                          placement: .offBoard, verdict: .open))
                }
            }
            out.append(ES23Lane(
                id: "leo-\(h.handoffId)",
                party: laneName(h, index: i),
                sub: "GATE \(i + 1) · \(h.stateTo?.uppercased() ?? "—")",
                wire: isBorder ? .writeOnly : .readable,
                verdict: isBorder ? .writeOnly : (unmet ? .behind : .open),
                nodes: nodes,
                note: isBorder
                    ? "CARGA ANCHA → OVERSIZE LOAD · MXN/USD TOLL"
                    : (unmet ? "incomingOfficers [] · etaMinutes null" : nil),
                darkGrep: nil,
                handoffId: h.handoffId))
        }

        // Survey — the only lane the platform timestamps.
        if let env = survey {
            var nodes: [ES23Node] = []
            if env.survey?.completedAt == nil {
                nodes.append(ES23Node(id: "sv-approval", label: "APPROVAL",
                                      placement: .untimed, verdict: .absent))
            }
            if let hb = hoursBefore(env.survey?.startedAt), hb >= 0 {
                nodes.append(ES23Node(id: "sv-start", label: "START",
                                      placement: .timed(hoursBeforeZero: hb), verdict: .met))
            }
            let utility = (env.hazards ?? []).filter { $0.kind == "UTILITY_LINE" }
            if let first = utility.first, let hb = hoursBefore(first.loggedAt), hb >= 0 {
                nodes.append(ES23Node(id: "sv-haz", label: "\(utility.count) UTIL",
                                      placement: .timed(hoursBeforeZero: hb), verdict: .met))
            }
            if let hb = hoursBefore(env.survey?.completedAt), hb >= 0 {
                nodes.append(ES23Node(id: "sv-done", label: "SUBMIT",
                                      placement: .timed(hoursBeforeZero: hb), verdict: .met))
            }
            out.append(ES23Lane(id: "survey", party: "SURVEY", sub: "ROUTE + HAZ",
                                wire: .readable,
                                verdict: env.survey?.completedAt == nil ? .open : .met,
                                nodes: nodes, note: nil, darkGrep: nil, handoffId: nil))
        }

        // Permits — escort-held certifications rows, NOT the load's OS/OW paper.
        var permitNodes: [ES23Node] = [
            ES23Node(id: "pm-states", label: "STATES", placement: .untimed,
                     verdict: (stats?.statesCovered ?? 0) > 0 ? .met : .absent),
        ]
        if checklist?.items?.contains(where: { $0.id == "permit_in_cab" }) == true {
            permitNodes.append(ES23Node(id: "pm-cab", label: "CAB COPY",
                                        placement: .untimed, verdict: .absent))
        }
        var permitVerdict: ES23Verdict = .open
        for p in permits {
            guard let hb = hoursBefore(p.expiryDate), hb >= 0, hb <= 72 else { continue }
            permitNodes.append(ES23Node(id: "pm-\(p.id)", label: "EXPIRES",
                                        placement: .timed(hoursBeforeZero: hb),
                                        verdict: .expiring))
            permitVerdict = .expiring
        }
        out.append(ES23Lane(id: "permits", party: "PERMITS", sub: "TXDMV · SICT",
                            wire: .readable, verdict: permitVerdict, nodes: permitNodes,
                            note: "ESCORT-HELD · NOT LOAD OS/OW", darkGrep: nil, handoffId: nil))

        // The two lanes the platform does not carry at all. Drawn as REAL lanes
        // with unplaced dashed nodes — the structure is the design truth even
        // where the data is absent.
        out.append(darkLane(id: "utility", party: "UTILITY",
                            sub: utilitySub, grep: "grep utilityLift → 0"))
        out.append(darkLane(id: "signals", party: "SIGNALS",
                            sub: "SIGNAL LIFTS", grep: "grep signalLift → 0"))
        return out
    }

    /// The checklist's `utility_notification` item (escorts.ts:3398) is the only
    /// server-side acknowledgement that overhead wire lifts exist at all. Its
    /// presence sets this lane's subtitle; it never implies a tracked lift.
    private var utilitySub: String {
        let required = checklist?.items?.first(where: { $0.id == "utility_notification" })?.required
        return required == true ? "WIRE LIFTS REQ" : "WIRE LIFTS"
    }

    private func darkLane(id: String, party: String, sub: String, grep: String) -> ES23Lane {
        ES23Lane(id: id, party: party, sub: sub, wire: .dark, verdict: .absent,
                 nodes: (1...3).map { ES23Node(id: "\(id)-\($0)", label: "",
                                               placement: .notOnTheWire, verdict: .absent) },
                 note: nil, darkGrep: grep, handoffId: nil)
    }

    private func laneName(_ h: ES23Handoff, index: Int) -> String {
        if let a = h.agency, !a.isEmpty { return String(a.prefix(11)).uppercased() }
        return "GATE \(index + 1)"
    }

    private func gateClock(_ h: ES23Handoff) -> String {
        guard let d = parseISO(h.scheduledAt) else { return "GATE" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private func parseISO(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let a = ISO8601DateFormatter()
        a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = a.date(from: s) { return d }
        let b = ISO8601DateFormatter()
        b.formatOptions = [.withInternetDateTime]
        return b.date(from: s)
    }

    // MARK: - Service seam · ONLINE_ONLY, nothing cached, nothing swallowed

    private func refresh() async {
        await MainActor.run { phase = .loading; now = Date() }

        // The LEO lanes are the board's spine and its axis anchor. If this read
        // fails the board does not exist, so its error is not swallowed.
        let rows: [ES23Handoff]
        do {
            rows = try await EusoTripAPI.shared.query(
                "escorts.getHandoffs",
                input: ES23AssignmentIdInput(assignmentId: assignmentId))
        } catch {
            await MainActor.run {
                phase = .failed("Coordination steps couldn't be loaded. Check your connection and try again.")
            }
            return
        }
        guard !rows.isEmpty else {
            await MainActor.run { handoffs = []; phase = .empty }
            return
        }

        // The supporting lanes may legitimately be empty. Each failure is
        // recorded as an ABSENT lane, never as a silently successful one — a
        // `try?` here is how a screen ships permanently empty and looks fine.
        var surveyEnv: ES23SurveyEnvelope? = nil
        do {
            surveyEnv = try await EusoTripAPI.shared.query(
                "escorts.getRouteSurvey",
                input: ES23AssignmentIdInput(assignmentId: assignmentId))
        } catch {
            ES23Log.readFailed("escorts.getRouteSurvey", error)
        }

        var permitRows: [ES23Permit] = []
        do {
            permitRows = try await EusoTripAPI.shared.queryNoInput("escorts.getPermits")
        } catch {
            ES23Log.readFailed("escorts.getPermits", error)
        }

        var permitStats: ES23PermitStats? = nil
        do {
            permitStats = try await EusoTripAPI.shared.queryNoInput("escorts.getPermitStats")
        } catch {
            ES23Log.readFailed("escorts.getPermitStats", error)
        }

        var list: ES23Checklist? = nil
        do {
            list = try await EusoTripAPI.shared.query(
                "escorts.getOversizeChecklist",
                input: ES23ChecklistInput(state: state, heightFt: heightFt,
                                          widthFt: widthFt, weightLbs: weightLbs))
        } catch {
            ES23Log.readFailed("escorts.getOversizeChecklist", error)
        }

        await MainActor.run {
            handoffs = rows
            survey = surveyEnv
            permits = permitRows
            stats = permitStats
            checklist = list
            now = Date()
            phase = .live
        }
    }

    /// The server commits the relay, platform notifications, and audit intent
    /// atomically. Direct officer delivery is a separate state and is never
    /// inferred from a successful platform commit or realtime fan-out.
    private func relayIncomingETA() async {
        guard let hid = behindLane?.handoffId else {
            await MainActor.run { relay = .failed("No handoff row to relay against.") }
            return
        }
        guard let z = zeroDate else {
            await MainActor.run { relay = .failed("No scheduledAt on the gate — nothing to measure an ETA from.") }
            return
        }
        // The server bounds this at 1...480 (escorts.ts:1812); clamp on the
        // client so a valid intent is never rejected as a bad request.
        let minutes = min(max(Int(z.timeIntervalSince(Date()) / 60), 1), 480)
        await MainActor.run { relay = .inFlight }
        do {
            let res: ES23NotifyResult = try await EusoTripAPI.shared.mutation(
                "escorts.notifyIncomingOfficer",
                input: ES23NotifyInput(
                    handoffId: hid,
                    etaMinutes: minutes,
                    requestKey: relayRequestKey.uuidString.lowercased()))
            guard let relayId = res.relayId, relayId > 0, res.handoffId == hid else {
                await MainActor.run { relay = .failed("Not confirmed — treat the ETA as NOT relayed.") }
                return
            }
            let recipients = res.platformRecipientCount ?? 0
            let officerState = res.directOfficerDelivery?.state ?? "unknown"
            let officerCopy = officerState == "delivered"
                ? "direct officer delivery confirmed"
                : "officer channel \(officerState.replacingOccurrences(of: "_", with: " "))"
            await MainActor.run {
                relay = .done("ETA \(minutes) min committed · \(recipients) platform recipient\(recipients == 1 ? "" : "s") · \(officerCopy)")
                relayRequestKey = UUID()
            }
            await refresh()
        } catch {
            await MainActor.run {
                relay = .failed("Commit not confirmed. Retry uses the same request key; call the officer by voice.")
            }
        }
    }
}

// MARK: - Support

enum ES23USStates {
    static let all: Set<String> = [
        "AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA","HI","ID","IL","IN","IA","KS","KY",
        "LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ","NM","NY","NC","ND",
        "OH","OK","OR","PA","RI","SC","SD","TN","TX","UT","VT","VA","WA","WV","WI","WY","DC",
    ]
}

/// A read that fails must leave a trace. Silence is what lets a screen ship
/// permanently empty and look healthy.
enum ES23Log {
    static func readFailed(_ path: String, _ error: Error) {
        #if DEBUG
        print("[ES-23] \(path) failed: \(error)")
        #endif
    }
}

extension Notification.Name {
    static let esES23ScheduleGate = Notification.Name("esES23ScheduleGate")
}

// MARK: - Screen wrapper

struct EscortMovePlanES23Screen: View {
    let theme: Theme.Palette
    let assignmentId: Int
    let state: String
    var heightFt: Double? = nil
    var widthFt: Double? = nil
    var weightLbs: Double? = nil

    var body: some View {
        Shell(theme: theme) {
            EscortMovePlanES23(assignmentId: assignmentId, state: state,
                               heightFt: heightFt, widthFt: widthFt, weightLbs: weightLbs)
        } nav: {
            BottomNav(leading: es23NavLeading(),
                      trailing: es23NavTrailing(),
                      orbState: .idle)
        }
    }
}

private func es23NavLeading() -> [NavSlot] { EscortNavRoute.leading(current: .assignments) }
private func es23NavTrailing() -> [NavSlot] { EscortNavRoute.trailing(current: .assignments) }

#if DEBUG

// `.task` does not run in the preview canvas, so both variants render in
// their loading register without touching the network.

#Preview("ES-23 · Move Plan & Coordination · Light") {
    EscortMovePlanES23Screen(theme: Theme.light, assignmentId: 77104, state: "TX",
                             heightFt: 16.17, widthFt: 18.0, weightLbs: 186_400)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}

#Preview("ES-23 · Move Plan & Coordination · Dark") {
    EscortMovePlanES23Screen(theme: Theme.dark, assignmentId: 77104, state: "TX",
                             heightFt: 16.17, widthFt: 18.0, weightLbs: 186_400)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#endif
