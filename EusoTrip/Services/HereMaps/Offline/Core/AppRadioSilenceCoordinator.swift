//
//  AppRadioSilenceCoordinator.swift
//  EusoTrip
//
//  A bounded, reference-counted lease that prevents app-initiated network
//  traffic while a fully offline journey owns the screen. This policy does
//  not and cannot disable OS-managed radios or APNs delivery; it stops the
//  application's transports and upload/replay producers.
//

import Foundation

extension Notification.Name {
    /// Synchronously posted only after the coordinator and API transport gate
    /// are enforced. Consumers with direct transports (for example WKWebView)
    /// must dispose/cancel them before returning from this notification.
    static let eusoAppRadioSilenceWillEngage = Notification.Name("eusoAppRadioSilenceWillEngage")

    /// Posted after the final lease releases and the central transport gate is
    /// open again. No lease identifiers or reasons are included in userInfo.
    static let eusoAppRadioSilenceDidRelease = Notification.Name("eusoAppRadioSilenceDidRelease")
}

@MainActor
final class AppRadioSilenceCoordinator {
    static let shared = AppRadioSilenceCoordinator()

    /// Fixed reasons avoid turning diagnostics or user-provided text into
    /// policy metadata. The reason is intentionally never logged or posted.
    enum Reason: Sendable {
        case offlineRoadJourney
        case offlineMapLibrary
    }

    private(set) var isEnforced = false
    var activeLeaseCount: Int { state.activeLeaseCount }

    private var state = AppRadioSilenceLeaseState()

    private init() {}

    /// Acquire synchronously on the main actor. On the first lease, the state
    /// and central API gate are both closed before any notification or service
    /// cancellation can re-enter application code.
    @discardableResult
    func acquire(reason: Reason) -> AppRadioSilenceLease {
        _ = reason
        let result = state.acquire()
        guard result.transition == .firstLease else { return result.lease }

        isEnforced = true
        EusoTripAPI.shared.setAppRadioSilenceEnforced(true)

        OfflineQueue.shared.suspendForAppRadioSilence()
        RealtimeService.shared.suspendForAppRadioSilence()
        DriverGPSPushService.shared.suspendForAppRadioSilence()
        HOSClockService.shared.suspendForAppRadioSilence()
        ReminderSyncService.shared.suspendForAppRadioSilence()
        GeofenceService.shared.suspendForAppRadioSilence()

        NotificationCenter.default.post(name: .eusoAppRadioSilenceWillEngage, object: nil)

        return result.lease
    }

    /// Release one ownership token. Duplicate/foreign releases are no-ops;
    /// producers resume only after the final valid owner releases.
    func release(_ lease: AppRadioSilenceLease) {
        guard state.release(lease) == .finalLeaseReleased else { return }

        isEnforced = false
        EusoTripAPI.shared.setAppRadioSilenceEnforced(false)

        GeofenceService.shared.resumeAfterAppRadioSilence()
        DriverGPSPushService.shared.resumeAfterAppRadioSilence()
        RealtimeService.shared.resumeAfterAppRadioSilence()
        HOSClockService.shared.resumeAfterAppRadioSilence()
        ReminderSyncService.shared.resumeAfterAppRadioSilence()
        OfflineQueue.shared.resumeAfterAppRadioSilence()

        NotificationCenter.default.post(name: .eusoAppRadioSilenceDidRelease, object: nil)
    }
}
