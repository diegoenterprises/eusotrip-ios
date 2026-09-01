import XCTest
@testable import EusoTrip

final class OfflineMapLibraryViewModelTests: XCTestCase {
    func testInstalledByteAggregationReportsOverflowAsUnknown() {
        XCTAssertEqual(OfflineMapByteMath.sum([1, 2, 3]), 6)
        XCTAssertNil(OfflineMapByteMath.sum([Int64.max, 1]))
    }

    @MainActor
    func testRepairAvailabilityRequiresExplicitNativeRepairCapability() async throws {
        let unavailableEngine = try FakeOfflineMapEngine(
            capabilities: OfflineMapCapabilities.fullRoadFreightParity
                .subtracting(.persistentMapRepair),
            persistentHealth: .needsRepair(reason: "Fake persistent map requires repair.")
        )
        let unavailableCoordinator = try makeCoordinator(engine: unavailableEngine)
        let unavailableViewModel = OfflineMapLibraryViewModel(coordinator: unavailableCoordinator)

        await unavailableViewModel.prepare()

        XCTAssertFalse(unavailableViewModel.repairAvailability.isEnabled)
        XCTAssertEqual(
            unavailableViewModel.repairAvailability.disabledReason,
            "The native HERE engine did not prove persistent-map repair support."
        )

        let availableEngine = try FakeOfflineMapEngine(
            persistentHealth: .needsRepair(reason: "Fake persistent map requires repair.")
        )
        let availableCoordinator = try makeCoordinator(engine: availableEngine)
        let availableViewModel = OfflineMapLibraryViewModel(coordinator: availableCoordinator)

        await availableViewModel.prepare()

        guard case .blocked = availableViewModel.snapshot.readiness else {
            XCTFail("Health damage should still block native-engine readiness.")
            return
        }
        XCTAssertTrue(availableViewModel.snapshot.availableCapabilities.contains(.persistentMapRepair))
        XCTAssertTrue(availableViewModel.repairAvailability.isEnabled)
        XCTAssertNil(availableViewModel.repairAvailability.disabledReason)
    }

    @MainActor
    private func makeCoordinator(engine: FakeOfflineMapEngine) throws -> OfflineMapCoordinator {
        OfflineMapCoordinator(
            engine: engine,
            storagePolicy: try OfflineMapStoragePolicy(minimumPostOperationFreeBytes: 100),
            connectivityPolicy: .onlineAllowed
        )
    }
}
