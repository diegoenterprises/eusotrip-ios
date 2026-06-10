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
//

import Foundation

// MARK: - Dashboard widget shape (hos.getStatus)

struct HOSStatus: Codable, Hashable {
    let drivingRemaining: Double   // hours
    let onDutyRemaining: Double    // hours
    let cycleRemaining: Double     // hours
    let breakRequired: Bool
    let nextBreakDue: String?      // ISO-8601
    let status: String             // off_duty | sleeper | driving | on_duty
    let canDrive: Bool
    let canAcceptLoad: Bool

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

    static func formatHours(_ hours: Double) -> String {
        let totalMin = Int((hours * 60).rounded())
        let h = totalMin / 60
        let m = totalMin % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }
}

// MARK: - Detailed shape (hos.getCurrentStatus)

struct HOSLimit: Codable, Hashable {
    let used: Int       // minutes
    let limit: Int      // minutes
    let remaining: Int  // minutes
}

struct HOSLimits: Codable, Hashable {
    let driving: HOSLimit
    let onDuty: HOSLimit
    let cycle: HOSLimit
}

struct HOSCurrentStatus: Codable, Hashable {
    let driverId: String
    let currentStatus: String
    let statusStartTime: String
    let limits: HOSLimits
    let breakRequired: Bool
    let nextBreakDue: String?
    let lastRestartDate: String?
    let violations: [HOSViolation]
    let canDrive: Bool
    let canAcceptLoad: Bool
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

// MARK: - Demo fixture (offline fallback)

extension HOSStatus {
    /// A mid-shift "on-duty, driving" snapshot — 7h 22m drive / 11h 48m
    /// on-duty / 58h cycle remaining. Used when the backend is unreachable
    /// so the tile renders its split-gradient hour/minute design.
    static func demoOnDuty() -> HOSStatus {
        HOSStatus(
            drivingRemaining: 7.0 + 22.0 / 60.0,
            onDutyRemaining: 11.0 + 48.0 / 60.0,
            cycleRemaining: 58.0,
            breakRequired: false,
            nextBreakDue: nil,
            status: "driving",
            canDrive: true,
            canAcceptLoad: true
        )
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

    /// Decoded duty code with a safe fallback.
    var duty: HOSDutyCode {
        HOSDutyCode(rawValue: status) ?? .offDuty
    }

    /// Parsed start date or the epoch, so the timeline renders even if
    /// the server's clock drifts.
    var startDate: Date {
        HOSLogEntry.iso.date(from: startAt) ?? Date(timeIntervalSince1970: 0)
    }

    /// Parsed end date; nil means "still active".
    var endDate: Date? {
        guard let endAt else { return nil }
        return HOSLogEntry.iso.date(from: endAt)
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Best-effort minutes for this segment: explicit duration first,
    /// else the start→end span. Open segments (endAt == nil) return nil
    /// — we never extrapolate "now" into a stored log total.
    var resolvedMinutes: Int? {
        if let durationMinutes { return durationMinutes }
        guard let end = endDate else { return nil }
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
    let entries: [HOSLogEntry]
    let drivingMinutes: Int
    let onDutyMinutes: Int              // on-duty NOT driving (server totals.onDuty semantics)
    let milesDriven: Double?
    let certified: Bool
    let certifiedAt: String?
    let signature: String?              // sha256 of driver signature token
    let violations: [HOSViolation]

    var id: String { date }

    /// 11h 00m / 14h 00m / 58 mi style formatter used by both the ELD
    /// overview tiles and the 019 certify row.
    var drivingDisplay: String { HOSStatus.formatHours(Double(drivingMinutes) / 60.0) }
    var onDutyDisplay:  String { HOSStatus.formatHours(Double(onDutyMinutes)  / 60.0) }

    /// Copy of this day with the §395.8(g) certification stamped on —
    /// used by HOSLiveStore to reconcile a successful `certifyLog` ack
    /// (the server returns `{success, date, certifiedAt}` without
    /// echoing the day).
    func certifiedCopy(at certifiedAtISO: String?) -> HOSDailyLog {
        HOSDailyLog(
            date: date,
            entries: entries,
            drivingMinutes: drivingMinutes,
            onDutyMinutes: onDutyMinutes,
            milesDriven: milesDriven,
            certified: true,
            certifiedAt: certifiedAtISO ?? certifiedAt,
            signature: signature,
            violations: violations
        )
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
        case date, entries, totals
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
        entries = (boxes ?? []).compactMap(\.value)

        // Date — wire field, else derived from the first segment's start stamp.
        let rawDate = try c.decodeIfPresent(String.self, forKey: .date)
        date = rawDate ?? String((entries.first?.startAt ?? "").prefix(10))

        // Totals (minutes): flat keys → nested `totals` → summed from the
        // day's own segments. Driving and on-duty-not-driving stay separate.
        var driving = try? c.decodeIfPresent(Int.self, forKey: .drivingMinutes) ?? nil
        var onDuty  = try? c.decodeIfPresent(Int.self, forKey: .onDutyMinutes) ?? nil
        if driving == nil || onDuty == nil,
           let t = try? c.nestedContainer(keyedBy: TotalsKeys.self, forKey: .totals) {
            if driving == nil { driving = try? t.decodeIfPresent(Int.self, forKey: .driving) ?? nil }
            if onDuty == nil { onDuty = try? t.decodeIfPresent(Int.self, forKey: .onDuty) ?? nil }
        }
        let summed = HOSDailyLog.summedMinutes(entries)
        drivingMinutes = driving ?? summed.driving
        onDutyMinutes  = onDuty ?? summed.onDutyNotDriving

        milesDriven = try? c.decodeIfPresent(Double.self, forKey: .milesDriven) ?? nil
        certified   = (try? c.decodeIfPresent(Bool.self, forKey: .certified) ?? nil) ?? false
        certifiedAt = try? c.decodeIfPresent(String.self, forKey: .certifiedAt) ?? nil
        signature   = try? c.decodeIfPresent(String.self, forKey: .signature) ?? nil
        let vBoxes = (try? c.decodeIfPresent([HOSLossyRow<HOSViolation>].self, forKey: .violations)) ?? nil
        violations = (vBoxes ?? []).compactMap(\.value)
    }

    /// Sum real segment durations per duty bucket. Open segments
    /// contribute nothing (we don't extrapolate "now").
    static func summedMinutes(_ entries: [HOSLogEntry]) -> (driving: Int, onDutyNotDriving: Int) {
        var driving = 0
        var onDuty = 0
        for e in entries {
            guard let m = e.resolvedMinutes else { continue }
            switch e.duty {
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
    let canDrive: Bool
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
    /// Optional human-readable blurb the toast falls back to. We
    /// synthesise it locally since the server doesn't emit one —
    /// `"Status set to <NEW>"` reads as a successful confirmation.
    var message: String? {
        "Status set to \(newStatus.replacingOccurrences(of: "_", with: " "))"
    }
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
/// and `message` stay as computed properties so existing call-sites keep
/// compiling. NOTE (§395.8(g)): the server currently acknowledges
/// without persisting the certification — flagged upstream, do not paper
/// over it client-side.
struct CertifyLogResult: Codable, Hashable {
    let success: Bool
    let date: String?
    let certifiedAt: String?

    /// Legacy alias — same pattern as HOSChangeStatusResult.ok.
    var ok: Bool { success }
    /// The server doesn't echo the certified day; HOSLiveStore stamps
    /// the local copy via `HOSDailyLog.certifiedCopy(at:)` instead.
    var log: HOSDailyLog? { nil }
    /// Locally-synthesised toast copy (UI string, not wire data).
    var message: String? { success ? "Log certified" : nil }
}

/// Response from `hos.addRemark`. Real server shape (hos.ts:217-221):
///   { success, remarkId, addedAt }
/// The old struct required `ok` → every remark read as failed even when
/// the server accepted it (audit B5). NOTE: the server currently
/// acknowledges without persisting the remark — flagged upstream.
struct AddRemarkResult: Codable, Hashable {
    let success: Bool
    let remarkId: String?
    let addedAt: String?

    /// Legacy alias — same pattern as HOSChangeStatusResult.ok.
    var ok: Bool { success }
    /// The server doesn't echo a segment; the store refetches the log.
    var entry: HOSLogEntry? { nil }
    /// Locally-synthesised toast copy (UI string, not wire data).
    var message: String? { success ? "Remark added" : nil }
}
