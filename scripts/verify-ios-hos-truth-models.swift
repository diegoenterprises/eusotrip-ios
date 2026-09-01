import Foundation

private func decodeStatus(_ json: String) throws -> HOSStatus {
    try JSONDecoder().decode(HOSStatus.self, from: Data(json.utf8))
}

@main
private struct IOSHOSTruthModels {
    static func main() throws {
        let now = ISO8601DateFormatter().date(from: "2026-08-24T12:00:00Z")!

        let untracked = try decodeStatus(#"{"trackingState":"not_tracked","tracked":false}"#)
        precondition(untracked.drivingRemaining == nil)
        precondition(untracked.status == nil)
        precondition(untracked.drivingRemainingDisplay == "\u{2014}")
        precondition(untracked.assignmentEligibility(now: now) == .notTracked)

        let stale = try decodeStatus(#"""
        {
          "trackingState":"tracked","tracked":true,"source":"motive",
          "freshness":"2026-08-24T11:30:00Z","status":"off_duty",
          "drivingRemaining":11,"onDutyRemaining":14,"cycleRemaining":70,
          "breakRequired":false,"canDrive":true,"canAcceptLoad":true
        }
        """#)
        precondition(stale.assignmentEligibility(now: now) == .stale)

        let missingBreak = try decodeStatus(#"""
        {
          "trackingState":"tracked","tracked":true,"source":"samsara",
          "freshness":"2026-08-24T11:55:00Z","status":"on_duty",
          "drivingRemaining":8.5,"onDutyRemaining":10,"cycleRemaining":42,
          "canDrive":true,"canAcceptLoad":true
        }
        """#)
        precondition(missingBreak.assignmentEligibility(now: now) == .breakEvidenceUnavailable)

        let unknownDuty = try decodeStatus(#"""
        {
          "trackingState":"tracked","tracked":true,"source":"geotab",
          "freshness":"2026-08-24T11:55:00Z","status":"provider_new_state",
          "drivingRemaining":8.5,"onDutyRemaining":10,"cycleRemaining":42,
          "breakRequired":false,"canDrive":true,"canAcceptLoad":true
        }
        """#)
        precondition(unknownDuty.assignmentEligibility(now: now) == .statusUnavailable)

        let current = try decodeStatus(#"""
        {
          "trackingState":"tracked","tracked":true,"source":"geotab",
          "freshness":"2026-08-24T11:55:00Z","status":"on_duty",
          "drivingRemaining":8.5,"onDutyRemaining":10,"cycleRemaining":42,
          "breakRequired":false,"canDrive":true,"canAcceptLoad":true
        }
        """#)
        precondition(current.hasCurrentObservation(now: now))
        precondition(current.assignmentEligibility(now: now) == .eligible)

        let hours = try JSONDecoder().decode(
            HOSHoursAvailable.self,
            from: Data(#"{"driving":null,"onDuty":6,"cycle":22}"#.utf8)
        )
        precondition(hours.drivingRemaining == nil)
        precondition(hours.onDutyRemaining == 6)

        print("iOS HOS truth models verified: null preservation, freshness, status, break, and fail-closed assignment.")
    }
}
