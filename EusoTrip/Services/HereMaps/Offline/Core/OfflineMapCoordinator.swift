//
//  OfflineMapCoordinator.swift
//  EusoTrip
//
//  Main-actor state machine for all persistent-map mutations. The coordinator
//  admits exactly one root mutation at a time and treats pause/resume/cancel as
//  controls on that same operation, never as independent background work.
//

import Foundation

final class OfflineMapProgressSequencer: @unchecked Sendable {
    private let lock = NSLock()
    private var sequence: UInt64 = 0
    private var pending: [(sequence: UInt64, progress: OfflineMapTransferProgress)] = []

    @discardableResult
    func enqueue(_ progress: OfflineMapTransferProgress) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        if sequence < UInt64.max { sequence += 1 }
        pending.append((sequence, progress))
        return sequence
    }

    func drain() -> [(sequence: UInt64, progress: OfflineMapTransferProgress)] {
        lock.lock()
        defer { lock.unlock() }
        let drained = pending.sorted { $0.sequence < $1.sequence }
        pending.removeAll(keepingCapacity: true)
        return drained
    }
}

@MainActor
final class OfflineMapCoordinator {
    private enum Admission: Equatable {
        case idle
        case inventoryRefresh
        case policyTransition
        case storagePreflight
        case localRead

        var description: String {
            switch self {
            case .idle: return "command"
            case .inventoryRefresh: return "inventory refresh"
            case .policyTransition: return "connectivity transition"
            case .storagePreflight: return "storage preflight"
            case .localRead: return "local search or routing"
            }
        }
    }

    private(set) var snapshot: OfflineMapSnapshot {
        didSet {
            onSnapshotChange?(snapshot)
            for observer in Array(snapshotObservers.values) {
                observer(snapshot)
            }
        }
    }

    var onSnapshotChange: ((OfflineMapSnapshot) -> Void)? {
        didSet { onSnapshotChange?(snapshot) }
    }

    private var snapshotObservers: [UUID: (OfflineMapSnapshot) -> Void] = [:]

    @discardableResult
    func addSnapshotObserver(
        _ observer: @escaping (OfflineMapSnapshot) -> Void
    ) -> UUID {
        let id = UUID()
        snapshotObservers[id] = observer
        observer(snapshot)
        return id
    }

    func removeSnapshotObserver(_ id: UUID) {
        snapshotObservers.removeValue(forKey: id)
    }

    private let engine: any OfflineMapEngine
    private let requiredCapabilities: OfflineMapCapabilities
    private let storagePolicy: OfflineMapStoragePolicy
    private var inspectedCapabilities: OfflineMapCapabilities = []
    private var admission: Admission = .idle
    private var cancellationRequested = Set<UUID>()
    private var lastAppliedProgressSequence: UInt64 = 0

    init(
        engine: any OfflineMapEngine,
        storagePolicy: OfflineMapStoragePolicy,
        requiredCapabilities: OfflineMapCapabilities = .fullRoadFreightParity,
        connectivityPolicy: OfflineMapConnectivityPolicy = .radioSilent
    ) {
        self.engine = engine
        self.storagePolicy = storagePolicy
        self.requiredCapabilities = requiredCapabilities
        var initial = OfflineMapSnapshot()
        initial.connectivityPolicy = connectivityPolicy
        initial.radioSilenceState = .notRequested
        snapshot = initial
    }

    /// Applies the connectivity policy, inspects the native engine, and loads
    /// the real region inventory. Failures remain visible in `snapshot`.
    func prepare() async {
        guard snapshot.activeOperation == nil, admission == .idle else { return }
        admission = .inventoryRefresh
        defer { admission = .idle }
        snapshot.readiness = .checking
        snapshot.lastFailure = nil

        let requestedPolicy = snapshot.connectivityPolicy
        if requestedPolicy == .radioSilent {
            snapshot.radioSilenceState = .applying
        }

        var policyFailure: OfflineMapFailure?
        do {
            snapshot.radioSilenceState = try await engine.applyConnectivityPolicy(requestedPolicy)
        } catch {
            let failure = normalizedFailure(error, fallbackCode: "connectivity_policy_failed")
            policyFailure = failure
            snapshot.lastFailure = failure
            snapshot.radioSilenceState = .notEnforced(reason: failure.message)
        }

        let inspection = await engine.inspect(connectivityPolicy: requestedPolicy)
        inspectedCapabilities = inspection.capabilities
        snapshot.availableCapabilities = inspection.capabilities
        snapshot.persistentHealth = inspection.persistentHealth
        if policyFailure == nil {
            snapshot.radioSilenceState = inspection.radioSilenceState
        }

        var blockers = inspection.blockers
        blockers.append(contentsOf: readinessBlockers(for: inspection.persistentHealth))
        if requestedPolicy == .radioSilent {
            switch snapshot.radioSilenceState {
            case .enforced:
                break
            case .notEnforced(let reason):
                blockers.append(
                    .init(
                        code: .radioSilenceNotEnforced,
                        message: reason,
                        recovery: "Retry after the native offline engine can enforce radio silence."
                    )
                )
            case .notRequested, .applying:
                blockers.append(
                    .init(
                        code: .radioSilenceNotEnforced,
                        message: "Radio silence has not been confirmed by the offline map engine.",
                        recovery: "Retry offline initialization before departure."
                    )
                )
            }
        }

        blockers = deduplicatedBlockers(blockers)
        if !blockers.isEmpty {
            snapshot.readiness = .blocked(blockers)
            let inventoryFailures = await reloadInventory()
            if snapshot.lastFailure == nil {
                snapshot.lastFailure = inventoryFailures.first
            }
            return
        }

        applyReadiness(for: inspection.capabilities)

        let inventoryFailures = await reloadInventory()
        snapshot.lastFailure = inventoryFailures.first
    }

    func refresh() async throws {
        guard snapshot.activeOperation == nil else {
            throw OfflineMapCoreError.busy(activeOperation: snapshot.activeOperation!.kind)
        }
        guard admission == .idle else {
            throw OfflineMapCoreError.coordinatorBusy(admission.description)
        }
        try requireCapability(.persistentRegionLifecycle)

        admission = .inventoryRefresh
        defer { admission = .idle }
        snapshot.lastFailure = nil
        let inspection = await engine.inspect(connectivityPolicy: snapshot.connectivityPolicy)
        inspectedCapabilities = inspection.capabilities
        snapshot.availableCapabilities = inspection.capabilities
        snapshot.persistentHealth = inspection.persistentHealth
        snapshot.radioSilenceState = inspection.radioSilenceState
        var blockers = deduplicatedBlockers(
            inspection.blockers + readinessBlockers(for: inspection.persistentHealth)
        )
        if snapshot.connectivityPolicy == .radioSilent,
           inspection.radioSilenceState != .enforced {
            blockers.append(
                .init(
                    code: .radioSilenceNotEnforced,
                    message: "Radio silence has not been confirmed by the offline map engine.",
                    recovery: "Retry offline initialization before departure."
                )
            )
            blockers = deduplicatedBlockers(blockers)
        }
        if blockers.isEmpty {
            applyReadiness(for: inspection.capabilities)
            let failures = await reloadInventory()
            snapshot.lastFailure = failures.first
        } else {
            snapshot.readiness = .blocked(blockers)
            let failures = await reloadInventory()
            snapshot.lastFailure = failures.first
        }
    }

    func setConnectivityPolicy(_ policy: OfflineMapConnectivityPolicy) async throws {
        try requireCommandAdmission()
        admission = .policyTransition
        let previousPolicy = snapshot.connectivityPolicy
        let previousRadioSilenceState = snapshot.radioSilenceState
        snapshot.radioSilenceState = policy == .radioSilent ? .applying : .notRequested
        do {
            let state = try await engine.applyConnectivityPolicy(policy)
            if policy == .radioSilent, state != .enforced {
                let blocker = OfflineMapReadinessBlocker(
                    code: .radioSilenceNotEnforced,
                    message: "The native engine did not confirm radio silence.",
                    recovery: "Do not describe this session as fully offline until enforcement succeeds."
                )
                throw OfflineMapCoreError.notReady([blocker])
            }
            snapshot.connectivityPolicy = policy
            snapshot.radioSilenceState = state
        } catch {
            let reportedError: OfflineMapCoreError
            if let coreError = error as? OfflineMapCoreError {
                reportedError = coreError
            } else {
                reportedError = .engineFailure(
                    normalizedFailure(error, fallbackCode: "connectivity_policy_failed")
                )
            }

            // A rejected runtime transition (for example because navigation or
            // rendering holds a lease) must never make the snapshot claim the
            // requested mode. Reapply and inspect the previously confirmed
            // policy before returning the transition error.
            snapshot.connectivityPolicy = previousPolicy
            snapshot.radioSilenceState = previousRadioSilenceState
            admission = .idle
            await prepare()
            snapshot.lastFailure = failure(from: reportedError)
            throw reportedError
        }
        admission = .idle
        await prepare()
    }

    func preflightDownload(regionIDs: [OfflineMapRegionID]) async throws -> OfflineMapStoragePreflight {
        try requireCommandAdmission()
        admission = .storagePreflight
        defer { admission = .idle }
        try requireConnectedMaintenance(operation: "download")
        let regionIDs = unique(regionIDs)
        try validateDownloadTargets(regionIDs)
        do {
            guard let estimate = try await engine.downloadByteEstimate(for: regionIDs) else {
                throw OfflineMapCoreError.storageEstimateUnavailable
            }
            let storage = try await refreshStorageSnapshot()
            return storagePreflight(estimate: estimate, storage: storage)
        } catch let error as OfflineMapCoreError {
            throw error
        } catch {
            throw recordAndWrap(error, fallbackCode: "storage_preflight_failed")
        }
    }

    func download(regionIDs: [OfflineMapRegionID]) async throws {
        try requireCommandAdmission()
        try requireConnectedMaintenance(operation: "download")
        let regionIDs = unique(regionIDs)
        try validateDownloadTargets(regionIDs)
        try requireHealthyPersistentMap()
        let operationID = try beginOperation(kind: .downloadRegions, regionIDs: regionIDs)

        do {
            guard let estimate = try await engine.downloadByteEstimate(for: regionIDs) else {
                throw OfflineMapCoreError.storageEstimateUnavailable
            }
            let storage = try await refreshStorageSnapshot()
            let preflight = storagePreflight(estimate: estimate, storage: storage)
            guard case .accepted = preflight else {
                throw OfflineMapCoreError.insufficientStorage(
                    requiredBytes: estimate.requiredBytes,
                    availableBytes: storage.availableBytes,
                    reserveBytes: storagePolicy.minimumPostOperationFreeBytes
                )
            }

            setOperationPhase(.running, id: operationID)
            try await engine.downloadRegions(regionIDs, progress: progressHandler(for: operationID))
            if cancellationRequested.contains(operationID) {
                throw CancellationError()
            }
            try await finishSuccessfulOperation(id: operationID)
        } catch {
            try await finishFailedOperation(id: operationID, error: error, fallbackCode: "region_download_failed")
        }
    }

    func delete(regionIDs: [OfflineMapRegionID]) async throws {
        try requireCommandAdmission()
        let regionIDs = unique(regionIDs)
        try requireCapability(.persistentRegionLifecycle)
        try requireHealthyPersistentMap()
        guard snapshot.installedRegionsState.isCurrent else {
            throw OfflineMapCoreError.notReady([
                .init(
                    code: .persistentMapUnavailable,
                    message: "Installed region inventory is not current.",
                    recovery: "Refresh installed maps before deleting map data."
                )
            ])
        }
        guard !regionIDs.isEmpty else {
            throw OfflineMapCoreError.invalidInput("Select at least one installed region to delete.")
        }
        let installed = Set(snapshot.installedRegions.map(\.id))
        let unknown = regionIDs.filter { !installed.contains($0) }
        guard unknown.isEmpty else { throw OfflineMapCoreError.unknownRegions(unknown) }

        let operationID = try beginOperation(kind: .deleteRegions, regionIDs: regionIDs)
        do {
            setOperationPhase(.running, id: operationID)
            try await engine.deleteRegions(regionIDs, progress: progressHandler(for: operationID))
            try await finishSuccessfulOperation(id: operationID)
        } catch {
            try await finishFailedOperation(id: operationID, error: error, fallbackCode: "region_delete_failed")
        }
    }

    func repairPersistentMap() async throws {
        try requireCommandAdmission()
        try requireCapability(.persistentMapRepair)
        let operationID = try beginOperation(kind: .repairPersistentMap, regionIDs: [])
        snapshot.persistentHealth = .repairing
        do {
            setOperationPhase(.running, id: operationID)
            try await engine.repairPersistentMap(progress: progressHandler(for: operationID))
            try await finishSuccessfulOperation(id: operationID)
        } catch {
            snapshot.persistentHealth = .needsRepair(reason: "The persistent map repair did not complete.")
            try await finishFailedOperation(id: operationID, error: error, fallbackCode: "persistent_map_repair_failed")
        }
    }

    func updatePersistentMap() async throws {
        try requireCommandAdmission()
        try requireConnectedMaintenance(operation: "update")
        try requireCapability(.persistentMapUpdates)
        try requireHealthyPersistentMap()
        guard snapshot.installedRegionsState.isCurrent else {
            throw OfflineMapCoreError.notReady([
                .init(
                    code: .persistentMapUnavailable,
                    message: "Installed region inventory is not current.",
                    recovery: "Refresh installed maps before updating map data."
                )
            ])
        }
        let targetIDs = snapshot.installedRegions
            .filter { $0.state.isUsableCoverage }
            .map(\.id)
        guard !targetIDs.isEmpty else {
            throw OfflineMapCoreError.invalidInput(
                "There are no complete offline regions eligible for a persistent-map update."
            )
        }
        let operationID = try beginOperation(kind: .updatePersistentMap, regionIDs: targetIDs)

        do {
            let storage = try await refreshStorageSnapshot()
            let sdkEstimate = try await engine.persistentMapUpdateByteEstimate()
            let estimate: OfflineMapByteEstimate?
            if let sdkEstimate {
                estimate = sdkEstimate
            } else {
                estimate = try policyUpdateEstimate(storage: storage)
            }
            guard let estimate else {
                throw OfflineMapCoreError.storageEstimateUnavailable
            }
            guard case .accepted = storagePreflight(estimate: estimate, storage: storage) else {
                throw OfflineMapCoreError.insufficientStorage(
                    requiredBytes: estimate.requiredBytes,
                    availableBytes: storage.availableBytes,
                    reserveBytes: storagePolicy.minimumPostOperationFreeBytes
                )
            }

            setOperationPhase(.running, id: operationID)
            try await engine.updatePersistentMap(progress: progressHandler(for: operationID))
            if cancellationRequested.contains(operationID) {
                throw CancellationError()
            }
            try await finishSuccessfulOperation(id: operationID)
        } catch {
            try await finishFailedOperation(id: operationID, error: error, fallbackCode: "persistent_map_update_failed")
        }
    }

    func pauseActiveTransfer() async throws {
        guard let operation = snapshot.activeOperation,
              operation.kind == .downloadRegions || operation.kind == .updatePersistentMap,
              operation.phase == .running else {
            throw OfflineMapCoreError.operationNotPausable
        }
        setOperationPhase(.pausing, id: operation.id)
        do {
            try await engine.pauseActiveTransfer()
            setOperationPhase(.paused, id: operation.id)
        } catch {
            setOperationPhase(.running, id: operation.id)
            throw recordAndWrap(error, fallbackCode: "pause_failed")
        }
    }

    func resumeActiveTransfer() async throws {
        guard let operation = snapshot.activeOperation,
              operation.kind == .downloadRegions || operation.kind == .updatePersistentMap,
              operation.phase == .paused else {
            throw OfflineMapCoreError.operationNotPaused
        }
        setOperationPhase(.resuming, id: operation.id)
        do {
            try await engine.resumeActiveTransfer()
            setOperationPhase(.running, id: operation.id)
        } catch {
            setOperationPhase(.paused, id: operation.id)
            throw recordAndWrap(error, fallbackCode: "resume_failed")
        }
    }

    func cancelActiveTransfer() async throws {
        guard let operation = snapshot.activeOperation,
              operation.kind == .downloadRegions || operation.kind == .updatePersistentMap,
              operation.phase == .running || operation.phase == .paused else {
            throw OfflineMapCoreError.operationNotCancellable
        }
        let priorPhase = operation.phase
        setOperationPhase(.cancelling, id: operation.id)
        cancellationRequested.insert(operation.id)
        do {
            try await engine.cancelActiveTransfer()
        } catch {
            cancellationRequested.remove(operation.id)
            setOperationPhase(priorPhase, id: operation.id)
            throw recordAndWrap(error, fallbackCode: "cancel_failed")
        }
    }

    func searchOffline(_ request: OfflineSearchRequest) async throws -> OfflineSearchResponse {
        try requireCommandAdmission()
        admission = .localRead
        defer { admission = .idle }
        try requireCapability(.offlineSearch)
        try requireHealthyPersistentMap()
        try requireRadioSilenceIfRequested()
        let installedRegionIDs = try currentUsableInstalledRegionIDs()
        do {
            let response = try await engine.searchOffline(request)
            guard response.results.count <= request.maximumResultCount else {
                throw offlineSearchResultLimitFailure()
            }
            try validateCoverage(response.coverage, installedRegionIDs: installedRegionIDs)
            let responseRegionIDs = Set(response.coveredByRegionIDs)
            guard response.results.allSatisfy({
                responseRegionIDs.contains($0.regionID) && installedRegionIDs.contains($0.regionID)
            }) else {
                throw coverageAttributionFailure()
            }
            return response
        } catch {
            throw recordAndWrap(error, fallbackCode: "offline_search_failed")
        }
    }

    func calculateOfflineRoute(_ request: OfflineRouteRequest) async throws -> OfflineRouteResponse {
        try requireCommandAdmission()
        admission = .localRead
        defer { admission = .idle }
        guard request.mode.supportsHEREOfflineCalculation else {
            throw OfflineMapCoreError.unsupportedLocalRouting(request.mode)
        }
        try requireCapability(request.mode == .truck ? .offlineTruckRouting : .offlineRoadRouting)
        try requireHealthyPersistentMap()
        try requireRadioSilenceIfRequested()
        let installedRegionIDs = try currentUsableInstalledRegionIDs()
        do {
            let response = try await engine.calculateOfflineRoute(request)
            guard response.requestID == request.id,
                  response.routes.allSatisfy({ $0.mode == request.mode && $0.provenance == .hereOfflineLocal }) else {
                let failure = OfflineMapFailure(
                    code: "offline_route_contract_violation",
                    message: "The offline routing engine returned a route with mismatched identity, mode, or provenance.",
                    recovery: "Discard the route and reinitialize the native offline routing engine.",
                    isRecoverable: true
                )
                snapshot.lastFailure = failure
                throw OfflineMapCoreError.engineFailure(failure)
            }
            try validateCoverage(response.coverage, installedRegionIDs: installedRegionIDs)
            let responseRegionIDs = Set(response.coveredByRegionIDs)
            guard response.routes.allSatisfy({ route in
                let routeRegionIDs = Set(route.coverage.regionIDs)
                return routeRegionIDs.isSubset(of: responseRegionIDs) &&
                    routeRegionIDs.isSubset(of: installedRegionIDs)
            }) else {
                throw coverageAttributionFailure()
            }
            return response
        } catch let error as OfflineMapCoreError {
            throw error
        } catch {
            throw recordAndWrap(error, fallbackCode: "offline_route_failed")
        }
    }

    // MARK: - State machine helpers

    private func beginOperation(
        kind: OfflineMapOperationKind,
        regionIDs: [OfflineMapRegionID]
    ) throws -> UUID {
        if let active = snapshot.activeOperation {
            throw OfflineMapCoreError.busy(activeOperation: active.kind)
        }
        let id = UUID()
        snapshot.lastFailure = nil
        snapshot.activeOperation = .init(
            id: id,
            kind: kind,
            targetRegionIDs: regionIDs,
            phase: .preparing,
            progress: nil,
            startedAt: Date()
        )
        lastAppliedProgressSequence = 0
        return id
    }

    private func setOperationPhase(_ phase: OfflineMapOperationPhase, id: UUID) {
        guard snapshot.activeOperation?.id == id else { return }
        snapshot.activeOperation?.phase = phase
    }

    private func progressHandler(for operationID: UUID) -> OfflineMapProgressHandler {
        let sequencer = OfflineMapProgressSequencer()
        return { [weak self] progress in
            sequencer.enqueue(progress)
            Task { @MainActor [weak self] in
                let orderedProgress = sequencer.drain()
                guard let self,
                      self.snapshot.activeOperation?.id == operationID else { return }
                for item in orderedProgress where item.sequence > self.lastAppliedProgressSequence {
                    self.lastAppliedProgressSequence = item.sequence
                    guard !self.isRegressiveProgress(item.progress),
                          !self.isStaleResumeReport(item.progress) else { continue }
                    let mergedProgress = self.mergedProgress(item.progress)
                    self.snapshot.activeOperation?.progress = mergedProgress
                    guard let reportedPhase = item.progress.reportedPhase,
                          let currentPhase = self.snapshot.activeOperation?.phase else { continue }
                    switch (currentPhase, reportedPhase) {
                    case (.running, .paused), (.pausing, .paused):
                        self.snapshot.activeOperation?.phase = .paused
                    case (.resuming, .running):
                        self.snapshot.activeOperation?.phase = .running
                    default:
                        break
                    }
                }
            }
        }
    }

    private func isRegressiveProgress(_ progress: OfflineMapTransferProgress) -> Bool {
        guard let previous = snapshot.activeOperation?.progress else { return false }
        if let priorBytes = previous.completedBytes,
           let nextBytes = progress.completedBytes,
           nextBytes < priorBytes { return true }
        if let priorTotal = previous.totalBytes,
           let nextTotal = progress.totalBytes,
           nextTotal < priorTotal { return true }
        if let priorFraction = previous.fractionCompleted,
           let nextFraction = progress.fractionCompleted,
           nextFraction < priorFraction { return true }
        return false
    }

    private func isStaleResumeReport(_ progress: OfflineMapTransferProgress) -> Bool {
        snapshot.activeOperation?.phase == .paused && progress.reportedPhase == .running
    }

    private func mergedProgress(
        _ progress: OfflineMapTransferProgress
    ) -> OfflineMapTransferProgress {
        guard let previous = snapshot.activeOperation?.progress,
              let merged = try? OfflineMapTransferProgress(
                completedBytes: progress.completedBytes ?? previous.completedBytes,
                totalBytes: progress.totalBytes ?? previous.totalBytes,
                fractionCompleted: progress.fractionCompleted ?? previous.fractionCompleted,
                regionID: progress.regionID ?? previous.regionID,
                detail: progress.detail ?? previous.detail,
                reportedPhase: progress.reportedPhase
              ) else { return progress }
        return merged
    }

    private func finishSuccessfulOperation(id: UUID) async throws {
        guard let operation = snapshot.activeOperation, operation.id == id else { return }
        setOperationPhase(.finalizing, id: id)
        cancellationRequested.remove(id)
        let inspection = await engine.inspect(connectivityPolicy: snapshot.connectivityPolicy)
        inspectedCapabilities = inspection.capabilities
        snapshot.availableCapabilities = inspection.capabilities
        snapshot.persistentHealth = inspection.persistentHealth
        snapshot.radioSilenceState = inspection.radioSilenceState
        var blockers = deduplicatedBlockers(
            inspection.blockers + readinessBlockers(for: inspection.persistentHealth)
        )
        if snapshot.connectivityPolicy == .radioSilent,
           inspection.radioSilenceState != .enforced {
            blockers.append(
                .init(
                    code: .radioSilenceNotEnforced,
                    message: "Radio silence was not confirmed after the map operation.",
                    recovery: "Reinitialize the native offline engine before relying on this map data."
                )
            )
            blockers = deduplicatedBlockers(blockers)
        }
        if !blockers.isEmpty {
            snapshot.readiness = .blocked(blockers)
            let failures = await reloadInventory()
            snapshot.lastFailure = failures.first
            throw OfflineMapCoreError.notReady(blockers)
        }
        applyReadiness(for: inspection.capabilities)
        let failures = await reloadInventory()
        snapshot.lastFailure = failures.first

        // Catalog access can legitimately fail while radio-silent. Durable
        // mutations still require independent installed-map and storage
        // readback, plus target presence/absence verification.
        guard snapshot.installedRegionsState.isCurrent,
              snapshot.storageState.isCurrent else {
            throw postOperationReadbackFailure()
        }
        let installedIDs = Set(snapshot.installedRegions.map(\.id))
        switch operation.kind {
        case .downloadRegions:
            let usableIDs = Set(
                snapshot.installedRegions
                    .filter { $0.state.isUsableCoverage }
                    .map(\.id)
            )
            guard operation.targetRegionIDs.allSatisfy(usableIDs.contains) else {
                throw postOperationReadbackFailure()
            }
        case .deleteRegions:
            guard operation.targetRegionIDs.allSatisfy({ !installedIDs.contains($0) }) else {
                throw postOperationReadbackFailure()
            }
        case .updatePersistentMap:
            let currentIDs = Set(
                snapshot.installedRegions
                    .filter { $0.state == .installed }
                    .map(\.id)
            )
            guard operation.targetRegionIDs.allSatisfy(currentIDs.contains) else {
                throw postOperationReadbackFailure()
            }
        case .repairPersistentMap:
            break
        }
        snapshot.activeOperation = nil
        lastAppliedProgressSequence = 0
    }

    private func finishFailedOperation(
        id: UUID,
        error: Error,
        fallbackCode: String
    ) async throws -> Never {
        if snapshot.activeOperation?.id == id {
            if snapshot.activeOperation?.phase != .finalizing {
                setOperationPhase(.finalizing, id: id)
            }

            // A failed or cancelled durable mutation can change persistent-map
            // health and runtime radio policy even when the SDK callback did
            // not report success. Re-prove those facts before clearing the
            // operation so stale readiness can never authorize the next one.
            let inspection = await engine.inspect(connectivityPolicy: snapshot.connectivityPolicy)
            inspectedCapabilities = inspection.capabilities
            snapshot.availableCapabilities = inspection.capabilities
            snapshot.persistentHealth = inspection.persistentHealth
            snapshot.radioSilenceState = inspection.radioSilenceState
            var blockers = deduplicatedBlockers(
                inspection.blockers + readinessBlockers(for: inspection.persistentHealth)
            )
            if snapshot.connectivityPolicy == .radioSilent,
               inspection.radioSilenceState != .enforced {
                blockers.append(
                    .init(
                        code: .radioSilenceNotEnforced,
                        message: "Radio silence was not confirmed after the interrupted map operation.",
                        recovery: "Reinitialize the native offline engine before relying on this map data."
                    )
                )
                blockers = deduplicatedBlockers(blockers)
            }
            if blockers.isEmpty {
                applyReadiness(for: inspection.capabilities)
            } else {
                snapshot.readiness = .blocked(blockers)
            }
            let inventoryFailures = await reloadInventory()
            snapshot.lastFailure = inventoryFailures.first
        }
        let wasCancellation = cancellationRequested.remove(id) != nil
        if snapshot.activeOperation?.id == id {
            snapshot.activeOperation = nil
            lastAppliedProgressSequence = 0
        }
        if wasCancellation {
            throw CancellationError()
        }
        if let coreError = error as? OfflineMapCoreError {
            snapshot.lastFailure = failure(from: coreError)
            throw coreError
        }
        throw recordAndWrap(error, fallbackCode: fallbackCode)
    }

    private func refreshStorageSnapshot() async throws -> OfflineMapStorageSnapshot {
        let lastSuccess = snapshot.storageState.lastSuccessfulAt
        snapshot.storageState = .loading(lastSuccessfulAt: lastSuccess)
        do {
            let storage = try await engine.storageSnapshot()
            snapshot.storage = storage
            snapshot.storageState = .current(loadedAt: Date())
            return storage
        } catch {
            let failure = normalizedFailure(error, fallbackCode: "storage_snapshot_failed")
            snapshot.storageState = lastSuccess.map {
                .stale(lastSuccessfulAt: $0, failure: failure)
            } ?? .unavailable(failure: failure)
            snapshot.lastFailure = failure
            throw OfflineMapCoreError.engineFailure(failure)
        }
    }

    private func reloadInventory() async -> [OfflineMapFailure] {
        var failures: [OfflineMapFailure] = []

        // Installed data and device space are useful without a radio. Load them
        // before attempting the catalog, which may legitimately be unreachable
        // in a cold radio-silent launch.
        let installedLastSuccess = snapshot.installedRegionsState.lastSuccessfulAt
        snapshot.installedRegionsState = .loading(lastSuccessfulAt: installedLastSuccess)
        do {
            let installed = try await engine.installedRegions()
            guard Set(installed.map(\.id)).count == installed.count else {
                throw inventoryIdentityFailure(feed: "installed region inventory")
            }
            let loadedAt = Date()
            snapshot.installedRegions = installed.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            snapshot.installedRegionsState = .current(loadedAt: loadedAt)
        } catch {
            let failure = normalizedFailure(error, fallbackCode: "installed_regions_failed")
            failures.append(failure)
            snapshot.installedRegionsState = installedLastSuccess.map {
                .stale(lastSuccessfulAt: $0, failure: failure)
            } ?? .unavailable(failure: failure)
        }

        let storageLastSuccess = snapshot.storageState.lastSuccessfulAt
        snapshot.storageState = .loading(lastSuccessfulAt: storageLastSuccess)
        do {
            snapshot.storage = try await engine.storageSnapshot()
            snapshot.storageState = .current(loadedAt: Date())
        } catch {
            let failure = normalizedFailure(error, fallbackCode: "storage_snapshot_failed")
            failures.append(failure)
            snapshot.storageState = storageLastSuccess.map {
                .stale(lastSuccessfulAt: $0, failure: failure)
            } ?? .unavailable(failure: failure)
        }

        let catalogLastSuccess = snapshot.downloadableCatalogState.lastSuccessfulAt
        snapshot.downloadableCatalogState = .loading(lastSuccessfulAt: catalogLastSuccess)
        do {
            let downloadable = try await engine.downloadableRegions()
            guard Set(downloadable.map(\.id)).count == downloadable.count else {
                throw inventoryIdentityFailure(feed: "downloadable region catalog")
            }
            let loadedAt = Date()
            snapshot.downloadableRegions = downloadable.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            snapshot.downloadableCatalogState = .current(loadedAt: loadedAt)
        } catch {
            let failure = normalizedFailure(error, fallbackCode: "downloadable_catalog_failed")
            failures.append(failure)
            snapshot.downloadableCatalogState = catalogLastSuccess.map {
                .stale(lastSuccessfulAt: $0, failure: failure)
            } ?? .unavailable(failure: failure)
        }

        snapshot.lastRefreshedAt = Date()
        return failures
    }

    private func validateDownloadTargets(_ regionIDs: [OfflineMapRegionID]) throws {
        try requireCapability(.persistentRegionLifecycle)
        guard snapshot.downloadableCatalogState.isCurrent else {
            let blocker = OfflineMapReadinessBlocker(
                code: .persistentMapUnavailable,
                message: "The downloadable region catalog is not current.",
                recovery: "Reconnect and refresh the region catalog before starting a transfer."
            )
            throw OfflineMapCoreError.notReady([blocker])
        }
        guard snapshot.installedRegionsState.isCurrent else {
            let blocker = OfflineMapReadinessBlocker(
                code: .persistentMapUnavailable,
                message: "The installed region inventory is not current.",
                recovery: "Refresh installed maps before starting or resuming a transfer."
            )
            throw OfflineMapCoreError.notReady([blocker])
        }
        guard !regionIDs.isEmpty else {
            throw OfflineMapCoreError.invalidInput("Select at least one region to download.")
        }
        let downloadable = Set(snapshot.downloadableRegions.map(\.id))
        let unknown = regionIDs.filter { !downloadable.contains($0) }
        guard unknown.isEmpty else { throw OfflineMapCoreError.unknownRegions(unknown) }

        let installed = Set(
            snapshot.installedRegions
                .filter { $0.state.isUsableCoverage }
                .map(\.id)
        )
        guard regionIDs.allSatisfy({ !installed.contains($0) }) else {
            throw OfflineMapCoreError.invalidInput(
                "One or more selected HERE regions are already installed."
            )
        }

        // HERE parent regions contain their descendants. Submitting both can
        // double-count storage or create an ambiguous SDK transfer, so the
        // core enforces the same non-overlap rule as the management UI.
        let selected = Set(regionIDs)
        var parentByID: [OfflineMapRegionID: OfflineMapRegionID?] = [:]
        var catalogIDs = Set<OfflineMapRegionID>()
        for region in snapshot.downloadableRegions {
            guard catalogIDs.insert(region.id).inserted else {
                throw OfflineMapCoreError.engineFailure(
                    inventoryIdentityFailure(feed: "downloadable region catalog")
                )
            }
            parentByID.updateValue(region.parentID, forKey: region.id)
        }
        for regionID in regionIDs {
            var seen = Set<OfflineMapRegionID>()
            var ancestor = parentByID[regionID] ?? nil
            while let ancestorID = ancestor, seen.insert(ancestorID).inserted {
                guard !selected.contains(ancestorID) else {
                    throw OfflineMapCoreError.invalidInput(
                        "Select either a HERE parent region or its child region, not both."
                    )
                }
                ancestor = parentByID[ancestorID] ?? nil
            }
        }
    }

    private func storagePreflight(
        estimate: OfflineMapByteEstimate,
        storage: OfflineMapStorageSnapshot
    ) -> OfflineMapStoragePreflight {
        let reserve = storagePolicy.minimumPostOperationFreeBytes
        if storage.availableBytes >= reserve {
            let usableBytes = storage.availableBytes - reserve
            if estimate.requiredBytes <= usableBytes {
                return .accepted(
                    estimate: estimate,
                    storage: storage,
                    remainingBytesAfterOperation: storage.availableBytes - estimate.requiredBytes
                )
            }
            return .blocked(
                estimate: estimate,
                storage: storage,
                requiredReserveBytes: reserve,
                shortfallBytes: estimate.requiredBytes - usableBytes
            )
        }
        let reserveDeficit = reserve - storage.availableBytes
        let combinedShortfall = estimate.requiredBytes.addingReportingOverflow(reserveDeficit)
        return .blocked(
            estimate: estimate,
            storage: storage,
            requiredReserveBytes: reserve,
            shortfallBytes: combinedShortfall.overflow ? Int64.max : combinedShortfall.partialValue
        )
    }

    private func policyUpdateEstimate(
        storage: OfflineMapStorageSnapshot
    ) throws -> OfflineMapByteEstimate? {
        guard let multiplier = storagePolicy.updateStagingBytesPerInstalledByte else {
            return nil
        }
        guard storage.installedMapBytes > 0 else { return nil }
        let calculated = ceil(Double(storage.installedMapBytes) * multiplier)
        guard calculated.isFinite, calculated < Double(Int64.max) else {
            throw OfflineMapCoreError.invalidInput("The update staging policy exceeds supported storage bounds.")
        }
        return try OfflineMapByteEstimate(
            requiredBytes: Int64(calculated),
            confidence: .policyEstimate
        )
    }

    private func requireCapability(_ capability: OfflineMapCapabilities) throws {
        let missing = capability.subtracting(inspectedCapabilities)
        guard missing.isEmpty else { throw OfflineMapCoreError.missingCapabilities(missing) }
    }

    private func requireCommandAdmission() throws {
        if let active = snapshot.activeOperation {
            throw OfflineMapCoreError.busy(activeOperation: active.kind)
        }
        guard admission == .idle else {
            throw OfflineMapCoreError.coordinatorBusy(admission.description)
        }
    }

    private func requireHealthyPersistentMap() throws {
        guard snapshot.persistentHealth.permitsRegionMutation else {
            let blocker = OfflineMapReadinessBlocker(
                code: .persistentMapNeedsRepair,
                message: "Persistent map health is not verified as healthy.",
                recovery: "Run the persistent map repair or retry the health inspection."
            )
            throw OfflineMapCoreError.notReady([blocker])
        }
    }

    private func requireRadioSilenceIfRequested() throws {
        guard snapshot.connectivityPolicy != .radioSilent || snapshot.radioSilenceState == .enforced else {
            let blocker = OfflineMapReadinessBlocker(
                code: .radioSilenceNotEnforced,
                message: "Radio silence was requested but has not been enforced.",
                recovery: "Reinitialize the offline engine before using this result without connectivity."
            )
            throw OfflineMapCoreError.notReady([blocker])
        }
    }

    private func currentUsableInstalledRegionIDs() throws -> Set<OfflineMapRegionID> {
        guard snapshot.installedRegionsState.isCurrent else {
            throw OfflineMapCoreError.notReady([
                .init(
                    code: .persistentMapUnavailable,
                    message: "Installed-region coverage evidence is not current.",
                    recovery: "Refresh installed maps before using offline search or routing."
                )
            ])
        }
        let regionIDs = Set(
            snapshot.installedRegions
                .filter { $0.state.isUsableCoverage }
                .map(\.id)
        )
        guard !regionIDs.isEmpty else {
            throw OfflineMapCoreError.notReady([
                .init(
                    code: .persistentMapUnavailable,
                    message: "No verified usable installed-region coverage is available.",
                    recovery: "Install and verify the required HERE regions before using local map services."
                )
            ])
        }
        return regionIDs
    }

    private func validateCoverage(
        _ coverage: OfflineInstalledCoverageEvidence,
        installedRegionIDs: Set<OfflineMapRegionID>
    ) throws {
        guard Set(coverage.regionIDs).isSubset(of: installedRegionIDs) else {
            throw coverageAttributionFailure()
        }
    }

    private func coverageAttributionFailure() -> OfflineMapCoreError {
        let failure = OfflineMapFailure(
            code: "offline_coverage_contract_violation",
            message: "The local HERE result was not attributed to current installed-region coverage.",
            recovery: "Discard the result and re-verify installed-region boundary evidence.",
            isRecoverable: true
        )
        snapshot.lastFailure = failure
        return .engineFailure(failure)
    }

    private func offlineSearchResultLimitFailure() -> OfflineMapCoreError {
        let failure = OfflineMapFailure(
            code: "offline_search_result_limit_violation",
            message: "The local HERE search returned more results than the bounded request allowed.",
            recovery: "Discard the result and retry only after the native search adapter is verified.",
            isRecoverable: true
        )
        snapshot.lastFailure = failure
        return .engineFailure(failure)
    }

    private func inventoryIdentityFailure(feed: String) -> OfflineMapFailure {
        OfflineMapFailure(
            code: "offline_inventory_identity_violation",
            message: "The HERE \(feed) contained duplicate region identifiers.",
            recovery: "Discard this inventory and re-inspect the native persistent-map catalog.",
            isRecoverable: true
        )
    }

    private func requireConnectedMaintenance(operation: String) throws {
        guard snapshot.connectivityPolicy == .onlineAllowed else {
            let blocker = OfflineMapReadinessBlocker(
                code: .configurationInvalid,
                message: "HERE map \(operation) requires an explicit connected maintenance session.",
                recovery: "Allow network access for setup, finish maintenance, then restore radio silence."
            )
            throw OfflineMapCoreError.notReady([blocker])
        }
    }

    private func readinessBlockers(
        for health: OfflinePersistentMapHealth
    ) -> [OfflineMapReadinessBlocker] {
        switch health {
        case .healthy:
            return []
        case .unknown:
            return [
                .init(
                    code: .persistentMapUnavailable,
                    message: "Persistent map health has not been verified.",
                    recovery: "Retry native offline map inspection."
                )
            ]
        case .needsRepair(let reason):
            return [
                .init(
                    code: .persistentMapNeedsRepair,
                    message: reason,
                    recovery: "Repair persistent map data before relying on it offline."
                )
            ]
        case .repairing:
            return [
                .init(
                    code: .persistentMapNeedsRepair,
                    message: "Persistent map repair is still in progress.",
                    recovery: "Keep the app open until repair completes."
                )
            ]
        case .unusable(let reason):
            return [
                .init(
                    code: .persistentMapUnavailable,
                    message: reason,
                    recovery: "Repair or reinstall the affected offline regions."
                )
            ]
        }
    }

    private func applyReadiness(for available: OfflineMapCapabilities) {
        let missing = requiredCapabilities.subtracting(available)
        snapshot.readiness = missing.isEmpty
            ? .ready(available)
            : .limited(available: available, missing: missing)
    }

    private func unique(_ regionIDs: [OfflineMapRegionID]) -> [OfflineMapRegionID] {
        var seen = Set<OfflineMapRegionID>()
        return regionIDs.filter { seen.insert($0).inserted }
    }

    private func deduplicatedBlockers(
        _ blockers: [OfflineMapReadinessBlocker]
    ) -> [OfflineMapReadinessBlocker] {
        var seen = Set<String>()
        return blockers.filter {
            seen.insert("\($0.code.rawValue)|\($0.message)").inserted
        }
    }

    private func recordAndWrap(_ error: Error, fallbackCode: String) -> OfflineMapCoreError {
        if let coreError = error as? OfflineMapCoreError {
            snapshot.lastFailure = failure(from: coreError)
            return coreError
        }
        let failure = normalizedFailure(error, fallbackCode: fallbackCode)
        snapshot.lastFailure = failure
        return .engineFailure(failure)
    }

    private func normalizedFailure(_ error: Error, fallbackCode: String) -> OfflineMapFailure {
        if let failure = error as? OfflineMapFailure { return failure }
        if let provider = error as? any OfflineMapFailureProviding {
            return provider.offlineMapFailure
        }
        return OfflineMapFailure(
            code: fallbackCode,
            message: "The native offline map engine could not complete this operation.",
            recovery: "Retry the operation. If it repeats, refresh the offline map health status.",
            isRecoverable: true
        )
    }

    private func failure(from error: OfflineMapCoreError) -> OfflineMapFailure {
        if case .engineFailure(let failure) = error { return failure }
        let code: String
        let message: String
        switch error {
        case .invalidInput:
            (code, message) = ("offline_core_invalid_input", "Offline map input was invalid.")
        case .busy:
            (code, message) = ("offline_core_busy", "Another offline map operation is active.")
        case .coordinatorBusy:
            (code, message) = ("offline_core_command_busy", "Another offline map command is in progress.")
        case .notReady:
            (code, message) = ("offline_core_not_ready", "Offline map readiness requirements are not satisfied.")
        case .missingCapabilities:
            (code, message) = ("offline_core_missing_capability", "A required offline map capability is unavailable.")
        case .unknownRegions:
            (code, message) = ("offline_core_unknown_region", "A selected offline map region is unavailable.")
        case .storageEstimateUnavailable:
            (code, message) = ("offline_core_estimate_unavailable", "Offline map storage requirements could not be verified.")
        case .insufficientStorage:
            (code, message) = ("offline_core_insufficient_storage", "The device does not have enough reserved storage for this operation.")
        case .operationNotPausable:
            (code, message) = ("offline_core_not_pausable", "No offline map transfer can be paused.")
        case .operationNotPaused:
            (code, message) = ("offline_core_not_paused", "No paused offline map transfer can be resumed.")
        case .operationNotCancellable:
            (code, message) = ("offline_core_not_cancellable", "No offline map transfer can be cancelled.")
        case .unsupportedLocalRouting:
            (code, message) = ("offline_core_unsupported_route_mode", "This freight mode cannot be routed by the local HERE engine.")
        case .engineFailure:
            (code, message) = ("offline_core_engine_failure", "The native offline map engine failed.")
        }
        return OfflineMapFailure(
            code: code,
            message: message,
            recovery: nil,
            isRecoverable: true
        )
    }

    private func postOperationReadbackFailure() -> OfflineMapCoreError {
        let failure = OfflineMapFailure(
            code: "post_operation_readback_failed",
            message: "HERE completed the request, but the on-device map change could not be verified.",
            recovery: "Recheck persistent map health before relying on this coverage.",
            isRecoverable: true
        )
        snapshot.lastFailure = failure
        return .engineFailure(failure)
    }
}
