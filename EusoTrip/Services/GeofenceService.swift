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
//    • Background geofences require `alwaysAndWhenInUse` + "Location
//      updates" background mode; callers can escalate later via
//      `escalateToAlways()` once we're ready to ship true background
//      auto-arrival. Not enabled in v1.0.
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
    func monitor(load: Load) {
        ensureAuthorized()
        clearAll()
        monitoredLoadId = load.id

        if let p = load.pickupLocation, p.lat != 0 || p.lng != 0 {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng),
                radius: 3200,
                identifier: "pickup-\(load.id)"
            )
            region.notifyOnEntry = true
            region.notifyOnExit  = false
            manager.startMonitoring(for: region)
        }
        if let d = load.deliveryLocation, d.lat != 0 || d.lng != 0 {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: d.lat, longitude: d.lng),
                radius: 3200,
                identifier: "delivery-\(load.id)"
            )
            region.notifyOnEntry = true
            region.notifyOnExit  = false
            manager.startMonitoring(for: region)
        }
        #if DEBUG
        print("[Geofence] monitoring load \(load.id) · pickup + delivery")
        #endif
    }

    /// Stop monitoring every registered region. Called on sign-out or
    /// when a trip completes and the next load hasn't been bound yet.
    func clearAll() {
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
        monitoredLoadId = nil
    }

    /// Escalate to `authorizedAlways` — required for background-wake
    /// geofences. Left for a future pass; v1.0 stays in-use-only.
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
        Task { @MainActor in
            guard let id = region.identifier as String? else { return }
            if id.hasPrefix("pickup-") {
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
        monitoringDidFailFor region: CLRegion?,
        withError error: Error
    ) {
        #if DEBUG
        print("[Geofence] fail · \(region?.identifier ?? "<nil>") · \(error.localizedDescription)")
        #endif
    }
}
