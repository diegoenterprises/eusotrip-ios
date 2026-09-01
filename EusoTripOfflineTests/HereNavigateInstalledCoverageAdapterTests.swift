import Foundation
import XCTest
@testable import EusoTrip

final class HereNavigateInstalledCoverageAdapterTests: XCTestCase {
    func testCompleteCoverageRequiresEveryRequestedCoordinate() throws {
        let evidence = try coverageEvidence("here:region:alpha")
        let coordinate = try OfflineGeoCoordinate(latitude: 41.88, longitude: -87.63)
        let incomplete = try resolution(
            classification: .verifiedInside(evidence),
            coordinateClassifications: [
                OfflineCoverageCoordinateClassification(
                    index: 0,
                    coordinate: coordinate,
                    classification: .outside
                ),
            ]
        )

        XCTAssertThrowsError(
            try HereNavigateCoverageAdmission.requireCompleteEvidence(incomplete)
        ) { error in
            XCTAssertEqual(
                (error as? HereNavigateOfflineAdapterError)?.code,
                .coverageUnverified
            )
        }
    }

    func testCompleteCoveragePreservesApproachingBoundaryEvidence() throws {
        let evidence = try coverageEvidence("here:region:alpha")
        let coordinate = try OfflineGeoCoordinate(latitude: 41.88, longitude: -87.63)
        let admitted = try resolution(
            classification: .approachingBoundary(
                coverage: evidence,
                distanceMeters: 125
            ),
            coordinateClassifications: [
                OfflineCoverageCoordinateClassification(
                    index: 0,
                    coordinate: coordinate,
                    classification: .approachingBoundary(
                        coverage: evidence,
                        distanceMeters: 125
                    )
                ),
            ]
        )

        let completeEvidence = try HereNavigateCoverageAdmission
            .requireCompleteEvidence(admitted)
        let routeCoverage = try HereNavigateCoverageAdmission
            .requireCurrentRouteEvidence(admitted, contains: evidence)
        XCTAssertEqual(completeEvidence, evidence)
        XCTAssertEqual(
            routeCoverage,
            .approachingBoundary(coverage: evidence, distanceMeters: 125)
        )
        XCTAssertThrowsError(
            try HereNavigateCoverageAdmission.requireCompleteEvidence(
                admitted,
                expectedCoordinateCount: 2
            )
        )
        XCTAssertThrowsError(
            try HereNavigateCoverageAdmission.requireCompleteEvidence(
                admitted,
                expectedCoordinateCount: 1,
                expectedGeometryKind: .point
            )
        )
    }

    func testRouteEvidenceMustStillContainEveryOriginallyAttributedRegion() throws {
        let current = try coverageEvidence("here:region:alpha")
        let expected = try coverageEvidence(
            "here:region:alpha",
            "here:region:bravo"
        )
        let coordinate = try OfflineGeoCoordinate(latitude: 41.88, longitude: -87.63)
        let resolution = try resolution(
            classification: .verifiedInside(current),
            coordinateClassifications: [
                OfflineCoverageCoordinateClassification(
                    index: 0,
                    coordinate: coordinate,
                    classification: .verifiedInside(current)
                ),
            ]
        )

        XCTAssertThrowsError(
            try HereNavigateCoverageAdmission.requireCurrentRouteEvidence(
                resolution,
                contains: expected
            )
        )
    }

    func testCoverageUnionIsUniqueAndDeterministicallySorted() throws {
        let alpha = try coverageEvidence("here:region:alpha")
        let bravoAlpha = try coverageEvidence(
            "here:region:bravo",
            "here:region:alpha"
        )

        let union = try HereNavigateCoverageAdmission.unionEvidence([
            bravoAlpha,
            alpha,
        ])

        XCTAssertEqual(
            union.regionIDs.map(\.rawValue),
            ["here:region:alpha", "here:region:bravo"]
        )
    }

    func testCoverageAuthorityIsWriteOnce() throws {
        let authority = HereNavigateInstalledCoverageAuthority()
        let installation = try HereNavigateInstalledCoverageInstallation(
            resolver: UnusedCoverageResolver(),
            expectedSDKVersion: "4.27.2.0",
            routeCorridorHalfWidthMeters: 75
        )

        try authority.installOnce(installation)

        XCTAssertEqual(
            authority.currentInstallation()?.expectedSDKVersion,
            "4.27.2.0"
        )
        XCTAssertThrowsError(try authority.installOnce(installation)) { error in
            XCTAssertEqual(
                error as? HereNavigateInstalledCoverageConfigurationError,
                .alreadyInstalled
            )
        }
    }

    func testProductionLocationAccuracyBoundaryIsExactAndFinite() {
        XCTAssertTrue(HereNavigationLocationAcceptancePolicy.production
            .acceptsHorizontalAccuracy(65))
        XCTAssertFalse(HereNavigationLocationAcceptancePolicy.production
            .acceptsHorizontalAccuracy(Double(65).nextUp))
        XCTAssertFalse(HereNavigationLocationAcceptancePolicy.production
            .acceptsHorizontalAccuracy(-1))
        XCTAssertFalse(HereNavigationLocationAcceptancePolicy.production
            .acceptsHorizontalAccuracy(.infinity))
        XCTAssertFalse(HereNavigationLocationAcceptancePolicy.production
            .acceptsHorizontalAccuracy(.nan))
    }

    func testNavigationEventSequencerSchedulesOneDrainAndPreservesFIFO() {
        let sequencer = OfflineNavigationEventSequencer()
        let first = Date(timeIntervalSince1970: 100)
        let second = Date(timeIntervalSince1970: 200)

        XCTAssertTrue(sequencer.enqueue(.arrived(first)))
        XCTAssertFalse(sequencer.enqueue(.arrived(second)))
        XCTAssertEqual(sequencer.drain(), [.arrived(first), .arrived(second)])
        XCTAssertTrue(sequencer.enqueue(.arrived(second)))
    }

    @MainActor
    func testPrincipalSerializerDoesNotInterleaveSuspendedOperations() async {
        let serializer = OfflineMapPrincipalTransitionSerializer()
        let firstEntered = TestAsyncLatch()
        let releaseFirst = TestAsyncLatch()
        let log = TestSerialLog()

        let first = Task { @MainActor in
            await serializer.run {
                await log.append("first-enter")
                await firstEntered.signal()
                await releaseFirst.wait()
                await log.append("first-exit")
            }
        }
        await firstEntered.wait()

        let second = Task { @MainActor in
            await serializer.run {
                await log.append("second-enter")
                await log.append("second-exit")
            }
        }
        await releaseFirst.signal()
        _ = await first.value
        _ = await second.value
        let snapshot = await log.snapshot()

        XCTAssertEqual(
            snapshot,
            ["first-enter", "first-exit", "second-enter", "second-exit"]
        )
    }

    private func coverageEvidence(
        _ rawRegionIDs: String...
    ) throws -> OfflineInstalledCoverageEvidence {
        try OfflineInstalledCoverageEvidence(
            regionIDs: try rawRegionIDs.map(OfflineMapRegionID.init)
        )
    }

    private func resolution(
        classification: OfflineInstalledCoverageClassification,
        coordinateClassifications: [OfflineCoverageCoordinateClassification]
    ) throws -> OfflineInstalledCoverageResolution {
        OfflineInstalledCoverageResolution(
            geometryKind: .routeCorridor,
            classification: classification,
            coordinateClassifications: coordinateClassifications,
            manifestID: "manifest-test",
            manifestSequence: 1,
            catalogVersion: try HEREOfflineCatalogVersion("catalog-test"),
            evaluatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}

private actor TestAsyncLatch {
    private var signaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        signaled = true
        let retained = waiters
        waiters.removeAll()
        retained.forEach { $0.resume() }
    }

    func wait() async {
        guard !signaled else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private actor TestSerialLog {
    private var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func snapshot() -> [String] {
        values
    }
}

private actor UnusedCoverageResolver: OfflineInstalledCoverageResolving {
    func resolveInstalledCoverage(
        for geometry: OfflineCoverageRequestGeometry
    ) async throws -> OfflineInstalledCoverageResolution {
        _ = geometry
        throw SignedInstalledCoverageError.manifestMissing
    }
}
