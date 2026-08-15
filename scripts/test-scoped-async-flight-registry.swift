import Foundation

@MainActor
private final class FlightProbe {
    var starts = 0
    var cancellations = 0
}

@main
private struct ScopedAsyncFlightRegistryTest {
    @MainActor
    static func main() async {
        await verifyIndependentWaiterDeadlines()
        await verifyKeyIsolation()
        await verifyFinalWaiterCancellation()
        print("ScopedAsyncFlightRegistry timing tests passed (3/3)")
    }

    @MainActor
    private static func verifyIndependentWaiterDeadlines() async {
        let registry = ScopedAsyncFlightRegistry<String, Int>()
        let probe = FlightProbe()
        let clock = ContinuousClock()
        let wallStart = Date()

        let first = Task { @MainActor in
            await registry.value(
                for: "same-flight",
                deadline: clock.now.advanced(by: .milliseconds(100)),
                timeoutValue: -1
            ) {
                probe.starts += 1
                do {
                    try await Task.sleep(for: .milliseconds(400))
                    return 42
                } catch {
                    probe.cancellations += 1
                    return -2
                }
            }
        }

        try? await Task.sleep(for: .milliseconds(20))
        let second = Task { @MainActor in
            await registry.value(
                for: "same-flight",
                deadline: clock.now.advanced(by: .seconds(1)),
                timeoutValue: -1
            ) {
                fatalError("A coalesced waiter started a duplicate provider")
            }
        }

        let firstValue = await first.value
        let firstElapsed = Date().timeIntervalSince(wallStart)
        precondition(firstValue == -1, "First waiter did not return its timeout value")
        precondition(firstElapsed < 0.28, "First waiter did not return near its 100 ms ceiling")
        precondition(probe.cancellations == 0, "Provider cancelled while a second waiter remained")

        let secondValue = await second.value
        precondition(secondValue == 42, "Second waiter did not receive the shared provider result")
        precondition(probe.starts == 1, "Identical keys did not coalesce to one provider")
        precondition(probe.cancellations == 0, "Completed shared provider was unexpectedly cancelled")
    }

    @MainActor
    private static func verifyKeyIsolation() async {
        let registry = ScopedAsyncFlightRegistry<String, Int>()
        let clock = ContinuousClock()
        let first = Task { @MainActor in
            await registry.value(
                for: "tenant-a|location-a",
                deadline: clock.now.advanced(by: .seconds(1)),
                timeoutValue: -1
            ) {
                try? await Task.sleep(for: .milliseconds(30))
                return 11
            }
        }
        let second = Task { @MainActor in
            await registry.value(
                for: "tenant-b|location-b",
                deadline: clock.now.advanced(by: .seconds(1)),
                timeoutValue: -1
            ) {
                try? await Task.sleep(for: .milliseconds(30))
                return 22
            }
        }
        let values = await (first.value, second.value)
        precondition(values.0 == 11 && values.1 == 22, "Distinct keys coalesced across isolation boundaries")
    }

    @MainActor
    private static func verifyFinalWaiterCancellation() async {
        let registry = ScopedAsyncFlightRegistry<String, Int>()
        let probe = FlightProbe()
        let clock = ContinuousClock()

        let waiter = Task { @MainActor in
            await registry.value(
                for: "last-waiter",
                deadline: clock.now.advanced(by: .milliseconds(100)),
                timeoutValue: -1
            ) {
                probe.starts += 1
                do {
                    try await Task.sleep(for: .seconds(5))
                    return 7
                } catch {
                    probe.cancellations += 1
                    return -2
                }
            }
        }

        let value = await waiter.value
        precondition(value == -1, "Final waiter did not return at its deadline")
        try? await Task.sleep(for: .milliseconds(40))
        precondition(probe.starts == 1, "Final-waiter provider never started")
        precondition(probe.cancellations == 1, "Provider was not cancelled after its final waiter left")
        precondition(registry.activeFlightCount == 0, "Cancelled provider remained joinable")
    }
}
