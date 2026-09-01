import Foundation

#if canImport(XCTest) && !APP_RADIO_SILENCE_WATCH_SOURCE_VERIFICATION
import XCTest
@testable import EusoTrip_Pulse_Watch_App

final class AppRadioSilenceWatchStateTests: XCTestCase {
    func testNewerEdgesEngageAndRelease() {
        var state = AppRadioSilenceWatchState()
        XCTAssertTrue(state.isEnforced)
        XCTAssertEqual(state.apply(enforced: false, revision: 0, epoch: "install-a"), .released)
        XCTAssertFalse(state.isEnforced)
        XCTAssertEqual(state.apply(enforced: true, revision: 1, epoch: "install-a"), .engaged)
        XCTAssertTrue(state.isEnforced)
        XCTAssertEqual(state.apply(enforced: false, revision: 2, epoch: "install-a"), .released)
        XCTAssertFalse(state.isEnforced)
    }

    func testStaleOrConflictingEdgesCannotReopenPolicy() {
        var state = AppRadioSilenceWatchState(
            isEnforced: true,
            revision: 8,
            epoch: "install-a"
        )
        XCTAssertEqual(state.apply(enforced: false, revision: 7, epoch: "install-a"), .stale)
        XCTAssertEqual(state.apply(enforced: false, revision: 8, epoch: "install-a"), .stale)
        XCTAssertTrue(state.isEnforced)
        XCTAssertEqual(state.apply(enforced: true, revision: 8, epoch: "install-a"), .unchanged)
    }

    func testNewInstallEpochReplacesOldButRetiredEpochCannotReturn() {
        var state = AppRadioSilenceWatchState(
            isEnforced: true,
            revision: 20,
            epoch: "install-a"
        )
        XCTAssertEqual(state.apply(enforced: false, revision: 0, epoch: "install-b"), .released)
        XCTAssertFalse(state.isEnforced)
        XCTAssertEqual(state.apply(enforced: true, revision: 21, epoch: "install-a"), .stale)
        XCTAssertFalse(state.isEnforced)
    }

    func testAtomicSnapshotRoundTripsTrustedState() throws {
        var state = AppRadioSilenceWatchState()
        XCTAssertEqual(state.apply(enforced: false, revision: 4, epoch: "install-a"), .released)

        let data = try AppRadioSilenceWatchPersistence.encode(state)

        XCTAssertEqual(
            AppRadioSilenceWatchPersistence.restore(snapshotData: data),
            state
        )
    }

    func testCorruptSnapshotFailsClosedWithoutLegacyFallback() {
        let legacy = AppRadioSilenceWatchLegacyState(
            isEnforced: false,
            revision: 50,
            epoch: "legacy-open",
            retiredEpochs: []
        )

        let restored = AppRadioSilenceWatchPersistence.restore(
            snapshotData: Data("corrupt".utf8),
            legacy: legacy
        )

        XCTAssertTrue(restored.isEnforced)
        XCTAssertNil(restored.epoch)
        XCTAssertEqual(restored.revision, 0)
    }

    func testPartialLegacyStateFailsClosed() {
        let restored = AppRadioSilenceWatchPersistence.restore(
            snapshotData: nil,
            legacy: .init(
                isEnforced: false,
                revision: nil,
                epoch: "partial",
                retiredEpochs: nil
            )
        )

        XCTAssertTrue(restored.isEnforced)
        XCTAssertNil(restored.epoch)
    }

    func testCompleteLegacyStateMigrates() {
        let restored = AppRadioSilenceWatchPersistence.restore(
            snapshotData: nil,
            legacy: .init(
                isEnforced: false,
                revision: 8,
                epoch: "legacy",
                retiredEpochs: ["retired"]
            )
        )

        XCTAssertFalse(restored.isEnforced)
        XCTAssertEqual(restored.revision, 8)
        XCTAssertEqual(restored.epoch, "legacy")
        XCTAssertEqual(restored.retiredEpochs, Set(["retired"]))
    }
}
#endif

#if APP_RADIO_SILENCE_WATCH_SOURCE_VERIFICATION
@main
enum AppRadioSilenceWatchStateSourceVerification {
    static func main() {
        var state = AppRadioSilenceWatchState()
        precondition(state.isEnforced)
        precondition(state.apply(enforced: false, revision: 0, epoch: "install-a") == .released)
        precondition(!state.isEnforced)
        precondition(state.apply(enforced: true, revision: 1, epoch: "install-a") == .engaged)
        precondition(state.isEnforced)
        precondition(state.apply(enforced: false, revision: 0, epoch: "install-a") == .stale)
        precondition(state.apply(enforced: false, revision: 1, epoch: "install-a") == .stale)
        precondition(state.isEnforced)
        precondition(state.apply(enforced: false, revision: 2, epoch: "install-a") == .released)
        precondition(!state.isEnforced)
        precondition(state.apply(enforced: true, revision: 1, epoch: "install-b") == .engaged)
        precondition(state.apply(enforced: false, revision: 99, epoch: "install-a") == .stale)
        precondition(state.isEnforced)
        precondition(state.apply(enforced: false, revision: 2, epoch: "install-b") == .released)
        precondition(!state.isEnforced)

        let encoded = try! AppRadioSilenceWatchPersistence.encode(state)
        precondition(AppRadioSilenceWatchPersistence.restore(snapshotData: encoded) == state)
        let openLegacy = AppRadioSilenceWatchLegacyState(
            isEnforced: false,
            revision: 50,
            epoch: "legacy-open",
            retiredEpochs: []
        )
        let corrupt = AppRadioSilenceWatchPersistence.restore(
            snapshotData: Data("corrupt".utf8),
            legacy: openLegacy
        )
        precondition(corrupt.isEnforced)
        precondition(corrupt.epoch == nil)
        let partial = AppRadioSilenceWatchPersistence.restore(
            snapshotData: nil,
            legacy: .init(
                isEnforced: false,
                revision: nil,
                epoch: "partial",
                retiredEpochs: nil
            )
        )
        precondition(partial.isEnforced)
        precondition(partial.epoch == nil)
    }
}
#endif
