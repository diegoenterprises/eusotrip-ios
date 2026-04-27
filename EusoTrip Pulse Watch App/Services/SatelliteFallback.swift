//
//  SatelliteFallback.swift
//  EusoTrip Pulse Watch App
//
//  F03 — Satellite SMS fallback (Q2 2026 offline-mode tier).
//
//  When all cellular + WiFi paths are dead, the paired iPhone may still
//  have a satellite link (T-Mobile D2C Starlink, Apple Emergency SOS via
//  Globalstar, or a Garmin inReach-style BLE pairing). This controller
//  surfaces the decision tree:
//
//     1. Determine which satellite channels are actually reachable
//        right now (queried from the phone via WCSession).
//     2. Offer the driver the narrowest useful payload (location + HOS
//        + load-id), not a full sync — sat bandwidth is pennies/byte.
//     3. Confirm with the user before sending (these channels are
//        billed + some are emergency-only).
//     4. Hand the payload to the OfflineQueue so even if the sat link
//        drops mid-send, the retry contract is the same.
//
//  This is the scaffold: API surface + a lightweight reachability
//  heuristic. The actual phone-side `satellite.probe` handler lands in
//  a follow-up iOS change.
//

import Foundation
import Combine
import Network
#if canImport(CoreLocation)
import CoreLocation
#endif

enum SatelliteChannel: String, Codable, CaseIterable {
    case globalstarEmergency = "globalstar_emergency"
    case tmobileStarlinkD2C   = "tmobile_starlink_d2c"
    case iridiumInReach       = "iridium_inreach"

    var displayName: String {
        switch self {
        case .globalstarEmergency: return "Apple Emergency SOS"
        case .tmobileStarlinkD2C:  return "T-Mobile Satellite"
        case .iridiumInReach:      return "Garmin inReach"
        }
    }

    /// Max bytes per message this channel can carry.
    var maxPayloadBytes: Int {
        switch self {
        case .globalstarEmergency: return 160
        case .tmobileStarlinkD2C:  return 240
        case .iridiumInReach:      return 160
        }
    }

    /// Whether the channel is life-safety-only (not for routine use).
    var emergencyOnly: Bool {
        self == .globalstarEmergency
    }
}

@MainActor
final class SatelliteFallback: ObservableObject {
    static let shared = SatelliteFallback()

    @Published private(set) var available: [SatelliteChannel] = []
    @Published private(set) var lastProbeAt: Date?
    /// True when terrestrial data (cellular or WiFi) has been unavailable
    /// for `terrestrialLossThresholdSeconds`. UI reads this to render
    /// the "Use your phone's satellite connection" card (Group 3, F03).
    @Published private(set) var terrestrialDown: Bool = false
    /// Dispatch shortcode the phone wants us to prefix/route to. Tenant-
    /// configurable via `tenant_branding.satelliteShortcode` on the phone;
    /// we cache it after the probe so `composeSOS` can pre-pend it when
    /// the chosen channel is SMS (T-Mobile D2C / inReach), skipping it on
    /// `globalstarEmergency` (which is always "911" on the phone side).
    @Published private(set) var dispatchShortcode: String = "#EUSODISPATCH"

    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.eusotrip.sat.path")
    private var terrestrialLostAt: Date?
    private var dwellTimer: Timer?
    private var monitorStarted: Bool = false
    /// Cached connectivity ref so the NWPath closure doesn't need to
    /// capture a @MainActor class across a @Sendable boundary (Swift 6
    /// would reject that). Set on `startMonitoring(connectivity:)`.
    private weak var connectivityRef: WatchConnectivityManager?
    /// Strategy doc threshold: "no terrestrial data for N minutes." We
    /// use 3 minutes as the initial default — long enough to cover a
    /// typical tunnel or cellular handoff, short enough that a real
    /// dead zone gets flagged before the driver is frustrated.
    private let terrestrialLossThresholdSeconds: TimeInterval = 180

    /// Start observing network path changes. Idempotent — safe to call
    /// from EusoTripWatchApp.onAppear even if already running.
    func startMonitoring(connectivity: WatchConnectivityManager) {
        guard EusoTripConfig.satelliteFallbackEnabled else { return }
        self.connectivityRef = connectivity
        // Only start the NWPathMonitor once.
        guard !monitorStarted else { return }
        monitorStarted = true
        pathMonitor.pathUpdateHandler = { path in
            // Snapshot the two flags we care about on the monitor's own
            // queue (they're @Sendable primitives). The MainActor hop
            // below then uses only those — no non-Sendable capture.
            let satisfied = path.status == .satisfied
            let cell = path.usesInterfaceType(.cellular)
            let wifi = path.usesInterfaceType(.wifi)
            Task { @MainActor in
                SatelliteFallback.shared.handlePathUpdate(
                    terrestrialAvailable: satisfied && (cell || wifi)
                )
            }
        }
        pathMonitor.start(queue: monitorQueue)

        // F02b hook: when Dead-Zone Coast escalates (GNSS silent for
        // > 5 min), trip the same `terrestrialDown` banner and kick
        // off a probe. The two triggers (network loss, GNSS loss) are
        // distinct but the UX is identical — "your phone is your
        // only link right now, tap to check satellite."
        NotificationCenter.default.addObserver(
            forName: .deadZoneSatelliteEscalation,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                let fallback = SatelliteFallback.shared
                fallback.terrestrialDown = true
                if let conn = fallback.connectivityRef {
                    await fallback.probe(connectivity: conn)
                }
            }
        }
    }

    private func handlePathUpdate(terrestrialAvailable: Bool) {
        if terrestrialAvailable {
            // Clear the loss state + the stale "sat needed" flag.
            terrestrialLostAt = nil
            dwellTimer?.invalidate()
            dwellTimer = nil
            if terrestrialDown { terrestrialDown = false }
        } else if terrestrialLostAt == nil {
            // First moment of loss — start a dwell timer. If the path
            // doesn't recover before the threshold, trip terrestrialDown
            // and fire a probe.
            terrestrialLostAt = Date()
            dwellTimer?.invalidate()
            dwellTimer = Timer.scheduledTimer(
                withTimeInterval: terrestrialLossThresholdSeconds,
                repeats: false
            ) { _ in
                Task { @MainActor in
                    let fallback = SatelliteFallback.shared
                    guard fallback.terrestrialLostAt != nil else { return }
                    fallback.terrestrialDown = true
                    if let conn = fallback.connectivityRef {
                        await fallback.probe(connectivity: conn)
                    }
                }
            }
        }
    }

    /// Ask the phone which sat channels it can currently reach. The
    /// phone replies with a short ack message after polling its own
    /// carrier flags + the system emergency framework.
    ///
    /// Round-trip contract (see `SatellitePhoneBridge.handleProbe`):
    ///   request  : `{op: "satellite.probe", ts: <epoch>}`
    ///   response : `{ok: true, channels: [String], shortcode: String}`
    /// Channel rawValues mirror this enum's cases. If the phone is
    /// unreachable (common on the wrist — cellular is out on both ends),
    /// fall back to the Globalstar-only conservative default so the
    /// driver still sees *some* escalation option on the "dead-zone"
    /// card. iPhone 14+ always exposes Emergency SOS via Globalstar
    /// regardless of our bridge, so surfacing it is never a lie.
    func probe(connectivity: WatchConnectivityManager) async {
        lastProbeAt = Date()
        let (raw, shortcode) = await connectivity.probeSatelliteChannels()
        dispatchShortcode = shortcode
        if raw.isEmpty {
            // Phone didn't answer (offline, peer not reachable, or timed
            // out). Conservative fallback: offer Globalstar emergency
            // only, which is the one channel that works without any
            // phone-side cooperation from our app code.
            available = [.globalstarEmergency]
            return
        }
        available = raw.compactMap { SatelliteChannel(rawValue: $0) }
        // If compactMap dropped everything (phone sent only unknown
        // channel IDs — forward-compat safety), keep the conservative
        // default rather than leaving the list empty.
        if available.isEmpty {
            available = [.globalstarEmergency]
        }
    }

    /// Craft the smallest useful SOS payload for a given channel.
    /// Returns a byte-capped string suitable for the satellite link.
    func composeSOS(
        channel: SatelliteChannel,
        reason: String,
        coordinate: (Double, Double)?,
        loadId: String?,
        driverId: String?
    ) -> String {
        var parts: [String] = []
        parts.append("EUSO SOS")
        if let c = coordinate {
            parts.append(String(format: "%.4f,%.4f", c.0, c.1))
        }
        if let loadId, !loadId.isEmpty { parts.append("L:\(loadId)") }
        if let driverId, !driverId.isEmpty { parts.append("D:\(driverId)") }
        let reasonTrimmed = reason.prefix(40)
        parts.append(String(reasonTrimmed))
        let composed = parts.joined(separator: " | ")
        if composed.utf8.count <= channel.maxPayloadBytes { return composed }
        return String(composed.prefix(channel.maxPayloadBytes))
    }

    /// Fire the SOS through the chosen channel. Returns true on
    /// accepted handoff (not delivery — the satellite confirms later).
    func sendSOS(
        channel: SatelliteChannel,
        payload: String,
        reason: String = "driver-initiated",
        connectivity: WatchConnectivityManager
    ) async -> Bool {
        // Watch can't open a satellite link directly; it asks the phone.
        // The phone routes to the right system sheet (Emergency SOS or
        // Messages-via-satellite) or invokes the Iridium BLE pairing.
        //
        // Primary path: sendMessage → SatellitePhoneBridge.handleSend →
        //   phone presents MFMessageComposeViewController (SMS channels)
        //   or opens `tel://911` (Globalstar emergency). Wrist gets an
        //   ack dict `{ok: true, recipient: "..."}`.
        //
        // Even on success we STILL enqueue to OfflineQueue — that's the
        // audit log the backend ingests on reconnect so dispatch can
        // prove what was sent + when. If the phone wasn't reachable,
        // `sendSatelliteSOS` falls back to `transferUserInfo`, which
        // iOS will deliver when the phone is woken — our reply/result
        // just tells us whether the immediate handoff succeeded.
        let handoffAccepted = await connectivity.sendSatelliteSOS(
            channel: channel.rawValue,
            payload: payload,
            reason: reason
        )
        OfflineQueue.shared.enqueueMessage(
            loadId: nil,
            to: "satellite:\(channel.rawValue)",
            text: payload
        )
        return handoffAccepted
    }
}
