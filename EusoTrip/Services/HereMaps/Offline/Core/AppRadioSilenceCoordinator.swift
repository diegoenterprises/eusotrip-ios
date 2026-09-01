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
    /// Synchronously posted after this process's transport gates are closed.
    /// `AppRadioSilenceCoordinator.isEnforced` separately remains false if the
    /// cross-process marker could not be made fail-closed. Consumers with
    /// direct transports must dispose/cancel them before returning.
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

        // Publish before opening any native offline surface. Separate app-owned
        // processes re-read this atomic marker before each transport start.
        // Missing/corrupt state is enforced, so propagation fails closed. A
        // second immediate attempt heals the only unsafe failure shape: an old
        // RELEASE marker that could neither be atomically replaced nor removed.
        // Every nested acquire repeats the write, so it also retries a prior
        // propagation failure instead of inheriting an unproven readiness bit.
        var sharedEnforcementSucceeded = AppRadioSilenceSharedState.setEnforced(true)
        if !sharedEnforcementSucceeded {
            sharedEnforcementSucceeded = AppRadioSilenceSharedState.setEnforced(true)
        }

        if result.transition != .firstLease {
            isEnforced = sharedEnforcementSucceeded
            return result.lease
        }

        // Close this process even when cross-process propagation failed. The
        // public readiness bit remains false in that case, preventing native
        // offline surfaces from claiming full radio silence.
        isEnforced = sharedEnforcementSucceeded
        EusoTripAPI.shared.setAppRadioSilenceEnforced(true)
        WatchAuthBridge.shared.setAppRadioSilenceEnforced(true)

        OfflineQueue.shared.suspendForAppRadioSilence()
        RealtimeService.shared.suspendForAppRadioSilence()
        DriverGPSPushService.shared.suspendForAppRadioSilence()
        HOSClockService.shared.suspendForAppRadioSilence()
        GeofenceService.shared.suspendForAppRadioSilence()
        WeatherService.shared.suspendForAppRadioSilence()
        NewsOGImageCache.shared.suspendForAppRadioSilence()
        PTChannelManager.shared.suspendForAppRadioSilence()
        AppRadioSilenceDirectTransportController.shared.suspendAll()

        NotificationCenter.default.post(name: .eusoAppRadioSilenceWillEngage, object: nil)

        return result.lease
    }

    /// Release one ownership token. Duplicate/foreign releases are no-ops;
    /// producers resume only after the final valid owner releases.
    func release(_ lease: AppRadioSilenceLease) {
        guard state.release(lease) == .finalLeaseReleased else { return }

        // The shared marker is the cross-process authority. Do not publish a
        // phone/watch release or resume a transport until RELEASE is durable.
        // A write failure intentionally leaves this process closed; a later
        // true foreground relaunch can recover through prepareMainAppLaunch().
        guard AppRadioSilenceSharedState.setEnforced(false) else {
            isEnforced = true
            EusoTripAPI.shared.setAppRadioSilenceEnforced(true)
            WatchAuthBridge.shared.setAppRadioSilenceEnforced(true)
            return
        }

        isEnforced = false
        EusoTripAPI.shared.setAppRadioSilenceEnforced(false)
        WatchAuthBridge.shared.setAppRadioSilenceEnforced(false)

        GeofenceService.shared.resumeAfterAppRadioSilence()
        DriverGPSPushService.shared.resumeAfterAppRadioSilence()
        RealtimeService.shared.resumeAfterAppRadioSilence()
        HOSClockService.shared.resumeAfterAppRadioSilence()
        OfflineQueue.shared.resumeAfterAppRadioSilence()
        WeatherService.shared.resumeAfterAppRadioSilence()
        NewsOGImageCache.shared.resumeAfterAppRadioSilence()
        PTChannelManager.shared.resumeAfterAppRadioSilence()
        AppRadioSilenceDirectTransportController.shared.resumeAll()

        NotificationCenter.default.post(name: .eusoAppRadioSilenceDidRelease, object: nil)
    }

    /// Resolve an inherited marker exactly once on the first genuine
    /// foreground activation of a cold process. Background push,
    /// WatchConnectivity, and openAppWhenRun=false App Intent wakes never call
    /// this boundary. A live lease count makes the attempted recovery a no-op.
    @discardableResult
    func recoverSharedStateOnFirstForegroundActivation() -> Bool {
        guard state.activeLeaseCount == 0 else { return false }
        guard AppRadioSilenceSharedState.prepareMainAppLaunch() else {
            isEnforced = true
            EusoTripAPI.shared.setAppRadioSilenceEnforced(true)
            WatchAuthBridge.shared.setAppRadioSilenceEnforced(true)
            OfflineQueue.shared.suspendForAppRadioSilence()
            RealtimeService.shared.suspendForAppRadioSilence()
            DriverGPSPushService.shared.suspendForAppRadioSilence()
            HOSClockService.shared.suspendForAppRadioSilence()
            GeofenceService.shared.suspendForAppRadioSilence()
            WeatherService.shared.suspendForAppRadioSilence()
            NewsOGImageCache.shared.suspendForAppRadioSilence()
            PTChannelManager.shared.suspendForAppRadioSilence()
            AppRadioSilenceDirectTransportController.shared.suspendAll()
            return false
        }

        isEnforced = false
        EusoTripAPI.shared.setAppRadioSilenceEnforced(false)
        WatchAuthBridge.shared.setAppRadioSilenceEnforced(false)
        GeofenceService.shared.resumeAfterAppRadioSilence()
        DriverGPSPushService.shared.resumeAfterAppRadioSilence()
        RealtimeService.shared.resumeAfterAppRadioSilence()
        RealtimeService.shared.resumeAfterFirstForegroundRadioSilenceRelease()
        HOSClockService.shared.resumeAfterAppRadioSilence()
        OfflineQueue.shared.resumeAfterAppRadioSilence()
        WeatherService.shared.resumeAfterAppRadioSilence()
        NewsOGImageCache.shared.resumeAfterAppRadioSilence()
        PTChannelManager.shared.resumeAfterAppRadioSilence()
        AppRadioSilenceDirectTransportController.shared.resumeAll()
        NotificationCenter.default.post(name: .eusoAppRadioSilenceDidRelease, object: nil)
        return true
    }
}
