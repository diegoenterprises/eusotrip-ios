//
//  ConvoyPhoneBridge.swift
//  EusoTrip
//
//  F13 — iOS companion bridge for Convoy envelopes.
//
//  Mirrors the wrist's `ConvoyBridge` on the phone. Two directions:
//
//    1. Watch → Phone → Server (outbound).
//       The wrist sends an envelope via WCSession with op "convoy.envelope".
//       WatchCommandHandler routes it here; this bridge decodes the
//       base64 JSON, de-dupes on envelope id (so the wrist's mesh
//       fan-out can't double-post), and POSTs to `convoy.relay` on
//       the tRPC backend. The server is the one that actually fans
//       out to other trucks' phones over its own topic stream.
//
//    2. Server → Phone → Watch (inbound).
//       When the backend pushes a convoy envelope to this driver
//       (via the existing realtime socket channel), the phone turns
//       around and WCSession-fans-out to the wrist with op
//       "convoy.ingest". The wrist's WatchConnectivityManager picks
//       it up and calls `ConvoyCoordinator.shared.ingest(...)`, which
//       is where envelope verification + state mutation happens.
//
//  Dedup / idempotency:
//    A short rolling set of envelope ids keeps the "same envelope
//    looped back from the server" case from producing a second wrist
//    notification. We bound it at 256 entries with an LRU eviction
//    policy — more than enough for a busy convoy, small enough that
//    it fits comfortably in RAM on a backgrounded companion app.
//
//  Transport choice:
//    We send the envelope itself as a base64-encoded JSON string
//    rather than unpacking it into top-level WCSession keys, because
//    the envelope's signature field is a raw byte payload and
//    WCSession serializes through property-list encoding which gets
//    cute about Data. Base64 dodges the whole encoding layer.
//

import Foundation
import WatchConnectivity
import Combine

@MainActor
final class ConvoyPhoneBridge {
    static let shared = ConvoyPhoneBridge()

    /// LRU window of envelope ids the bridge has already handled.
    /// Prevents the server-loopback duplicate case and also suppresses
    /// the "retransmit over WCSession when watch reachability flaps"
    /// echo that would otherwise land an envelope on the wrist twice.
    private var seenEnvelopeIds: [String] = []
    private let seenCapacity = 256

    /// Subscribers for realtime inbound envelopes. Populated by
    /// `startRealtimeBridge()` and torn down by `stop()`.
    private var realtimeObservers: [NSObjectProtocol] = []

    private var isStarted = false

    private var session: WCSession? {
        guard WCSession.isSupported() else { return nil }
        return WCSession.default
    }

    // MARK: - Lifecycle

    /// Called once, from the same startup point that kicks off
    /// `WatchAuthBridge.startRealtimeBridge()`. Idempotent.
    func startRealtimeBridge() {
        guard !isStarted else { return }
        isStarted = true
        let center = NotificationCenter.default
        // The backend pushes convoy envelopes to this driver over
        // the same notification bus the rest of the realtime surface
        // uses. Payload shape: { "convoy": <envelope dict> } — we
        // re-encode to JSON + base64 for WCSession transit.
        realtimeObservers.append(
            center.addObserver(
                forName: .eusoConvoyInbound,
                object: nil,
                queue: .main
            ) { [weak self] note in
                Task { @MainActor in
                    self?.handleInboundFromRealtime(note.userInfo)
                }
            }
        )
    }

    func stop() {
        for obs in realtimeObservers { NotificationCenter.default.removeObserver(obs) }
        realtimeObservers.removeAll()
        isStarted = false
    }

    // MARK: - Watch → Phone → Server

    /// Called by `WatchCommandHandler` when the wrist sends an
    /// `op: "convoy.envelope"` message. The payload carries the
    /// envelope as a base64-encoded JSON string under the "env"
    /// key. We return `["ok": true]` even on partial failures so
    /// the wrist's send path doesn't retry in a tight loop — the
    /// wrist already has its own OfflineQueue fallback for the
    /// message lane, and double-posting an SOS is worse than the
    /// rare lost one.
    func handleWatchEnvelope(_ message: [String: Any]) async -> [String: Any] {
        guard
            let envB64 = message["env"] as? String,
            let envData = Data(base64Encoded: envB64)
        else {
            return ["ok": false, "reason": "missing or malformed envelope"]
        }

        // Pull the envelope id out without fully decoding into a
        // typed struct — the iOS target doesn't import the wrist's
        // ConvoyCoordinator module, and we don't actually need the
        // typed shape to fan out. Just lift id + kind for dedup +
        // routing.
        guard
            let obj = try? JSONSerialization.jsonObject(with: envData) as? [String: Any],
            let envelopeId = obj["id"] as? String,
            let kind = obj["kind"] as? String
        else {
            return ["ok": false, "reason": "envelope JSON unrecognized"]
        }

        if rememberEnvelopeId(envelopeId) == .duplicate {
            // Already handled — treat as a no-op success so the
            // wrist doesn't retry.
            return ["ok": true, "dedup": true]
        }

        // Forward to backend. The server will dedupe again on its
        // side (envelope id is the idempotency key) and fan out to
        // other convoy members' companion apps.
        await postEnvelopeToBackend(envelopeData: envData, kind: kind)
        return ["ok": true]
    }

    /// Wrist asked us to verify a batch of pinned peer keys against
    /// the fleet roster. `message["keys"]` carries an array of
    /// `["driverId": "...", "pinnedPublicKeyB64": "..."]` dicts.
    /// We POST the batch to `fleet.verifyConvoyMember` and hand the
    /// result map back in the WCSession reply. Network failures
    /// return `ok: false` without a map so the wrist leaves the
    /// trust states untouched and retries on the next reconcile.
    func handleVerifyRoster(_ message: [String: Any]) async -> [String: Any] {
        guard let rawKeys = message["keys"] as? [[String: Any]], !rawKeys.isEmpty else {
            return ["ok": false, "reason": "missing keys"]
        }
        // Re-shape to the tRPC input contract. We don't trust the
        // wrist blindly — cap at 64 entries to match the server Zod
        // schema, drop any malformed rows.
        let keys: [[String: String]] = rawKeys.prefix(64).compactMap { dict in
            guard
                let driverId = dict["driverId"] as? String, !driverId.isEmpty,
                let pub = dict["pinnedPublicKeyB64"] as? String, !pub.isEmpty
            else { return nil }
            return ["driverId": driverId, "pinnedPublicKeyB64": pub]
        }
        guard !keys.isEmpty else { return ["ok": false, "reason": "no valid keys"] }

        let api = EusoTripAPI.shared
        guard let base = api.baseURL else {
            return ["ok": false, "reason": "no base URL"]
        }
        let url = base.appendingPathComponent("api/trpc/fleet.verifyConvoyMember")
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = api.authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let payload: [String: Any] = ["keys": keys]
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["json": payload])

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return ["ok": false, "reason": "http \(String(describing: (resp as? HTTPURLResponse)?.statusCode))"]
            }
            // tRPC wraps mutations as { result: { data: { results: [...] } } }.
            // Peel the onion defensively — the server target here is
            // stable but we don't want a future tRPC batch wrapper
            // change to poison the wrist's trust state.
            guard
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return ["ok": false, "reason": "bad JSON"] }
            var dataNode: Any? = obj["result"]
            if let r = dataNode as? [String: Any] { dataNode = r["data"] }
            if let d = dataNode as? [String: Any], let json = d["json"] as? [String: Any] { dataNode = json }
            guard
                let node = dataNode as? [String: Any],
                let arr = node["results"] as? [[String: Any]]
            else { return ["ok": false, "reason": "no results"] }

            var map: [String: String] = [:]
            for row in arr {
                guard
                    let driverId = row["driverId"] as? String,
                    let status = row["status"] as? String
                else { continue }
                map[driverId] = status
            }
            return ["ok": true, "results": map]
        } catch {
            return ["ok": false, "reason": error.localizedDescription]
        }
    }

    private func postEnvelopeToBackend(envelopeData: Data, kind: String) async {
        // The backend endpoint is `convoy.relay` under tRPC. We
        // hand-build the envelope exactly like WatchCommandHandler
        // does for the SOS path — that pattern has been stable
        // since build 20, and we don't want to thread a new typed
        // router through EusoTripAPI just to light up convoy.
        let api = EusoTripAPI.shared
        guard let base = api.baseURL else { return }
        let url = base.appendingPathComponent("api/trpc/convoy.relay")
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = api.authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        // Envelope stays base64 on the wire so the server can pass
        // the exact signed bytes straight to other members without
        // re-encoding (which would invalidate the signature).
        let payload: [String: Any] = [
            "envelopeB64": envelopeData.base64EncodedString(),
            "kind": kind,
            "source": "watch-via-phone"
        ]
        req.httpBody = try? JSONSerialization.data(
            withJSONObject: ["json": payload]
        )
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Server → Phone → Watch

    /// Handles an inbound envelope delivered by the realtime stream.
    /// `userInfo` MUST contain either:
    ///   - "envelopeB64": String  (raw signed bytes, base64), OR
    ///   - "envelope":    [String: Any]  (decoded dict form)
    /// The dict form is accepted so the backend can push either
    /// representation depending on its transport.
    private func handleInboundFromRealtime(_ userInfo: [AnyHashable: Any]?) {
        guard let userInfo else { return }

        var envB64: String?
        if let direct = userInfo["envelopeB64"] as? String {
            envB64 = direct
        } else if let dict = userInfo["envelope"] as? [String: Any],
                  let encoded = try? JSONSerialization.data(withJSONObject: dict) {
            envB64 = encoded.base64EncodedString()
        }
        guard let envB64,
              let envData = Data(base64Encoded: envB64),
              let obj = try? JSONSerialization.jsonObject(with: envData) as? [String: Any],
              let envelopeId = obj["id"] as? String
        else { return }

        // Drop loopbacks — envelopes we just sent upstream shouldn't
        // come back down and re-trigger the wrist.
        if rememberEnvelopeId(envelopeId) == .duplicate { return }

        pushEnvelopeToWatch(envB64: envB64)
    }

    private func pushEnvelopeToWatch(envB64: String) {
        guard let session else { return }
        if session.activationState != .activated {
            session.activate()
        }
        let ctx: [String: Any] = [
            "op": "convoy.ingest",
            "env": envB64,
            "ts": Date().timeIntervalSince1970
        ]
        // sendMessage when the wrist is awake for low latency;
        // transferUserInfo as a fallback when the app is backgrounded
        // so the envelope still lands on the next activation.
        if session.isReachable {
            session.sendMessage(ctx, replyHandler: nil) { _ in
                // If sendMessage fails (watch app goes inactive mid-send),
                // enqueue via transferUserInfo so the envelope still lands
                // on the next activation rather than evaporating.
                session.transferUserInfo(ctx)
            }
        } else {
            session.transferUserInfo(ctx)
        }
    }

    // MARK: - Dedup

    private enum RememberResult { case novel, duplicate }

    private func rememberEnvelopeId(_ id: String) -> RememberResult {
        if seenEnvelopeIds.contains(id) { return .duplicate }
        seenEnvelopeIds.append(id)
        // LRU evict from the front once we exceed capacity so the
        // window stays bounded. A straight array is fine at this
        // scale — contains() on 256 strings is nothing next to the
        // network call we're about to make.
        if seenEnvelopeIds.count > seenCapacity {
            seenEnvelopeIds.removeFirst(seenEnvelopeIds.count - seenCapacity)
        }
        return .novel
    }
}

// MARK: - Realtime hook

extension Notification.Name {
    /// Emitted by the realtime layer when the backend pushes a
    /// convoy envelope to this driver. `userInfo` keys — see
    /// `ConvoyPhoneBridge.handleInboundFromRealtime(_:)`.
    static let eusoConvoyInbound = Notification.Name("eusoConvoyInbound")
}
