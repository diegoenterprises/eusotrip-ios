//
//  AppRadioSilenceSharedState.swift
//  EusoTrip
//
//  Atomic, fail-closed policy propagation for app-owned processes that do
//  not share the main app's in-memory coordinator (App Intents and future
//  extensions). The file lives in the already-entitled EusoTrip app group.
//

import Foundation

enum AppRadioSilenceSharedState {
    static let applicationGroupIdentifier = "group.com.app.eusotrip"

    private static let fileName = "app-radio-silence-v1.state"
    private static let enforcedPayload = Data("EUSOTRIP_APP_RADIO_SILENCE_V1:ENFORCED\n".utf8)
    private static let releasedPayload = Data("EUSOTRIP_APP_RADIO_SILENCE_V1:RELEASED\n".utf8)

    /// Missing, unreadable, or malformed state is enforced. That makes an
    /// App Intent which races the first main-app launch fail closed instead
    /// of becoming an ungoverned network client.
    static var isEnforced: Bool {
        guard let url = stateFileURL,
              let payload = try? Data(contentsOf: url) else {
            return true
        }
        if payload == releasedPayload { return false }
        return true
    }

    /// Called once on the first true foreground activation of a cold main-app
    /// process. A prior process crash may have left an ENFORCED marker; real
    /// foreground activation proves that no earlier process-local offline
    /// journey still owns the UI. Background push, WatchConnectivity, and
    /// App Intent wakes must never call this method.
    @discardableResult
    static func prepareMainAppLaunch() -> Bool {
        setEnforced(false)
    }

    /// Atomically replace the fixed-format marker. An enforced write that
    /// fails attempts to remove the old marker: absence decodes as enforced.
    /// A release failure leaves the old enforced marker in place.
    @discardableResult
    static func setEnforced(_ enforced: Bool) -> Bool {
        // No container URL means this process cannot prove that another
        // app-owned process will observe the requested edge. Keep native
        // readiness closed for both ENFORCED and RELEASED transitions.
        guard let url = stateFileURL else { return false }
        let payload = enforced ? enforcedPayload : releasedPayload
        do {
            try payload.write(to: url, options: .atomic)
        } catch {
            if enforced {
                try? FileManager.default.removeItem(at: url)
            }
        }
        return isEnforced == enforced
    }

    private static var stateFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: applicationGroupIdentifier)?
            .appendingPathComponent(fileName, isDirectory: false)
    }
}
