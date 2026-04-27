//
//  DriverLocationResolver.swift
//  EusoTrip — One-shot + cached CoreLocation fix for the
//  "what's near me right now?" glance surfaces (fuel prices,
//  parking, EV charging, safety cameras, etc.).
//
//  Why another location helper: WeatherService owns its own
//  CLLocationManager wrapped around WeatherKit, but it doesn't
//  expose the raw fix. Adding a second manager on every new
//  feature (fuel, parking, cameras) would mean 5+ managers
//  competing for delegate callbacks + 5 "Allow Location" prompts
//  the first time the driver lands on Home. This resolver is a
//  single shared instance every glance widget taps into. It:
//
//    • Requests a one-shot fix with a 4-second timeout so a
//      stalled CoreLocation call (common in the simulator) can't
//      hang a pull-to-refresh.
//    • Caches the last successful fix for 90 seconds so repeated
//      `currentCoordinate()` calls from different widgets on
//      the same Home paint don't re-burn the radio.
//    • Exposes the authorization status so callers can decide
//      whether to render an "Enable location" CTA vs. silently
//      hide the widget (matching the doctrine we already apply
//      to WeatherService).
//
//  Powered by ESANG AI™.
//

import Foundation
import CoreLocation

@MainActor
final class DriverLocationResolver: NSObject, ObservableObject {

    static let shared = DriverLocationResolver()

    @Published private(set) var lastCoordinate: CLLocationCoordinate2D?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager: CLLocationManager
    /// Active continuations awaiting the next `didUpdateLocations`.
    /// Stored as a list so multiple concurrent calls to
    /// `currentCoordinate()` all resume off a single physical fix.
    private var pending: [CheckedContinuation<CLLocationCoordinate2D?, Never>] = []
    /// Timestamp of the most recent successful fix. Used to decide
    /// whether `currentCoordinate()` can return the cache.
    private var lastFixAt: Date?
    /// How long a cached fix is considered fresh. 90s matches the
    /// "reasonable driving glance" window — at 60 mph a driver has
    /// moved ~1.5 mi, which is inside the default 40 km fuel /
    /// parking query radius so the nearby set is still accurate.
    private let cacheTTL: TimeInterval = 90
    /// Hard timeout on a single fix attempt. Keeps the UI from
    /// stalling on a simulator that never delivers a CoreLocation
    /// callback.
    private let fixTimeout: TimeInterval = 4

    override init() {
        let m = CLLocationManager()
        m.desiredAccuracy = kCLLocationAccuracyKilometer
        self.manager = m
        self.authorizationStatus = m.authorizationStatus
        super.init()
        m.delegate = self
    }

    /// Returns the driver's current coordinate, serving the cache
    /// when fresh and triggering a one-shot fix otherwise. Returns
    /// nil when authorization is denied / restricted or the fix
    /// times out — callers render their "Enable location" CTA or
    /// silently omit their widget in that case.
    func currentCoordinate() async -> CLLocationCoordinate2D? {
        // Serve cache while fresh.
        if let c = lastCoordinate,
           let at = lastFixAt,
           Date().timeIntervalSince(at) < cacheTTL {
            return c
        }

        // Fast-path: denied / restricted → never fire a prompt,
        // never wait for a callback that won't come.
        switch authorizationStatus {
        case .denied, .restricted:
            return nil
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            break
        @unknown default:
            break
        }

        // Await a live fix with a hard timeout so a stuck
        // CoreLocation can't hang the widget forever.
        return await withCheckedContinuation { (cont: CheckedContinuation<CLLocationCoordinate2D?, Never>) in
            pending.append(cont)
            manager.requestLocation()
            // Timeout watchdog.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(self?.fixTimeout ?? 4) * NSEC_PER_SEC)
                self?.drainPending(with: self?.lastCoordinate)
            }
        }
    }

    private func drainPending(with coord: CLLocationCoordinate2D?) {
        guard !pending.isEmpty else { return }
        let waiters = pending
        pending.removeAll()
        for w in waiters {
            w.resume(returning: coord)
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension DriverLocationResolver: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        Task { @MainActor in
            self.authorizationStatus = status
            // If authorization just flipped to denied, drain any
            // in-flight waiters with nil so the UI can move on.
            if status == .denied || status == .restricted {
                self.drainPending(with: nil)
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let loc = locations.last else { return }
        let coord = loc.coordinate
        Task { @MainActor in
            self.lastCoordinate = coord
            self.lastFixAt = Date()
            self.drainPending(with: coord)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            // Drain pending with whatever cache we have — if nothing,
            // waiters see nil and the widget cleanly hides itself.
            self.drainPending(with: self.lastCoordinate)
        }
    }
}
