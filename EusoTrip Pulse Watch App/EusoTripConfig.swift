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

    // MARK: - Q2 2026 Offline-Mode Feature Flags (OFFLINE_MODE_STRATEGY)
    //
    // All default to `true` — these are the Q2 tier landing. Set any of
    // them to `false` to disable the corresponding subsystem at launch
    // (useful for bisecting a regression without an Xcode rebuild).

    /// F01 — Unified Outbox with Priority Lanes (SOS > HOS > Load > Voice > Message).
    static let unifiedOutboxEnabled = true

    /// F02 — Tunnel-Aware ETA (IMU dead-reckoning while GNSS is lost).
    static let tunnelAwareETAEnabled = true

    /// F03 — Satellite SMS fallback (Globalstar / Starlink D2C / inReach).
    static let satelliteFallbackEnabled = true

    /// F02b — Dead-Zone Coast. Pairs with TunnelAwareETA but broader:
    /// any time GNSS has been stale > 60s *regardless* of whether we
    /// think we're in a known tunnel, maintain a breadcrumb-grade
    /// coasted position for dispatch visibility + trigger the
    /// terrestrial-loss satellite flow. No-op when off.
    static let deadZoneCoastEnabled = true

    /// F04 — Voice Dispatch offline grammar (local intent resolution).
    static let voiceDispatchOfflineEnabled = true

    /// F05 — HOS clock swap via updateApplicationContext (1-second tick).
    static let hosClockSwapEnabled = true

    // MARK: - Q3/Q4 2026 Offline-Mode Feature Flags
    //
    // These are scaffolded-but-opt-in. They compile in; they don't run
    // until their flag flips. Production ships with them `false` until
    // the full implementation lands and is validated on-device.

    /// Q3 — CoreBluetooth / LoRa mesh relay for SOS + HOS forwarding
    /// through nearby EusoTrip-paired peers.
    static let meshRelayEnabled = false

    /// Q3 — U1/U2 Ultra-Wideband docking + trailer-coupling guidance.
    static let uwbDockingEnabled = false

    /// Q3 — Per-field vector-clock LWW CRDT for HOS + load state sync.
    static let fleetCRDTEnabled = false

    /// Q4 — Hash-chained local audit log + periodic server anchor.
    static let blockchainAuditEnabled = false

    /// F06 — Offline ETA from learned route history. Ships as a runtime-
    /// only EWMA estimator today; the full Create ML tabular regressor
    /// swaps in behind this same flag in a later drop.
    static let learnedRouteETAEnabled = true

    /// F10 — ELD-Fused Precision ETA. When the phone is actively paired
    /// with the truck ECM, wheel-tick velocity (J1939 SPN 84) is forwarded
    /// over WatchConnectivity and fused into tunnel-mode dead reckoning.
    /// Falls back to GPS-derived speed when the ECM is not connected.
    static let eldFusedPrecisionEnabled = true

    /// F13 — Convoy coordination. Uses MeshRelay peer discovery to cluster
    /// trucks traveling the same route into a logical convoy for shared
    /// SOS fanout, synchronized ETAs, and leader-elected rolling-buddy
    /// stops. Convoy LOGIC runs regardless of transport; when
    /// `meshRelayEnabled` is also on, the physical BLE layer powers peer
    /// discovery. Otherwise the coordinator runs in "phantom convoy"
    /// mode — happy to form a convoy with a peer forwarded by the iOS
    /// companion over WCSession, which is how most production convoys
    /// will actually bootstrap (phone has the larger BLE radio + already
    /// maintains the peer registry).
    static let convoyEnabled = false

    /// F13 — Require all convoy envelopes to carry a valid P-256 signature
    /// against a pinned or presented public key. Fail-closed: unsigned or
    /// mis-signed envelopes are dropped before reaching the coordinator.
    /// Leave on in production; flip off only for isolation-testing the
    /// coordinator state machine without the crypto layer interfering.
    static let convoySignatureRequired = true

    /// F14 — Pulse Keep-Alive Navigation Session. Runs a dedicated
    /// HKWorkoutSession-backed surface so turn-by-turn cues continue
    /// firing on the wrist across the full haul, even when the paired
    /// iPhone is backgrounded or out of reach. Consumes live location
    /// from DrivingSessionManager (same shared CLLocation pump as F02
    /// and F06) so there's no second GPS pipeline — the nav layer
    /// annotates the existing stream with maneuver-distance haptics.
    static let keepAliveNavigationEnabled = true

    /// F15 — On-device BOL + placard copilot. The iOS companion owns
    /// the camera (VisionKit `DataScannerViewController` + Foundation
    /// Models for structured-field extraction). The watch is a
    /// result-viewer + voice trigger surface: "Esang, scan the placard"
    /// launches the camera on the phone and the parsed result fans back
    /// to the wrist for driver confirmation + discrepancy flags.
    static let bolCopilotEnabled = true

    /// F16 — Wrist-to-terminal Proximity Handoff (BLE advertising).
    /// Driver taps "Handoff" and the wrist advertises a short-lived
    /// BLE beacon carrying driver id + active load displayId + an
    /// HMAC-signed envelope. A paired iPhone, a dock kiosk, or a
    /// dispatcher's wrist can pick up the context without scanning a
    /// QR code or typing the load number. Defaults to on: the service
    /// only transmits while `isBroadcasting == true`, so there's no
    /// always-on battery cost.
    static let proximityHandoffEnabled = true

    /// F16 — Length of time (seconds) a single Proximity Handoff
    /// advertisement stays live before auto-stopping. 60s is long
    /// enough for a dockhand to walk over + scan, short enough that an
    /// unattended wrist doesn't leak context into the parking lot.
    static let proximityHandoffWindowSeconds: TimeInterval = 60
}
