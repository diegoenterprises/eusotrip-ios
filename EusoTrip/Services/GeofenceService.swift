//
//  GeofenceService.swift
//  EusoTrip — CoreLocation region monitoring → TripEvent bridge.
//
//  For each active load we register two `CLCircularRegion`s:
//      • "pickup-<loadId>"   centered on pickupLocation,   radius 3.2km (~2mi)
//      • "delivery-<loadId>" centered on deliveryLocation, radius 3.2km
//
//  On region entry we fire the corresponding `TripEvent` into the shared
//  `DriverTripController` so the UI auto-advances without the driver
//  having to tap. The outer radius is deliberately ~2 mi so the
//  "approaching" screen (014 / 020) has time to render before the driver
//  is actually at the gate. The inner, at-location transition still
//  happens through the CTA tap (or future dispatch confirmation).
//
//  Permission posture:
//    • Requests `whenInUse` on first bind — enough for foreground flows.
//    • The `NSLocationWhenInUseUsageDescription` key must be in Info.plist.
//    • L13-4: `monitor(load:)` now escalates to Always + enables background
//      CoreLocation (Info.plist declares the `location` background mode) so a
//      screen-locked arrival wakes the app to post the ON-SITE flip.
//
//  L13-4 — closing the geofence loop:
//    Beyond the UI auto-advance, each server fence crossing now posts
//    `location.telemetry.geofenceEvent` (ENTER/EXIT) → server
//    `processGeofenceEvent` → load-status flip (at_pickup / at_delivery /
//    departed) + detention clock. Wide entry-only "pickup-/delivery-<loadId>"
//    regions remain as the UI fallback; tight "srv|<id>|<kind>|<loadId>"
//    regions (resolved from real `geofences` rows) are the ones that post.
//

import Foundation
import CoreLocation
import Combine

@MainActor
final class GeofenceService: NSObject, ObservableObject,
                             CLLocationManagerDelegate {

    static let shared = GeofenceService()

    enum Phase: Equatable {
        case unknown
        case denied
        case authorizedInUse
        case authorizedAlways
    }

    @Published private(set) var phase: Phase = .unknown

    private let manager = CLLocationManager()
    /// Weak reference to the trip controller is resolved lazily the first
    /// time a geofence fires, so construction order (App init → Session →
    /// Controller) doesn't matter.
    private weak var controller: DriverTripController?

    private var monitoredLoadId: Int?

    /// L13-4 — identifiers of the SERVER-backed regions (encode the numeric
    /// geofence id + kind + loadId, so a background-relaunched delegate can
    /// still post without the in-memory map). Fallback UI regions
    /// ("pickup-<loadId>") are NOT in this set and never post.
    private var serverRegionIds: Set<String> = []
    private var didConfigureBackground = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: Binding

    /// Called by the root view once `DriverTripController` exists. The
    /// service caches a weak reference so it can fire `TripEvent`s the
    /// moment CoreLocation reports a region transition.
    func bind(to controller: DriverTripController) {
        self.controller = controller
    }

    /// Begin monitoring the pickup + delivery regions for a load.
    /// Replaces any previously-monitored load in one call — there's only
    /// ever one active load per driver.
    ///
    /// L13-4: escalates to Always + enables background updates so a
    /// screen-locked arrival still wakes the app, registers wide entry-only
    /// UI-approach regions immediately (so 014/020 auto-advance never
    /// regresses), then upgrades to server-fence-backed regions (with the
    /// numeric geofence id + EXIT + event posting) as soon as the fence rows
    /// resolve — which is what drives the server-side ON-SITE / departed
    /// status flips (doc §4).
    func monitor(load: Load) {
        ensureAuthorized()
        escalateToAlways()          // background-wake geofences (was never called)
        configureForBackground()    // background CoreLocation posture
        clearAll()
        monitoredLoadId = load.id

        registerApproachRegions(for: load)   // immediate UI fallback (entry-only)

        // Upgrade to server-fence-backed regions (id + EXIT + posting).
        Task { await resolveAndRegisterServerFences(for: load) }

        #if DEBUG
        print("[Geofence] monitoring load \(load.id) · approach regions up, resolving server fences")
        #endif
    }

    /// Wide (~2 mi) entry-only regions that fire the UI approach TripEvents.
    /// These carry no server id and never post — they only exist so the
    /// approaching screen renders even before/without a server fence row.
    private func registerApproachRegions(for load: Load) {
        if let p = load.pickupLocation, p.lat != 0 || p.lng != 0 {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng),
                radius: 3200, identifier: "pickup-\(load.id)")
            region.notifyOnEntry = true
            region.notifyOnExit  = false
            manager.startMonitoring(for: region)
        }
        if let d = load.deliveryLocation, d.lat != 0 || d.lng != 0 {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: d.lat, longitude: d.lng),
                radius: 3200, identifier: "delivery-\(load.id)")
            region.notifyOnEntry = true
            region.notifyOnExit  = false
            manager.startMonitoring(for: region)
        }
    }

    /// One-time background posture. `allowsBackgroundLocationUpdates` is only
    /// safe because `UIBackgroundModes` declares `location` — verified in
    /// Info.plist (setting it otherwise throws).
    private func configureForBackground() {
        guard !didConfigureBackground else { return }
        didConfigureBackground = true
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .automotiveNavigation
    }

    /// Resolve the PICKUP_FACILITY / DELIVERY_FACILITY fence rows for the load,
    /// creating them server-side if none exist yet, then register tight
    /// enter+exit regions keyed by the numeric geofence id. Any failure leaves
    /// the entry-only approach regions in place (honest degrade — no posting).
    @MainActor
    private func resolveAndRegisterServerFences(for load: Load) async {
        guard monitoredLoadId == load.id else { return }
        let gf = EusoTripAPI.shared.trackingGeofences

        // Facility coordinates (nil when the load carries no real coord).
        let pickup: (lat: Double, lng: Double)? = load.pickupLocation.flatMap {
            ($0.lat != 0 || $0.lng != 0) ? ($0.lat, $0.lng) : nil
        }
        let delivery: (lat: Double, lng: Double)? = load.deliveryLocation.flatMap {
            ($0.lat != 0 || $0.lng != 0) ? ($0.lat, $0.lng) : nil
        }
        guard pickup != nil || delivery != nil else { return }

        // Resolve each facility independently so every fence keeps its kind.
        func resolve() async -> (pickup: TrackingGeofencesAPI.IdentifiedFence?,
                                 delivery: TrackingGeofencesAPI.IdentifiedFence?) {
            var pf: TrackingGeofencesAPI.IdentifiedFence? = nil
            var df: TrackingGeofencesAPI.IdentifiedFence? = nil
            if let p = pickup { pf = await gf.identifiedFences(near: [p]).first }
            if let d = delivery { df = await gf.identifiedFences(near: [d]).first }
            return (pf, df)
        }

        var resolved = await resolve()
        guard monitoredLoadId == load.id else { return }

        // If a needed facility has no fence yet, create the load's fences once
        // (ownership-gated server-side; requires BOTH coords) and re-resolve.
        let needsCreate = (pickup != nil && resolved.pickup == nil)
            || (delivery != nil && resolved.delivery == nil)
        if needsCreate, let p = pickup, let d = delivery {
            try? await gf.createFencesForLoad(
                loadId: load.id,
                pickupLat: p.lat, pickupLng: p.lng, pickupFacilityName: nil,
                deliveryLat: d.lat, deliveryLng: d.lng, deliveryFacilityName: nil)
            guard monitoredLoadId == load.id else { return }
            resolved = await resolve()
            guard monitoredLoadId == load.id else { return }
        }

        if let f = resolved.pickup { registerServerRegion(f, kind: "pickup", loadId: load.id) }
        if let f = resolved.delivery { registerServerRegion(f, kind: "delivery", loadId: load.id) }
    }

    /// Register a tight enter+exit region keyed by the numeric geofence id and
    /// retire the wide approach region for that leg (the server fence supersedes
    /// it). Radius clamped to [150, 3200] m.
    private func registerServerRegion(_ fence: TrackingGeofencesAPI.IdentifiedFence,
                                      kind: String, loadId: Int) {
        // Retire the entry-only approach region for this leg.
        if let stale = manager.monitoredRegions.first(where: { $0.identifier == "\(kind)-\(loadId)" }) {
            manager.stopMonitoring(for: stale)
        }
        let id = "srv|\(fence.id)|\(kind)|\(loadId)"
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: fence.center.lat, longitude: fence.center.lng),
            radius: min(max(fence.radiusMeters, 150), 3200),
            identifier: id)
        region.notifyOnEntry = true
        region.notifyOnExit  = true
        manager.startMonitoring(for: region)
        serverRegionIds.insert(id)
        #if DEBUG
        print("[Geofence] server fence up · \(id) · r=\(Int(region.radius))m")
        #endif
    }

    /// Parse a server region identifier "srv|<geofenceId>|<kind>|<loadId>".
    private func parseServerRegion(_ identifier: String)
        -> (geofenceId: Int, kind: String, loadId: Int)? {
        let parts = identifier.split(separator: "|")
        guard parts.count == 4, parts[0] == "srv",
              let gid = Int(parts[1]), let lid = Int(parts[3]) else { return nil }
        return (gid, String(parts[2]), lid)
    }

    /// POST a resolved transition to the server (ON-SITE / departed flip).
    private func postServerFence(geofenceId: Int, kind: String, loadId: Int,
                                 action: String, at coord: CLLocationCoordinate2D) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let type = kind == "delivery" ? "DELIVERY_FACILITY" : "PICKUP_FACILITY"
        Task {
            try? await EusoTripAPI.shared.trackingGeofences.postGeofenceEvent(
                geofenceId: geofenceId, action: action,
                lat: coord.latitude, lng: coord.longitude, timestamp: ts,
                loadId: loadId, geofenceType: type, facilityName: nil)
        }
    }

    /// Stop monitoring every registered region. Called on sign-out or
    /// when a trip completes and the next load hasn't been bound yet.
    func clearAll() {
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
        monitoredLoadId = nil
        serverRegionIds.removeAll()
    }

    /// Escalate to `authorizedAlways` — required for background-wake
    /// geofences. L13-4: now called from `monitor(load:)` so a screen-locked
    /// arrival still wakes the app to post the ON-SITE flip. No-op if the user
    /// already granted Always or hard-denied; the system shows the prompt at
    /// most once.
    func escalateToAlways() {
        manager.requestAlwaysAuthorization()
    }

    // MARK: Auth helpers

    private func ensureAuthorized() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            phase = .denied
        case .authorizedWhenInUse:
            phase = .authorizedInUse
        case .authorizedAlways:
            phase = .authorizedAlways
        @unknown default:
            break
        }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse: self.phase = .authorizedInUse
            case .authorizedAlways:    self.phase = .authorizedAlways
            case .denied, .restricted: self.phase = .denied
            default:                   self.phase = .unknown
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didEnterRegion region: CLRegion
    ) {
        let id = region.identifier
        let center = (region as? CLCircularRegion)?.center
        let fix = manager.location?.coordinate
        Task { @MainActor in
            if let parsed = self.parseServerRegion(id) {
                // UI auto-advance (same TripEvent as the approach region)…
                self.fireApproach(kind: parsed.kind)
                // …AND the server ON-SITE flip (doc §4). Prefer the live fix,
                // fall back to the fence center (the boundary just crossed).
                if let coord = fix ?? center {
                    self.postServerFence(geofenceId: parsed.geofenceId, kind: parsed.kind,
                                         loadId: parsed.loadId, action: "ENTER", at: coord)
                }
            } else if id.hasPrefix("pickup-") {
                self.controller?.handle(.geofenceApproachingPickup)
            } else if id.hasPrefix("delivery-") {
                self.controller?.handle(.geofenceApproachingDelivery)
            }
            #if DEBUG
            print("[Geofence] enter · \(id)")
            #endif
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didExitRegion region: CLRegion
    ) {
        let id = region.identifier
        let center = (region as? CLCircularRegion)?.center
        let fix = manager.location?.coordinate
        Task { @MainActor in
            // Only server-backed regions carry EXIT (departed → in_transit).
            guard let parsed = self.parseServerRegion(id) else { return }
            if let coord = fix ?? center {
                self.postServerFence(geofenceId: parsed.geofenceId, kind: parsed.kind,
                                     loadId: parsed.loadId, action: "EXIT", at: coord)
            }
            #if DEBUG
            print("[Geofence] exit · \(id)")
            #endif
        }
    }

    /// Fire the UI approach TripEvent for a server fence crossing.
    @MainActor private func fireApproach(kind: String) {
        if kind == "delivery" { controller?.handle(.geofenceApproachingDelivery) }
        else { controller?.handle(.geofenceApproachingPickup) }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: Error
    ) {
        #if DEBUG
        print("[Geofence] fail · \(region?.identifier ?? "<nil>") · \(error.localizedDescription)")
        #endif
    }
}
