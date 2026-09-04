import Foundation

@main
enum VerifyIOSMapFamilyTransition {
    static func main() {
        var state = EusoTripMapFamilyTransitionState(activeFamily: .operational)
        let terrain = state.request(.terrain)
        require(state.activeFamily == .operational, "request changed active family before commit")
        require(state.pendingFamily == .terrain, "request did not enter pending state")

        let navigation = state.request(.navigation)
        require(!state.commit(.terrain, requestID: terrain), "stale request committed")
        require(state.activeFamily == .operational, "stale commit changed active family")
        state.synchronizeActive(.terrain)
        require(state.activeFamily == .operational, "shared preference displaced a pending request")
        require(state.commit(.navigation, requestID: navigation), "latest request did not commit")
        require(state.activeFamily == .navigation, "committed family is not active")

        let failedTerrain = state.request(.terrain)
        require(
            state.fail(
                .terrain,
                requestID: failedTerrain,
                message: " Map family could not be prepared. "
            ),
            "latest failure was not accepted"
        )
        require(state.activeFamily == .navigation, "failure replaced the retained active family")
        require(state.failedFamily == .terrain, "failure did not expose a retry target")
        require(
            state.failureMessage == "Map family could not be prepared.",
            "failure message was not normalized"
        )
        state.synchronizeActive(.operational)
        require(state.activeFamily == .operational, "settled shared preference was not adopted")
        require(state.failedFamily == nil, "shared preference left a stale retry warning")

        let retry = state.request(.terrain)
        require(retry > failedTerrain, "retry did not advance request identity")
        require(state.commit(.terrain, requestID: retry), "retry did not commit")
        require(state.activeFamily == .terrain, "retried family is not active")

        print("PASS: map-family requests commit transactionally, stale callbacks are ignored, and failures retain a retryable active map")
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else { fatalError(message) }
    }
}
