//
//  EusoTrip_Pulse_Watch_AppTests.swift
//  EusoTrip Pulse Watch AppTests
//
//  Created by Diego Usoro on 4/20/26.
//

import Foundation
import Testing
@testable import EusoTrip_Pulse_Watch_App

struct EusoTrip_Pulse_Watch_AppTests {

    @Test func esangActivationCarriesAnExplicitContinuationContract() {
        let instant = Date(timeIntervalSince1970: 1_800_000_000)
        let payload = PhoneActivationRequest(
            destination: .esang,
            transcript: "Where is my next pickup?",
            reply: "Continue with ESANG on your iPhone.",
            beginListening: false,
            autoSubmit: true
        ).payload(at: instant)

        #expect(payload["op"] as? String == "esang.activate")
        #expect(payload["destination"] as? String == "esang")
        #expect(payload["transcript"] as? String == "Where is my next pickup?")
        #expect(payload["beginListening"] as? Bool == false)
        #expect(payload["autoSubmit"] as? Bool == true)
        #expect(payload["ts"] as? TimeInterval == instant.timeIntervalSince1970)
    }

    @Test func watchOrbFallbackRequestsForegroundVoiceOnlyAfterHandoff() {
        let payload = PhoneActivationRequest(
            destination: .esang,
            transcript: "",
            reply: "Continue with ESANG on your iPhone.",
            beginListening: true,
            autoSubmit: false
        ).payload()

        #expect(payload["destination"] as? String == "esang")
        #expect(payload["transcript"] as? String == "")
        #expect(payload["beginListening"] as? Bool == true)
        #expect(payload["autoSubmit"] as? Bool == false)
    }

    @Test func hosRecoveryTargetsThePhoneHOSSurfaceWithoutStartingVoice() {
        let payload = PhoneActivationRequest(
            destination: .hos,
            transcript: "",
            reply: "Review and synchronize HOS evidence in EusoTrip.",
            beginListening: false,
            autoSubmit: false
        ).payload()

        #expect(payload["destination"] as? String == "hos")
        #expect(payload["beginListening"] as? Bool == false)
        #expect(payload["autoSubmit"] as? Bool == false)
    }

    @Test func routeDirectionsTargetMapsWithoutVoiceFallback() {
        let payload = PhoneActivationRequest(
            destination: .maps,
            transcript: "navigate to Dallas, TX",
            reply: "Opening driving directions on your iPhone.",
            beginListening: false,
            autoSubmit: false
        ).payload()

        #expect(payload["destination"] as? String == "maps")
        #expect(payload["transcript"] as? String == "navigate to Dallas, TX")
        #expect(payload["beginListening"] as? Bool == false)
        #expect(payload["autoSubmit"] as? Bool == false)
    }

    @Test func routeEvidenceCannotCrossLoadIdentity() {
        let receivedAt = Date(timeIntervalSince1970: 1_800_000_050)
        let loadA = RouteProgressPayload(
            etaMinutes: 95,
            milesRemaining: 72,
            nextWaypoint: "Dallas, TX",
            weatherFlag: "wind-advisory"
        )
        var evidence = RouteProgressEvidence()

        evidence.begin(loadId: "load-a", signedIn: true)
        let acceptedLoadA = evidence.applyProgress(loadA, for: "load-a", receivedAt: receivedAt)
        #expect(acceptedLoadA)
        #expect(evidence.etaMinutes == 95)

        evidence.begin(loadId: "load-b", signedIn: true)
        #expect(evidence.loadId == "load-b")
        #expect(evidence.etaMinutes == nil)
        #expect(evidence.nextWaypoint == nil)
        #expect(evidence.weatherFlag == nil)
        let rejectedStaleLoadA = evidence.applyProgress(loadA, for: "load-a", receivedAt: receivedAt)
        #expect(!rejectedStaleLoadA)
        #expect(evidence.etaMinutes == nil)
    }

    @Test func routeServerNullsClearPriorValuesForTheSameLoad() {
        let receivedAt = Date(timeIntervalSince1970: 1_800_000_060)
        var evidence = RouteProgressEvidence(loadId: "load-a", phase: .loading)
        let complete = RouteProgressPayload(
            etaMinutes: 30,
            milesRemaining: 18,
            nextWaypoint: "Waco, TX",
            weatherFlag: nil
        )
        let missing = RouteProgressPayload(
            etaMinutes: nil,
            milesRemaining: nil,
            nextWaypoint: nil,
            weatherFlag: nil
        )

        let acceptedComplete = evidence.applyProgress(complete, for: "load-a", receivedAt: receivedAt)
        #expect(acceptedComplete)
        #expect(evidence.hasRouteValues)
        let acceptedMissing = evidence.applyProgress(
            missing,
            for: "load-a",
            receivedAt: receivedAt.addingTimeInterval(30)
        )
        #expect(acceptedMissing)
        #expect(!evidence.hasRouteValues)
        #expect(evidence.etaMinutes == nil)
        #expect(evidence.nextWaypoint == nil)
    }

    @Test func emergencyRelayCarriesStableIdentityAndSilentContract() {
        let instant = Date(timeIntervalSince1970: 1_800_000_100)
        let payload = EmergencyPhoneRelayRequest(
            eventId: "pulse-event-42",
            reason: "duress phrase",
            silent: true,
            coordinate: (41.8781, -87.6298)
        ).payload(at: instant)

        #expect(payload["op"] as? String == "esang.sos")
        #expect(payload["eventId"] as? String == "pulse-event-42")
        #expect(payload["reason"] as? String == "duress phrase")
        #expect(payload["silent"] as? Bool == true)
        #expect(payload["lat"] as? Double == 41.8781)
        #expect(payload["lon"] as? Double == -87.6298)
        #expect(payload["ts"] as? TimeInterval == instant.timeIntervalSince1970)
    }

    @Test func emergencyRelayOmitsInvalidCoordinates() {
        let payload = EmergencyPhoneRelayRequest(
            eventId: "pulse-event-invalid-location",
            reason: "manual",
            silent: false,
            coordinate: (200, -87.6298)
        ).payload()

        #expect(payload["lat"] == nil)
        #expect(payload["lon"] == nil)
        #expect(payload["silent"] as? Bool == false)
    }

    @Test func directEmergencyInputCarriesEventEvidenceWithoutInventingLocation() {
        let input = EmergencyController.declareEmergencyInput(
            eventId: "pulse-event-direct",
            reason: "medical emergency",
            silent: false,
            lat: nil,
            lon: nil,
            at: Date(timeIntervalSince1970: 1_800_000_200)
        )

        #expect(input["type"] as? String == "medical")
        #expect((input["description"] as? String)?.contains("pulse-event-direct") == true)
        #expect(input["latitude"] == nil)
        #expect(input["longitude"] == nil)
    }

    @Test func hosClockRequiresCurrentSourcedEvidence() {
        let now = Date(timeIntervalSince1970: 1_800_000_300)
        let current = WatchHOS(
            status: .driving,
            driveRemainingMinutes: 315,
            windowRemainingMinutes: 480,
            cycleRemainingMinutes: 2_700,
            statusSince: now.addingTimeInterval(-900),
            tracked: true,
            source: "eld.fused",
            observedAt: now.addingTimeInterval(-60)
        )

        #expect(current.hasCurrentObservation(at: now))

        var unsourced = current
        unsourced.source = "  "
        #expect(!unsourced.hasCurrentObservation(at: now))

        var untracked = current
        untracked.tracked = false
        #expect(!untracked.hasCurrentObservation(at: now))
    }

    @Test func hosClockRejectsStaleEvidence() {
        let now = Date(timeIntervalSince1970: 1_800_000_400)
        let stale = WatchHOS(
            status: .onDuty,
            driveRemainingMinutes: 240,
            windowRemainingMinutes: 360,
            cycleRemainingMinutes: 2_400,
            statusSince: now.addingTimeInterval(-3_600),
            tracked: true,
            source: "server",
            observedAt: now.addingTimeInterval(-(16 * 60))
        )

        #expect(!stale.hasCurrentObservation(at: now))
    }

    @Test @MainActor func hosDutyStatusUsesCanonicalServerVocabulary() {
        #expect(HOSStore.serverDutyStatus(HOSStatus.off.rawValue) == "off_duty")
        #expect(HOSStore.serverDutyStatus(HOSStatus.sleeper.rawValue) == "sleeper")
        #expect(HOSStore.serverDutyStatus(HOSStatus.driving.rawValue) == "driving")
        #expect(HOSStore.serverDutyStatus(HOSStatus.onDuty.rawValue) == "on_duty")
    }

}
