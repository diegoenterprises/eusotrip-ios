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

    @Test func inboxContinuationCarriesTheExactConversationIdentity() {
        let payload = PhoneActivationRequest(
            destination: .messages,
            transcript: "open conversation thread-42",
            reply: "Opening this conversation on your iPhone.",
            beginListening: false,
            autoSubmit: false,
            conversationId: "thread-42"
        ).payload()

        #expect(payload["destination"] as? String == "messages")
        #expect(payload["conversationId"] as? String == "thread-42")
        #expect(payload["beginListening"] as? Bool == false)
        #expect(payload["autoSubmit"] as? Bool == false)
    }

    @Test func walletContinuationTargetsEusoWalletWithoutVoiceInference() {
        let payload = PhoneActivationRequest(
            destination: .wallet,
            transcript: "",
            reply: "Review EusoWallet on your iPhone.",
            beginListening: false,
            autoSubmit: false
        ).payload()

        #expect(payload["destination"] as? String == "wallet")
        #expect(payload["transcript"] as? String == "")
        #expect(payload["beginListening"] as? Bool == false)
        #expect(payload["autoSubmit"] as? Bool == false)
    }

    @Test func safetyCoachContinuationTargetsTheNativePhoneSurface() {
        let payload = PhoneActivationRequest(
            destination: .safetyCoach,
            transcript: "",
            reply: "Review Safety Coach evidence on your iPhone.",
            beginListening: false,
            autoSubmit: false
        ).payload()

        #expect(payload["destination"] as? String == "safetyCoach")
        #expect(payload["transcript"] as? String == "")
        #expect(payload["beginListening"] as? Bool == false)
        #expect(payload["autoSubmit"] as? Bool == false)
    }

    @Test @MainActor func safetyCoachEvidenceClearsWhenIdentityChanges() {
        let store = WristSafetyCoachStore()
        #if targetEnvironment(simulator)
        store.installVisualQA(mode: "safety-active")
        #expect(store.evidence != nil)
        #expect(!store.items.isEmpty)
        #endif

        store.resetForIdentity("another-user")
        #expect(store.boundUserId == "another-user")
        #expect(store.evidence == nil)
        #expect(store.items.isEmpty)
        #expect(!store.hasLoadedOnce)
    }

    @Test @MainActor func walletTimestampsStayUnknownWhenEvidenceIsMissing() {
        #expect(WalletStore.parseTimestamp(nil) == nil)
        #expect(WalletStore.parseTimestamp("") == nil)
        #expect(WalletStore.parseTimestamp("not-a-timestamp") == nil)
        #expect(WalletStore.parseTimestamp("2026-08-31") != nil)
    }

    @Test @MainActor func walletEntryDirectionUsesLedgerSemantics() {
        #expect(WatchWalletEntryFlow.resolve(type: "earnings", amount: 1900) == .incoming)
        #expect(WatchWalletEntryFlow.resolve(type: "payout", amount: 850) == .outgoing)
        #expect(WatchWalletEntryFlow.resolve(type: "adjustment", amount: -42) == .outgoing)
        #expect(WatchWalletEntryFlow.resolve(type: nil, amount: nil) == .neutral)
    }

    @Test @MainActor func walletEvidenceClearsWhenIdentityChanges() {
        let store = WalletStore()
        #if targetEnvironment(simulator)
        store.installVisualQA(mode: "wallet-active")
        #expect(store.balance != nil)
        #expect(!store.recent.isEmpty)
        #endif

        store.resetForIdentity("another-user")
        #expect(store.boundUserId == "another-user")
        #expect(store.balance == nil)
        #expect(store.recent.isEmpty)
        #expect(!store.hasLoadedBalance)
        #expect(!store.hasLoadedActivity)
    }

    @Test func phoneZeroUnreadRemainsAuthoritativeOverOlderServerRows() {
        let phoneAt = Date(timeIntervalSince1970: 1_800_000_010)
        var evidence = InboxUnreadEvidence(userId: "user-a")

        let acceptedPhone = evidence.applyPhone(
            total: 0,
            map: [:],
            userId: "user-a",
            observedAt: phoneAt
        )
        let acceptedServer = evidence.applyServer(
            map: ["thread-stale": 4],
            userId: "user-a",
            observedAt: phoneAt.addingTimeInterval(-30)
        )

        #expect(acceptedPhone)
        #expect(!acceptedServer)
        #expect(evidence.total == 0)
        #expect(evidence.unread(for: "thread-stale", serverFallback: 4) == 0)
    }

    @Test func unreadEvidenceRejectsAnotherIdentity() {
        var evidence = InboxUnreadEvidence(userId: "user-a")
        let accepted = evidence.applyPhone(
            total: 7,
            map: ["thread-b": 7],
            userId: "user-b",
            observedAt: Date(timeIntervalSince1970: 1_800_000_020)
        )

        #expect(!accepted)
        #expect(evidence.userId == "user-a")
        #expect(evidence.total == 0)
        #expect(evidence.byConversation.isEmpty)
    }

    @Test @MainActor func missingOrMalformedMessageTimeStaysUnknown() {
        #expect(InboxStore.parseTimestamp(nil) == nil)
        #expect(InboxStore.parseTimestamp("") == nil)
        #expect(InboxStore.parseTimestamp("not-a-timestamp") == nil)
    }

    @Test @MainActor func inboxDeliveryQueuesOnlyRetryableOrAmbiguousFailures() {
        let offline = InboxDeliveryPolicy.shouldQueue(
            URLError(.notConnectedToInternet)
        )
        let unavailable = InboxDeliveryPolicy.shouldQueue(
            EsangError.server(status: 503, body: "")
        )
        let ambiguousReceipt = InboxDeliveryPolicy.shouldQueue(
            EsangError.decoding("missing receipt")
        )
        let forbidden = InboxDeliveryPolicy.shouldQueue(
            EsangError.server(status: 403, body: "")
        )
        let unauthorized = InboxDeliveryPolicy.shouldQueue(
            EsangError.unauthorized
        )

        #expect(offline)
        #expect(unavailable)
        #expect(ambiguousReceipt)
        #expect(!forbidden)
        #expect(!unauthorized)
    }

    @Test @MainActor func compactInboxAgePreservesConversationTitleSpace() {
        let now = Date(timeIntervalSince1970: 1_800_000_100)
        #expect(InboxStore.compactAge(now.addingTimeInterval(-45), at: now) == "NOW")
        #expect(InboxStore.compactAge(now.addingTimeInterval(-180), at: now) == "3M")
        #expect(InboxStore.compactAge(now.addingTimeInterval(-7_200), at: now) == "2H")
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
