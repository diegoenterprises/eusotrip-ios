//
//  DriverGPSPushService.swift
//  EusoTrip — pushes driver GPS to `drivers.updateLocation` while a
//  trip is active so shippers, dispatch, and Catalyst all see a
//  live truck pin without waiting on a coarse geofence enter/exit.
//
//  Why this exists
//  ───────────────
//  Audit 2026-05-10: iOS had `GeofenceService` (region-enter events
//  fired to TripController) and `DriverLocationResolver` (one-shot
//  fixes for glance widgets), but NO continuous push of the driver's
//  GPS to the backend. Result: shipper LifecycleMapCard's truck pin
//  only updated on coarse geofence transitions (~2 mi radius) — for
//  hours of in-transit time, the shipper saw a stale pin.
//
//  This service closes that gap. It uses a single `CLLocationManager`
//  configured for `kCLLocationAccuracyBest` with a 50-meter distance
//  filter. Each `didUpdateLocations` callback POSTs to
//  `drivers.updateLocation` (already on the server, idempotent). The
//  server stamps `users.currentLocation` + `users.lastGPSUpdate`,
//  which downstream surfaces (shipper LifecycleSnapshot, Catalyst
//  fleet board, ESANG live dashboard) read via existing queries.
//
//  Lifecycle
//  ─────────
//  • `start(loadId:)` → request `whenInUse` if needed, begin updates
//  • `stop()`        → end updates, drop the manager's delegate
//
//  ContentView's onChange(of: trip.currentLoad?.id) drives both calls
//  — same hook that wires `GeofenceService.monitor(load:)`. So the
//  push pipeline starts the moment a load goes active and stops the
//  moment the trip closes (or the user signs out).
//
//  Battery posture
//  ───────────────
//  • `desiredAccuracy = kCLLocationAccuracyBest` — required for the
//    truck pin to be useful at city-block scale (the looser
//    `nearestTenMeters` reads as "somewhere in this 1-block area"
//    on iPhone 12 and below). Battery cost is acceptable while a
//    trip is active; deactivates the moment trip ends.
//  • `distanceFilter = 50` — only pushes when the driver actually
//    moves 50 m. At rest in a yard, the manager goes quiet.
//  • `pausesLocationUpdatesAutomatically = false` — iOS's auto-pause
//    is too aggressive for our use case (it can suspend updates for
//    minutes during a HOS break, leaving the shipper pin stale).
//
//  Powered by ESANG AI™.
//

import Foundation
import CoreLocation

@MainActor
final class DriverGPSPushService: NSObject, ObservableObject,
                                  CLLocationManagerDelegate {

    static let shared = DriverGPSPushService()

    @Published private(set) var isStreaming: Bool = false
    @Published private(set) var lastPushAt: Date? = nil
    @Published private(set) var lastError: String? = nil

    private let manager = CLLocationManager()
    private var activeLoadId: Int?

    /// Minimum interval between two backend POSTs even if the driver
    /// moves rapidly. CoreLocation can fire `didUpdateLocations`
    /// several times per second on a moving truck; 15 s is the
    /// shipper-side polling cadence so finer pushes don't help — they
    /// just burn the battery + the tRPC call rate.
    private let minPushInterval: TimeInterval = 15

    private var lastPushedAt: Date = .distantPast
    private var lastPushedCoord: CLLocationCoordinate2D?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter  = 50
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .automotiveNavigation
    }

    // MARK: - Public lifecycle

    func start(loadId: Int) {
        guard activeLoadId != loadId else { return }
        activeLoadId = loadId

        switch manager.authorizationStatus {
        case .notDetermined:
            // Pop the standard "Allow While Using" sheet. If the
            // driver picks "Don't Allow" the service silently goes
            // quiet — matches the doctrine for WeatherService /
            // GeofenceService / DriverLocationResolver.
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            isStreaming = false
            lastError = "Location permission denied — shipper truck pin will not update."
            return
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            break
        }

        manager.startUpdatingLocation()
        isStreaming = true
        lastError = nil
    }

    func stop() {
        manager.stopUpdatingLocation()
        activeLoadId = nil
        isStreaming = false
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last else { return }
        // Drop very old fixes — CoreLocation occasionally replays a
        // cached fix on first start, which would push a stale point
        // that's seconds-to-minutes behind the truck.
        let age = -fix.timestamp.timeIntervalSinceNow
        guard age < 60 else { return }
        Task { @MainActor [weak self] in
            self?.maybePush(fix: fix)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.lastError = error.localizedDescription
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                if self.activeLoadId != nil {
                    manager.startUpdatingLocation()
                    self.isStreaming = true
                    self.lastError = nil
                }
            case .denied, .restricted:
                self.isStreaming = false
                self.lastError = "Location permission denied."
            default:
                break
            }
        }
    }

    // MARK: - Push

    @MainActor
    private func maybePush(fix: CLLocation) {
        let now = Date()
        if now.timeIntervalSince(lastPushedAt) < minPushInterval { return }
        // Skip if the driver hasn't moved meaningfully since the last
        // push (CoreLocation can fire fixes during stationary GPS
        // jitter). 25 m is half the distanceFilter so the next real
        // 50-m move always crosses the threshold.
        if let prev = lastPushedCoord {
            let prevLoc = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
            if fix.distance(from: prevLoc) < 25 { return }
        }

        lastPushedAt = now
        lastPushedCoord = fix.coordinate

        let lat = fix.coordinate.latitude
        let lng = fix.coordinate.longitude

        Task {
            do {
                struct UpdateLocationInput: Encodable {
                    let lat: Double
                    let lng: Double
                    let city: String?
                    let state: String?
                }
                struct Ack: Decodable { let success: Bool? }
                let _: Ack = try await EusoTripAPI.shared.mutation(
                    "drivers.updateLocation",
                    input: UpdateLocationInput(lat: lat, lng: lng, city: nil, state: nil)
                )
                await MainActor.run { self.lastPushAt = Date() }
            } catch {
                await MainActor.run {
                    self.lastError = "GPS push failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
