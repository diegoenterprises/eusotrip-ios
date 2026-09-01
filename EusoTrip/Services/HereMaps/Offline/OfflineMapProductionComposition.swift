//
//  OfflineMapProductionComposition.swift
//  EusoTrip
//
//  App-owned wiring for HERE Navigate offline maps. Road and truck may use
//  verified local HERE coverage; Rail and Vessel remain bound to signed,
//  server-canonical route.plan packages.
//

import CoreLocation
import CryptoKit
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
    typealias LocalRoutePurgeOperation = () async -> Void

    private static let principalMarkerKey = "offlineMaps.canonicalRoutePrincipal.v2"
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
    @Published private(set) var installedCoverageTrustAvailable: Bool
    @Published private(set) var installedCoverageFailure: String?

    private let searchOperation: SearchOperation
    private let routeOperation: RouteOperation
    private let startNavigationOperation: StartNavigationOperation
    private let feedLocationOperation: FeedLocationOperation
    private let stopNavigationOperation: StopNavigationOperation
    private let canonicalRouteStore: CanonicalRoutePackageStore?
    private let canonicalRouteIngestOperation: CanonicalRouteIngestOperation
    private let canonicalRoutePurgeOperation: CanonicalRoutePurgeOperation
    private let localRoutePurgeOperation: LocalRoutePurgeOperation
    private let principalDefaults: UserDefaults
    private let locationSource: HereNavigationLocationSource
    private let navigationEventSequencer = OfflineNavigationEventSequencer()
    private let principalTransitionSerializer = OfflineMapPrincipalTransitionSerializer()
    private var mapSurfaceOwnerToken: UUID?
    private let installedCoverageResolver: SignedInstalledCoverageResolver?
    private let installedCoverageInstallation: HereNavigateInstalledCoverageInstallation?
    private let initialSignedCoverageManifest: OfflineCoverageSignedEnvelope?
    private var coveragePreparationTask: Task<(Bool, String?), Never>?
    private var pendingPrincipalTransitionCount = 0
    private var principalTransitionGeneration = UUID()

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
        localRoutePurgeOperation: @escaping LocalRoutePurgeOperation,
        canonicalRouteFailure: String?,
        installedCoverageResolver: SignedInstalledCoverageResolver?,
        installedCoverageInstallation: HereNavigateInstalledCoverageInstallation?,
        initialSignedCoverageManifest: OfflineCoverageSignedEnvelope?,
        installedCoverageFailure: String?,
        locationSource: HereNavigationLocationSource,
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
        self.localRoutePurgeOperation = localRoutePurgeOperation
        self.canonicalRouteFailure = canonicalRouteFailure
        canonicalRouteTrustAvailable = canonicalRouteStore != nil
        self.installedCoverageResolver = installedCoverageResolver
        self.installedCoverageInstallation = installedCoverageInstallation
        self.initialSignedCoverageManifest = initialSignedCoverageManifest
        self.installedCoverageFailure = installedCoverageFailure
        installedCoverageTrustAvailable = false
        self.locationSource = locationSource
        self.principalDefaults = principalDefaults
    }

    /// Installs exactly one process-wide owner before any route or Settings
    /// surface can request HERE state. Missing signing trust blocks only the
    /// affected capability; it never fabricates route or coverage authority.
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
            let engine = HereNavigateOfflineEngine.shared

            var installedCoverageResolver: SignedInstalledCoverageResolver?
            var installedCoverageInstallation: HereNavigateInstalledCoverageInstallation?
            var initialSignedCoverageManifest: OfflineCoverageSignedEnvelope?
            var installedCoverageFailure: String?
            do {
                if let trust = try HereNavigateInstalledCoverageTrustConfiguration.load(
                    bundle: bundle
                ) {
                    let verifier = try HEREOfflineCoverageManifestVerifier(
                        expectedIssuer: trust.issuer,
                        expectedAudience: trust.audience,
                        expectedSDKVersion: trust.expectedSDKVersion,
                        expectedRightsHolder: trust.expectedRightsHolder,
                        keys: [trust.verificationKey]
                    )
                    let runtimePaths = try HereSDKRuntimePaths(fileManager: fileManager)
                    try runtimePaths.prepare(fileManager: fileManager)
                    let resolver = try SignedInstalledCoverageResolver(
                        rootDirectory: runtimePaths.root,
                        verifier: verifier,
                        inventoryProvider: engine
                    )
                    let installation = try HereNavigateInstalledCoverageInstallation(
                        resolver: resolver,
                        expectedSDKVersion: trust.expectedSDKVersion,
                        routeCorridorHalfWidthMeters: trust.routeCorridorHalfWidthMeters
                    )
                    installedCoverageResolver = resolver
                    installedCoverageInstallation = installation
                    initialSignedCoverageManifest = trust.initialSignedManifest
                } else {
                    installedCoverageFailure =
                        "Signed installed-region coverage awaits an approved release catalog."
                }
            } catch {
                installedCoverageFailure =
                    "Signed installed-region coverage trust is invalid in this build."
            }

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
                voicePolicy: voicePolicy,
                coverageResolver: installedCoverageResolver,
                routeCorridorHalfWidthMeters: installedCoverageInstallation?
                    .routeCorridorHalfWidthMeters ?? 75
            )

            let searchOperation: SearchOperation = { text, center, maximumResultCount in
                let request = try OfflineSearchRequest(
                    text: text,
                    center: center,
                    maximumResultCount: maximumResultCount
                )
                return try await owner.coordinator.searchOffline(request)
            }
            let routeOperation: RouteOperation = {
                waypoints, mode, truckConstraints, departureTime in
                let request = try OfflineRouteRequest(
                    waypoints: waypoints,
                    mode: mode,
                    truckConstraints: truckConstraints,
                    departureTime: departureTime
                )
                return try await owner.coordinator.calculateOfflineRoute(request)
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
            let localRoutePurgeOperation: LocalRoutePurgeOperation = {
                await engine.purgeRetainedLocalRoutes()
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
                localRoutePurgeOperation: localRoutePurgeOperation,
                canonicalRouteFailure: canonicalRouteFailure,
                installedCoverageResolver: installedCoverageResolver,
                installedCoverageInstallation: installedCoverageInstallation,
                initialSignedCoverageManifest: initialSignedCoverageManifest,
                installedCoverageFailure: installedCoverageFailure,
                locationSource: HereNavigationLocationSource(),
                principalDefaults: principalDefaults
            )
            shared = composition
            installationFailure = nil
        } catch {
            installationFailure =
                "Offline maps could not install the release-approved device policy."
        }
    }

    func prepare() async {
        await prepareInstalledCoverageAuthority()
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
        ownerToken: UUID,
        bundle: Bundle = .main
    ) -> AnyObject? {
        guard mapSurfaceOwnerToken == nil || mapSurfaceOwnerToken == ownerToken else {
            return nil
        }
        guard let nativeView = mapSurface.prepare(
            identity: identity,
            bundle: bundle
        ) else {
            if mapSurfaceOwnerToken == ownerToken {
                mapSurfaceOwnerToken = nil
            }
            return nil
        }
        mapSurfaceOwnerToken = ownerToken
        return nativeView
    }

    func clearMapSurface(ownerToken: UUID) {
        guard mapSurfaceOwnerToken == ownerToken else { return }
        mapSurfaceOwnerToken = nil
        mapSurface.clear()
    }

    func searchOffline(
        text: String,
        center: OfflineGeoCoordinate,
        maximumResultCount: Int = 20
    ) async throws -> OfflineSearchResponse {
        try await withStablePrincipal { [searchOperation] in
            try await searchOperation(text, center, maximumResultCount)
        }
    }

    func calculateOfflineRoute(
        waypoints: [OfflineRouteWaypoint],
        mode: OfflineRouteMode,
        truckConstraints: OfflineTruckConstraints? = nil,
        departureTime: Date? = nil
    ) async throws -> OfflineRouteResponse {
        try await withStablePrincipal { [routeOperation] in
            try await routeOperation(
                waypoints,
                mode,
                truckConstraints,
                departureTime
            )
        }
    }

    func startNavigation(route: OfflineLocalRoute) async throws {
        lastNavigationFailure = nil
        do {
            try await withStablePrincipal { [weak self] in
                guard let self else {
                    throw OfflineMapProductionError.principalTransitionInProgress
                }
                let eventSequencer = self.navigationEventSequencer
                try await self.startNavigationOperation(route) { [weak self] event in
                    let shouldSchedule = eventSequencer.enqueue(event)
                    guard shouldSchedule else { return }
                    Task { @MainActor [weak self] in
                        self?.drainNavigationEvents()
                    }
                }
                self.drainNavigationEvents()
                do {
                    try self.locationSource.start(
                        onLocation: { [weak self] fix in
                            Task { @MainActor [weak self] in
                                await self?.acceptDeviceLocation(fix)
                            }
                        },
                        onFailure: { [weak self] failure in
                            self?.acceptLocationSourceFailure(failure)
                        }
                    )
                } catch {
                    await self.stopNavigationOperation()
                    throw error
                }
            }
        } catch let failure as OfflineNavigationFailure {
            lastNavigationFailure = failure
            throw failure
        } catch {
            let failure = OfflineNavigationFailure(
                code: .nativeGuidanceUnavailable,
                message: "Offline guidance could not start during the account transition.",
                recovery: "Wait for account activation and complete signed coverage preparation, then retry.",
                isRecoverable: true
            )
            lastNavigationFailure = failure
            throw failure
        }
    }

    func stopNavigation() async {
        await stopNavigationAndLocationSource()
    }

    func ingestCanonicalRoutePlan(
        encodedEnvelope: Data,
        expectedScope: CanonicalRouteScope,
        receivedAt: Date
    ) async throws -> CanonicalRoutePackage {
        do {
            let package = try await withStablePrincipal {
                [canonicalRouteIngestOperation] in
                try await canonicalRouteIngestOperation(
                    encodedEnvelope,
                    expectedScope,
                    receivedAt
                )
            }
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
        try await withStablePrincipal { [canonicalRouteStore] in
            guard let canonicalRouteStore else {
                throw OfflineMapProductionError.canonicalRouteTrustUnavailable
            }
            return try await canonicalRouteStore.observe(
                scope: scope,
                policy: freshnessPolicy
            )
        }
    }

    /// Purges signed route geometry only when the effective tenant/user scope
    /// changes. Relaunching as the same principal preserves legitimate offline
    /// coverage, while sign-out and account switching remove it before reuse.
    func activatePrincipal(tenantID: String?, userID: String?) async {
        let nextMarker = Self.principalMarker(tenantID: tenantID, userID: userID)
        if pendingPrincipalTransitionCount == 0,
           let nextMarker,
           principalDefaults.string(forKey: Self.principalMarkerKey) == nextMarker {
            return
        }
        principalTransitionGeneration = UUID()
        pendingPrincipalTransitionCount += 1
        defer { pendingPrincipalTransitionCount -= 1 }
        await principalTransitionSerializer.run { [weak self] in
            await self?.performPrincipalTransition(to: nextMarker)
        }
    }

    private func prepareInstalledCoverageAuthority() async {
        guard let installedCoverageResolver,
              let installedCoverageInstallation,
              let initialSignedCoverageManifest else {
            installedCoverageTrustAvailable = false
            return
        }
        let task: Task<(Bool, String?), Never>
        if let coveragePreparationTask {
            task = coveragePreparationTask
        } else {
            task = Task {
                do {
                    _ = try await installedCoverageResolver.installSignedManifest(
                        initialSignedCoverageManifest
                    )
                    try HereNavigateInstalledCoverageAuthority.shared.installOnce(
                        installedCoverageInstallation
                    )
                    return (true, nil)
                } catch {
                    return (
                        false,
                        "Signed installed-region coverage could not be verified and installed."
                    )
                }
            }
            coveragePreparationTask = task
        }
        let result = await task.value
        installedCoverageTrustAvailable = result.0
        installedCoverageFailure = result.1
        if !result.0 {
            coveragePreparationTask = nil
        }
    }

    private func withStablePrincipal<Value: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async throws -> Value
    ) async throws -> Value {
        let generation = principalTransitionGeneration
        guard pendingPrincipalTransitionCount == 0 else {
            throw OfflineMapProductionError.principalTransitionInProgress
        }
        let value = try await principalTransitionSerializer.run { [weak self] in
            guard let self,
                  self.pendingPrincipalTransitionCount == 0,
                  self.principalTransitionGeneration == generation else {
                throw OfflineMapProductionError.principalTransitionInProgress
            }
            return try await operation()
        }
        guard pendingPrincipalTransitionCount == 0,
              principalTransitionGeneration == generation else {
            throw OfflineMapProductionError.principalTransitionInProgress
        }
        return value
    }

    private func performPrincipalTransition(to nextMarker: String?) async {
        let previousMarker = principalDefaults.string(
            forKey: Self.principalMarkerKey
        )
        // Signed-out activation always purges. An absent/corrupt marker must
        // never be interpreted as proof that an on-disk route is unscoped.
        guard previousMarker != nextMarker || nextMarker == nil else { return }

        await releaseRuntimeConsumers()
        await localRoutePurgeOperation()
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
                "Cached local and canonical routes could not be cleared for the account transition."
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

    private func acceptLocationSourceFailure(_ failure: OfflineNavigationFailure) {
        lastNavigationFailure = failure
        Task { @MainActor [weak self] in
            await self?.stopNavigation()
        }
    }

    private func drainNavigationEvents() {
        for event in navigationEventSequencer.drain() {
            acceptNavigationEvent(event)
        }
    }

    private func acceptNavigationEvent(_ event: OfflineNavigationEvent) {
        switch event {
        case .stateChanged(let state):
            navigationState = state
            if case .navigating(_, let coverage) = state {
                navigationCoverage = coverage
            }
            switch state {
            case .arrived, .stopped, .failed:
                locationSource.stop()
            case .idle, .starting, .navigating, .paused, .offRoute, .rerouting:
                break
            }
        case .coverageChanged(let coverage):
            navigationCoverage = coverage
        case .inputRejected(let failure), .rerouteFailed(let failure):
            lastNavigationFailure = failure
        case .arrived:
            locationSource.stop()
        case .maneuver, .deviationDetected:
            break
        }
    }

    private func stopNavigationAndLocationSource() async {
        locationSource.stop()
        await stopNavigationOperation()
        drainNavigationEvents()
    }

    private func releaseRuntimeConsumers() async {
        await stopNavigationAndLocationSource()
        mapSurfaceOwnerToken = nil
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
        let scope = Data(
            "\(tenantID.utf8.count):\(tenantID)\(userID.utf8.count):\(userID)".utf8
        )
        return SHA256.hash(data: scope).map {
            String(format: "%02x", $0)
        }.joined()
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

/// HERE callbacks can arrive on SDK-owned queues. One scheduled MainActor
/// drain preserves the actor session's emission order without letting each
/// callback manufacture an independently racing UI task.
final class OfflineNavigationEventSequencer: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [(UInt64, OfflineNavigationEvent)] = []
    private var nextSequence: UInt64 = 0
    private var drainScheduled = false

    func enqueue(_ event: OfflineNavigationEvent) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        nextSequence &+= 1
        events.append((nextSequence, event))
        guard !drainScheduled else { return false }
        drainScheduled = true
        return true
    }

    func drain() -> [OfflineNavigationEvent] {
        lock.lock()
        defer { lock.unlock() }
        let drained = events.sorted { $0.0 < $1.0 }.map { $0.1 }
        events.removeAll(keepingCapacity: true)
        drainScheduled = false
        return drained
    }
}

/// Serializes account-scoped route reads/writes with principal transitions.
/// Actor isolation by itself is reentrant at every await, so an explicit FIFO
/// permit is required to keep an old-principal route from landing after purge.
actor OfflineMapPrincipalTransitionSerializer {
    private var permitHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<Value: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async throws -> Value
    ) async rethrows -> Value {
        await acquire()
        do {
            let value = try await operation()
            release()
            return value
        } catch {
            release()
            throw error
        }
    }

    private func acquire() async {
        guard permitHeld else {
            permitHeld = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            permitHeld = false
            return
        }
        waiters.removeFirst().resume()
    }
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
    case principalTransitionInProgress
}
