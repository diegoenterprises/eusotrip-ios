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
    let severity: String?
    let message: String?
    let timestamp: String?
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
}

/// A single calendar day's log. Wraps the day's segments plus the
/// §395.8(f) totals the driver has to sign off on.
struct HOSDailyLog: Codable, Hashable, Identifiable {
    let date: String                    // YYYY-MM-DD (local to carrier tz)
    let entries: [HOSLogEntry]
    let drivingMinutes: Int
    let onDutyMinutes: Int
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
/// Any unknown keys are silently dropped by `Decodable`, so the
/// struct can grow with the backend without a migration.
struct HOSHoursAvailable: Codable, Hashable {
    let drivingRemaining: Double?
    let onDutyRemaining: Double?
    let cycleRemaining: Double?
}

/// Response from `hos.certifyLog`. The server returns the now-certified
/// day so the UI can reflect the signature + timestamp without refetching.
struct CertifyLogResult: Codable, Hashable {
    let ok: Bool
    let log: HOSDailyLog?
    let message: String?
}

/// Response from `hos.addRemark`. The remark attaches to the driver's
/// *current* (or supplied) segment and appears on the inline 24-hour
/// strip.
struct AddRemarkResult: Codable, Hashable {
    let ok: Bool
    let entry: HOSLogEntry?
    let message: String?
}
