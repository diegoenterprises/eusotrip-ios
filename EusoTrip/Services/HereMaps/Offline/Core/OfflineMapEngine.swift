//
//  OfflineMapEngine.swift
//  EusoTrip
//
//  Narrow adapter boundary. A HERE Navigate implementation belongs outside
//  Core and must translate SDK callbacks into these truthful contracts.
//

import Foundation

typealias OfflineMapProgressHandler = @Sendable (OfflineMapTransferProgress) -> Void

protocol OfflineMapLifecycleProviding: Sendable {
    /// Inspection returns blockers instead of manufacturing a ready state.
    /// It must not include credential values or secret-bearing SDK messages.
    func inspect(connectivityPolicy: OfflineMapConnectivityPolicy) async -> OfflineMapEngineInspection

    /// Applies the requested network policy and reports whether radio silence
    /// is actually enforced. Returning `.notEnforced` for `.radioSilent` keeps
    /// the coordinator out of the ready state.
    func applyConnectivityPolicy(
        _ policy: OfflineMapConnectivityPolicy
    ) async throws -> OfflineMapRadioSilenceState

    func downloadableRegions() async throws -> [OfflineMapDownloadableRegion]
    func installedRegions() async throws -> [OfflineMapInstalledRegion]
    func storageSnapshot() async throws -> OfflineMapStorageSnapshot

    /// Nil means the SDK could not provide a trustworthy estimate. The
    /// coordinator blocks the download rather than gambling with device space.
    func downloadByteEstimate(
        for regionIDs: [OfflineMapRegionID]
    ) async throws -> OfflineMapByteEstimate?

    /// Update staging can temporarily require substantial free space. Nil is
    /// treated as unverifiable and the coordinator will not start the update.
    func persistentMapUpdateByteEstimate() async throws -> OfflineMapByteEstimate?

    func downloadRegions(
        _ regionIDs: [OfflineMapRegionID],
        progress: @escaping OfflineMapProgressHandler
    ) async throws

    func deleteRegions(
        _ regionIDs: [OfflineMapRegionID],
        progress: @escaping OfflineMapProgressHandler
    ) async throws

    func repairPersistentMap(
        progress: @escaping OfflineMapProgressHandler
    ) async throws

    func updatePersistentMap(
        progress: @escaping OfflineMapProgressHandler
    ) async throws

    /// Transfer controls apply only to the active download/update task. The
    /// adapter should throw a typed failure when its SDK task rejects a control.
    func pauseActiveTransfer() async throws
    func resumeActiveTransfer() async throws
    func cancelActiveTransfer() async throws
}

protocol OfflineLocalSearchProviding: Sendable {
    func searchOffline(_ request: OfflineSearchRequest) async throws -> OfflineSearchResponse
}

protocol OfflineRoadRoutingProviding: Sendable {
    func calculateOfflineRoute(_ request: OfflineRouteRequest) async throws -> OfflineRouteResponse
}

protocol OfflineMapEngine:
    OfflineMapLifecycleProviding,
    OfflineLocalSearchProviding,
    OfflineRoadRoutingProviding,
    Sendable
{}
