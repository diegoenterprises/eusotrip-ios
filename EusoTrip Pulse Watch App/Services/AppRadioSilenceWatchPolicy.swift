//
//  AppRadioSilenceWatchPolicy.swift
//  EusoTrip Pulse Watch App
//
//  Fail-closed gate for app-initiated watchOS traffic while the paired phone
//  owns a fully offline journey. WCSession delivers only policy state; direct
//  HTTP and durable outbox replay are stopped locally in the watch process.
//

import Foundation

enum AppRadioSilenceWatchTransportError: Error, LocalizedError, Equatable, Sendable {
    case enforced

    var errorDescription: String? {
        "Network access is paused while the offline journey is active."
    }
}

@MainActor
final class AppRadioSilenceWatchPolicy {
    static let shared = AppRadioSilenceWatchPolicy()

    private static let snapshotDefaultsKey = "watch_app_radio_silence_snapshot_v2"
    private static let enforcedDefaultsKey = "watch_app_radio_silence_enforced_v1"
    private static let revisionDefaultsKey = "watch_app_radio_silence_revision_v1"
    private static let epochDefaultsKey = "watch_app_radio_silence_epoch_v1"
    private static let retiredEpochsDefaultsKey = "watch_app_radio_silence_retired_epochs_v1"

    private var state: AppRadioSilenceWatchState
    private let defaults: UserDefaults
    private var sessions: [UUID: URLSession] = [:]

    var isEnforced: Bool { state.isEnforced }
    var revision: Int { state.revision }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let legacy = AppRadioSilenceWatchLegacyState(
            isEnforced: defaults.object(forKey: Self.enforcedDefaultsKey) as? Bool,
            revision: (defaults.object(forKey: Self.revisionDefaultsKey) as? NSNumber)?.intValue,
            epoch: defaults.string(forKey: Self.epochDefaultsKey),
            retiredEpochs: defaults.stringArray(forKey: Self.retiredEpochsDefaultsKey)
        )
        state = AppRadioSilenceWatchPersistence.restore(
            snapshotData: defaults.data(forKey: Self.snapshotDefaultsKey),
            legacy: legacy
        )
        persistState()
    }

    /// Apply before any other mirrored channel. The state flips to enforced
    /// before task cancellation, closing the race where a cancellation callback
    /// could otherwise start a replacement request.
    func apply(enforced: Bool, revision: Int, epoch: String) {
        let transition = state.apply(
            enforced: enforced,
            revision: revision,
            epoch: epoch
        )
        guard transition != .stale else { return }

        persistState()

        if state.isEnforced {
            OfflineQueue.shared.suspendForAppRadioSilence()
            let active = Array(sessions.values)
            sessions.removeAll()
            for session in active { session.invalidateAndCancel() }
        } else {
            OfflineQueue.shared.resumeAfterAppRadioSilence()
        }
    }

    /// Re-apply the persisted fail-closed state during cold launch, before any
    /// reachability or scene-phase hook is allowed to drain the outbox.
    func bootstrap() {
        guard state.isEnforced else { return }
        OfflineQueue.shared.suspendForAppRadioSilence()
        let active = Array(sessions.values)
        sessions.removeAll()
        for session in active { session.invalidateAndCancel() }
    }

    func requireTransportAllowed() throws {
        guard !state.isEnforced else {
            throw AppRadioSilenceWatchTransportError.enforced
        }
    }

    private func persistState() {
        guard let data = try? AppRadioSilenceWatchPersistence.encode(state) else {
            // Encoding failure must never reopen transport. Replace both the
            // in-memory and persisted values with the valid closed default.
            state = AppRadioSilenceWatchState()
            if let failClosedData = try? AppRadioSilenceWatchPersistence.encode(state) {
                defaults.set(failClosedData, forKey: Self.snapshotDefaultsKey)
            }
            return
        }
        defaults.set(data, forKey: Self.snapshotDefaultsKey)
    }

    nonisolated private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    func data(for original: URLRequest) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        try requireTransportAllowed()

        var request = original
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-store, no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")

        let session = Self.makeSession()
        let registration = UUID()
        sessions[registration] = session
        defer {
            sessions[registration] = nil
            session.invalidateAndCancel()
        }

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            if state.isEnforced {
                throw AppRadioSilenceWatchTransportError.enforced
            }
            throw error
        }

        try Task.checkCancellation()
        try requireTransportAllowed()
        return result
    }
}
