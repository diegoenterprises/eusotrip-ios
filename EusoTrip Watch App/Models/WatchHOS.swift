//
//  WatchHOS.swift
//  EusoTrip Watch App
//
//  Hours-of-service snapshot for the wrist. Mirrors FMCSA 49 CFR §395.22
//  electronic logging categories (off / sleeper / driving / on_duty)
//  plus the canonical 11h drive / 14h window / 70h-in-8-days counters.
//

import Foundation

enum HOSStatus: String, Codable, CaseIterable {
    case off           = "off"
    case sleeper       = "sleeper"
    case driving       = "driving"
    case onDuty        = "on_duty"

    var label: String {
        switch self {
        case .off:      return "Off Duty"
        case .sleeper:  return "Sleeper"
        case .driving:  return "Driving"
        case .onDuty:   return "On Duty (not driving)"
        }
    }
    var short: String {
        switch self {
        case .off:      return "OFF"
        case .sleeper:  return "SB"
        case .driving:  return "DR"
        case .onDuty:   return "ON"
        }
    }
    var symbol: String {
        switch self {
        case .off:      return "moon.zzz.fill"
        case .sleeper:  return "bed.double.fill"
        case .driving:  return "steeringwheel"
        case .onDuty:   return "wrench.and.screwdriver.fill"
        }
    }
}

struct WatchHOS: Codable, Equatable {
    /// Current duty status.
    var status: HOSStatus
    /// Minutes remaining on the 11-hour drive counter.
    var driveRemainingMinutes: Int
    /// Minutes remaining on the 14-hour on-duty window.
    var windowRemainingMinutes: Int
    /// Minutes remaining on the 70-hour / 8-day rule (cycle).
    var cycleRemainingMinutes: Int
    /// When the current status started (used to age progress rings).
    var statusSince: Date

    static let placeholder = WatchHOS(
        status: .driving,
        driveRemainingMinutes: 4 * 60 + 12,
        windowRemainingMinutes: 7 * 60,
        cycleRemainingMinutes: 52 * 60,
        statusSince: Date().addingTimeInterval(-2 * 3600)
    )

    var driveHoursText: String {
        let h = driveRemainingMinutes / 60
        let m = driveRemainingMinutes % 60
        return String(format: "%dh %02dm", h, m)
    }
    var windowHoursText: String {
        let h = windowRemainingMinutes / 60
        let m = windowRemainingMinutes % 60
        return String(format: "%dh %02dm", h, m)
    }
    var drivePct: Double {
        max(0, min(1, Double(driveRemainingMinutes) / Double(11 * 60)))
    }
    var windowPct: Double {
        max(0, min(1, Double(windowRemainingMinutes) / Double(14 * 60)))
    }
    var cyclePct: Double {
        max(0, min(1, Double(cycleRemainingMinutes) / Double(70 * 60)))
    }
}
