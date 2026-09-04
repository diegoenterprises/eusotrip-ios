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
        state.synchronizePreference(.operational)
        require(state.activeFamily == .navigation, "shared preference bypassed renderer proof")
        require(state.pendingFamily == .operational, "shared preference was not requested")
        require(state.failedFamily == nil, "shared preference left a stale retry warning")
        require(state.commit(.operational, requestID: state.latestRequestID), "preference did not commit")

        let retry = state.request(.terrain)
        require(retry > failedTerrain, "retry did not advance request identity")
        require(state.commit(.terrain, requestID: retry), "retry did not commit")
        require(state.activeFamily == .terrain, "retried family is not active")

        var initial = EusoTripMapFamilyTransitionState(initialFamily: .operational)
        require(!initial.hasCommittedFamily, "initial renderer was reported active before readiness")
        require(initial.pendingFamily == .operational, "initial family was not pending")
        require(initial.fail(.operational, requestID: 0, message: "Unavailable"), "initial failure was ignored")
        require(!initial.hasCommittedFamily, "initial failure invented an active family")
        initial.synchronizePreference(.operational)
        require(initial.pendingFamily == .operational, "unavailable preference could not retry")
        require(initial.commit(.operational, requestID: initial.latestRequestID), "initial retry did not commit")
        require(initial.hasCommittedFamily, "successful initial retry is not active")

        let interrupted = initial.request(.navigation)
        initial.restartRenderer()
        require(!initial.hasCommittedFamily, "renderer restart retained stale proof")
        require(initial.pendingFamily == .navigation, "renderer restart lost the requested family")
        require(!initial.commit(.navigation, requestID: interrupted), "old renderer committed after restart")
        require(initial.commit(.navigation, requestID: initial.latestRequestID), "new renderer did not commit")
        let brokenRollback = initial.request(.terrain)
        require(initial.fail(.terrain, requestID: brokenRollback, message: "Unavailable", retainsActiveMap: false), "failed rollback was ignored")
        require(!initial.hasCommittedFamily, "failed rollback retained a false active label")
        require(!initial.commit(.terrain, requestID: brokenRollback), "failed request committed after settling")

        var bootstrap = EusoTripMapFamilyTransitionState(initialFamily: .operational)
        bootstrap.synchronizePreference(.terrain)
        require(bootstrap.pendingFamily == .terrain, "preference during bootstrap was dropped")
        require(!bootstrap.commit(.operational, requestID: 0), "bootstrap superseded the later preference")
        require(bootstrap.commit(.terrain, requestID: bootstrap.latestRequestID), "later bootstrap preference did not commit")

        var automatic = EusoTripMapFamilyTransitionState(activeFamily: .navigation)
        require(automatic.rendererBegan(.navigation, requestID: 0, retainedFamily: .navigation), "same-ID theme refresh was ignored")
        require(automatic.rendererBegan(.navigation, requestID: 0, retainedFamily: nil), "renderer loss was ignored")
        require(automatic.fail(.navigation, requestID: 0, message: "Unavailable", retainsActiveMap: false), "theme refresh failure was ignored")
        require(!automatic.hasCommittedFamily, "theme refresh failure left a false active map")

        var superseded = EusoTripMapFamilyTransitionState(activeFamily: .operational)
        let supersededRequest = superseded.request(.terrain)
        let newestRequest = superseded.request(.operational)
        require(!superseded.rendererBegan(.terrain, requestID: supersededRequest, retainedFamily: .terrain), "stale renderer changed the latest intent")
        require(superseded.rendererBegan(.operational, requestID: newestRequest, retainedFamily: .terrain), "retained renderer snapshot was rejected")
        require(superseded.fail(.operational, requestID: newestRequest, message: "Unavailable"), "latest failure rejected")
        require(superseded.activeFamily == .terrain && superseded.hasCommittedFamily, "failed latest request hid the actual retained family")

        let implicit = EusoTripMapFamilyPreference.resolve(explicitFamily: nil, persistedRawValue: "", activeJob: false, surfaceDefault: .operational)
        let explicit = EusoTripMapFamilyPreference.resolve(explicitFamily: .operational, persistedRawValue: "", activeJob: false, surfaceDefault: .operational)
        require(implicit != explicit, "explicit override must be observable even when the family is unchanged")

        print("PASS: initial readiness, shared preferences, retries, stale callbacks, renderer restarts, and failed rollback obey map-family truth")
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else { fatalError(message) }
    }
}
