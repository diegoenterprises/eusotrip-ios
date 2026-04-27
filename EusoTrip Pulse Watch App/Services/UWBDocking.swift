//
//  UWBDocking.swift
//  EusoTrip Pulse Watch App
//
//  Q3 2026 offline-mode tier — Ultra-Wideband cab + trailer docking.
//
//  Apple Watch Series 6+ and Ultra 2 ship with a U1 / U2 Ultra-Wideband
//  chip. Combined with Nearby Interaction, we can measure centimeter-
//  accurate distance + direction to any other U1/U2-equipped device —
//  including the phone in the driver's pocket, a trailer-mounted
//  Apple beacon, or a paired watch worn by a dockhand.
//
//  Use cases:
//    • Trailer coupling — warn the driver when the fifth wheel is 12"
//      from the kingpin so they don't slam it.
//    • Dock backing — guide the last 25 feet with haptic ticks that
//      speed up as the distance closes.
//    • Dockhand handoff — confirm the right warehouse employee is the
//      one signing the POD by UWB proximity, not a spoofed QR code.
//
//  This scaffold exposes session lifecycle + a Combine publisher. The
//  full NIDiscoveryToken exchange runs via WatchConnectivity so the
//  phone + watch can jointly maintain a session with a third device.
//

import Foundation
import Combine
import WatchKit
#if canImport(NearbyInteraction)
import NearbyInteraction
#endif

enum UWBDockingState: Equatable {
    case unsupported
    case idle
    /// Local NISession is live and has a discovery token, but we
    /// haven't received the peer's token yet. The UI shows "pairing".
    case awaitingPeer
    case discovering
    case ranging(distanceMeters: Float, bearingDegrees: Float?)
    case handoff(recipient: String)
    case error(String)
}

/// What kind of dock/coupling the ranging session is guiding. The
/// threshold bands + haptic cadences differ per kind (a kingpin bite
/// wants tighter bands than a 53' dock back-in).
enum UWBDockingScenario: String, Codable {
    case trailerCoupling    // fifth-wheel → kingpin
    case dockBackin         // trailer → warehouse dock bumper
    case dockhandHandoff    // wrist → dockhand wrist/phone for POD signer
}

@MainActor
final class UWBDocking: NSObject, ObservableObject {
    static let shared = UWBDocking()

    @Published private(set) var state: UWBDockingState = .idle
    @Published private(set) var lastDistance: Float = 0   // meters
    @Published private(set) var lastUpdate: Date?
    /// Base64 of our local discovery token, published so the view layer
    /// can show the ready indicator and so the WCSession forwarder can
    /// copy the bytes up to the phone after the session comes up.
    @Published private(set) var localTokenB64: String?
    /// The scenario the current session is ranging for. Drives the
    /// threshold bands + haptic cadence curve.
    @Published private(set) var scenario: UWBDockingScenario = .trailerCoupling

    #if canImport(NearbyInteraction)
    private var session: NISession?
    #endif

    /// Haptic tick driver — wakes at whatever cadence
    /// `hapticCadenceSeconds()` reports and plays a WatchKit haptic so
    /// the driver doesn't have to look at their wrist during the last
    /// few feet of a dock back-in.
    private var hapticTimer: Timer?

    override init() {
        super.init()
        #if canImport(NearbyInteraction)
        if !NISession.deviceCapabilities.supportsPreciseDistanceMeasurement {
            state = .unsupported
        }
        #else
        state = .unsupported
        #endif
    }

    // MARK: - Session lifecycle

    /// Bring up a local NISession, publish the local discovery token so
    /// the phone can ferry it to the counterparty, and park in
    /// `.awaitingPeer` until the matching token comes back the other
    /// direction. Safe to call when the flag is off or the device lacks
    /// a U1/U2 chip — both paths are no-ops that keep the state machine
    /// from entering an invalid configuration.
    func beginDiscovery(scenario: UWBDockingScenario) {
        guard EusoTripConfig.uwbDockingEnabled else { return }
        #if canImport(NearbyInteraction)
        guard state != .unsupported else { return }
        // If we already have a live session in a good state, only swap
        // the scenario; don't re-create — a rebuilt session would churn
        // the peer token and invalidate whatever the phone just ferried.
        self.scenario = scenario
        if session == nil {
            let s = NISession()
            s.delegate = self
            self.session = s
        }
        if let token = session?.discoveryToken,
           let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            let b64 = data.base64EncodedString()
            localTokenB64 = b64
            // Fire-and-forget: the phone is the relay, so missed ferries
            // are recovered by the driver re-opening the Coach View.
            WatchConnectivityManager.shared.forwardUWBLocalToken(
                tokenB64: b64,
                scenario: scenario.rawValue
            )
        } else {
            localTokenB64 = nil
        }
        if case .ranging = state {
            // Already ranging — keep the state.
        } else {
            state = .awaitingPeer
        }
        #endif
    }

    /// Start a ranging session with a peer token received from the
    /// iOS companion via WatchConnectivity. The token is exchanged out-
    /// of-band before we arrive here.
    func beginRanging(peerTokenData: Data) {
        guard EusoTripConfig.uwbDockingEnabled else { return }
        #if canImport(NearbyInteraction)
        guard state != .unsupported else { return }
        do {
            // Re-use the local session if `beginDiscovery` already
            // spun one up — re-creating would invalidate the local
            // token the phone has already ferried to the peer.
            if session == nil {
                let s = NISession()
                s.delegate = self
                self.session = s
            }
            let token = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: NIDiscoveryToken.self,
                from: peerTokenData
            )
            guard let token else { state = .error("bad token"); return }
            let config = NINearbyPeerConfiguration(peerToken: token)
            session?.run(config)
            state = .discovering
            startHapticTicker()
        } catch {
            state = .error(error.localizedDescription)
        }
        #endif
    }

    /// Convenience used by WatchConnectivityManager when a `uwb.peerToken`
    /// message arrives base64-encoded.
    func beginRanging(peerTokenB64: String, scenario: UWBDockingScenario? = nil) {
        if let scenario { self.scenario = scenario }
        guard let data = Data(base64Encoded: peerTokenB64) else {
            state = .error("bad base64 token")
            return
        }
        beginRanging(peerTokenData: data)
    }

    func endRanging() {
        #if canImport(NearbyInteraction)
        session?.invalidate()
        session = nil
        #endif
        localTokenB64 = nil
        stopHapticTicker()
        state = .idle
    }

    /// Mark a completed dockhand handoff (POD signer proximity verified).
    /// Logs to the audit chain so the chain-of-custody is unforgeable,
    /// then collapses the session.
    func completeHandoff(recipient: String) {
        if EusoTripConfig.blockchainAuditEnabled {
            BlockchainAudit.shared.append(
                kind: .hazmatHandoff,
                payload: [
                    "scenario": scenario.rawValue,
                    "recipient": recipient,
                    "distance": String(format: "%.2f", lastDistance)
                ]
            )
        }
        state = .handoff(recipient: recipient)
        WKInterfaceDevice.current().play(.success)
        stopHapticTicker()
    }

    // MARK: - Haptic guidance

    /// Convert the live distance reading into haptic-guidance cadence.
    /// Scenario-aware: a kingpin bite wants tighter banding than a
    /// 53' trailer backing into a 120' dock lane.
    func hapticCadenceSeconds() -> TimeInterval? {
        guard case .ranging(let d, _) = state else { return nil }
        switch scenario {
        case .trailerCoupling:
            // Fifth-wheel → kingpin. The driver is creeping backwards
            // inches at a time under mirror guidance; tight bands so
            // haptic cadence tracks kingpin distance precisely.
            if d <= 0.15 { return 0.05 }   // effectively continuous
            if d <= 0.40 { return 0.15 }
            if d <= 1.0  { return 0.35 }
            if d <= 2.5  { return 0.9 }
            return nil
        case .dockBackin:
            // 53' trailer into a warehouse dock. Wider bands — we
            // start coaching at 5m because mirror blind spots at that
            // distance are where most dock bumps happen.
            if d <= 0.3  { return 0.1 }
            if d <= 1.0  { return 0.25 }
            if d <= 3.0  { return 1.0 }
            if d <= 5.0  { return 2.0 }
            return nil
        case .dockhandHandoff:
            // No continuous coaching — just a single tick when the
            // dockhand is within arm's length so the driver knows
            // the POD signer is actually the right person.
            if d <= 0.6 { return 1.5 }
            return nil
        }
    }

    private func startHapticTicker() {
        stopHapticTicker()
        // Reschedules every tick so the cadence adapts as distance
        // changes. The 0.05s floor in `hapticCadenceSeconds` keeps us
        // out of runaway-timer territory.
        scheduleNextHaptic()
    }

    private func scheduleNextHaptic() {
        guard let interval = hapticCadenceSeconds() else { return }
        hapticTimer?.invalidate()
        hapticTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // `.click` is the tightest watch haptic and doesn't
                // push a notification card, which is exactly the feel
                // we want for a distance ticker.
                WKInterfaceDevice.current().play(.click)
                self.scheduleNextHaptic()
            }
        }
    }

    private func stopHapticTicker() {
        hapticTimer?.invalidate()
        hapticTimer = nil
    }
}

#if canImport(NearbyInteraction)
extension UWBDocking: NISessionDelegate {
    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let obj = nearbyObjects.first, let distance = obj.distance else { return }
        Task { @MainActor in
            self.lastDistance = distance
            self.lastUpdate = Date()
            let bearing = obj.direction.map { Float(atan2($0.x, -$0.z) * 180 / .pi) }
            self.state = .ranging(distanceMeters: distance, bearingDegrees: bearing)
        }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        Task { @MainActor in
            self.state = .error(error.localizedDescription)
            self.stopHapticTicker()
        }
    }
}
#endif
