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

}
