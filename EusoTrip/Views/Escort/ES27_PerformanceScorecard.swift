//
//  ES27_PerformanceScorecard.swift
//  EusoTrip — Escort · Performance Scorecard (ES-27).
//
//  NEW SURFACE. Nothing on disk owns the escort's own performance record
//  today, so this file shadows no brick and edits none. It needs a nav
//  entry it does NOT write: `EscortNavController.swift` is single-writer
//  owned, and the route this screen wants ("scorecard" →
//  `EscortPerformanceScorecardES27Screen`) is filed in the manifest for
//  that writer. Until it lands, the screen is reachable only by direct
//  push from ES-12 Me Profile.
//
//  Built from the ES-27 design-authority SVG pair
//  ("07 Escort/{Light,Dark}-SVG/ES-27 Performance Scorecard.svg").
//
//  ─────────────────────────────────────────────────────────────────────
//  ARCHETYPE — DETAIL · CONTRIBUTION WATERFALL. The composite is built in
//  front of the escort as a left-to-right staircase of SIGNED
//  contributions: baseline 0 at the left, one slot per metric, terminal
//  at the right, so what is read is WHAT MOVED THE NUMBER rather than the
//  number alone. Five slots carry a solid tread because five metrics have
//  a real producer. Five carry no tread at all — only a dashed outline of
//  the weight that would have stood there, over a hatched wedge that
//  widens the running total into an INTERVAL. The terminal is 31–76 of
//  100 and never a point score.
//
//  THE DEFECT THIS FILE EXISTS TO AVOID, stated once, in code terms: a
//  non-optional `Int` that defaults to 0 when a field is missing. Every
//  wire field below is optional, every contribution is an enum with no
//  `.zero` member, and the fold refuses to sum an unmeasured slot. `0` is
//  a value; absence is not.
//
//  Anti-clone: NOT ES-13's ranked leaderboard with ordinal rail, metric
//  bars and radar-ring (there is no escort leaderboard to rank against at
//  all); NOT ES-12's three-rung cert staircase (a staircase is monotonic
//  progress through states and only rises — a waterfall is signed
//  contributions summing to a total, and two of these five treads
//  descend); NOT ES-19's payout ribbon (that cuts ONE KNOWN whole into
//  shares — this whole is not known, so it can only be bounded).
//
//  ─────────────────────────────────────────────────────────────────────
//  WIRING — every anchor opened at the pin against the live working tree
//  this fire (frontend/server/routers/escorts.ts, 4,745 lines).
//
//    EXISTS escorts.getProfile              escorts.ts:3081
//           · stats.onTimePercentage        escorts.ts:3155 — real SQL
//             over escortAssignments.completedAt vs loads.deliveryDate
//             with an innerJoin on loads (escorts.ts:3117-3122)
//           · stats.totalConvoys            escorts.ts:3153 — count of
//             escortAssignments, status 'completed' (escorts.ts:3101-3104)
//           · self-scoped: a caller-supplied escortId is pinned to self
//             unless ADMIN/SUPER_ADMIN (escorts.ts:3089-3091)
//    EXISTS escorts.getVehicleCheckHistory  escorts.ts:1344
//           over escortVehicleInspections (drizzle/schema.ts:1821);
//           own-rows scope IS the escortUserId equality (escorts.ts:1354-1356)
//    EXISTS escorts.getIncidentStats        escorts.ts:2719
//           counted off incidents where driverId = the escort's own
//           userId (escorts.ts:2726-2733)
//    EXISTS escorts.getClearanceEventHistory escorts.ts:4559
//           over clearanceEvents (drizzle/schema.ts:3862): eventType
//           strike|near_miss|clearance_check, damageObserved, haulStopped,
//           escalation none|logged|reported|incident
//
//    STUB   FIVE-CATEGORY RATING — getProfile returns a rating block at
//           escorts.ts:3163-3171 read out of users.metadata.escortProfile
//           .rating. `grep -rn "escortProfile" server/ client/src/ shared/
//           drizzle/` → 24 hits, exactly SEVEN touch .rating
//           (escorts.ts:3164-3170) and all seven are READS ending `|| 0`.
//           The only writer of that JSON is escorts.updateProfile
//           (escorts.ts:3192): its input schema (escorts.ts:3193-3207) has
//           no rating key and its merge block (escorts.ts:3219-3228) never
//           assigns one. `ratings.entityTypeSchema` (ratings.ts:16) is
//           z.enum(["driver","catalyst","shipper","broker","facility"]) —
//           "escort" is ABSENT. The block is permanently 0 and
//           structurally unreachable, so this file NEVER decodes it.
//           Owed: "escort" on ratings.ts:16 + escorts.submitEscortRating +
//           an aggregate reader inside getProfile.
//    STUB   XP / BADGES — `grep -rn "ESCORT" server/routers/gamification.ts
//           server/routers/achievements.ts
//           server/routers/advancedGamification.ts
//           server/routers/leaderboard.ts` → 0 hits in all four.
//    STUB   SCORE HISTORY — `grep -rn "scoreHistory\|score_history"
//           server/ drizzle/ shared/ --include=*.ts` → 0. No time-series
//           table, so no trend line is drawn and no sparkline is faked.
//    STUB   COACHING PLAN — `grep -rn "coachingPlan\|coaching_moment" …` → 0.
//    STUB   INSURANCE IMPACT — `grep -rn "insuranceImpact\|premiumImpact"
//           …` → 0. certificatesOfInsurance exists (drizzle/schema.ts:4905)
//           and /insurance is escort-routed (App.tsx:722 includes
//           "ESCORT"), but nothing links a record to a premium.
//    STUB   THE COMPOSITE ITSELF — `grep -rn "escortScore\|escort_score\|
//           escortRating\|escort_rating\|escortPerformance" server/
//           drizzle/ shared/ --include=*.ts` → 0 on all five patterns. No
//           server composite, no weight table, no stored score. The
//           weights in `ES27Weights` are therefore a CLIENT-SIDE MODEL and
//           the screen says so on its face twice. Owed:
//           escorts.getScorecard({escortUserId?}) → {slots:[{key, weight,
//           earned, source}], banked, ceiling, computedAt} with `earned`
//           NULLABLE — nullable precisely so no client can mistake an
//           absent metric for a zero one.
//
//    REFUSED — four hard-coded zeros that are PRESENT in the getProfile
//           payload and would render as data if bound. None is decoded
//           below, and the footnote names all four:
//             stats.incidentCount   literal 0                escorts.ts:3156
//             stats.repeatClientRate literal 0               escorts.ts:3157
//             stats.totalMiles      escortProfile.totalMiles || 0, no
//                                   writer in the merge block            :3154
//             wallet.balance        literal 0                escorts.ts:3175
//           The incidentCount collision is why SLOT 7 reads
//           getIncidentStats (:2719, a query) instead of :3156 (a constant).
//
//    NOT REUSED — safety.getDriverScoreDetail server/routers/safety.ts:905.
//           CITATION DRIFT CORRECTED: EusoTrip/Views/Driver/
//           075_MeSafetyScore.swift:16 cited safety.ts:820 (the procedure
//           is named one line above at :14); the live line is 905, and
//           that comment was corrected this fire rather than propagated. It resolves its subject with drivers.userId = signed-in
//           user AND drivers.companyId = caller companyId (safety.ts:
//           915-918) and returns the zeroed fallback declared at
//           safety.ts:907 when no row matches. An escort is a users row
//           with role 'ESCORT'; registration.registerEscort
//           (registration.ts:1338, role at :1388) creates no drivers row
//           and an independent escort carries companyId 0 — so for an
//           escort the call does not error, it SUCCEEDS AND RETURNS ZEROS.
//           A scorecard rendered off it would show a working escort a face
//           of zeros indistinguishable from a genuinely bad escort's face.
//           That is the single outcome this screen exists to prevent.
//
//  ─────────────────────────────────────────────────────────────────────
//  PERSIST · AUDIT · REALTIME — this surface performs NO WRITE. No row is
//  persisted, so no `blockchainAuditTrail` row is inserted; the token
//  appears 0 times in escorts.ts, hazmatEscort.ts and safety.ts, and the
//  escort tree's audit surface is recordAuditEvent() (_core/auditService,
//  imported escorts.ts:17, called at :110 et al), which none of these five
//  reads calls. WS fan-out NONE: shared/websocket-events.ts carries
//  SAFETY_SCORE_UPDATED :187 and CSA_SCORE_UPDATED :193, both driver /
//  carrier events with no escort producer. Filed ESC-GAP-27-SCORE-EVENT.
//
//  RBAC — every read is escortProcedure aliased protectedProcedure
//  (escorts.ts:11) = roleProcedure(ROLES.ESCORT) (_core/trpc.ts:228) over
//  ROLES.ESCORT (_core/trpc.ts:23); row scope resolveEscortUserId
//  (escorts.ts:138). getStructureClearanceHistory (escorts.ts:4571,
//  roleProcedure ESCORT|CATALYST|DISPATCH) is deliberately NOT bound: it
//  is anonymised corridor memory, not this escort's record.
//
//  OFFLINE (§W) — READ_CACHED(600s) via `EscortOfflineCache`
//  (key escort.es27.scorecard). Safe at this ttl because every figure is a
//  historical aggregate with no clock inside it; a cached paint swaps the
//  meta register for `EscortOfflineCache.stalenessLine(age:)`. On a cache
//  miss past ttl the waterfall paints NO treads rather than a floor of
//  zeros. There are no mutations here at all, so no queue badge is ever
//  drawn — there is no escort outbox on the phone.
//
//  CHAIN — read chain CLOSED for all five backed slots. Write chain N-A.
//  COUNTER-PARTY CHAIN BROKEN: users.metadata.escortProfile.rating is read
//  seven times and written nowhere, so no shipper, catalyst, driver or
//  dispatcher has any path by which to rate this escort, and the escort
//  has no path by which to be rated. Filed ESC-GAP-27-RATING-COUNTERPARTY;
//  owning lane the ratings router; symbols owed ratings.ts:16
//  entityTypeSchema + escorts.submitEscortRating + an aggregate reader.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Wire projections (screen-local, private)
//
// Every field is OPTIONAL. A missing key decodes to nil, never to 0.
// `decimal` columns serialise as JSON strings, so numerics go through
// `ES27Number`, which accepts Int, Double or String and fails loudly on
// anything else rather than quietly yielding a zero.

private struct ES27Number: Codable, Equatable {
    let value: Double
    var int: Int { Int(value.rounded()) }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = Double(i); return }
        if let d = try? c.decode(Double.self) { value = d; return }
        if let s = try? c.decode(String.self), let d = Double(s) { value = d; return }
        throw DecodingError.dataCorruptedError(
            in: c, debugDescription: "ES-27: numeric field was neither number nor numeric string")
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}

/// escorts.getProfile · escorts.ts:3152-3160.
/// `incidentCount` (:3156), `repeatClientRate` (:3157) and `totalMiles`
/// (:3154) are DELIBERATELY ABSENT from this struct — they are hard-coded
/// zeros in the payload and binding them would render a lie as data.
private struct ES27ProfileStats: Codable, Equatable {
    let totalConvoys: ES27Number?
    let onTimePercentage: ES27Number?
    let leadJobs: ES27Number?
    let chaseJobs: ES27Number?
}

/// escorts.getProfile · escorts.ts:3081. `wallet` is not decoded either:
/// wallet.balance is the literal 0 at escorts.ts:3175.
private struct ES27Profile: Codable, Equatable {
    let id: String?
    let name: String?
    let stats: ES27ProfileStats?
}

/// escorts.getVehicleCheckHistory · escorts.ts:1344.
private struct ES27VehicleCheck: Codable, Equatable {
    let inspectionId: Int?
    let assignmentId: Int?
    let passed: Bool?
    let failedItems: [String]?
    let signedAt: String?
}

/// escorts.getIncidentStats · escorts.ts:2719.
private struct ES27IncidentStats: Codable, Equatable {
    let total: ES27Number?
    let open: ES27Number?
    let resolved: ES27Number?
    let critical: ES27Number?
}

/// escorts.getClearanceEventHistory · escorts.ts:4559 (drizzle/schema.ts:3862).
private struct ES27ClearanceEvent: Codable, Equatable {
    let id: Int?
    let eventType: String?          // strike | near_miss | clearance_check
    let damageObserved: Bool?
    let haulStopped: Bool?
    let escalation: String?         // none | logged | reported | incident
    let occurredAt: String?
}

private struct ES27ClearanceInput: Encodable { let limit: Int }
private struct ES27VehicleInput: Encodable { let limit: Int }

/// Everything this surface holds. Each half is optional so a partial
/// answer stays partial instead of collapsing into zeros.
private struct ES27Snapshot: Codable, Equatable {
    var profile: ES27Profile? = nil
    var checks: [ES27VehicleCheck]? = nil
    var incidents: ES27IncidentStats? = nil
    var clearance: [ES27ClearanceEvent]? = nil
}

// MARK: - The honesty machinery

/// No `.zero` member, on purpose.
enum ES27Contribution: Equatable {
    /// A signed contribution actually computed from a producer that answered.
    case measured(Int)
    /// No producer exists, or the producer did not answer. NOT a zero.
    case unmeasured
}

struct ES27Slot: Identifiable, Equatable {
    let key: String
    let label: String
    /// Share of the 100-point CLIENT-SIDE model. No server weight table exists.
    let weight: Int
    let contribution: ES27Contribution
    /// `escorts.ts:NNNN` for a backed slot; the literal grep that returned
    /// zero for a void one.
    let provenance: String

    var id: String { key }
    var isVoid: Bool { contribution == .unmeasured }
    var signed: Int? { if case .measured(let v) = contribution { return v }; return nil }
}

/// The fold. It cannot produce a point value while any slot is unmeasured,
/// and an unmeasured slot widens the ceiling instead of being summed as 0.
struct ES27Composite: Equatable {
    let banked: Int
    let unmeasuredWeight: Int

    var ceiling: Int { banked + unmeasuredWeight }
    var isComplete: Bool { unmeasuredWeight == 0 }
    /// nil until every slot has a producer.
    var pointValue: Int? { isComplete ? banked : nil }
    var intervalLabel: String { isComplete ? "\(banked)" : "\(banked)–\(ceiling)" }

    static func fold(_ slots: [ES27Slot]) -> ES27Composite {
        var banked = 0
        var missing = 0
        for slot in slots {
            switch slot.contribution {
            case .measured(let v): banked += v
            case .unmeasured:      missing += slot.weight
            }
        }
        return ES27Composite(banked: banked, unmeasuredWeight: missing)
    }
}

/// CLIENT-SIDE MODEL. grep escortScore|escort_score|escortRating|
/// escort_rating|escortPerformance over server/ drizzle/ shared/ → 0.
enum ES27Weights {
    static let onTime = 18
    static let rating = 14
    static let convoys = 12
    static let xp = 8
    static let checks = 10
    static let history = 10
    static let incidents = 8
    static let coaching = 6
    static let clearance = 7
    static let insurance = 7
}

private enum ES27Score {

    /// Every branch returns `.unmeasured` when the producer did not
    /// answer. None of them falls back to 0.
    static func slots(_ snap: ES27Snapshot) -> [ES27Slot] {
        [
            ES27Slot(key: "onTime", label: onTimeLabel(snap), weight: ES27Weights.onTime,
                     contribution: onTime(snap),
                     provenance: "escorts.getProfile · escorts.ts:3155"),
            ES27Slot(key: "rating", label: "RATING", weight: ES27Weights.rating,
                     contribution: .unmeasured,
                     provenance: "escortProfile.rating read 7× escorts.ts:3164-3170 · written 0×"),
            ES27Slot(key: "convoys", label: convoysLabel(snap), weight: ES27Weights.convoys,
                     contribution: convoys(snap),
                     provenance: "escorts.getProfile · escorts.ts:3153"),
            ES27Slot(key: "xp", label: "XP · BADGES", weight: ES27Weights.xp,
                     contribution: .unmeasured,
                     provenance: "grep ESCORT in gamification/achievements/advancedGamification/leaderboard → 0"),
            ES27Slot(key: "checks", label: checksLabel(snap), weight: ES27Weights.checks,
                     contribution: checks(snap),
                     provenance: "escorts.getVehicleCheckHistory · escorts.ts:1344"),
            ES27Slot(key: "history", label: "HISTORY", weight: ES27Weights.history,
                     contribution: .unmeasured,
                     provenance: "grep scoreHistory|score_history → 0"),
            ES27Slot(key: "incidents", label: incidentsLabel(snap), weight: ES27Weights.incidents,
                     contribution: incidents(snap),
                     provenance: "escorts.getIncidentStats · escorts.ts:2719"),
            ES27Slot(key: "coaching", label: "COACHING", weight: ES27Weights.coaching,
                     contribution: .unmeasured,
                     provenance: "grep coachingPlan|coaching_moment → 0"),
            ES27Slot(key: "clearance", label: clearanceLabel(snap), weight: ES27Weights.clearance,
                     contribution: clearance(snap),
                     provenance: "escorts.getClearanceEventHistory · escorts.ts:4559"),
            ES27Slot(key: "insurance", label: "INSURANCE", weight: ES27Weights.insurance,
                     contribution: .unmeasured,
                     provenance: "grep insuranceImpact|premiumImpact → 0"),
        ]
    }

    // ── credits

    static func onTime(_ s: ES27Snapshot) -> ES27Contribution {
        guard let pct = s.profile?.stats?.onTimePercentage?.value else { return .unmeasured }
        let earned = Int((min(max(pct, 0), 100) / 100.0 * Double(ES27Weights.onTime)).rounded())
        return .measured(earned)
    }

    static func convoys(_ s: ES27Snapshot) -> ES27Contribution {
        guard let n = s.profile?.stats?.totalConvoys?.int else { return .unmeasured }
        return .measured(min(ES27Weights.convoys, n / 15))
    }

    static func checks(_ s: ES27Snapshot) -> ES27Contribution {
        guard let rows = s.checks, !rows.isEmpty else { return .unmeasured }
        let known = rows.compactMap(\.passed)
        guard !known.isEmpty else { return .unmeasured }
        let rate = Double(known.filter { $0 }.count) / Double(known.count)
        return .measured(Int((rate * Double(ES27Weights.checks)).rounded()))
    }

    // ── penalties

    static func incidents(_ s: ES27Snapshot) -> ES27Contribution {
        guard let st = s.incidents, let total = st.total?.int else { return .unmeasured }
        let open = st.open?.int ?? 0
        let critical = st.critical?.int ?? 0
        let other = max(0, total - open - critical)
        let penalty = min(ES27Weights.incidents, open * 4 + critical * 8 + other * 1)
        return .measured(-penalty)
    }

    static func clearance(_ s: ES27Snapshot) -> ES27Contribution {
        guard let rows = s.clearance else { return .unmeasured }
        let strikes = rows.filter { $0.eventType == "strike" }.count
        let nearMisses = rows.filter { $0.eventType == "near_miss" }.count
        let penalty = min(ES27Weights.clearance, strikes * 7 + nearMisses * 3)
        return .measured(-penalty)
    }

    // ── labels (the figure is printed only when it exists)

    static func onTimeLabel(_ s: ES27Snapshot) -> String {
        guard let pct = s.profile?.stats?.onTimePercentage?.int else { return "ON-TIME" }
        return "ON-TIME \(pct)%"
    }
    static func convoysLabel(_ s: ES27Snapshot) -> String {
        guard let n = s.profile?.stats?.totalConvoys?.int else { return "CONVOYS" }
        return "CONVOYS \(n)"
    }
    static func checksLabel(_ s: ES27Snapshot) -> String {
        guard let rows = s.checks, !rows.isEmpty else { return "CHECKS" }
        let known = rows.compactMap(\.passed)
        return "CHECKS \(known.filter { $0 }.count)/\(known.count)"
    }
    static func incidentsLabel(_ s: ES27Snapshot) -> String {
        guard let n = s.incidents?.total?.int else { return "INCIDENTS" }
        return "INCIDENTS \(n)"
    }
    static func clearanceLabel(_ s: ES27Snapshot) -> String {
        guard let rows = s.clearance else { return "CLEARANCE" }
        let flagged = rows.filter { $0.eventType == "strike" || $0.eventType == "near_miss" }.count
        return "CLEARANCE \(flagged)"
    }
}

// MARK: - Service seam

private protocol ES27Reading {
    func profile() async throws -> ES27Profile?
    func vehicleChecks() async throws -> [ES27VehicleCheck]
    func incidentStats() async throws -> ES27IncidentStats?
    func clearanceEvents() async throws -> [ES27ClearanceEvent]
}

private struct ES27LiveReader: ES27Reading {
    func profile() async throws -> ES27Profile? {
        try await EusoTripAPI.shared.queryNoInput("escorts.getProfile")
    }
    func vehicleChecks() async throws -> [ES27VehicleCheck] {
        try await EusoTripAPI.shared.query("escorts.getVehicleCheckHistory",
                                           input: ES27VehicleInput(limit: 50))
    }
    func incidentStats() async throws -> ES27IncidentStats? {
        try await EusoTripAPI.shared.queryNoInput("escorts.getIncidentStats")
    }
    func clearanceEvents() async throws -> [ES27ClearanceEvent] {
        try await EusoTripAPI.shared.query("escorts.getClearanceEventHistory",
                                           input: ES27ClearanceInput(limit: 200))
    }
}

// MARK: - Nav intents (this file never touches EscortNavController)

extension Notification.Name {
    static let esES27OpenClearanceLog = Notification.Name("esES27OpenClearanceLog")
    static let esES27OpenCheckLog     = Notification.Name("esES27OpenCheckLog")
}

// MARK: - Screen body

struct EscortPerformanceScorecardES27: View {

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    private enum Phase { case loading, live, cached, partial, failed }

    @State private var phase: Phase = .loading
    @State private var snap = ES27Snapshot()
    @State private var cacheAge: TimeInterval? = nil
    @State private var readAt: Date? = nil
    /// Reads that threw. Named on the face — a read that did not answer is
    /// an unmeasured slot, never a zero one.
    @State private var failures: [String] = []

    private let reader: ES27Reading = ES27LiveReader()
    private let cacheKey = "escort.es27.scorecard"
    private let cacheTTL: TimeInterval = 600      // READ_CACHED(600s)

    private var isDark: Bool { scheme == .dark }
    private var creditInk: Color { isDark ? Color(hex: 0x34D399) : Color(hex: 0x0B7A4B) }
    private var penaltyInk: Color { isDark ? Color(hex: 0xF87171) : Color(hex: 0xB91C1C) }
    private var blueInk: Color { isDark ? Color(hex: 0x60A5FA) : Color(hex: 0x1D4ED8) }
    private var creditFill: Color { isDark ? Color(hex: 0x34D399) : Color(hex: 0x10B981) }
    private var penaltyFill: Color { isDark ? Color(hex: 0xF87171) : Color(hex: 0xEF4444) }
    private var amberFill: Color { isDark ? Color(hex: 0xFBBF24) : Color(hex: 0xF59E0B) }

    private var slots: [ES27Slot] { ES27Score.slots(snap) }
    private var composite: ES27Composite { .fold(slots) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            eyebrowRow
            titleRow
            IridescentHairline()
            metaRow
            content
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s2)
        .task { await refresh() }
        .eusoRefreshable { await refresh() }
    }

    // MARK: Header — DETAIL archetype

    private var eyebrowRow: some View {
        HStack {
            EusoTripEyebrow(verbatim: "ESCORT · PERFORMANCE SCORECARD")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: Space.s2)
            Text(snap.profile?.id.map { "ESCORT \($0)" } ?? "—")
                .font(EType.mono(.micro)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
    }

    private var titleRow: some View {
        Text("Performance")
            .font(.system(size: 28, weight: .bold)).tracking(-0.4)
            .foregroundStyle(palette.textPrimary)
            .lineLimit(1).minimumScaleFactor(0.7)
    }

    private var metaRow: some View {
        HStack(spacing: Space.s2) {
            chip("NO SERVER COMPOSITE", tint: penaltyFill, ink: penaltyInk)
            chip("MATH ON DEVICE", tint: Brand.blue, ink: blueInk)
            Circle()
                .fill(cacheAge == nil ? AnyShapeStyle(creditFill) : AnyShapeStyle(amberFill))
                .frame(width: 7, height: 7)
            Spacer(minLength: Space.s1)
            Text(readRegister)
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    /// A cached paint says so, in words, in the same slot the live register
    /// occupies. Nothing on this screen ever claims LIVE over a snapshot.
    private var readRegister: String {
        if let age = cacheAge { return EscortOfflineCache.stalenessLine(age: age).uppercased() }
        guard let at = readAt else { return "READING…" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "LIVE · READ \(f.string(from: at))"
    }

    private func chip(_ text: String, tint: Color, ink: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy)).tracking(0.4)
            .foregroundStyle(ink)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(isDark ? 0.16 : 0.10)))
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            VStack(alignment: .leading, spacing: Space.s3) {
                RoundedRectangle(cornerRadius: 20).fill(palette.bgCard).frame(height: 320)
                RoundedRectangle(cornerRadius: 16).fill(palette.bgCard).frame(height: 200)
            }
        case .failed:
            VStack(alignment: .leading, spacing: Space.s3) {
                emptyState(
                    title: "Nothing answered",
                    body: "Every read failed and there is no saved copy inside 10 minutes, so no treads are drawn. An empty waterfall is the truth here — a floor of zeros would look exactly like a bad record, and that is not what happened.")
                CTAButton(title: "Try again", action: { Task { await refresh() } })
            }
        case .live, .cached, .partial:
            VStack(alignment: .leading, spacing: Space.s5) {
                waterfallCard
                evidenceSection
                footnotes
                ctaRow
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

    // MARK: The one ActiveCard — the waterfall

    private var waterfallCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            sectionLabel("CONTRIBUTION WATERFALL",
                         trailing: "\(slots.filter { !$0.isVoid }.count) BACKED · \(slots.filter(\.isVoid).count) VOID",
                         ink: penaltyInk)

            ES27WaterfallChart(
                slots: slots, composite: composite,
                ink: palette.textPrimary, credit: creditFill, penalty: penaltyFill,
                creditInk: creditInk, penaltyInk: penaltyInk, voidInk: palette.textTertiary
            )
            .frame(height: 236)

            Text("SOLID TREAD = MEASURED · DASHED = WEIGHT WITH NO WRITER · HATCH = CANNOT NARROW")
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.65)

            Divider().background(palette.borderFaint)

            HStack(alignment: .lastTextBaseline) {
                Text(composite.intervalLabel)
                    .font(.system(size: 28, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("/ 100")
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: Space.s2)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(composite.pointValue == nil ? "INTERVAL · NOT A SCORE" : "COMPLETE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(penaltyInk)
                    Text("\(composite.unmeasuredWeight) OF 100 POINTS HAVE NO WRITER")
                        .font(.system(size: 8))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(Space.s4)
        .background(RoundedRectangle(cornerRadius: 18.5).fill(palette.bgCard))
        .padding(1.5)
        .background(RoundedRectangle(cornerRadius: 20).fill(LinearGradient.diagonal.opacity(0.85)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Composite between \(composite.banked) and \(composite.ceiling) out of 100. "
            + "\(composite.unmeasuredWeight) points have no producer, so no single score exists.")
    }

    // MARK: Evidence

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            sectionLabel("EVIDENCE · BACKED INPUTS",
                         trailing: "+2 FROM getProfile :3081", ink: palette.textTertiary)
            VStack(spacing: 0) {
                evidenceRow(slot: slots.first { $0.key == "checks" },
                            title: ES27Score.checksLabel(snap).capitalizedSentence,
                            glyph: "checkmark", tint: creditFill)
                Divider().background(palette.borderFaint).padding(.leading, 52)
                evidenceRow(slot: slots.first { $0.key == "incidents" },
                            title: incidentTitle, glyph: "exclamationmark.triangle", tint: penaltyFill)
                Divider().background(palette.borderFaint).padding(.leading, 52)
                evidenceRow(slot: slots.first { $0.key == "clearance" },
                            title: clearanceTitle, glyph: "arrow.up.and.down", tint: amberFill)
            }
            .padding(Space.s4)
            .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.borderFaint))
        }
    }

    private var incidentTitle: String {
        guard let st = snap.incidents, let total = st.total?.int else { return "Incidents · did not answer" }
        return "Incidents · \(total) total · \(st.open?.int ?? 0) open"
    }

    private var clearanceTitle: String {
        guard let rows = snap.clearance else { return "Clearance · did not answer" }
        let near = rows.filter { $0.eventType == "near_miss" }.count
        let strikes = rows.filter { $0.eventType == "strike" }.count
        if strikes > 0 { return "Clearance · \(strikes) strike\(strikes == 1 ? "" : "s")" }
        return "Clearance · \(near) near-miss logged"
    }

    /// A row whose slot is unmeasured prints NOT MEASURED, never a 0.
    private func evidenceRow(slot: ES27Slot?, title: String, glyph: String, tint: Color) -> some View {
        let value = slot?.signed
        let ink = (value ?? 0) >= 0 ? creditInk : penaltyInk
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(tint.opacity(isDark ? 0.22 : 0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: glyph)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(slot?.provenance ?? "no producer")
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 2) {
                Text(value == nil ? "NOT MEASURED" : (value! >= 0 ? "CREDIT" : "PENALTY"))
                    .font(.system(size: 11, weight: .bold)).tracking(0.6)
                    .foregroundStyle(value == nil ? palette.textTertiary : ink)
                Text(value.map { "\($0 > 0 ? "+" : "−")\(abs($0))" } ?? "—")
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(value == nil ? palette.textTertiary : ink)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: Footnotes + CTA

    private var footnotes: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("INCIDENTS, CLIENT RETURN RATE, MILES, AND BALANCE ARE NOT MEASURED HERE")
            Text("SCORECARD IS READ-ONLY · UNMEASURED METRICS REMAIN UNKNOWN")
            if !failures.isEmpty {
                Text("SOME SCORECARD SOURCES ARE UNAVAILABLE · VALUES REMAIN UNMEASURED, NOT ZERO")
                    .foregroundStyle(penaltyInk)
            }
        }
        .font(EType.mono(.micro))
        .foregroundStyle(palette.textTertiary)
        .lineLimit(1).minimumScaleFactor(0.55)
    }

    /// Two navigations onto reads that answer. No mutation exists on this
    /// surface, so no mutation button is drawn.
    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Open clearance log") {
                NotificationCenter.default.post(name: .esES27OpenClearanceLog, object: nil)
            }
            Button {
                NotificationCenter.default.post(name: .esES27OpenCheckLog, object: nil)
            } label: {
                Text("Check log")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 144, height: 48)
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().stroke(palette.borderSoft))
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionLabel(_ title: String, trailing: String, ink: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: Space.s2)
            Text(trailing)
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(ink)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: Load
    //
    // Each read is attempted independently and its failure is RECORDED,
    // never swallowed: a read that threw leaves its slot `.unmeasured` and
    // its name in the footnote. There is no `try?` that turns a decode
    // failure into an empty screen, and nothing anywhere substitutes 0.

    private func refresh() async {
        var next = ES27Snapshot()
        var failed: [String] = []

        do { next.profile = try await reader.profile() }
        catch { failed.append("getProfile") }

        do { next.checks = try await reader.vehicleChecks() }
        catch { failed.append("getVehicleCheckHistory") }

        do { next.incidents = try await reader.incidentStats() }
        catch { failed.append("getIncidentStats") }

        do { next.clearance = try await reader.clearanceEvents() }
        catch { failed.append("getClearanceEventHistory") }

        let anythingAnswered = next != ES27Snapshot()

        if anythingAnswered {
            await MainActor.run {
                snap = next
                failures = failed
                cacheAge = nil
                readAt = Date()
                phase = failed.isEmpty ? .live : .partial
            }
            EscortOfflineCache.store(next, key: cacheKey)
            return
        }

        if let hit = EscortOfflineCache.load(ES27Snapshot.self, key: cacheKey, ttl: cacheTTL) {
            await MainActor.run {
                snap = hit.value
                failures = failed
                cacheAge = hit.age
                phase = .cached
            }
        } else {
            await MainActor.run {
                snap = ES27Snapshot()      // no treads. Not a floor of zeros.
                failures = failed
                cacheAge = nil
                phase = .failed
            }
        }
    }
}

private extension String {
    var capitalizedSentence: String {
        guard let f = first else { return self }
        return String(f).uppercased() + dropFirst().lowercased()
    }
}

// MARK: - The waterfall
//
// One signed step per metric. A slot with no producer is a GAP — a dashed
// outline of the tread that is not there — and the wedge above the
// measured line widens by that slot's weight, which is why the terminal is
// an interval and not a point.

struct ES27WaterfallChart: View {
    let slots: [ES27Slot]
    let composite: ES27Composite
    let ink: Color
    let credit: Color
    let penalty: Color
    let creditInk: Color
    let penaltyInk: Color
    let voidInk: Color

    private let axisMax: Double = 80
    private let plotHeight: CGFloat = 168
    private let labelHeight: CGFloat = 64

    private var walk: [(loBefore: Int, loAfter: Int, hiAfter: Int)] {
        var lo = 0, hi = 0
        return slots.map { slot in
            let l0 = lo
            switch slot.contribution {
            case .measured(let v): lo += v; hi += v
            case .unmeasured:      hi += slot.weight
            }
            return (l0, lo, hi)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let pitch = geo.size.width / CGFloat(slots.count + 1)
            let bw = pitch * 0.74
            let steps = walk
            let y: (Double) -> CGFloat = { v in
                plotHeight - CGFloat(min(max(v, 0), axisMax) / axisMax) * plotHeight
            }
            let x: (Int) -> CGFloat = { i in
                CGFloat(i) * pitch + (pitch - bw) / 2
            }

            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    for g in [80.0, 40.0] {
                        var p = Path()
                        p.move(to: CGPoint(x: 0, y: y(g)))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y(g)))
                        ctx.stroke(p, with: .color(ink.opacity(0.10)),
                                   style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    }
                    var base = Path()
                    base.move(to: CGPoint(x: 0, y: y(0)))
                    base.addLine(to: CGPoint(x: geo.size.width, y: y(0)))
                    ctx.stroke(base, with: .color(ink.opacity(0.28)), lineWidth: 1)

                    guard !steps.isEmpty else { return }

                    // the wedge the composite cannot narrow
                    var wedge = Path()
                    wedge.move(to: CGPoint(x: 0, y: y(0)))
                    for (i, s) in steps.enumerated() {
                        wedge.addLine(to: CGPoint(x: CGFloat(i) * pitch, y: y(Double(s.hiAfter))))
                        wedge.addLine(to: CGPoint(x: CGFloat(i + 1) * pitch, y: y(Double(s.hiAfter))))
                    }
                    for (i, s) in steps.enumerated().reversed() {
                        wedge.addLine(to: CGPoint(x: CGFloat(i + 1) * pitch, y: y(Double(s.loAfter))))
                        wedge.addLine(to: CGPoint(x: CGFloat(i) * pitch, y: y(Double(s.loAfter))))
                    }
                    wedge.closeSubpath()
                    ctx.drawLayer { layer in
                        layer.clip(to: wedge)
                        var hatch = Path()
                        var hx = -plotHeight
                        while hx < geo.size.width + plotHeight {
                            hatch.move(to: CGPoint(x: hx, y: plotHeight))
                            hatch.addLine(to: CGPoint(x: hx + plotHeight, y: 0))
                            hx += 7
                        }
                        layer.stroke(hatch, with: .color(voidInk.opacity(0.30)), lineWidth: 1.1)
                    }
                    var ceiling = Path()
                    ceiling.move(to: CGPoint(x: 0, y: y(0)))
                    for (i, s) in steps.enumerated() {
                        ceiling.addLine(to: CGPoint(x: CGFloat(i) * pitch, y: y(Double(s.hiAfter))))
                        ceiling.addLine(to: CGPoint(x: CGFloat(i + 1) * pitch, y: y(Double(s.hiAfter))))
                    }
                    ctx.stroke(ceiling, with: .color(voidInk.opacity(0.75)),
                               style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))

                    // the measured line — broken wherever no metric answered
                    for (i, s) in steps.enumerated() {
                        var seg = Path()
                        seg.move(to: CGPoint(x: CGFloat(i) * pitch, y: y(Double(s.loAfter))))
                        seg.addLine(to: CGPoint(x: CGFloat(i + 1) * pitch, y: y(Double(s.loAfter))))
                        if slots[i].isVoid {
                            ctx.stroke(seg, with: .color(voidInk),
                                       style: StrokeStyle(lineWidth: 1.4, dash: [2, 3]))
                        } else {
                            ctx.stroke(seg, with: .color(ink.opacity(0.55)), lineWidth: 1.4)
                        }
                    }

                    // treads and gaps
                    for (i, slot) in slots.enumerated() {
                        let s = steps[i]
                        if let d = slot.signed {
                            let top = min(y(Double(s.loBefore)), y(Double(s.loAfter)))
                            let bot = max(y(Double(s.loBefore)), y(Double(s.loAfter)))
                            let rr = Path(roundedRect: CGRect(x: x(i), y: top, width: bw,
                                                              height: max(bot - top, 2)),
                                          cornerRadius: 3)
                            let colour = d >= 0 ? credit : penalty
                            ctx.fill(rr, with: .color(colour.opacity(0.30)))
                            ctx.stroke(rr, with: .color(colour), lineWidth: 1.8)
                        } else {
                            let top = y(Double(s.loAfter + slot.weight))
                            let bot = y(Double(s.loAfter))
                            let rr = Path(roundedRect: CGRect(x: x(i), y: top, width: bw,
                                                              height: max(bot - top, 2)),
                                          cornerRadius: 3)
                            ctx.stroke(rr, with: .color(voidInk),
                                       style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                        }
                    }

                    // terminal — banked solid, unresolvable hatched
                    let ti = slots.count
                    let termRect = CGRect(x: x(ti), y: y(Double(composite.banked)),
                                          width: bw,
                                          height: max(y(0) - y(Double(composite.banked)), 0))
                    ctx.fill(Path(roundedRect: termRect, cornerRadius: 3),
                             with: .linearGradient(Gradient(colors: [Brand.blue, Brand.magenta]),
                                                   startPoint: CGPoint(x: termRect.minX, y: termRect.minY),
                                                   endPoint: CGPoint(x: termRect.maxX, y: termRect.maxY)))
                    if !composite.isComplete {
                        let openRect = CGRect(x: x(ti), y: y(Double(composite.ceiling)),
                                              width: bw,
                                              height: max(y(Double(composite.banked))
                                                          - y(Double(composite.ceiling)), 0))
                        let rr = Path(roundedRect: openRect, cornerRadius: 3)
                        ctx.fill(rr, with: .color(voidInk.opacity(0.08)))
                        ctx.stroke(rr, with: .color(voidInk),
                                   style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                }
                .frame(height: plotHeight)

                ForEach(Array(slots.enumerated()), id: \.element.id) { i, slot in
                    let s = steps[i]
                    if let d = slot.signed {
                        Text("\(d >= 0 ? "+" : "−")\(abs(d))")
                            .font(.system(size: 8.5, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(d >= 0 ? creditInk : penaltyInk)
                            .position(x: CGFloat(i) * pitch + pitch / 2,
                                      y: min(y(Double(s.loBefore)), y(Double(s.loAfter))) - 7)
                    } else {
                        Text("\(slot.weight)")
                            .font(.system(size: 8, weight: .bold)).monospacedDigit()
                            .foregroundStyle(voidInk)
                            .position(x: CGFloat(i) * pitch + pitch / 2,
                                      y: (y(Double(s.loAfter)) + y(Double(s.loAfter + slot.weight))) / 2)
                    }
                }

                HStack(spacing: 0) {
                    ForEach(slots) { slot in
                        Text(slot.label)
                            .font(.system(size: 8, weight: .bold)).tracking(0.2)
                            .foregroundStyle(slot.isVoid ? voidInk : ink)
                            .fixedSize()
                            .rotationEffect(.degrees(-90))
                            .frame(width: pitch, height: labelHeight, alignment: .bottom)
                    }
                    Text("INTERVAL")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(ink)
                        .fixedSize()
                        .rotationEffect(.degrees(-90))
                        .frame(width: pitch, height: labelHeight, alignment: .bottom)
                }
                .offset(y: plotHeight + 4)
            }
        }
    }
}

// MARK: - Screen wrapper

struct EscortPerformanceScorecardES27Screen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortPerformanceScorecardES27()
        } nav: {
            BottomNav(
                leading: es27NavLeading(),
                trailing: es27NavTrailing(),
                orbState: .idle
            )
        }
    }
}

private func es27NavLeading() -> [NavSlot] {
    EscortNavRoute.leading(current: .me)
}

private func es27NavTrailing() -> [NavSlot] {
    EscortNavRoute.trailing(current: .me)
}

// MARK: - Previews
//
// `.task` does not run in the preview canvas, so both variants render in
// their loading register without touching the network.

#if DEBUG
#Preview("ES-27 · Performance Scorecard · Dark") {
    EscortPerformanceScorecardES27Screen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("ES-27 · Performance Scorecard · Light") {
    EscortPerformanceScorecardES27Screen(theme: Theme.light)
        .preferredColorScheme(.light)
}
#endif
