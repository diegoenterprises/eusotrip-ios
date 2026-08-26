//
//  WatchCommandHandler.swift
//  EusoTrip
//
//  Processes watch-side commands sent via WCSession. Three categories:
//
//    1. activation  — "open on iPhone" hand-off (opens Maps, eSang chat,
//                     dispatcher view, etc.)
//    2. voice       — transcribed voice text the watch would like the
//                     phone to answer (richer Gemini context on phone)
//    3. esang.sos   — escalation from wrist; place an E911 call + route
//                     dispatch notification
//
//  Keeps a singleton so WCSession delegates can forward without caring
//  which object holds the SwiftUI deeplink state.
//

import Foundation
import UIKit
import SwiftUI
import CoreLocation
@preconcurrency import UserNotifications

@MainActor
final class WatchCommandHandler: NSObject, ObservableObject {
    static let shared = WatchCommandHandler()

    /// Deeplink surface observed by ContentView. When non-nil, the iOS
    /// app should route to the appropriate destination.
    @Published var pendingDeeplink: WatchDeeplink?

    /// Toast-ish banner the iOS app can show ("eSang is on the wrist…").
    @Published var lastWatchTranscript: String?

    private let api: EusoTripAPI

    init(api: EusoTripAPI = .shared) {
        self.api = api
        super.init()
    }

    /// Entry point for both `didReceiveMessage` and `didReceiveUserInfo`.
    /// Returns a reply dict that the WCSession can hand back to the wrist.
    @discardableResult
    func handle(_ message: [String: Any]) async -> [String: Any] {
        let op = (message["op"] as? String) ?? ""
        switch op {
        // Legacy op codes
        case "activation":
            return await handleActivation(message)
        case "voice":
            return await handleVoice(message)
        case "hos.event":
            return await handleHOSEvent(message)

        // Pulse (2026) op codes — wrist's WatchConnectivityManager emits these.
        // Aliased to the same handlers so iOS responds regardless of which
        // generation of the watch app is paired.
        case "esang.activate":
            return await handleActivation(message)
        case "esang.exchange":
            return await handleExchange(message)
        case "esang.hos":
            return await handleHOSEvent(message)

        case "esang.sos":
            return await handleSOS(message)

        case "load.accept":
            return await handleLoadAccept(message)

        case "load.arrived":
            return await handleArrived(message)

        case "auth.request":
            return await handleAuthRequest()

        // F13 — wrist forwards a signed convoy envelope to the
        // companion for cellular relay. ConvoyPhoneBridge handles
        // dedup + backend POST; see that file for the full rationale.
        case "convoy.envelope":
            return await ConvoyPhoneBridge.shared.handleWatchEnvelope(message)

        // F13 — wrist batches pinned peer keys and asks the phone
        // to resolve each driverId against the fleet roster via
        // `fleet.verifyConvoyMember`. The reply dict carries a
        // [driverId: "confirmed"|"suspect"|"unknown"] map the wrist
        // routes back into `ConvoySignature.setTrustState`.
        case "convoy.verifyRoster":
            return await ConvoyPhoneBridge.shared.handleVerifyRoster(message)

        // F03 — wrist terrestrial-loss dwell tripped. Ask the phone
        // which satellite channels are reachable (CTTelephony-backed
        // + emergency-sos-capable detection).
        case "satellite.probe":
            return await SatellitePhoneBridge.shared.handleProbe(message)

        // F03 — driver confirmed a satellite channel + payload on the
        // wrist. Phone routes into the appropriate system composer
        // (Messages-via-sat, Emergency SOS, inReach hand-off).
        case "satellite.send":
            return await SatellitePhoneBridge.shared.handleSend(message)

        // Pulse relay — the wrist couldn't reach the backend directly
        // (dead zone, airplane mode, etc.) so it asks the phone to
        // run a tRPC query on its behalf. The phone is already on
        // the authenticated user's session (cookies + Bearer), so
        // we can run the call and ship the raw response bytes back.
        case "trpc.relay":
            return await handleTRPCRelay(message)

        default:
            return ["ok": false, "reason": "unknown op \(op)"]
        }
    }

    /// Pulse tRPC relay — the wrist passes a `path` (e.g. "wallet.getBalance")
    /// and an `inputJSON` string (already wrapped or bare), we execute
    /// it via the authenticated iOS session, and hand back the raw
    /// server response bytes base64-encoded under `data`. The wrist
    /// decodes with its own envelope parser.
    ///
    /// Safety: the wrist is only a relay client — it does NOT get to
    /// run mutations through this path. We refuse any op that doesn't
    /// look like a query (`get*`, `list*`, `search*`, etc.) so a
    /// compromised wrist bearer can't `deletePaymentMethod` or similar
    /// through the phone's privileged session.
    private func handleTRPCRelay(_ message: [String: Any]) async -> [String: Any] {
        guard let path = message["path"] as? String, !path.isEmpty else {
            return ["ok": false, "reason": "missing path"]
        }
        // Allowlist — the get*/list*-family prefix heuristic PLUS an
        // explicit set for read procs whose names don't match the
        // pattern but which the wrist legitimately relays in dead
        // zones (Port Ops board + per-load weather chip). Mutations
        // (submit, accept, delete, create, update, mark) stay refused.
        let explicitQueryAllowlist: Set<String> = [
            "controlTower.exceptions",
            "weather.forLoad",
        ]
        let lastSegment = path.split(separator: ".").last.map(String.init) ?? path
        let allowedPrefixes = ["get", "list", "search", "fetch", "query", "find", "summary"]
        let lower = lastSegment.lowercased()
        let allowed = explicitQueryAllowlist.contains(path)
            || allowedPrefixes.contains { lower.hasPrefix($0) }
        guard allowed else {
            return ["ok": false, "reason": "relay refuses non-query \(path)"]
        }
        let inputJSON = (message["inputJSON"] as? String) ?? "{}"
        do {
            let data = try await api.rawQuery(path: path, inputJSON: inputJSON)
            return [
                "ok": true,
                "data": data.base64EncodedString(),
                "path": path,
            ]
        } catch {
            return [
                "ok": false,
                "reason": error.localizedDescription,
                "path": path,
            ]
        }
    }

    /// Wrist asks "are we signed in? if so, please re-mirror". We
    /// re-broadcast the last pushed auth context (if any), and if no
    /// cached push exists we fall back to `EusoTripAPI.shared.authToken`
    /// so the wrist still unblocks.
    ///
    /// Why the fallback matters: `WatchAuthBridge.cachedAuth` is only
    /// populated after `EusoTripSession.boot()` /.signIn / .signInDemo
    /// explicitly calls `push(...)`. On a cold phone launch the wrist
    /// activates + calls `requestAuthMirror` in the ~500ms window BEFORE
    /// `auth.me()` resolves — which previously answered `hasAuth: false`
    /// and left the orb stuck on "Link your iPhone" even though the
    /// phone was signed in. Forwarding the live API token makes the
    /// answer reflect the actual backend-auth state, matching the
    /// Me-tab Resync button which already used this fallback path.
    private func handleAuthRequest() async -> [String: Any] {
        // `api.authToken` is whatever EusoTripSession hydrated into the
        // singleton. On a brutally cold app activation (the watch beat
        // EusoTripSession.boot() to the punch) it's still nil even
        // though the keychain has a perfectly good bearer from a prior
        // signed-in run. Read the keychain directly as a third
        // fallback so the wrist's launch-time poll can resolve before
        // the phone's session has finished its async boot.
        let liveToken = api.authToken
        let keychainToken: String? = {
            guard liveToken == nil || liveToken?.isEmpty == true else { return nil }
            return EusoKeychain(service: "com.eusorone.EusoTrip.session")
                .load(key: "authToken")
        }()
        let bearer = (liveToken?.isEmpty == false) ? liveToken : keychainToken
        let sent = WatchAuthBridge.shared.republishAuth(
            fallbackToken: bearer
        )
        if let ctx = WatchAuthBridge.shared.lastPushedAuthContext {
            return ["ok": true, "hasAuth": true, "auth": ctx]
        }
        return ["ok": true, "hasAuth": sent]
    }

    /// Pulse sends `esang.exchange` after every wrist conversation round-trip.
    /// We treat it like an activation + surface the transcript so the iOS
    /// eSang chat has the latest exchange preloaded if the driver taps through.
    ///
    /// Persistence: the wrist already SPOKE the reply locally, but that voice
    /// turn lived only on the watch. We now write it through the real
    /// `messages.sendMessage` path so the exchange reaches the backend and
    /// shows up in the driver's ESANG thread on the phone/web like any other
    /// message. The wrist envelope carries no `conversationId`, so we resolve
    /// a sensible default (load thread if the wrist supplied a `loadId`,
    /// otherwise the existing ESANG/assistant conversation). If we genuinely
    /// can't resolve a conversation, we DON'T fabricate one — we keep the
    /// UI-cache + report the honest gap in the reply dict.
    private func handleExchange(_ message: [String: Any]) async -> [String: Any] {
        let transcript = (message["transcript"] as? String) ?? ""
        let reply = (message["reply"] as? String) ?? ""
        let intent = (message["intent"] as? String) ?? ""
        let actions = (message["actions"] as? [[String: Any]]) ?? []

        // Keep the existing UI-cache behaviour (toast banner + realtime
        // refresh) regardless of whether persistence succeeds.
        lastWatchTranscript = transcript.isEmpty ? nil : transcript
        // Don't force a deeplink — the wrist already spoke the reply.
        // Just notify realtime surface so any open iOS view can refresh.
        NotificationCenter.default.post(name: .esangRefreshSurface, object: nil)

        // Nothing to persist if the wrist sent an empty turn.
        guard !transcript.isEmpty || !reply.isEmpty else {
            return ["ok": true, "persisted": false, "reason": "empty exchange"]
        }

        // Resolve the conversation to write into.
        guard let conversationId = await resolveExchangeConversationId(message) else {
            // Honest gap — no conversation context and no ESANG thread to
            // attach to. The wrist's exchange stays cached for the UI but
            // does NOT silently pretend it reached the backend.
            return [
                "ok": true,
                "persisted": false,
                "reason": "no conversation context for voice turn",
            ]
        }

        // The `messages.sendMessage` proc accepts only (conversationId,
        // content, type) — there is no structured-metadata field for intent
        // or the action list. So we fold the salient context into the
        // message body honestly: the spoken transcript + ESANG's reply, and
        // a compact intent/actions trailer when present. (GAP: a metadata
        // field on sendMessage would let intent/actions persist as structured
        // data instead of inline text — see report.)
        let content = composeVoiceTurnBody(
            transcript: transcript,
            reply: reply,
            intent: intent,
            actions: actions
        )

        // Dedup a re-delivered wrist turn. WCSession can deliver the same
        // `esang.exchange` envelope more than once (sendMessage falls back
        // to transferUserInfo on failure, and transferUserInfo itself
        // retries until ack), which would otherwise post a DUPLICATE
        // message every redelivery. Derive a STABLE key the server dedupes
        // on (userId + idempotencyKey): prefer a wrist-supplied
        // exchange/turn id if the watch ever sends one, else hash the
        // conversation + content + the watch's own `ts`. `ts` is stamped
        // once at the wrist send-site and carried verbatim through every
        // redelivery, so the same logical turn always maps to the same key
        // while distinct turns (different content or ts) don't collide.
        let idempotencyKey = exchangeIdempotencyKey(
            message: message,
            conversationId: conversationId,
            content: content
        )

        do {
            let result = try await api.messaging.sendMessage(
                conversationId: conversationId,
                content: content,
                type: "voice_message",
                idempotencyKey: idempotencyKey
            )
            return [
                "ok": true,
                "persisted": true,
                "messageId": result.id,
                "conversationId": result.conversationId,
            ]
        } catch {
            // Surface the REAL failure — the caller (and the wrist) should
            // know the turn didn't land. No fake success.
            NSLog("[WatchCommandHandler] esang.exchange persist failed: \(error.localizedDescription)")
            return [
                "ok": false,
                "persisted": false,
                "reason": error.localizedDescription,
            ]
        }
    }

    /// Picks the conversation a wrist voice turn should be written into.
    ///
    ///   1. If the wrist supplied a `loadId`, use it — the messages router
    ///      treats a load id as a stable conversation key for dispatch
    ///      threads (same convention as the 053 ESANG dispatch chat).
    ///   2. Otherwise fall back to the driver's existing ESANG / AI-assistant
    ///      conversation, identified by name the same way `MessagesScreen`
    ///      does (`esang` / `ai assistant`).
    ///
    /// Returns `nil` when neither exists — we refuse to invent a conversation
    /// (`createConversation` needs participant ids we don't have on the wrist
    /// hand-off path), so the caller reports the honest gap instead.
    private func resolveExchangeConversationId(_ message: [String: Any]) async -> String? {
        if let loadId = message["loadId"] as? String, !loadId.isEmpty {
            return loadId
        }
        if let loadIdInt = message["loadId"] as? Int {
            return String(loadIdInt)
        }
        // Look up the ESANG/assistant thread from the live inbox.
        guard let conversations = try? await api.messaging.getConversations() else {
            return nil
        }
        let esang = conversations.first { convo in
            let hay = ((convo.participantName ?? convo.name) + " "
                       + (convo.type ?? "")).lowercased()
            return hay.contains("esang") || hay.contains("ai assistant")
        }
        return esang?.id
    }

    /// Builds the persisted body for a wrist voice turn. Folds the spoken
    /// transcript, ESANG's reply, and (when present) the routed intent +
    /// action labels into a single readable string, since `sendMessage`
    /// has no structured-metadata field.
    private func composeVoiceTurnBody(
        transcript: String,
        reply: String,
        intent: String,
        actions: [[String: Any]]
    ) -> String {
        var parts: [String] = []
        if !transcript.isEmpty { parts.append("Driver (Watch): \(transcript)") }
        if !reply.isEmpty { parts.append("ESANG: \(reply)") }
        if !intent.isEmpty { parts.append("intent: \(intent)") }
        let actionLabels = actions.compactMap { action -> String? in
            let label = (action["label"] as? String) ?? ""
            let type = (action["type"] as? String) ?? ""
            let chosen = label.isEmpty ? type : label
            return chosen.isEmpty ? nil : chosen
        }
        if !actionLabels.isEmpty {
            parts.append("actions: \(actionLabels.joined(separator: ", "))")
        }
        return parts.joined(separator: "\n")
    }

    /// Derives a STABLE idempotency key for a wrist `esang.exchange` turn so
    /// a re-delivered envelope collapses on the server instead of inserting
    /// a duplicate message.
    ///
    ///   1. If the wrist supplied an explicit `exchangeId` / `turnId`, trust
    ///      it verbatim (prefixed so it can't collide with another source's
    ///      keyspace) — that's the canonical per-turn identity.
    ///   2. Otherwise hash the stable inputs the wrist DID send:
    ///      conversationId + content + the watch's own `ts`. WCSession
    ///      redelivery preserves these bytes identically, so the same
    ///      logical turn always yields the same key, while a genuinely new
    ///      turn (different content or `ts`) yields a different one.
    ///
    /// The watch stamps `ts` once at the send-site and carries it through
    /// every redelivery, which is what makes the fallback hash stable rather
    /// than minting a fresh key per delivery.
    private func exchangeIdempotencyKey(
        message: [String: Any],
        conversationId: String,
        content: String
    ) -> String {
        if let exchangeId = (message["exchangeId"] as? String)
            ?? (message["turnId"] as? String),
           !exchangeId.isEmpty {
            return "watch-exchange:\(exchangeId)"
        }
        // The wrist sends `ts` as a Double (epoch seconds). Use it as the
        // stable nonce; fall back to a degenerate "0" only if absent so the
        // key is still deterministic for that (rare) envelope shape.
        let ts: String = {
            if let d = message["ts"] as? Double { return String(d) }
            if let i = message["ts"] as? Int { return String(i) }
            if let s = message["ts"] as? String, !s.isEmpty { return s }
            return "0"
        }()
        let seed = "\(conversationId)\u{1F}\(content)\u{1F}\(ts)"
        return "watch-exchange:\(stableHash(seed))"
    }

    /// FNV-1a 64-bit hash, rendered as a fixed-width hex string. Deterministic
    /// across launches/processes (unlike `Hasher`, which is per-process seeded),
    /// which is exactly what an idempotency nonce needs.
    private func stableHash(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return String(format: "%016llx", hash)
    }

    // MARK: - Activation (open-on-phone hand-off)

    private func handleActivation(_ message: [String: Any]) async -> [String: Any] {
        let transcript = message["transcript"] as? String ?? ""
        lastWatchTranscript = transcript

        // Very lightweight intent routing — the watch gives us a hint in
        // `transcript`, we pick a deeplink. Full Gemini routing happens
        // only if the user explicitly opens eSang chat on the phone.
        let lower = transcript.lowercased()
        if transcript.isEmpty || lower.contains("open eusotrip") || lower.contains("home") {
            // Plain "open the app" request from the wrist (pairing gate
            // / Open-on-iPhone pill). Landing on the Home screen IS the
            // destination — set NO deeplink so no sheet covers it; the
            // local notification below is the one-tap opener.
            pendingDeeplink = nil
        } else if lower.contains("wallet") {
            pendingDeeplink = .wallet
        } else if lower.contains("hos") || lower.contains("hours") || lower.contains("log") {
            pendingDeeplink = .hos
        } else if lower.contains("navigate") || lower.contains("map") || lower.contains("rest") {
            pendingDeeplink = .maps(query: transcript)
        } else if lower.contains("dispatch") {
            pendingDeeplink = .dispatchCall
        } else if lower.contains("escort") {
            pendingDeeplink = .hazmatEscort
        } else {
            pendingDeeplink = .esangChat(seed: transcript)
        }

        // Fallback: if the iPhone app is not in the foreground when the
        // wrist taps "Open on iPhone", the deeplink is invisible — the
        // sheet only presents while the scene is active. Schedule a
        // local notification so the driver gets a surface they can tap
        // to bring the app forward. The tap path is the default system
        // launch, which runs the app → EusoTripWatchBridgeModifier picks
        // up `pendingDeeplink` and presents the sheet immediately.
        presentActivationNotification(transcript: transcript)

        return ["ok": true, "reply": message["reply"] as? String ?? "Opening on your iPhone."]
    }

    /// Schedules a local notification iff the iOS app is currently
    /// backgrounded / inactive. In foreground, it's a no-op — the sheet
    /// we just set on `pendingDeeplink` will render immediately.
    private func presentActivationNotification(transcript: String) {
        guard UIApplication.shared.applicationState != .active else { return }
        // Only fire if authorization exists; don't prompt the user from
        // a wrist handoff path. Fetch `current()` inside the closure so
        // we don't capture a non-Sendable UNUserNotificationCenter across
        // the concurrency boundary (strict-concurrency warning under
        // Swift 6 / Xcode 26).
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
                    || settings.authorizationStatus == .ephemeral else { return }
            let content = UNMutableNotificationContent()
            content.title = "Open EusoTrip"
            let lower = transcript.lowercased()
            let isPlainOpen = transcript.isEmpty
                || lower.contains("open eusotrip") || lower.contains("home")
            content.body = isPlainOpen
                ? "Tap to open EusoTrip on your iPhone."
                : "From your watch: \(transcript)"
            content.sound = .default
            content.categoryIdentifier = "eusotrip.watchHandoff"
            let req = UNNotificationRequest(
                identifier: "eusotrip.watchHandoff.\(Int(Date().timeIntervalSince1970))",
                content: content,
                trigger: nil // deliver immediately
            )
            UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
        }
    }

    // MARK: - Voice (wrist → phone fallback)

    private func handleVoice(_ message: [String: Any]) async -> [String: Any] {
        guard let text = message["text"] as? String else {
            return ["ok": false, "reason": "missing text"]
        }
        // Route to esang.chat directly so the wrist gets a spoken reply
        // even if the watch couldn't reach the backend itself.
        do {
            let resp = try await api.esang.chat(
                message: text,
                currentPage: "watch",
                loadId: message["loadId"] as? String
            )
            return [
                "ok": true,
                "text": resp.message,
                "suggestions": resp.suggestions ?? []
            ]
        } catch {
            return ["ok": false, "reason": error.localizedDescription]
        }
    }

    // MARK: - SOS escalation

    private func handleSOS(_ message: [String: Any]) async -> [String: Any] {
        let reason = message["reason"] as? String ?? "driver-initiated"
        let silent = message["silent"] as? Bool ?? false
        let lat = message["lat"] as? Double
        let lon = message["lon"] as? Double

        // Forward to backend (fire-and-forget; we still want the phone
        // UI to reflect the emergency state immediately). We bypass the
        // strongly-typed eSangAPI here because the emergency router is
        // phone-only and only the wrist needs to invoke it.
        Task {
            await WatchCommandHandler.fireEmergencyMutation(
                reason: reason,
                silent: silent,
                lat: lat,
                lon: lon,
                api: api
            )
        }

        // Surface deeplink so the phone swaps to the emergency hub.
        pendingDeeplink = .emergency(reason: reason, lat: lat, lon: lon, silent: silent)

        // If not in duress mode, attempt to place an E911 call from the
        // phone — only the phone has the cellular radio + telephony.
        if !silent {
            if let url = URL(string: "tel://911") {
                await UIApplication.shared.open(url)
            }
        }

        return ["ok": true]
    }

    private func handleHOSEvent(_ message: [String: Any]) async -> [String: Any] {
        // The wrist's own direct call is best-effort only (dead zones,
        // expired wrist JWT) — this phone lane is the TRUE fallback, so
        // it must actually write the duty change, not assume the wrist
        // already did. Call the same typed API the iOS ELD surface uses,
        // then poke HOSClockService so the canonical backend view
        // re-mirrors onto the wrist within ~1s.
        let raw = (message["status"] as? String) ?? ""
        let location = (message["location"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let duty: HOSDutyCode? = {
            switch raw.lowercased() {
            case "off", "off_duty":       return .offDuty
            case "sleeper", "sb":         return .sleeperBerth
            case "driving", "d":          return .driving
            case "on_duty", "on":         return .onDuty
            default:                      return nil
            }
        }()
        if let duty {
            guard let location, !location.isEmpty else {
                return [
                    "ok": false,
                    "reason": "A current location is required before changing duty status."
                ]
            }
            do {
                _ = try await api.hos.changeStatus(
                    status: duty,
                    source: "watch",
                    location: location,
                    idempotencyKey: (message["idempotencyKey"] as? String) ?? UUID().uuidString
                )
            } catch {
                print("[WatchCommandHandler] hos.changeStatus relay failed: \(error.localizedDescription)")
                NotificationCenter.default.post(name: .esangRefreshSurface, object: nil)
                return ["ok": false, "reason": error.localizedDescription]
            }
        }
        NotificationCenter.default.post(name: .esangRefreshSurface, object: nil)
        return ["ok": duty != nil]
    }

    /// Direct URLRequest POST to `emergencyProtocols.declareEmergency` —
    /// the REAL proc (emergencyProtocols.ts:497). The previously targeted
    /// `emergencyProtocols.activate` does not exist, so every phone-side
    /// SOS escalation 404'd silently. We build the tRPC envelope by hand
    /// so we don't have to edit EusoTripAPI's typed routers just to
    /// light up the wrist's SOS path. Errors are logged loudly — an SOS
    /// that didn't reach dispatch must never look delivered.
    nonisolated static func fireEmergencyMutation(
        reason: String,
        silent: Bool,
        lat: Double?,
        lon: Double?,
        api: EusoTripAPI
    ) async {
        guard let base = await api.baseURL else { return }
        let url = base.appendingPathComponent("api/trpc/emergencyProtocols.declareEmergency")
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = await api.authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        var payload: [String: Any] = [
            "type": "security",
            "severity": "critical",
            "title": "Wrist SOS — EusoTrip Pulse",
            "description": "Driver-initiated SOS relayed by the paired iPhone. Reason: \(reason).\(silent ? " Duress mode — silent escalation." : "")",
        ]
        if let coordinate = LatLongParser.validatedCoordinate(
            latitude: lat,
            longitude: lon
        ) {
            payload["latitude"] = coordinate.latitude
            payload["longitude"] = coordinate.longitude
            payload["location"] = LatLongParser.displayString(coordinate)
        }
        let body: [String: Any] = ["json": payload]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                print("[WatchCommandHandler] SOS declareEmergency HTTP \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
            }
        } catch {
            print("[WatchCommandHandler] SOS declareEmergency failed: \(error.localizedDescription)")
        }
    }

    private func handleLoadAccept(_ message: [String: Any]) async -> [String: Any] {
        return ["ok": true]
    }

    private func handleArrived(_ message: [String: Any]) async -> [String: Any] {
        return ["ok": true]
    }
}

// MARK: - Deeplink surface

enum WatchDeeplink: Equatable {
    case wallet
    case hos
    case esangChat(seed: String)
    case maps(query: String)
    case dispatchCall
    case hazmatEscort
    case emergency(reason: String, lat: Double?, lon: Double?, silent: Bool)
}
