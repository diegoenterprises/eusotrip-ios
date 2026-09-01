//
//  HereNavigationLocationSource.swift
//  EusoTrip
//
//  Session-owned continuous CoreLocation lifecycle for native guidance. This
//  deliberately does not reuse the app's kilometer-accuracy glance resolver
//  or depend on whether backend GPS telemetry happens to be active.
//

import CoreLocation
import Foundation

@MainActor
final class HereNavigationLocationSource: NSObject, CLLocationManagerDelegate {
    typealias LocationHandler = @MainActor (OfflineProductionLocationFix) -> Void
    typealias FailureHandler = @MainActor (OfflineNavigationFailure) -> Void

    private let manager: CLLocationManager
    private var locationHandler: LocationHandler?
    private var failureHandler: FailureHandler?
    private(set) var isRunning = false

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        #if os(iOS)
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        #endif
    }

    func start(
        onLocation: @escaping LocationHandler,
        onFailure: @escaping FailureHandler
    ) throws {
        guard !isRunning else { return }
        guard CLLocationManager.locationServicesEnabled() else {
            throw Self.failure(
                message: "Location Services are disabled for offline guidance.",
                recovery: "Enable Location Services and Precise Location before departure."
            )
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            throw Self.failure(
                message: "Offline guidance is waiting for location permission.",
                recovery: "Approve Precise Location, then start guidance again."
            )
        case .denied, .restricted:
            throw Self.failure(
                message: "Location permission is unavailable for offline guidance.",
                recovery: "Allow Precise Location for EusoTrip in Settings before departure."
            )
        case .authorizedAlways, .authorizedWhenInUse:
            break
        @unknown default:
            throw Self.failure(
                message: "Location authorization could not be verified for offline guidance.",
                recovery: "Review EusoTrip location permission in Settings before departure."
            )
        }
        guard manager.accuracyAuthorization == .fullAccuracy else {
            throw Self.failure(
                message: "Precise Location is disabled for offline guidance.",
                recovery: "Enable Precise Location for EusoTrip before departure."
            )
        }
        locationHandler = onLocation
        failureHandler = onFailure
        isRunning = true
        manager.startUpdatingLocation()
    }

    func stop() {
        guard isRunning || locationHandler != nil || failureHandler != nil else {
            return
        }
        manager.stopUpdatingLocation()
        isRunning = false
        locationHandler = nil
        failureHandler = nil
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            guard let self, self.isRunning else { return }
            let source = location.sourceInformation
            let provenance: OfflineLocationProvenance
            if source?.isSimulatedBySoftware == true {
                provenance = .simulated
            } else if source?.isProducedByAccessory == true {
                provenance = .externalGNSS
            } else {
                // CoreLocation does not expose whether an individual fused
                // fix came solely from satellite hardware. Preserve that
                // distinction until airplane-mode device evidence proves it.
                provenance = .deviceFusedLocation
            }
            self.locationHandler?(
                OfflineProductionLocationFix(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    timestamp: location.timestamp,
                    horizontalAccuracyMeters: location.horizontalAccuracy,
                    speedMetersPerSecond: location.speed >= 0 ? location.speed : nil,
                    courseDegrees: location.course >= 0 ? location.course : nil,
                    provenance: provenance
                )
            )
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.isRunning else { return }
            let coreLocationError = error as? CLError
            if coreLocationError?.code == .locationUnknown {
                return
            }
            let failure = Self.failure(
                message: coreLocationError?.code == .denied
                    ? "Location permission was withdrawn during offline guidance."
                    : "Continuous device location failed during offline guidance.",
                recovery: coreLocationError?.code == .denied
                    ? "Restore Precise Location permission before resuming guidance."
                    : "Wait for a clear GNSS view and retry from a safe stop."
            )
            self.failureHandler?(failure)
            self.stop()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(
        _: CLLocationManager
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.isRunning else { return }
            switch self.manager.authorizationStatus {
            case .denied, .restricted:
                self.failureHandler?(
                    Self.failure(
                        message: "Location permission was withdrawn during offline guidance.",
                        recovery: "Restore Precise Location permission before resuming guidance."
                    )
                )
                self.stop()
            case .authorizedAlways, .authorizedWhenInUse:
                if self.manager.accuracyAuthorization != .fullAccuracy {
                    self.failureHandler?(
                        Self.failure(
                            message: "Precise Location was disabled during offline guidance.",
                            recovery: "Restore Precise Location before resuming guidance."
                        )
                    )
                    self.stop()
                }
            case .notDetermined:
                break
            @unknown default:
                self.failureHandler?(
                    Self.failure(
                        message: "Location authorization became unknown during offline guidance.",
                        recovery: "Review EusoTrip location permission before resuming guidance."
                    )
                )
                self.stop()
            }
        }
    }

    private static func failure(
        message: String,
        recovery: String
    ) -> OfflineNavigationFailure {
        OfflineNavigationFailure(
            code: .locationRejected,
            message: message,
            recovery: recovery,
            isRecoverable: true
        )
    }
}
