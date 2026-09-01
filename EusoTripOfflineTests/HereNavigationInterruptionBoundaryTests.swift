import XCTest
@testable import EusoTrip

final class HereNavigationInterruptionBoundaryTests: XCTestCase {
    func testInterruptionMutesOnceAndRequiresSystemResumePlusFreshLocation() {
        var boundary = HereNavigationInterruptionBoundary()
        let restoredAt = Date(timeIntervalSinceReferenceDate: 500)

        XCTAssertEqual(
            boundary.receive(.began, sessionIsActive: true),
            .pauseAndMute
        )
        XCTAssertTrue(boundary.blocksNativeCallbacks)
        XCTAssertEqual(
            boundary.receive(.began, sessionIsActive: true),
            .none
        )
        XCTAssertFalse(boundary.acceptFreshLocation(observedAt: restoredAt))

        XCTAssertEqual(
            boundary.receive(
                .ended(shouldResume: true),
                sessionIsActive: true,
                now: restoredAt
            ),
            .prepareAudioAndAwaitFreshLocation
        )
        XCTAssertTrue(boundary.blocksNativeCallbacks)
        XCTAssertFalse(
            boundary.acceptFreshLocation(
                observedAt: restoredAt.addingTimeInterval(-0.001)
            )
        )
        XCTAssertTrue(boundary.acceptFreshLocation(observedAt: restoredAt))
        XCTAssertFalse(boundary.blocksNativeCallbacks)
    }

    func testSystemDeniedResumeRemainsPaused() {
        var boundary = HereNavigationInterruptionBoundary()

        _ = boundary.receive(.began, sessionIsActive: true)
        XCTAssertEqual(
            boundary.receive(.ended(shouldResume: false), sessionIsActive: true),
            .remainPaused
        )
        XCTAssertTrue(boundary.blocksNativeCallbacks)
        XCTAssertFalse(boundary.acceptFreshLocation(observedAt: Date()))
        XCTAssertEqual(
            boundary.receive(.ended(shouldResume: true), sessionIsActive: true),
            .none
        )
        XCTAssertTrue(boundary.blocksNativeCallbacks)
    }

    func testFailedAudioPreparationCannotBeClearedByLocation() {
        var boundary = HereNavigationInterruptionBoundary()

        _ = boundary.receive(.began, sessionIsActive: true)
        _ = boundary.receive(.ended(shouldResume: true), sessionIsActive: true)
        boundary.rejectResume()

        XCTAssertTrue(boundary.blocksNativeCallbacks)
        XCTAssertFalse(boundary.acceptFreshLocation(observedAt: Date()))
        XCTAssertEqual(
            boundary.receive(.ended(shouldResume: true), sessionIsActive: true),
            .none
        )
        XCTAssertTrue(boundary.blocksNativeCallbacks)
    }

    func testInactiveSessionClearsStaleInterruptionState() {
        var boundary = HereNavigationInterruptionBoundary()
        _ = boundary.receive(.began, sessionIsActive: true)

        XCTAssertEqual(
            boundary.receive(.ended(shouldResume: true), sessionIsActive: false),
            .none
        )
        XCTAssertFalse(boundary.blocksNativeCallbacks)
    }
}
