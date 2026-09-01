import XCTest
@testable import EusoTrip

final class OfflineMapCoordinatorTests: XCTestCase {
    @MainActor
    func testRadioSilenceMustBeEnforcedBeforeReadiness() async throws {
        let engine = try FakeOfflineMapEngine()
        await engine.setRadioSilenceState(.notEnforced(reason: "Fake radio silence is unavailable."))
        let coordinator = try makeCoordinator(engine: engine)

        await coordinator.prepare()

        guard case .blocked(let blockers) = coordinator.snapshot.readiness else {
            XCTFail("Readiness must remain blocked when radio silence is not enforced.")
            return
        }
        XCTAssertTrue(blockers.contains { $0.code == .radioSilenceNotEnforced })
        XCTAssertNotEqual(coordinator.snapshot.radioSilenceState, .enforced)

        await engine.setRadioSilenceState(.enforced)
        await coordinator.prepare()

        guard case .ready(let capabilities) = coordinator.snapshot.readiness else {
            XCTFail("Full fake capabilities should become ready after radio-silence enforcement.")
            return
        }
        XCTAssertTrue(capabilities.isSuperset(of: .fullRoadFreightParity))
        XCTAssertEqual(coordinator.snapshot.radioSilenceState, .enforced)

        let targetID = try OfflineMapRegionID(FakeOfflineMapEngine.targetRegionRawID)
        do {
            _ = try await coordinator.preflightDownload(regionIDs: [targetID])
            XCTFail("Radio-silent readiness must not authorize connected map maintenance.")
        } catch let OfflineMapCoreError.notReady(blockers) {
            XCTAssertTrue(blockers.contains { $0.code == .configurationInvalid })
        } catch {
            XCTFail("Expected an explicit connected-maintenance blocker, received \(error).")
        }

        await engine.setRadioSilenceState(.notEnforced(reason: "Fake policy regressed."))
        try await coordinator.refresh()
        guard case .blocked(let refreshedBlockers) = coordinator.snapshot.readiness else {
            XCTFail("Refresh must revoke readiness when radio silence is no longer confirmed.")
            return
        }
        XCTAssertTrue(refreshedBlockers.contains { $0.code == .radioSilenceNotEnforced })
    }

    @MainActor
    func testConnectivityPolicyFailureRemainsBlockedWhileInventoryStillLoads() async throws {
        let engine = try FakeOfflineMapEngine()
        await engine.setConnectivityPolicyFailure(
            OfflineMapFailure(
                code: "fake_connectivity_policy_failure",
                message: "Fake runtime could not enforce radio silence.",
                recovery: "Retry fake engine initialization.",
                isRecoverable: true
            )
        )
        let coordinator = try makeCoordinator(engine: engine)

        await coordinator.prepare()

        guard case .blocked(let blockers) = coordinator.snapshot.readiness else {
            XCTFail("A failed radio-silence policy must keep readiness blocked.")
            return
        }
        XCTAssertTrue(blockers.contains { $0.code == .radioSilenceNotEnforced })
        guard case .notEnforced(let reason) = coordinator.snapshot.radioSilenceState else {
            XCTFail("The failed policy must remain explicit in the snapshot.")
            return
        }
        XCTAssertEqual(reason, "Fake runtime could not enforce radio silence.")
        XCTAssertEqual(coordinator.snapshot.lastFailure?.code, "fake_connectivity_policy_failure")
        XCTAssertTrue(coordinator.snapshot.installedRegionsState.isCurrent)
        XCTAssertTrue(coordinator.snapshot.storageState.isCurrent)
        XCTAssertTrue(coordinator.snapshot.downloadableCatalogState.isCurrent)
    }

    @MainActor
    func testRejectedConnectivityTransitionNeverCommitsAndReinspectsPriorPolicy() async throws {
        let engine = try FakeOfflineMapEngine()
        let coordinator = try makeCoordinator(engine: engine, connectivityPolicy: .onlineAllowed)
        await coordinator.prepare()
        guard case .ready = coordinator.snapshot.readiness else {
            XCTFail("The initial connected policy should be ready in the deterministic engine.")
            return
        }

        await engine.setConnectivityPolicyFailure(
            OfflineMapFailure(
                code: "fake_runtime_lease_rejection",
                message: "A fake active runtime lease rejected the transition.",
                recovery: "End the fake lease and retry.",
                isRecoverable: true
            ),
            for: .radioSilent
        )
        var observedPolicies: [OfflineMapConnectivityPolicy] = []
        coordinator.onSnapshotChange = { snapshot in
            observedPolicies.append(snapshot.connectivityPolicy)
        }

        do {
            try await coordinator.setConnectivityPolicy(.radioSilent)
            XCTFail("The fake runtime lease must reject the requested transition.")
        } catch let OfflineMapCoreError.engineFailure(failure) {
            XCTAssertEqual(failure.code, "fake_runtime_lease_rejection")
        } catch {
            XCTFail("Expected the typed runtime transition failure, received \(error).")
        }

        XCTAssertFalse(observedPolicies.contains(.radioSilent))
        XCTAssertEqual(coordinator.snapshot.connectivityPolicy, .onlineAllowed)
        XCTAssertEqual(coordinator.snapshot.radioSilenceState, .notRequested)
        guard case .ready(let capabilities) = coordinator.snapshot.readiness else {
            XCTFail("The previously confirmed connected mode must be reinspected as ready.")
            return
        }
        XCTAssertTrue(capabilities.isSuperset(of: .fullRoadFreightParity))
        XCTAssertEqual(coordinator.snapshot.lastFailure?.code, "fake_runtime_lease_rejection")

        let statistics = await engine.statistics()
        XCTAssertEqual(Array(statistics.appliedConnectivityPolicies.suffix(2)), [.radioSilent, .onlineAllowed])
        XCTAssertEqual(statistics.inspectedConnectivityPolicies.last, .onlineAllowed)
    }

    @MainActor
    func testTextGuidanceWithoutOfflineVoiceGuidanceRemainsLimited() async throws {
        let capabilitiesWithoutVoice = OfflineMapCapabilities.fullRoadFreightParity
            .subtracting(.offlineVoiceGuidance)
        XCTAssertTrue(capabilitiesWithoutVoice.contains(.offlineGuidance))
        XCTAssertFalse(capabilitiesWithoutVoice.contains(.offlineVoiceGuidance))
        let engine = try FakeOfflineMapEngine(capabilities: capabilitiesWithoutVoice)
        let coordinator = try makeCoordinator(engine: engine)

        await coordinator.prepare()

        guard case .limited(let available, let missing) = coordinator.snapshot.readiness else {
            XCTFail("Text guidance alone must not satisfy full road-freight parity.")
            return
        }
        XCTAssertTrue(available.contains(.offlineGuidance))
        XCTAssertEqual(missing, .offlineVoiceGuidance)
    }

    @MainActor
    func testCatalogFailurePreservesInstalledMapsAndStorageTruth() async throws {
        let engine = try FakeOfflineMapEngine()
        await engine.setCatalogFailure(
            OfflineMapFailure(
                code: "fake_catalog_offline",
                message: "The fake catalog is unreachable while radio-silent.",
                recovery: nil,
                isRecoverable: true
            )
        )
        let coordinator = try makeCoordinator(engine: engine)

        await coordinator.prepare()

        XCTAssertEqual(coordinator.snapshot.installedRegions.count, 1)
        XCTAssertNotNil(coordinator.snapshot.storage)
        XCTAssertEqual(coordinator.snapshot.lastFailure?.code, "fake_catalog_offline")
        if case .current = coordinator.snapshot.installedRegionsState {
            // Expected: installed coverage remains independently usable.
        } else {
            XCTFail("Installed-map state must remain current when only catalog loading fails.")
        }
        if case .current = coordinator.snapshot.storageState {
            // Expected: storage remains independently usable.
        } else {
            XCTFail("Storage state must remain current when only catalog loading fails.")
        }
        if case .unavailable(let failure) = coordinator.snapshot.downloadableCatalogState {
            XCTAssertEqual(failure.code, "fake_catalog_offline")
        } else {
            XCTFail("The unavailable catalog must remain explicit.")
        }
    }

    @MainActor
    func testBlockedPrepareAndRefreshStillReloadIndependentInventoryAndCapabilities() async throws {
        let engine = try FakeOfflineMapEngine(
            persistentHealth: .needsRepair(reason: "Fake persistent map requires repair.")
        )
        let coordinator = try makeCoordinator(engine: engine, connectivityPolicy: .onlineAllowed)

        await coordinator.prepare()

        guard case .blocked(let blockers) = coordinator.snapshot.readiness else {
            XCTFail("Persistent-map damage must block overall readiness.")
            return
        }
        XCTAssertTrue(blockers.contains { $0.code == .persistentMapNeedsRepair })
        XCTAssertEqual(coordinator.snapshot.availableCapabilities, .fullRoadFreightParity)
        XCTAssertEqual(coordinator.snapshot.installedRegions.count, 1)
        XCTAssertNotNil(coordinator.snapshot.storage)
        XCTAssertEqual(coordinator.snapshot.downloadableRegions.count, 2)
        XCTAssertTrue(coordinator.snapshot.installedRegionsState.isCurrent)
        XCTAssertTrue(coordinator.snapshot.storageState.isCurrent)
        XCTAssertTrue(coordinator.snapshot.downloadableCatalogState.isCurrent)

        let refreshedStorage = try OfflineMapStorageSnapshot(
            availableBytes: 1_500,
            installedMapBytes: 400,
            measuredAt: Date(timeIntervalSince1970: 1_700_000_020)
        )
        await engine.setStorage(refreshedStorage)
        await engine.setCatalogFailure(
            OfflineMapFailure(
                code: "fake_refresh_catalog_failure",
                message: "The fake catalog failed during blocked refresh.",
                recovery: nil,
                isRecoverable: true
            )
        )

        try await coordinator.refresh()

        guard case .blocked = coordinator.snapshot.readiness else {
            XCTFail("Refresh must preserve the health blocker.")
            return
        }
        XCTAssertEqual(coordinator.snapshot.storage, refreshedStorage)
        XCTAssertTrue(coordinator.snapshot.installedRegionsState.isCurrent)
        XCTAssertTrue(coordinator.snapshot.storageState.isCurrent)
        if case .stale(_, let failure) = coordinator.snapshot.downloadableCatalogState {
            XCTAssertEqual(failure.code, "fake_refresh_catalog_failure")
        } else {
            XCTFail("A failed blocked refresh must retain the prior catalog as explicitly stale.")
        }
    }

    @MainActor
    func testDownloadPreflightRequiresBothCatalogAndInstalledFeedsToBeCurrent() async throws {
        let targetID = try OfflineMapRegionID(FakeOfflineMapEngine.targetRegionRawID)
        let installedFailure = OfflineMapFailure(
            code: "fake_installed_inventory_failure",
            message: "Installed HERE inventory is unavailable.",
            recovery: nil,
            isRecoverable: true
        )
        let missingInstalledEngine = try FakeOfflineMapEngine()
        await missingInstalledEngine.setInstalledFailure(installedFailure)
        let missingInstalledCoordinator = try makeCoordinator(
            engine: missingInstalledEngine,
            connectivityPolicy: .onlineAllowed
        )
        await missingInstalledCoordinator.prepare()

        XCTAssertTrue(missingInstalledCoordinator.snapshot.downloadableCatalogState.isCurrent)
        XCTAssertFalse(missingInstalledCoordinator.snapshot.installedRegionsState.isCurrent)
        do {
            _ = try await missingInstalledCoordinator.preflightDownload(regionIDs: [targetID])
            XCTFail("A current catalog cannot compensate for unknown installed coverage.")
        } catch let OfflineMapCoreError.notReady(blockers) {
            XCTAssertTrue(blockers.contains { $0.message.contains("installed region inventory") })
        } catch {
            XCTFail("Expected installed-inventory blocker, received \(error).")
        }
        let missingInstalledStats = await missingInstalledEngine.statistics()
        XCTAssertEqual(missingInstalledStats.downloadEstimateCalls, 0)

        let missingCatalogEngine = try FakeOfflineMapEngine()
        await missingCatalogEngine.setCatalogFailure(
            OfflineMapFailure(
                code: "fake_catalog_inventory_failure",
                message: "Downloadable HERE catalog is unavailable.",
                recovery: nil,
                isRecoverable: true
            )
        )
        let missingCatalogCoordinator = try makeCoordinator(
            engine: missingCatalogEngine,
            connectivityPolicy: .onlineAllowed
        )
        await missingCatalogCoordinator.prepare()

        XCTAssertFalse(missingCatalogCoordinator.snapshot.downloadableCatalogState.isCurrent)
        XCTAssertTrue(missingCatalogCoordinator.snapshot.installedRegionsState.isCurrent)
        do {
            _ = try await missingCatalogCoordinator.preflightDownload(regionIDs: [targetID])
            XCTFail("Current installed coverage cannot compensate for an unknown catalog.")
        } catch let OfflineMapCoreError.notReady(blockers) {
            XCTAssertTrue(blockers.contains { $0.message.contains("catalog") })
        } catch {
            XCTFail("Expected catalog blocker, received \(error).")
        }
        let missingCatalogStats = await missingCatalogEngine.statistics()
        XCTAssertEqual(missingCatalogStats.downloadEstimateCalls, 0)
    }

    @MainActor
    func testDownloadStorageUnknownAndInsufficientAreBothBlocked() async throws {
        let engine = try FakeOfflineMapEngine()
        let coordinator = try makeCoordinator(
            engine: engine,
            reserveBytes: 200,
            connectivityPolicy: .onlineAllowed
        )
        let targetID = try OfflineMapRegionID(FakeOfflineMapEngine.targetRegionRawID)
        await coordinator.prepare()

        await engine.setDownloadEstimate(nil)
        do {
            _ = try await coordinator.preflightDownload(regionIDs: [targetID])
            XCTFail("An unknown storage estimate must not pass preflight.")
        } catch {
            XCTAssertEqual(error as? OfflineMapCoreError, .storageEstimateUnavailable)
        }

        let estimate = try OfflineMapByteEstimate(requiredBytes: 800, confidence: .exact)
        let storage = try OfflineMapStorageSnapshot(
            availableBytes: 900,
            installedMapBytes: 400,
            measuredAt: Date(timeIntervalSince1970: 1_700_000_010)
        )
        await engine.setDownloadEstimate(estimate)
        await engine.setStorage(storage)

        let preflight = try await coordinator.preflightDownload(regionIDs: [targetID])
        guard case .blocked(_, _, let reserve, let shortfall) = preflight else {
            XCTFail("An estimate that breaches the reserve must be blocked.")
            return
        }
        XCTAssertEqual(reserve, 200)
        XCTAssertEqual(shortfall, 100)

        do {
            try await coordinator.download(regionIDs: [targetID])
            XCTFail("The mutation must enforce the same storage reserve as preflight.")
        } catch {
            XCTAssertEqual(
                error as? OfflineMapCoreError,
                .insufficientStorage(requiredBytes: 800, availableBytes: 900, reserveBytes: 200)
            )
        }
        XCTAssertNil(coordinator.snapshot.activeOperation)
    }

    @MainActor
    func testStorageReserveViolationBlocksZeroByteAndSaturatesShortfall() async throws {
        let targetID = try OfflineMapRegionID(FakeOfflineMapEngine.targetRegionRawID)
        let belowReserveEngine = try FakeOfflineMapEngine()
        await belowReserveEngine.setDownloadEstimate(
            try OfflineMapByteEstimate(requiredBytes: 0, confidence: .exact)
        )
        await belowReserveEngine.setStorage(
            try OfflineMapStorageSnapshot(
                availableBytes: 99,
                installedMapBytes: 400
            )
        )
        let belowReserveCoordinator = try makeCoordinator(
            engine: belowReserveEngine,
            reserveBytes: 100,
            connectivityPolicy: .onlineAllowed
        )
        await belowReserveCoordinator.prepare()

        let zeroBytePreflight = try await belowReserveCoordinator.preflightDownload(
            regionIDs: [targetID]
        )
        guard case .blocked(_, _, let reserve, let shortfall) = zeroBytePreflight else {
            XCTFail("An already-violated reserve must block even a zero-byte operation.")
            return
        }
        XCTAssertEqual(reserve, 100)
        XCTAssertEqual(shortfall, 1)

        let boundaryEngine = try FakeOfflineMapEngine()
        await boundaryEngine.setDownloadEstimate(
            try OfflineMapByteEstimate(requiredBytes: Int64.max, confidence: .exact)
        )
        await boundaryEngine.setStorage(
            try OfflineMapStorageSnapshot(availableBytes: 0, installedMapBytes: 0)
        )
        let boundaryCoordinator = try makeCoordinator(
            engine: boundaryEngine,
            reserveBytes: Int64.max,
            connectivityPolicy: .onlineAllowed
        )
        await boundaryCoordinator.prepare()

        let boundaryPreflight = try await boundaryCoordinator.preflightDownload(
            regionIDs: [targetID]
        )
        guard case .blocked(_, _, _, let saturatedShortfall) = boundaryPreflight else {
            XCTFail("An unrepresentable reserve shortfall must fail closed.")
            return
        }
        XCTAssertEqual(saturatedShortfall, Int64.max)
    }

    @MainActor
    func testStorageAttemptsExposeLoadingThenCurrentStaleOrUnavailable() async throws {
        let engine = try FakeOfflineMapEngine()
        let coordinator = try makeCoordinator(engine: engine, connectivityPolicy: .onlineAllowed)
        let targetID = try OfflineMapRegionID(FakeOfflineMapEngine.targetRegionRawID)
        await coordinator.prepare()

        var successfulStates: [OfflineMapInventoryFeedState] = []
        coordinator.onSnapshotChange = { snapshot in
            successfulStates.append(snapshot.storageState)
        }
        _ = try await coordinator.preflightDownload(regionIDs: [targetID])
        XCTAssertTrue(successfulStates.contains { state in
            guard case .loading(let lastSuccessfulAt) = state else { return false }
            return lastSuccessfulAt != nil
        })
        XCTAssertTrue(successfulStates.contains { $0.isCurrent })

        let storageFailure = OfflineMapFailure(
            code: "fake_storage_read_failed",
            message: "The fake storage read failed.",
            recovery: "Retry the fake read.",
            isRecoverable: true
        )
        await engine.setStorageFailure(storageFailure)
        var failedStates: [OfflineMapInventoryFeedState] = []
        coordinator.onSnapshotChange = { snapshot in
            failedStates.append(snapshot.storageState)
        }
        do {
            _ = try await coordinator.preflightDownload(regionIDs: [targetID])
            XCTFail("A failed fresh storage read must not reuse a prior value as current.")
        } catch let OfflineMapCoreError.engineFailure(failure) {
            XCTAssertEqual(failure.code, "fake_storage_read_failed")
        } catch {
            XCTFail("Expected typed storage failure, received \(error).")
        }
        XCTAssertTrue(failedStates.contains { state in
            guard case .loading(let lastSuccessfulAt) = state else { return false }
            return lastSuccessfulAt != nil
        })
        guard case .stale(_, let staleFailure) = coordinator.snapshot.storageState else {
            XCTFail("A failed refresh after current storage must become explicitly stale.")
            return
        }
        XCTAssertEqual(staleFailure.code, "fake_storage_read_failed")

        let coldEngine = try FakeOfflineMapEngine()
        await coldEngine.setStorageFailure(storageFailure)
        let coldCoordinator = try makeCoordinator(
            engine: coldEngine,
            connectivityPolicy: .onlineAllowed
        )
        await coldCoordinator.prepare()
        guard case .unavailable(let unavailableFailure) = coldCoordinator.snapshot.storageState else {
            XCTFail("A first storage failure with no successful value must be unavailable.")
            return
        }
        XCTAssertEqual(unavailableFailure.code, "fake_storage_read_failed")
    }

    @MainActor
    func testParentAndChildRegionsCannotShareOneDownloadMutation() async throws {
        let engine = try FakeOfflineMapEngine()
        let coordinator = try makeCoordinator(engine: engine, connectivityPolicy: .onlineAllowed)
        let parentID = try OfflineMapRegionID(FakeOfflineMapEngine.parentRegionRawID)
        let childID = try OfflineMapRegionID(FakeOfflineMapEngine.targetRegionRawID)
        await coordinator.prepare()

        do {
            _ = try await coordinator.preflightDownload(regionIDs: [parentID, childID])
            XCTFail("A parent and descendant must not create an ambiguous HERE transfer.")
        } catch let OfflineMapCoreError.invalidInput(message) {
            XCTAssertTrue(message.contains("parent region or its child"))
        } catch {
            XCTFail("Expected parent/child validation, received \(error).")
        }
        let statistics = await engine.statistics()
        XCTAssertEqual(statistics.downloadCalls, 0)
    }

    @MainActor
    func testRootMutationsAreSerializedAndCancellationDoesNotInstallCoverage() async throws {
        let engine = try FakeOfflineMapEngine()
        let coordinator = try makeCoordinator(engine: engine, connectivityPolicy: .onlineAllowed)
        let targetID = try OfflineMapRegionID(FakeOfflineMapEngine.targetRegionRawID)
        let existingID = try OfflineMapRegionID(FakeOfflineMapEngine.existingRegionRawID)
        await coordinator.prepare()
        await engine.setHoldTransfers(true)

        var trackedOperationID: UUID?
        var terminalTransitions = 0
        coordinator.onSnapshotChange = { snapshot in
            if let operationID = snapshot.activeOperation?.id {
                trackedOperationID = operationID
            } else if trackedOperationID != nil {
                terminalTransitions += 1
                trackedOperationID = nil
            }
        }

        let downloadTask = Task {
            try await coordinator.download(regionIDs: [targetID])
        }
        await engine.waitForDownloadStart()

        do {
            try await coordinator.delete(regionIDs: [existingID])
            XCTFail("A second root mutation must be rejected while download is active.")
        } catch {
            XCTAssertEqual(error as? OfflineMapCoreError, .busy(activeOperation: .downloadRegions))
        }
        let beforeCancellation = await engine.statistics()
        XCTAssertEqual(beforeCancellation.downloadCalls, 1)
        XCTAssertEqual(beforeCancellation.deleteCalls, 0)

        try await coordinator.cancelActiveTransfer()
        do {
            try await downloadTask.value
            XCTFail("The held download must finish as cancellation.")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, received \(error).")
        }

        XCTAssertNil(coordinator.snapshot.activeOperation)
        XCTAssertNil(coordinator.snapshot.lastFailure)
        XCTAssertEqual(terminalTransitions, 1)
        let installedIDs = await engine.installedRegionIDs()
        XCTAssertFalse(installedIDs.contains(targetID))
        let afterCancellation = await engine.statistics()
        XCTAssertEqual(afterCancellation.cancelCalls, 1)
    }

    @MainActor
    func testHeldRootMutationRejectsRefreshPolicyPreflightAndLocalReads() async throws {
        let engine = try FakeOfflineMapEngine()
        let coordinator = try makeCoordinator(engine: engine, connectivityPolicy: .onlineAllowed)
        let targetID = try OfflineMapRegionID(FakeOfflineMapEngine.targetRegionRawID)
        await coordinator.prepare()
        await engine.setHoldTransfers(true)

        let downloadTask = Task {
            try await coordinator.download(regionIDs: [targetID])
        }
        await engine.waitForDownloadStart()
        let expectedBusy = OfflineMapCoreError.busy(activeOperation: .downloadRegions)
        let inspectionsBeforePrepare = await engine.statistics().inspectedConnectivityPolicies.count

        await coordinator.prepare()
        let inspectionsAfterPrepare = await engine.statistics().inspectedConnectivityPolicies.count
        XCTAssertEqual(inspectionsAfterPrepare, inspectionsBeforePrepare)

        do {
            try await coordinator.refresh()
            XCTFail("Refresh must not interleave with a root mutation.")
        } catch {
            XCTAssertEqual(error as? OfflineMapCoreError, expectedBusy)
        }
        do {
            try await coordinator.setConnectivityPolicy(.radioSilent)
            XCTFail("Policy transition must not interleave with a root mutation.")
        } catch {
            XCTAssertEqual(error as? OfflineMapCoreError, expectedBusy)
        }
        do {
            _ = try await coordinator.preflightDownload(regionIDs: [targetID])
            XCTFail("Storage preflight must not interleave with a root mutation.")
        } catch {
            XCTAssertEqual(error as? OfflineMapCoreError, expectedBusy)
        }

        let center = try OfflineGeoCoordinate(latitude: 29.7604, longitude: -95.3698)
        let searchRequest = try OfflineSearchRequest(text: "fuel", center: center)
        do {
            _ = try await coordinator.searchOffline(searchRequest)
            XCTFail("Offline search must not interleave with a root mutation.")
        } catch {
            XCTAssertEqual(error as? OfflineMapCoreError, expectedBusy)
        }

        let routeRequest = try OfflineRouteRequest(
            waypoints: [
                OfflineRouteWaypoint(coordinate: center, label: "Houston"),
                OfflineRouteWaypoint(
                    coordinate: try OfflineGeoCoordinate(latitude: 32.7767, longitude: -96.7970),
                    label: "Dallas"
                )
            ],
            mode: .road
        )
        do {
            _ = try await coordinator.calculateOfflineRoute(routeRequest)
            XCTFail("Offline routing must not interleave with a root mutation.")
        } catch {
            XCTAssertEqual(error as? OfflineMapCoreError, expectedBusy)
        }

        try await coordinator.cancelActiveTransfer()
        do {
            try await downloadTask.value
            XCTFail("The held transfer must terminate as cancellation.")
        } catch is CancellationError {
            // Expected.
        }
    }

    @MainActor
    func testPartialMutationFailureReloadsIncompleteCoverageWhileFinalizing() async throws {
        let engine = try FakeOfflineMapEngine()
        let coordinator = try makeCoordinator(engine: engine, connectivityPolicy: .onlineAllowed)
        let targetID = try OfflineMapRegionID(FakeOfflineMapEngine.targetRegionRawID)
        await coordinator.prepare()
        await engine.setDownloadFailureAfterIncomplete(
            OfflineMapFailure(
                code: "fake_partial_download_failure",
                message: "The fake transfer failed after writing partial coverage.",
                recovery: "Resume the fake transfer.",
                isRecoverable: true
            )
        )
        var sawFinalizing = false
        var sawReadbackWhileFinalizing = false
        coordinator.onSnapshotChange = { snapshot in
            guard snapshot.activeOperation?.phase == .finalizing else { return }
            sawFinalizing = true
            if case .loading = snapshot.installedRegionsState {
                sawReadbackWhileFinalizing = true
            }
        }

        do {
            try await coordinator.download(regionIDs: [targetID])
            XCTFail("The injected partial transfer must fail.")
        } catch let OfflineMapCoreError.engineFailure(failure) {
            XCTAssertEqual(failure.code, "fake_partial_download_failure")
        } catch {
            XCTFail("Expected typed partial-transfer failure, received \(error).")
        }

        XCTAssertTrue(sawFinalizing)
        XCTAssertTrue(sawReadbackWhileFinalizing)
        XCTAssertNil(coordinator.snapshot.activeOperation)
        let partial = try XCTUnwrap(
            coordinator.snapshot.installedRegions.first { $0.id == targetID }
        )
        XCTAssertEqual(partial.state, .incomplete)
        XCTAssertTrue(partial.state.isResumableTransfer)
        XCTAssertTrue(coordinator.snapshot.installedRegionsState.isCurrent)
        XCTAssertEqual(coordinator.snapshot.lastFailure?.code, "fake_partial_download_failure")
    }

    @MainActor
    func testPartialMutationFailureReinspectsHealthAndRevokesPriorReadiness() async throws {
        let engine = try FakeOfflineMapEngine()
        let coordinator = try makeCoordinator(engine: engine, connectivityPolicy: .onlineAllowed)
        let targetID = try OfflineMapRegionID(FakeOfflineMapEngine.targetRegionRawID)
        await coordinator.prepare()
        guard case .ready = coordinator.snapshot.readiness else {
            XCTFail("The initial deterministic inspection must be ready.")
            return
        }

        await engine.setDownloadFailureAfterIncomplete(
            OfflineMapFailure(
                code: "fake_partial_health_failure",
                message: "The fake transfer invalidated persistent-map health after writing bytes.",
                recovery: "Repair the deterministic persistent map.",
                isRecoverable: true
            ),
            persistentHealthAfterFailure: .needsRepair(
                reason: "The partial fake transfer left persistent data requiring repair."
            )
        )

        do {
            try await coordinator.download(regionIDs: [targetID])
            XCTFail("The injected durable partial mutation must fail.")
        } catch let OfflineMapCoreError.engineFailure(failure) {
            XCTAssertEqual(failure.code, "fake_partial_health_failure")
        } catch {
            XCTFail("Expected the typed partial-mutation failure, received \(error).")
        }

        guard case .needsRepair(let reason) = coordinator.snapshot.persistentHealth else {
            XCTFail("Failure finalization must replace prior healthy inspection evidence.")
            return
        }
        XCTAssertTrue(reason.contains("requiring repair"))
        guard case .blocked(let blockers) = coordinator.snapshot.readiness else {
            XCTFail("Invalidated durable health must immediately revoke readiness.")
            return
        }
        XCTAssertTrue(blockers.contains { $0.code == .persistentMapNeedsRepair })
        XCTAssertEqual(
            coordinator.snapshot.installedRegions.first(where: { $0.id == targetID })?.state,
            .incomplete
        )
        XCTAssertEqual(coordinator.snapshot.lastFailure?.code, "fake_partial_health_failure")

        let statistics = await engine.statistics()
        XCTAssertGreaterThanOrEqual(statistics.inspectedConnectivityPolicies.count, 2)
        XCTAssertEqual(statistics.inspectedConnectivityPolicies.last, .onlineAllowed)
    }

    @MainActor
    func testCancellationReloadsIncompleteCoverageBeforeFinalizing() async throws {
        let engine = try FakeOfflineMapEngine()
        let coordinator = try makeCoordinator(engine: engine, connectivityPolicy: .onlineAllowed)
        let targetID = try OfflineMapRegionID(FakeOfflineMapEngine.targetRegionRawID)
        await coordinator.prepare()
        await engine.setHoldTransfers(true)
        await engine.setExposeIncompleteOnCancellation(true)

        let downloadTask = Task {
            try await coordinator.download(regionIDs: [targetID])
        }
        await engine.waitForDownloadStart()
        try await coordinator.cancelActiveTransfer()

        do {
            try await downloadTask.value
            XCTFail("The fake interrupted transfer must complete as cancellation.")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, received \(error).")
        }

        XCTAssertNil(coordinator.snapshot.activeOperation)
        XCTAssertNil(coordinator.snapshot.lastFailure)
        let interrupted = try XCTUnwrap(
            coordinator.snapshot.installedRegions.first { $0.id == targetID }
        )
        XCTAssertEqual(interrupted.state, .incomplete)
        XCTAssertTrue(interrupted.state.isResumableTransfer)
        XCTAssertFalse(interrupted.state.isUsableCoverage)
        XCTAssertTrue(coordinator.snapshot.installedRegionsState.isCurrent)
    }

    @MainActor
    func testDownloadPublishesProgressAndRequiresInstalledReadback() async throws {
        let engine = try FakeOfflineMapEngine()
        let coordinator = try makeCoordinator(engine: engine, connectivityPolicy: .onlineAllowed)
        let targetID = try OfflineMapRegionID(FakeOfflineMapEngine.targetRegionRawID)
        await coordinator.prepare()
        await engine.setHoldTransfers(true)

        let progressSeen = expectation(description: "coordinator receives fake transfer progress")
        var didFulfillProgress = false
        coordinator.onSnapshotChange = { snapshot in
            guard !didFulfillProgress,
                  snapshot.activeOperation?.progress?.fractionCompleted == 0.25 else { return }
            didFulfillProgress = true
            progressSeen.fulfill()
        }
        let downloadTask = Task {
            try await coordinator.download(regionIDs: [targetID])
        }
        await engine.waitForDownloadStart()
        await fulfillment(of: [progressSeen], timeout: 2)

        XCTAssertEqual(coordinator.snapshot.activeOperation?.progress?.completedBytes, 50)
        await engine.completeActiveTransfer()
        try await downloadTask.value

        XCTAssertNil(coordinator.snapshot.activeOperation)
        XCTAssertTrue(coordinator.snapshot.installedRegions.contains { $0.id == targetID })
        XCTAssertNil(coordinator.snapshot.lastFailure)
    }

    @MainActor
    func testEngineReportedAutoPauseRequiresExplicitResume() async throws {
        let engine = try FakeOfflineMapEngine()
        let coordinator = try makeCoordinator(engine: engine, connectivityPolicy: .onlineAllowed)
        let targetID = try OfflineMapRegionID(FakeOfflineMapEngine.targetRegionRawID)
        await coordinator.prepare()
        await engine.setHoldTransfers(true)

        let downloadTask = Task {
            try await coordinator.download(regionIDs: [targetID])
        }
        await engine.waitForDownloadStart()

        let paused = expectation(description: "coordinator exposes the SDK auto-pause")
        coordinator.onSnapshotChange = { snapshot in
            guard snapshot.activeOperation?.phase == .paused else { return }
            paused.fulfill()
        }
        try await engine.emitActiveTransferPhase(.paused)
        await fulfillment(of: [paused], timeout: 2)
        XCTAssertEqual(coordinator.snapshot.activeOperation?.phase, .paused)
        XCTAssertEqual(coordinator.snapshot.activeOperation?.progress?.reportedPhase, .paused)

        // A late running callback cannot revive a physically paused transfer.
        try await engine.emitActiveTransferPhase(.running)
        for _ in 0 ..< 4 { await Task.yield() }
        XCTAssertEqual(coordinator.snapshot.activeOperation?.phase, .paused)

        try await coordinator.resumeActiveTransfer()
        XCTAssertEqual(coordinator.snapshot.activeOperation?.phase, .running)

        let statistics = await engine.statistics()
        XCTAssertEqual(statistics.pauseCalls, 0)
        XCTAssertEqual(statistics.resumeCalls, 1)

        await engine.completeActiveTransfer()
        try await downloadTask.value
        XCTAssertNil(coordinator.snapshot.activeOperation)
        XCTAssertTrue(coordinator.snapshot.installedRegions.contains { $0.id == targetID })
    }

    @MainActor
    func testConcurrentProgressCallbacksCannotRegressProgressOrPausedPhase() async throws {
        let engine = try FakeOfflineMapEngine()
        let coordinator = try makeCoordinator(engine: engine, connectivityPolicy: .onlineAllowed)
        let targetID = try OfflineMapRegionID(FakeOfflineMapEngine.targetRegionRawID)
        await coordinator.prepare()
        await engine.setHoldTransfers(true)

        let downloadTask = Task {
            try await coordinator.download(regionIDs: [targetID])
        }
        await engine.waitForDownloadStart()
        let capturedHandler = await engine.capturedActiveTransferProgressHandler()
        let handler = try XCTUnwrap(capturedHandler)
        let staleRunning = try OfflineMapTransferProgress(
            completedBytes: 20,
            totalBytes: 200,
            fractionCompleted: 0.10,
            detail: "Stale running callback.",
            reportedPhase: .running
        )
        let newerPaused = try OfflineMapTransferProgress(
            completedBytes: 150,
            totalBytes: 200,
            fractionCompleted: 0.75,
            detail: "Newest paused callback.",
            reportedPhase: .paused
        )

        await withTaskGroup(of: Void.self) { group in
            group.addTask { handler(newerPaused) }
            group.addTask { handler(staleRunning) }
        }
        for _ in 0 ..< 8 { await Task.yield() }

        XCTAssertEqual(coordinator.snapshot.activeOperation?.progress?.fractionCompleted, 0.75)
        XCTAssertEqual(coordinator.snapshot.activeOperation?.progress?.completedBytes, 150)
        XCTAssertEqual(coordinator.snapshot.activeOperation?.phase, .paused)

        await engine.completeActiveTransfer()
        try await downloadTask.value
    }

    func testProgressSequencerDrainsIssuedCallbacksInStrictOrder() throws {
        let sequencer = OfflineMapProgressSequencer()
        let earlierHighProgress = try OfflineMapTransferProgress(
            completedBytes: 150,
            totalBytes: 200,
            fractionCompleted: 0.75,
            detail: "Earlier high-water callback."
        )
        let laterRegressiveProgress = try OfflineMapTransferProgress(
            completedBytes: 20,
            totalBytes: 200,
            fractionCompleted: 0.10,
            detail: "Later regressive callback."
        )

        XCTAssertEqual(sequencer.enqueue(earlierHighProgress), 1)
        XCTAssertEqual(sequencer.enqueue(laterRegressiveProgress), 2)
        let drained = sequencer.drain()

        XCTAssertEqual(drained.map(\.sequence), [1, 2])
        XCTAssertEqual(drained.map(\.progress.fractionCompleted), [0.75, 0.10])
        XCTAssertTrue(sequencer.drain().isEmpty)
    }

    @MainActor
    func testCompletedMutationFailsWhenReadbackDoesNotProveTheChange() async throws {
        let engine = try FakeOfflineMapEngine()
        let coordinator = try makeCoordinator(engine: engine, connectivityPolicy: .onlineAllowed)
        let targetID = try OfflineMapRegionID(FakeOfflineMapEngine.targetRegionRawID)
        await coordinator.prepare()
        await engine.setForceReadbackMismatch(true)

        do {
            try await coordinator.download(regionIDs: [targetID])
            XCTFail("An SDK callback alone must not prove durable installation.")
        } catch let OfflineMapCoreError.engineFailure(failure) {
            XCTAssertEqual(failure.code, "post_operation_readback_failed")
        } catch {
            XCTFail("Expected post-operation readback failure, received \(error).")
        }

        XCTAssertEqual(coordinator.snapshot.lastFailure?.code, "post_operation_readback_failed")
        XCTAssertFalse(coordinator.snapshot.installedRegions.contains { $0.id == targetID })
    }

    @MainActor
    func testIncompleteRegionCanResumeAndMustReadBackAsUsableCoverage() async throws {
        let engine = try FakeOfflineMapEngine()
        try await engine.setTargetInstalledState(.incomplete)
        let coordinator = try makeCoordinator(engine: engine, connectivityPolicy: .onlineAllowed)
        let targetID = try OfflineMapRegionID(FakeOfflineMapEngine.targetRegionRawID)
        await coordinator.prepare()

        let initial = try XCTUnwrap(
            coordinator.snapshot.installedRegions.first { $0.id == targetID }
        )
        XCTAssertEqual(initial.state, .incomplete)
        XCTAssertFalse(initial.state.isUsableCoverage)
        XCTAssertTrue(initial.state.isResumableTransfer)

        _ = try await coordinator.preflightDownload(regionIDs: [targetID])
        try await coordinator.download(regionIDs: [targetID])

        let completed = try XCTUnwrap(
            coordinator.snapshot.installedRegions.first { $0.id == targetID }
        )
        XCTAssertEqual(completed.state, .installed)
        XCTAssertTrue(completed.state.isUsableCoverage)
        let statistics = await engine.statistics()
        XCTAssertEqual(statistics.downloadCalls, 1)
    }

    @MainActor
    func testIncompleteRegionIDDoesNotSatisfySuccessfulDownloadReadback() async throws {
        let engine = try FakeOfflineMapEngine()
        try await engine.setTargetInstalledState(.incomplete)
        await engine.setForceReadbackMismatch(true)
        let coordinator = try makeCoordinator(engine: engine, connectivityPolicy: .onlineAllowed)
        let targetID = try OfflineMapRegionID(FakeOfflineMapEngine.targetRegionRawID)
        await coordinator.prepare()

        do {
            try await coordinator.download(regionIDs: [targetID])
            XCTFail("An incomplete matching ID must not prove usable downloaded coverage.")
        } catch let OfflineMapCoreError.engineFailure(failure) {
            XCTAssertEqual(failure.code, "post_operation_readback_failed")
        } catch {
            XCTFail("Expected post-operation readback failure, received \(error).")
        }

        let readback = try XCTUnwrap(
            coordinator.snapshot.installedRegions.first { $0.id == targetID }
        )
        XCTAssertEqual(readback.state, .incomplete)
        XCTAssertFalse(readback.state.isUsableCoverage)
        XCTAssertEqual(coordinator.snapshot.lastFailure?.code, "post_operation_readback_failed")
    }

    @MainActor
    func testRepairAndPolicyBasedUpdateEstimateRemainExplicit() async throws {
        let repairingEngine = try FakeOfflineMapEngine(
            persistentHealth: .needsRepair(reason: "Fake persistent map is damaged.")
        )
        let repairingCoordinator = try makeCoordinator(
            engine: repairingEngine,
            connectivityPolicy: .onlineAllowed
        )
        await repairingCoordinator.prepare()

        try await repairingCoordinator.repairPersistentMap()

        guard case .healthy(let catalogVersion, _) = repairingCoordinator.snapshot.persistentHealth else {
            XCTFail("Successful repair must be re-inspected as healthy.")
            return
        }
        XCTAssertEqual(catalogVersion, "catalog-repaired")
        let repairStatistics = await repairingEngine.statistics()
        XCTAssertEqual(repairStatistics.repairCalls, 1)

        let updatingEngine = try FakeOfflineMapEngine()
        await updatingEngine.setUpdateEstimate(nil)
        let updatingCoordinator = try makeCoordinator(
            engine: updatingEngine,
            reserveBytes: 100,
            updateMultiplier: 0.5,
            connectivityPolicy: .onlineAllowed
        )
        await updatingCoordinator.prepare()

        try await updatingCoordinator.updatePersistentMap()

        let updateStatistics = await updatingEngine.statistics()
        XCTAssertEqual(updateStatistics.updateEstimateCalls, 1)
        XCTAssertEqual(updateStatistics.updateCalls, 1)
        XCTAssertNil(updatingCoordinator.snapshot.lastFailure)

        let unknownEstimateEngine = try FakeOfflineMapEngine()
        await unknownEstimateEngine.setUpdateEstimate(nil)
        let unknownEstimateCoordinator = try makeCoordinator(
            engine: unknownEstimateEngine,
            connectivityPolicy: .onlineAllowed
        )
        await unknownEstimateCoordinator.prepare()
        do {
            try await unknownEstimateCoordinator.updatePersistentMap()
            XCTFail("An update with neither SDK nor policy estimate must be blocked.")
        } catch {
            XCTAssertEqual(error as? OfflineMapCoreError, .storageEstimateUnavailable)
        }
    }

    @MainActor
    func testPolicyUpdateEstimateRejectsInt64BoundaryWithoutTrapping() async throws {
        let engine = try FakeOfflineMapEngine()
        await engine.setUpdateEstimate(nil)
        await engine.setStorage(
            try OfflineMapStorageSnapshot(
                availableBytes: Int64.max,
                installedMapBytes: Int64.max,
                measuredAt: Date(timeIntervalSince1970: 1_700_000_100)
            )
        )
        let coordinator = try makeCoordinator(
            engine: engine,
            reserveBytes: 0,
            updateMultiplier: 1,
            connectivityPolicy: .onlineAllowed
        )
        await coordinator.prepare()

        do {
            try await coordinator.updatePersistentMap()
            XCTFail("A rounded 2^63 staging estimate must fail before Int64 conversion.")
        } catch let OfflineMapCoreError.invalidInput(message) {
            XCTAssertEqual(message, "The update staging policy exceeds supported storage bounds.")
        } catch {
            XCTFail("Expected bounded policy-estimate failure, received \(error).")
        }
        XCTAssertNil(coordinator.snapshot.activeOperation)
    }

    @MainActor
    func testUpdateCannotSucceedWhileInstalledReadbackStillReportsUpdateAvailable() async throws {
        let engine = try FakeOfflineMapEngine()
        try await engine.setExistingInstalledState(.updateAvailable)
        await engine.setForceReadbackMismatch(true)
        let coordinator = try makeCoordinator(engine: engine, connectivityPolicy: .onlineAllowed)
        await coordinator.prepare()

        XCTAssertEqual(coordinator.snapshot.installedRegions.first?.state, .updateAvailable)
        do {
            try await coordinator.updatePersistentMap()
            XCTFail("A native completion callback must not prove an update while readback remains stale.")
        } catch let OfflineMapCoreError.engineFailure(failure) {
            XCTAssertEqual(failure.code, "post_operation_readback_failed")
        } catch {
            XCTFail("Expected the typed post-update readback failure, received \(error).")
        }

        XCTAssertEqual(coordinator.snapshot.installedRegions.first?.state, .updateAvailable)
        XCTAssertEqual(coordinator.snapshot.lastFailure?.code, "post_operation_readback_failed")
        XCTAssertNil(coordinator.snapshot.activeOperation)
        let statistics = await engine.statistics()
        XCTAssertEqual(statistics.updateCalls, 1)
    }

    @MainActor
    func testRoutingRejectsRailAndVesselRequiresTruckProfileAndReturnsLocalProvenance() async throws {
        let origin = OfflineRouteWaypoint(
            coordinate: try OfflineGeoCoordinate(latitude: 29.7604, longitude: -95.3698),
            label: "Houston"
        )
        let destination = OfflineRouteWaypoint(
            coordinate: try OfflineGeoCoordinate(latitude: 32.7767, longitude: -96.7970),
            label: "Dallas"
        )
        let waypoints = [origin, destination]

        for mode in [OfflineRouteMode.rail, .vessel] {
            do {
                _ = try OfflineRouteRequest(waypoints: waypoints, mode: mode)
                XCTFail("\(mode.rawValue) must remain server-canonical.")
            } catch {
                XCTAssertEqual(error as? OfflineMapCoreError, .unsupportedLocalRouting(mode))
            }
        }

        do {
            _ = try OfflineRouteRequest(waypoints: waypoints, mode: .truck)
            XCTFail("Truck routing must not invent a native SDK default profile.")
        } catch let OfflineMapCoreError.invalidInput(message) {
            XCTAssertTrue(message.contains("explicit truck profile"))
        } catch {
            XCTFail("Expected explicit-profile validation, received \(error).")
        }

        let profile = try OfflineTruckConstraints(
            truckType: .tractor,
            truckCategory: .tractor,
            tunnelCategory: .d,
            grossWeightKilograms: 36_000,
            weightPerAxleKilograms: 9_000,
            heightCentimeters: 410,
            widthCentimeters: 260,
            lengthCentimeters: 1_650,
            axleCount: 5,
            trailerCount: 1,
            hazardousGoods: [.flammable]
        )
        let request = try OfflineRouteRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            waypoints: waypoints,
            mode: .truck,
            truckConstraints: profile,
            departureTime: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let engine = try FakeOfflineMapEngine()
        let coordinator = try makeCoordinator(engine: engine)
        await coordinator.prepare()

        let response = try await coordinator.calculateOfflineRoute(request)

        XCTAssertEqual(response.requestID, request.id)
        XCTAssertTrue(response.routes.allSatisfy { $0.provenance == .hereOfflineLocal })
        XCTAssertTrue(response.routes.allSatisfy { $0.mode == .truck })
        XCTAssertTrue(response.routes.allSatisfy { $0.summary.trafficBasis == .noneOffline })
        let captured = await engine.capturedRouteContract()
        XCTAssertEqual(captured.0, .truck)
        XCTAssertEqual(captured.1, profile)
    }

    func testInstalledCoverageEvidenceCannotBeEmpty() throws {
        XCTAssertThrowsError(try OfflineInstalledCoverageEvidence(regionIDs: [])) { error in
            guard case OfflineMapCoreError.invalidInput(let message) = error else {
                XCTFail("Expected validated coverage input failure, received \(error).")
                return
            }
            XCTAssertTrue(message.contains("cannot be empty"))
        }
    }

    @MainActor
    func testCoordinatorRejectsCoverageEvidenceOutsideCurrentUsableInstalledRegions() async throws {
        let engine = try FakeOfflineMapEngine()
        let incompleteID = try OfflineMapRegionID(FakeOfflineMapEngine.targetRegionRawID)
        try await engine.setTargetInstalledState(.incomplete)
        await engine.setCoverageRegionIDsOverride([incompleteID])
        let coordinator = try makeCoordinator(engine: engine)
        await coordinator.prepare()

        XCTAssertEqual(
            coordinator.snapshot.installedRegions.first(where: { $0.id == incompleteID })?.state,
            .incomplete
        )

        let origin = try OfflineGeoCoordinate(latitude: 29.7604, longitude: -95.3698)
        let searchRequest = try OfflineSearchRequest(text: "fuel", center: origin)
        do {
            _ = try await coordinator.searchOffline(searchRequest)
            XCTFail("Incomplete installed bytes must not validate search coverage evidence.")
        } catch let OfflineMapCoreError.engineFailure(failure) {
            XCTAssertEqual(failure.code, "offline_coverage_contract_violation")
        } catch {
            XCTFail("Expected typed search coverage rejection, received \(error).")
        }

        let routeRequest = try OfflineRouteRequest(
            waypoints: [
                OfflineRouteWaypoint(coordinate: origin, label: "Houston"),
                OfflineRouteWaypoint(
                    coordinate: try OfflineGeoCoordinate(latitude: 32.7767, longitude: -96.7970),
                    label: "Dallas"
                )
            ],
            mode: .road
        )
        do {
            _ = try await coordinator.calculateOfflineRoute(routeRequest)
            XCTFail("Incomplete installed bytes must not validate route corridor evidence.")
        } catch let OfflineMapCoreError.engineFailure(failure) {
            XCTAssertEqual(failure.code, "offline_coverage_contract_violation")
        } catch {
            XCTFail("Expected typed route coverage rejection, received \(error).")
        }

        XCTAssertEqual(coordinator.snapshot.lastFailure?.code, "offline_coverage_contract_violation")
    }

    @MainActor
    func testPersistentUpdateIgnoresInterruptedTransferTargets() async throws {
        let engine = try FakeOfflineMapEngine()
        try await engine.setExistingInstalledState(.updateAvailable)
        try await engine.setTargetInstalledState(.incomplete)
        let coordinator = try makeCoordinator(engine: engine, connectivityPolicy: .onlineAllowed)
        await coordinator.prepare()

        try await coordinator.updatePersistentMap()

        let existingID = try OfflineMapRegionID(FakeOfflineMapEngine.existingRegionRawID)
        let interruptedID = try OfflineMapRegionID(FakeOfflineMapEngine.targetRegionRawID)
        XCTAssertEqual(
            coordinator.snapshot.installedRegions.first { $0.id == existingID }?.state,
            .installed
        )
        XCTAssertEqual(
            coordinator.snapshot.installedRegions.first { $0.id == interruptedID }?.state,
            .incomplete
        )
        XCTAssertNil(coordinator.snapshot.lastFailure)
        let statistics = await engine.statistics()
        XCTAssertEqual(statistics.updateCalls, 1)
    }

    @MainActor
    func testSearchRejectsEngineResponseAboveRequestedMaximum() async throws {
        let engine = try FakeOfflineMapEngine()
        await engine.setSearchResultCount(2)
        let coordinator = try makeCoordinator(engine: engine)
        await coordinator.prepare()
        let request = try OfflineSearchRequest(
            text: "fuel",
            center: try OfflineGeoCoordinate(latitude: 29.7604, longitude: -95.3698),
            maximumResultCount: 1
        )

        do {
            _ = try await coordinator.searchOffline(request)
            XCTFail("The native engine must not exceed the bounded offline search request.")
        } catch let OfflineMapCoreError.engineFailure(failure) {
            XCTAssertEqual(failure.code, "offline_search_result_limit_violation")
        } catch {
            XCTFail("Expected a typed search contract failure, received \(error).")
        }
    }

    @MainActor
    func testDuplicateCatalogIdentifiersFailClosedWithoutTrapping() async throws {
        let engine = try FakeOfflineMapEngine()
        try await engine.appendDuplicateDownloadableRegionID()
        let coordinator = try makeCoordinator(engine: engine)

        await coordinator.prepare()

        guard case .unavailable(let failure) = coordinator.snapshot.downloadableCatalogState else {
            XCTFail("A duplicate-ID catalog must be unavailable.")
            return
        }
        XCTAssertEqual(failure.code, "offline_inventory_identity_violation")
        XCTAssertEqual(coordinator.snapshot.lastFailure?.code, failure.code)
        XCTAssertTrue(coordinator.snapshot.downloadableRegions.isEmpty)
    }

    @MainActor
    func testSnapshotObserverCanRemoveItselfDuringPublication() async throws {
        let engine = try FakeOfflineMapEngine()
        let coordinator = try makeCoordinator(engine: engine)
        var observerID: UUID?
        var callbackCount = 0
        observerID = coordinator.addSnapshotObserver { _ in
            callbackCount += 1
            if callbackCount > 1, let observerID {
                coordinator.removeSnapshotObserver(observerID)
            }
        }

        await coordinator.prepare()

        XCTAssertGreaterThanOrEqual(callbackCount, 2)
        if let observerID {
            coordinator.removeSnapshotObserver(observerID)
        }
    }

    @MainActor
    func testSuccessfulRefreshClearsResolvedInventoryFailure() async throws {
        let engine = try FakeOfflineMapEngine()
        await engine.setStorageFailure(
            OfflineMapFailure(
                code: "synthetic_storage_failure",
                message: "Synthetic storage failure.",
                isRecoverable: true
            )
        )
        let coordinator = try makeCoordinator(engine: engine)
        await coordinator.prepare()
        XCTAssertEqual(coordinator.snapshot.lastFailure?.code, "synthetic_storage_failure")

        await engine.setStorageFailure(nil)
        try await coordinator.refresh()

        XCTAssertNil(coordinator.snapshot.lastFailure)
        XCTAssertTrue(coordinator.snapshot.storageState.isCurrent)
    }

    @MainActor
    private func makeCoordinator(
        engine: FakeOfflineMapEngine,
        reserveBytes: Int64 = 100,
        updateMultiplier: Double? = nil,
        connectivityPolicy: OfflineMapConnectivityPolicy = .radioSilent
    ) throws -> OfflineMapCoordinator {
        OfflineMapCoordinator(
            engine: engine,
            storagePolicy: try OfflineMapStoragePolicy(
                minimumPostOperationFreeBytes: reserveBytes,
                updateStagingBytesPerInstalledByte: updateMultiplier
            ),
            connectivityPolicy: connectivityPolicy
        )
    }
}
