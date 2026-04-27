//
//  WatchConnectivityManager.swift
//  EusoTrip Watch App
//
//  Bridges the watch to the paired iPhone. Handles:
//    1. Receiving the auth token from iOS app on pair/sign-in
//    2. Firing the "activate Esang on phone" trigger, which requests
//       the iOS app to: wake in background + publish Handoff activity +
//       schedule a local notification.
//    3. Forwarding each voice interaction's transcript + reply so the
//       phone's Esang conversation stays in sync.
//    4. Receiving iOS-side state pushes (active load, HOS status) so the
//       watch stays in sync even when the app isn't launched on the wrist.
//

import Foundation
import WatchConnectivity
import Combine

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    /// Debounced reachability flag the UI reads. WCSession.isReachable
    /// itself flips false during normal BLE hops, wrist-lower cycles,
    /// and phone foreground/background transitions; observing that raw
    /// signal directly made the "LINK" dial + iOS pairing pill visibly
    /// flap between Live and Offline within a few seconds. We keep this
    /// sticky for `reachableStickyWindow` after the last true tick so
    /// the UI only reports Offline when the link is genuinely down.
    @Published private(set) var isReachable: Bool = false
    @Published var isActivated: Bool = false

    /// Timestamp of the most recent raw `isReachable == true` observation.
    private var lastReachableAt: Date?
    private let reachableStickyWindow: TimeInterval = 15
    private var stickyTimer: Timer?

    /// Single source of truth that maps raw WCSession reachability to
    /// the debounced `isReachable` value. Called from every delegate
    /// path that used to write `isReachable` directly.
    private func applyReachability(_ raw: Bool) {
        let next: Bool
        if raw {
            lastReachableAt = Date()
            next = true
            scheduleStickyExpiration()
        } else if let last = lastReachableAt,
                  Date().timeIntervalSince(last) < reachableStickyWindow {
            // Still inside the sticky window — keep the UI showing Live.
            next = true
            scheduleStickyExpiration()
        } else {
            next = false
            stickyTimer?.invalidate()
            stickyTimer = nil
        }
        if isReachable != next { isReachable = next }
        // Mirror to OrbStateMachine so the OFFLINE capsule on Home
        // respects the iPhone-bridge transport, not just direct
        // cellular. Without this the orb flashed OFFLINE during
        // every cold-launch unpaired-pairing window even though the
        // phone was right there, signed-in, reachable.
        OrbStateMachine.shared.phoneReachable = next
    }

    private func scheduleStickyExpiration() {
        stickyTimer?.invalidate()
        guard let last = lastReachableAt else { return }
        let deadline = last.addingTimeInterval(reachableStickyWindow)
        let delay = max(0, deadline.timeIntervalSinceNow) + 0.1
        stickyTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Re-evaluate with the latest raw signal when the window
                // expires so we flip to Offline iff the link is still down.
                let raw = self.session?.isReachable ?? false
                self.applyReachability(raw)
            }
        }
    }

    // Marked nonisolated — WCSession must be accessible from any thread.
    // Lazy so we don't touch WCSession.default during the class's static
    // init (which happens on whichever thread first triggers it); under
    // watchOS 26.4 this access on the wrong actor context can wedge the
    // main thread during app launch.
    nonisolated private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Ask the iPhone to re-mirror its current auth state. Called at
    /// watch launch and every time the session goes reachable without a
    /// cached token. The phone replies with the `auth.update` payload
    /// via both the message replyHandler and an applicationContext
    /// fan-out, so whichever arrives first wins.
    ///
    /// If the phone isn't reachable (app not in foreground, Bluetooth
    /// flaky, watchOS companion bridge cold), we fall back to
    /// `transferUserInfo` — the phone's WCSessionDelegate handles that
    /// call identically to a live message, which means `republishAuth()`
    /// fires on the phone side and pushes `updateApplicationContext`
    /// back at us whenever delivery happens. This is the path that
    /// unsticks the "Open EusoTrip on iPhone to pair" screen in the
    /// real-world flow where the user just installed Pulse and neither
    /// side has seen the other yet.
    func requestAuthMirror() {
        guard let session, session.activationState == .activated else { return }
        let payload: [String: Any] = [
            "op": "auth.request",
            "ts": Date().timeIntervalSince1970
        ]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: { [weak self] reply in
                guard let self else { return }
                // The phone can either return the full auth context inline
                // or just `hasAuth: true` and rely on the applicationContext
                // fan-out that `republishAuth()` fires. Handle both.
                if let ctx = reply["auth"] as? [String: Any] {
                    Task { @MainActor in self.applyContext(ctx) }
                }
            }, errorHandler: { [weak session] _ in
                // Live send failed — drop into the queued path so the
                // phone still hears us when it wakes up. transferUserInfo
                // survives app restarts on both sides.
                session?.transferUserInfo(payload)
            })
        } else {
            // No live link right now. transferUserInfo queues the request
            // for the next time the companion wakes and then the phone
            // responds via applicationContext fan-out.
            session.transferUserInfo(payload)
        }
    }

    /// Launch-time auth-bootstrap loop. Fires `requestAuthMirror()`
    /// every 2 seconds for up to 30 seconds, stopping the moment the
    /// AuthStore reports we have a token. Solves the cold-launch race
    /// where the watch app comes up first and asks the iPhone for auth
    /// while `EusoTripSession.boot()` on the phone is still running —
    /// the single one-shot request fired by `activationDidComplete` lands
    /// before the phone has anything to reply with, then nothing happens
    /// until the user manually backgrounds + foregrounds the watch app.
    /// Without this loop the wrist sat on "Sign in on your iPhone" even
    /// though the phone was right there, signed in, in the foreground.
    func startAuthBootstrapPolling() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<15 {
                if AuthStore.shared?.isSignedIn == true { return }
                self.requestAuthMirror()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: - Outgoing messages

    /// Ask the iOS app to open Esang. Fires all three activation paths
    /// on the phone side (background wake, Handoff, local notification).
    func requestPhoneActivation(transcript: String?, reply: String?) {
        guard let session, session.activationState == .activated else { return }
        let payload: [String: Any] = [
            "op": "esang.activate",
            "transcript": transcript ?? "",
            "reply": reply ?? "",
            "ts": Date().timeIntervalSince1970,
        ]

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    /// tRPC relay — ask the paired iPhone to run a tRPC query on our
    /// behalf and return the raw response bytes. The wrist uses this
    /// as a fallback when direct network is unreachable (dead zone,
    /// airplane mode, watch-only eSIM paused). The iPhone side lives
    /// at `WatchCommandHandler.handleTRPCRelay` and is allow-listed
    /// to query-shaped procs only (getX / listX / searchX) so the
    /// privileged phone bearer never runs a mutation on behalf of
    /// a compromised wrist.
    ///
    /// Throws when the phone is unreachable, not activated, the
    /// phone-side relay returned an error payload, or the reply
    /// lacks the expected `data` field.
    func requestTRPCRelay(path: String, inputJSON: String) async throws -> Data {
        guard let session else { throw EsangError.notConnected }
        guard session.activationState == .activated, session.isReachable else {
            throw EsangError.notConnected
        }
        let payload: [String: Any] = [
            "op": "trpc.relay",
            "path": path,
            "inputJSON": inputJSON,
            "ts": Date().timeIntervalSince1970,
        ]
        return try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(payload, replyHandler: { reply in
                if let ok = reply["ok"] as? Bool, ok,
                   let b64 = reply["data"] as? String,
                   let data = Data(base64Encoded: b64) {
                    continuation.resume(returning: data)
                    return
                }
                let reason = (reply["reason"] as? String) ?? "Phone relay failed"
                continuation.resume(throwing: EsangError.server(status: 502, body: reason))
            }, errorHandler: { error in
                continuation.resume(throwing: error)
            })
        }
    }

    /// Forward a round-trip conversation (user said / Esang replied) so
    /// the iPhone's Esang surface renders it. iOS handler treats this as
    /// an activation event and fires the three phone-side paths.
    func forwardToPhone(transcript: String, reply: String, intent: String, actions: [VoiceAction]) {
        guard let session, session.activationState == .activated else { return }
        let actionPayloads: [[String: Any]] = actions.map { a in
            ["type": a.type, "label": a.label ?? ""]
        }
        let payload: [String: Any] = [
            "op": "esang.exchange",
            "transcript": transcript,
            "reply": reply,
            "intent": intent,
            "actions": actionPayloads,
            "ts": Date().timeIntervalSince1970,
        ]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in
                session.transferUserInfo(payload)
            })
        } else {
            session.transferUserInfo(payload)
        }
    }

    /// Fired by the emergency SOS surface — the phone responds with an
    /// E911 dial + support-team ping.
    func triggerEmergencySOS(reason: String, coordinate: (Double, Double)?) {
        guard let session, session.activationState == .activated else { return }
        var payload: [String: Any] = [
            "op": "esang.sos",
            "reason": reason,
            "ts": Date().timeIntervalSince1970,
        ]
        if let c = coordinate {
            payload["lat"] = c.0
            payload["lon"] = c.1
        }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in
                session.transferUserInfo(payload)
            })
        } else {
            session.transferUserInfo(payload)
        }
    }

    /// F13 — Hand a signed convoy envelope to the iPhone companion
    /// for cellular relay. The envelope is passed through as raw JSON
    /// bytes (already signed by `ConvoySignature`) so the phone can
    /// forward to the backend without re-encoding — which would
    /// invalidate the signature since we sign the canonical byte
    /// representation, not the decoded dictionary.
    ///
    /// Fire-and-forget from the wrist's perspective. The OfflineQueue
    /// message lane is the retry surface for missed packets; this
    /// path exists for the reachable case where we can skip the
    /// queue round-trip + get envelopes onto the wire within a frame.
    func sendConvoyEnvelope(_ data: Data) {
        guard let session, session.activationState == .activated else { return }
        let payload: [String: Any] = [
            "op": "convoy.envelope",
            "env": data.base64EncodedString(),
            "ts": Date().timeIntervalSince1970
        ]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in
                session.transferUserInfo(payload)
            })
        } else {
            // Background / wrist-down: queue for next activation so the
            // envelope still lands on the phone.
            session.transferUserInfo(payload)
        }
    }

    /// F13 — Ask the iOS companion to resolve pinned peer keys
    /// against the fleet roster (`fleet.verifyConvoyMember`). The
    /// phone does the HTTP round-trip and returns a
    /// `[driverId: "confirmed"|"suspect"|"unknown"]` map via the
    /// WCSession reply handler.
    ///
    /// Fails silently if the wrist isn't reachable — the caller
    /// treats missing replies as "no change" and retries on the
    /// next reconcile cadence.
    func verifyConvoyRoster(
        _ keys: [(driverId: String, pinnedPublicKeyB64: String)]
    ) async -> [String: String] {
        guard let session, session.activationState == .activated, session.isReachable else {
            return [:]
        }
        let shaped = keys.map { k -> [String: String] in
            ["driverId": k.driverId, "pinnedPublicKeyB64": k.pinnedPublicKeyB64]
        }
        let payload: [String: Any] = [
            "op": "convoy.verifyRoster",
            "keys": shaped,
            "ts": Date().timeIntervalSince1970
        ]
        return await withCheckedContinuation { cont in
            var resumed = false
            let resume: ([String: String]) -> Void = { map in
                if !resumed { resumed = true; cont.resume(returning: map) }
            }
            session.sendMessage(payload, replyHandler: { reply in
                guard
                    (reply["ok"] as? Bool) == true,
                    let map = reply["results"] as? [String: String]
                else { resume([:]); return }
                resume(map)
            }, errorHandler: { _ in resume([:]) })
        }
    }

    // MARK: - F03 satellite fallback

    /// Ask the phone to enumerate which satellite channels it can
    /// reach right now. Returns a list of raw channel identifiers
    /// (e.g. ["globalstar_emergency", "tmobile_starlink_d2c"]) and
    /// the tenant-configured dispatch shortcode.
    ///
    /// Empty list on failure — the wrist UI then falls back to
    /// "Globalstar emergency only" as a safe default.
    func probeSatelliteChannels() async -> (channels: [String], shortcode: String) {
        guard let session, session.activationState == .activated, session.isReachable else {
            return ([], "#EUSODISPATCH")
        }
        let payload: [String: Any] = [
            "op": "satellite.probe",
            "ts": Date().timeIntervalSince1970
        ]
        return await withCheckedContinuation { cont in
            var resumed = false
            let resume: (([String], String)) -> Void = { result in
                if !resumed { resumed = true; cont.resume(returning: result) }
            }
            session.sendMessage(payload, replyHandler: { reply in
                guard (reply["ok"] as? Bool) == true else {
                    resume(([], "#EUSODISPATCH")); return
                }
                let channels = reply["channels"] as? [String] ?? []
                let shortcode = reply["shortcode"] as? String ?? "#EUSODISPATCH"
                resume((channels, shortcode))
            }, errorHandler: { _ in resume(([], "#EUSODISPATCH")) })
        }
    }

    /// Hand off a satellite SOS payload to the phone for routing.
    /// Returns true when the phone ack'd the handoff — not delivery
    /// (the actual sat link is confirmed asynchronously by the
    /// iOS composer).
    func sendSatelliteSOS(
        channel: String,
        payload: String,
        reason: String
    ) async -> Bool {
        guard let session, session.activationState == .activated else { return false }
        let msg: [String: Any] = [
            "op": "satellite.send",
            "channel": channel,
            "payload": payload,
            "reason": reason,
            "ts": Date().timeIntervalSince1970
        ]
        // isReachable required — the phone has to wake + present the
        // composer. If not reachable, fall back to transferUserInfo so
        // the handoff lands the moment the phone comes back.
        if session.isReachable {
            return await withCheckedContinuation { cont in
                var resumed = false
                let resume: (Bool) -> Void = { ok in
                    if !resumed { resumed = true; cont.resume(returning: ok) }
                }
                session.sendMessage(msg, replyHandler: { reply in
                    resume((reply["ok"] as? Bool) == true)
                }, errorHandler: { _ in
                    // Queue via userInfo so the handoff is durable even
                    // when the phone is out of range.
                    session.transferUserInfo(msg)
                    resume(true)
                })
            }
        } else {
            session.transferUserInfo(msg)
            return true
        }
    }

    /// F06b — forward a load CRDT snapshot to the iOS companion so
    /// the phone can merge + POST it up to `fleet.ingestLoadCRDT`.
    /// Delivery mode: prefer `sendMessage` when the phone is reachable
    /// (sub-second latency, good for UX mutations like "driver pressed
    /// Arrived at Pickup"), otherwise `transferUserInfo` (durable but
    /// arrives whenever the phone comes back). Both are idempotent on
    /// the receiving side — FleetCRDT.importLoad is merge-safe.
    func forwardLoadCRDT(snapshot data: Data) {
        guard let session, session.activationState == .activated else { return }
        let payload: [String: Any] = [
            "op": "load.crdt",
            "snapshot": data.base64EncodedString(),
            "ts": Date().timeIntervalSince1970
        ]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in
                session.transferUserInfo(payload)
            })
        } else {
            session.transferUserInfo(payload)
        }
    }

    /// Q3 UWB docking — ferry the watch's local NIDiscoveryToken up to
    /// the iPhone so the phone can hand it to the counterparty device
    /// (trailer beacon, dockhand's watch, partner driver's phone). The
    /// counterparty's matching token comes back via the reverse
    /// direction as a `uwb.peerToken` applicationContext push.
    ///
    /// Scenario string picks the coaching band on the receiving side
    /// (trailer-coupling vs. dock-backin vs. dockhand-handoff). We
    /// prefer `sendMessage` for the sub-second feel at the beginning
    /// of a coupling maneuver, and fall back to `transferUserInfo` so
    /// the phone still gets the token if the app just went background.
    func forwardUWBLocalToken(tokenB64: String, scenario: String) {
        guard let session, session.activationState == .activated else { return }
        let payload: [String: Any] = [
            "op": "uwb.localToken",
            "token": tokenB64,
            "scenario": scenario,
            "ts": Date().timeIntervalSince1970
        ]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in
                session.transferUserInfo(payload)
            })
        } else {
            session.transferUserInfo(payload)
        }
    }

    /// F16 — Mirror a freshly-broadcast Proximity Handoff payload to
    /// the iPhone. The phone holds the payload in case the wrist's
    /// BLE radio dies mid-handoff (e.g., driver pulls the wrist off
    /// to wash their hands at the dock). The phone can then continue
    /// the advertisement from its own CoreBluetooth stack so the
    /// dockhand's scan still lands the same payload.
    ///
    /// We JSON-encode here rather than push a plist dictionary so the
    /// phone-side decode uses the exact same `HandoffPayload` struct
    /// that signed the envelope — byte-identical round-tripping is
    /// required for the HMAC to verify on both ends.
    func forwardProximityHandoff(_ payload: HandoffPayload) {
        guard let session, session.activationState == .activated else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        guard let data = try? enc.encode(payload) else { return }
        let body: [String: Any] = [
            "op": "proximity.handoff",
            "payload": data.base64EncodedString(),
            "ts": Date().timeIntervalSince1970
        ]
        if session.isReachable {
            session.sendMessage(body, replyHandler: nil, errorHandler: { _ in
                session.transferUserInfo(body)
            })
        } else {
            session.transferUserInfo(body)
        }
    }

    /// F15 — Ask the iOS companion to open the camera + Vision +
    /// Foundation Models pipeline on a BOL or placard. The phone is
    /// the only side with a camera and the only side that has
    /// `FoundationModels` available (watchOS has neither). Result
    /// comes back asynchronously as a `bol.result` push.
    func requestBOLScan(kind: String, loadId: String?) {
        guard let session, session.activationState == .activated else { return }
        var payload: [String: Any] = [
            "op": "bol.scanRequest",
            "kind": kind,
            "ts": Date().timeIntervalSince1970
        ]
        if let loadId { payload["loadId"] = loadId }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in
                session.transferUserInfo(payload)
            })
        } else {
            session.transferUserInfo(payload)
        }
    }

    /// Ping the phone to report driver status change from the wrist
    /// (on-duty / off-duty / driving / sleeper-berth). The iOS app
    /// forwards this to hos.changeStatus so the ELD + FMCSA log stays
    /// authoritative.
    func reportHOSStatusChange(status: String, odometer: Double?, location: String?) {
        guard let session, session.activationState == .activated else { return }
        var payload: [String: Any] = [
            "op": "esang.hos",
            "status": status,
            "ts": Date().timeIntervalSince1970,
        ]
        if let odometer { payload["odometer"] = odometer }
        if let location { payload["location"] = location }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in
                session.transferUserInfo(payload)
            })
        } else {
            session.transferUserInfo(payload)
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    // All WCSessionDelegate callbacks come in on a background queue. Mark
    // them nonisolated so the Swift 6 concurrency checker doesn't require
    // a synchronous actor hop (which, under implicit-@MainActor classes,
    // can deadlock launch when the session activates during first frame).
    // Inside each, we hop to the main actor explicitly to touch @Published
    // state.
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let activated = state == .activated
        let reachable = session.isReachable
        let ctx = session.receivedApplicationContext
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isActivated = activated
            self.applyReachability(reachable)
            self.applyContext(ctx)
            // If we activated without a cached token but the phone is
            // reachable right now, pull auth state immediately so the
            // wrist can swap its "Open EusoTrip on iPhone to pair" hint
            // off without waiting for the next phone push.
            if reachable, AuthStore.shared?.isSignedIn == false {
                self.requestAuthMirror()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.applyReachability(reachable)
            // Phone just came back in range. If we don't already have
            // a mirrored token, pull it so the UI can flip out of the
            // pairing-hint state before the driver even taps anything.
            if reachable, AuthStore.shared?.isSignedIn == false {
                self.requestAuthMirror()
            }
            // L5 — drain the Unified Outbox the moment reachability
            // flips positive. Without this, queued voice / HOS /
            // arrival events sat in the lanes until the next tap or
            // scenePhase cycle. Safe when `flushAll` short-circuits on
            // an unsigned auth store.
            if reachable, let auth = AuthStore.shared {
                await OfflineQueue.shared.flushAll(auth: auth)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor [weak self] in
            self?.applyContext(applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor [weak self] in
            self?.applyContext(message)
        }
    }

    /// Notification name posted whenever the iPhone forwards a
    /// realtime event (bid award, settlement paid, document
    /// uploaded, etc.). Watch surfaces observe this to refresh.
    static let realtimeEventNotification = Notification.Name("watchRealtimeEvent")

    private func applyContext(_ ctx: [String: Any]) {
        guard let op = ctx["op"] as? String else { return }
        switch op {
        case "realtime.event":
            // iPhone forwarded one of its WebSocket events. Re-broadcast
            // locally so any watch view that cares (HomeView, HOSView,
            // wallet glance) can refresh. Carries `event` (string)
            // and `info` (dict) for routing.
            NotificationCenter.default.post(
                name: WatchConnectivityManager.realtimeEventNotification,
                object: ctx["event"] as? String,
                userInfo: ctx
            )
            return
        case "auth.update":
            Task { @MainActor in
                // Auth payloads from the phone come in TWO flavors:
                //   1. Explicit sign-out:  `clear: true` (with or without
                //      empty token fields). Only then do we wipe keychain.
                //   2. Sign-in / refresh:  a payload that MUST carry a
                //      non-empty token. If the incoming payload has no
                //      token (or an empty string), treat it as a stale /
                //      partial mirror and IGNORE — do NOT wipe a good
                //      local token just because the phone's in-memory
                //      `lastPushedAuthContext` was empty during a cold
                //      app launch or background cycle.
                //
                // Before this patch, a phone backgrounded / foregrounded
                // while the wrist had a cached token would fire
                // `requestAuthMirror` → phone replies with empty fields →
                // watch `AuthStore.update(token: nil, ...)` → keychain
                // cleared → orb flips dead → orb gated on `isSignedIn`
                // played failure haptic → looked "unresponsive / flapping
                // offline" to the driver. Fix: treat empty payloads as
                // no-ops; the next genuine sign-in push (or the local
                // keychain) is the source of truth.
                let cleared = (ctx["clear"] as? Bool) ?? false
                let rawToken = ctx["token"] as? String
                let rawUserId = ctx["userId"] as? String
                let rawUserName = ctx["userName"] as? String
                let rawRole = ctx["role"] as? String
                let normalize: (String?) -> String? = { s in
                    guard let s, !s.isEmpty else { return nil }
                    return s
                }
                if cleared {
                    AuthStore.shared?.update(token: nil, userId: nil, userName: nil, role: nil)
                } else if let token = normalize(rawToken) {
                    // Additive update: only overwrite when we actually
                    // have a token. Missing user/name/role are allowed —
                    // keep the existing ones rather than clobbering.
                    AuthStore.shared?.update(
                        token: token,
                        userId: normalize(rawUserId) ?? AuthStore.shared?.userId,
                        userName: normalize(rawUserName) ?? AuthStore.shared?.userName,
                        role: normalize(rawRole) ?? AuthStore.shared?.role
                    )
                }
                // else: partial/empty mirror → ignore; keep the cached
                // token + keychain intact so the orb stays alive across
                // reachability churn.
            }
        case "load.active":
            Task { @MainActor in
                if let cleared = ctx["cleared"] as? Bool, cleared {
                    LoadStore.shared.clearActive()
                } else if let json = ctx["load"] as? [String: Any], !json.isEmpty {
                    LoadStore.shared.applyRemote(json: json)
                }
            }
        case "load.crdt":
            // F06b — remote load-state CRDT snapshot from the iOS
            // companion (forwarded either directly from a tRPC fan-out
            // or relayed from another device via ConvoyCoordinator).
            // The phone base64-encodes the JSON to avoid WCSession's
            // nested-dict overhead. On success, FleetCRDT merges and
            // republishes the active-load snapshot so any UI bound to
            // it re-renders with the remote mutations folded in.
            Task { @MainActor in
                guard let snapB64 = ctx["snapshot"] as? String,
                      let data = Data(base64Encoded: snapB64) else { return }
                _ = FleetCRDT.shared.importLoad(data)
            }
        case "hos.update":
            Task { @MainActor in
                HOSStore.shared.applyRemote(
                    status: ctx["status"] as? String ?? "off",
                    driveRemainingMinutes: ctx["driveRemainingMinutes"] as? Int ?? 0,
                    windowRemainingMinutes: ctx["windowRemainingMinutes"] as? Int ?? 0,
                    cycleRemainingMinutes: ctx["cycleRemainingMinutes"] as? Int ?? 0
                )
            }
        case "messaging.unread":
            // Phone's `UnreadMessageStore` mirrored to the wrist so the
            // Inbox tab badge matches what the user just saw on the
            // phone's top-bar chat glyph. Per-conversation map allows
            // the thread list to stamp a dot on the right rows even
            // without a fresh tRPC call.
            Task { @MainActor in
                let total = ctx["total"] as? Int ?? 0
                let map = ctx["byConversation"] as? [String: Int] ?? [:]
                InboxStore.shared.applyRemoteUnread(total: total, map: map)
            }
        case "bol.result":
            // F15 — scan result from the iPhone companion. The phone
            // JSON-encodes the full BOLScanResult (including warnings)
            // and base64s the bytes so WCSession's plist-shaped
            // applicationContext doesn't flatten the nested structure.
            Task { @MainActor in
                guard let payloadB64 = ctx["payload"] as? String,
                      let data = Data(base64Encoded: payloadB64) else { return }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                guard let result = try? decoder.decode(BOLScanResult.self, from: data) else { return }
                BOLCopilot.shared.applyScanResult(result)
            }
        case "nav.route":
            // F14 — phone planned a new truck-legal route and is
            // pushing the maneuver list down for wrist turn-by-turn.
            // Payload shape:
            //   routeId: String
            //   route:   base64-encoded JSON {maneuvers: [Maneuver]}
            // The watch starts a keep-alive workout session as part of
            // startRoute so guidance survives a long haul.
            Task { @MainActor in
                guard let routeId = ctx["routeId"] as? String,
                      let routeB64 = ctx["route"] as? String else { return }
                NavigationSession.shared.ingestRemoteRouteB64(routeB64, routeId: routeId)
            }
        case "nav.clear":
            // Phone ended navigation (driver tapped "End route" on
            // the iPhone, or a newer route superseded this one).
            Task { @MainActor in
                NavigationSession.shared.endRoute()
            }
        case "uwb.peerToken":
            // Q3 UWB — phone ferried the counterparty's NIDiscoveryToken
            // to us. Bytes are base64-encoded over the wire because
            // WCSession's plist-shaped applicationContext chokes on raw
            // keyed-archive Data in some watchOS point releases. The
            // scenario string is optional: if missing we keep the
            // scenario UWBDocking was already configured for.
            Task { @MainActor in
                guard let tokenB64 = ctx["token"] as? String, !tokenB64.isEmpty else { return }
                let scenario = (ctx["scenario"] as? String)
                    .flatMap { UWBDockingScenario(rawValue: $0) }
                UWBDocking.shared.beginRanging(peerTokenB64: tokenB64, scenario: scenario)
            }
        case "proximity.capture":
            // F16 — phone-side capture of a nearby Proximity Handoff
            // beacon. The phone scanned over its CoreBluetooth stack
            // (more power budget + better antenna than the wrist) and
            // is forwarding the decoded payload up for the driver to
            // confirm on their wrist. Same JSON-encoded HandoffPayload
            // shape as the phone-bound mirror, so a round-trip passes
            // HMAC verification on both sides.
            Task { @MainActor in
                guard let payloadB64 = ctx["payload"] as? String,
                      let data = Data(base64Encoded: payloadB64) else { return }
                guard let payload = try? JSONDecoder()
                        .decode(HandoffPayload.self, from: data) else { return }
                ProximityHandoff.shared.ingestRemoteCapture(payload)
            }
        case "convoy.ingest":
            // F13 — phone received a convoy envelope from the backend
            // and forwarded it down. Decode + hand to the coordinator,
            // which verifies the signature before any state mutation.
            // The signing layer is the trust boundary — envelopes that
            // failed verification on the phone side still get checked
            // here, so a compromised phone can't bypass trust.
            Task { @MainActor in
                guard
                    let envB64 = ctx["env"] as? String,
                    let envData = Data(base64Encoded: envB64),
                    let envelope = try? JSONDecoder().decode(ConvoyEnvelope.self, from: envData)
                else { return }
                ConvoyCoordinator.shared.ingest(envelope)
            }
        default:
            break
        }
    }
}
