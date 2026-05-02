//
//  ShipperHandoffContinuity.swift
//  EusoTrip — Real `NSUserActivity` registry for the Continuity /
//  Handoff surfaces previewed in `238_ShipperHandoffContinuity.swift`.
//
//  Continuity / Handoff posts `NSUserActivity` objects to the system
//  so paired Apple devices (iPhone, iPad, Mac, Watch) can advertise
//  + resume the user's task. This file ships the canonical activity
//  type strings + a thin `ShipperContinuityBroker` that the screen
//  layer calls when the user navigates to a handoff-eligible surface.
//
//  No new Apple-developer-portal entitlement is needed for Handoff
//  itself (NSUserActivity is system-vended). Add the activity type
//  strings to the main app's Info.plist under `NSUserActivityTypes`
//  before calling `becomeCurrent()`. They are listed in the file
//  header below for easy copy-paste.
//
//  Activity types (must mirror Info.plist):
//    com.eusorone.eusotrip.LoadDetailActivity
//    com.eusorone.eusotrip.PostLoadActivity
//    com.eusorone.eusotrip.SettlementActivity
//    com.eusorone.eusotrip.BidsActivity
//    com.eusorone.eusotrip.ControlTowerActivity
//

import Foundation

/// Shipper-side Handoff/Continuity activity types. Each constant
/// matches a row that should be present in the main app Info.plist
/// `NSUserActivityTypes` array — without that, the activity fails
/// silently at `becomeCurrent()`.
public enum ShipperHandoffActivityType: String, CaseIterable {
    /// User is viewing a specific load detail. Carries `loadId`
    /// in `userInfo` so the receiving device can deep-link.
    case loadDetail     = "com.eusorone.eusotrip.LoadDetailActivity"
    /// User is in the post-load wizard. Carries the in-progress
    /// `PostLoadDraft` snapshot (origin/destination/cargoType/...).
    case postLoad       = "com.eusorone.eusotrip.PostLoadActivity"
    /// User is reviewing a settlement detail.
    case settlement     = "com.eusorone.eusotrip.SettlementActivity"
    /// User is reviewing bids on a load.
    case bids           = "com.eusorone.eusotrip.BidsActivity"
    /// User is on the control tower / exception feed.
    case controlTower   = "com.eusorone.eusotrip.ControlTowerActivity"
}

/// Single entry point the app uses to advertise + resign the
/// current activity. Calling `advertise(_:userInfo:)` immediately
/// supersedes any previous activity — only one per device is
/// active at a time.
@MainActor
public final class ShipperContinuityBroker {
    public static let shared = ShipperContinuityBroker()
    private init() {}

    private var current: NSUserActivity?

    /// Advertise the user's current task to nearby paired devices.
    /// Pass `nil` to resign without starting a new one (e.g. on
    /// sign-out or background entry where Handoff isn't appropriate).
    public func advertise(
        _ type: ShipperHandoffActivityType?,
        userInfo: [String: Any] = [:],
        title: String? = nil
    ) {
        // Resign any previous activity first.
        current?.resignCurrent()
        current = nil

        guard let type else { return }

        let activity = NSUserActivity(activityType: type.rawValue)
        if let title { activity.title = title }
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch  = false
        activity.requiredUserInfoKeys = Set(userInfo.keys)
        activity.userInfo = userInfo
        // Mark eligible for `Continue on Mac` Dock badge when the
        // user has a paired Mac running the EusoTrip Mac app.
        activity.becomeCurrent()
        current = activity
    }

    /// Drop any active advertisement. Call on sign-out.
    public func resign() {
        current?.resignCurrent()
        current = nil
    }
}
