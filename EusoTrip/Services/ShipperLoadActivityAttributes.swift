//
//  ShipperLoadActivityAttributes.swift
//  EusoTrip — ActivityKit attribute schema for the Lock Screen
//  Live Activity previewed in `232_ShipperLockScreenLiveActivity.swift`.
//
//  This file ships ONLY the data schema (`ActivityAttributes` +
//  `ContentState`) and the start/update/end orchestration entry
//  points (`ShipperLoadLiveActivityController`). It does NOT ship
//  the Live Activity widget bundle itself — that has to live inside
//  a Widget Extension target (Widget Extensions are a separate Xcode
//  target with their own Info.plist + entitlements + bundle id, and
//  cannot live in the main app bundle per Apple's framework rules).
//
//  Wiring the Widget Extension target is a separate engineering scope
//  (see the `[role-router:shipper-3.4]` commit message). Once that
//  target lands, its widget bundle imports this same `ActivityAttributes`
//  type and renders the visual Live Activity using the layout
//  documented in 232's preview surface — the schema is shared so the
//  in-app preview and the on-device Live Activity carry the exact
//  same fields.
//
//  iOS 17 deployment target — ActivityKit available since iOS 16.1.
//  Add `NSSupportsLiveActivities = YES` to the main app's Info.plist
//  before calling `Activity.request(attributes:contentState:)`.
//

import Foundation
import ActivityKit

/// Schema for the active-load Live Activity. One per active shipment.
/// `Attributes` are the immutable identifiers (set once when the
/// activity starts); `ContentState` is the mutable lifecycle state
/// the activity updates as the load progresses.
@available(iOS 16.1, *)
struct ShipperLoadActivityAttributes: ActivityAttributes {
    /// Mutable lifecycle state that drives the Lock Screen +
    /// Dynamic Island rendering. Field set mirrors the §11.4 row 3
    /// canon documented in `232_ShipperLockScreenLiveActivity.swift`
    /// so the preview surface and the live render share contracts.
    public struct ContentState: Codable, Hashable {
        /// 8-stage canonical lifecycle index (0=posted, 7=delivered).
        public let stageIndex: Int
        /// Friendly stage label ("In transit").
        public let stageLabel: String
        /// Lane string ("Kansas City, MO → Omaha, NE").
        public let laneSummary: String
        /// Driver display name (or "—" before assignment).
        public let driverName: String
        /// Carrier short name (or "—").
        public let carrierName: String
        /// Equipment chip ("MC-331 NH₃ UN1005" / "53' Reefer" / etc.).
        public let equipment: String
        /// Distance remaining in miles. `nil` until the driver sets
        /// off — the activity renders an em-dash placeholder.
        public let distanceRemainingMi: Int?
        /// Seconds-until-arrival countdown. `nil` if no ETA known.
        public let etaSeconds: Int?
        /// ISO8601 timestamp of the last server-pushed state change.
        public let lastUpdatedAt: String
        /// True when the lifecycle has hit a divergence (escort
        /// detached, geofence breach, HOS pause). Drives the alert
        /// gradient on the Live Activity card.
        public let alerting: Bool
    }

    /// Immutable identifiers set once when the activity starts.
    public let loadId: String
    public let loadNumber: String
    public let shipperCompanyName: String
}

// MARK: - Controller

/// Single entry point the app uses to start / update / end the
/// Live Activity for a given load. The controller checks
/// `ActivityAuthorizationInfo().areActivitiesEnabled` before each
/// call so it gracefully no-ops when the user has Live Activities
/// disabled in Settings.
@available(iOS 16.1, *)
@MainActor
final class ShipperLoadLiveActivityController {
    static let shared = ShipperLoadLiveActivityController()
    private init() {}

    /// Map of loadId → live `Activity` reference so update/end can
    /// find the matching activity without polling
    /// `Activity<ShipperLoadActivityAttributes>.activities`.
    private var active: [String: Activity<ShipperLoadActivityAttributes>] = [:]

    /// Start a new Live Activity for a load. Returns true if the
    /// activity was successfully requested. Idempotent — if an
    /// activity already exists for `loadId`, the existing one is
    /// updated instead. Uses the iOS 16.2+ `ActivityContent` wrapper
    /// API (the older `contentState:` / `using:` parameters were
    /// deprecated in 16.2).
    @discardableResult
    func start(
        loadId: String,
        loadNumber: String,
        shipperCompanyName: String,
        state: ShipperLoadActivityAttributes.ContentState
    ) -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        let content = ActivityContent(state: state, staleDate: nil)
        if let existing = active[loadId] {
            // Already running — fold the call into an update.
            Task { await existing.update(content) }
            return true
        }
        let attrs = ShipperLoadActivityAttributes(
            loadId: loadId,
            loadNumber: loadNumber,
            shipperCompanyName: shipperCompanyName
        )
        do {
            let activity = try Activity<ShipperLoadActivityAttributes>.request(
                attributes: attrs,
                content: content,
                pushType: nil
            )
            active[loadId] = activity
            return true
        } catch {
            return false
        }
    }

    /// Push a new content state to the existing activity for
    /// `loadId`. No-op if no activity exists for that id.
    func update(loadId: String, to state: ShipperLoadActivityAttributes.ContentState) async {
        guard let a = active[loadId] else { return }
        await a.update(ActivityContent(state: state, staleDate: nil))
    }

    /// End the activity. The Lock Screen card sticks around for the
    /// `dismissalPolicy` window so the user can see the final state,
    /// then iOS drops it.
    func end(loadId: String, finalState: ShipperLoadActivityAttributes.ContentState? = nil) async {
        guard let a = active[loadId] else { return }
        let finalContent = finalState.map { ActivityContent(state: $0, staleDate: nil) }
        await a.end(finalContent, dismissalPolicy: .default)
        active.removeValue(forKey: loadId)
    }

    /// End every activity this app started. Useful on sign-out.
    func endAll() async {
        for (_, a) in active {
            await a.end(nil, dismissalPolicy: .immediate)
        }
        active.removeAll()
    }
}
