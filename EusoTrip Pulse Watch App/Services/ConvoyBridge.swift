//
//  ConvoyBridge.swift
//  EusoTrip Pulse Watch App
//
//  Transport adapter that bolts `ConvoyCoordinator` onto the live
//  transports — MeshRelay (watch-to-watch BLE) and WatchConnectivity
//  (watch-to-phone, phone forwards to other trucks over cellular).
//
//  Why this lives in its own file rather than inside the coordinator:
//  the coordinator's whole design is to stay transport-agnostic so it
//  can be unit-tested in isolation and its policy (formation,
//  divergence, leader election) stays pure. The bridge is the thin
//  impure piece that knows about the actual wires.
//
//  Lifecycle: `start()` is called from `EusoTripWatchApp` once the
//  convoy feature is enabled. It subscribes to the coordinator's
//  `outbound` publisher and forwards each envelope to both transports
//  in a best-effort fan-out. Either transport accepting the envelope
//  counts as a successful send from the coordinator's perspective.
//

import Foundation
import Combine

@MainActor
final class ConvoyBridge {
    static let shared = ConvoyBridge()

    private var subscription: AnyCancellable?
    private var isStarted = false

    /// Start forwarding coordinator envelopes. Idempotent; second + Nth
    /// calls are no-ops so the startup task can call it without the
    /// coordination overhead of a "did we already start" dance.
    func start() {
        guard EusoTripConfig.convoyEnabled else { return }
        guard !isStarted else { return }
        isStarted = true

        subscription = ConvoyCoordinator.shared.outbound
            .sink { envelope in
                Task { @MainActor in
                    Self.dispatch(envelope: envelope)
                }
            }
    }

    func stop() {
        subscription?.cancel()
        subscription = nil
        isStarted = false
    }

    // MARK: - Dispatch

    /// Fan-out strategy:
    ///   1. Try the watch's own BLE mesh first — lowest-latency, and
    ///      guaranteed to reach peers that are physically alongside us
    ///      (the common convoy topology on a 4-truck haul down I-35).
    ///   2. Hand the same envelope to the phone companion. The phone
    ///      batches + forwards via cellular when its radio is live,
    ///      which is how convoys spread across >100m separation.
    ///
    /// The two transports are independent — one failing doesn't
    /// prevent the other. Over cellular, the server de-dupes on the
    /// envelope id before fanning out to other convoy members'
    /// phones.
    private static func dispatch(envelope: ConvoyEnvelope) {
        // 1) Watch BLE (best-effort).
        if EusoTripConfig.meshRelayEnabled {
            Task { @MainActor in
                _ = await MeshRelay.shared.forwardConvoyEnvelope(
                    envelope,
                    originDriverId: envelope.fromDriverId
                )
            }
        }

        // 2) Phone companion (best-effort). Two complementary paths:
        //
        //    a. Direct WCSession: when the phone is reachable we hand
        //       the envelope straight over as `op: "convoy.envelope"`.
        //       This is the low-latency path — the phone decodes and
        //       POSTs to the backend's `convoy.relay` endpoint within
        //       a frame, so envelopes reach other trucks' phones over
        //       cellular within the ~200ms WCSession round-trip.
        //
        //    b. Unified Outbox message lane: durable fallback for the
        //       case where the phone is asleep, out of range, or the
        //       direct sendMessage fails silently. The offline queue
        //       will POST messaging.send with the envelope base64'd
        //       into the text field on the next flush, which is how
        //       the wrist spreads convoy state when the phone never
        //       activates during a trip.
        //
        //    SOS gets a third path — the SOS lane of the unified
        //    outbox — because the phone's SOS endpoint is the one
        //    that actually dials E911 and posts the emergency. For
        //    SOS we deliberately fan out to ALL THREE surfaces: mesh
        //    (step 1 above), direct WCSession (a), AND the SOS lane
        //    (c). Duplicated alerting on an actual emergency is the
        //    right failure mode.
        guard let payload = try? JSONEncoder().encode(envelope) else { return }

        // 2a — direct, low-latency.
        WatchConnectivityManager.shared.sendConvoyEnvelope(payload)

        // 2b / 2c — durable.
        let encoded = payload.base64EncodedString()
        switch envelope.kind {
        case .sos:
            let lat = Double(envelope.fields["lat"] ?? "")
            let lon = Double(envelope.fields["lon"] ?? "")
            OfflineQueue.shared.enqueueSOS(
                reason: "convoy:" + (envelope.fields["reason"] ?? "unknown"),
                lat: lat, lon: lon
            )
        default:
            OfflineQueue.shared.enqueueMessage(
                loadId: nil,
                to: "convoy",
                text: encoded
            )
        }
    }
}
