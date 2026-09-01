//
//  OfflineMapModels.swift
//  EusoTrip
//
//  SDK-independent truth model for persistent HERE map data. This file does
//  not imply that the Navigate SDK, credentials, or a region are available;
//  an adapter must prove each capability at runtime.
//

import Foundation

enum OfflineMapByteMath {
    static func sum<S: Sequence>(_ values: S) -> Int64? where S.Element == Int64 {
        var total: Int64 = 0
        for value in values {
            let addition = total.addingReportingOverflow(value)
            guard !addition.overflow else { return nil }
            total = addition.partialValue
        }
        return total
    }
}

struct OfflineMapRegionID: Hashable, Codable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(_ rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw OfflineMapCoreError.invalidInput("A map region identifier cannot be empty.")
        }
        self.rawValue = value
    }

    var description: String { rawValue }

    private init(validatedRawValue: String) {
        rawValue = validatedRawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "A map region identifier cannot be empty."
            )
        }
        self.init(validatedRawValue: value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct OfflineMapCapabilities: OptionSet, Hashable, Sendable, Codable {
    let rawValue: UInt64

    init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    static let persistentRegionLifecycle = Self(rawValue: 1 << 0)
    static let offlineVectorRendering = Self(rawValue: 1 << 1)
    static let offlineSearch = Self(rawValue: 1 << 2)
    static let offlineRoadRouting = Self(rawValue: 1 << 3)
    static let offlineTruckRouting = Self(rawValue: 1 << 4)
    static let offlineGuidance = Self(rawValue: 1 << 5)
    static let radioSilence = Self(rawValue: 1 << 6)
    static let persistentMapRepair = Self(rawValue: 1 << 7)
    static let persistentMapUpdates = Self(rawValue: 1 << 8)
    static let detailedRendering = Self(rawValue: 1 << 9)
    /// Proves that HERE maneuver text can be spoken by an installed,
    /// device-local voice without a network connection. Text/event guidance
    /// alone is represented by `offlineGuidance` and is not audible parity.
    static let offlineVoiceGuidance = Self(rawValue: 1 << 10)

    /// Capabilities required before EusoTrip can describe the road-freight
    /// experience as fully offline. Terrain or editorial content must be
    /// represented separately and never inferred from this set.
    static let fullRoadFreightParity: Self = [
        .persistentRegionLifecycle,
        .offlineVectorRendering,
        .offlineSearch,
        .offlineRoadRouting,
        .offlineTruckRouting,
        .offlineGuidance,
        .offlineVoiceGuidance,
        .radioSilence,
        .persistentMapRepair,
        .persistentMapUpdates
    ]

    var individualCapabilities: [Self] {
        [
            .persistentRegionLifecycle,
            .offlineVectorRendering,
            .offlineSearch,
            .offlineRoadRouting,
            .offlineTruckRouting,
            .offlineGuidance,
            .radioSilence,
            .persistentMapRepair,
            .persistentMapUpdates,
            .detailedRendering,
            .offlineVoiceGuidance
        ].filter(contains)
    }
}

enum OfflineMapConnectivityPolicy: String, Codable, Sendable, CaseIterable {
    /// The SDK may use the network when it has no local answer.
    case onlineAllowed
    /// Prefer installed data, while permitting an explicit online fallback.
    case preferOffline
    /// Prohibit SDK network access. The adapter must confirm enforcement.
    case radioSilent
}

enum OfflineMapRadioSilenceState: Equatable, Sendable {
    case notRequested
    case applying
    case enforced
    case notEnforced(reason: String)
}

enum OfflineMapReadinessBlockerCode: String, Codable, Sendable {
    case sdkUnavailable
    case sdkInitializationFailed
    case credentialsUnavailable
    case entitlementUnavailable
    case persistentMapUnavailable
    case persistentMapNeedsRepair
    case capabilityUnavailable
    case radioSilenceNotEnforced
    case configurationInvalid
}

struct OfflineMapReadinessBlocker: Hashable, Codable, Sendable {
    let code: OfflineMapReadinessBlockerCode
    let message: String
    let recovery: String?

    init(code: OfflineMapReadinessBlockerCode, message: String, recovery: String? = nil) {
        self.code = code
        self.message = message
        self.recovery = recovery
    }
}

enum OfflineMapReadiness: Equatable, Sendable {
    case unchecked
    case checking
    case blocked([OfflineMapReadinessBlocker])
    case limited(available: OfflineMapCapabilities, missing: OfflineMapCapabilities)
    case ready(OfflineMapCapabilities)
}

enum OfflinePersistentMapHealth: Equatable, Sendable {
    case unknown
    case healthy(catalogVersion: String?, verifiedAt: Date)
    case needsRepair(reason: String)
    case repairing
    case unusable(reason: String)

    var permitsRegionMutation: Bool {
        switch self {
        case .healthy:
            return true
        case .unknown, .needsRepair, .repairing, .unusable:
            return false
        }
    }
}

enum OfflineMapRegionLevel: String, Codable, Sendable {
    case world
    case continent
    case country
    case stateOrProvince
    case county
    case city
    case customArea
    case other
}

struct OfflineMapDownloadableRegion: Identifiable, Hashable, Codable, Sendable {
    let id: OfflineMapRegionID
    let name: String
    let level: OfflineMapRegionLevel
    let parentID: OfflineMapRegionID?
    let childCount: Int
    /// Nil means the SDK did not provide a trustworthy estimate.
    let estimatedDownloadBytes: Int64?

    init(
        id: OfflineMapRegionID,
        name: String,
        level: OfflineMapRegionLevel,
        parentID: OfflineMapRegionID?,
        childCount: Int,
        estimatedDownloadBytes: Int64?
    ) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OfflineMapCoreError.invalidInput("A downloadable region must have a name.")
        }
        guard childCount >= 0 else {
            throw OfflineMapCoreError.invalidInput("A region child count cannot be negative.")
        }
        if let estimatedDownloadBytes, estimatedDownloadBytes < 0 {
            throw OfflineMapCoreError.invalidInput("A region byte estimate cannot be negative.")
        }
        self.id = id
        self.name = name
        self.level = level
        self.parentID = parentID
        self.childCount = childCount
        self.estimatedDownloadBytes = estimatedDownloadBytes
    }
}

enum OfflineMapInstalledRegionState: String, Codable, Sendable {
    case installed
    case updateAvailable
    /// Installed bytes are usable, but no connected catalog check has proven
    /// whether a newer persistent-map version exists.
    case updateStatusUnknown
    case pausedDownload
    case incomplete

    var isUsableCoverage: Bool {
        switch self {
        case .installed, .updateAvailable, .updateStatusUnknown:
            return true
        case .pausedDownload, .incomplete:
            return false
        }
    }

    var isResumableTransfer: Bool {
        self == .pausedDownload || self == .incomplete
    }
}

struct OfflineMapInstalledRegion: Identifiable, Hashable, Codable, Sendable {
    let id: OfflineMapRegionID
    let name: String
    let installedBytes: Int64
    let catalogVersion: String?
    let state: OfflineMapInstalledRegionState
    let installedAt: Date?
    let lastVerifiedAt: Date?

    init(
        id: OfflineMapRegionID,
        name: String,
        installedBytes: Int64,
        catalogVersion: String?,
        state: OfflineMapInstalledRegionState,
        installedAt: Date?,
        lastVerifiedAt: Date?
    ) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OfflineMapCoreError.invalidInput("An installed region must have a name.")
        }
        guard installedBytes >= 0 else {
            throw OfflineMapCoreError.invalidInput("Installed bytes cannot be negative.")
        }
        self.id = id
        self.name = name
        self.installedBytes = installedBytes
        self.catalogVersion = catalogVersion
        self.state = state
        self.installedAt = installedAt
        self.lastVerifiedAt = lastVerifiedAt
    }
}

struct OfflineMapStorageSnapshot: Equatable, Sendable {
    /// Capacity the operating system reports as available for this app.
    let availableBytes: Int64
    let installedMapBytes: Int64
    let measuredAt: Date

    init(availableBytes: Int64, installedMapBytes: Int64, measuredAt: Date = Date()) throws {
        guard availableBytes >= 0, installedMapBytes >= 0 else {
            throw OfflineMapCoreError.invalidInput("Storage byte counts cannot be negative.")
        }
        self.availableBytes = availableBytes
        self.installedMapBytes = installedMapBytes
        self.measuredAt = measuredAt
    }
}

struct OfflineMapStoragePolicy: Equatable, Sendable {
    /// Free space that must remain after the operation. The app layer owns the
    /// policy value; the core never invents a device-independent threshold.
    let minimumPostOperationFreeBytes: Int64

    /// Optional staging bytes per installed-map byte for catalog updates.
    /// When HERE exposes no update size, the coordinator may use this explicit
    /// policy calculation. Nil preserves "unknown means blocked". The chosen
    /// multiplier belongs in the app composition layer, not this core.
    let updateStagingBytesPerInstalledByte: Double?

    init(
        minimumPostOperationFreeBytes: Int64,
        updateStagingBytesPerInstalledByte: Double? = nil
    ) throws {
        guard minimumPostOperationFreeBytes >= 0 else {
            throw OfflineMapCoreError.invalidInput("The storage reserve cannot be negative.")
        }
        if let updateStagingBytesPerInstalledByte {
            guard updateStagingBytesPerInstalledByte.isFinite,
                  updateStagingBytesPerInstalledByte > 0 else {
                throw OfflineMapCoreError.invalidInput(
                    "The update staging multiplier must be a positive finite number."
                )
            }
        }
        self.minimumPostOperationFreeBytes = minimumPostOperationFreeBytes
        self.updateStagingBytesPerInstalledByte = updateStagingBytesPerInstalledByte
    }
}

enum OfflineMapByteEstimateConfidence: String, Codable, Sendable {
    case exact
    case sdkEstimate
    /// A caller-configured conservative staging calculation. It is never
    /// presented as a value reported by HERE.
    case policyEstimate
}

struct OfflineMapByteEstimate: Equatable, Sendable {
    let requiredBytes: Int64
    let confidence: OfflineMapByteEstimateConfidence

    init(requiredBytes: Int64, confidence: OfflineMapByteEstimateConfidence) throws {
        guard requiredBytes >= 0 else {
            throw OfflineMapCoreError.invalidInput("Required bytes cannot be negative.")
        }
        self.requiredBytes = requiredBytes
        self.confidence = confidence
    }
}

enum OfflineMapStoragePreflight: Equatable, Sendable {
    case accepted(
        estimate: OfflineMapByteEstimate,
        storage: OfflineMapStorageSnapshot,
        remainingBytesAfterOperation: Int64
    )
    case blocked(
        estimate: OfflineMapByteEstimate,
        storage: OfflineMapStorageSnapshot,
        requiredReserveBytes: Int64,
        shortfallBytes: Int64
    )
}

enum OfflineMapOperationKind: String, Codable, Sendable {
    case downloadRegions
    case deleteRegions
    case repairPersistentMap
    case updatePersistentMap
}

enum OfflineMapOperationPhase: String, Codable, Sendable {
    case preparing
    case running
    case pausing
    case paused
    case resuming
    case cancelling
    case finalizing
}

struct OfflineMapTransferProgress: Equatable, Sendable {
    let completedBytes: Int64?
    let totalBytes: Int64?
    let fractionCompleted: Double?
    let regionID: OfflineMapRegionID?
    let detail: String?
    /// HERE may pause a transfer itself after retry exhaustion. This lets the
    /// adapter report that callback so the coordinator exposes Resume instead
    /// of leaving a physically paused task labeled as running.
    let reportedPhase: OfflineMapOperationPhase?

    init(
        completedBytes: Int64? = nil,
        totalBytes: Int64? = nil,
        fractionCompleted: Double? = nil,
        regionID: OfflineMapRegionID? = nil,
        detail: String? = nil,
        reportedPhase: OfflineMapOperationPhase? = nil
    ) throws {
        if let completedBytes, completedBytes < 0 {
            throw OfflineMapCoreError.invalidInput("Completed bytes cannot be negative.")
        }
        if let totalBytes, totalBytes < 0 {
            throw OfflineMapCoreError.invalidInput("Total bytes cannot be negative.")
        }
        if let completedBytes, let totalBytes, completedBytes > totalBytes {
            throw OfflineMapCoreError.invalidInput("Completed bytes cannot exceed total bytes.")
        }
        if let fractionCompleted, !(0 ... 1).contains(fractionCompleted) {
            throw OfflineMapCoreError.invalidInput("Progress must be between zero and one.")
        }
        if let reportedPhase,
           reportedPhase != .running,
           reportedPhase != .paused {
            throw OfflineMapCoreError.invalidInput(
                "An engine transfer callback may report only running or paused."
            )
        }
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.fractionCompleted = fractionCompleted
        self.regionID = regionID
        self.detail = detail
        self.reportedPhase = reportedPhase
    }
}

struct OfflineMapOperationState: Equatable, Sendable {
    let id: UUID
    let kind: OfflineMapOperationKind
    let targetRegionIDs: [OfflineMapRegionID]
    var phase: OfflineMapOperationPhase
    var progress: OfflineMapTransferProgress?
    let startedAt: Date
}

struct OfflineMapFailure: Error, Equatable, Sendable {
    let code: String
    let message: String
    let recovery: String?
    let isRecoverable: Bool

    init(code: String, message: String, recovery: String? = nil, isRecoverable: Bool) {
        self.code = code
        self.message = message
        self.recovery = recovery
        self.isRecoverable = isRecoverable
    }
}

/// Independent truth state for each inventory feed. A stale downloadable
/// catalog must not erase working installed maps during a cold radio-silent
/// launch, while mutation controls can still require a current feed.
enum OfflineMapInventoryFeedState: Equatable, Sendable {
    case notLoaded
    case loading(lastSuccessfulAt: Date?)
    case current(loadedAt: Date)
    case stale(lastSuccessfulAt: Date, failure: OfflineMapFailure)
    case unavailable(failure: OfflineMapFailure)

    var lastSuccessfulAt: Date? {
        switch self {
        case .notLoaded, .unavailable:
            return nil
        case .loading(let date):
            return date
        case .current(let date), .stale(let date, _):
            return date
        }
    }

    var isCurrent: Bool {
        if case .current = self { return true }
        return false
    }
}

protocol OfflineMapFailureProviding: Error {
    var offlineMapFailure: OfflineMapFailure { get }
}

enum OfflineMapCoreError: Error, Equatable, Sendable {
    case invalidInput(String)
    case busy(activeOperation: OfflineMapOperationKind)
    case coordinatorBusy(String)
    case notReady([OfflineMapReadinessBlocker])
    case missingCapabilities(OfflineMapCapabilities)
    case unknownRegions([OfflineMapRegionID])
    case storageEstimateUnavailable
    case insufficientStorage(requiredBytes: Int64, availableBytes: Int64, reserveBytes: Int64)
    case operationNotPausable
    case operationNotPaused
    case operationNotCancellable
    case unsupportedLocalRouting(OfflineRouteMode)
    case engineFailure(OfflineMapFailure)
}

extension OfflineMapCoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return message
        case .busy(let operation):
            return "An offline map \(operation.rawValue) operation is already active."
        case .coordinatorBusy(let command):
            return "Offline map \(command) is already in progress."
        case .notReady(let blockers):
            return blockers.map(\.message).joined(separator: " ")
        case .missingCapabilities:
            return "This offline map engine does not provide every required capability."
        case .unknownRegions:
            return "One or more selected offline map regions are unavailable."
        case .storageEstimateUnavailable:
            return "The download size is unknown, so storage safety cannot be verified."
        case .insufficientStorage:
            return "There is not enough device storage for this offline map operation."
        case .operationNotPausable:
            return "There is no active offline map transfer to pause."
        case .operationNotPaused:
            return "There is no paused offline map transfer to resume."
        case .operationNotCancellable:
            return "There is no active offline map transfer to cancel."
        case .unsupportedLocalRouting(let mode):
            return "\(mode.rawValue.capitalized) routes require the server canonical route and cannot be calculated by HERE offline routing."
        case .engineFailure(let failure):
            return failure.message
        }
    }
}

struct OfflineMapEngineInspection: Equatable, Sendable {
    let capabilities: OfflineMapCapabilities
    let blockers: [OfflineMapReadinessBlocker]
    let persistentHealth: OfflinePersistentMapHealth
    let radioSilenceState: OfflineMapRadioSilenceState
    let inspectedAt: Date

    init(
        capabilities: OfflineMapCapabilities,
        blockers: [OfflineMapReadinessBlocker],
        persistentHealth: OfflinePersistentMapHealth,
        radioSilenceState: OfflineMapRadioSilenceState,
        inspectedAt: Date = Date()
    ) {
        self.capabilities = capabilities
        self.blockers = blockers
        self.persistentHealth = persistentHealth
        self.radioSilenceState = radioSilenceState
        self.inspectedAt = inspectedAt
    }
}

struct OfflineMapSnapshot: Equatable, Sendable {
    /// Native-engine health and capability readiness only. Journey/corridor
    /// departure authority requires a separate, explicit coverage requirement
    /// and must never be inferred from this value.
    var readiness: OfflineMapReadiness = .unchecked
    /// Capabilities observed during the latest native-engine inspection.
    /// Kept independent from engine readiness so a narrowly scoped recovery
    /// command can be proven while persistent-map health is blocked.
    var availableCapabilities: OfflineMapCapabilities = []
    var connectivityPolicy: OfflineMapConnectivityPolicy = .onlineAllowed
    var radioSilenceState: OfflineMapRadioSilenceState = .notRequested
    var persistentHealth: OfflinePersistentMapHealth = .unknown
    var downloadableRegions: [OfflineMapDownloadableRegion] = []
    var downloadableCatalogState: OfflineMapInventoryFeedState = .notLoaded
    var installedRegions: [OfflineMapInstalledRegion] = []
    var installedRegionsState: OfflineMapInventoryFeedState = .notLoaded
    var storage: OfflineMapStorageSnapshot?
    var storageState: OfflineMapInventoryFeedState = .notLoaded
    var activeOperation: OfflineMapOperationState?
    var lastFailure: OfflineMapFailure?
    var lastRefreshedAt: Date?
}
