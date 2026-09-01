import Foundation

#if canImport(XCTest) && !APP_RADIO_SILENCE_SOURCE_VERIFICATION
import XCTest
@testable import EusoTrip

final class AppRadioSilenceLeaseStateTests: XCTestCase {
    func testFirstAndNestedLeasesRequireFinalRelease() {
        var state = AppRadioSilenceLeaseState()

        let first = state.acquire()
        XCTAssertEqual(first.transition, .firstLease)
        XCTAssertTrue(state.isEnforced)
        XCTAssertEqual(state.activeLeaseCount, 1)

        let nested = state.acquire()
        XCTAssertEqual(nested.transition, .nestedLease)
        XCTAssertNotEqual(first.lease, nested.lease)
        XCTAssertEqual(state.activeLeaseCount, 2)

        XCTAssertEqual(state.release(first.lease), .stillEnforced)
        XCTAssertTrue(state.isEnforced)
        XCTAssertEqual(state.release(nested.lease), .finalLeaseReleased)
        XCTAssertFalse(state.isEnforced)
    }

    func testDuplicateAndForeignReleaseAreIdempotent() {
        var state = AppRadioSilenceLeaseState()
        let owned = state.acquire().lease

        XCTAssertEqual(state.release(AppRadioSilenceLease()), .unknownLease)
        XCTAssertEqual(state.activeLeaseCount, 1)
        XCTAssertEqual(state.release(owned), .finalLeaseReleased)
        XCTAssertEqual(state.release(owned), .unknownLease)
        XCTAssertEqual(state.activeLeaseCount, 0)
    }
}
#endif

#if APP_RADIO_SILENCE_SOURCE_VERIFICATION
@main
enum AppRadioSilenceLeaseStateSourceVerification {
    static func main() {
        var state = AppRadioSilenceLeaseState()
        precondition(!state.isEnforced)

        let first = state.acquire()
        precondition(first.transition == .firstLease)
        let nested = state.acquire()
        precondition(nested.transition == .nestedLease)
        precondition(first.lease != nested.lease)
        precondition(state.activeLeaseCount == 2)

        precondition(state.release(AppRadioSilenceLease()) == .unknownLease)
        precondition(state.activeLeaseCount == 2)
        precondition(state.release(first.lease) == .stillEnforced)
        precondition(state.isEnforced)
        precondition(state.release(first.lease) == .unknownLease)
        precondition(state.release(nested.lease) == .finalLeaseReleased)
        precondition(!state.isEnforced)
    }
}
#endif
