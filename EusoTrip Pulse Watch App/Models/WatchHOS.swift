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
    /// Provider identity and observation time travel with every snapshot so
    /// the wrist can distinguish a current legal observation from cached UI.
    var tracked: Bool?
    var source: String?
    var observedAt: Date?

    init(
        status: HOSStatus,
        driveRemainingMinutes: Int,
        windowRemainingMinutes: Int,
        cycleRemainingMinutes: Int,
        statusSince: Date,
        tracked: Bool? = nil,
        source: String? = nil,
        observedAt: Date? = nil
    ) {
        self.status = status
        self.driveRemainingMinutes = driveRemainingMinutes
        self.windowRemainingMinutes = windowRemainingMinutes
        self.cycleRemainingMinutes = cycleRemainingMinutes
        self.statusSince = statusSince
        self.tracked = tracked
        self.source = source
        self.observedAt = observedAt
    }

    /// Empty-state fixture — off-duty, all counters zero. Used at cold
    /// launch before the phone has pushed the first real snapshot so
    /// the wrist never renders synthetic data.
    static let empty = WatchHOS(
        status: .off,
        driveRemainingMinutes: 0,
        windowRemainingMinutes: 0,
        cycleRemainingMinutes: 0,
        statusSince: Date(),
        tracked: false
    )

    /// Legacy demo/placeholder shape. Retained so the SwiftUI preview
    /// on `#Preview` surfaces still compiles, but never used at runtime.
    static let placeholder = WatchHOS(
        status: .driving,
        driveRemainingMinutes: 4 * 60 + 12,
        windowRemainingMinutes: 7 * 60,
        cycleRemainingMinutes: 52 * 60,
        statusSince: Date().addingTimeInterval(-2 * 3600),
        tracked: true,
        source: "preview",
        observedAt: Date()
    )

    func hasCurrentObservation(at now: Date = Date()) -> Bool {
        guard tracked == true,
              source?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              let observedAt else { return false }
        let age = now.timeIntervalSince(observedAt)
        return age >= -(5 * 60) && age <= 15 * 60
    }

    var isEmpty: Bool {
        tracked != true
    }

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
