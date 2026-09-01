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

    func testPhoneRestartPublishesStrictlyNewerSharedMarkerState() throws {
        for previousEnforced in [false, true] {
            for sharedStateIsEnforced in [false, true] {
                let previous = AppRadioSilencePhoneMirrorState(
                    isEnforced: previousEnforced,
                    revision: 7,
                    epoch: "phone-install"
                )
                let data = try AppRadioSilencePhoneMirrorPersistence.encode(previous)

                let restarted = AppRadioSilencePhoneMirrorPersistence
                    .restoreForProcessRestart(
                        snapshotData: data,
                        sharedStateIsEnforced: sharedStateIsEnforced,
                        makeEpoch: { "unexpected-new-epoch" }
                    )

                XCTAssertEqual(restarted.isEnforced, sharedStateIsEnforced)
                XCTAssertEqual(restarted.revision, 8)
                XCTAssertEqual(restarted.epoch, "phone-install")
            }
        }
    }

    func testCorruptPhoneSnapshotStartsFreshFailClosedEpoch() {
        let restarted = AppRadioSilencePhoneMirrorPersistence
            .restoreForProcessRestart(
                snapshotData: Data("corrupt".utf8),
                legacy: .init(
                    isEnforced: true,
                    revision: 99,
                    epoch: "partial-writes"
                ),
                sharedStateIsEnforced: true,
                makeEpoch: { "replacement-epoch" }
            )

        XCTAssertTrue(restarted.isEnforced)
        XCTAssertEqual(restarted.revision, 0)
        XCTAssertEqual(restarted.epoch, "replacement-epoch")
    }

    func testCompletePhoneLegacyTupleMigratesThenAdvances() {
        let restarted = AppRadioSilencePhoneMirrorPersistence
            .restoreForProcessRestart(
                snapshotData: nil,
                legacy: .init(
                    isEnforced: true,
                    revision: 5,
                    epoch: "legacy-phone"
                ),
                sharedStateIsEnforced: false,
                makeEpoch: { "unexpected-new-epoch" }
            )

        XCTAssertFalse(restarted.isEnforced)
        XCTAssertEqual(restarted.revision, 6)
        XCTAssertEqual(restarted.epoch, "legacy-phone")
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

        let priorPhoneState = AppRadioSilencePhoneMirrorState(
            isEnforced: false,
            revision: 7,
            epoch: "phone-install"
        )
        let phoneData = try! AppRadioSilencePhoneMirrorPersistence.encode(priorPhoneState)
        let restartedPhoneState = AppRadioSilencePhoneMirrorPersistence
            .restoreForProcessRestart(
                snapshotData: phoneData,
                sharedStateIsEnforced: false,
                makeEpoch: { "unexpected-new-epoch" }
            )
        precondition(!restartedPhoneState.isEnforced)
        precondition(restartedPhoneState.revision == 8)
        precondition(restartedPhoneState.epoch == "phone-install")

        let recoveredPhoneState = AppRadioSilencePhoneMirrorPersistence
            .restoreForProcessRestart(
                snapshotData: Data("corrupt".utf8),
                legacy: .init(
                    isEnforced: true,
                    revision: 99,
                    epoch: "partial-writes"
                ),
                sharedStateIsEnforced: true,
                makeEpoch: { "replacement-epoch" }
            )
        precondition(recoveredPhoneState.isEnforced)
        precondition(recoveredPhoneState.revision == 0)
        precondition(recoveredPhoneState.epoch == "replacement-epoch")
    }
}
#endif
