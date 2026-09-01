import Foundation

#if canImport(XCTest) && !HERE_OFFLINE_MAP_JOURNEY_PROJECTION_SOURCE_VERIFICATION
import XCTest
@testable import EusoTrip
#endif

private enum HereOfflineMapJourneyProjectionFixtures {
    static func localRoute(
        id: String = "route-1",
        mode: OfflineRouteMode = .truck,
        latitudeOffset: Double = 0,
        region: String = "here:cm:nam:usa:illinois"
    ) throws -> OfflineLocalRoute {
        let coordinates = [
            try OfflineGeoCoordinate(
                latitude: 41.8781 + latitudeOffset,
                longitude: -87.6298
            ),
            try OfflineGeoCoordinate(
                latitude: 41.8810 + latitudeOffset,
                longitude: -87.6200
            ),
        ]
        let summary = try OfflineRouteSummary(
            distanceMeters: 1_000,
            durationSeconds: 90
        )
        return try OfflineLocalRoute(
            id: id,
            mode: mode,
            sections: [
                try OfflineRouteSection(
                    coordinates: coordinates,
                    maneuvers: [],
                    summary: summary
                ),
            ],
            summary: summary,
            notices: [],
            coverage: OfflineInstalledCoverageEvidence(
                regionIDs: [try OfflineMapRegionID(region)]
            )
        )
    }
}

#if canImport(XCTest) && !HERE_OFFLINE_MAP_JOURNEY_PROJECTION_SOURCE_VERIFICATION
final class HereOfflineMapJourneyProjectionTests: XCTestCase {
    func testVerifiedPositionPreservesExactDeviceEvidence() throws {
        let coordinate = try OfflineGeoCoordinate(latitude: 41.8781, longitude: -87.6298)
        let timestamp = Date(timeIntervalSinceReferenceDate: 900)

        let position = try HereOfflineMapJourneyPosition(
            coordinate: coordinate,
            timestamp: timestamp,
            horizontalAccuracyMeters: 8,
            speedMetersPerSecond: 17,
            bearingDegrees: 270
        )

        XCTAssertEqual(position.coordinate, coordinate)
        XCTAssertEqual(position.timestamp, timestamp)
        XCTAssertEqual(position.horizontalAccuracyMeters, 8)
        XCTAssertEqual(position.speedMetersPerSecond, 17)
        XCTAssertEqual(position.bearingDegrees, 270)
    }

    func testInvalidPositionEvidenceFailsClosed() throws {
        let coordinate = try OfflineGeoCoordinate(latitude: 41.8781, longitude: -87.6298)

        XCTAssertThrowsError(
            try HereOfflineMapJourneyPosition(
                coordinate: coordinate,
                timestamp: Date(),
                horizontalAccuracyMeters: -1
            )
        )
        XCTAssertThrowsError(
            try HereOfflineMapJourneyPosition(
                coordinate: coordinate,
                timestamp: Date(),
                horizontalAccuracyMeters: 5,
                speedMetersPerSecond: -.infinity
            )
        )
        XCTAssertThrowsError(
            try HereOfflineMapJourneyPosition(
                coordinate: coordinate,
                timestamp: Date(),
                horizontalAccuracyMeters: 5,
                bearingDegrees: 360
            )
        )
    }

    func testEmptyProjectionCannotClaimFollowMode() {
        XCTAssertNil(HereOfflineMapJourneyProjection.empty.route)
        XCTAssertNil(HereOfflineMapJourneyProjection.empty.canonicalRoute)
        XCTAssertNil(HereOfflineMapJourneyProjection.empty.position)
        XCTAssertFalse(HereOfflineMapJourneyProjection.empty.followsPosition)
    }

    func testRerouteReplacementPreservesIdentityModeAndCoverage() throws {
        let replacementRoute = try HereOfflineMapJourneyProjectionFixtures.localRoute(
            latitudeOffset: 0.02
        )
        let replacement = try OfflineNavigationRouteReplacement(
            route: replacementRoute,
            replacingRouteID: replacementRoute.id,
            expectedMode: replacementRoute.mode,
            admittedCoverage: replacementRoute.coverage
        )

        XCTAssertEqual(replacement.route, replacementRoute)
        XCTAssertThrowsError(
            try OfflineNavigationRouteReplacement(
                route: replacementRoute,
                replacingRouteID: "other-route",
                expectedMode: replacementRoute.mode,
                admittedCoverage: replacementRoute.coverage
            )
        )
        XCTAssertThrowsError(
            try OfflineNavigationRouteReplacement(
                route: replacementRoute,
                replacingRouteID: replacementRoute.id,
                expectedMode: .road,
                admittedCoverage: replacementRoute.coverage
            )
        )
        let otherCoverage = try OfflineInstalledCoverageEvidence(
            regionIDs: [try OfflineMapRegionID("here:cm:nam:usa:indiana")]
        )
        XCTAssertThrowsError(
            try OfflineNavigationRouteReplacement(
                route: replacementRoute,
                replacingRouteID: replacementRoute.id,
                expectedMode: replacementRoute.mode,
                admittedCoverage: otherCoverage
            )
        )
    }

    func testAcceptedRerouteOwnsProjectionAgainstStaleHostRoute() throws {
        let original = try HereOfflineMapJourneyProjectionFixtures.localRoute()
        let rerouted = try HereOfflineMapJourneyProjectionFixtures.localRoute(
            latitudeOffset: 0.02
        )
        let replacement = try OfflineNavigationRouteReplacement(
            route: rerouted,
            replacingRouteID: original.id,
            expectedMode: original.mode,
            admittedCoverage: rerouted.coverage
        )
        var authority = OfflineNavigationRouteProjectionAuthority()
        authority.begin(original)

        XCTAssertTrue(authority.accept(replacement))
        XCTAssertEqual(
            authority.resolveHostRoute(original, navigationIsActive: true),
            rerouted
        )
        XCTAssertEqual(
            authority.resolveHostRoute(original, navigationIsActive: false),
            rerouted
        )
    }

    func testSameRouteIDWithNewGeometryChangesNativeProjectionSignature() throws {
        let original = try HereOfflineMapJourneyProjectionFixtures.localRoute()
        let rerouted = try HereOfflineMapJourneyProjectionFixtures.localRoute(
            latitudeOffset: 0.02
        )

        XCTAssertEqual(original.id, rerouted.id)
        XCTAssertNotEqual(
            HereOfflineMapProjectedRouteSignature.local(original),
            HereOfflineMapProjectedRouteSignature.local(rerouted)
        )
    }

    @MainActor
    func testHostReconcileCannotRegressNewerNavigationPosition() throws {
        let coordinate = try OfflineGeoCoordinate(latitude: 41.8781, longitude: -87.6298)
        let earlier = try HereOfflineMapJourneyPosition(
            coordinate: coordinate,
            timestamp: Date(timeIntervalSinceReferenceDate: 900),
            horizontalAccuracyMeters: 8
        )
        let newer = try HereOfflineMapJourneyPosition(
            coordinate: coordinate,
            timestamp: Date(timeIntervalSinceReferenceDate: 901),
            horizontalAccuracyMeters: 6,
            speedMetersPerSecond: 17,
            bearingDegrees: 270
        )
        let surface = HereNavigateOfflineMapSurface()

        surface.reconcileHostJourneyProjection(
            .init(route: nil, position: earlier, followsPosition: false)
        )
        surface.updateLivePosition(newer, followsPosition: true)
        surface.reconcileHostJourneyProjection(
            .init(route: nil, position: earlier, followsPosition: false)
        )

        XCTAssertEqual(surface.journeyProjection.position, newer)
        XCTAssertTrue(surface.journeyProjection.followsPosition)
    }

    @MainActor
    func testClearedNavigationPositionCannotBeRestoredByDelayedHostState() throws {
        let coordinate = try OfflineGeoCoordinate(latitude: 41.8781, longitude: -87.6298)
        let position = try HereOfflineMapJourneyPosition(
            coordinate: coordinate,
            timestamp: Date(timeIntervalSinceReferenceDate: 900),
            horizontalAccuracyMeters: 8
        )
        let surface = HereNavigateOfflineMapSurface()

        surface.updateLivePosition(position, followsPosition: true)
        surface.clearLivePosition()
        surface.reconcileHostJourneyProjection(
            .init(route: nil, position: position, followsPosition: true)
        )

        XCTAssertNil(surface.journeyProjection.position)
        XCTAssertFalse(surface.journeyProjection.followsPosition)
    }
}
#endif

#if HERE_OFFLINE_MAP_JOURNEY_PROJECTION_SOURCE_VERIFICATION
@main
enum HereOfflineMapJourneyProjectionSourceVerification {
    @MainActor
    static func main() throws {
        let coordinate = try OfflineGeoCoordinate(latitude: 41.8781, longitude: -87.6298)
        let earlier = try HereOfflineMapJourneyPosition(
            coordinate: coordinate,
            timestamp: Date(timeIntervalSinceReferenceDate: 900),
            horizontalAccuracyMeters: 8
        )
        let newer = try HereOfflineMapJourneyPosition(
            coordinate: coordinate,
            timestamp: Date(timeIntervalSinceReferenceDate: 901),
            horizontalAccuracyMeters: 6,
            speedMetersPerSecond: 17,
            bearingDegrees: 270
        )
        let surface = HereNavigateOfflineMapSurface()

        surface.reconcileHostJourneyProjection(
            .init(route: nil, position: earlier, followsPosition: false)
        )
        surface.updateLivePosition(newer, followsPosition: true)
        surface.reconcileHostJourneyProjection(
            .init(route: nil, position: earlier, followsPosition: false)
        )
        precondition(surface.journeyProjection.position == newer)
        precondition(surface.journeyProjection.followsPosition)

        surface.clearLivePosition()
        surface.reconcileHostJourneyProjection(
            .init(route: nil, position: earlier, followsPosition: true)
        )
        precondition(surface.journeyProjection.position == nil)
        precondition(!surface.journeyProjection.followsPosition)

        let original = try HereOfflineMapJourneyProjectionFixtures.localRoute()
        let rerouted = try HereOfflineMapJourneyProjectionFixtures.localRoute(
            latitudeOffset: 0.02
        )
        let replacement = try OfflineNavigationRouteReplacement(
            route: rerouted,
            replacingRouteID: original.id,
            expectedMode: original.mode,
            admittedCoverage: rerouted.coverage
        )
        var authority = OfflineNavigationRouteProjectionAuthority()
        authority.begin(original)
        precondition(authority.accept(replacement))
        precondition(
            authority.resolveHostRoute(original, navigationIsActive: true)
                == rerouted
        )
        precondition(
            HereOfflineMapProjectedRouteSignature.local(original)
                != HereOfflineMapProjectedRouteSignature.local(rerouted)
        )
    }
}
#endif
