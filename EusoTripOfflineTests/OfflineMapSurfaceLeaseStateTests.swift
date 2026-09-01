import XCTest
@testable import EusoTrip

final class OfflineMapSurfaceLeaseStateTests: XCTestCase {
    func testSecondWindowCannotEnterWhileFirstOwnsSurface() {
        var lease = OfflineMapSurfaceLeaseState()
        let first = UUID()
        let second = UUID()

        XCTAssertTrue(lease.reserve(for: first))
        XCTAssertEqual(lease.status(for: first), .ownedByCaller)
        XCTAssertEqual(lease.status(for: second), .ownedByAnotherSurface)
        XCTAssertEqual(lease.revision, 1)

        XCTAssertFalse(lease.reserve(for: second))
        XCTAssertEqual(lease.revision, 1)
    }

    func testSameOwnerReservationIsIdempotentDuringLoading() {
        var lease = OfflineMapSurfaceLeaseState()
        let owner = UUID()

        XCTAssertTrue(lease.reserve(for: owner))
        XCTAssertTrue(lease.reserve(for: owner))
        XCTAssertEqual(lease.status(for: owner), .ownedByCaller)
        XCTAssertEqual(lease.revision, 1)
    }

    func testReleaseHandsSurfaceToWaitingWindow() {
        var lease = OfflineMapSurfaceLeaseState()
        let first = UUID()
        let second = UUID()

        XCTAssertTrue(lease.reserve(for: first))
        XCTAssertFalse(lease.release(for: second))
        XCTAssertEqual(lease.revision, 1)

        XCTAssertTrue(lease.release(for: first))
        XCTAssertEqual(lease.status(for: second), .available)
        XCTAssertEqual(lease.revision, 2)

        XCTAssertTrue(lease.reserve(for: second))
        XCTAssertEqual(lease.status(for: second), .ownedByCaller)
        XCTAssertEqual(lease.revision, 3)
    }

    func testOpaqueFailureForceReleaseWakesWaiters() {
        var lease = OfflineMapSurfaceLeaseState()
        let first = UUID()
        let second = UUID()

        XCTAssertTrue(lease.reserve(for: first))
        XCTAssertTrue(lease.forceRelease())
        XCTAssertEqual(lease.status(for: second), .available)
        XCTAssertEqual(lease.revision, 2)
        XCTAssertFalse(lease.forceRelease())
        XCTAssertEqual(lease.revision, 2)
    }
}
