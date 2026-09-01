import Combine
import Foundation
import XCTest
@testable import EusoTrip

#if !canImport(heresdk)
final class HereNavigateMissingSDKTests: XCTestCase {
    @MainActor
    func testCompositionOwnerIsAppScopedAndMulticastsOneCoordinatorSnapshot() async throws {
        let storagePolicy = try OfflineMapStoragePolicy(minimumPostOperationFreeBytes: 100)
        let firstOwner = OfflineMapComposition.makeOwner(
            storagePolicy: storagePolicy,
            connectivityPolicy: .radioSilent
        )
        let secondOwner = OfflineMapComposition.makeOwner(
            storagePolicy: storagePolicy,
            connectivityPolicy: .onlineAllowed
        )

        XCTAssertTrue(firstOwner === secondOwner)
        XCTAssertTrue(firstOwner.coordinator === secondOwner.coordinator)

        let firstObserver = expectation(description: "first owner subscriber receives readiness")
        let secondObserver = expectation(description: "second owner subscriber receives readiness")
        var firstFulfilled = false
        var secondFulfilled = false
        var cancellables = Set<AnyCancellable>()
        firstOwner.$snapshot
            .sink { snapshot in
                guard !firstFulfilled, case .blocked = snapshot.readiness else { return }
                firstFulfilled = true
                firstObserver.fulfill()
            }
            .store(in: &cancellables)
        secondOwner.$snapshot
            .sink { snapshot in
                guard !secondFulfilled, case .blocked = snapshot.readiness else { return }
                secondFulfilled = true
                secondObserver.fulfill()
            }
            .store(in: &cancellables)

        await firstOwner.coordinator.prepare()
        await fulfillment(of: [firstObserver, secondObserver], timeout: 2)

        XCTAssertEqual(firstOwner.snapshot, secondOwner.snapshot)
        XCTAssertEqual(firstOwner.snapshot, firstOwner.coordinator.snapshot)
        XCTAssertEqual(firstOwner.snapshot.connectivityPolicy, .radioSilent)
        XCTAssertFalse(cancellables.isEmpty)
    }

    func testPlaceholderAndUnresolvedRuntimeCredentialsAreRejected() throws {
        let placeholderPairs = [
            ("REPLACE_WITH_HERE_ACCESS_KEY", "valid-test-secret"),
            ("CHANGEME", "valid-test-secret"),
            ("CHANGE_ME", "valid-test-secret"),
            ("$(HERESDK_ACCESS_KEY_ID)", "valid-test-secret"),
            ("valid-test-key", "$(HERESDK_ACCESS_KEY_SECRET)")
        ]
        for (accessKeyID, accessKeySecret) in placeholderPairs {
            let fixture = try makeCredentialBundle(
                accessKeyID: accessKeyID,
                accessKeySecret: accessKeySecret
            )
            defer { try? FileManager.default.removeItem(at: fixture.url) }
            XCTAssertNil(
                HereSDKRuntimeCredentials(bundle: fixture.bundle),
                "Placeholder credentials must not provision HERE runtime startup."
            )
        }

        let validFixture = try makeCredentialBundle(
            accessKeyID: "  test-access-key-id  ",
            accessKeySecret: "  test-access-key-secret  "
        )
        defer { try? FileManager.default.removeItem(at: validFixture.url) }
        let credentials = try XCTUnwrap(HereSDKRuntimeCredentials(bundle: validFixture.bundle))
        XCTAssertEqual(credentials.accessKeyID, "test-access-key-id")
        XCTAssertEqual(credentials.accessKeySecret, "test-access-key-secret")
    }

    func testMissingSDKInspectionAndOperationsFailTruthfully() async throws {
        let engine = HereNavigateOfflineEngine()

        let inspection = await engine.inspect(connectivityPolicy: .radioSilent)

        XCTAssertTrue(inspection.capabilities.isEmpty)
        XCTAssertTrue(inspection.blockers.contains { $0.code == .sdkUnavailable })
        if case .unusable = inspection.persistentHealth {
            // Expected: missing binary never masquerades as persistent coverage.
        } else {
            XCTFail("A build without HERE Navigate must report unusable persistent maps.")
        }
        if case .notEnforced = inspection.radioSilenceState {
            // Expected: a missing SDK cannot prove radio silence.
        } else {
            XCTFail("A build without HERE Navigate must not claim radio-silence enforcement.")
        }

        do {
            _ = try await engine.installedRegions()
            XCTFail("Operational adapter methods must fail when the framework is absent.")
        } catch let error as HereNavigateOfflineAdapterError {
            XCTAssertEqual(error.offlineMapFailure.code, "here_sdk_missing_framework")
            XCTAssertFalse(error.offlineMapFailure.isRecoverable)
        } catch {
            XCTFail("Expected typed missing-framework failure, received \(error).")
        }
    }

    func testMissingSDKNavigationSessionTransitionsToTypedFailure() async throws {
        let route = try makeRoadRoute()
        let session = await MainActor.run {
            OfflineMapComposition.makeNavigationSession()
        }

        do {
            try await session.start(route: route, eventHandler: { _ in })
            XCTFail("Native guidance must fail when the HERE framework is absent.")
        } catch let failure as OfflineNavigationFailure {
            XCTAssertEqual(failure.code, .nativeGuidanceUnavailable)
            XCTAssertFalse(failure.isRecoverable)
        } catch {
            XCTFail("Expected typed native-guidance failure, received \(error).")
        }

        guard case .failed(let routeID, let failure) = await session.currentState() else {
            XCTFail("The session must retain its missing-SDK failure state.")
            return
        }
        XCTAssertEqual(routeID, route.id)
        XCTAssertEqual(failure.code, .nativeGuidanceUnavailable)

        let location = try OfflineDeviceLocationSample(
            coordinate: try OfflineGeoCoordinate(latitude: 29.7604, longitude: -95.3698),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            horizontalAccuracyMeters: 4,
            speedMetersPerSecond: 12,
            courseDegrees: 30,
            provenance: .deviceGNSS
        )
        do {
            try await session.feed(location: location)
            XCTFail("Location feeding must not revive unavailable native guidance.")
        } catch let failure as OfflineNavigationFailure {
            XCTAssertEqual(failure.code, .nativeGuidanceUnavailable)
        }
    }

    private func makeRoadRoute() throws -> OfflineLocalRoute {
        let origin = try OfflineGeoCoordinate(latitude: 29.7604, longitude: -95.3698)
        let destination = try OfflineGeoCoordinate(latitude: 32.7767, longitude: -96.7970)
        let summary = try OfflineRouteSummary(distanceMeters: 385_000, durationSeconds: 18_000)
        let section = try OfflineRouteSection(
            coordinates: [origin, destination],
            maneuvers: [],
            summary: summary
        )
        let coverage = try OfflineInstalledCoverageEvidence(
            regionIDs: [OfflineMapRegionID("missing-sdk-test-region")]
        )
        return try OfflineLocalRoute(
            id: "missing-sdk-road-route",
            mode: .road,
            sections: [section],
            summary: summary,
            notices: [],
            coverage: coverage
        )
    }

    private func makeCredentialBundle(
        accessKeyID: String,
        accessKeySecret: String
    ) throws -> (bundle: Bundle, url: URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EusoTripCredentialFixture-\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.app.eusotrip.tests.credentials.\(UUID().uuidString)",
            "CFBundleName": "EusoTripCredentialFixture",
            "CFBundlePackageType": "BNDL",
            "CFBundleVersion": "1",
            "HERESDKAccessKeyID": accessKeyID,
            "HERESDKAccessKeySecret": accessKeySecret
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try data.write(to: url.appendingPathComponent("Info.plist"), options: .atomic)
        return (try XCTUnwrap(Bundle(url: url)), url)
    }
}
#endif
