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
import UIKit

@MainActor
final class DriverGPSPushService: NSObject, ObservableObject,
                                  CLLocationManagerDelegate {

    static let shared = DriverGPSPushService()

    @Published private(set) var isStreaming: Bool = false
    @Published private(set) var lastPushAt: Date? = nil
    @Published private(set) var lastError: String? = nil

    private let manager = CLLocationManager()
    private var activeLoadId: Int?
    private var isRadioSilenceSuspended = false
    private var locationPushTask: Task<Void, Never>?
    private var crumbFlushTask: Task<Void, Never>?
    private var needsFinalCrumbFlush = false
    private var pendingFinalCrumbLoadId: Int?

    // MARK: - Breadcrumb trail (L13-6)
    //
    // `drivers.updateLocation` (above) only keeps the LATEST position for the
    // live pin. The persisted TRAIL — behind replay / mileage / deviation /
    // detention proof + The Haul territory coverage — comes from batching
    // fixes to the existing `location.telemetry.locationBatch`. We buffer
    // every accepted fix (one per 50 m via `distanceFilter`) and flush ≤200 at
    // a time on 20 buffered / 60 s / stop(). The 15 s updateLocation loop is
    // untouched. Gated by the `breadcrumbsEnabled` flag (default on;
    // kill-switch — the buffer simply never flushes when off).

    /// Raw buffered fix; converted to the wire shape at flush time so each
    /// consumer (locationBatch = mph, Haul coverage = kph) gets its own unit.
    private struct Crumb {
        let loadId: Int?
        let lat: Double, lng: Double
        let timestamp: String
        let speedMps: Double?      // raw m/s (nil when CoreLocation reports <0)
        let heading: Double?
        let accuracy: Double?
        let altitude: Double?
        let batteryPct: Double?
        let isCharging: Bool?
    }
    private var crumbBuffer: [Crumb] = []
    private var lastCrumbFlushAt: Date = .distantPast
    private let crumbIso = ISO8601DateFormatter()

    private var breadcrumbsEnabled: Bool {
        (UserDefaults.standard.object(forKey: "breadcrumbsEnabled") as? Bool) ?? true
    }

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
        // Real battery telemetry for the breadcrumb trail (nil otherwise).
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    // MARK: - Public lifecycle

    func start(loadId: Int) {
        guard activeLoadId != loadId else { return }
        activeLoadId = loadId
        guard !isRadioSilenceSuspended else {
            isStreaming = false
            return
        }

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
        if !crumbBuffer.isEmpty || crumbFlushTask != nil {
            pendingFinalCrumbLoadId = activeLoadId
            if crumbFlushTask != nil || isRadioSilenceSuspended {
                needsFinalCrumbFlush = true
            }
        }
        flushCrumbs()                 // persist whatever's buffered before teardown
        manager.stopUpdatingLocation()
        locationPushTask?.cancel()
        activeLoadId = nil
        isStreaming = false
    }

    /// Preserve the desired active load and buffered breadcrumbs while
    /// synchronously stopping every app-owned location upload path.
    func suspendForAppRadioSilence() {
        guard !isRadioSilenceSuspended else { return }
        isRadioSilenceSuspended = true
        manager.stopUpdatingLocation()
        isStreaming = false
        locationPushTask?.cancel()
        crumbFlushTask?.cancel()
    }

    /// Resume only when `start(loadId:)` still has a desired load. Buffered
    /// crumbs remain local during the lease and flush after the transport gate
    /// has reopened.
    func resumeAfterAppRadioSilence() {
        guard isRadioSilenceSuspended else { return }
        isRadioSilenceSuspended = false
        if needsFinalCrumbFlush {
            needsFinalCrumbFlush = false
            flushCrumbs()
        }
        guard activeLoadId != nil else { return }

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            isStreaming = true
            lastError = nil
            flushCrumbs()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            isStreaming = false
        @unknown default:
            isStreaming = false
        }
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
            // L13-2: mirror EVERY accepted fix into DriverLocationResolver
            // BEFORE the 15 s push throttle — the turn-by-turn navigator
            // consumes `$lastLocation` and needs the full 50 m-filtered
            // cadence for maneuver advance / voice gates / deviation.
            DriverLocationResolver.shared.ingest(externalFix: fix)
            self?.maybePush(fix: fix)
            self?.bufferCrumb(fix)
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
                if self.activeLoadId != nil, !self.isRadioSilenceSuspended {
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
        // A CoreLocation delegate callback may already be queued on MainActor
        // when stop() clears the load. Never let that delayed callback create a
        // new upload after the load lifecycle has ended.
        guard activeLoadId != nil,
              !isRadioSilenceSuspended,
              locationPushTask == nil else { return }
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

        // L13-10: carry heading + speed on the live push too (the server
        // consumes both for the directional pin + live-ping payload). speed
        // in mph to match the breadcrumb trail unit.
        let heading: Double? = fix.course >= 0 ? fix.course : nil
        let speedMph: Double? = fix.speed >= 0 ? fix.speed * 2.236_94 : nil

        locationPushTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, !self.isRadioSilenceSuspended else { return }
            defer { self.locationPushTask = nil }
            do {
                struct UpdateLocationInput: Encodable {
                    let lat: Double
                    let lng: Double
                    let city: String?
                    let state: String?
                    let heading: Double?
                    let speed: Double?
                }
                struct Ack: Decodable { let success: Bool? }
                let _: Ack = try await EusoTripAPI.shared.mutation(
                    "drivers.updateLocation",
                    input: UpdateLocationInput(lat: lat, lng: lng, city: nil, state: nil,
                                               heading: heading, speed: speedMph)
                )
                guard !Task.isCancelled, !self.isRadioSilenceSuspended else { return }
                self.lastPushAt = Date()
            } catch is CancellationError {
                return
            } catch is AppRadioSilenceTransportError {
                return
            } catch {
                self.lastError = "GPS push failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Breadcrumb trail

    /// Buffer one accepted fix (called from `didUpdateLocations` after the
    /// stale-fix guard). Flushes when 20 are buffered or 60 s have elapsed.
    @MainActor
    private func bufferCrumb(_ fix: CLLocation) {
        // Match the live-push boundary above: a delayed callback after stop()
        // has no load authority and must not enter the durable breadcrumb trail.
        guard activeLoadId != nil,
              breadcrumbsEnabled,
              !isRadioSilenceSuspended else { return }
        let battery = UIDevice.current.isBatteryMonitoringEnabled && UIDevice.current.batteryLevel >= 0
            ? Double(UIDevice.current.batteryLevel * 100) : nil
        let charging: Bool? = UIDevice.current.isBatteryMonitoringEnabled
            ? (UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full)
            : nil
        crumbBuffer.append(Crumb(
            loadId: activeLoadId,
            lat: fix.coordinate.latitude,
            lng: fix.coordinate.longitude,
            timestamp: crumbIso.string(from: fix.timestamp),
            speedMps: fix.speed >= 0 ? fix.speed : nil,
            heading: fix.course >= 0 ? fix.course : nil,
            accuracy: fix.horizontalAccuracy >= 0 ? fix.horizontalAccuracy : nil,
            altitude: fix.verticalAccuracy >= 0 ? fix.altitude : nil,
            batteryPct: battery,
            isCharging: charging))
        if crumbBuffer.count >= 20 || Date().timeIntervalSince(lastCrumbFlushAt) >= 60 {
            flushCrumbs()
        }
    }

    /// Flush ≤200 buffered fixes to `location.telemetry.locationBatch` and feed
    /// the same points to `HereHaulBridge.recordCoverage` (its first real
    /// caller — lights up `hereMaps.locationAnalytics` territory events).
    ///
    /// Cap raised 25→200 (adversarial-verify 2026-07-09): the server schema
    /// allows `.max(200)` and the buffer is capped at 200, so any backlog
    /// drains in ONE request — structurally avoiding the server's 2 s
    /// per-driver rate limiter during catch-up. A rate-limited ack now
    /// THROWS from `locationBatch` (the server persisted nothing), so the
    /// catch re-buffers the batch AND skips `recordCoverage` — Haul territory
    /// / XP is only ever credited for confirmed-persisted points. On failure
    /// the batch is re-buffered for the next flush (buffer capped at 200 so a
    /// long offline stretch never grows unbounded).
    @MainActor
    private func flushCrumbs() {
        guard breadcrumbsEnabled,
              !isRadioSilenceSuspended,
              crumbFlushTask == nil,
              !crumbBuffer.isEmpty else { return }
        guard let firstCrumb = crumbBuffer.first else { return }
        let batch = Array(
            crumbBuffer
                .prefix(200)
                .prefix { $0.loadId == firstCrumb.loadId }
        )
        crumbBuffer.removeFirst(batch.count)
        lastCrumbFlushAt = Date()
        // Load authority is captured with every crumb. A stopped load's delayed
        // evidence therefore cannot fall through to a newer `activeLoadId`, and
        // mixed-load buffers drain as separate ordered requests.
        let loadId = firstCrumb.loadId

        let points = batch.map { c in
            EusoTripAPI.LocationBatchPoint(
                lat: c.lat, lng: c.lng, timestamp: c.timestamp,
                speed: c.speedMps.map { $0 * 2.236_94 },   // m/s → mph
                heading: c.heading, accuracy: c.accuracy, altitude: c.altitude,
                batteryLevel: c.batteryPct, isCharging: c.isCharging)
        }
        let coverage = batch.map { c in
            HereMapsAPI.Breadcrumb(
                lat: c.lat, lng: c.lng, capturedAt: c.timestamp,
                speedKph: c.speedMps.map { $0 * 3.6 })       // m/s → kph
        }

        crumbFlushTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var retryAfterPolicyCancellation = false
            defer {
                self.crumbFlushTask = nil
                if self.needsFinalCrumbFlush, !self.isRadioSilenceSuspended {
                    self.needsFinalCrumbFlush = false
                    self.flushCrumbs()
                } else if retryAfterPolicyCancellation, !self.isRadioSilenceSuspended {
                    self.flushCrumbs()
                }
            }
            do {
                _ = try await EusoTripAPI.shared.locationBatch(locations: points, loadId: loadId)
                guard !Task.isCancelled, !self.isRadioSilenceSuspended else {
                    throw CancellationError()
                }
                await HereHaulBridge.shared.recordCoverage(breadcrumbs: coverage)
                guard !Task.isCancelled, !self.isRadioSilenceSuspended else {
                    throw CancellationError()
                }
                if let pendingLoadId = self.pendingFinalCrumbLoadId,
                   pendingLoadId == loadId {
                    self.pendingFinalCrumbLoadId = nil
                }
            } catch {
                // Re-buffer for retry; cap at 200. The trim drops the OLDEST
                // crumbs (front of the array) so the persisted trail always
                // keeps the most recent ~10 km up to reconnection — the
                // operationally relevant segment for detention/mileage proof.
                self.crumbBuffer.insert(contentsOf: batch, at: 0)
                if self.crumbBuffer.count > 200 {
                    self.crumbBuffer.removeFirst(self.crumbBuffer.count - 200)
                }
                if !(error is CancellationError), !(error is AppRadioSilenceTransportError) {
                    self.lastError = "locationBatch: \(error.localizedDescription)"
                } else {
                    retryAfterPolicyCancellation = true
                }
            }
        }
    }
}
