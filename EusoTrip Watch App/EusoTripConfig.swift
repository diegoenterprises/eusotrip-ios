//
//  EusoTripConfig.swift
//  EusoTrip Watch App
//
//  Central config. The iOS companion app points at the Azure App Service
//  host; the watch must match so auth tokens minted on the phone remain
//  valid server-side.
//

import Foundation

enum EusoTripConfig {
    /// Base URL of the EusoTrip server. Must match the iOS app's
    /// `EusoTripAPI.baseURL`. Trailing slash matters so we can
    /// `appendingPathComponent("api/trpc")` cleanly.
    static let apiBaseURL: String = "https://eusotrip-app.azurewebsites.net/"

    /// Handoff activity type — must be declared in both iOS and watchOS
    /// Info.plist under `NSUserActivityTypes`.
    static let handoffActivityType = "com.eusotrip.esang.activate"

    /// Local-notification category id used by the iOS app to surface
    /// the "Open Esang" action on the iPhone.
    static let esangNotificationCategory = "ESANG_ACTIVATE"

    /// Siri / App Intents shortcut phrases.
    static let askEsangPhrase = "Ask Esang"
    static let emergencyPhrase = "Esang SOS"

    /// ERG (Emergency Response Guidebook) bundled database filename.
    /// Ships with the watch so HazMat lookups work offline.
    static let ergDatabaseFilename = "erg2024.json"

    /// Offline-queue storage file under the watch's group container.
    static let offlineQueueFilename = "esang-offline-queue.json"

    /// Minimum battery % below which the watch enters ultra-low-power
    /// mode (reduces voice to text-only replies, drops complications to
    /// 1 refresh/hour).
    static let ultraLowPowerThreshold: Double = 0.10

    /// Complication refresh cadence (seconds) when on wall power / in
    /// driving session.
    static let complicationRefreshSeconds: TimeInterval = 60 * 5
}
