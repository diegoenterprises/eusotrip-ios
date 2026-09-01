import XCTest
@testable import EusoTrip

final class HereFiniteCallbackWatchdogTests: XCTestCase {
    private struct TimeoutFailure: Error, Equatable {}

    func testFirstNativeResultWinsAndLateResultIsIgnored() async throws {
        let watchdog = HereFiniteCallbackWatchdog<Int>(
            timeout: 1,
            timeoutFailure: { TimeoutFailure() }
        )

        XCTAssertTrue(watchdog.succeed(41))
        XCTAssertFalse(watchdog.succeed(99))
        let value = try await watchdog.wait()

        XCTAssertEqual(value, 41)
    }

    func testTimeoutInterruptsNativeOperationAndRejectsLateCallback() async {
        let interrupted = expectation(description: "native operation interrupted")
        let watchdog = HereFiniteCallbackWatchdog<Int>(
            timeout: 0.02,
            timeoutFailure: { TimeoutFailure() }
        )

        do {
            _ = try await watchdog.wait {
                interrupted.fulfill()
            }
            XCTFail("Expected the callback watchdog to time out.")
        } catch {
            XCTAssertEqual(error as? TimeoutFailure, TimeoutFailure())
        }

        await fulfillment(of: [interrupted], timeout: 1)
        XCTAssertFalse(watchdog.succeed(7))
    }

    func testTaskCancellationInterruptsNativeOperationExactlyOnce() async {
        let interrupted = expectation(description: "native operation interrupted once")
        interrupted.expectedFulfillmentCount = 1
        let watchdog = HereFiniteCallbackWatchdog<Int>(
            timeout: 1,
            timeoutFailure: { TimeoutFailure() }
        )

        let task = Task {
            try await watchdog.wait {
                interrupted.fulfill()
            }
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        await fulfillment(of: [interrupted], timeout: 1)
        XCTAssertFalse(watchdog.fail(TimeoutFailure()))
    }

    func testInterruptionBeforeWaitStillCancelsNativeOperationExactlyOnce() async {
        let interrupted = expectation(description: "native operation interrupted once")
        interrupted.expectedFulfillmentCount = 1
        let watchdog = HereFiniteCallbackWatchdog<Int>(
            timeout: 1,
            timeoutFailure: { TimeoutFailure() }
        )

        XCTAssertTrue(watchdog.interrupt())
        do {
            _ = try await watchdog.wait {
                interrupted.fulfill()
            }
            XCTFail("Expected cancellation.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        await fulfillment(of: [interrupted], timeout: 1)
        XCTAssertFalse(watchdog.interrupt())
    }

    func testInvalidTimeoutFailsClosedAndInterruptsNativeOperation() async {
        let interrupted = expectation(description: "invalid timeout interrupts native operation")
        let watchdog = HereFiniteCallbackWatchdog<Int>(
            timeout: .nan,
            timeoutFailure: { TimeoutFailure() }
        )

        do {
            _ = try await watchdog.wait {
                interrupted.fulfill()
            }
            XCTFail("Expected invalid timeout configuration to fail closed.")
        } catch {
            XCTAssertEqual(error as? TimeoutFailure, TimeoutFailure())
        }

        await fulfillment(of: [interrupted], timeout: 1)
        XCTAssertFalse(watchdog.succeed(1))
    }

    func testSuspendedTimeoutDoesNotExpireUntilResumed() async throws {
        let watchdog = HereFiniteCallbackWatchdog<Int>(
            timeout: 0.04,
            timeoutFailure: { TimeoutFailure() }
        )
        watchdog.suspendTimeout()

        let task = Task { try await watchdog.wait() }
        try await Task.sleep(for: .milliseconds(80))
        watchdog.resumeTimeout()
        XCTAssertTrue(watchdog.succeed(12))

        let value = try await task.value
        XCTAssertEqual(value, 12)
    }

    func testHeartbeatExtendsInactivityDeadline() async throws {
        let watchdog = HereFiniteCallbackWatchdog<Int>(
            timeout: 0.05,
            timeoutFailure: { TimeoutFailure() }
        )

        let task = Task { try await watchdog.wait() }
        try await Task.sleep(for: .milliseconds(30))
        watchdog.heartbeat()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(watchdog.succeed(23))

        let value = try await task.value
        XCTAssertEqual(value, 23)
    }
}
