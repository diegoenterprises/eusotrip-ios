import Foundation
@testable import EusoTrip

struct FakeOfflineMapEngineStatistics: Equatable, Sendable {
    var appliedConnectivityPolicies: [OfflineMapConnectivityPolicy] = []
    var inspectedConnectivityPolicies: [OfflineMapConnectivityPolicy] = []
    var downloadEstimateCalls = 0
    var downloadCalls = 0
    var deleteCalls = 0
    var repairCalls = 0
    var updateCalls = 0
    var pauseCalls = 0
    var resumeCalls = 0
    var cancelCalls = 0
    var updateEstimateCalls = 0
}

actor FakeOfflineMapEngine: OfflineMapEngine {
    static let targetRegionName = "Texas"
    static let targetRegionRawID = "target-region"
    static let parentRegionRawID = "parent-region"
    static let existingRegionRawID = "existing-region"

    private var capabilities: OfflineMapCapabilities
    private var blockers: [OfflineMapReadinessBlocker]
    private var persistentHealth: OfflinePersistentMapHealth
    private var radioSilenceState: OfflineMapRadioSilenceState
    private var downloadableRegionsValue: [OfflineMapDownloadableRegion]
    private var installedRegionsValue: [OfflineMapInstalledRegion]
    private var storageValue: OfflineMapStorageSnapshot
    private var downloadEstimateValue: OfflineMapByteEstimate?
    private var updateEstimateValue: OfflineMapByteEstimate?
    private var catalogFailure: OfflineMapFailure?
    private var installedFailure: OfflineMapFailure?
    private var storageFailure: OfflineMapFailure?
    private var downloadFailureAfterIncomplete: OfflineMapFailure?
    private var persistentHealthAfterDownloadFailure: OfflinePersistentMapHealth?
    private var connectivityPolicyFailure: OfflineMapFailure?
    private var rejectedConnectivityPolicy: OfflineMapConnectivityPolicy?
    private var holdTransfers = false
    private var forceReadbackMismatch = false
    private var exposeIncompleteOnCancellation = false
    private var coverageRegionIDsOverride: [OfflineMapRegionID]?
    private var searchResultCount = 0
    private var transferContinuation: CheckedContinuation<Void, Error>?
    private var activeTransferProgress: OfflineMapProgressHandler?
    private var downloadStarted = false
    private var downloadStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var lastRouteMode: OfflineRouteMode?
    private var lastTruckConstraints: OfflineTruckConstraints?
    private var statisticsValue = FakeOfflineMapEngineStatistics()

    init(
        capabilities: OfflineMapCapabilities = .fullRoadFreightParity,
        persistentHealth: OfflinePersistentMapHealth = .healthy(
            catalogVersion: "catalog-1",
            verifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    ) throws {
        let targetID = try OfflineMapRegionID(Self.targetRegionRawID)
        let parentID = try OfflineMapRegionID(Self.parentRegionRawID)
        let existingID = try OfflineMapRegionID(Self.existingRegionRawID)
        self.capabilities = capabilities
        blockers = []
        self.persistentHealth = persistentHealth
        radioSilenceState = .enforced
        downloadableRegionsValue = [
            try OfflineMapDownloadableRegion(
                id: parentID,
                name: "United States",
                level: .country,
                parentID: nil,
                childCount: 1,
                estimatedDownloadBytes: 1_000
            ),
            try OfflineMapDownloadableRegion(
                id: targetID,
                name: Self.targetRegionName,
                level: .stateOrProvince,
                parentID: parentID,
                childCount: 0,
                estimatedDownloadBytes: 200
            )
        ]
        installedRegionsValue = [
            try OfflineMapInstalledRegion(
                id: existingID,
                name: "Existing coverage",
                installedBytes: 400,
                catalogVersion: "catalog-1",
                state: .installed,
                installedAt: Date(timeIntervalSince1970: 1_699_999_000),
                lastVerifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        ]
        storageValue = try OfflineMapStorageSnapshot(
            availableBytes: 2_000,
            installedMapBytes: 400,
            measuredAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        downloadEstimateValue = try OfflineMapByteEstimate(
            requiredBytes: 200,
            confidence: .exact
        )
        updateEstimateValue = try OfflineMapByteEstimate(
            requiredBytes: 100,
            confidence: .sdkEstimate
        )
    }

    func setRadioSilenceState(_ state: OfflineMapRadioSilenceState) {
        radioSilenceState = state
    }

    func setPersistentHealth(_ health: OfflinePersistentMapHealth) {
        persistentHealth = health
    }

    func setCatalogFailure(_ failure: OfflineMapFailure?) {
        catalogFailure = failure
    }

    func setInstalledFailure(_ failure: OfflineMapFailure?) {
        installedFailure = failure
    }

    func setStorageFailure(_ failure: OfflineMapFailure?) {
        storageFailure = failure
    }

    func setDownloadFailureAfterIncomplete(
        _ failure: OfflineMapFailure?,
        persistentHealthAfterFailure: OfflinePersistentMapHealth? = nil
    ) {
        downloadFailureAfterIncomplete = failure
        persistentHealthAfterDownloadFailure = persistentHealthAfterFailure
    }

    func setConnectivityPolicyFailure(
        _ failure: OfflineMapFailure?,
        for policy: OfflineMapConnectivityPolicy = .radioSilent
    ) {
        connectivityPolicyFailure = failure
        rejectedConnectivityPolicy = failure == nil ? nil : policy
    }

    func setStorage(_ storage: OfflineMapStorageSnapshot) {
        storageValue = storage
    }

    func setDownloadEstimate(_ estimate: OfflineMapByteEstimate?) {
        downloadEstimateValue = estimate
    }

    func setUpdateEstimate(_ estimate: OfflineMapByteEstimate?) {
        updateEstimateValue = estimate
    }

    func setHoldTransfers(_ shouldHold: Bool) {
        holdTransfers = shouldHold
    }

    func setForceReadbackMismatch(_ shouldMismatch: Bool) {
        forceReadbackMismatch = shouldMismatch
    }

    func setExposeIncompleteOnCancellation(_ shouldExpose: Bool) {
        exposeIncompleteOnCancellation = shouldExpose
    }

    func setCoverageRegionIDsOverride(_ regionIDs: [OfflineMapRegionID]?) {
        coverageRegionIDsOverride = regionIDs
    }

    func setSearchResultCount(_ count: Int) {
        searchResultCount = count
    }

    func appendDuplicateDownloadableRegionID() throws {
        let targetID = try OfflineMapRegionID(Self.targetRegionRawID)
        downloadableRegionsValue.append(
            try OfflineMapDownloadableRegion(
                id: targetID,
                name: "Duplicate Texas",
                level: .stateOrProvince,
                parentID: nil,
                childCount: 0,
                estimatedDownloadBytes: 300
            )
        )
    }

    func setTargetInstalledState(_ state: OfflineMapInstalledRegionState) throws {
        let targetID = try OfflineMapRegionID(Self.targetRegionRawID)
        installedRegionsValue.removeAll { $0.id == targetID }
        installedRegionsValue.append(
            try OfflineMapInstalledRegion(
                id: targetID,
                name: Self.targetRegionName,
                installedBytes: state.isUsableCoverage ? 200 : 50,
                catalogVersion: state.isUsableCoverage ? "catalog-1" : nil,
                state: state,
                installedAt: state.isUsableCoverage
                    ? Date(timeIntervalSince1970: 1_700_000_001)
                    : nil,
                lastVerifiedAt: Date(timeIntervalSince1970: 1_700_000_001)
            )
        )
    }

    func setExistingInstalledState(_ state: OfflineMapInstalledRegionState) throws {
        let existingID = try OfflineMapRegionID(Self.existingRegionRawID)
        guard let existingIndex = installedRegionsValue.firstIndex(where: { $0.id == existingID }) else {
            throw OfflineMapCoreError.invalidInput("The deterministic existing region is missing.")
        }
        let existing = installedRegionsValue[existingIndex]
        installedRegionsValue[existingIndex] = try OfflineMapInstalledRegion(
            id: existing.id,
            name: existing.name,
            installedBytes: existing.installedBytes,
            catalogVersion: state == .updateAvailable ? "catalog-old" : "catalog-1",
            state: state,
            installedAt: existing.installedAt,
            lastVerifiedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
    }

    func waitForDownloadStart() async {
        if downloadStarted { return }
        await withCheckedContinuation { continuation in
            downloadStartWaiters.append(continuation)
        }
    }

    func completeActiveTransfer() {
        let continuation = transferContinuation
        transferContinuation = nil
        continuation?.resume()
    }

    func emitActiveTransferPhase(_ phase: OfflineMapOperationPhase) throws {
        activeTransferProgress?(
            try OfflineMapTransferProgress(
                completedBytes: 50,
                totalBytes: 200,
                fractionCompleted: 0.25,
                detail: "Fake engine-reported transfer phase.",
                reportedPhase: phase
            )
        )
    }

    func capturedActiveTransferProgressHandler() -> OfflineMapProgressHandler? {
        activeTransferProgress
    }

    func installedRegionIDs() -> Set<OfflineMapRegionID> {
        Set(installedRegionsValue.map(\.id))
    }

    func capturedRouteContract() -> (OfflineRouteMode?, OfflineTruckConstraints?) {
        (lastRouteMode, lastTruckConstraints)
    }

    func statistics() -> FakeOfflineMapEngineStatistics {
        statisticsValue
    }

    func inspect(
        connectivityPolicy: OfflineMapConnectivityPolicy
    ) async -> OfflineMapEngineInspection {
        statisticsValue.inspectedConnectivityPolicies.append(connectivityPolicy)
        return OfflineMapEngineInspection(
            capabilities: capabilities,
            blockers: blockers,
            persistentHealth: persistentHealth,
            radioSilenceState: connectivityPolicy == .radioSilent
                ? radioSilenceState
                : .notRequested,
            inspectedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func applyConnectivityPolicy(
        _ policy: OfflineMapConnectivityPolicy
    ) async throws -> OfflineMapRadioSilenceState {
        statisticsValue.appliedConnectivityPolicies.append(policy)
        if rejectedConnectivityPolicy == policy, let connectivityPolicyFailure {
            throw connectivityPolicyFailure
        }
        if policy == .radioSilent {
            return radioSilenceState
        }
        return .notRequested
    }

    func downloadableRegions() async throws -> [OfflineMapDownloadableRegion] {
        if let catalogFailure { throw catalogFailure }
        return downloadableRegionsValue
    }

    func installedRegions() async throws -> [OfflineMapInstalledRegion] {
        if let installedFailure { throw installedFailure }
        return installedRegionsValue
    }

    func storageSnapshot() async throws -> OfflineMapStorageSnapshot {
        if let storageFailure { throw storageFailure }
        return storageValue
    }

    func downloadByteEstimate(
        for regionIDs: [OfflineMapRegionID]
    ) async throws -> OfflineMapByteEstimate? {
        _ = regionIDs
        statisticsValue.downloadEstimateCalls += 1
        return downloadEstimateValue
    }

    func persistentMapUpdateByteEstimate() async throws -> OfflineMapByteEstimate? {
        statisticsValue.updateEstimateCalls += 1
        return updateEstimateValue
    }

    func downloadRegions(
        _ regionIDs: [OfflineMapRegionID],
        progress: @escaping OfflineMapProgressHandler
    ) async throws {
        statisticsValue.downloadCalls += 1
        activeTransferProgress = progress
        defer { activeTransferProgress = nil }
        downloadStarted = true
        let waiters = downloadStartWaiters
        downloadStartWaiters.removeAll()
        waiters.forEach { $0.resume() }
        progress(
            try OfflineMapTransferProgress(
                completedBytes: 50,
                totalBytes: 200,
                fractionCompleted: 0.25,
                regionID: regionIDs.first,
                detail: "Downloading deterministic fake coverage."
            )
        )
        try await holdTransferIfNeeded()
        if let downloadFailureAfterIncomplete {
            try setTargetInstalledState(.incomplete)
            if let persistentHealthAfterDownloadFailure {
                persistentHealth = persistentHealthAfterDownloadFailure
            }
            throw downloadFailureAfterIncomplete
        }
        progress(
            try OfflineMapTransferProgress(
                completedBytes: 200,
                totalBytes: 200,
                fractionCompleted: 1,
                regionID: regionIDs.first,
                detail: "Fake coverage installed."
            )
        )
        guard !forceReadbackMismatch else { return }
        for regionID in regionIDs {
            let name = downloadableRegionsValue.first(where: { $0.id == regionID })?.name
                ?? regionID.rawValue
            let completedRegion = try OfflineMapInstalledRegion(
                id: regionID,
                name: name,
                installedBytes: 200,
                catalogVersion: "catalog-1",
                state: .installed,
                installedAt: Date(timeIntervalSince1970: 1_700_000_001),
                lastVerifiedAt: Date(timeIntervalSince1970: 1_700_000_001)
            )
            if let existingIndex = installedRegionsValue.firstIndex(where: { $0.id == regionID }) {
                installedRegionsValue[existingIndex] = completedRegion
            } else {
                installedRegionsValue.append(completedRegion)
            }
        }
    }

    func deleteRegions(
        _ regionIDs: [OfflineMapRegionID],
        progress: @escaping OfflineMapProgressHandler
    ) async throws {
        statisticsValue.deleteCalls += 1
        progress(try OfflineMapTransferProgress(fractionCompleted: 0.5, regionID: regionIDs.first))
        try await holdTransferIfNeeded()
        guard !forceReadbackMismatch else { return }
        let targets = Set(regionIDs)
        installedRegionsValue.removeAll { targets.contains($0.id) }
    }

    func repairPersistentMap(
        progress: @escaping OfflineMapProgressHandler
    ) async throws {
        statisticsValue.repairCalls += 1
        progress(try OfflineMapTransferProgress(fractionCompleted: 0.5, detail: "Repairing fake map."))
        try await holdTransferIfNeeded()
        persistentHealth = .healthy(
            catalogVersion: "catalog-repaired",
            verifiedAt: Date(timeIntervalSince1970: 1_700_000_002)
        )
    }

    func updatePersistentMap(
        progress: @escaping OfflineMapProgressHandler
    ) async throws {
        statisticsValue.updateCalls += 1
        progress(try OfflineMapTransferProgress(fractionCompleted: 0.5, detail: "Updating fake map."))
        try await holdTransferIfNeeded()
        guard !forceReadbackMismatch else { return }
        installedRegionsValue = try installedRegionsValue.map { region in
            guard region.state == .updateAvailable else { return region }
            return try OfflineMapInstalledRegion(
                id: region.id,
                name: region.name,
                installedBytes: region.installedBytes,
                catalogVersion: "catalog-1",
                state: .installed,
                installedAt: region.installedAt,
                lastVerifiedAt: Date(timeIntervalSince1970: 1_700_000_002)
            )
        }
    }

    func pauseActiveTransfer() async throws {
        statisticsValue.pauseCalls += 1
    }

    func resumeActiveTransfer() async throws {
        statisticsValue.resumeCalls += 1
    }

    func cancelActiveTransfer() async throws {
        statisticsValue.cancelCalls += 1
        if exposeIncompleteOnCancellation {
            try setTargetInstalledState(.incomplete)
        }
        let continuation = transferContinuation
        transferContinuation = nil
        continuation?.resume(throwing: CancellationError())
    }

    func searchOffline(_ request: OfflineSearchRequest) async throws -> OfflineSearchResponse {
        _ = request
        let coverage = try coverageEvidence()
        guard let regionID = coverage.regionIDs.first else {
            throw OfflineMapCoreError.invalidInput("Fake search coverage is empty.")
        }
        let results = try (0 ..< searchResultCount).map { index in
            try OfflineSearchResult(
                id: "fake-search-\(index)",
                title: "Offline result \(index)",
                address: nil,
                coordinate: try OfflineGeoCoordinate(
                    latitude: 29.7604 + Double(index) * 0.001,
                    longitude: -95.3698
                ),
                categories: ["fixture"],
                regionID: regionID
            )
        }
        return try OfflineSearchResponse(
            results: results,
            coverage: coverage,
            searchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func calculateOfflineRoute(_ request: OfflineRouteRequest) async throws -> OfflineRouteResponse {
        lastRouteMode = request.mode
        lastTruckConstraints = request.truckConstraints
        let summary = try OfflineRouteSummary(distanceMeters: 1_000, durationSeconds: 600)
        let section = try OfflineRouteSection(
            coordinates: request.waypoints.map(\.coordinate),
            maneuvers: [],
            summary: summary
        )
        let coverage = try coverageEvidence()
        let route = try OfflineLocalRoute(
            id: "fake-local-route",
            mode: request.mode,
            sections: [section],
            summary: summary,
            notices: [],
            coverage: coverage
        )
        return try OfflineRouteResponse(
            requestID: request.id,
            routes: [route],
            coverage: coverage,
            calculatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func holdTransferIfNeeded() async throws {
        guard holdTransfers else { return }
        try await withCheckedThrowingContinuation { continuation in
            transferContinuation = continuation
        }
    }

    private func coverageEvidence() throws -> OfflineInstalledCoverageEvidence {
        try OfflineInstalledCoverageEvidence(
            regionIDs: coverageRegionIDsOverride
                ?? installedRegionsValue.filter { $0.state.isUsableCoverage }.map(\.id)
        )
    }
}
