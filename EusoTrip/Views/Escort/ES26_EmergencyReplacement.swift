//
//  ES26_EmergencyReplacement.swift
//  EusoTrip — Escort · Emergency & Replacement (ES-26).
//
//  NEW SURFACE. Nothing on disk owns the escort exception flow today, so
//  this file shadows no brick and edits none. It needs a nav entry it
//  does NOT write: `EscortNavController.swift` is single-writer owned,
//  and the route this screen wants (`"emergency"` →
//  `EscortEmergencyReplacementES26Screen`) is filed in the manifest for
//  that writer, not added here. Until it lands, the screen is reachable
//  only by direct push from ES-16 Active Trip Console.
//
//  Built from the ES-26 design-authority SVG pair
//  ("07 Escort/{Light,Dark}-SVG/ES-26 Emergency Replacement.svg").
//
//  ARCHETYPE — DETAIL · EXCEPTION LADDER ordered by TIME-TO-ACT rather
//  than by entity. The hero is a plan view of the roadway with the three
//  protection layers placed at their real upstream distances; below it,
//  four bands sorted by how soon each must be touched — convoy legality
//  now, replacement inside the half hour, briefing at the handshake,
//  restart last. That is what separates it from ES-10 Assignment Detail
//  (three lifecycle STATIONS of ONE object on a vertical spine), from
//  ES-17 Incidents & Claims (a severity-banded historical ledger with no
//  clock and nothing to do), and from ES-13 Job Marketplace (the same
//  30-mi broadcast seen from OUTSIDE by a bidder, ranked, with radar
//  rings — here it is seen from INSIDE by the operator being replaced,
//  and rendered as a provenance split instead of a rank).
//
//  ─────────────────────────────────────────────────────────────────────
//  WIRING — every anchor below was opened at the pin against the live
//  working tree this fire (frontend/server/routers/escorts.ts, md5
//  064a1b8459b8013613dac05184cf4277, 4,745 lines). Nothing on this
//  surface is seeded: if a read does not answer, the band renders its
//  own absence.
//
//    EXISTS escorts.getActiveTrip            escorts.ts:2787
//           → move header, position, load envelope facts, convoy caps
//    EXISTS convoy.getConvoy                 convoy.ts:175
//           (mounted routers.ts:2247) → the three structural slots.
//           The VACANT chase seat is not a drawing convention: the
//           procedure returns `rear ? {...} : null` at convoy.ts:202,
//           so a missing rear escort is literally the shape of the read.
//    EXISTS escorts.getStateEscortRules      escorts.ts:3433
//           → services/oversizeEnforcement.ts:161 getStateRules; the TX
//           row at services/oversizeEnforcement.ts:69 carries
//           escortThresholds { frontEscortWidth 14, dualEscortWidth 16,
//           escortHeight 17, escortLength 110, escortWeight 200000 }.
//           This is the legality line printed on the verdict bar — a
//           real server constant, not a client guess.
//    EXISTS escorts.analyzeOversize          escorts.ts:3237
//           → escortCount (services/oversizeEnforcement.ts:271-272,
//           emitted :301). HONEST CEILING, rendered on the face: the
//           procedure takes widthFt / heightFt / lengthFt as CLIENT
//           INPUT (escorts.ts:3239-3241) because `loads` has no
//           dimension columns, so this call can only pass the weight it
//           actually has. The verdict states which inputs it stood on.
//    EXISTS escorts.getRouteStates           escorts.ts:3495
//    EXISTS escorts.findQualifiedEscorts     escorts.ts:3445
//           → replacement candidates. Certification filter ONLY: the
//           SQL demands every route state (HAVING stateCount >= n,
//           escorts.ts:3480) and returns no lat/lng, no distance, no
//           ETA, no availability. This screen therefore prints a count
//           and a name and REFUSES to print an ETA.
//    EXISTS escorts.getVehicleCheck          escorts.ts:1310
//           → the restart-inspection state + ESCORT_CHECKLIST_V1.
//    EXISTS escorts.updateJobStatus          escorts.ts:1171
//           → THE RESTART GATE, and the one condition here the server
//           enforces rather than the screen: `en_route` is refused
//           unless a PASSED escortVehicleInspections row exists for the
//           assignment inside 24h (escorts.ts:1185-1194), throwing
//           PRECONDITION_FAILED at escorts.ts:1196. We surface the
//           server's own refusal verbatim; we never pre-empt it with a
//           client guess dressed as a rule.
//    EXISTS escorts.recordDOTNotification    escorts.ts:3407
//           → the state-DOT advisory. HONEST CEILING on the chip: it
//           writes a system_alerts row (escorts.ts:3422) and nothing
//           leaves the building — no DOT endpoint, no confirmation
//           check, and failure is swallowed as {success:false}
//           (escorts.ts:3430). Hence the cell says LOG ONLY.
//    EXISTS roadsideTickets.create           roadsideTickets.ts:110
//           (mounted routers.ts:2215; isolatedProcedure aliased
//           protectedProcedure roadsideTickets.ts:27-29, no role gate,
//           so an escort can genuinely open one; category "tire" from
//           drizzle/schema.additions.wave4-7.ts:72). HONEST CEILING:
//           the row is scoped `driverId = ctx.user.id`
//           (roadsideTickets.ts:119), so an escort files under a
//           driver-named key. It round-trips — `list` reads that same
//           column at roadsideTickets.ts:67 — but the schema does not
//           yet know what an escort is.
//    EXISTS roadsideTickets.list             roadsideTickets.ts:51
//    EXISTS roadsideTickets.policyForCarrier roadsideTickets.ts:251
//           → the repair vendor name + SLA minutes, off
//           roadsidePolicies.preferredProviderJson
//           (drizzle/schema.additions.wave4-7.ts:191-196).
//
//    STUB   30-mi RADIUS — the emergency fan-out payload
//           (escorts.ts:621-626) carries {loadId, loadNumber, position,
//           requestedBy, status, timestamp} and no geo of any kind.
//           Owed: escorts.broadcastEmergencyReplacement({assignmentId,
//           loadId, position, radiusMi, lat, lng, expiresInMin}) →
//           {broadcastId, pinged, radiusMi, expiresAt}.
//    STUB   ESCORT-CALLABLE STAND-DOWN — escorts.requestEscort
//           (escorts.ts:572) is roleProcedure(DRIVER, SHIPPER, CATALYST,
//           BROKER, DISPATCH); ROLES.ESCORT is not in that list, so the
//           operator on the shoulder cannot re-open their own seat and
//           this screen never draws a button that pretends otherwise.
//           Owed: escorts.declareUnitDown({assignmentId, reason, lat,
//           lng}) → {assignmentId, status:'stood_down', seatReopened,
//           broadcastId}.
//    STUB   DEADHEAD / ETA / RESPONSE STATE — no geo on
//           findQualifiedEscorts and no broadcast-response table.
//    STUB   BRIEFING TRANSFER — no procedure, no
//           escort_briefing_transfers table. The payload renders with
//           per-item provenance and 0 acknowledged, never a green tick.
//    STUB   SPLIT PAYOUT — getSettlementDetail (escorts.ts:4598) and
//           createEscortSettlement (escorts.ts:4654) settle ONE whole
//           assignment and escort_assignments has no milesEscorted, so
//           a mid-move handover cannot be prorated. Not drawn.
//    STUB   INCIDENT WRITE — a sweep of escorts.ts finds exactly one
//           db.insert(incidents), inside logClearanceEvent at
//           escorts.ts:4459. There is no escort-callable reportIncident,
//           so the blowout cannot be filed from here.
//    STUB   PROTECTION-LAYER EVIDENCE — nothing anywhere records that a
//           warning device was placed, which is why the layer ticks in
//           this file are DEVICE-LOCAL and labelled as such on glass.
//    STUB   DEVICE GEOMETRY AS DATA — the 10 / 100 / 200 ft placement is
//           a client constant quoting 49 CFR 392.22(b)(2)(v). It is a
//           constant on purpose (see OFFLINE) and it says so.
//
//  ─────────────────────────────────────────────────────────────────────
//  OFFLINE (§W) — this surface is read at the roadside where the bars
//  go, so the split is drawn, not merely declared.
//
//    CACHED · READ_CACHED(15m) through `EscortOfflineCache` (key
//    escort.es26.emergency), repainted with
//    `EscortOfflineCache.stalenessLine(age:)` whenever a snapshot is on
//    glass: the protection protocol and its device geometry (client
//    constants — they cannot fail to load), the move header, the convoy
//    slot map, the legality threshold (a server CONSTANT table, so a
//    cached copy is as true as a live one), the briefing payload, the
//    repair vendor + SLA, and the restart-inspection state.
//
//    NEEDS SIGNAL · never cached, and rendered as its own absence: the
//    replacement candidate set. A stale candidate is worse than none,
//    because the operator would stand on a shoulder waiting for a truck
//    that turned around.
//
//    Mutations ONLINE_ONLY (escort outbox not yet ported — PLANNED per
//    Encyclopedia v2). recordDOTNotification, roadsideTickets.create and
//    updateJobStatus each disable with their own reason on their own
//    face. No queue badge is ever drawn, and the advisory says NOT SENT
//    rather than "queued", because a driver who believes the state has
//    been told makes a different decision about the lane.
//
//  CHAIN — ONE-SIDED, both halves named.
//    C1 SILENT · stand-down → seat re-open → broadcast cannot originate
//       from this device (requestEscort role list, escorts.ts:572) and
//       no unit-down event exists in WS_EVENTS at all. Missing half:
//       escorts.declareUnitDown + an ESCORT_UNIT_DOWN emit.
//    C2 ONE-SIDED · applyForJob fans out to the LOAD room, the catalyst,
//       the driver and the applicant (escorts.ts:915-918) — the OUTGOING
//       escort is none of those four, so the one person the replacement
//       is driving toward is the one person the event never reaches. The
//       iOS half already exists (RealtimeService.swift:451 handles
//       escort:job_applied); the missing half is one more
//       broadcastToChannel on WS_CHANNELS.USER(outgoingEscortUserId).
//       This band therefore polls, and says POLL.
//    C3 ONE-SIDED · the DOT advisory logs and never leaves the building.
//    C4 CLOSED · the restart gate, server-enforced.
//
//  RBAC: every read is escortProcedure aliased protectedProcedure
//  (escorts.ts:11) with row scoping through resolveEscortUserId
//  (escorts.ts:138). findQualifiedEscorts returns other escorts' email
//  and phone; this file binds NEITHER — the match renders as a name and
//  a cert set, and contact is a call affordance, never an address. No
//  loads.rate, no shipper margin, no carrier identity is read here.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI
import CoreLocation

// MARK: - Wire projections (screen-local, private)

/// escorts.getActiveTrip · escorts.ts:2787 — nested load block.
private struct ES26TripLoad: Codable {
    let id: Int?
    let loadNumber: String?
    let status: String?
    let cargoType: String?
    let hazmatClass: String?
    let weight: Double?
    let distance: Double?
    let origin: String?
    let destination: String?
    let specialInstructions: String?
}

/// escorts.getActiveTrip · escorts.ts:2836-2842 — nested convoy block.
private struct ES26TripConvoy: Codable {
    let id: Int?
    let status: String?
    let maxSpeedMph: Int?
    let targetLeadDistanceMeters: Int?
    let targetRearDistanceMeters: Int?
    let currentLeadDistance: Double?
    let currentRearDistance: Double?
}

/// escorts.getActiveTrip · escorts.ts:2819-2845.
private struct ES26ActiveTrip: Codable {
    let assignmentId: Int?
    let assignmentStatus: String?
    let position: String?
    let startedAt: String?
    let load: ES26TripLoad?
    let convoy: ES26TripConvoy?
    let notes: String?
}

/// convoy.getConvoy · convoy.ts:175 — the three structural slots. `rear`
/// is nullable at convoy.ts:202 and that null IS the vacancy.
private struct ES26ConvoySlotMember: Codable {
    let userId: Int?
    let name: String?
}
private struct ES26ConvoySlots: Codable {
    let id: Int?
    let loadId: Int?
    let status: String?
    let lead: ES26ConvoySlotMember?
    let loadVehicle: ES26ConvoySlotMember?
    let rear: ES26ConvoySlotMember?
    let targetLeadDistance: Int?
    let targetRearDistance: Int?
}

/// escorts.getStateEscortRules · escorts.ts:3433 → services/oversizeEnforcement.ts:161.
private struct ES26EscortThresholds: Codable {
    let frontEscortWidth: Double?
    let dualEscortWidth: Double?
    let escortHeight: Double?
    let escortLength: Double?
    let escortWeight: Double?
}
private struct ES26TravelRestrictions: Codable {
    let daylightOnly: Bool?
    let maxSpeed: Double?
    let curfewStart: Int?
    let curfewEnd: Int?
}
private struct ES26StateRules: Codable {
    let escortThresholds: ES26EscortThresholds?
    let travelRestrictions: ES26TravelRestrictions?
    let notes: String?
}
private struct ES26StateEscortRules: Codable {
    let state: String?
    let rules: ES26StateRules?
}

/// escorts.analyzeOversize · escorts.ts:3237 → services/oversizeEnforcement.ts:318-330.
private struct ES26OversizeAnalysis: Codable {
    let isOversize: Bool?
    let isOverweight: Bool?
    let requiresEscort: Bool?
    let escortCount: Int?
    let violations: [String]?
}

/// escorts.getRouteStates · escorts.ts:3495.
private struct ES26RouteStates: Codable {
    let states: [String]?
    let routeStates: [String]?
    var resolved: [String] { states ?? routeStates ?? [] }
}

/// escorts.findQualifiedEscorts · escorts.ts:3445. `email` and `phone`
/// are on the wire and are deliberately NOT decoded here — the surface
/// has no business painting another operator's address.
///
/// The rows come off a raw `db.execute(sql...)` (escorts.ts:3457), so the
/// driver may hand back `id` / `stateCount` as either a number or a
/// string. This decodes leniently on purpose: a type mismatch here would
/// throw the whole candidate read and blank the one band on this screen
/// that tells the operator whether anyone is coming.
private struct ES26Candidate: Codable, Identifiable {
    let userId: Int?
    let name: String?
    let certifiedStates: [String]?

    var id: String { userId.map(String.init) ?? (name ?? UUID().uuidString) }

    private enum CodingKeys: String, CodingKey { case userId, name, certifiedStates }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int.self, forKey: .userId) { userId = i }
        else if let s = try? c.decode(String.self, forKey: .userId) { userId = Int(s) }
        else { userId = nil }
        name = try? c.decode(String.self, forKey: .name)
        certifiedStates = try? c.decode([String].self, forKey: .certifiedStates)
    }
}
private struct ES26QualifiedEscorts: Codable {
    let escorts: [ES26Candidate]?
    let totalAvailable: Int?
    let routeStates: [String]?
}

/// escorts.getVehicleCheck · escorts.ts:1310. `checklist`, `photos` and
/// `failedItems` are free-shaped JSON columns on the row and are NOT
/// projected here — decoding a column whose shape we have not pinned
/// would fail the whole read and silently blank the restart gate.
private struct ES26InspectionLatest: Codable {
    let inspectionId: Int?
    let passed: Bool?
    let signedAt: String?
}
private struct ES26VehicleCheck: Codable {
    let assignmentId: Int?
    let latest: ES26InspectionLatest?
}

/// roadsideTickets.list · roadsideTickets.ts:51.
private struct ES26RoadsideTicket: Codable, Identifiable {
    let id: Int
    let category: String?
    let status: String?
    let description: String?
    let createdAt: String?
}
private struct ES26RoadsideList: Codable { let items: [ES26RoadsideTicket]? }

/// roadsideTickets.policyForCarrier · roadsideTickets.ts:251 →
/// roadsidePolicies.preferredProviderJson.
private struct ES26PreferredProvider: Codable {
    let name: String?
    let slaMinutes: Int?
}
private struct ES26RoadsidePolicy: Codable {
    let coverageLimitCents: Int?
    let preferredProvider: ES26PreferredProvider?
}

// MARK: - Inputs

private struct ES26LoadIdInput: Encodable { let loadId: Int }
private struct ES26StateInput: Encodable { let state: String }
private struct ES26RouteStatesInput: Encodable { let originState: String; let destinationState: String }
private struct ES26AnalyzeInput: Encodable { let weightLbs: Double?; let routeStates: [String] }
private struct ES26QualifiedInput: Encodable { let routeStates: [String]; let position: String }
private struct ES26AssignmentIdInput: Encodable { let assignmentId: Int }
private struct ES26CarrierIdInput: Encodable { let carrierId: Int }
private struct ES26TicketListInput: Encodable { let status: String?; let limit: Int; let offset: Int }
private struct ES26LatLng: Encodable { let lat: Double; let lng: Double }
private struct ES26TicketCreateInput: Encodable {
    let category: String
    let location: ES26LatLng
    let description: String?
}
private struct ES26DOTInput: Encodable {
    let loadId: Int
    let state: String
    let notificationType: String
    let notifiedAt: String
    let notes: String?
}
private struct ES26JobStatusInput: Encodable { let jobId: String; let status: String }

// MARK: - Mutation results

private struct ES26TicketCreateResult: Decodable { let success: Bool?; let ticketId: Int? }
private struct ES26DOTResult: Decodable { let success: Bool?; let recordedAt: String? }
private struct ES26JobStatusResult: Decodable { let success: Bool?; let newStatus: String? }

// MARK: - Cached envelope

/// Everything that is allowed to survive a dead cell. The replacement
/// candidate set is DELIBERATELY absent from this struct.
private struct ES26Snapshot: Codable {
    var trip: ES26ActiveTrip? = nil
    var slots: ES26ConvoySlots? = nil
    var stateRules: ES26StateEscortRules? = nil
    var analysis: ES26OversizeAnalysis? = nil
    var check: ES26VehicleCheck? = nil
    var tickets: [ES26RoadsideTicket] = []
    var policy: ES26RoadsidePolicy? = nil
    var routeStates: [String] = []
}

// MARK: - The protection protocol (client constant, on purpose)

/// 49 CFR 392.22(b). This is a CONSTANT and not a read, because the one
/// thing on this screen that keeps the operator alive must not depend on
/// a bar of LTE. It is labelled as a constant on glass; nothing here is
/// dressed as server data. Owed server-side: a federal_warning_device_rules
/// row set, so two surfaces cannot disagree about the law.
private enum ES26Protocol {
    /// Divided / one-way highway placement, 392.22(b)(2)(v).
    static let dividedHighwayFeet: [Int] = [200, 100, 10]
    /// 392.22(b)(1) — devices out within ten minutes of stopping.
    static let federalDeadline: TimeInterval = 10 * 60
    /// House operating target, tighter than the federal ceiling.
    static let opsTarget: TimeInterval = 4 * 60
    static let citation = "49 CFR 392.22(b)(2)(v) · divided highway"

    struct Layer: Identifiable {
        let id: Int
        let code: String
        let title: String
        let detail: String
    }

    static let layers: [Layer] = [
        Layer(id: 1, code: "L1", title: "SIGNAL",
              detail: "hazards · amber beacon · Class 3 vest"),
        Layer(id: 2, code: "L2", title: "DEVICES",
              detail: "triangles at 200 · 100 · 10 ft upstream"),
        Layer(id: 3, code: "L3", title: "SHIELD",
              detail: "lead unit blocks the lane · state-DOT advisory"),
    ]
}

/// One row of the briefing payload with its provenance stamped on it.
private struct ES26BriefingItem: Identifiable {
    let label: String
    let value: String
    /// AUTO — carried off the assignment row · DOC — off the permit ·
    /// SPOKEN — exists only in a human mouth, no field holds it.
    let source: String
    var id: String { label }
}

// MARK: - Nav intents (this file never touches EscortNavController)

extension Notification.Name {
    static let esES26OpenVehicleCheck = Notification.Name("esES26OpenVehicleCheck")
    static let esES26OpenMarketplace  = Notification.Name("esES26OpenMarketplace")
}

// MARK: - Screen body

struct EscortEmergencyReplacementES26: View {

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var session: EusoTripSession

    private enum Phase { case loading, live, cached, failed, empty }
    private enum MarketPhase { case idle, loading, live, unavailable }
    private enum Commit: Equatable {
        case idle
        case inFlight
        case done(String)
        case failed(String)
    }

    @State private var phase: Phase = .loading
    @State private var marketPhase: MarketPhase = .idle
    @State private var snap = ES26Snapshot()
    @State private var candidates: [ES26Candidate] = []
    @State private var cacheAge: TimeInterval? = nil

    /// Layer ticks are DEVICE-LOCAL. No procedure records a placed
    /// warning device (STUB), so this is a memory aid for one operator
    /// on one phone and the card says exactly that.
    @State private var layersSet: Set<Int> = []

    @State private var repair: Commit = .idle
    @State private var advisory: Commit = .idle
    @State private var restart: Commit = .idle
    @State private var fixDenied = false

    private let cacheKey = "escort.es26.emergency"
    private let cacheTTL: TimeInterval = 15 * 60      // READ_CACHED(15m)

    private var isDark: Bool { scheme == .dark }
    private var dangerInk: Color { isDark ? Color(hex: 0xF87171) : Color(hex: 0xB91C1C) }
    private var amberInk: Color  { isDark ? Color(hex: 0xFBBF24) : Color(hex: 0xB45309) }
    private var greenInk: Color  { isDark ? Color(hex: 0x34D399) : Color(hex: 0x0B7A4B) }
    private var blueInk: Color   { isDark ? Color(hex: 0x60A5FA) : Color(hex: 0x1D4ED8) }
    private var purpleInk: Color { isDark ? Color(hex: 0xCE93D8) : Color(hex: 0x7B1FA2) }
    private let amber  = Color(hex: 0xF59E0B)
    private let danger = Color(hex: 0xEF4444)
    private let orange = Color(hex: 0xF97316)
    private let heroRim = LinearGradient(
        colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            eyebrowRow
            ledgerRow
            titleRow
            metaRow
            IridescentHairline()
            content
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s2)
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    // MARK: Header

    private var eyebrowRow: some View {
        HStack {
            Text("✦ ESCORT · EMERGENCY & REPLACEMENT")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: Space.s2)
            Text(snap.trip?.assignmentId.map { "ASSIGNMENT \($0)" } ?? "—")
                .font(EType.mono(.micro)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
    }

    private var ledgerRow: some View {
        Text(ledgerLine)
            .font(EType.mono(.caption))
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1).minimumScaleFactor(0.7)
    }

    private var ledgerLine: String {
        guard let load = snap.trip?.load else { return "no active move on this account" }
        let lane = [load.origin, load.destination].compactMap { $0 }.joined(separator: " → ")
        return [load.loadNumber, lane.isEmpty ? nil : lane].compactMap { $0 }.joined(separator: " · ")
    }

    private var titleRow: some View {
        Text(headlineClock)
            .font(.system(size: 28, weight: .bold)).tracking(-0.6)
            .foregroundStyle(LinearGradient.diagonal)
            .lineLimit(1).minimumScaleFactor(0.65)
    }

    /// The H1 is the next deadline, not a noun. When no stop stamp is
    /// known it says so rather than inventing a countdown.
    private var headlineClock: String {
        guard let started = parseISO(snap.trip?.startedAt) else { return "Protection protocol" }
        let elapsed = Date().timeIntervalSince(started)
        let left = ES26Protocol.opsTarget - elapsed
        if left <= 0 { return "Ops target passed" }
        return "\(mmss(left)) to Layer 2"
    }

    private var metaRow: some View {
        HStack(spacing: Space.s2) {
            positionBadge(snap.trip?.position ?? "—")
            Text("UNIT DOWN")
                .font(.system(size: 9.5, weight: .heavy)).tracking(0.5)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(danger))
            Circle()
                .fill(cacheAge == nil ? AnyShapeStyle(Brand.success) : AnyShapeStyle(amber))
                .frame(width: 7, height: 7)
            Text(freshnessLine)
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: Space.s1)
            Text(session.user?.name ?? "escort")
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
    }

    private var freshnessLine: String {
        if let age = cacheAge { return EscortOfflineCache.stalenessLine(age: age).uppercased() }
        return "LIVE"
    }

    private func positionBadge(_ raw: String) -> some View {
        let key = raw.lowercased()
        let tint: Color = key.contains("lead") ? Color(hex: 0x3B82F6)
            : key.contains("chase") || key.contains("rear") ? Color(hex: 0x9C27B0)
            : key.contains("steer") ? amber
            : key.contains("pole") ? orange
            : Brand.neutral
        let ink: Color = key.contains("lead") ? blueInk
            : key.contains("chase") || key.contains("rear") ? purpleInk
            : key.contains("steer") ? amberInk
            : key.contains("pole") ? orange
            : palette.textSecondary
        return Text(raw.uppercased())
            .font(.system(size: 10, weight: .heavy)).tracking(0.5)
            .foregroundStyle(ink)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(isDark ? 0.24 : 0.16)))
    }

    // MARK: Content switch

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            VStack(alignment: .leading, spacing: Space.s3) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16)
                        .fill(palette.bgCard)
                        .frame(height: 96)
                }
            }
        case .empty:
            emptyState(
                title: "No active move",
                body: "This flow only opens on a move that is already under way. Nothing is active right now — that is a real answer, not a failure.")
        case .failed:
            VStack(alignment: .leading, spacing: Space.s3) {
                emptyState(
                    title: "This move didn't load",
                    body: "Nothing came back live, and there is no saved copy from the last 15 minutes, so nothing is drawn. The protection protocol below does not need a connection.")
                protocolCard
                CTAButton(title: "Try again", action: { Task { await refresh() } })
            }
        case .live, .cached:
            VStack(alignment: .leading, spacing: Space.s5) {
                protocolCard
                convoyCard
                replacementCard
                briefingCard
                restartGateCard
            }
        }
    }

    private func emptyState(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(EType.title).foregroundStyle(palette.textPrimary)
            Text(body).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard))
    }

    // MARK: 1 · Protection protocol (the hero — cached by design)

    private var protocolCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionLabel("PROTECTION PROTOCOL · 3 LAYERS")
                Spacer()
                Text(federalClockLine)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(dangerInk)
            }
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("LAYER \(activeLayer) · \(ES26Protocol.layers[activeLayer - 1].title) · \(layersSet.count) OF 3 SET")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: Space.s2)
                    tag("CACHED · NO SIGNAL OK", tint: Brand.success, ink: greenInk)
                }

                roadwayPlanView

                VStack(spacing: 6) { ForEach(ES26Protocol.layers) { layerRow($0) } }

                Divider().overlay(palette.borderFaint)

                HStack(spacing: Space.s2) {
                    Button {
                        toggleLayer(activeLayer)
                    } label: {
                        Text("MARK LAYER \(activeLayer) SET")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.textSecondary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                                .foregroundStyle(palette.borderSoft))
                    }
                    .buttonStyle(.plain)
                    Text("device-local · nothing off this phone records a placed device")
                        .font(.system(size: 9))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(2)
                }
            }
            .padding(Space.s4)
            .background(
                RoundedRectangle(cornerRadius: 18).fill(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(heroRim, lineWidth: 1.5)))
        }
    }

    /// Plan view of the shoulder with the three device positions placed
    /// at their real upstream distances. The geometry is the point: the
    /// operator is being told WHERE to walk, not shown a status chip.
    private var roadwayPlanView: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let scale = w / 320.0                     // 0..300 ft plus the unit
            let x: (Int) -> CGFloat = { ft in w - 24 - CGFloat(ft) * scale }

            ZStack(alignment: .topLeading) {
                // travel lanes
                Rectangle().fill(palette.bgSecondary)
                    .frame(height: 32)
                    .offset(y: 14)
                // lane divider
                Rectangle().fill(palette.textTertiary.opacity(0.45))
                    .frame(height: 1.5)
                    .offset(y: 30)
                // edge line
                Rectangle().fill(palette.textTertiary.opacity(0.8))
                    .frame(height: 2)
                    .offset(y: 46)
                // shoulder
                Rectangle().fill(palette.bgCardSoft)
                    .frame(height: 16)
                    .offset(y: 48)

                // approach arrow
                Text("TRAFFIC →")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)

                // device markers
                ForEach(ES26Protocol.dividedHighwayFeet, id: \.self) { ft in
                    deviceMarker(feet: ft, set: layersSet.contains(2))
                        .position(x: x(ft), y: 54)
                }

                // the disabled unit
                RoundedRectangle(cornerRadius: 3)
                    .fill(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(danger, lineWidth: 1.6))
                    .frame(width: 34, height: 14)
                    .position(x: w - 22, y: 55)
            }
            .frame(height: 92)
        }
        .frame(height: 92)
    }

    private func deviceMarker(feet: Int, set: Bool) -> some View {
        VStack(spacing: 2) {
            Triangle()
                .fill(set ? AnyShapeStyle(orange) : AnyShapeStyle(Color.clear))
                .overlay {
                    if !set {
                        Triangle()
                            .stroke(style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                .frame(width: 10, height: 10)
            Text("\(feet) FT")
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
            Text(set ? "SET" : "NOT SET")
                .font(.system(size: 7, weight: .heavy))
                .foregroundStyle(set ? greenInk : dangerInk)
        }
    }

    private func layerRow(_ layer: ES26Protocol.Layer) -> some View {
        let done = layersSet.contains(layer.id)
        let active = layer.id == activeLayer
        return HStack(spacing: Space.s2) {
            Circle()
                .fill(done ? AnyShapeStyle(Brand.success) : AnyShapeStyle(Color.clear))
                .overlay {
                    if !done {
                        Circle().strokeBorder(active ? amber : palette.borderStrong, lineWidth: 1.6)
                    }
                }
                .frame(width: 11, height: 11)
            Text("\(layer.code) · \(layer.title) — \(layer.detail)")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: Space.s1)
            if layer.id == 3 {
                tag(advisorySent ? "ADVISORY LOGGED" : "ADVISORY —",
                    tint: advisorySent ? Brand.success : danger,
                    ink: advisorySent ? greenInk : dangerInk)
            } else {
                Text(done ? "SET" : "OPEN")
                    .font(EType.mono(.micro))
                    .foregroundStyle(done ? greenInk : amberInk)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(done ? Brand.success.opacity(0.10)
                  : active ? amber.opacity(isDark ? 0.18 : 0.12)
                  : palette.bgCardSoft))
        .overlay {
            if active && !done {
                RoundedRectangle(cornerRadius: 8).strokeBorder(amber, lineWidth: 1.2)
            }
        }
    }

    private var activeLayer: Int {
        for l in ES26Protocol.layers where !layersSet.contains(l.id) { return l.id }
        return 3
    }

    private var federalClockLine: String {
        guard let started = parseISO(snap.trip?.startedAt) else { return "49 CFR 392.22(b)" }
        let left = ES26Protocol.federalDeadline - Date().timeIntervalSince(started)
        return left > 0 ? "49 CFR 392.22(b) · \(mmss(left)) LEFT" : "49 CFR 392.22(b) · PASSED"
    }

    private func toggleLayer(_ id: Int) {
        if layersSet.contains(id) { layersSet.remove(id) } else { layersSet.insert(id) }
    }

    // MARK: 2 · Convoy state — short one unit

    private var convoyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionLabel("CONVOY STATE · SHORT ONE UNIT")
                Spacer()
                Text(vacantSlotLabel.map { "\($0) VACANT" } ?? "ALL SLOTS FILLED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(vacantSlotLabel == nil ? greenInk : dangerInk)
            }
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: 6) {
                    slotBlock("LEAD", snap.slots?.lead?.name, filled: snap.slots?.lead?.userId != nil, tint: Color(hex: 0x3B82F6), ink: blueInk)
                    slotBlock("LOAD", snap.slots?.loadVehicle?.name, filled: snap.slots?.loadVehicle?.userId != nil, tint: Brand.neutral, ink: palette.textSecondary)
                    slotBlock("CHASE", snap.slots?.rear?.name, filled: snap.slots?.rear?.userId != nil, tint: danger, ink: dangerInk)
                }
                legalityBar
            }
            .padding(Space.s4)
            .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint, lineWidth: 1)))
        }
    }

    private func slotBlock(_ role: String, _ name: String?, filled: Bool, tint: Color, ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(role)
                .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                .foregroundStyle(filled ? ink : dangerInk)
            Text(filled ? (name ?? "assigned") : "VACANT")
                .font(.system(size: 9, weight: filled ? .semibold : .heavy))
                .foregroundStyle(filled ? palette.textPrimary : dangerInk)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(filled ? tint.opacity(isDark ? 0.16 : 0.10) : Color.clear)
                .overlay {
                    if !filled {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .foregroundStyle(danger)
                    }
                })
    }

    /// The verdict, with its own basis printed underneath. When the
    /// server could not supply an escort count, this says so instead of
    /// asserting a legality it did not compute.
    private var legalityBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(legalityHeadline)
                    .font(.system(size: 9.5, weight: .heavy))
                    .foregroundStyle(legalityIsBlocking ? dangerInk : palette.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.75)
                Spacer(minLength: Space.s2)
                Text(legalityIsBlocking ? "NOT LEGAL" : "—")
                    .font(.system(size: 9.5, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(legalityIsBlocking ? dangerInk : palette.textTertiary)
            }
            Text(legalityBasis)
                .font(.system(size: 8.5))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(3)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(legalityIsBlocking ? danger.opacity(isDark ? 0.18 : 0.12) : palette.bgCardSoft))
    }

    private var slotsFilled: Int {
        [snap.slots?.lead?.userId, snap.slots?.rear?.userId].compactMap { $0 }.count
    }
    private var vacantSlotLabel: String? {
        guard snap.slots != nil else { return nil }
        if snap.slots?.rear?.userId == nil { return "CHASE" }
        if snap.slots?.lead?.userId == nil { return "LEAD" }
        return nil
    }
    private var requiredEscorts: Int? { snap.analysis?.escortCount }
    private var legalityIsBlocking: Bool {
        guard let need = requiredEscorts else { return false }
        return slotsFilled < need
    }
    private var legalityHeadline: String {
        guard let need = requiredEscorts else {
            return "Escort count not computed — no load dimensions were available to judge on"
        }
        return "\(need) escort\(need == 1 ? "" : "s") required · \(slotsFilled) on scene"
    }
    private var legalityBasis: String {
        var parts: [String] = []
        if let t = snap.stateRules?.rules?.escortThresholds {
            if let dual = t.dualEscortWidth {
                parts.append("dual-escort width line \(fmt(dual)) ft")
            }
            if let wt = t.escortWeight {
                parts.append("escort weight line \(Int(wt).formatted()) lb")
            }
        }
        if let wt = snap.trip?.load?.weight, wt > 0 {
            parts.append("load \(Int(wt).formatted()) lb")
        }
        parts.append("width/height/length are not columns on loads, so this verdict stands on weight and route states only")
        return parts.joined(separator: " · ")
    }

    // MARK: 3 · Replacement — the provenance split

    private var replacementCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionLabel("RECOVERY · REPLACEMENT SEARCH")
                Spacer()
                Text("POLL")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(amberInk)
            }
            .padding(.bottom, 8)

            HStack(alignment: .top, spacing: Space.s3) {
                // LEFT · what the server actually answers
                VStack(alignment: .leading, spacing: 6) {
                    Text("ON THE WIRE")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.7)
                        .foregroundStyle(greenInk)
                    switch marketPhase {
                    case .idle, .loading:
                        Text("checking…").font(EType.caption).foregroundStyle(palette.textSecondary)
                    case .unavailable:
                        Text("NO SIGNAL — candidates are never cached")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(dangerInk)
                            .lineLimit(2)
                    case .live:
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(candidates.count)")
                                .font(EType.mono(.body)).fontWeight(.heavy)
                                .foregroundStyle(palette.textPrimary)
                            Text("qualified · \(snap.routeStates.joined(separator: " + "))")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        if let top = candidates.first {
                            Text(top.name ?? "escort \(top.userId ?? 0)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(1)
                            tag("CERTS VERIFIED", tint: Brand.success, ink: greenInk)
                        } else {
                            Text("no operator holds every route state")
                                .font(.system(size: 9))
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle().fill(palette.borderFaint).frame(width: 1, height: 74)

                // RIGHT · what only a radio can supply
                VStack(alignment: .leading, spacing: 6) {
                    Text("NOT ON THE WIRE ✱")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.7)
                        .foregroundStyle(palette.textTertiary)
                    ghostRow("RADIUS")
                    ghostRow("DEADHEAD")
                    ghostRow("ETA ON SCENE")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Space.s4)
            .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint, lineWidth: 1)))

            Text("✱ certifications are all that comes back — no location, no ETA, no record of who answered. Anything you know beyond this came over the radio, and this screen will not print it as if it were confirmed here.")
                .font(.system(size: 9))
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 6)
        }
    }

    private func ghostRow(_ label: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: Space.s1)
            Text("—")
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
                .overlay(Rectangle().fill(palette.textTertiary.opacity(0.5))
                    .frame(height: 1).offset(y: 7))
        }
    }

    // MARK: 4 · Briefing transfer payload

    private var briefingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionLabel("BRIEFING TRANSFER")
                Spacer()
                Text("0 OF \(briefingItems.count) ACKNOWLEDGED ✱")
                    .font(EType.mono(.micro))
                    .foregroundStyle(dangerInk)
            }
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(briefingItems) { item in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(item.source == "AUTO" ? Brand.blue
                                  : item.source == "DOC" ? Brand.escort : amber)
                            .frame(width: 3, height: 14)
                        Text(item.label)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)
                            .frame(width: 96, alignment: .leading)
                        Text(item.value)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: Space.s1)
                        Text(item.source)
                            .font(.system(size: 7.5, weight: .heavy)).tracking(0.3)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                Text("✱ nothing anywhere records a briefing handover, so nothing here can be ticked off. SPOKEN items exist only in a human mouth.")
                    .font(.system(size: 9))
                    .foregroundStyle(palette.textTertiary)
                    .padding(.top, 2)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint, lineWidth: 1)))
        }
    }

    /// Every AUTO value is read off a procedure above; nothing here is a
    /// literal. SPOKEN rows carry no value on purpose — there is no field
    /// on the wire that holds them, so an em-dash is the honest answer.
    private var briefingItems: [ES26BriefingItem] {
        var out: [ES26BriefingItem] = []
        out.append(.init(label: "LOAD", value: snap.trip?.load?.loadNumber ?? "—", source: "AUTO"))
        out.append(.init(label: "POSITION", value: (snap.trip?.position ?? "—").uppercased(), source: "AUTO"))
        if let m = snap.slots?.targetRearDistance {
            out.append(.init(label: "SEPARATION", value: "\(Int(Double(m) * 3.28084)) ft target", source: "AUTO"))
        } else {
            out.append(.init(label: "SEPARATION", value: "—", source: "AUTO"))
        }
        out.append(.init(label: "ENVELOPE", value: envelopeLine, source: "DOC"))
        out.append(.init(label: "RADIO", value: "—", source: "SPOKEN"))
        out.append(.init(label: "CORRIDOR HAZARDS", value: "—", source: "SPOKEN"))
        return out
    }

    private var envelopeLine: String {
        guard let wt = snap.trip?.load?.weight, wt > 0 else { return "— (no dimensions on file)" }
        return "\(Int(wt).formatted()) lb · dimensions off the permit"
    }

    // MARK: 5 · Restart gate

    private var restartGateCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionLabel("RESTART GATE")
                Spacer()
                Text(gateOpen ? "GATE OPEN · 4 OF 4" : "GATE CLOSED · \(gateMet) OF 4")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(gateOpen ? greenInk : dangerInk)
            }
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: 6) {
                    gateCell("REPLACEMENT", replacementOnScene ? "SEAT FILLED" : "SEAT OPEN", met: replacementOnScene, enforced: false)
                    gateCell("UNIT CLEARED", repairLine, met: repairTicketOpen, enforced: false)
                    gateCell("DOT ADVISORY", advisorySent ? "LOGGED" : "NOT SENT", met: advisorySent, enforced: false)
                    gateCell("RESTART CHECK", inspectionPassed ? "PASSED" : "REQUIRED", met: inspectionPassed, enforced: true)
                }

                // The three ONLINE_ONLY commits, each with its own reason.
                VStack(alignment: .leading, spacing: 6) {
                    commitRow(title: "Open roadside ticket",
                              state: repair,
                              disabled: repairTicketOpen,
                              disabledReason: repairTicketOpen ? "a ticket is already open on this account" : nil,
                              action: { Task { await commitRepairTicket() } })
                    commitRow(title: "Log state-DOT advisory",
                              state: advisory,
                              disabled: advisorySent,
                              disabledReason: advisorySent ? "already logged this session" : nil,
                              action: { Task { await commitAdvisory() } })
                    commitRow(title: "Request restart → en route",
                              state: restart,
                              disabled: false,
                              disabledReason: nil,
                              action: { Task { await commitRestart() } })
                }

                Text("Every action above needs a live connection — escort actions are not held offline yet. Nothing is queued and no badge is drawn: if one fails here, it failed. The restart is refused outright until a passed inspection exists for this assignment inside 24 hours — that rule is enforced on the record, not by this screen.")
                    .font(.system(size: 9))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint, lineWidth: 1)))
        }
    }

    private func gateCell(_ title: String, _ sub: String, met: Bool, enforced: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(met ? AnyShapeStyle(Brand.success) : AnyShapeStyle(Color.clear))
                    .overlay {
                        if !met {
                            Circle().strokeBorder(enforced ? danger : palette.borderStrong, lineWidth: 1.4)
                        }
                    }
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 7.5, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(enforced && !met ? dangerInk : palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(sub)
                .font(.system(size: 7))
                .foregroundStyle(met ? greenInk : palette.textTertiary)
                .lineLimit(2).minimumScaleFactor(0.7)
            if enforced {
                Text("NOT WAIVABLE")
                    .font(.system(size: 6.5, weight: .heavy))
                    .foregroundStyle(dangerInk)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(enforced && !met ? danger.opacity(isDark ? 0.16 : 0.10) : palette.bgCardSoft))
    }

    private func commitRow(title: String, state: Commit, disabled: Bool,
                           disabledReason: String?, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Button(action: action) {
                HStack {
                    Text(title)
                        .font(.system(size: 10, weight: .heavy)).tracking(0.3)
                    Spacer()
                    if case .inFlight = state { ProgressView().scaleEffect(0.6) }
                }
                .foregroundStyle(disabled ? palette.textTertiary : palette.textPrimary)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(palette.bgCardSoft))
            }
            .buttonStyle(.plain)
            .disabled(disabled || state == .inFlight)

            switch state {
            case .failed(let why):
                Text(why).font(.system(size: 9)).foregroundStyle(dangerInk).lineLimit(3)
            case .done(let what):
                Text(what).font(.system(size: 9)).foregroundStyle(greenInk).lineLimit(2)
            default:
                if let why = disabledReason {
                    Text(why).font(.system(size: 9)).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private var repairTicketOpen: Bool {
        snap.tickets.contains { ($0.status ?? "").lowercased() != "closed" }
    }
    private var repairLine: String {
        if let name = snap.policy?.preferredProvider?.name {
            if let sla = snap.policy?.preferredProvider?.slaMinutes {
                return "\(name) · SLA \(sla) min"
            }
            return name
        }
        return repairTicketOpen ? "ticket open" : "no ticket"
    }
    private var advisorySent: Bool { if case .done = advisory { return true }; return false }
    private var inspectionPassed: Bool { snap.check?.latest?.passed == true }
    private var replacementOnScene: Bool { snap.slots?.rear?.userId != nil && snap.slots?.lead?.userId != nil }
    private var gateMet: Int {
        [replacementOnScene, repairTicketOpen, advisorySent, inspectionPassed].filter { $0 }.count
    }
    private var gateOpen: Bool { gateMet == 4 }

    // MARK: Small chrome

    private func sectionLabel(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
            .foregroundStyle(palette.textTertiary)
    }

    private func tag(_ s: String, tint: Color, ink: Color) -> some View {
        Text(s)
            .font(.system(size: 7.5, weight: .heavy)).tracking(0.3)
            .foregroundStyle(ink)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(isDark ? 0.20 : 0.14)))
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    private func mmss(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func parseISO(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
    }

    /// "Denver, CO" → "CO". Returns nil rather than a guess.
    private func stateCode(_ s: String?) -> String? {
        guard let s else { return nil }
        let tail = s.split(separator: ",").last?.trimmingCharacters(in: .whitespaces) ?? ""
        let up = tail.uppercased()
        return up.count == 2 && up.allSatisfy(\.isLetter) ? up : nil
    }

    // MARK: - Data plumbing

    private func softQuery<T: Decodable, I: Encodable>(_ path: String, _ input: I) async -> T? {
        do { let v: T = try await EusoTripAPI.shared.query(path, input: input); return v }
        catch { return nil }
    }

    /// READ_CACHED(15m) for the survivable half; the candidate set is
    /// fetched separately and never written to the cache.
    private func refresh() async {
        if snap.trip == nil { phase = .loading }
        do {
            let trip: ES26ActiveTrip? = try await EusoTripAPI.shared.queryNoInput("escorts.getActiveTrip")
            guard let trip, let loadId = trip.load?.id else {
                await MainActor.run { phase = .empty }
                return
            }

            var next = ES26Snapshot()
            next.trip = trip

            // The three structural slots — the vacancy is a server null.
            next.slots = await softQuery("convoy.getConvoy", ES26LoadIdInput(loadId: loadId))

            // Route states, then the legality pair.
            let originState = stateCode(trip.load?.origin)
            let destState   = stateCode(trip.load?.destination)
            if let o = originState, let d = destState {
                let rs: ES26RouteStates? = await softQuery(
                    "escorts.getRouteStates", ES26RouteStatesInput(originState: o, destinationState: d))
                next.routeStates = rs?.resolved ?? Array(Set([o, d])).sorted()
            } else if let o = originState ?? destState {
                next.routeStates = [o]
            }

            if let here = originState ?? destState {
                next.stateRules = await softQuery("escorts.getStateEscortRules", ES26StateInput(state: here))
            }
            if !next.routeStates.isEmpty {
                next.analysis = await softQuery(
                    "escorts.analyzeOversize",
                    ES26AnalyzeInput(weightLbs: trip.load?.weight, routeStates: next.routeStates))
            }

            if let aid = trip.assignmentId {
                next.check = await softQuery("escorts.getVehicleCheck", ES26AssignmentIdInput(assignmentId: aid))
            }

            let list: ES26RoadsideList? = await softQuery(
                "roadsideTickets.list", ES26TicketListInput(status: "open", limit: 20, offset: 0))
            next.tickets = list?.items ?? []

            if let cid = session.user?.companyId, let carrierId = Int(cid) {
                next.policy = await softQuery("roadsideTickets.policyForCarrier", ES26CarrierIdInput(carrierId: carrierId))
            }

            await MainActor.run {
                snap = next
                cacheAge = nil
                phase = .live
            }
            EscortOfflineCache.store(next, key: cacheKey)
            await refreshMarket()
        } catch {
            if let hit = EscortOfflineCache.load(ES26Snapshot.self, key: cacheKey, ttl: cacheTTL) {
                await MainActor.run {
                    snap = hit.value
                    cacheAge = hit.age
                    phase = .cached
                    // The candidate band is never painted from a snapshot.
                    candidates = []
                    marketPhase = .unavailable
                }
            } else {
                await MainActor.run { cacheAge = nil; phase = .failed }
            }
        }
    }

    /// NEEDS SIGNAL. A stale candidate is worse than none, so this read
    /// never touches the cache and fails loudly.
    private func refreshMarket() async {
        guard !snap.routeStates.isEmpty else {
            await MainActor.run { marketPhase = .unavailable }
            return
        }
        await MainActor.run { marketPhase = .loading }
        let position = (snap.trip?.position ?? "").lowercased().contains("lead") ? "lead" : "chase"
        do {
            let res: ES26QualifiedEscorts = try await EusoTripAPI.shared.query(
                "escorts.findQualifiedEscorts",
                input: ES26QualifiedInput(routeStates: snap.routeStates, position: position))
            await MainActor.run {
                candidates = res.escorts ?? []
                marketPhase = .live
            }
        } catch {
            await MainActor.run { candidates = []; marketPhase = .unavailable }
        }
    }

    // MARK: Mutations — ONLINE_ONLY, every one of them

    /// roadsideTickets.create · roadsideTickets.ts:110. A roadside ticket
    /// without a location is worse than no ticket, so no fix means no
    /// commit — and the reason is said out loud.
    /// `DriverLocationResolver` is `@MainActor`-isolated, so the hop is
    /// made explicit here rather than implied at the call site.
    @MainActor private func currentFix() async -> CLLocationCoordinate2D? {
        await DriverLocationResolver.shared.currentCoordinate()
    }

    private func commitRepairTicket() async {
        await MainActor.run { repair = .inFlight }
        guard let coord = await currentFix() else {
            await MainActor.run {
                fixDenied = true
                repair = .failed("No GPS fix. A roadside ticket without a position is worse than none, so nothing was sent.")
            }
            return
        }
        let where_ = snap.trip?.load?.loadNumber.map { "escort unit down · load \($0)" }
        do {
            let res: ES26TicketCreateResult = try await EusoTripAPI.shared.mutation(
                "roadsideTickets.create",
                input: ES26TicketCreateInput(category: "tire",
                                             location: ES26LatLng(lat: coord.latitude, lng: coord.longitude),
                                             description: where_))
            guard res.success == true, let id = res.ticketId else {
                await MainActor.run { repair = .failed("The ticket was not confirmed. Nothing was recorded.") }
                return
            }
            await MainActor.run { repair = .done("Ticket #\(id) open.") }
            await refresh()
        } catch {
            await MainActor.run {
                repair = .failed("Did not go through — check signal and try again. Nothing is queued.")
            }
        }
    }

    /// escorts.recordDOTNotification · escorts.ts:3407. This LOGS the
    /// advisory; it does not contact a DOT. The success copy says so.
    private func commitAdvisory() async {
        guard let loadId = snap.trip?.load?.id,
              let state = stateCode(snap.trip?.load?.destination) ?? stateCode(snap.trip?.load?.origin) else {
            await MainActor.run { advisory = .failed("No load or state on the assignment — nothing to log against.") }
            return
        }
        await MainActor.run { advisory = .inFlight }
        do {
            let res: ES26DOTResult = try await EusoTripAPI.shared.mutation(
                "escorts.recordDOTNotification",
                input: ES26DOTInput(loadId: loadId, state: state,
                                    notificationType: "state_dot",
                                    notifiedAt: ISO8601DateFormatter().string(from: Date()),
                                    notes: "escort unit down · convoy short one · lane obstruction"))
            guard res.success == true else {
                await MainActor.run { advisory = .failed("No confirmation came back. Treat the state as NOT told.") }
                return
            }
            await MainActor.run {
                advisory = .done("Logged locally to the alert ledger. No DOT system was contacted — call it in by voice as well.")
            }
        } catch {
            await MainActor.run {
                advisory = .failed("Did not go through. The state has NOT been told. Nothing is queued.")
            }
        }
    }

    /// escorts.updateJobStatus · escorts.ts:1171. The gate lives at
    /// escorts.ts:1185-1196 and we let it speak for itself.
    private func commitRestart() async {
        guard let aid = snap.trip?.assignmentId else {
            await MainActor.run { restart = .failed("No assignment id on this surface.") }
            return
        }
        await MainActor.run { restart = .inFlight }
        do {
            let res: ES26JobStatusResult = try await EusoTripAPI.shared.mutation(
                "escorts.updateJobStatus",
                input: ES26JobStatusInput(jobId: String(aid), status: "en_route"))
            guard res.success == true else {
                await MainActor.run { restart = .failed("The restart was not confirmed. The move has not resumed.") }
                return
            }
            await MainActor.run { restart = .done("Assignment is en route.") }
            await refresh()
        } catch {
            // PRECONDITION_FAILED from escorts.ts:1196 lands here. We do
            // not paraphrase the rule — we name it and point at ES-06.
            await MainActor.run {
                restart = .failed("The restart was refused. A passed pre-trip vehicle check inside the last 24 hours is required for this assignment before it will go en route — open the vehicle check and sign it.")
            }
            NotificationCenter.default.post(name: .esES26OpenVehicleCheck, object: nil,
                                            userInfo: ["assignmentId": aid])
        }
    }
}

// MARK: - Triangle (the warning device glyph)

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Screen wrapper

struct EscortEmergencyReplacementES26Screen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortEmergencyReplacementES26()
        } nav: {
            BottomNav(
                leading: es26NavLeading(),
                trailing: es26NavTrailing(),
                orbState: .idle
            )
        }
    }
}

private func es26NavLeading() -> [NavSlot] {
    [NavSlot(label: "Home",        systemImage: "house",                  isCurrent: false),
     NavSlot(label: "Assignments", systemImage: "shield.lefthalf.filled", isCurrent: true)]
}

private func es26NavTrailing() -> [NavSlot] {
    [NavSlot(label: "Corridor", systemImage: "map",    isCurrent: false),
     NavSlot(label: "Me",       systemImage: "person", isCurrent: false)]
}

// MARK: - Previews
//
// `.task` does not run in the preview canvas, so both variants render in
// their loading register without touching the network.

#Preview("ES-26 · Emergency & Replacement · Dark") {
    EscortEmergencyReplacementES26Screen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("ES-26 · Emergency & Replacement · Light") {
    EscortEmergencyReplacementES26Screen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
