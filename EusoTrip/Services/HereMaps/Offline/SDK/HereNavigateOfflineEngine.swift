//
//  HereNavigateOfflineEngine.swift
//  EusoTrip
//
//  Conditional HERE Navigate adapter. Every route/search result in this file
//  comes from a device-local HERE engine. The adapter never falls back to an
//  online HERE service and never treats the SDK cache as installed coverage.
//

import Foundation
import Combine

enum HereNavigateOfflineFailureCode: String, Sendable {
    case missingFramework = "here_sdk_missing_framework"
    case runtimeUnavailable = "here_sdk_runtime_unavailable"
    case unsupportedConnectivityPolicy = "here_sdk_unsupported_connectivity_policy"
    case connectivityTransitionBlocked = "here_sdk_connectivity_transition_blocked"
    case radioSilenceFailed = "here_sdk_radio_silence_failed"
    case lifecycleUnavailable = "here_sdk_map_lifecycle_unavailable"
    case catalogUnavailable = "here_sdk_catalog_unavailable"
    case inventoryUnavailable = "here_sdk_inventory_unavailable"
    case storageUnavailable = "here_sdk_storage_unavailable"
    case downloadFailed = "here_sdk_download_failed"
    case deleteFailed = "here_sdk_delete_failed"
    case repairFailed = "here_sdk_repair_failed"
    case updateFailed = "here_sdk_update_failed"
    case transferControlUnavailable = "here_sdk_transfer_control_unavailable"
    case searchUnavailable = "here_sdk_offline_search_unavailable"
    case searchFailed = "here_sdk_offline_search_failed"
    case routingUnavailable = "here_sdk_offline_routing_unavailable"
    case routingFailed = "here_sdk_offline_routing_failed"
    case coverageUnverified = "here_sdk_installed_coverage_unverified"
    case invalidTruckProfile = "here_sdk_invalid_truck_profile"
    case invalidSDKData = "here_sdk_invalid_local_data"
}

struct HereNavigateOfflineAdapterError: Error, OfflineMapFailureProviding, Sendable {
    let code: HereNavigateOfflineFailureCode
    let message: String
    let recovery: String?
    let isRecoverable: Bool

    var offlineMapFailure: OfflineMapFailure {
        OfflineMapFailure(
            code: code.rawValue,
            message: message,
            recovery: recovery,
            isRecoverable: isRecoverable
        )
    }

    static let missingFramework = Self(
        code: .missingFramework,
        message: "The licensed HERE Navigate framework is not present in this build.",
        recovery: "Install the entitled HERE Navigate binary and rebuild the iOS app.",
        isRecoverable: false
    )

    static func runtime(_ message: String, recovery: String?) -> Self {
        Self(
            code: .runtimeUnavailable,
            message: message,
            recovery: recovery,
            isRecoverable: true
        )
    }

    static func operation(
        _ code: HereNavigateOfflineFailureCode,
        _ message: String,
        recovery: String,
        isRecoverable: Bool = true
    ) -> Self {
        Self(code: code, message: message, recovery: recovery, isRecoverable: isRecoverable)
    }
}

#if canImport(heresdk)
@preconcurrency import heresdk

/// Serializes ownership of HERE's process-global engine. A connectivity change
/// recreates `SDKNativeEngine`, so it must never happen under a live Navigator
/// or MapView. Weak owners prevent an abandoned consumer from permanently
/// pinning the runtime, while normal stop/clear paths release deterministically.
@MainActor
final class HereNavigateRuntimeSupervisor {
    static let shared = HereNavigateRuntimeSupervisor()

    private final class WeakLeaseOwner {
        weak var value: AnyObject?

        init(_ value: AnyObject) {
            self.value = value
        }
    }

    private var currentConnectivity: HereSDKLaunchConnectivity?
    private var currentEngineIdentity: ObjectIdentifier?
    private var navigationLeases: [UUID: WeakLeaseOwner] = [:]
    private var renderingLeases: [UUID: WeakLeaseOwner] = [:]

    private init() {}

    func validateConnectivityTransition(
        to requested: HereSDKLaunchConnectivity
    ) throws {
        discardReleasedOwners()
        let activeEngineIdentity = SDKNativeEngine.sharedInstance.map { ObjectIdentifier($0) }
        guard !hasActiveConsumer
                || (currentConnectivity == requested
                    && currentEngineIdentity != nil
                    && currentEngineIdentity == activeEngineIdentity) else {
            throw HereNavigateOfflineAdapterError.operation(
                .connectivityTransitionBlocked,
                "HERE connectivity or engine identity cannot change while offline guidance or rendering is active.",
                recovery: "Stop guidance and close the native map surface before changing or restarting map connectivity."
            )
        }
    }

    func validateEngineRestart() throws {
        discardReleasedOwners()
        guard !hasActiveConsumer else {
            throw HereNavigateOfflineAdapterError.operation(
                .connectivityTransitionBlocked,
                "HERE persistent-map repair cannot restart the engine while guidance or rendering is active.",
                recovery: "Stop guidance and close the native map surface before repairing persistent maps."
            )
        }
    }

    func recordReady(connectivity: HereSDKLaunchConnectivity) {
        currentConnectivity = connectivity
        currentEngineIdentity = SDKNativeEngine.sharedInstance.map { ObjectIdentifier($0) }
    }

    func recordStopped() {
        currentConnectivity = nil
        currentEngineIdentity = nil
    }

    func acquireNavigationLease(owner: AnyObject) throws -> UUID {
        try requireProvenRadioSilence()
        let id = UUID()
        navigationLeases[id] = WeakLeaseOwner(owner)
        return id
    }

    func releaseNavigationLease(_ id: UUID) {
        navigationLeases[id] = nil
    }

    func acquireRenderingLease(owner: AnyObject) throws -> UUID {
        try requireProvenRadioSilence()
        let id = UUID()
        renderingLeases[id] = WeakLeaseOwner(owner)
        return id
    }

    func releaseRenderingLease(_ id: UUID) {
        renderingLeases[id] = nil
    }

    private var hasActiveConsumer: Bool {
        !navigationLeases.isEmpty || !renderingLeases.isEmpty
    }

    private func discardReleasedOwners() {
        navigationLeases = navigationLeases.filter { $0.value.value != nil }
        renderingLeases = renderingLeases.filter { $0.value.value != nil }
    }

    private func requireProvenRadioSilence() throws {
        let activeEngineIdentity = SDKNativeEngine.sharedInstance.map { ObjectIdentifier($0) }
        guard currentConnectivity == .radioSilent,
              currentEngineIdentity != nil,
              currentEngineIdentity == activeEngineIdentity,
              SDKNativeEngine.sharedInstance?.isOfflineMode == true else {
            throw HereNavigateOfflineAdapterError.operation(
                .radioSilenceFailed,
                "HERE cannot lease a native consumer without proven radio silence.",
                recovery: "Prepare the shared offline map engine in radio-silent mode first."
            )
        }
    }
}

actor HereNativeRouteStore {
    static let shared = HereNativeRouteStore()

    private var routes: [String: HereNativeRouteBox] = [:]

    func store(_ route: HereNativeRouteBox, id: String) {
        routes[id] = route
    }

    func route(for id: String) -> HereNativeRouteBox? {
        routes[id]
    }

    func replace(_ route: HereNativeRouteBox, id: String) {
        routes[id] = route
    }

    func remove(id: String) {
        routes.removeValue(forKey: id)
    }

    func removeAll() {
        routes.removeAll()
    }
}

final class HereNativeRouteBox: @unchecked Sendable {
    let route: Route
    let mode: OfflineRouteMode

    init(route: Route, mode: OfflineRouteMode) {
        self.route = route
        self.mode = mode
    }
}

private struct HerePersistedRegionNameCatalog: Codable {
    let formatVersion: Int
    let namesByRegionID: [String: String]
}

private final class HereDownloadProgressBridge: DownloadRegionsStatusListener, @unchecked Sendable {
    private static let controlCallbackTimeout: TimeInterval = 15

    private let lock = NSLock()
    private let progress: OfflineMapProgressHandler
    private let expectedRegionIDs: Set<String>
    private var completion: CheckedContinuation<Void, Error>?
    private var pauseCompletion: CheckedContinuation<Void, Error>?
    private var resumeCompletion: CheckedContinuation<Void, Error>?
    private var pauseWaiterID: UUID?
    private var resumeWaiterID: UUID?
    private var pendingPauseResult: Result<Void, Error>?
    private var pendingResume = false
    private var terminalResult: Result<Void, Error>?

    init(
        expectedRegionIDs: Set<String>,
        progress: @escaping OfflineMapProgressHandler
    ) {
        self.expectedRegionIDs = expectedRegionIDs
        self.progress = progress
    }

    func installCompletion(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        if let terminalResult {
            lock.unlock()
            continuation.resume(with: terminalResult)
            return
        }
        guard completion == nil else {
            lock.unlock()
            continuation.resume(throwing: Self.duplicateCompletionError)
            return
        }
        completion = continuation
        lock.unlock()
    }

    func waitForPause() async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let terminalResult {
                lock.unlock()
                continuation.resume(with: terminalResult)
                return
            }
            if let result = pendingPauseResult {
                pendingPauseResult = nil
                lock.unlock()
                continuation.resume(with: result)
                return
            }
            guard pauseCompletion == nil else {
                lock.unlock()
                continuation.resume(
                    throwing: Self.concurrentControlError(command: "pause")
                )
                return
            }
            let waiterID = UUID()
            pauseCompletion = continuation
            pauseWaiterID = waiterID
            lock.unlock()
            schedulePauseTimeout(waiterID: waiterID)
        }
    }

    func waitForResume() async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let terminalResult {
                lock.unlock()
                continuation.resume(with: terminalResult)
                return
            }
            if pendingResume {
                pendingResume = false
                lock.unlock()
                continuation.resume()
                return
            }
            guard resumeCompletion == nil else {
                lock.unlock()
                continuation.resume(
                    throwing: Self.concurrentControlError(command: "resume")
                )
                return
            }
            let waiterID = UUID()
            resumeCompletion = continuation
            resumeWaiterID = waiterID
            lock.unlock()
            scheduleResumeTimeout(waiterID: waiterID)
        }
    }

    func onProgress(region: RegionId, percentage: Int32) {
        guard expectedRegionIDs.contains(region.id),
              let regionID = try? OfflineMapRegionID(region.id),
              let update = try? OfflineMapTransferProgress(
                regionID: regionID,
                detail: "Downloading one installed HERE region: \(min(max(percentage, 0), 100)) percent."
              ) else { return }
        progress(update)
    }

    func onDownloadRegionsComplete(error: MapLoaderError?, regions: [RegionId]?) {
        let result: Result<Void, Error>
        let completedRegions = regions ?? []
        let completedRegionIDs = Set(completedRegions.map(\.id))
        if error == nil,
           completedRegions.count == expectedRegionIDs.count,
           completedRegionIDs == expectedRegionIDs {
            if let update = try? OfflineMapTransferProgress(
                fractionCompleted: 1,
                detail: "Selected HERE region downloads are complete."
            ) {
                progress(update)
            }
            result = .success(())
        } else {
            result = .failure(
                HereNavigateOfflineAdapterError.operation(
                    .downloadFailed,
                    "HERE could not finish the region download.",
                    recovery: "Retry on a stable connection with sufficient storage."
                )
            )
        }
        finish(result)
    }

    func onPause(error: MapLoaderError?) {
        // HERE invokes this only after the task is paused. A non-nil error is
        // the sanitized reason automatic retries were exhausted, not evidence
        // that the task remained running.
        let result: Result<Void, Error> = .success(())
        lock.lock()
        let shouldReport = terminalResult == nil
        let continuation = pauseCompletion
        pauseCompletion = nil
        pauseWaiterID = nil
        pendingResume = false
        if continuation == nil, terminalResult == nil, pendingPauseResult == nil {
            pendingPauseResult = result
        }
        lock.unlock()
        if shouldReport,
           let update = try? OfflineMapTransferProgress(
               detail: error == nil
                   ? "HERE paused the map download."
                   : "HERE paused the map download after a native transfer failure.",
               reportedPhase: .paused
           ) {
            progress(update)
        }
        continuation?.resume(with: result)
    }

    func onResume() {
        lock.lock()
        let shouldReport = terminalResult == nil
        let continuation = resumeCompletion
        resumeCompletion = nil
        resumeWaiterID = nil
        pendingPauseResult = nil
        if continuation == nil, terminalResult == nil {
            pendingResume = true
        }
        lock.unlock()
        if shouldReport,
           let update = try? OfflineMapTransferProgress(
               detail: "HERE resumed the map download.",
               reportedPhase: .running
           ) {
            progress(update)
        }
        continuation?.resume()
    }

    func resolveCancellation() {
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        guard terminalResult == nil else {
            lock.unlock()
            return
        }
        terminalResult = result
        let continuation = completion
        completion = nil
        let pause = pauseCompletion
        pauseCompletion = nil
        pauseWaiterID = nil
        let resume = resumeCompletion
        resumeCompletion = nil
        resumeWaiterID = nil
        pendingPauseResult = nil
        pendingResume = false
        lock.unlock()
        continuation?.resume(with: result)
        pause?.resume(with: result)
        resume?.resume(with: result)
    }

    private func schedulePauseTimeout(waiterID: UUID) {
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + Self.controlCallbackTimeout
        ) { [weak self] in
            self?.expirePauseWaiter(waiterID)
        }
    }

    private func expirePauseWaiter(_ waiterID: UUID) {
        lock.lock()
        guard pauseWaiterID == waiterID,
              terminalResult == nil,
              let continuation = pauseCompletion else {
            lock.unlock()
            return
        }
        pauseCompletion = nil
        pauseWaiterID = nil
        lock.unlock()
        continuation.resume(
            throwing: Self.callbackTimeoutError(command: "pause")
        )
    }

    private func scheduleResumeTimeout(waiterID: UUID) {
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + Self.controlCallbackTimeout
        ) { [weak self] in
            self?.expireResumeWaiter(waiterID)
        }
    }

    private func expireResumeWaiter(_ waiterID: UUID) {
        lock.lock()
        guard resumeWaiterID == waiterID,
              terminalResult == nil,
              let continuation = resumeCompletion else {
            lock.unlock()
            return
        }
        resumeCompletion = nil
        resumeWaiterID = nil
        lock.unlock()
        continuation.resume(
            throwing: Self.callbackTimeoutError(command: "resume")
        )
    }

    private static func concurrentControlError(
        command: String
    ) -> HereNavigateOfflineAdapterError {
        HereNavigateOfflineAdapterError.operation(
            .transferControlUnavailable,
            "A HERE map-transfer \(command) command is already awaiting native confirmation.",
            recovery: "Wait for the current transfer control to finish before retrying."
        )
    }

    private static func callbackTimeoutError(
        command: String
    ) -> HereNavigateOfflineAdapterError {
        HereNavigateOfflineAdapterError.operation(
            .transferControlUnavailable,
            "HERE did not confirm the map-transfer \(command) command in time.",
            recovery: "Review the displayed native transfer phase before retrying the control."
        )
    }

    private static let duplicateCompletionError: HereNavigateOfflineAdapterError =
        HereNavigateOfflineAdapterError.operation(
            .transferControlUnavailable,
            "HERE map download completion is already being observed.",
            recovery: "Wait for the active download to finish or cancel it before retrying."
        )
}

private final class HereCatalogUpdateProgressBridge: CatalogUpdateProgressListener, @unchecked Sendable {
    private static let controlCallbackTimeout: TimeInterval = 15

    private let lock = NSLock()
    private let catalogIndex: Int
    private let catalogCount: Int
    private let progress: OfflineMapProgressHandler
    private var completion: CheckedContinuation<Void, Error>?
    private var pauseCompletion: CheckedContinuation<Void, Error>?
    private var resumeCompletion: CheckedContinuation<Void, Error>?
    private var pauseWaiterID: UUID?
    private var resumeWaiterID: UUID?
    private var pendingPauseResult: Result<Void, Error>?
    private var pendingResume = false
    private var terminalResult: Result<Void, Error>?

    init(catalogIndex: Int, catalogCount: Int, progress: @escaping OfflineMapProgressHandler) {
        self.catalogIndex = catalogIndex
        self.catalogCount = max(catalogCount, 1)
        self.progress = progress
    }

    func installCompletion(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        if let terminalResult {
            lock.unlock()
            continuation.resume(with: terminalResult)
            return
        }
        guard completion == nil else {
            lock.unlock()
            continuation.resume(throwing: Self.duplicateCompletionError)
            return
        }
        completion = continuation
        lock.unlock()
    }

    func waitForPause() async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let terminalResult {
                lock.unlock()
                continuation.resume(with: terminalResult)
                return
            }
            if let result = pendingPauseResult {
                pendingPauseResult = nil
                lock.unlock()
                continuation.resume(with: result)
                return
            }
            guard pauseCompletion == nil else {
                lock.unlock()
                continuation.resume(
                    throwing: Self.concurrentControlError(command: "pause")
                )
                return
            }
            let waiterID = UUID()
            pauseCompletion = continuation
            pauseWaiterID = waiterID
            lock.unlock()
            schedulePauseTimeout(waiterID: waiterID)
        }
    }

    func waitForResume() async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let terminalResult {
                lock.unlock()
                continuation.resume(with: terminalResult)
                return
            }
            if pendingResume {
                pendingResume = false
                lock.unlock()
                continuation.resume()
                return
            }
            guard resumeCompletion == nil else {
                lock.unlock()
                continuation.resume(
                    throwing: Self.concurrentControlError(command: "resume")
                )
                return
            }
            let waiterID = UUID()
            resumeCompletion = continuation
            resumeWaiterID = waiterID
            lock.unlock()
            scheduleResumeTimeout(waiterID: waiterID)
        }
    }

    func onProgress(region: RegionId, percentage: Int32) {
        let regionID = try? OfflineMapRegionID(region.id)
        guard let update = try? OfflineMapTransferProgress(
            regionID: regionID,
            detail: "Updating HERE map catalog \(catalogIndex + 1) of \(catalogCount), current region \(min(max(percentage, 0), 100)) percent."
        ) else { return }
        progress(update)
    }

    func onComplete(error: MapLoaderError?) {
        let result: Result<Void, Error>
        if error == nil {
            result = .success(())
        } else {
            result = .failure(
                HereNavigateOfflineAdapterError.operation(
                    .updateFailed,
                    "HERE could not finish the persistent map update.",
                    recovery: "Retry the update on a stable connection with sufficient storage."
                )
            )
        }
        finish(result)
    }

    func onPause(error: MapLoaderError?) {
        // HERE invokes this only after the task is paused. A non-nil error is
        // the sanitized reason automatic retries were exhausted, not evidence
        // that the task remained running.
        let result: Result<Void, Error> = .success(())
        lock.lock()
        let shouldReport = terminalResult == nil
        let continuation = pauseCompletion
        pauseCompletion = nil
        pauseWaiterID = nil
        pendingResume = false
        if continuation == nil, terminalResult == nil, pendingPauseResult == nil {
            pendingPauseResult = result
        }
        lock.unlock()
        if shouldReport,
           let update = try? OfflineMapTransferProgress(
               detail: error == nil
                   ? "HERE paused the persistent map update."
                   : "HERE paused the persistent map update after a native transfer failure.",
               reportedPhase: .paused
           ) {
            progress(update)
        }
        continuation?.resume(with: result)
    }

    func onResume() {
        lock.lock()
        let shouldReport = terminalResult == nil
        let continuation = resumeCompletion
        resumeCompletion = nil
        resumeWaiterID = nil
        pendingPauseResult = nil
        if continuation == nil, terminalResult == nil {
            pendingResume = true
        }
        lock.unlock()
        if shouldReport,
           let update = try? OfflineMapTransferProgress(
               detail: "HERE resumed the persistent map update.",
               reportedPhase: .running
           ) {
            progress(update)
        }
        continuation?.resume()
    }

    func resolveCancellation() {
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        guard terminalResult == nil else {
            lock.unlock()
            return
        }
        terminalResult = result
        let continuation = completion
        completion = nil
        let pause = pauseCompletion
        pauseCompletion = nil
        pauseWaiterID = nil
        let resume = resumeCompletion
        resumeCompletion = nil
        resumeWaiterID = nil
        pendingPauseResult = nil
        pendingResume = false
        lock.unlock()
        continuation?.resume(with: result)
        pause?.resume(with: result)
        resume?.resume(with: result)
    }

    private func schedulePauseTimeout(waiterID: UUID) {
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + Self.controlCallbackTimeout
        ) { [weak self] in
            self?.expirePauseWaiter(waiterID)
        }
    }

    private func expirePauseWaiter(_ waiterID: UUID) {
        lock.lock()
        guard pauseWaiterID == waiterID,
              terminalResult == nil,
              let continuation = pauseCompletion else {
            lock.unlock()
            return
        }
        pauseCompletion = nil
        pauseWaiterID = nil
        lock.unlock()
        continuation.resume(
            throwing: Self.callbackTimeoutError(command: "pause")
        )
    }

    private func scheduleResumeTimeout(waiterID: UUID) {
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + Self.controlCallbackTimeout
        ) { [weak self] in
            self?.expireResumeWaiter(waiterID)
        }
    }

    private func expireResumeWaiter(_ waiterID: UUID) {
        lock.lock()
        guard resumeWaiterID == waiterID,
              terminalResult == nil,
              let continuation = resumeCompletion else {
            lock.unlock()
            return
        }
        resumeCompletion = nil
        resumeWaiterID = nil
        lock.unlock()
        continuation.resume(
            throwing: Self.callbackTimeoutError(command: "resume")
        )
    }

    private static func concurrentControlError(
        command: String
    ) -> HereNavigateOfflineAdapterError {
        HereNavigateOfflineAdapterError.operation(
            .transferControlUnavailable,
            "A HERE map-transfer \(command) command is already awaiting native confirmation.",
            recovery: "Wait for the current transfer control to finish before retrying."
        )
    }

    private static func callbackTimeoutError(
        command: String
    ) -> HereNavigateOfflineAdapterError {
        HereNavigateOfflineAdapterError.operation(
            .transferControlUnavailable,
            "HERE did not confirm the map-transfer \(command) command in time.",
            recovery: "Review the displayed native transfer phase before retrying the control."
        )
    }

    private static let duplicateCompletionError: HereNavigateOfflineAdapterError =
        HereNavigateOfflineAdapterError.operation(
            .transferControlUnavailable,
            "HERE map update completion is already being observed.",
            recovery: "Wait for the active update to finish or cancel it before retrying."
        )
}

actor HereNavigateOfflineEngine: OfflineMapEngine, HEREInstalledRegionInventoryProviding {
    static let shared = HereNavigateOfflineEngine()

    private let routeStore: HereNativeRouteStore
    private var appliedPolicy: OfflineMapConnectivityPolicy?
    private var launchConnectivity: HereSDKLaunchConnectivity?
    private var nativeEngineIdentity: ObjectIdentifier?
    private var mapDownloader: MapDownloader?
    private var mapUpdater: MapUpdater?
    private var offlineSearchEngine: OfflineSearchEngine?
    private var offlineRoutingEngine: OfflineRoutingEngine?
    private var downloadableRegionCache: [String: Region] = [:]
    private var downloadableNameCache: [String: String] = [:]
    /// A catalog update is global in HERE's current API. Nil means no connected
    /// catalog check has been retained, not "up to date."
    private var retainedCatalogUpdateAvailable: Bool?
    private var retainedCatalogCheckedAt: Date?
    private var activeDownloadTask: MapDownloaderTask?
    private var activeDownloadBridge: HereDownloadProgressBridge?
    private var activeUpdateTask: CatalogUpdateTask?
    private var activeUpdateBridge: HereCatalogUpdateProgressBridge?
    private var activeTransferControl: OfflineMapOperationPhase?
    /// Actor isolation alone does not serialize across an `await`. This guard
    /// protects the native downloader/updater from a second root mutation while
    /// the first actor method is suspended.
    private var activeMutation: OfflineMapOperationKind?

    private init(routeStore: HereNativeRouteStore = .shared) {
        self.routeStore = routeStore
    }

    func makeNavigationSession(
        locationPolicy: HereNavigationLocationAcceptancePolicy = .production,
        voicePolicy: HereNavigationVoicePolicy = .requiredEnglishUS,
        coverageResolver: (any OfflineInstalledCoverageResolving)? = nil,
        routeCorridorHalfWidthMeters: Double = 75
    ) -> HereNavigateNavigationSession {
        HereNavigateNavigationSession(
            routeStore: routeStore,
            locationPolicy: locationPolicy,
            voicePolicy: voicePolicy,
            coverageResolver: coverageResolver,
            routeCorridorHalfWidthMeters: routeCorridorHalfWidthMeters
        )
    }

    func purgeRetainedLocalRoutes() async {
        await routeStore.removeAll()
    }

    func inspect(
        connectivityPolicy: OfflineMapConnectivityPolicy
    ) async -> OfflineMapEngineInspection {
        do {
            let radioState = try await applyConnectivityPolicy(connectivityPolicy)
            let downloader = try await requireMapDownloader()
            let updater = try await requireMapUpdater()
            let renderingAvailable = HereOfflineNativeStyleBundleCatalog
                .hasCompleteValidatedCatalog()

            var capabilities: OfflineMapCapabilities = [
                .persistentRegionLifecycle,
                .radioSilence,
                .persistentMapRepair,
                .persistentMapUpdates,
            ]
            if renderingAvailable {
                capabilities.insert(.offlineVectorRendering)
                capabilities.insert(.detailedRendering)
            }
            if let coverage = HereNavigateInstalledCoverageAuthority.shared
                .currentInstallation() {
                let runtimeVersion = SDKBuildInformation.sdkVersion().versionName
                guard runtimeVersion == coverage.expectedSDKVersion else {
                    throw HereNavigateOfflineAdapterError.operation(
                        .invalidSDKData,
                        "The installed HERE framework version does not match signed coverage trust.",
                        recovery: "Install the exact release-approved HERE SDK and matching signed coverage catalog.",
                        isRecoverable: false
                    )
                }
                capabilities.formUnion([
                    .offlineSearch,
                    .offlineRoadRouting,
                    .offlineTruckRouting,
                ])
                if HereNavigateNavigationSession.canInitializeNativeGuidance() {
                    capabilities.insert(.offlineGuidance)
                }
                let voiceAvailable = await MainActor.run {
                    HereNavigateNavigationSession.canInitializeOfflineVoiceGuidance()
                }
                if voiceAvailable {
                    capabilities.insert(.offlineVoiceGuidance)
                }
            }

            // Missing optional/required parity capabilities are represented by
            // absent bits. The coordinator can then remain usable in `.limited`
            // state instead of losing installed-map inventory entirely.
            var blockers: [OfflineMapReadinessBlocker] = []

            let health = persistentHealth(downloader: downloader, updater: updater)
            if case .needsRepair(let reason) = health {
                blockers.append(
                    .init(
                        code: .persistentMapNeedsRepair,
                        message: reason,
                        recovery: "Repair the persistent map before downloading, deleting, or navigating."
                    )
                )
            }
            return OfflineMapEngineInspection(
                capabilities: capabilities,
                blockers: blockers,
                persistentHealth: health,
                radioSilenceState: radioState
            )
        } catch {
            let blocker = blocker(for: error)
            return OfflineMapEngineInspection(
                capabilities: [],
                blockers: [blocker],
                persistentHealth: .unusable(reason: blocker.message),
                radioSilenceState: connectivityPolicy == .radioSilent
                    ? .notEnforced(reason: blocker.message)
                    : .notRequested
            )
        }
    }

    func applyConnectivityPolicy(
        _ policy: OfflineMapConnectivityPolicy
    ) async throws -> OfflineMapRadioSilenceState {
        try await applyConnectivityPolicy(policy, allowing: nil)
    }

    private func applyConnectivityPolicy(
        _ policy: OfflineMapConnectivityPolicy,
        allowing permittedMutation: OfflineMapOperationKind?
    ) async throws -> OfflineMapRadioSilenceState {
        if let activeMutation, activeMutation != permittedMutation {
            throw OfflineMapCoreError.busy(activeOperation: activeMutation)
        }
        let requestedLaunch: HereSDKLaunchConnectivity
        switch policy {
        case .onlineAllowed:
            requestedLaunch = .connected
        case .radioSilent:
            requestedLaunch = .radioSilent
        case .preferOffline:
            throw HereNavigateOfflineAdapterError.operation(
                .unsupportedConnectivityPolicy,
                "HERE offline maps cannot prove a prefer-offline network policy.",
                recovery: "Use connected maintenance for downloads and updates, then switch explicitly to radio-silent operation."
            )
        }
        if launchConnectivity != nil,
           launchConnectivity != requestedLaunch,
           (activeDownloadTask != nil || activeUpdateTask != nil) {
            throw HereNavigateOfflineAdapterError.operation(
                .connectivityTransitionBlocked,
                "HERE connectivity cannot change during an active map transfer.",
                recovery: "Pause or cancel the transfer before changing map connectivity."
            )
        }
        let availability = try await MainActor.run {
            try HereSDKRuntime.shared.start(connectivity: requestedLaunch)
        }
        guard case .ready(let launched) = availability, launched == requestedLaunch else {
            throw runtimeError(for: availability)
        }

        guard let nativeEngine = SDKNativeEngine.sharedInstance else {
            throw HereNavigateOfflineAdapterError.runtime(
                "HERE reported ready without an active native engine.",
                recovery: "Restart the offline map runtime."
            )
        }
        let currentIdentity = ObjectIdentifier(nativeEngine)
        if launchConnectivity != requestedLaunch || nativeEngineIdentity != currentIdentity {
            await resetSDKServices()
            launchConnectivity = requestedLaunch
            nativeEngineIdentity = currentIdentity
        }
        appliedPolicy = policy

        if policy == .radioSilent {
            guard nativeEngine.isOfflineMode else {
                throw HereNavigateOfflineAdapterError.operation(
                    .radioSilenceFailed,
                    "HERE did not confirm radio-silent operation.",
                    recovery: "Do not depart until the native engine starts in offline mode."
                )
            }
            return .enforced
        }
        return .notRequested
    }

    func downloadableRegions() async throws -> [OfflineMapDownloadableRegion] {
        try requireConnectedCatalogAccess()
        let downloader = try await requireMapDownloader()
        let regions: [Region] = try await withCheckedThrowingContinuation { continuation in
            _ = downloader.getDownloadableRegions(languageCode: .enUs) { error, regions in
                guard error == nil, let regions else {
                    continuation.resume(
                        throwing: HereNavigateOfflineAdapterError.operation(
                            .catalogUnavailable,
                            "HERE could not load the downloadable region catalog.",
                            recovery: "Reconnect and retry the region catalog."
                        )
                    )
                    return
                }
                continuation.resume(returning: regions)
            }
        }

        downloadableRegionCache.removeAll(keepingCapacity: true)
        downloadableNameCache.removeAll(keepingCapacity: true)
        var models: [OfflineMapDownloadableRegion] = []
        for region in regions {
            try flatten(
                region: region,
                parentID: nil,
                depth: 0,
                models: &models
            )
        }
        try persistDownloadableRegionNames()
        return models
    }

    func installedRegions() async throws -> [OfflineMapInstalledRegion] {
        let downloader = try await requireMapDownloader()
        let updater = try await requireMapUpdater()
        loadPersistedRegionNamesIfNeeded()
        let nativeRegions: [InstalledRegion]
        do {
            nativeRegions = try downloader.getInstalledRegions()
        } catch {
            throw HereNavigateOfflineAdapterError.operation(
                .inventoryUnavailable,
                "HERE could not read installed map regions.",
                recovery: "Repair the persistent map or restart the offline runtime."
            )
        }
        let catalogVersion = (try? updater.getCurrentMapVersion()
            .stringRepresentation(separator: "."))
            .flatMap(sanitizedRegionName)
        if appliedPolicy != .radioSilent {
            do {
                let updates = try await catalogUpdateInfo()
                retainedCatalogUpdateAvailable = !updates.isEmpty
                retainedCatalogCheckedAt = Date()
            } catch {
                // Installed inventory remains useful. Update currency is kept
                // explicitly unknown instead of erasing a valid cold-start list.
                retainedCatalogUpdateAvailable = nil
                retainedCatalogCheckedAt = nil
            }
        }
        var observedRegionIDs = Set<String>()
        return try nativeRegions.map { region in
            guard observedRegionIDs.insert(region.regionId.id).inserted else {
                throw HereNavigateOfflineAdapterError.operation(
                    .invalidSDKData,
                    "HERE returned duplicate identifiers in installed map data.",
                    recovery: "Repair the persistent map before using installed regions."
                )
            }
            let id = try OfflineMapRegionID(region.regionId.id)
            let name = downloadableNameCache[id.rawValue] ?? "Installed HERE region"
            let state: OfflineMapInstalledRegionState
            if region.status != .installed {
                state = .incomplete
            } else if retainedCatalogUpdateAvailable == true {
                // CatalogUpdateInfo is catalog-wide, so the current HERE API
                // does not support more granular per-region attribution.
                state = .updateAvailable
            } else if retainedCatalogUpdateAvailable == false {
                state = .installed
            } else {
                state = .updateStatusUnknown
            }
            return try OfflineMapInstalledRegion(
                id: id,
                name: name,
                installedBytes: checkedInt64(region.sizeOnDiskInBytes),
                catalogVersion: catalogVersion,
                state: state,
                // InstalledRegion does not evidence an install timestamp in
                // the current checked-in iOS examples. Do not manufacture one.
                installedAt: nil,
                lastVerifiedAt: retainedCatalogCheckedAt
            )
        }
    }

    func currentHEREInstalledRegionInventory() async throws
        -> HEREInstalledRegionInventory {
        let downloader = try await requireMapDownloader()
        let updater = try await requireMapUpdater()
        let nativeRegions: [InstalledRegion]
        do {
            nativeRegions = try downloader.getInstalledRegions()
        } catch {
            throw SignedInstalledCoverageError.invalidInventory(
                "HERE could not read its native installed-region inventory."
            )
        }
        guard let version = (try? updater.getCurrentMapVersion()
            .stringRepresentation(separator: "."))
            .flatMap(sanitizedRegionName) else {
            throw SignedInstalledCoverageError.invalidInventory(
                "HERE did not provide the installed map catalog version."
            )
        }
        var observed = Set<String>()
        var usable = Set<OfflineMapRegionID>()
        for region in nativeRegions {
            guard observed.insert(region.regionId.id).inserted else {
                throw SignedInstalledCoverageError.invalidInventory(
                    "HERE returned duplicate native installed-region identifiers."
                )
            }
            guard region.status == .installed else { continue }
            usable.insert(try OfflineMapRegionID(region.regionId.id))
        }
        return try HEREInstalledRegionInventory(
            catalogVersion: HEREOfflineCatalogVersion(version),
            usableRegionIDs: usable,
            observedAt: Date()
        )
    }

    func storageSnapshot() async throws -> OfflineMapStorageSnapshot {
        let downloader = try await requireMapDownloader()
        let installedBytes: UInt64
        do {
            installedBytes = try downloader.getOfflineMapsStorageSizeInBytes()
        } catch {
            throw HereNavigateOfflineAdapterError.operation(
                .storageUnavailable,
                "HERE could not measure persistent map storage.",
                recovery: "Restart the offline runtime and retry the storage check."
            )
        }
        let available = try deviceAvailableBytes()
        return try OfflineMapStorageSnapshot(
            availableBytes: available,
            installedMapBytes: checkedInt64(installedBytes)
        )
    }

    func downloadByteEstimate(
        for regionIDs: [OfflineMapRegionID]
    ) async throws -> OfflineMapByteEstimate? {
        if downloadableRegionCache.isEmpty {
            _ = try await downloadableRegions()
        }
        var total: Int64 = 0
        for id in regionIDs {
            guard let region = downloadableRegionCache[id.rawValue] else {
                throw OfflineMapCoreError.unknownRegions([id])
            }
            // Protect device storage using installed bytes plus a conservative
            // compressed-transfer staging allowance. Network bytes alone can
            // materially understate the free-space requirement.
            let regionRequirement = try adding(
                checkedInt64(region.sizeOnDiskInBytes),
                checkedInt64(region.sizeOnNetworkInBytes)
            )
            total = try adding(total, regionRequirement)
        }
        return try OfflineMapByteEstimate(requiredBytes: total, confidence: .sdkEstimate)
    }

    func persistentMapUpdateByteEstimate() async throws -> OfflineMapByteEstimate? {
        try requireConnectedCatalogAccess()
        let infos = try await catalogUpdateInfo()
        var total: Int64 = 0
        for info in infos {
            total = try adding(total, checkedInt64(info.diskSizeInBytes))
            total = try adding(total, checkedInt64(info.temporaryDiskRequirementInBytes))
        }
        return try OfflineMapByteEstimate(requiredBytes: total, confidence: .sdkEstimate)
    }

    func downloadRegions(
        _ regionIDs: [OfflineMapRegionID],
        progress: @escaping OfflineMapProgressHandler
    ) async throws {
        try beginMutation(.downloadRegions)
        defer { endMutation(.downloadRegions) }
        guard !regionIDs.isEmpty,
              Set(regionIDs).count == regionIDs.count else {
            throw OfflineMapCoreError.invalidInput(
                "Region downloads require unique non-empty identifiers."
            )
        }
        try requireConnectedCatalogAccess()
        let downloader = try await requireMapDownloader()
        if downloadableRegionCache.isEmpty {
            _ = try await downloadableRegions()
        }
        let nativeIDs: [RegionId] = try regionIDs.map { id in
            guard let region = downloadableRegionCache[id.rawValue] else {
                throw OfflineMapCoreError.unknownRegions([id])
            }
            return region.regionId
        }
        let bridge = HereDownloadProgressBridge(
            expectedRegionIDs: Set(regionIDs.map(\.rawValue)),
            progress: progress
        )
        activeDownloadBridge = bridge
        defer {
            activeDownloadTask = nil
            activeDownloadBridge = nil
        }
        try await withCheckedThrowingContinuation { continuation in
            bridge.installCompletion(continuation)
            activeDownloadTask = downloader.downloadRegions(
                regions: nativeIDs,
                statusListener: bridge
            )
        }
    }

    func deleteRegions(
        _ regionIDs: [OfflineMapRegionID],
        progress: @escaping OfflineMapProgressHandler
    ) async throws {
        try beginMutation(.deleteRegions)
        defer { endMutation(.deleteRegions) }
        guard !regionIDs.isEmpty,
              Set(regionIDs).count == regionIDs.count else {
            throw OfflineMapCoreError.invalidInput(
                "Region deletion requires unique non-empty identifiers."
            )
        }
        let downloader = try await requireMapDownloader()
        let installed: [InstalledRegion]
        do {
            installed = try downloader.getInstalledRegions()
        } catch {
            throw HereNavigateOfflineAdapterError.operation(
                .inventoryUnavailable,
                "HERE could not read installed regions before deletion.",
                recovery: "Restart offline maps or repair the persistent map before retrying."
            )
        }
        var index: [String: RegionId] = [:]
        for region in installed {
            guard index.updateValue(region.regionId, forKey: region.regionId.id) == nil else {
                throw HereNavigateOfflineAdapterError.operation(
                    .invalidSDKData,
                    "HERE returned duplicate identifiers in installed map data.",
                    recovery: "Repair the persistent map before deleting regions."
                )
            }
        }
        let nativeIDs = try regionIDs.map { id -> RegionId in
            guard let native = index[id.rawValue] else {
                throw OfflineMapCoreError.unknownRegions([id])
            }
            return native
        }
        emitProgress(progress, fraction: 0, detail: "Preparing installed map deletion.")
        try await withCheckedThrowingContinuation { continuation in
            downloader.deleteRegions(regions: nativeIDs) { error, deleted in
                let requestedIDs = Set(nativeIDs.map(\.id))
                let deletedIDs = Set((deleted ?? []).map(\.id))
                guard error == nil, requestedIDs == deletedIDs else {
                    continuation.resume(
                        throwing: HereNavigateOfflineAdapterError.operation(
                            .deleteFailed,
                            "HERE could not delete the selected installed regions.",
                            recovery: "Finish any active transfer, then retry the deletion."
                        )
                    )
                    return
                }
                continuation.resume()
            }
        }
        emitProgress(progress, fraction: 1, detail: "Installed map deletion complete.")
    }

    func repairPersistentMap(
        progress: @escaping OfflineMapProgressHandler
    ) async throws {
        try beginMutation(.repairPersistentMap)
        defer { endMutation(.repairPersistentMap) }
        guard activeDownloadTask == nil, activeUpdateTask == nil else {
            throw HereNavigateOfflineAdapterError.operation(
                .transferControlUnavailable,
                "HERE persistent-map repair cannot restart during an active transfer.",
                recovery: "Cancel the active transfer before repairing persistent maps."
            )
        }
        let downloader = try await requireMapDownloader()
        guard let policy = appliedPolicy else {
            throw HereNavigateOfflineAdapterError.runtime(
                "HERE offline maps have not been prepared.",
                recovery: "Prepare offline maps before repairing persistent data."
            )
        }
        emitProgress(progress, fraction: 0, detail: "Repairing persistent HERE map data.")
        try await withCheckedThrowingContinuation { continuation in
            downloader.repairPersistentMap { error in
                guard error == nil else {
                    continuation.resume(
                        throwing: HereNavigateOfflineAdapterError.operation(
                            .repairFailed,
                            "HERE could not repair the persistent map.",
                            recovery: "Review the persistent-map state and retry the recommended recovery."
                        )
                    )
                    return
                }
                continuation.resume()
            }
        }

        // HERE documents the initial persistent-map status as immutable for an
        // engine lifetime. A successful callback is not proof of health until a
        // fresh engine reports `.ok` from the repaired storage.
        await resetSDKServices()
        try await MainActor.run {
            try HereSDKRuntime.shared.stop()
        }
        appliedPolicy = nil
        launchConnectivity = nil
        nativeEngineIdentity = nil
        _ = try await applyConnectivityPolicy(
            policy,
            allowing: .repairPersistentMap
        )
        let verifyingDownloader = try await requireMapDownloader()
        guard verifyingDownloader.getInitialPersistentMapStatus() == .ok else {
            throw HereNavigateOfflineAdapterError.operation(
                .repairFailed,
                "HERE completed repair but the restarted engine still reports unhealthy persistent data.",
                recovery: "Do not use the affected maps; retry the SDK-recommended recovery."
            )
        }
        emitProgress(progress, fraction: 1, detail: "Persistent map repair complete.")
    }

    func updatePersistentMap(
        progress: @escaping OfflineMapProgressHandler
    ) async throws {
        try beginMutation(.updatePersistentMap)
        defer { endMutation(.updatePersistentMap) }
        try requireConnectedCatalogAccess()
        let updater = try await requireMapUpdater()
        let infos = try await catalogUpdateInfo()
        if infos.isEmpty {
            retainedCatalogUpdateAvailable = false
            retainedCatalogCheckedAt = Date()
            downloadableRegionCache.removeAll()
            downloadableNameCache.removeAll()
            emitProgress(progress, fraction: 1, detail: "Installed maps are current.")
            return
        }

        for (index, info) in infos.enumerated() {
            let bridge = HereCatalogUpdateProgressBridge(
                catalogIndex: index,
                catalogCount: infos.count,
                progress: progress
            )
            activeUpdateBridge = bridge
            defer {
                activeUpdateTask = nil
                activeUpdateBridge = nil
            }
            try await withCheckedThrowingContinuation { continuation in
                bridge.installCompletion(continuation)
                activeUpdateTask = updater.updateCatalog(
                    catalogInfo: info,
                    completion: bridge
                )
            }
        }
        emitProgress(progress, fraction: 1, detail: "Persistent map update complete.")
        retainedCatalogUpdateAvailable = false
        retainedCatalogCheckedAt = Date()
        downloadableRegionCache.removeAll()
        downloadableNameCache.removeAll()
    }

    func pauseActiveTransfer() async throws {
        try beginTransferControl(.pausing)
        defer { endTransferControl(.pausing) }
        if let task = activeDownloadTask, let bridge = activeDownloadBridge {
            task.pause()
            try await bridge.waitForPause()
            return
        }
        if let task = activeUpdateTask, let bridge = activeUpdateBridge {
            task.pause()
            try await bridge.waitForPause()
            return
        }
        throw OfflineMapCoreError.operationNotPausable
    }

    func resumeActiveTransfer() async throws {
        try beginTransferControl(.resuming)
        defer { endTransferControl(.resuming) }
        if let task = activeDownloadTask, let bridge = activeDownloadBridge {
            task.resume()
            try await bridge.waitForResume()
            return
        }
        if let task = activeUpdateTask, let bridge = activeUpdateBridge {
            task.resume()
            try await bridge.waitForResume()
            return
        }
        throw OfflineMapCoreError.operationNotPaused
    }

    func cancelActiveTransfer() async throws {
        if let task = activeDownloadTask, let bridge = activeDownloadBridge {
            task.cancel()
            activeDownloadTask = nil
            activeDownloadBridge = nil
            bridge.resolveCancellation()
            return
        }
        if let task = activeUpdateTask, let bridge = activeUpdateBridge {
            task.cancel()
            activeUpdateTask = nil
            activeUpdateBridge = nil
            bridge.resolveCancellation()
            return
        }
        throw OfflineMapCoreError.operationNotCancellable
    }

    func searchOffline(_ request: OfflineSearchRequest) async throws -> OfflineSearchResponse {
        try requireAppliedPolicy()
        let coverageInstallation = try requireInstalledCoverageInstallation()
        let centerResolution = try await coverageInstallation.resolver
            .resolveInstalledCoverage(for: .point(request.center))
        let centerEvidence = try HereNavigateCoverageAdmission
            .requireCompleteEvidence(
                centerResolution,
                expectedCoordinateCount: 1,
                expectedGeometryKind: .point
            )

        let searchEngine = try requireOfflineSearchEngine()
        let queryArea = TextQuery.Area(
            areaCenter: nativeCoordinate(request.center)
        )
        let textQuery = TextQuery(request.text, area: queryArea)
        guard let maximumItems = Int32(exactly: request.maximumResultCount) else {
            throw OfflineMapCoreError.invalidInput(
                "Offline search result count exceeds HERE's supported range."
            )
        }
        let options = SearchOptions(
            languageCode: .enUs,
            maxItems: maximumItems
        )
        let places: [Place] = try await withCheckedThrowingContinuation { continuation in
            _ = searchEngine.searchByText(
                textQuery,
                options: options
            ) { error, places in
                guard error == nil, let places else {
                    continuation.resume(
                        throwing: HereNavigateOfflineAdapterError.operation(
                            .searchFailed,
                            "HERE could not complete the device-local search.",
                            recovery: "Verify the signed installed region and offline-search layer, then retry."
                        )
                    )
                    return
                }
                continuation.resume(returning: places)
            }
        }

        var results: [OfflineSearchResult] = []
        var admittedEvidence = [centerEvidence]
        for (index, place) in places.prefix(request.maximumResultCount).enumerated() {
            guard let nativeCoordinates = place.geoCoordinates else {
                throw HereNavigateOfflineAdapterError.operation(
                    .invalidSDKData,
                    "HERE returned a local search result without coordinates.",
                    recovery: "Repair installed map data before retrying local search."
                )
            }
            let coordinate = try OfflineGeoCoordinate(
                latitude: nativeCoordinates.latitude,
                longitude: nativeCoordinates.longitude
            )
            let resolution = try await coverageInstallation.resolver
                .resolveInstalledCoverage(for: .point(coordinate))
            guard let resultEvidence = resolution.classification.evidence else {
                // HERE may rank a global/cache result even for a centered
                // query. Excluding it is safe; returning it as installed data
                // would not be.
                continue
            }
            _ = try HereNavigateCoverageAdmission.requireCompleteEvidence(
                resolution,
                expectedCoordinateCount: 1,
                expectedGeometryKind: .point
            )
            admittedEvidence.append(resultEvidence)
            guard let regionID = resultEvidence.regionIDs.sorted(by: {
                $0.rawValue < $1.rawValue
            }).first else {
                throw HereNavigateOfflineAdapterError.operation(
                    .coverageUnverified,
                    "HERE search coverage did not identify an installed region.",
                    recovery: "Reinstall the signed coverage catalog and native HERE region."
                )
            }
            results.append(
                try OfflineSearchResult(
                    id: offlineSearchResultID(
                        index: index,
                        coordinate: coordinate
                    ),
                    title: place.title,
                    address: place.address.addressText,
                    coordinate: coordinate,
                    categories: [],
                    regionID: regionID
                )
            )
        }
        let responseEvidence = try HereNavigateCoverageAdmission.unionEvidence(
            admittedEvidence
        )
        return try OfflineSearchResponse(
            results: results,
            coverage: responseEvidence
        )
    }

    func calculateOfflineRoute(_ request: OfflineRouteRequest) async throws -> OfflineRouteResponse {
        guard request.mode.supportsHEREOfflineCalculation else {
            throw OfflineMapCoreError.unsupportedLocalRouting(request.mode)
        }
        try requireAppliedPolicy()
        let coverageInstallation = try requireInstalledCoverageInstallation()
        let requestedCorridor = try OfflineCoverageRequestGeometry.routeCorridor(
            coordinates: request.waypoints.map(\.coordinate),
            halfWidthMeters: coverageInstallation.routeCorridorHalfWidthMeters
        )
        let requestedResolution = try await coverageInstallation.resolver
            .resolveInstalledCoverage(for: requestedCorridor)
        _ = try HereNavigateCoverageAdmission.requireCompleteEvidence(
            requestedResolution,
            expectedCoordinateCount: request.waypoints.count,
            expectedGeometryKind: .routeCorridor
        )

        let routingEngine = try requireOfflineRoutingEngine()
        let nativeWaypoints = request.waypoints.map {
            Waypoint(coordinates: nativeCoordinate($0.coordinate))
        }
        let options = try routingOptions(for: request)
        let nativeRoutes: [Route] = try await withCheckedThrowingContinuation { continuation in
            _ = routingEngine.calculateRoute(
                with: nativeWaypoints,
                options: options
            ) { error, routes in
                guard error == nil, let routes, !routes.isEmpty else {
                    continuation.resume(
                        throwing: HereNavigateOfflineAdapterError.operation(
                            .routingFailed,
                            "HERE could not calculate a device-local road route.",
                            recovery: "Verify complete signed corridor coverage and the offline-routing layer, then retry."
                        )
                    )
                    return
                }
                continuation.resume(returning: routes)
            }
        }

        var admitted: [(
            model: OfflineLocalRoute,
            native: HereNativeRouteBox,
            evidence: OfflineInstalledCoverageEvidence
        )] = []
        for (index, nativeRoute) in nativeRoutes.enumerated() {
            let coordinates = try routeCoordinates(nativeRoute)
            let corridor = try OfflineCoverageRequestGeometry.routeCorridor(
                coordinates: coordinates,
                halfWidthMeters: coverageInstallation.routeCorridorHalfWidthMeters
            )
            let resolution = try await coverageInstallation.resolver
                .resolveInstalledCoverage(for: corridor)
            guard resolution.classification.evidence != nil else {
                continue
            }
            let evidence = try HereNavigateCoverageAdmission
                .requireCompleteEvidence(
                    resolution,
                    expectedCoordinateCount: coordinates.count,
                    expectedGeometryKind: .routeCorridor
                )
            let routeID = "\(request.id.uuidString.lowercased())-\(index)"
            admitted.append(
                (
                    model: try mapRoute(
                        nativeRoute,
                        routeID: routeID,
                        mode: request.mode,
                        coverage: evidence
                    ),
                    native: HereNativeRouteBox(
                        route: nativeRoute,
                        mode: request.mode
                    ),
                    evidence: evidence
                )
            )
        }
        guard !admitted.isEmpty else {
            throw HereNavigateOfflineAdapterError.operation(
                .coverageUnverified,
                "No calculated HERE route remained completely inside signed installed-region coverage.",
                recovery: "Install every region covering the route corridor or choose a destination within current coverage."
            )
        }
        let responseEvidence = try HereNavigateCoverageAdmission.unionEvidence(
            admitted.map(\.evidence)
        )
        let response = try OfflineRouteResponse(
            requestID: request.id,
            routes: admitted.map(\.model),
            coverage: responseEvidence
        )
        for value in admitted {
            await routeStore.store(value.native, id: value.model.id)
        }
        return response
    }

    private func requireAppliedPolicy() throws {
        guard appliedPolicy != nil, SDKNativeEngine.sharedInstance != nil else {
            throw HereNavigateOfflineAdapterError.runtime(
                "HERE offline maps have not been prepared.",
                recovery: "Prepare the offline map coordinator before using map services."
            )
        }
    }

    private func beginMutation(_ mutation: OfflineMapOperationKind) throws {
        guard let activeMutation else {
            self.activeMutation = mutation
            return
        }
        throw OfflineMapCoreError.busy(activeOperation: activeMutation)
    }

    private func endMutation(_ mutation: OfflineMapOperationKind) {
        guard activeMutation == mutation else { return }
        activeMutation = nil
    }

    private func beginTransferControl(_ phase: OfflineMapOperationPhase) throws {
        guard activeTransferControl == nil else {
            throw HereNavigateOfflineAdapterError.operation(
                .transferControlUnavailable,
                "Another HERE map-transfer control is awaiting native confirmation.",
                recovery: "Wait for the current pause or resume command before retrying."
            )
        }
        activeTransferControl = phase
    }

    private func endTransferControl(_ phase: OfflineMapOperationPhase) {
        guard activeTransferControl == phase else { return }
        activeTransferControl = nil
    }

    private func requireConnectedCatalogAccess() throws {
        try requireAppliedPolicy()
        guard appliedPolicy != .radioSilent else {
            throw HereNavigateOfflineAdapterError.operation(
                .catalogUnavailable,
                "Region catalogs, downloads, and updates require an explicit connected session.",
                recovery: "Temporarily allow connectivity, finish map maintenance, then return to radio silence."
            )
        }
    }

    private func requireInstalledCoverageInstallation() throws
        -> HereNavigateInstalledCoverageInstallation {
        guard let installation = HereNavigateInstalledCoverageAuthority.shared
            .currentInstallation() else {
            throw HereNavigateOfflineAdapterError.operation(
                .coverageUnverified,
                "Signed HERE installed-region coverage is not installed for this process.",
                recovery: "Bundle and approve the signed coverage catalog matching the native HERE inventory."
            )
        }
        return installation
    }

    private func requireMapDownloader() async throws -> MapDownloader {
        try requireAppliedPolicy()
        if let mapDownloader { return mapDownloader }
        guard let nativeEngine = SDKNativeEngine.sharedInstance else {
            throw HereNavigateOfflineAdapterError.runtime(
                "The HERE native engine is unavailable.",
                recovery: "Restart offline maps."
            )
        }
        let downloader: MapDownloader? = await withCheckedContinuation { continuation in
            MapDownloader.fromEngineAsync(nativeEngine) { continuation.resume(returning: $0) }
        }
        guard let downloader else {
            throw HereNavigateOfflineAdapterError.operation(
                .lifecycleUnavailable,
                "HERE map lifecycle services could not initialize.",
                recovery: "Verify the Navigate entitlement and restart offline maps."
            )
        }
        mapDownloader = downloader
        return downloader
    }

    private func requireMapUpdater() async throws -> MapUpdater {
        try requireAppliedPolicy()
        if let mapUpdater { return mapUpdater }
        guard let nativeEngine = SDKNativeEngine.sharedInstance else {
            throw HereNavigateOfflineAdapterError.runtime(
                "The HERE native engine is unavailable.",
                recovery: "Restart offline maps."
            )
        }
        let updater: MapUpdater? = await withCheckedContinuation { continuation in
            MapUpdater.fromEngineAsync(nativeEngine) { continuation.resume(returning: $0) }
        }
        guard let updater else {
            throw HereNavigateOfflineAdapterError.operation(
                .lifecycleUnavailable,
                "HERE map update services could not initialize.",
                recovery: "Verify the Navigate entitlement and restart offline maps."
            )
        }
        mapUpdater = updater
        return updater
    }

    private func requireOfflineSearchEngine() throws -> OfflineSearchEngine {
        try requireAppliedPolicy()
        if let offlineSearchEngine { return offlineSearchEngine }
        do {
            let engine = try OfflineSearchEngine()
            offlineSearchEngine = engine
            return engine
        } catch {
            throw HereNavigateOfflineAdapterError.operation(
                .searchUnavailable,
                "HERE offline search could not initialize.",
                recovery: "Verify the offline-search entitlement and persistent layer configuration."
            )
        }
    }

    private func requireOfflineRoutingEngine() throws -> OfflineRoutingEngine {
        try requireAppliedPolicy()
        if let offlineRoutingEngine { return offlineRoutingEngine }
        do {
            let engine = try OfflineRoutingEngine()
            offlineRoutingEngine = engine
            return engine
        } catch {
            throw HereNavigateOfflineAdapterError.operation(
                .routingUnavailable,
                "HERE offline routing could not initialize.",
                recovery: "Verify the offline-routing entitlement and persistent layer configuration."
            )
        }
    }

    private func catalogUpdateInfo() async throws -> [CatalogUpdateInfo] {
        let updater = try await requireMapUpdater()
        return try await withCheckedThrowingContinuation { continuation in
            _ = updater.retrieveCatalogsUpdateInfo { error, infos in
                guard error == nil, let infos else {
                    continuation.resume(
                        throwing: HereNavigateOfflineAdapterError.operation(
                            .updateFailed,
                            "HERE could not inspect persistent map updates.",
                            recovery: "Reconnect and retry the update check."
                        )
                    )
                    return
                }
                continuation.resume(returning: infos)
            }
        }
    }

    private func persistentHealth(
        downloader: MapDownloader,
        updater: MapUpdater
    ) -> OfflinePersistentMapHealth {
        guard downloader.getInitialPersistentMapStatus() == .ok else {
            return .needsRepair(reason: "HERE reports that the persistent map needs recovery.")
        }
        let version = (try? updater.getCurrentMapVersion()
            .stringRepresentation(separator: "."))
            .flatMap(sanitizedRegionName)
        return .healthy(catalogVersion: version, verifiedAt: Date())
    }

    private func flatten(
        region: Region,
        parentID: OfflineMapRegionID?,
        depth: Int,
        models: inout [OfflineMapDownloadableRegion]
    ) throws {
        guard depth <= 16 else {
            throw HereNavigateOfflineAdapterError.operation(
                .invalidSDKData,
                "HERE returned an invalid downloadable-region hierarchy.",
                recovery: "Reconnect and refresh the region catalog."
            )
        }
        let id = try OfflineMapRegionID(region.regionId.id)
        guard downloadableRegionCache[id.rawValue] == nil else {
            throw HereNavigateOfflineAdapterError.operation(
                .invalidSDKData,
                "HERE returned duplicate identifiers in the downloadable-region catalog.",
                recovery: "Reconnect and refresh the region catalog."
            )
        }
        guard let name = sanitizedRegionName(region.name) else {
            throw HereNavigateOfflineAdapterError.operation(
                .invalidSDKData,
                "HERE returned an invalid downloadable-region name.",
                recovery: "Reconnect and refresh the region catalog."
            )
        }
        let children = region.childRegions ?? []
        downloadableRegionCache[id.rawValue] = region
        downloadableNameCache[id.rawValue] = name
        models.append(
            try OfflineMapDownloadableRegion(
                id: id,
                name: name,
                level: regionLevel(depth: depth, hasChildren: !children.isEmpty),
                parentID: parentID,
                childCount: children.count,
                estimatedDownloadBytes: adding(
                    checkedInt64(region.sizeOnDiskInBytes),
                    checkedInt64(region.sizeOnNetworkInBytes)
                )
            )
        )
        for child in children {
            try flatten(region: child, parentID: id, depth: depth + 1, models: &models)
        }
    }

    private func regionLevel(depth: Int, hasChildren: Bool) -> OfflineMapRegionLevel {
        switch depth {
        case 0: return .continent
        case 1: return .country
        case 2: return .stateOrProvince
        case 3: return .county
        default: return hasChildren ? .other : .city
        }
    }

    private func routingOptions(for request: OfflineRouteRequest) throws -> RoutingOptions {
        var options = RoutingOptions()
        options.routeOptions.trafficOptimizationMode = .disabled
        options.routeOptions.departureTime = request.departureTime

        switch request.mode {
        case .road:
            options.transportSpecification.transportMode = .car
        case .truck:
            guard let constraints = request.truckConstraints else {
                throw HereNavigateOfflineAdapterError.operation(
                    .invalidTruckProfile,
                    "Truck routing requires a complete explicit truck profile.",
                    recovery: "Select the vehicle type, restriction category, dimensions, and cargo restrictions."
                )
            }
            try validateTruckIdentity(constraints)
            let builder = VehicleSpecification.TruckBuilder()
                .withTruckCategory(nativeTruckCategory(constraints.truckCategory))
            if let value = constraints.grossWeightKilograms {
                builder.withGrossWeightInKilograms(try checkedTruckInt32(value))
            }
            if let value = constraints.weightPerAxleKilograms {
                builder.withWeightPerAxleInKilograms(try checkedTruckInt32(value))
            }
            if let value = constraints.heightCentimeters {
                builder.withHeightInCentimeters(try checkedTruckInt32(value))
            }
            if let value = constraints.widthCentimeters {
                builder.withWidthInCentimeters(try checkedTruckInt32(value))
            }
            if let value = constraints.lengthCentimeters {
                builder.withLengthInCentimeters(try checkedTruckInt32(value))
            }
            if let value = constraints.axleCount {
                builder.withAxleCount(try checkedTruckInt32(value))
            }
            if let value = constraints.trailerCount {
                builder.withTrailerCount(try checkedTruckInt32(value))
            }
            if let tunnel = constraints.tunnelCategory {
                builder.withTunnelCategory(nativeTunnelCategory(tunnel))
            }
            if !constraints.hazardousGoods.isEmpty {
                builder.withHazardousMaterials(
                    constraints.hazardousGoods.map(nativeHazardousMaterial)
                )
            }
            options.transportSpecification = TransportSpecification.TruckBuilder()
                .withVehicleSpecification(builder.build())
                .build()
        case .rail, .vessel:
            throw OfflineMapCoreError.unsupportedLocalRouting(request.mode)
        }
        return options
    }

    private func validateTruckIdentity(_ constraints: OfflineTruckConstraints) throws {
        let valid: Bool
        switch (constraints.truckType, constraints.truckCategory) {
        case (.straight, .straight):
            valid = true
        case (.tractor, .tractor):
            valid = true
        default:
            valid = false
        }
        guard valid else {
            throw HereNavigateOfflineAdapterError.operation(
                .invalidTruckProfile,
                "The selected truck type and restriction category are inconsistent.",
                recovery: "HERE 4.27 can represent only straight/straight and tractor/tractor without losing category identity."
            )
        }
    }

    private func nativeTruckCategory(_ value: OfflineTruckCategory) -> TruckCategory {
        switch value {
        case .straight: return .straight
        case .tractor: return .tractor
        }
    }

    private func nativeTunnelCategory(_ value: OfflineTruckTunnelCategory) -> TunnelCategory {
        switch value {
        case .b: return .b
        case .c: return .c
        case .d: return .d
        case .e: return .e
        }
    }

    private func nativeHazardousMaterial(_ value: OfflineHazardousGoodsClass) -> HazardousMaterial {
        switch value {
        case .explosive: return .explosive
        case .gas: return .gas
        case .flammable: return .flammable
        case .combustible: return .combustible
        case .organic: return .organic
        case .poison: return .poison
        case .radioActive: return .radioactive
        case .corrosive: return .corrosive
        case .poisonousInhalation: return .poisonousInhalation
        case .harmfulToWater: return .harmfulToWater
        case .other: return .other
        }
    }

    private func checkedTruckInt32(_ value: Int) throws -> Int32 {
        guard let result = Int32(exactly: value) else {
            throw HereNavigateOfflineAdapterError.operation(
                .invalidTruckProfile,
                "A truck profile value exceeds HERE's supported numeric range.",
                recovery: "Correct the vehicle dimensions, weights, axle count, or trailer count."
            )
        }
        return result
    }

    private func mapRoute(
        _ route: Route,
        routeID: String,
        mode: OfflineRouteMode,
        coverage: OfflineInstalledCoverageEvidence
    ) throws -> OfflineLocalRoute {
        var sequence = 0
        var sections: [OfflineRouteSection] = []
        var notices: [String] = []
        for section in route.sections {
            let coordinates = try section.geometry.vertices.map {
                try OfflineGeoCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            }
            var maneuvers: [OfflineRouteManeuver] = []
            for maneuver in section.maneuvers {
                let instruction = maneuver.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !instruction.isEmpty else { continue }
                maneuvers.append(
                    try OfflineRouteManeuver(
                        sequence: sequence,
                        instruction: instruction,
                        coordinate: OfflineGeoCoordinate(
                            latitude: maneuver.coordinates.latitude,
                            longitude: maneuver.coordinates.longitude
                        ),
                        distanceFromStartMeters: nil
                    )
                )
                sequence += 1
            }
            notices.append(
                contentsOf: section.sectionNotices.map { _ in
                    "HERE reported a local route restriction or preference notice."
                }
            )
            sections.append(
                try OfflineRouteSection(
                    coordinates: coordinates,
                    maneuvers: maneuvers,
                    summary: OfflineRouteSummary(
                        distanceMeters: try checkedRouteDistance(
                            section.lengthInMeters
                        ),
                        durationSeconds: checkedDuration(section.duration)
                    )
                )
            )
        }
        return try OfflineLocalRoute(
            id: routeID,
            mode: mode,
            sections: sections,
            summary: OfflineRouteSummary(
                distanceMeters: try checkedRouteDistance(route.lengthInMeters),
                durationSeconds: checkedDuration(route.duration)
            ),
            notices: notices,
            coverage: coverage
        )
    }

    private func routeCoordinates(
        _ route: Route
    ) throws -> [OfflineGeoCoordinate] {
        let coordinates = try route.sections.flatMap { section in
            try section.geometry.vertices.map { value in
                try OfflineGeoCoordinate(
                    latitude: value.latitude,
                    longitude: value.longitude
                )
            }
        }
        guard coordinates.count >= 2 else {
            throw HereNavigateOfflineAdapterError.operation(
                .invalidSDKData,
                "HERE returned a local route without usable corridor geometry.",
                recovery: "Repair installed map data before retrying the route."
            )
        }
        return coordinates
    }

    private func offlineSearchResultID(
        index: Int,
        coordinate: OfflineGeoCoordinate
    ) -> String {
        let latitude = coordinate.latitude.bitPattern
        let longitude = coordinate.longitude.bitPattern
        return "here-offline-\(latitude)-\(longitude)-\(index)"
    }

    private func nativeCoordinate(_ coordinate: OfflineGeoCoordinate) -> GeoCoordinates {
        GeoCoordinates(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private func checkedDuration(_ duration: Double) throws -> Int64 {
        guard duration.isFinite, duration >= 0, duration <= Double(Int64.max) else {
            throw HereNavigateOfflineAdapterError.operation(
                .invalidSDKData,
                "HERE returned an invalid local route duration.",
                recovery: "Repair installed map data and retry the route."
            )
        }
        return Int64(duration.rounded())
    }

    private func checkedRouteDistance<T: BinaryInteger>(_ value: T) throws -> Int64 {
        guard let result = Int64(exactly: value), result >= 0 else {
            throw HereNavigateOfflineAdapterError.operation(
                .invalidSDKData,
                "HERE returned an invalid local route distance.",
                recovery: "Repair installed map data and retry the route."
            )
        }
        return result
    }

    private func checkedInt64<T: BinaryInteger>(_ value: T) throws -> Int64 {
        guard let result = Int64(exactly: value), result >= 0 else {
            throw HereNavigateOfflineAdapterError.operation(
                .invalidSDKData,
                "HERE returned an invalid local byte count.",
                recovery: "Restart offline maps and retry the operation."
            )
        }
        return result
    }

    private func adding(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else {
            throw HereNavigateOfflineAdapterError.operation(
                .invalidSDKData,
                "HERE map size estimates exceeded the supported range.",
                recovery: "Select fewer regions and retry."
            )
        }
        return result
    }

    private func deviceAvailableBytes() throws -> Int64 {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        do {
            let values = try home.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            )
            guard let bytes = values.volumeAvailableCapacityForImportantUsage, bytes >= 0 else {
                throw CocoaError(.fileReadUnknown)
            }
            return bytes
        } catch {
            throw HereNavigateOfflineAdapterError.operation(
                .storageUnavailable,
                "The operating system did not provide available device storage.",
                recovery: "Free device storage and retry the preflight."
            )
        }
    }

    private func persistDownloadableRegionNames() throws {
        let sanitized = downloadableNameCache.reduce(into: [String: String]()) { result, pair in
            guard (try? OfflineMapRegionID(pair.key)) != nil,
                  let name = sanitizedRegionName(pair.value) else { return }
            result[pair.key] = name
        }
        let catalog = HerePersistedRegionNameCatalog(
            formatVersion: 1,
            namesByRegionID: sanitized
        )
        do {
            let paths = try HereSDKRuntimePaths()
            try paths.prepare()
            let url = paths.root.appendingPathComponent(
                "region-catalog-names-v1.json",
                isDirectory: false
            )
            let data = try JSONEncoder().encode(catalog)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = url
            try mutableURL.setResourceValues(values)
        } catch {
            throw HereNavigateOfflineAdapterError.operation(
                .storageUnavailable,
                "HERE region metadata could not be saved for radio-silent inventory.",
                recovery: "Verify application-support storage, then refresh the connected region catalog."
            )
        }
    }

    private func loadPersistedRegionNamesIfNeeded() {
        guard downloadableNameCache.isEmpty,
              let paths = try? HereSDKRuntimePaths() else { return }
        let url = paths.root.appendingPathComponent(
            "region-catalog-names-v1.json",
            isDirectory: false
        )
        guard let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(
                HerePersistedRegionNameCatalog.self,
                from: data
              ),
              catalog.formatVersion == 1 else { return }
        downloadableNameCache = catalog.namesByRegionID.reduce(into: [:]) { result, pair in
            guard (try? OfflineMapRegionID(pair.key)) != nil,
                  let name = sanitizedRegionName(pair.value) else { return }
            result[pair.key] = name
        }
    }

    private func sanitizedRegionName(_ value: String) -> String? {
        let withoutControls = value
            .components(separatedBy: .controlCharacters)
            .joined()
        let collapsed = withoutControls
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(160))
    }

    private func emitProgress(
        _ handler: OfflineMapProgressHandler,
        fraction: Double,
        detail: String
    ) {
        guard let value = try? OfflineMapTransferProgress(
            fractionCompleted: fraction,
            detail: detail
        ) else { return }
        handler(value)
    }

    private func resetSDKServices() async {
        activeDownloadTask?.cancel()
        activeUpdateTask?.cancel()
        activeDownloadBridge?.resolveCancellation()
        activeUpdateBridge?.resolveCancellation()
        activeDownloadTask = nil
        activeDownloadBridge = nil
        activeUpdateTask = nil
        activeUpdateBridge = nil
        activeTransferControl = nil
        mapDownloader = nil
        mapUpdater = nil
        offlineSearchEngine = nil
        offlineRoutingEngine = nil
        downloadableRegionCache.removeAll()
        downloadableNameCache.removeAll()
        await routeStore.removeAll()
    }

    private func runtimeError(
        for availability: HereSDKRuntimeAvailability
    ) -> HereNavigateOfflineAdapterError {
        switch availability {
        case .missingFramework:
            return .missingFramework
        case .missingCredentials:
            return .runtime(
                "HERE offline maps are not provisioned for this build.",
                recovery: "Provision the HERE access-key pair through the private build configuration."
            )
        case .missingLegalNotice:
            return .runtime(
                "The required HERE legal notice is not bundled.",
                recovery: "Bundle HERE_NOTICE before enabling offline maps."
            )
        case .storageUnavailable:
            return .runtime(
                "HERE persistent map storage is unavailable.",
                recovery: "Verify application-support storage and device free space."
            )
        case .initializationFailed, .stopped:
            return .runtime(
                "HERE offline maps could not start.",
                recovery: "Restart the native map runtime and verify the Navigate entitlement."
            )
        case .ready:
            return .runtime(
                "HERE started with a connectivity mode that does not match the request.",
                recovery: "Restart offline maps with the requested connectivity policy."
            )
        }
    }

    private func blocker(for error: Error) -> OfflineMapReadinessBlocker {
        if let failure = error as? HereNavigateOfflineAdapterError {
            let blockerCode: OfflineMapReadinessBlockerCode
            switch failure.code {
            case .missingFramework:
                blockerCode = .sdkUnavailable
            case .radioSilenceFailed:
                blockerCode = .radioSilenceNotEnforced
            case .storageUnavailable:
                blockerCode = .persistentMapUnavailable
            default:
                blockerCode = .sdkInitializationFailed
            }
            return .init(
                code: blockerCode,
                message: failure.message,
                recovery: failure.recovery
            )
        }
        return .init(
            code: .sdkInitializationFailed,
            message: "HERE offline maps could not be inspected.",
            recovery: "Restart offline maps and retry the readiness check."
        )
    }
}

#else

actor HereNavigateOfflineEngine: OfflineMapEngine, HEREInstalledRegionInventoryProviding {
    static let shared = HereNavigateOfflineEngine()

    init() {}

    func makeNavigationSession(
        locationPolicy: HereNavigationLocationAcceptancePolicy = .production,
        voicePolicy: HereNavigationVoicePolicy = .requiredEnglishUS,
        coverageResolver: (any OfflineInstalledCoverageResolving)? = nil,
        routeCorridorHalfWidthMeters: Double = 75
    ) -> HereNavigateNavigationSession {
        HereNavigateNavigationSession(
            locationPolicy: locationPolicy,
            voicePolicy: voicePolicy,
            coverageResolver: coverageResolver,
            routeCorridorHalfWidthMeters: routeCorridorHalfWidthMeters
        )
    }

    func purgeRetainedLocalRoutes() async {}

    func inspect(
        connectivityPolicy: OfflineMapConnectivityPolicy
    ) async -> OfflineMapEngineInspection {
        let message = HereNavigateOfflineAdapterError.missingFramework.message
        return OfflineMapEngineInspection(
            capabilities: [],
            blockers: [
                .init(
                    code: .sdkUnavailable,
                    message: message,
                    recovery: HereNavigateOfflineAdapterError.missingFramework.recovery
                )
            ],
            persistentHealth: .unusable(reason: message),
            radioSilenceState: connectivityPolicy == .radioSilent
                ? .notEnforced(reason: message)
                : .notRequested
        )
    }

    func applyConnectivityPolicy(
        _ policy: OfflineMapConnectivityPolicy
    ) async throws -> OfflineMapRadioSilenceState {
        _ = policy
        _ = await MainActor.run {
            HereSDKRuntime.shared.start(connectivity: .radioSilent)
        }
        throw HereNavigateOfflineAdapterError.missingFramework
    }

    func downloadableRegions() async throws -> [OfflineMapDownloadableRegion] {
        throw HereNavigateOfflineAdapterError.missingFramework
    }

    func installedRegions() async throws -> [OfflineMapInstalledRegion] {
        throw HereNavigateOfflineAdapterError.missingFramework
    }

    func currentHEREInstalledRegionInventory() async throws
        -> HEREInstalledRegionInventory {
        throw HereNavigateOfflineAdapterError.missingFramework
    }

    func storageSnapshot() async throws -> OfflineMapStorageSnapshot {
        throw HereNavigateOfflineAdapterError.missingFramework
    }

    func downloadByteEstimate(
        for regionIDs: [OfflineMapRegionID]
    ) async throws -> OfflineMapByteEstimate? {
        _ = regionIDs
        throw HereNavigateOfflineAdapterError.missingFramework
    }

    func persistentMapUpdateByteEstimate() async throws -> OfflineMapByteEstimate? {
        throw HereNavigateOfflineAdapterError.missingFramework
    }

    func downloadRegions(
        _ regionIDs: [OfflineMapRegionID],
        progress: @escaping OfflineMapProgressHandler
    ) async throws {
        _ = regionIDs
        _ = progress
        throw HereNavigateOfflineAdapterError.missingFramework
    }

    func deleteRegions(
        _ regionIDs: [OfflineMapRegionID],
        progress: @escaping OfflineMapProgressHandler
    ) async throws {
        _ = regionIDs
        _ = progress
        throw HereNavigateOfflineAdapterError.missingFramework
    }

    func repairPersistentMap(
        progress: @escaping OfflineMapProgressHandler
    ) async throws {
        _ = progress
        throw HereNavigateOfflineAdapterError.missingFramework
    }

    func updatePersistentMap(
        progress: @escaping OfflineMapProgressHandler
    ) async throws {
        _ = progress
        throw HereNavigateOfflineAdapterError.missingFramework
    }

    func pauseActiveTransfer() async throws {
        throw HereNavigateOfflineAdapterError.missingFramework
    }

    func resumeActiveTransfer() async throws {
        throw HereNavigateOfflineAdapterError.missingFramework
    }

    func cancelActiveTransfer() async throws {
        throw HereNavigateOfflineAdapterError.missingFramework
    }

    func searchOffline(_ request: OfflineSearchRequest) async throws -> OfflineSearchResponse {
        _ = request
        throw HereNavigateOfflineAdapterError.missingFramework
    }

    func calculateOfflineRoute(_ request: OfflineRouteRequest) async throws -> OfflineRouteResponse {
        _ = request
        throw HereNavigateOfflineAdapterError.missingFramework
    }
}

#endif

/// The one app-scoped observable owner for HERE map-management state. Multiple
/// SwiftUI windows observe this object instead of competing for
/// `OfflineMapCoordinator.onSnapshotChange`, which is intentionally a single
/// core callback. Operations still go through the same retained coordinator.
@MainActor
final class OfflineMapCompositionOwner: ObservableObject {
    let coordinator: OfflineMapCoordinator
    @Published private(set) var snapshot: OfflineMapSnapshot
    private var coordinatorObservationID: UUID?

    fileprivate init(coordinator: OfflineMapCoordinator) {
        self.coordinator = coordinator
        snapshot = coordinator.snapshot
        coordinatorObservationID = coordinator.addSnapshotObserver { [weak self] snapshot in
            self?.snapshot = snapshot
        }
    }
}

@MainActor
enum OfflineMapComposition {
    static func makeOwner(
        storagePolicy: OfflineMapStoragePolicy,
        connectivityPolicy: OfflineMapConnectivityPolicy = .radioSilent,
        requiredCapabilities: OfflineMapCapabilities = .fullRoadFreightParity
    ) -> OfflineMapCompositionOwner {
        OfflineMapCompositionSupervisor.shared.owner(
            storagePolicy: storagePolicy,
            connectivityPolicy: connectivityPolicy,
            requiredCapabilities: requiredCapabilities
        )
    }

    static func makeCoordinator(
        storagePolicy: OfflineMapStoragePolicy,
        connectivityPolicy: OfflineMapConnectivityPolicy = .radioSilent,
        requiredCapabilities: OfflineMapCapabilities = .fullRoadFreightParity
    ) -> OfflineMapCoordinator {
        makeOwner(
            storagePolicy: storagePolicy,
            connectivityPolicy: connectivityPolicy,
            requiredCapabilities: requiredCapabilities
        ).coordinator
    }

    static func makeNavigationSession(
        locationPolicy: HereNavigationLocationAcceptancePolicy = .production,
        voicePolicy: HereNavigationVoicePolicy = .requiredEnglishUS,
        coverageResolver: (any OfflineInstalledCoverageResolving)? = nil,
        routeCorridorHalfWidthMeters: Double = 75
    ) -> HereNavigateNavigationSession {
        #if canImport(heresdk)
        HereNavigateNavigationSession(
            routeStore: .shared,
            locationPolicy: locationPolicy,
            voicePolicy: voicePolicy,
            coverageResolver: coverageResolver,
            routeCorridorHalfWidthMeters: routeCorridorHalfWidthMeters
        )
        #else
        HereNavigateNavigationSession(
            locationPolicy: locationPolicy,
            voicePolicy: voicePolicy,
            coverageResolver: coverageResolver,
            routeCorridorHalfWidthMeters: routeCorridorHalfWidthMeters
        )
        #endif
    }
}

/// App-scoped owner for the single observable coordinator. Reopening Settings
/// rejoins its live snapshot and transfer controls instead of manufacturing a
/// second state machine around HERE's process-global SDK. The first composition
/// establishes immutable storage/capability policy; later views intentionally
/// receive that same coordinator even if they repeat factory defaults.
@MainActor
private final class OfflineMapCompositionSupervisor {
    static let shared = OfflineMapCompositionSupervisor()

    private var retainedOwner: OfflineMapCompositionOwner?

    private init() {}

    func owner(
        storagePolicy: OfflineMapStoragePolicy,
        connectivityPolicy: OfflineMapConnectivityPolicy,
        requiredCapabilities: OfflineMapCapabilities
    ) -> OfflineMapCompositionOwner {
        if let retainedOwner {
            return retainedOwner
        }
        let coordinator = OfflineMapCoordinator(
            engine: HereNavigateOfflineEngine.shared,
            storagePolicy: storagePolicy,
            requiredCapabilities: requiredCapabilities,
            connectivityPolicy: connectivityPolicy
        )
        let owner = OfflineMapCompositionOwner(coordinator: coordinator)
        retainedOwner = owner
        return owner
    }
}
