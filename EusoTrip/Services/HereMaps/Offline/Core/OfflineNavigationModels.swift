//
//  OfflineNavigationModels.swift
//  EusoTrip
//
//  Navigation is a separate proven capability from route calculation. An SDK
//  adapter must implement this session contract before advertising guidance.
//

import Foundation

enum OfflineLocationProvenance: String, Codable, Sendable {
    case deviceGNSS
    case deviceFusedLocation
    case externalGNSS
    case simulated
    case unknown
}

struct OfflineDeviceLocationSample: Equatable, Sendable {
    let coordinate: OfflineGeoCoordinate
    let timestamp: Date
    let horizontalAccuracyMeters: Double
    let speedMetersPerSecond: Double?
    let courseDegrees: Double?
    let provenance: OfflineLocationProvenance

    init(
        coordinate: OfflineGeoCoordinate,
        timestamp: Date,
        horizontalAccuracyMeters: Double,
        speedMetersPerSecond: Double?,
        courseDegrees: Double?,
        provenance: OfflineLocationProvenance
    ) throws {
        guard timestamp.timeIntervalSinceReferenceDate.isFinite else {
            throw OfflineMapCoreError.invalidInput("Location timestamp must be finite.")
        }
        guard horizontalAccuracyMeters.isFinite, horizontalAccuracyMeters >= 0 else {
            throw OfflineMapCoreError.invalidInput("Location accuracy must be a finite, non-negative value.")
        }
        if let speedMetersPerSecond {
            guard speedMetersPerSecond.isFinite, speedMetersPerSecond >= 0 else {
                throw OfflineMapCoreError.invalidInput("Location speed must be a finite, non-negative value.")
            }
        }
        if let courseDegrees {
            guard courseDegrees.isFinite, (0 ..< 360).contains(courseDegrees) else {
                throw OfflineMapCoreError.invalidInput("Location course must be between 0 and 360 degrees.")
            }
        }
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.speedMetersPerSecond = speedMetersPerSecond
        self.courseDegrees = courseDegrees
        self.provenance = provenance
    }
}

enum OfflineNavigationCoverage: Equatable, Sendable {
    case verified(OfflineInstalledCoverageEvidence)
    case approachingBoundary(coverage: OfflineInstalledCoverageEvidence, distanceMeters: Int64?)
    case outsideInstalledCoverage(lastCovered: OfflineInstalledCoverageEvidence?)
    case unknown
}

struct OfflineNavigationDeviation: Equatable, Sendable {
    let crossTrackMeters: Double
    let consecutiveSamples: Int
    let observedAt: Date

    init(crossTrackMeters: Double, consecutiveSamples: Int, observedAt: Date) throws {
        guard observedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw OfflineMapCoreError.invalidInput("Route deviation timestamp must be finite.")
        }
        guard crossTrackMeters.isFinite, crossTrackMeters >= 0, consecutiveSamples > 0 else {
            throw OfflineMapCoreError.invalidInput("Route deviation evidence is invalid.")
        }
        self.crossTrackMeters = crossTrackMeters
        self.consecutiveSamples = consecutiveSamples
        self.observedAt = observedAt
    }
}

enum OfflineNavigationFailureCode: String, Codable, Sendable {
    case routeDataUnavailable
    case mapCoverageMissing
    case locationUnavailable
    case locationRejected
    case routeDeviation
    case offlineRerouteFailed
    case unsupportedRouteMode
    case unsupportedRouteProvenance
    case sessionAlreadyActive
    case nativeGuidanceUnavailable
    case nativeGuidanceFailed
}

struct OfflineNavigationFailure: Error, Equatable, Sendable {
    let code: OfflineNavigationFailureCode
    let message: String
    let recovery: String?
    let isRecoverable: Bool
}

enum OfflineNavigationSessionState: Equatable, Sendable {
    case idle
    case starting(routeID: String)
    case navigating(routeID: String, coverage: OfflineNavigationCoverage)
    case paused(routeID: String, reason: String)
    case offRoute(routeID: String, deviation: OfflineNavigationDeviation)
    case rerouting(routeID: String)
    case arrived(routeID: String, arrivedAt: Date)
    case stopped(routeID: String?, stoppedAt: Date)
    case failed(routeID: String?, failure: OfflineNavigationFailure)
}

struct OfflineNavigationManeuverEvent: Equatable, Sendable {
    let sequence: Int
    let instruction: String
    let distanceMeters: Int64
    let coordinate: OfflineGeoCoordinate?

    init(
        sequence: Int,
        instruction: String,
        distanceMeters: Int64,
        coordinate: OfflineGeoCoordinate?
    ) throws {
        guard sequence >= 0, distanceMeters >= 0 else {
            throw OfflineMapCoreError.invalidInput("Navigation maneuver sequence and distance cannot be negative.")
        }
        guard !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OfflineMapCoreError.invalidInput("Navigation instruction cannot be empty.")
        }
        self.sequence = sequence
        self.instruction = instruction
        self.distanceMeters = distanceMeters
        self.coordinate = coordinate
    }
}

/// A HERE reroute may replace native guidance geometry without changing the
/// app-owned route identifier. This value can be constructed only when the
/// replacement preserves that identifier and mode and carries the exact
/// signed installed-region evidence admitted for the new corridor.
struct OfflineNavigationRouteReplacement: Equatable, Sendable {
    let replacingRouteID: String
    let replacingMode: OfflineRouteMode
    let route: OfflineLocalRoute

    init(
        route: OfflineLocalRoute,
        replacingRouteID: String,
        expectedMode: OfflineRouteMode,
        admittedCoverage: OfflineInstalledCoverageEvidence
    ) throws {
        let routeID = replacingRouteID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !routeID.isEmpty,
              route.id == routeID,
              expectedMode.supportsHEREOfflineCalculation,
              route.mode == expectedMode,
              route.provenance == .hereOfflineLocal,
              route.coverage == admittedCoverage else {
            throw OfflineMapCoreError.invalidInput(
                "A navigation reroute must preserve route identity and mode with newly admitted signed coverage."
            )
        }
        self.replacingRouteID = routeID
        replacingMode = expectedMode
        self.route = route
    }
}

/// Composition-owned route authority. Declarative hosts may continue to hold
/// the pre-reroute DTO, so an accepted native replacement remains authoritative
/// for the same route ID and for every active navigation state.
struct OfflineNavigationRouteProjectionAuthority: Equatable, Sendable {
    private(set) var route: OfflineLocalRoute?

    mutating func begin(_ route: OfflineLocalRoute) {
        self.route = route
    }

    @discardableResult
    mutating func accept(_ replacement: OfflineNavigationRouteReplacement) -> Bool {
        guard let current = route,
              current.id == replacement.replacingRouteID,
              current.mode == replacement.replacingMode else {
            return false
        }
        route = replacement.route
        return true
    }

    func resolveHostRoute(
        _ proposedRoute: OfflineLocalRoute?,
        navigationIsActive: Bool
    ) -> OfflineLocalRoute? {
        guard let route else { return proposedRoute }
        if proposedRoute?.id == route.id || navigationIsActive {
            return route
        }
        return proposedRoute
    }

    mutating func clear() {
        route = nil
    }
}

enum OfflineNavigationEvent: Equatable, Sendable {
    case stateChanged(OfflineNavigationSessionState)
    case maneuver(OfflineNavigationManeuverEvent)
    case coverageChanged(OfflineNavigationCoverage)
    /// Emitted only after HERE's replacement geometry has passed signed
    /// installed-corridor admission and the SDK route has been mapped back to
    /// the same typed local-route authority.
    case routeReplaced(OfflineNavigationRouteReplacement)
    /// Typed rejection for asynchronous native evidence that cannot throw back
    /// to the location producer. Messages are fixed product copy and never
    /// interpolate provider payloads or timestamps.
    case inputRejected(OfflineNavigationFailure)
    case deviationDetected(OfflineNavigationDeviation)
    case rerouteFailed(OfflineNavigationFailure)
    case arrived(Date)
}

enum OfflineNavigationAudioInterruption: Equatable, Sendable {
    case began
    case ended(shouldResume: Bool)
}

typealias OfflineNavigationEventHandler = @Sendable (OfflineNavigationEvent) -> Void

protocol OfflineNavigationSessionProviding: Sendable {
    func currentState() async -> OfflineNavigationSessionState

    /// The route must be road/truck and carry `.hereOfflineLocal` provenance.
    /// Rail and vessel execution remains tied to the cached server-canonical
    /// package and cannot be promoted into HERE local guidance.
    func start(
        route: OfflineLocalRoute,
        eventHandler: @escaping OfflineNavigationEventHandler
    ) async throws

    func feed(location: OfflineDeviceLocationSample) async throws
    func handleAudioInterruption(_ interruption: OfflineNavigationAudioInterruption) async
    func stop() async
}
