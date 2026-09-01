import Foundation

@main
enum VerifyWatchHOSTruthModels {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        precondition(!WatchHOS.empty.hasCurrentObservation(at: now))

        let current = WatchHOS(
            status: .onDuty,
            driveRemainingMinutes: 420,
            windowRemainingMinutes: 600,
            cycleRemainingMinutes: 2_400,
            statusSince: now.addingTimeInterval(-300),
            tracked: true,
            source: "eld:motive",
            observedAt: now.addingTimeInterval(-300)
        )
        precondition(current.hasCurrentObservation(at: now))

        var stale = current
        stale.observedAt = now.addingTimeInterval(-(15 * 60 + 1))
        precondition(!stale.hasCurrentObservation(at: now))

        var futureDated = current
        futureDated.observedAt = now.addingTimeInterval(5 * 60 + 1)
        precondition(!futureDated.hasCurrentObservation(at: now))

        var sourceLess = current
        sourceLess.source = "  "
        precondition(!sourceLess.hasCurrentObservation(at: now))

        var untracked = current
        untracked.tracked = false
        precondition(!untracked.hasCurrentObservation(at: now))

        print("Watch HOS truth model verified.")
    }
}
