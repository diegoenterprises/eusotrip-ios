//
//  OfflineMapLibraryViewModel.swift
//  EusoTrip
//
//  UI adapter for the offline-map coordinator. It owns presentation-only
//  selection and confirmation state; every mutation remains coordinator-owned.
//

import Combine
import Foundation

enum OfflineMapLibraryScope: String, CaseIterable, Identifiable {
    case installed
    case available
    case updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .installed: return "Installed"
        case .available: return "Available"
        case .updates: return "Updates"
        }
    }

    var systemImage: String {
        switch self {
        case .installed: return "checkmark.circle"
        case .available: return "square.and.arrow.down"
        case .updates: return "arrow.triangle.2.circlepath"
        }
    }
}

struct OfflineMapRegionRegisterEntry: Identifiable {
    let region: OfflineMapDownloadableRegion
    let depth: Int

    var id: OfflineMapRegionID { region.id }
}

struct OfflineMapCommandAvailability {
    let isEnabled: Bool
    let disabledReason: String?

    static let enabled = Self(isEnabled: true, disabledReason: nil)

    static func disabled(_ reason: String) -> Self {
        Self(isEnabled: false, disabledReason: reason)
    }
}

struct OfflineMapLibraryFeedback: Identifiable, Equatable {
    enum Kind {
        case information
        case success
        case failure
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let message: String
}

struct OfflineMapLibraryPendingAction: Identifiable {
    enum Kind {
        case download([OfflineMapRegionID])
        case delete([OfflineMapRegionID])
        case update
        case repair
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let message: String
    let confirmLabel: String
    let isDestructive: Bool
}

@MainActor
final class OfflineMapLibraryViewModel: ObservableObject {
    @Published private(set) var snapshot: OfflineMapSnapshot
    @Published var scope: OfflineMapLibraryScope = .installed
    @Published private(set) var installedSelection = Set<OfflineMapRegionID>()
    @Published private(set) var availableSelection = Set<OfflineMapRegionID>()
    @Published var feedback: OfflineMapLibraryFeedback?
    @Published var pendingAction: OfflineMapLibraryPendingAction?
    @Published private(set) var isSubmitting = false

    private let coordinator: OfflineMapCoordinator
    private var cancellables = Set<AnyCancellable>()
    private var coordinatorObservationID: UUID?
    private var productionPrepare: (() async -> Void)?
    private var productionConnectivityTransition: ((OfflineMapConnectivityPolicy) async throws -> Void)?
    private var productionRepair: (() async throws -> Void)?

    init(owner: OfflineMapCompositionOwner) {
        coordinator = owner.coordinator
        snapshot = owner.snapshot
        owner.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.snapshot = snapshot
                self?.reconcileSelections()
            }
            .store(in: &cancellables)
    }

    convenience init(productionComposition: OfflineMapProductionComposition) {
        self.init(owner: productionComposition.owner)
        productionPrepare = { [weak productionComposition] in
            await productionComposition?.prepare()
        }
        productionConnectivityTransition = { [weak productionComposition] policy in
            guard let productionComposition else {
                throw OfflineMapCoreError.coordinatorBusy(
                    "the app-owned offline map composition is unavailable"
                )
            }
            try await productionComposition.setConnectivityPolicy(policy)
        }
        productionRepair = { [weak productionComposition] in
            guard let productionComposition else {
                throw OfflineMapCoreError.coordinatorBusy(
                    "the app-owned offline map composition is unavailable"
                )
            }
            try await productionComposition.repairPersistentMap()
        }
    }

    /// Isolated injection seam for focused tests. Production composition must
    /// use the app-scoped owner so multiple windows multicast the same state.
    init(coordinator: OfflineMapCoordinator) {
        self.coordinator = coordinator
        snapshot = coordinator.snapshot
        coordinatorObservationID = coordinator.addSnapshotObserver { [weak self] snapshot in
            self?.snapshot = snapshot
            self?.reconcileSelections()
        }
    }

    var updateRegions: [OfflineMapInstalledRegion] {
        snapshot.installedRegions.filter { $0.state == .updateAvailable }
    }

    var updateStatusUnknownRegions: [OfflineMapInstalledRegion] {
        snapshot.installedRegions.filter { $0.state == .updateStatusUnknown }
    }

    var updateRegisterRegions: [OfflineMapInstalledRegion] {
        snapshot.installedRegions.filter {
            $0.state == .updateAvailable || $0.state == .updateStatusUnknown
        }
    }

    var availableRegionEntries: [OfflineMapRegionRegisterEntry] {
        let regions = snapshot.downloadableRegions
        guard !regions.isEmpty else { return [] }

        let knownIDs = Set(regions.map(\.id))
        var children = [OfflineMapRegionID?: [OfflineMapDownloadableRegion]]()
        for region in regions {
            let parent = region.parentID.flatMap { knownIDs.contains($0) ? $0 : nil }
            children[parent, default: []].append(region)
        }
        for key in Array(children.keys) {
            children[key]?.sort {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }

        var entries: [OfflineMapRegionRegisterEntry] = []
        var visited = Set<OfflineMapRegionID>()

        func append(_ region: OfflineMapDownloadableRegion, depth: Int) {
            guard visited.insert(region.id).inserted else { return }
            entries.append(.init(region: region, depth: depth))
            for child in children[region.id] ?? [] {
                append(child, depth: depth + 1)
            }
        }

        for root in children[nil] ?? [] {
            append(root, depth: 0)
        }
        // A cyclic or incomplete SDK hierarchy must remain visible instead of
        // disappearing from the text-equivalent register.
        for orphan in regions where !visited.contains(orphan.id) {
            append(orphan, depth: 0)
        }
        return entries
    }

    var downloadAvailability: OfflineMapCommandAvailability {
        if availableSelection.isEmpty {
            return .disabled("Select at least one available region.")
        }
        if let reason = mutationBlockReason(requiring: .persistentRegionLifecycle) {
            return .disabled(reason)
        }
        guard snapshot.downloadableCatalogState.isCurrent else {
            return .disabled(feedMutationReason(
                snapshot.downloadableCatalogState,
                feedName: "downloadable region catalog"
            ))
        }
        guard snapshot.persistentHealth.permitsRegionMutation else {
            return .disabled("Persistent map health must be verified as healthy before a download.")
        }
        guard snapshot.connectivityPolicy == .onlineAllowed else {
            return .disabled("Allow network access for setup before downloading HERE coverage.")
        }
        return .enabled
    }

    var deleteAvailability: OfflineMapCommandAvailability {
        if installedSelection.isEmpty {
            return .disabled("Select at least one installed region.")
        }
        if let reason = mutationBlockReason(requiring: .persistentRegionLifecycle) {
            return .disabled(reason)
        }
        guard modelFeedIsCurrent(snapshot.installedRegionsState) else {
            return .disabled(feedMutationReason(
                snapshot.installedRegionsState,
                feedName: "installed region inventory"
            ))
        }
        guard snapshot.persistentHealth.permitsRegionMutation else {
            return .disabled("Persistent map health must be verified as healthy before deletion.")
        }
        return .enabled
    }

    var updateAvailability: OfflineMapCommandAvailability {
        guard modelFeedIsCurrent(snapshot.installedRegionsState) else {
            return .disabled(feedMutationReason(
                snapshot.installedRegionsState,
                feedName: "installed region inventory"
            ))
        }
        if updateRegions.isEmpty {
            if !updateStatusUnknownRegions.isEmpty {
                return .disabled("Update status is unknown for \(updateStatusUnknownRegions.count) installed region\(updateStatusUnknownRegions.count == 1 ? "" : "s"). Allow network access and recheck before updating.")
            }
            return .disabled("No installed region currently reports an available update.")
        }
        if let reason = mutationBlockReason(requiring: .persistentMapUpdates) {
            return .disabled(reason)
        }
        guard snapshot.persistentHealth.permitsRegionMutation else {
            return .disabled("Persistent map health must be verified as healthy before updating.")
        }
        guard snapshot.connectivityPolicy == .onlineAllowed else {
            return .disabled("Allow network access for setup before updating HERE coverage.")
        }
        return .enabled
    }

    var repairAvailability: OfflineMapCommandAvailability {
        if let active = snapshot.activeOperation {
            return .disabled("Finish or cancel the active \(operationName(active.kind).lowercased()) first.")
        }
        switch snapshot.persistentHealth {
        case .needsRepair, .unusable:
            guard snapshot.availableCapabilities.contains(.persistentMapRepair) else {
                return .disabled("The native HERE engine did not prove persistent-map repair support.")
            }
            if case .blocked(let blockers) = snapshot.readiness,
               let hardBlocker = blockers.first(where: {
                   [.sdkUnavailable, .sdkInitializationFailed, .credentialsUnavailable,
                    .entitlementUnavailable, .configurationInvalid, .capabilityUnavailable].contains($0.code)
               }) {
                return .disabled(hardBlocker.message)
            }
            if case .blocked = snapshot.readiness {
                // Health itself can block overall readiness even though the
                // coordinator proved and retained the repair capability.
                return .enabled
            }
            guard capabilityIsAvailable(.persistentMapRepair) else {
                return .disabled(capabilityUnavailableReason(.persistentMapRepair))
            }
            return .enabled
        case .repairing:
            return .disabled("Persistent map repair is already running.")
        case .healthy:
            return .disabled("Persistent map health is verified; repair is not required.")
        case .unknown:
            return .disabled("Persistent map health is unknown. Recheck health before repair.")
        }
    }

    var refreshAvailability: OfflineMapCommandAvailability {
        if let active = snapshot.activeOperation {
            return .disabled("Finish or cancel the active \(operationName(active.kind).lowercased()) first.")
        }
        if isSubmitting { return .disabled("A map-library command is already running.") }
        switch snapshot.readiness {
        case .checking:
            return .disabled("Offline map readiness is already being checked.")
        default:
            return .enabled
        }
    }

    var policyAvailability: OfflineMapCommandAvailability {
        if let active = snapshot.activeOperation {
            return .disabled("Connectivity policy cannot change during \(operationName(active.kind).lowercased()).")
        }
        if isSubmitting { return .disabled("A map-library command is already running.") }
        if case .blocked(let blockers) = snapshot.readiness,
           let blocker = blockers.first(where: {
               [.sdkUnavailable, .sdkInitializationFailed, .credentialsUnavailable,
                .entitlementUnavailable, .configurationInvalid].contains($0.code)
           }) {
            return .disabled(blocker.message)
        }
        return .enabled
    }

    func prepare() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        await prepareCoordinator()
        isSubmitting = false
    }

    func refresh() async {
        guard refreshAvailability.isEnabled else {
            presentUnavailable(refreshAvailability)
            return
        }
        switch snapshot.readiness {
        case .unchecked, .blocked:
            isSubmitting = true
            await prepareCoordinator()
            isSubmitting = false
            feedback = checkResultFeedback(
                successTitle: "Library checked",
                successMessage: "HERE map health, coverage, and storage feeds were rechecked."
            )
        case .checking:
            return
        case .limited, .ready:
            guard !isSubmitting else { return }
            isSubmitting = true
            do {
                try await coordinator.refresh()
                feedback = checkResultFeedback(
                    successTitle: "Library checked",
                    successMessage: "HERE map health, coverage, and storage feeds were rechecked."
                )
            } catch {
                present(error, fallbackTitle: "Map-library check failed")
            }
            isSubmitting = false
        }
    }

    func setConnectivityPolicy(_ policy: OfflineMapConnectivityPolicy) async {
        guard policyAvailability.isEnabled else {
            presentUnavailable(policyAvailability)
            return
        }
        guard policy != snapshot.connectivityPolicy ||
                (policy == .radioSilent && snapshot.radioSilenceState != .enforced) else { return }
        let description: String
        switch policy {
        case .onlineAllowed:
            description = "Network access is allowed for catalog and region preparation."
        case .preferOffline:
            description = "Installed map data is preferred, with an explicit online fallback allowed."
        case .radioSilent:
            description = "The native HERE engine confirmed radio silence."
        }
        guard !isSubmitting else { return }
        isSubmitting = true
        do {
            try await applyConnectivityPolicy(policy)
            feedback = checkResultFeedback(
                successTitle: "Connectivity policy applied",
                successMessage: description
            )
        } catch {
            present(error, fallbackTitle: "Connectivity policy failed")
        }
        isSubmitting = false
    }

    func toggleAvailable(_ region: OfflineMapDownloadableRegion) {
        guard !snapshot.installedRegions.contains(where: {
            $0.id == region.id && $0.state.isUsableCoverage
        }) else { return }
        if availableSelection.remove(region.id) != nil { return }

        // Parent and child HERE regions overlap. Keep the transfer request
        // unambiguous by retaining only the most recently chosen hierarchy node.
        var parentByID: [OfflineMapRegionID: OfflineMapRegionID?] = [:]
        var catalogIDs = Set<OfflineMapRegionID>()
        for catalogRegion in snapshot.downloadableRegions {
            guard catalogIDs.insert(catalogRegion.id).inserted else {
                availableSelection.removeAll()
                return
            }
            parentByID.updateValue(catalogRegion.parentID, forKey: catalogRegion.id)
        }
        var ancestor = region.parentID
        while let id = ancestor {
            availableSelection.remove(id)
            ancestor = parentByID[id] ?? nil
        }
        availableSelection = availableSelection.filter { candidate in
            !isDescendant(candidate, of: region.id, parentByID: parentByID)
        }
        availableSelection.insert(region.id)
    }

    func toggleInstalled(_ region: OfflineMapInstalledRegion) {
        if installedSelection.remove(region.id) == nil {
            installedSelection.insert(region.id)
        }
    }

    func requestDownload() async {
        guard downloadAvailability.isEnabled else {
            presentUnavailable(downloadAvailability)
            return
        }
        let ids = Array(availableSelection)
        guard !isSubmitting else { return }
        isSubmitting = true
        do {
            let preflight = try await coordinator.preflightDownload(regionIDs: ids)
            switch preflight {
            case .accepted(let estimate, _, let remainingBytes):
                pendingAction = .init(
                    kind: .download(ids),
                    title: "Download selected coverage?",
                    message: "HERE estimates \(Self.bytes(estimate.requiredBytes)) for \(ids.count) selected region\(ids.count == 1 ? "" : "s"). \(Self.bytes(remainingBytes)) of free space will remain after the transfer, including the configured reserve.",
                    confirmLabel: "Download coverage",
                    isDestructive: false
                )
            case .blocked(let estimate, _, let reserve, let shortfall):
                feedback = .init(
                    kind: .failure,
                    title: "Storage preflight blocked",
                    message: "The transfer needs \(Self.bytes(estimate.requiredBytes)) and must preserve a \(Self.bytes(reserve)) reserve. Free an additional \(Self.bytes(shortfall)) before downloading."
                )
            }
        } catch {
            present(error, fallbackTitle: "Download preflight failed")
        }
        isSubmitting = false
    }

    func requestDelete() {
        guard deleteAvailability.isEnabled else {
            presentUnavailable(deleteAvailability)
            return
        }
        let ids = Array(installedSelection)
        let selected = snapshot.installedRegions.filter { ids.contains($0.id) }
        let bytes = OfflineMapByteMath.sum(selected.lazy.map(\.installedBytes))
        let storageAmount = bytes.map(Self.bytes) ?? "an unknown amount of storage"
        pendingAction = .init(
            kind: .delete(ids),
            title: "Remove selected coverage?",
            message: "This removes \(storageAmount) across \(ids.count) installed region\(ids.count == 1 ? "" : "s"). Installed coverage in those regions will no longer be available without connectivity.",
            confirmLabel: "Remove coverage",
            isDestructive: true
        )
    }

    func requestUpdate() {
        guard updateAvailability.isEnabled else {
            presentUnavailable(updateAvailability)
            return
        }
        pendingAction = .init(
            kind: .update,
            title: "Update installed coverage?",
            message: "HERE will update persistent map data for complete, usable installed regions. Paused or incomplete transfers remain separate. Storage is verified again before the update begins.",
            confirmLabel: "Update coverage",
            isDestructive: false
        )
    }

    func requestRepair() {
        guard repairAvailability.isEnabled else {
            presentUnavailable(repairAvailability)
            return
        }
        pendingAction = .init(
            kind: .repair,
            title: "Repair persistent map data?",
            message: "HERE will inspect and repair the on-device persistent map. Region transfers remain unavailable until repair completes.",
            confirmLabel: "Run repair",
            isDestructive: false
        )
    }

    func confirmPendingAction() async {
        guard let action = pendingAction else { return }
        pendingAction = nil
        switch action.kind {
        case .download(let ids):
            await execute(successTitle: "Coverage installed", successMessage: "The selected HERE regions are now installed on this device.") {
                try await coordinator.download(regionIDs: ids)
                availableSelection.subtract(ids)
            }
        case .delete(let ids):
            await execute(successTitle: "Coverage removed", successMessage: "The selected HERE regions were removed from this device.") {
                try await coordinator.delete(regionIDs: ids)
                installedSelection.subtract(ids)
            }
        case .update:
            await execute(successTitle: "Coverage updated", successMessage: "Installed HERE map data was updated and rechecked.") {
                try await coordinator.updatePersistentMap()
            }
        case .repair:
            await execute(successTitle: "Persistent map repaired", successMessage: "HERE persistent map health was repaired and rechecked.") {
                try await repairPersistentMap()
            }
        }
    }

    func pauseActiveTransfer() async {
        await executeTransferControl(successTitle: "Transfer paused", successMessage: "The active map transfer is paused on this device.") {
            try await coordinator.pauseActiveTransfer()
        }
    }

    func resumeActiveTransfer() async {
        await executeTransferControl(successTitle: "Transfer resumed", successMessage: "The active map transfer is continuing.") {
            try await coordinator.resumeActiveTransfer()
        }
    }

    func cancelActiveTransfer() async {
        await executeTransferControl(successTitle: "Cancellation requested", successMessage: "HERE is cancelling the active map transfer.") {
            try await coordinator.cancelActiveTransfer()
        }
    }

    func dismissFeedback() {
        feedback = nil
    }

    func capabilityIsAvailable(_ capability: OfflineMapCapabilities) -> Bool {
        switch snapshot.readiness {
        case .ready(let available), .limited(let available, _):
            return available.contains(capability)
        case .unchecked, .checking, .blocked:
            return false
        }
    }

    func capabilityUnavailableReason(_ capability: OfflineMapCapabilities) -> String {
        switch snapshot.readiness {
        case .unchecked:
            return "Offline capabilities have not been checked."
        case .checking:
            return "Offline capabilities are being checked."
        case .blocked(let blockers):
            return blockers.first?.message ?? "Offline readiness is blocked."
        case .limited(_, let missing) where missing.contains(capability):
            return "The native HERE engine did not prove this offline capability."
        case .limited, .ready:
            return "This offline capability is not available."
        }
    }

    private func prepareCoordinator() async {
        if let productionPrepare {
            await productionPrepare()
        } else {
            await coordinator.prepare()
        }
    }

    private func applyConnectivityPolicy(
        _ policy: OfflineMapConnectivityPolicy
    ) async throws {
        if let productionConnectivityTransition {
            try await productionConnectivityTransition(policy)
        } else {
            try await coordinator.setConnectivityPolicy(policy)
        }
    }

    private func repairPersistentMap() async throws {
        if let productionRepair {
            try await productionRepair()
        } else {
            try await coordinator.repairPersistentMap()
        }
    }

    func regionName(for id: OfflineMapRegionID) -> String {
        snapshot.installedRegions.first(where: { $0.id == id })?.name
            ?? snapshot.downloadableRegions.first(where: { $0.id == id })?.name
            ?? id.rawValue
    }

    func operationName(_ kind: OfflineMapOperationKind) -> String {
        switch kind {
        case .downloadRegions: return "Region download"
        case .deleteRegions: return "Region removal"
        case .repairPersistentMap: return "Persistent map repair"
        case .updatePersistentMap: return "Persistent map update"
        }
    }

    private func execute(
        successTitle: String,
        successMessage: String,
        operation: () async throws -> Void
    ) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        do {
            try await operation()
            feedback = .init(kind: .success, title: successTitle, message: successMessage)
        } catch is CancellationError {
            feedback = .init(
                kind: .information,
                title: "Cancellation finalized",
                message: "The cancellation request finished and on-device map state was rechecked. Review installed coverage before relying on it."
            )
        } catch {
            present(error, fallbackTitle: "Map-library command failed")
        }
        isSubmitting = false
    }

    private func checkResultFeedback(
        successTitle: String,
        successMessage: String
    ) -> OfflineMapLibraryFeedback {
        if case .blocked(let blockers) = snapshot.readiness {
            return .init(
                kind: .failure,
                title: "Readiness remains blocked",
                message: blockers.map(\.message).joined(separator: " ")
            )
        }

        var limitations: [String] = []
        let feeds: [(String, OfflineMapInventoryFeedState)] = [
            ("downloadable catalog", snapshot.downloadableCatalogState),
            ("installed regions", snapshot.installedRegionsState),
            ("storage", snapshot.storageState)
        ]
        for (name, state) in feeds where !state.isCurrent {
            switch state {
            case .stale:
                limitations.append("The \(name) feed is a last verified snapshot.")
            case .unavailable:
                limitations.append("The \(name) feed is unavailable.")
            case .loading:
                limitations.append("The \(name) feed is still loading.")
            case .notLoaded:
                limitations.append("The \(name) feed has not been verified.")
            case .current:
                break
            }
        }
        if case .limited = snapshot.readiness {
            limitations.append("One or more required offline capabilities remain unproven.")
        }
        if let failure = snapshot.lastFailure,
           !limitations.contains(where: { $0.contains(failure.message) }) {
            limitations.append(failure.message)
        }
        guard !limitations.isEmpty else {
            return .init(kind: .success, title: successTitle, message: successMessage)
        }
        return .init(
            kind: .information,
            title: "\(successTitle) with limitations",
            message: ([successMessage] + limitations).joined(separator: " ")
        )
    }

    /// Pause/resume/cancel are controls on the already-running coordinator
    /// operation. They must remain callable while the root download/update
    /// task is awaiting the SDK and `isSubmitting` is therefore true.
    private func executeTransferControl(
        successTitle: String,
        successMessage: String,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            feedback = .init(kind: .success, title: successTitle, message: successMessage)
        } catch {
            present(error, fallbackTitle: "Transfer control failed")
        }
    }

    private func mutationBlockReason(requiring capability: OfflineMapCapabilities) -> String? {
        if let active = snapshot.activeOperation {
            return "Finish or cancel the active \(operationName(active.kind).lowercased()) first."
        }
        if isSubmitting { return "A map-library command is already running." }
        guard capabilityIsAvailable(capability) else {
            return capabilityUnavailableReason(capability)
        }
        return nil
    }

    private func feedMutationReason(
        _ state: OfflineMapInventoryFeedState,
        feedName: String
    ) -> String {
        switch state {
        case .notLoaded:
            return "The \(feedName) has not been loaded."
        case .loading:
            return "The \(feedName) is still loading."
        case .current:
            return ""
        case .stale(_, let failure):
            return "The \(feedName) is stale: \(failure.message)"
        case .unavailable(let failure):
            return "The \(feedName) is unavailable: \(failure.message)"
        }
    }

    private func modelFeedIsCurrent(_ state: OfflineMapInventoryFeedState) -> Bool {
        if case .current = state { return true }
        return false
    }

    private func isDescendant(
        _ candidate: OfflineMapRegionID,
        of ancestor: OfflineMapRegionID,
        parentByID: [OfflineMapRegionID: OfflineMapRegionID?]
    ) -> Bool {
        var seen = Set<OfflineMapRegionID>()
        var cursor = parentByID[candidate] ?? nil
        while let id = cursor, seen.insert(id).inserted {
            if id == ancestor { return true }
            cursor = parentByID[id] ?? nil
        }
        return false
    }

    private func reconcileSelections() {
        let installedIDs = Set(
            snapshot.installedRegions
                .filter { $0.state.isUsableCoverage }
                .map(\.id)
        )
        let availableIDs = Set(snapshot.downloadableRegions.map(\.id)).subtracting(installedIDs)
        installedSelection.formIntersection(installedIDs)
        availableSelection.formIntersection(availableIDs)
    }

    private func presentUnavailable(_ availability: OfflineMapCommandAvailability) {
        feedback = .init(
            kind: .failure,
            title: "Command unavailable",
            message: availability.disabledReason ?? "This map-library command is unavailable."
        )
    }

    private func present(_ error: Error, fallbackTitle: String) {
        let failure: OfflineMapFailure?
        if let direct = error as? OfflineMapFailure {
            failure = direct
        } else if let provider = error as? any OfflineMapFailureProviding {
            failure = provider.offlineMapFailure
        } else if let coreError = error as? OfflineMapCoreError {
            if case .engineFailure(let engineFailure) = coreError {
                failure = engineFailure
            } else {
                failure = nil
            }
        } else {
            failure = nil
        }
        let safeMessage: String
        if let failure {
            safeMessage = [failure.message, failure.recovery]
                .compactMap { $0 }
                .joined(separator: " ")
        } else if let coreError = error as? OfflineMapCoreError {
            safeMessage = coreError.localizedDescription
        } else {
            // Arbitrary SDK errors may contain paths, identifiers, or other
            // implementation detail. Only typed, sanitized contracts cross
            // this operator-facing boundary.
            safeMessage = "The offline map engine did not complete the command. Recheck map health and try again."
        }
        let message = safeMessage
        feedback = .init(kind: .failure, title: fallbackTitle, message: message)
    }

    private static func bytes(_ value: Int64) -> String {
        if value == 0 { return "0 bytes" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
