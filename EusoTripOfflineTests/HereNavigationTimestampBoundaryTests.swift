import Foundation
import XCTest
@testable import EusoTrip

final class HereNavigationTimestampBoundaryTests: XCTestCase {
    func testNavigationModelsRejectEveryNonFiniteTimestamp() throws {
        let coordinate = try OfflineGeoCoordinate(latitude: 29.7604, longitude: -95.3698)

        for interval in [Double.nan, Double.infinity, -Double.infinity] {
            let timestamp = Date(timeIntervalSinceReferenceDate: interval)
            XCTAssertThrowsError(
                try OfflineDeviceLocationSample(
                    coordinate: coordinate,
                    timestamp: timestamp,
                    horizontalAccuracyMeters: 4,
                    speedMetersPerSecond: 12,
                    courseDegrees: 30,
                    provenance: .deviceGNSS
                )
            ) { error in
                guard case OfflineMapCoreError.invalidInput(let message) = error else {
                    return XCTFail("Expected typed invalid location input, received \(error).")
                }
                XCTAssertEqual(message, "Location timestamp must be finite.")
            }

            XCTAssertThrowsError(
                try OfflineNavigationDeviation(
                    crossTrackMeters: 55,
                    consecutiveSamples: 3,
                    observedAt: timestamp
                )
            ) { error in
                guard case OfflineMapCoreError.invalidInput(let message) = error else {
                    return XCTFail("Expected typed invalid deviation input, received \(error).")
                }
                XCTAssertEqual(message, "Route deviation timestamp must be finite.")
            }
        }
    }

    func testNavigationModelsRetainFiniteTimestampsExactly() throws {
        let timestamp = Date(timeIntervalSinceReferenceDate: 800_000)
        let coordinate = try OfflineGeoCoordinate(latitude: 29.7604, longitude: -95.3698)
        let location = try OfflineDeviceLocationSample(
            coordinate: coordinate,
            timestamp: timestamp,
            horizontalAccuracyMeters: 4,
            speedMetersPerSecond: 12,
            courseDegrees: 30,
            provenance: .deviceGNSS
        )
        let deviation = try OfflineNavigationDeviation(
            crossTrackMeters: 55,
            consecutiveSamples: 3,
            observedAt: timestamp
        )

        XCTAssertEqual(location.timestamp, timestamp)
        XCTAssertEqual(deviation.observedAt, timestamp)
    }

    func testSessionBoundaryAcceptsExactFreshnessEdgesAndRejectsBeyondThem() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        var boundary = HereNavigationTimestampBoundary()

        try boundary.acceptDeviceLocation(
            timestamp: now.addingTimeInterval(-30),
            now: now
        )
        boundary.reset()
        try boundary.acceptDeviceLocation(
            timestamp: now.addingTimeInterval(5),
            now: now
        )
        boundary.reset()

        assertLocationRejected(
            expectedMessage: "The location sample is too old for freight guidance."
        ) {
            try boundary.acceptDeviceLocation(
                timestamp: now.addingTimeInterval(-30.001),
                now: now
            )
        }
        assertLocationRejected(
            expectedMessage: "The location timestamp is implausibly far in the future."
        ) {
            try boundary.acceptDeviceLocation(
                timestamp: now.addingTimeInterval(5.001),
                now: now
            )
        }
    }

    func testSessionBoundaryRejectsReplayedAndOutOfOrderDeviceLocations() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let first = now.addingTimeInterval(-2)
        var boundary = HereNavigationTimestampBoundary()

        try boundary.acceptDeviceLocation(timestamp: first, now: now)
        assertLocationRejected(
            expectedMessage: "The location sample is duplicated or out of order."
        ) {
            try boundary.acceptDeviceLocation(timestamp: first, now: now)
        }
        assertLocationRejected(
            expectedMessage: "The location sample is duplicated or out of order."
        ) {
            try boundary.acceptDeviceLocation(
                timestamp: first.addingTimeInterval(-1),
                now: now
            )
        }

        // Rejections do not advance the boundary or poison the next fresh fix.
        try boundary.acceptDeviceLocation(
            timestamp: first.addingTimeInterval(1),
            now: now
        )
    }

    func testSessionBoundaryRequiresCausalMonotonicDeviationEvidence() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let first = now.addingTimeInterval(-4)
        let second = now.addingTimeInterval(-3)
        let third = now.addingTimeInterval(-2)
        let fourth = now.addingTimeInterval(-1)
        var boundary = HereNavigationTimestampBoundary()

        assertLocationRejected(
            expectedMessage: "Route deviation evidence arrived before an accepted device location."
        ) {
            _ = try boundary.acceptDeviation(timestamp: first, now: now)
        }

        try boundary.acceptDeviceLocation(timestamp: first, now: now)
        try boundary.acceptDeviceLocation(timestamp: second, now: now)
        assertLocationRejected(
            expectedMessage: "Route deviation evidence has no device timestamp."
        ) {
            _ = try boundary.acceptDeviation(timestamp: nil, now: now)
        }
        // HERE may deliver the first callback after the second fix was fed. It
        // remains valid because it is recent, accepted, and not yet consumed.
        XCTAssertEqual(
            try boundary.acceptDeviation(timestamp: first, now: now),
            first
        )
        assertLocationRejected(
            expectedMessage: "Route deviation evidence is duplicated or out of order."
        ) {
            _ = try boundary.acceptDeviation(timestamp: first, now: now)
        }
        assertLocationRejected(
            expectedMessage: "Route deviation evidence is not tied to a recent accepted device location."
        ) {
            _ = try boundary.acceptDeviation(
                timestamp: second.addingTimeInterval(0.5),
                now: now
            )
        }

        // Rejected replayed/invented callbacks do not block the causal callback.
        XCTAssertEqual(
            try boundary.acceptDeviation(timestamp: second, now: now),
            second
        )

        try boundary.acceptDeviceLocation(timestamp: third, now: now)
        try boundary.acceptDeviceLocation(timestamp: fourth, now: now)
        XCTAssertEqual(
            try boundary.acceptDeviation(timestamp: fourth, now: now),
            fourth
        )
        assertLocationRejected(
            expectedMessage: "Route deviation evidence is duplicated or out of order."
        ) {
            _ = try boundary.acceptDeviation(timestamp: third, now: now)
        }
    }

    func testSessionBoundaryBoundsTheRecentAcceptedFixQueue() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let first = now.addingTimeInterval(-10)
        var boundary = HereNavigationTimestampBoundary()

        for index in 0 ... HereNavigationTimestampBoundary.maximumRetainedDeviceLocations {
            try boundary.acceptDeviceLocation(
                timestamp: first.addingTimeInterval(Double(index) * 0.01),
                now: now
            )
        }

        assertLocationRejected(
            expectedMessage: "Route deviation evidence is not tied to a recent accepted device location."
        ) {
            _ = try boundary.acceptDeviation(timestamp: first, now: now)
        }
        let oldestRetained = first.addingTimeInterval(0.01)
        XCTAssertEqual(
            try boundary.acceptDeviation(timestamp: oldestRetained, now: now),
            oldestRetained
        )
    }

    func testSessionBoundaryAppliesFreshnessToDeviationCallbacks() throws {
        let timestamp = Date(timeIntervalSinceReferenceDate: 1_000_000)
        var staleBoundary = HereNavigationTimestampBoundary()
        try staleBoundary.acceptDeviceLocation(timestamp: timestamp, now: timestamp)
        assertLocationRejected(
            expectedMessage: "The route deviation evidence is too old for freight guidance."
        ) {
            _ = try staleBoundary.acceptDeviation(
                timestamp: timestamp,
                now: timestamp.addingTimeInterval(30.001)
            )
        }

        var futureBoundary = HereNavigationTimestampBoundary()
        try futureBoundary.acceptDeviceLocation(timestamp: timestamp, now: timestamp)
        assertLocationRejected(
            expectedMessage: "The route deviation timestamp is implausibly far in the future."
        ) {
            _ = try futureBoundary.acceptDeviation(
                timestamp: timestamp,
                now: timestamp.addingTimeInterval(-5.001)
            )
        }
    }

    func testSessionBoundaryResetStartsASeparateOrderingEpoch() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        var boundary = HereNavigationTimestampBoundary()
        try boundary.acceptDeviceLocation(timestamp: now, now: now)
        _ = try boundary.acceptDeviation(timestamp: now, now: now)

        boundary.reset()

        let earlierFreshTimestamp = now.addingTimeInterval(-1)
        try boundary.acceptDeviceLocation(
            timestamp: earlierFreshTimestamp,
            now: now
        )
        XCTAssertEqual(
            try boundary.acceptDeviation(
                timestamp: earlierFreshTimestamp,
                now: now
            ),
            earlierFreshTimestamp
        )
    }

    func testSuspendedRerouteCannotCommitAfterRejectedLocationPausesSession() {
        let routeID = "road-route-1"
        let generation = UUID()
        let boundary = HereNavigationRerouteCommitBoundary(
            routeID: routeID,
            delegateGeneration: generation
        )

        XCTAssertTrue(
            boundary.permitsCommit(
                activeRouteID: routeID,
                currentDelegateGeneration: generation,
                state: .rerouting(routeID: routeID),
                pausedForRejectedLocation: false
            )
        )

        // This is the actor-reentrancy regression: feed() rejected temporal
        // input while returnToRoute() was suspended in its native callback.
        XCTAssertFalse(
            boundary.permitsCommit(
                activeRouteID: routeID,
                currentDelegateGeneration: generation,
                state: .paused(routeID: routeID, reason: "Location input rejected."),
                pausedForRejectedLocation: true
            )
        )
        XCTAssertFalse(
            boundary.permitsCommit(
                activeRouteID: routeID,
                currentDelegateGeneration: generation,
                state: .rerouting(routeID: routeID),
                pausedForRejectedLocation: true
            )
        )
        XCTAssertFalse(
            boundary.permitsCommit(
                activeRouteID: routeID,
                currentDelegateGeneration: UUID(),
                state: .rerouting(routeID: routeID),
                pausedForRejectedLocation: false
            )
        )
    }

    func testQueuedNativeCallbacksCannotEscapeRejectedLocationPause() throws {
        let routeID = "road-route-1"
        let generation = UUID()
        let pausedState = OfflineNavigationSessionState.paused(
            routeID: routeID,
            reason: "Location input rejected."
        )
        var simulatedState = pausedState
        var emittedEvents: [OfflineNavigationEvent] = []
        var spokenInstructions: [String] = []
        var rerouteStarts = 0

        for kind in HereNavigationNativeCallbackKind.allCases {
            guard HereNavigationNativeCallbackBoundary.permits(
                kind,
                expectedGeneration: generation,
                currentDelegateGeneration: generation,
                activeRouteID: routeID,
                state: simulatedState,
                pausedForRejectedLocation: true,
                rerouteInFlight: false
            ) else { continue }

            switch kind {
            case .eventText:
                let maneuver = try OfflineNavigationManeuverEvent(
                    sequence: 0,
                    instruction: "Queued instruction",
                    distanceMeters: 50,
                    coordinate: nil
                )
                emittedEvents.append(.maneuver(maneuver))
                spokenInstructions.append(maneuver.instruction)
            case .progress:
                break
            case .deviation:
                rerouteStarts += 1
                simulatedState = .rerouting(routeID: routeID)
            case .destination:
                let arrival = Date(timeIntervalSinceReferenceDate: 1_000_000)
                emittedEvents.append(.arrived(arrival))
                simulatedState = .arrived(routeID: routeID, arrivedAt: arrival)
            }
        }

        XCTAssertEqual(simulatedState, pausedState)
        XCTAssertTrue(emittedEvents.isEmpty)
        XCTAssertTrue(spokenInstructions.isEmpty)
        XCTAssertEqual(rerouteStarts, 0)

        let admittedWhileNavigating = HereNavigationNativeCallbackKind.allCases.filter { kind in
            HereNavigationNativeCallbackBoundary.permits(
                kind,
                expectedGeneration: generation,
                currentDelegateGeneration: generation,
                activeRouteID: routeID,
                state: .navigating(routeID: routeID, coverage: .unknown),
                pausedForRejectedLocation: false,
                rerouteInFlight: false
            )
        }
        XCTAssertEqual(admittedWhileNavigating, HereNavigationNativeCallbackKind.allCases)

        let admittedDuringReroute = HereNavigationNativeCallbackKind.allCases.filter { kind in
            HereNavigationNativeCallbackBoundary.permits(
                kind,
                expectedGeneration: generation,
                currentDelegateGeneration: generation,
                activeRouteID: routeID,
                state: .navigating(routeID: routeID, coverage: .unknown),
                pausedForRejectedLocation: false,
                rerouteInFlight: true
            )
        }
        XCTAssertTrue(admittedDuringReroute.isEmpty)
    }

    private func assertLocationRejected(
        expectedMessage: String,
        operation: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            try operation()
            XCTFail("Expected navigation evidence rejection.", file: file, line: line)
        } catch let failure as OfflineNavigationFailure {
            XCTAssertEqual(failure.code, .locationRejected, file: file, line: line)
            XCTAssertEqual(failure.message, expectedMessage, file: file, line: line)
            XCTAssertTrue(failure.isRecoverable, file: file, line: line)
            XCTAssertFalse(failure.message.contains("1000000"), file: file, line: line)
        } catch {
            XCTFail("Expected typed OfflineNavigationFailure, received \(error).", file: file, line: line)
        }
    }
}
