//
//  OfflineMapProductionComposition.swift
//  EusoTrip
//
//  App-owned wiring for HERE Navigate offline maps. Road and truck may use
//  verified local HERE coverage; Rail and Vessel remain bound to signed,
//  server-canonical route.plan packages.
//

import Combine
import CoreLocation
import Foundation

@MainActor
final class OfflineMapProductionComposition: ObservableObject {
    typealias SearchOperation = (
        _ text: String,
        _ center: OfflineGeoCoordinate,
        _ maximumResultCount: Int
    ) async throws -> OfflineSearchResponse

    typealias RouteOperation = (
        _ waypoints: [OfflineRouteWaypoint],
        _ mode: OfflineRouteMode,
        _ truckConstraints: OfflineTruckConstraints?,
        _ departureTime: Date?
    ) async throws -> OfflineRouteResponse

    typealias StartNavigationOperation = (
        _ route: OfflineLocalRoute,
        _ eventHandler: @escaping OfflineNavigationEventHandler
    ) async throws -> Void

    typealias FeedLocationOperation = (
        _ fix: OfflineProductionLocationFix
    ) async throws -> Void

    typealias StopNavigationOperation = () async -> Void

    typealias CanonicalRouteIngestOperation = (
        _ encodedEnvelope: Data,
        _ expectedScope: CanonicalRouteScope,
        _ receivedAt: Date
    ) async throws -> CanonicalRoutePackage

    typealias CanonicalRoutePurgeOperation = () async throws -> Void

    private static let principalMarkerKey = "offlineMaps.canonicalRoutePrincipal.v1"
    private static let canonicalRouteDirectoryName = "canonical-routes-v1"

    private(set) static var shared: OfflineMapProductionComposition?
    private(set) static var installationFailure: String?

    let owner: OfflineMapCompositionOwner
    let mapSurface: HereNavigateOfflineMapSurface

    @Published private(set) var navigationState: OfflineNavigationSessionState = .idle
    @Published private(set) var navigationCoverage: OfflineNavigationCoverage = .unknown
    @Published private(set) var lastNavigationFailure: OfflineNavigationFailure?
    @Published private(set) var canonicalRouteTrustAvailable: Bool
    @Published private(set) var canonicalRouteFailure: String?

    private let searchOperation: SearchOperation
    private let routeOperation: RouteOperation
    private let startNavigationOperation: StartNavigationOperation
    private let feedLocationOperation: FeedLocationOperation
    private let stopNavigationOperation: StopNavigationOperation
    private let canonicalRouteStore: CanonicalRoutePackageStore?
    private let canonicalRouteIngestOperation: CanonicalRouteIngestOperation
    private let canonicalRoutePurgeOperation: CanonicalRoutePurgeOperation
    private let principalDefaults: UserDefaults
    private var locationCancellable: AnyCancellable?

    private init(
        owner: OfflineMapCompositionOwner,
        mapSurface: HereNavigateOfflineMapSurface,
        searchOperation: @escaping SearchOperation,
        routeOperation: @escaping RouteOperation,
        startNavigationOperation: @escaping StartNavigationOperation,
        feedLocationOperation: @escaping FeedLocationOperation,
        stopNavigationOperation: @escaping StopNavigationOperation,
        canonicalRouteStore: CanonicalRoutePackageStore?,
        canonicalRouteIngestOperation: @escaping CanonicalRouteIngestOperation,
        canonicalRoutePurgeOperation: @escaping CanonicalRoutePurgeOperation,
        canonicalRouteFailure: String?,
        principalDefaults: UserDefaults
    ) {
        self.owner = owner
        self.mapSurface = mapSurface
        self.searchOperation = searchOperation
        self.routeOperation = routeOperation
        self.startNavigationOperation = startNavigationOperation
        self.feedLocationOperation = feedLocationOperation
        self.stopNavigationOperation = stopNavigationOperation
        self.canonicalRouteStore = canonicalRouteStore
        self.canonicalRouteIngestOperation = canonicalRouteIngestOperation
        self.canonicalRoutePurgeOperation = canonicalRoutePurgeOperation
        self.canonicalRouteFailure = canonicalRouteFailure
        canonicalRouteTrustAvailable = canonicalRouteStore != nil
        self.principalDefaults = principalDefaults
    }

    /// Installs exactly one process-wide owner before any route or Settings
    /// surface can request HERE state. Missing signing trust blocks only the
    /// Rail/Vessel cache; it never weakens road/truck or fabricates authority.
    static func install(
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        principalDefaults: UserDefaults = .standard
    ) {
        guard shared == nil else { return }

        do {
            let storagePolicy = try OfflineMapStoragePolicy(
                minimumPostOperationFreeBytes: 3 * 1_024 * 1_024 * 1_024,
                updateStagingBytesPerInstalledByte: nil
            )
            let owner = OfflineMapComposition.makeOwner(
                storagePolicy: storagePolicy,
                connectivityPolicy: .radioSilent,
                requiredCapabilities: .fullRoadFreightParity
            )
            let mapSurface = HereNavigateOfflineMapSurface()
            let voicePolicy = try HereNavigationVoicePolicy(
                requiredLocaleIdentifier: "en-US"
            )
            let navigationSession = OfflineMapComposition.makeNavigationSession(
                locationPolicy: .production,
                voicePolicy: voicePolicy
            )
            let engine = HereNavigateOfflineEngine.shared

            let searchOperation: SearchOperation = { text, center, maximumResultCount in
                let request = try OfflineSearchRequest(
                    text: text,
                    center: center,
                    maximumResultCount: maximumResultCount
                )
                return try await engine.searchOffline(request)
            }
            let routeOperation: RouteOperation = {
                waypoints, mode, truckConstraints, departureTime in
                let request = try OfflineRouteRequest(
                    waypoints: waypoints,
                    mode: mode,
                    truckConstraints: truckConstraints,
                    departureTime: departureTime
                )
                return try await engine.calculateOfflineRoute(request)
            }
            let startNavigationOperation: StartNavigationOperation = { route, downstream in
                try await navigationSession.start(route: route) { event in
                    switch event {
                    case .coverageChanged(let coverage):
                        if case .outsideInstalledCoverage(let lastCovered) = coverage {
                            downstream(
                                .coverageChanged(
                                    .outsideInstalledCoverage(lastCovered: lastCovered)
                                )
                            )
                        } else {
                            downstream(.coverageChanged(coverage))
                        }
                    default:
                        downstream(event)
                    }
                }
            }
            let feedLocationOperation: FeedLocationOperation = { fix in
                let coordinate = try OfflineGeoCoordinate(
                    latitude: fix.latitude,
                    longitude: fix.longitude
                )
                let sample = try OfflineDeviceLocationSample(
                    coordinate: coordinate,
                    timestamp: fix.timestamp,
                    horizontalAccuracyMeters: fix.horizontalAccuracyMeters,
                    speedMetersPerSecond: fix.speedMetersPerSecond,
                    courseDegrees: fix.courseDegrees,
                    provenance: fix.provenance
                )
                try await navigationSession.feed(location: sample)
            }
            let stopNavigationOperation: StopNavigationOperation = {
                await navigationSession.stop()
            }

            let canonicalRoot = try canonicalRouteRoot(
                fileManager: fileManager
            )
            var canonicalRouteStore: CanonicalRoutePackageStore?
            var canonicalRouteFailure: String?
            do {
                if let trust = try OfflineCanonicalRouteTrustConfiguration.load(
                    bundle: bundle
                ) {
                    let verifier = try CanonicalRoutePlanVerifier(
                        expectedIssuer: trust.issuer,
                        expectedAudience: trust.audience,
                        keys: [trust.verificationKey]
                    )
                    canonicalRouteStore = try CanonicalRoutePackageStore(
                        rootDirectory: canonicalRoot,
                        verifier: verifier
                    )
                } else {
                    canonicalRouteFailure =
                        "Signed offline Rail and Vessel routes await the release-pinned route trust key."
                }
            } catch {
                canonicalRouteFailure =
                    "Signed offline Rail and Vessel route trust is invalid in this build."
            }

            let retainedRouteStore = canonicalRouteStore
            let canonicalRouteIngestOperation: CanonicalRouteIngestOperation = {
                encodedEnvelope, expectedScope, receivedAt in
                guard let retainedRouteStore else {
                    throw OfflineMapProductionError.canonicalRouteTrustUnavailable
                }
                let decoder = JSONDecoder()
                let envelope: CanonicalRouteSignedEnvelope
                do {
                    envelope = try decoder.decode(
                        CanonicalRouteSignedEnvelope.self,
                        from: encodedEnvelope
                    )
                } catch {
                    throw OfflineMapProductionError.canonicalRouteEnvelopeInvalid
                }
                return try await retainedRouteStore.store(
                    signedEnvelope: envelope,
                    expectedScope: expectedScope,
                    receivedAt: receivedAt
                )
            }
            let canonicalRoutePurgeOperation: CanonicalRoutePurgeOperation = {
                if let retainedRouteStore {
                    try await retainedRouteStore.purgeAllCachedRoutes()
                    return
                }
                guard fileManager.fileExists(atPath: canonicalRoot.path) else { return }
                try fileManager.removeItem(at: canonicalRoot)
            }

            let composition = OfflineMapProductionComposition(
                owner: owner,
                mapSurface: mapSurface,
                searchOperation: searchOperation,
                routeOperation: routeOperation,
                startNavigationOperation: startNavigationOperation,
                feedLocationOperation: feedLocationOperation,
                stopNavigationOperation: stopNavigationOperation,
                canonicalRouteStore: canonicalRouteStore,
                canonicalRouteIngestOperation: canonicalRouteIngestOperation,
                canonicalRoutePurgeOperation: canonicalRoutePurgeOperation,
                canonicalRouteFailure: canonicalRouteFailure,
                principalDefaults: principalDefaults
            )
            shared = composition
            installationFailure = nil

            composition.locationCancellable = DriverLocationResolver.shared.$lastLocation
                .compactMap { $0 }
                .receive(on: RunLoop.main)
                .sink { [weak composition] location in
                    guard let composition, composition.acceptsDeviceLocations else { return }
                    let sourceInformation = location.sourceInformation
                    let provenance: OfflineLocationProvenance
                    if sourceInformation?.isSimulatedBySoftware == true {
                        provenance = .simulated
                    } else if sourceInformation?.isProducedByAccessory == true {
                        provenance = .externalGNSS
                    } else {
                        provenance = .deviceFusedLocation
                    }
                    let fix = OfflineProductionLocationFix(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude,
                        timestamp: location.timestamp,
                        horizontalAccuracyMeters: location.horizontalAccuracy,
                        speedMetersPerSecond: location.speed >= 0 ? location.speed : nil,
                        courseDegrees: location.course >= 0 ? location.course : nil,
                        provenance: provenance
                    )
                    Task { @MainActor [weak composition] in
                        await composition?.acceptDeviceLocation(fix)
                    }
                }
        } catch {
            installationFailure =
                "Offline maps could not install the release-approved device policy."
        }
    }

    func prepare() async {
        await owner.coordinator.prepare()
    }

    func setConnectivityPolicy(_ policy: OfflineMapConnectivityPolicy) async throws {
        if owner.snapshot.connectivityPolicy != policy {
            await releaseRuntimeConsumers()
        }
        try await owner.coordinator.setConnectivityPolicy(policy)
    }

    func repairPersistentMap() async throws {
        await releaseRuntimeConsumers()
        try await owner.coordinator.repairPersistentMap()
    }

    func prepareMapSurface(
        identity: HereOfflineNativeStyleIdentity,
        bundle: Bundle = .main
    ) -> AnyObject? {
        mapSurface.prepare(identity: identity, bundle: bundle)
    }

    func clearMapSurface() {
        mapSurface.clear()
    }

    func searchOffline(
        text: String,
        center: OfflineGeoCoordinate,
        maximumResultCount: Int = 20
    ) async throws -> OfflineSearchResponse {
        try await searchOperation(text, center, maximumResultCount)
    }

    func calculateOfflineRoute(
        waypoints: [OfflineRouteWaypoint],
        mode: OfflineRouteMode,
        truckConstraints: OfflineTruckConstraints? = nil,
        departureTime: Date? = nil
    ) async throws -> OfflineRouteResponse {
        try await routeOperation(
            waypoints,
            mode,
            truckConstraints,
            departureTime
        )
    }

    func startNavigation(route: OfflineLocalRoute) async throws {
        lastNavigationFailure = nil
        do {
            try await startNavigationOperation(route) { [weak self] event in
                Task { @MainActor in
                    self?.acceptNavigationEvent(event)
                }
            }
        } catch let failure as OfflineNavigationFailure {
            lastNavigationFailure = failure
            throw failure
        }
    }

    func stopNavigation() async {
        await stopNavigationOperation()
    }

    func ingestCanonicalRoutePlan(
        encodedEnvelope: Data,
        expectedScope: CanonicalRouteScope,
        receivedAt: Date
    ) async throws -> CanonicalRoutePackage {
        do {
            let package = try await canonicalRouteIngestOperation(
                encodedEnvelope,
                expectedScope,
                receivedAt
            )
            canonicalRouteFailure = nil
            return package
        } catch {
            canonicalRouteFailure =
                "The signed canonical route could not be verified for this account and load."
            throw error
        }
    }

    func observeCanonicalRoute(
        scope: CanonicalRouteScope,
        freshnessPolicy: CanonicalRouteFreshnessPolicy
    ) async throws -> CanonicalRouteObservation {
        guard let canonicalRouteStore else {
            throw OfflineMapProductionError.canonicalRouteTrustUnavailable
        }
        return try await canonicalRouteStore.observe(
            scope: scope,
            policy: freshnessPolicy
        )
    }

    /// Purges signed route geometry only when the effective tenant/user scope
    /// changes. Relaunching as the same principal preserves legitimate offline
    /// coverage, while sign-out and account switching remove it before reuse.
    func activatePrincipal(tenantID: String?, userID: String?) async {
        let nextMarker = Self.principalMarker(tenantID: tenantID, userID: userID)
        let previousMarker = principalDefaults.string(
            forKey: Self.principalMarkerKey
        )
        guard previousMarker != nextMarker else { return }

        await releaseRuntimeConsumers()
        do {
            try await canonicalRoutePurgeOperation()
            canonicalRouteFailure = canonicalRouteStore == nil
                ? canonicalRouteFailure
                : nil
            if let nextMarker {
                principalDefaults.set(nextMarker, forKey: Self.principalMarkerKey)
            } else {
                principalDefaults.removeObject(forKey: Self.principalMarkerKey)
            }
        } catch {
            canonicalRouteFailure =
                "Cached canonical routes could not be cleared for the account transition."
        }
    }

    private var acceptsDeviceLocations: Bool {
        switch navigationState {
        case .starting, .navigating, .paused, .offRoute, .rerouting:
            return true
        case .idle, .arrived, .stopped, .failed:
            return false
        }
    }

    private func acceptDeviceLocation(_ fix: OfflineProductionLocationFix) async {
        guard acceptsDeviceLocations else { return }
        do {
            try await feedLocationOperation(fix)
        } catch let failure as OfflineNavigationFailure {
            lastNavigationFailure = failure
        } catch {
            lastNavigationFailure = OfflineNavigationFailure(
                code: .locationRejected,
                message: "The current device location could not enter offline guidance.",
                recovery: "Wait for a fresh location fix and retry.",
                isRecoverable: true
            )
        }
    }

    private func acceptNavigationEvent(_ event: OfflineNavigationEvent) {
        switch event {
        case .stateChanged(let state):
            navigationState = state
            if case .navigating(_, let coverage) = state {
                navigationCoverage = coverage
            }
        case .coverageChanged(let coverage):
            navigationCoverage = coverage
        case .inputRejected(let failure), .rerouteFailed(let failure):
            lastNavigationFailure = failure
        case .maneuver, .deviationDetected, .arrived:
            break
        }
    }

    private func releaseRuntimeConsumers() async {
        await stopNavigationOperation()
        mapSurface.clear()
    }

    private static func canonicalRouteRoot(
        fileManager: FileManager
    ) throws -> URL {
        let paths = try HereSDKRuntimePaths(fileManager: fileManager)
        try paths.prepare(fileManager: fileManager)
        return paths.root.appendingPathComponent(
            canonicalRouteDirectoryName,
            isDirectory: true
        )
    }

    private static func principalMarker(
        tenantID: String?,
        userID: String?
    ) -> String? {
        guard let tenantID = tenantID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tenantID.isEmpty,
              let userID = userID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !userID.isEmpty else { return nil }
        return "\(tenantID)|\(userID)"
    }
}

struct OfflineProductionLocationFix: Sendable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let horizontalAccuracyMeters: Double
    let speedMetersPerSecond: Double?
    let courseDegrees: Double?
    let provenance: OfflineLocationProvenance
}

private struct OfflineCanonicalRouteTrustConfiguration {
    let issuer: String
    let audience: String
    let verificationKey: CanonicalRouteVerificationKey

    static func load(bundle: Bundle) throws -> Self? {
        let issuer = value(for: "EusoRoutePlanIssuer", bundle: bundle)
        let audience = value(for: "EusoRoutePlanAudience", bundle: bundle)
        let keyID = value(for: "EusoRoutePlanKeyID", bundle: bundle)
        let publicKey = value(for: "EusoRoutePlanPublicKey", bundle: bundle)
        let values = [issuer, audience, keyID, publicKey]
        guard values.contains(where: { $0 != nil }) else { return nil }
        guard let issuer, let audience, let keyID, let publicKey,
              let keyData = Data(base64Encoded: publicKey) else {
            throw OfflineMapProductionError.canonicalRouteTrustInvalid
        }
        return try Self(
            issuer: issuer,
            audience: audience,
            verificationKey: CanonicalRouteVerificationKey(
                keyID: keyID,
                ed25519RawRepresentation: keyData
            )
        )
    }

    private static func value(for key: String, bundle: Bundle) -> String? {
        guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = value.uppercased()
        guard !value.isEmpty,
              !value.hasPrefix("$("),
              !normalized.hasPrefix("REPLACE_WITH_"),
              normalized != "CHANGEME",
              normalized != "CHANGE_ME" else { return nil }
        return value
    }
}

private enum OfflineMapProductionError: Error {
    case canonicalRouteTrustUnavailable
    case canonicalRouteTrustInvalid
    case canonicalRouteEnvelopeInvalid
}
