//
//  HOSStatus.swift
//  EusoTrip — Codable mirrors of tRPC `hosRouter` response shapes
//
//  Authority: frontend/server/routers/hos.ts
//    • hos.getStatus         → HOSStatus (dashboard widget)
//    • hos.getCurrentStatus  → HOSCurrentStatus (detailed with per-limit breakdown)
//
//  All time values the backend exposes on getStatus are *hours* (Float).
//  getCurrentStatus exposes per-limit {used, limit, remaining} in *minutes* (Int).
//  Operational fields are nullable by design: an untracked or stale driver is
//  not equivalent to a driver with zero hours, an off-duty status, or a failed
//  compliance gate.
//

import Foundation

// MARK: - Observation truth

enum HOSTrackingState: Hashable, Codable {
    case tracked
    case partial
    case notTracked
    case unknown(String)

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "tracked": self = .tracked
        case "partial": self = .partial
        case "not_tracked": self = .notTracked
        default: self = .unknown(raw)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .tracked: try container.encode("tracked")
        case .partial: try container.encode("partial")
        case .notTracked: try container.encode("not_tracked")
        case .unknown(let raw): try container.encode(raw)
        }
    }

    var displayName: String {
        switch self {
        case .tracked: return "Tracked"
        case .partial: return "Partially tracked"
        case .notTracked: return "Not tracked"
        case .unknown: return "Tracking state unavailable"
        }
    }
}

struct HOSFieldTracking: Codable, Hashable {
    let status: Bool?
    let counters: Bool?
    let `break`: Bool?
    let violations: Bool?
    let todayLog: Bool?
}

enum HOSFreshnessState: Hashable {
    case current(observedAt: Date)
    case stale(observedAt: Date)
    case unavailable
    case invalid

    var isCurrent: Bool {
        if case .current = self { return true }
        return false
    }
}

enum HOSAssignmentEligibility: Hashable {
    case eligible
    case notTracked
    case partial
    case sourceUnavailable
    case freshnessUnavailable
    case stale
    case statusUnavailable
    case countersUnavailable
    case breakEvidenceUnavailable
    case serverBlocked

    var reason: String? {
        switch self {
        case .eligible: return nil
        case .notTracked: return "HOS is not tracked for this driver."
        case .partial: return "HOS evidence is only partially tracked."
        case .sourceUnavailable: return "HOS source is unavailable."
        case .freshnessUnavailable: return "HOS freshness is unavailable."
        case .stale: return "HOS evidence is stale."
        case .statusUnavailable: return "Current duty status is unavailable."
        case .countersUnavailable: return "HOS counters are unavailable."
        case .breakEvidenceUnavailable: return "Break evidence is unavailable."
        case .serverBlocked: return "The current HOS observation does not allow assignment."
        }
    }
}

enum HOSObservationClock {
    /// Matches the authoritative RIOS ELD policy and Smart Assign gate.
    static let maximumCurrentAge: TimeInterval = 15 * 60
    private static let futureClockTolerance: TimeInterval = 5 * 60

    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return fractional.date(from: raw) ?? internet.date(from: raw)
    }

    static func freshness(
        _ raw: String?,
        now: Date = Date(),
        maximumAge: TimeInterval = maximumCurrentAge
    ) -> HOSFreshnessState {
        guard let raw, !raw.isEmpty else { return .unavailable }
        guard let observedAt = parse(raw) else { return .invalid }
        let age = now.timeIntervalSince(observedAt)
        guard age >= -futureClockTolerance, age <= maximumAge else {
            return .stale(observedAt: observedAt)
        }
        return .current(observedAt: observedAt)
    }

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let internet: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

// MARK: - Dashboard widget shape (hos.getStatus)

struct HOSStatus: Codable, Hashable {
    let trackingState: HOSTrackingState?
    let tracked: Bool?
    let source: String?
    let freshness: String?
    let drivingRemaining: Double?   // hours
    let onDutyRemaining: Double?    // hours
    let cycleRemaining: Double?     // hours
    let breakRequired: Bool?
    let nextBreakDue: String?       // ISO-8601
    let status: String?             // off_duty | sleeper | driving | on_duty
    let canDrive: Bool?
    let canAcceptLoad: Bool?

    /// "7h 22m"
    var drivingRemainingDisplay: String {
        HOSStatus.formatHours(drivingRemaining)
    }

    /// "7h 22m"
    var onDutyRemainingDisplay: String {
        HOSStatus.formatHours(onDutyRemaining)
    }

    /// "58h 0m" — 70-hour/8-day or 60-hour/7-day cycle counter (§395.3(b)).
    var cycleRemainingDisplay: String {
        HOSStatus.formatHours(cycleRemaining)
    }

    static func formatHours(_ hours: Double?) -> String {
        guard let hours, hours.isFinite, hours >= 0 else { return "—" }
        let totalMin = Int((hours * 60).rounded())
        let h = totalMin / 60
        let m = totalMin % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    func freshnessState(now: Date = Date()) -> HOSFreshnessState {
        HOSObservationClock.freshness(freshness, now: now)
    }

    func hasCurrentObservation(now: Date = Date()) -> Bool {
        tracked == true
            && trackingState == .tracked
            && source?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && freshnessState(now: now).isCurrent
    }

    func assignmentEligibility(now: Date = Date()) -> HOSAssignmentEligibility {
        guard tracked == true else { return .notTracked }
        guard trackingState == .tracked else { return .partial }
        guard source?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return .sourceUnavailable
        }
        switch freshnessState(now: now) {
        case .current: break
        case .unavailable, .invalid: return .freshnessUnavailable
        case .stale: return .stale
        }
        guard status.flatMap(HOSDutyCode.init(rawValue:)) != nil else { return .statusUnavailable }
        guard let drivingRemaining,
              let onDutyRemaining,
              let cycleRemaining,
              drivingRemaining.isFinite,
              onDutyRemaining.isFinite,
              cycleRemaining.isFinite,
              drivingRemaining >= 0,
              onDutyRemaining >= 0,
              cycleRemaining >= 0 else {
            return .countersUnavailable
        }
        guard breakRequired != nil else { return .breakEvidenceUnavailable }
        guard canAcceptLoad == true, canDrive == true else { return .serverBlocked }
        return .eligible
    }
}

// MARK: - Detailed shape (hos.getCurrentStatus)

struct HOSLimit: Codable, Hashable {
    let used: Int?      // minutes
    let limit: Int      // minutes
    let remaining: Int? // minutes
}

struct HOSLimits: Codable, Hashable {
    let driving: HOSLimit
    let onDuty: HOSLimit
    let cycle: HOSLimit
}

struct HOSCurrentStatus: Codable, Hashable {
    let driverId: String
    let trackingState: HOSTrackingState?
    let tracked: Bool?
    let source: String?
    let freshness: String?
    let fieldTracking: HOSFieldTracking?
    let currentStatus: String?
    let statusStartTime: String?
    let limits: HOSLimits
    let breakRequired: Bool?
    let nextBreakDue: String?
    let lastRestartDate: String?
    let violations: [HOSViolation]
    let canDrive: Bool?
    let canAcceptLoad: Bool?

    func freshnessState(now: Date = Date()) -> HOSFreshnessState {
        HOSObservationClock.freshness(freshness, now: now)
    }

    func hasCurrentObservation(now: Date = Date()) -> Bool {
        tracked == true
            && trackingState == .tracked
            && source?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && freshnessState(now: now).isCurrent
    }

    func assignmentEligibility(now: Date = Date()) -> HOSAssignmentEligibility {
        guard tracked == true else { return .notTracked }
        guard trackingState == .tracked else { return .partial }
        guard source?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return .sourceUnavailable
        }
        switch HOSObservationClock.freshness(freshness, now: now) {
        case .current: break
        case .unavailable, .invalid: return .freshnessUnavailable
        case .stale: return .stale
        }
        guard currentStatus.flatMap(HOSDutyCode.init(rawValue:)) != nil,
              fieldTracking?.status == true else {
            return .statusUnavailable
        }
        guard fieldTracking?.counters == true,
              limits.driving.remaining != nil,
              limits.onDuty.remaining != nil,
              limits.cycle.remaining != nil else {
            return .countersUnavailable
        }
        guard fieldTracking?.break == true, breakRequired != nil else {
            return .breakEvidenceUnavailable
        }
        guard canAcceptLoad == true, canDrive == true else { return .serverBlocked }
        return .eligible
    }
}

/// Company-scoped driver evidence returned by `hos.getFleetHOS`. This is the
/// only driver-list shape that is allowed to decide assignment availability;
/// employment or active-load state alone is not HOS evidence.
struct HOSFleetDriver: Decodable, Hashable, Identifiable {
    let driverId: String
    let userId: Int?
    let name: String?
    let driverState: String?
    let identityState: String?
    let observationState: String?
    let trackingState: HOSTrackingState?
    let tracked: Bool?
    let source: String?
    let freshness: String?
    let status: String?
    let canDrive: Bool?
    let canAcceptLoad: Bool?
    let breakRequired: Bool?
    let violations: Int?
    let hoursAvailable: HOSHoursAvailable?
    let unavailableReason: String?

    var id: String { driverId }

    func hasCurrentObservation(now: Date = Date()) -> Bool {
        tracked == true
            && trackingState == .tracked
            && identityState == "linked"
            && observationState == "current"
            && source?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && HOSObservationClock.freshness(freshness, now: now).isCurrent
    }

    func assignmentEligibility(now: Date = Date()) -> HOSAssignmentEligibility {
        guard identityState == "linked", observationState == "current" else {
            return .notTracked
        }
        guard tracked == true else { return .notTracked }
        guard trackingState == .tracked else { return .partial }
        guard source?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return .sourceUnavailable
        }
        switch HOSObservationClock.freshness(freshness, now: now) {
        case .current: break
        case .unavailable, .invalid: return .freshnessUnavailable
        case .stale: return .stale
        }
        guard status.flatMap(HOSDutyCode.init(rawValue:)) != nil else {
            return .statusUnavailable
        }
        guard let hoursAvailable,
              hoursAvailable.drivingRemaining != nil,
              hoursAvailable.onDutyRemaining != nil,
              hoursAvailable.cycleRemaining != nil else {
            return .countersUnavailable
        }
        guard breakRequired != nil else { return .breakEvidenceUnavailable }
        guard canDrive == true, canAcceptLoad == true else { return .serverBlocked }
        return .eligible
    }
}

struct HOSViolation: Codable, Hashable {
    let type: String?
    let severity: String?      // server enum: "warning" | "violation"
    let message: String?       // wire key: `description` (hosEngine + ELD)
    let timestamp: String?     // wire key: `detectedAt` (hosEngine) | `occurredAt` (ELD)
    /// 49 CFR citation, e.g. "49 CFR 395.3(a)(3)(ii)" — the legally
    /// relevant reference the driver/manager surfaces must show.
    let cfr: String?
}

// Tolerant decoder — the server emits two violation dialects:
//   hosEngine.HOSViolation: { type, description, severity, cfr, detectedAt }
//   eld.ELDViolation:       { id, type, severity, description, occurredAt, … }
// Neither emits `message`/`timestamp`, which is what the iOS rows read —
// the old synthesized decoder nil'd both, so every violation rendered the
// hardcoded "Compliance violation" with no time and the CFR cite dropped.
// The init lives in an extension so the memberwise initializer survives.
extension HOSViolation {
    private enum WireKeys: String, CodingKey {
        case type, severity, cfr
        case message, description
        case timestamp, detectedAt, occurredAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: WireKeys.self)
        type     = try c.decodeIfPresent(String.self, forKey: .type)
        severity = try c.decodeIfPresent(String.self, forKey: .severity)
        var msg  = try c.decodeIfPresent(String.self, forKey: .message)
        if msg == nil { msg = try c.decodeIfPresent(String.self, forKey: .description) }
        message = msg
        var ts = try c.decodeIfPresent(String.self, forKey: .timestamp)
        if ts == nil { ts = try c.decodeIfPresent(String.self, forKey: .detectedAt) }
        if ts == nil { ts = try c.decodeIfPresent(String.self, forKey: .occurredAt) }
        timestamp = ts
        cfr = try c.decodeIfPresent(String.self, forKey: .cfr)
    }
}

// MARK: - Log / daily-log shapes (hos.changeStatus, hos.getDailyLog,
//        hos.getLogHistory, hos.certifyLog, hos.addRemark)
//
// Authority: frontend/server/routers/hos.ts — the log endpoints return
// segment-level §395.8 log entries plus per-day rollups that feed the
// 24-hour timeline on 019_HosDutyStatus and the cycle bar chart on the
// ELD overview screen. Times are ISO-8601; durations are minutes.

/// Canonical duty-status strings. Matches the server enum so we can
/// round-trip safely through tRPC without string-case surprises.
enum HOSDutyCode: String, Codable, Hashable, CaseIterable {
    case offDuty      = "off_duty"
    case sleeperBerth = "sleeper"
    case driving      = "driving"
    case onDuty       = "on_duty"

    /// Single-letter §395.8 line number label ("OFF", "SB", "D", "ON").
    var shortLabel: String {
        switch self {
        case .offDuty:      return "OFF"
        case .sleeperBerth: return "SB"
        case .driving:      return "D"
        case .onDuty:       return "ON"
        }
    }

    /// §395.8 line number the event is drawn on in a paper log.
    var lineNumber: Int {
        switch self {
        case .offDuty:      return 1
        case .sleeperBerth: return 2
        case .driving:      return 3
        case .onDuty:       return 4
        }
    }
}

/// One segment in the 24-hour duty-status log. Spans a contiguous run
/// of time in a single duty state. `endAt == nil` means still active.
struct HOSLogEntry: Codable, Hashable, Identifiable {
    /// Server-assigned identifier. Some payloads omit it for open-ended
    /// "current" segments; we synthesise one from startAt in that case.
    let id: String?
    let status: String                  // server enum: off_duty | sleeper | driving | on_duty
    let startAt: String                 // ISO-8601
    let endAt: String?                  // ISO-8601 or null for the live segment
    let durationMinutes: Int?
    let odometerStart: Double?          // miles
    let odometerEnd: Double?            // miles
    let locationDescription: String?    // "Chicago, IL", "Rest Area I-80 MM 228", ...
    let remark: String?                 // driver-entered note
    let automaticEntry: Bool?           // per §395.8(c), AOBRD-tagged

    /// Stable ID for SwiftUI ForEach — falls back to `startAt` when
    /// server id is absent (current open segment).
    var stableId: String { id ?? "live:\(startAt)" }

    /// A provider status outside the canonical duty enum is unknown. It must
    /// never be rendered or replayed as OFF duty.
    var duty: HOSDutyCode? {
        HOSDutyCode(rawValue: status)
    }

    /// A malformed timestamp is unavailable. Epoch is a real timestamp and
    /// must not be used as an error sentinel.
    var startDate: Date? {
        HOSObservationClock.parse(startAt)
    }

    /// Parsed end date; nil means "still active".
    var endDate: Date? {
        guard let endAt else { return nil }
        return HOSObservationClock.parse(endAt)
    }

    /// Best-effort minutes for this segment: explicit duration first,
    /// else the start→end span. Open segments (endAt == nil) return nil
    /// — we never extrapolate "now" into a stored log total.
    var resolvedMinutes: Int? {
        if let durationMinutes, durationMinutes >= 0 { return durationMinutes }
        guard let startDate, let end = endDate else { return nil }
        let span = end.timeIntervalSince(startDate)
        guard span > 0 else { return nil }
        return Int((span / 60).rounded())
    }
}

// Tolerant decoder — the server emits two segment dialects, NEITHER of
// which uses the Swift property names:
//   hosEngine.LogEntry:  { status, startTime, endTime, duration("2h 05m"), location? }
//   eld.ELDLogEntry:     { id, status, startTime, endTime, duration(minutes Int),
//                          location, notes?, edited, certified }
// The old synthesized decoder required `startAt`, so ANY non-empty entries
// array killed the whole daily-log decode (audit B2). `status` + a start
// time stay required — a segment without them cannot be drawn on the
// §395.8 grid — and HOSDailyLog skips such rows lossily instead of
// failing the day. Lives in an extension to keep the memberwise init.
extension HOSLogEntry {
    private enum WireKeys: String, CodingKey {
        case id, status
        case startAt, startTime
        case endAt, endTime
        case durationMinutes, duration
        case odometerStart, odometerEnd
        case locationDescription, location
        case remark, notes
        case automaticEntry
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: WireKeys.self)
        // id: ELD entries carry one (string or numeric); engine segments don't.
        if let s = try? c.decodeIfPresent(String.self, forKey: .id) {
            id = s
        } else if let n = try? c.decodeIfPresent(Int.self, forKey: .id) {
            // SE-0230: `try?` flattens the nested optional, so `n` is Int here.
            id = String(n)
        } else {
            id = nil
        }
        status = try c.decode(String.self, forKey: .status)
        if let s = try c.decodeIfPresent(String.self, forKey: .startAt) {
            startAt = s
        } else {
            startAt = try c.decode(String.self, forKey: .startTime)
        }
        var end = try c.decodeIfPresent(String.self, forKey: .endAt)
        if end == nil { end = try c.decodeIfPresent(String.self, forKey: .endTime) }
        endAt = end
        // duration: minutes Int (ELD), formatted "10h 05m" string (engine),
        // or absent. Never guessed — nil when unparseable.
        var minutes = try? c.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? nil
        if minutes == nil { minutes = (try? c.decodeIfPresent(Int.self, forKey: .duration) ?? nil) }
        if minutes == nil, let d = try? c.decodeIfPresent(Double.self, forKey: .duration) ?? nil {
            minutes = Int(d.rounded())
        }
        if minutes == nil, let s = try? c.decodeIfPresent(String.self, forKey: .duration) ?? nil {
            minutes = HOSLogEntry.parseHM(s)
        }
        durationMinutes = minutes
        odometerStart = try? c.decodeIfPresent(Double.self, forKey: .odometerStart) ?? nil
        odometerEnd   = try? c.decodeIfPresent(Double.self, forKey: .odometerEnd) ?? nil
        var loc = try c.decodeIfPresent(String.self, forKey: .locationDescription)
        if loc == nil { loc = try c.decodeIfPresent(String.self, forKey: .location) }
        locationDescription = loc
        var note = try c.decodeIfPresent(String.self, forKey: .remark)
        if note == nil { note = try c.decodeIfPresent(String.self, forKey: .notes) }
        remark = note
        automaticEntry = try? c.decodeIfPresent(Bool.self, forKey: .automaticEntry) ?? nil
    }

    /// "10h 05m" / "0h 45m" / "45m" / "11h" → total minutes. nil when the
    /// string carries no recognisable h/m component.
    static func parseHM(_ raw: String) -> Int? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return nil }
        if let pure = Int(s) { return pure }   // bare minutes, e.g. "45"
        var total = 0
        var found = false
        if let hRange = s.range(of: #"\d+\s*h"#, options: .regularExpression),
           let h = Int(s[hRange].filter(\.isNumber)) {
            total += h * 60
            found = true
        }
        if let mRange = s.range(of: #"\d+\s*m"#, options: .regularExpression),
           let m = Int(s[mRange].filter(\.isNumber)) {
            total += m
            found = true
        }
        return found ? total : nil
    }
}

/// A single calendar day's log. Wraps the day's segments plus the
/// §395.8(f) totals the driver has to sign off on.
struct HOSDailyLog: Codable, Hashable, Identifiable {
    let date: String                    // YYYY-MM-DD (local to carrier tz)
    let trackingState: HOSTrackingState?
    let tracked: Bool?
    let source: String?
    let freshness: String?
    let entries: [HOSLogEntry]
    let malformedEntryCount: Int
    let drivingMinutes: Int?
    let onDutyMinutes: Int?             // on-duty NOT driving (server totals.onDuty semantics)
    let milesDriven: Double?
    let certified: Bool?
    let certifiedAt: String?
    let signature: String?              // sha256 of driver signature token
    let violations: [HOSViolation]

    var id: String { date }

    /// 11h 00m / 14h 00m / 58 mi style formatter used by both the ELD
    /// overview tiles and the 019 certify row.
    var drivingDisplay: String { HOSStatus.formatHours(drivingMinutes.map { Double($0) / 60.0 }) }
    var onDutyDisplay:  String { HOSStatus.formatHours(onDutyMinutes.map { Double($0) / 60.0 }) }

    var hasCurrentLogEvidence: Bool {
        tracked == true
            && trackingState == .tracked
            && source?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && HOSObservationClock.freshness(freshness).isCurrent
            && malformedEntryCount == 0
    }

}

// Tolerant decoder — `hos.getDailyLog` returns
//   { date, driverId, entries, totals: {driving, onDuty, offDuty, sleeper},
//     violations, certified }
// with the rollups NESTED under `totals` (minutes), while the old
// synthesized decoder required flat non-optional `drivingMinutes` /
// `onDutyMinutes` → keyNotFound on every live payload (audit B1).
// `hos.getLogHistory`'s fallback rows are `{date, entries}`-ONLY (audit
// B3), so everything except the segments is optional here, with honest
// defaults: totals are derived by summing the day's real segment
// durations when the wire omits them — never invented.
extension HOSDailyLog {
    private enum WireKeys: String, CodingKey {
        case date, trackingState, tracked, source, freshness, entries, totals
        case drivingMinutes, onDutyMinutes
        case milesDriven, certified, certifiedAt, signature, violations
    }
    private enum TotalsKeys: String, CodingKey {
        case driving, onDuty
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: WireKeys.self)

        // Segments — lossy: a malformed row is skipped, it never kills the day.
        let boxes = (try? c.decodeIfPresent([HOSLossyRow<HOSLogEntry>].self, forKey: .entries)) ?? nil
        let decodedRows = boxes ?? []
        entries = decodedRows.compactMap(\.value)
        malformedEntryCount = decodedRows.filter { $0.value == nil }.count

        // Date — wire field, else derived from the first segment's start stamp.
        let rawDate = try c.decodeIfPresent(String.self, forKey: .date)
        let resolvedDate = rawDate ?? entries.first.map { String($0.startAt.prefix(10)) }
        guard let resolvedDate, !resolvedDate.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .date,
                in: c,
                debugDescription: "HOS daily log has neither a date nor a valid dated segment"
            )
        }
        date = resolvedDate
        trackingState = try c.decodeIfPresent(HOSTrackingState.self, forKey: .trackingState)
        tracked = try c.decodeIfPresent(Bool.self, forKey: .tracked)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        freshness = try c.decodeIfPresent(String.self, forKey: .freshness)

        // Totals (minutes): flat keys → nested `totals` → summed from the
        // day's own segments. Driving and on-duty-not-driving stay separate.
        var driving = try? c.decodeIfPresent(Int.self, forKey: .drivingMinutes) ?? nil
        var onDuty  = try? c.decodeIfPresent(Int.self, forKey: .onDutyMinutes) ?? nil
        if driving == nil || onDuty == nil,
           let t = try? c.nestedContainer(keyedBy: TotalsKeys.self, forKey: .totals) {
            if driving == nil { driving = try? t.decodeIfPresent(Int.self, forKey: .driving) ?? nil }
            if onDuty == nil { onDuty = try? t.decodeIfPresent(Int.self, forKey: .onDuty) ?? nil }
        }
        let summed = malformedEntryCount == 0 ? HOSDailyLog.summedMinutes(entries) : nil
        drivingMinutes = driving ?? summed?.driving
        onDutyMinutes  = onDuty ?? summed?.onDutyNotDriving

        milesDriven = try? c.decodeIfPresent(Double.self, forKey: .milesDriven) ?? nil
        certified   = try? c.decodeIfPresent(Bool.self, forKey: .certified) ?? nil
        certifiedAt = try? c.decodeIfPresent(String.self, forKey: .certifiedAt) ?? nil
        signature   = try? c.decodeIfPresent(String.self, forKey: .signature) ?? nil
        let vBoxes = (try? c.decodeIfPresent([HOSLossyRow<HOSViolation>].self, forKey: .violations)) ?? nil
        violations = (vBoxes ?? []).compactMap(\.value)
    }

    /// Sum real segment durations per duty bucket. Open segments
    /// contribute nothing (we don't extrapolate "now").
    static func summedMinutes(_ entries: [HOSLogEntry]) -> (driving: Int, onDutyNotDriving: Int)? {
        guard !entries.isEmpty else { return nil }
        var driving = 0
        var onDuty = 0
        for e in entries {
            guard let m = e.resolvedMinutes, let duty = e.duty else { return nil }
            switch duty {
            case .driving: driving += m
            case .onDuty:  onDuty += m
            case .offDuty, .sleeperBerth: break
            }
        }
        return (driving, onDuty)
    }
}

/// Element-level lossy decoding: always succeeds, `value == nil` when the
/// row didn't decode. Lets one malformed segment/violation drop out
/// without nuking the surrounding array (the decode-shape silent-fail trap).
struct HOSLossyRow<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) {
        value = try? T(from: decoder)
    }
}

/// One element of the `hos.getLogHistory` response, which is shape-forked
/// server-side (hos.ts:194-202):
///   • ELD-connected: a FLAT array of segment objects (`{id, status,
///     startTime, endTime, duration, …}`) spanning the whole window
///   • engine fallback: `[{date, entries}]` day rows (or `[]`)
/// HOSAPI.getLogHistory decodes this union and folds flat segments into
/// per-day `HOSDailyLog` rows so both dialects render.
enum HOSLogHistoryRow: Decodable {
    case day(HOSDailyLog)
    case entry(HOSLogEntry)
    case undecodable

    private enum ProbeKeys: String, CodingKey {
        case date, entries, startTime, startAt
    }

    init(from decoder: Decoder) throws {
        guard let probe = try? decoder.container(keyedBy: ProbeKeys.self) else {
            self = .undecodable
            return
        }
        if probe.contains(.date) || probe.contains(.entries) {
            if let d = try? HOSDailyLog(from: decoder) {
                self = .day(d)
                return
            }
        } else if probe.contains(.startTime) || probe.contains(.startAt) {
            if let e = try? HOSLogEntry(from: decoder) {
                self = .entry(e)
                return
            }
        }
        self = .undecodable
    }
}

/// Response from `hos.changeStatus`. Mirrors the server's real shape
/// — MCP-verified at `frontend/server/routers/hos.ts:99-108`:
///   { success, previousStatus, newStatus, timestamp, location,
///     canDrive, violations, hoursAvailable }
///
/// Earlier builds expected `{ ok, status, snapshot, entry, message }`
/// which the server never sent — decoder failed silently and the UI
/// thought every successful transition was an error. The new shape
/// pulls only what the server actually writes.
struct HOSChangeStatusResult: Codable, Hashable {
    let success: Bool
    let previousStatus: String?
    let newStatus: String
    let timestamp: String?
    let location: String?
    let canDrive: Bool?
    let violations: [HOSViolation]
    /// Server-computed object with per-limit remaining hours. Decoded
    /// loosely because the server occasionally adds fields here.
    let hoursAvailable: HOSHoursAvailable?

    /// Legacy-compatible alias so existing call-sites that read `ok`
    /// keep compiling. Maps to the server's `success` field verbatim.
    var ok: Bool { success }
    /// Legacy-compatible alias for `newStatus` → `status`.
    var status: String { newStatus }
    /// `HOSLiveStore` pulls a fresh snapshot right after the
    /// transition so we don't need the backend to embed one. Nil is
    /// fine for every render path that already existed before this
    /// shape was tightened.
    var snapshot: HOSStatus? { nil }
    /// Ditto.
    var entry: HOSLogEntry? { nil }
}

/// The server's `hoursAvailable` sub-object on `changeStatus`. All
/// fields are hours (Double) matching the dashboard snapshot shape.
/// Wire keys are `{driving, onDuty, cycle}` (hosEngine
/// `HOSSummary.hoursAvailable`) — the Swift names keep the
/// "-Remaining" suffix consumers expect, mapped via CodingKeys.
struct HOSHoursAvailable: Codable, Hashable {
    let drivingRemaining: Double?
    let onDutyRemaining: Double?
    let cycleRemaining: Double?

    private enum CodingKeys: String, CodingKey {
        case drivingRemaining = "driving"
        case onDutyRemaining  = "onDuty"
        case cycleRemaining   = "cycle"
    }
}

/// Response from `hos.certifyLog`. Real server shape (hos.ts:208-212):
///   { success, date, certifiedAt, certifiedBy }
/// The old struct required a key the server never sends (`ok`) so every
/// successful certification decoded as a failure (audit B4). `ok`, `log`
/// Confirmation is emitted only after `success` is decoded and the store
/// verifies the resulting certification through a fresh read.
struct CertifyLogResult: Codable, Hashable {
    let success: Bool
    let date: String?
    let certifiedAt: String?

    /// Legacy alias — same pattern as HOSChangeStatusResult.ok.
    var ok: Bool { success }
    /// The server doesn't echo the certified daily-log record. The store
    /// therefore refetches rather than synthesizing a local certification.
    var log: HOSDailyLog? { nil }
}

/// Response from `hos.addRemark`. Real server shape (hos.ts:217-221):
///   { success, remarkId, addedAt }
/// The old struct required `ok` → every remark read as failed even when
/// the server accepted it (audit B5).
struct AddRemarkResult: Codable, Hashable {
    let success: Bool
    let remarkId: String?
    let addedAt: String?

    /// Legacy alias — same pattern as HOSChangeStatusResult.ok.
    var ok: Bool { success }
    /// The server doesn't echo a segment; the store refetches the log.
    var entry: HOSLogEntry? { nil }
}
