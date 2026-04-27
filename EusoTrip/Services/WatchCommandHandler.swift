//
//  WatchCommandHandler.swift
//  EusoTrip
//
//  Processes watch-side commands sent via WCSession. Three categories:
//
//    1. activation  — "open on iPhone" hand-off (opens Maps, Esang chat,
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

    /// Toast-ish banner the iOS app can show ("Esang is on the wrist…").
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
        // Crude but effective allowlist — anything matching a typical
        // query proc name gets through; mutations (submit, accept,
        // delete, create, update, mark) are rejected.
        let lastSegment = path.split(separator: ".").last.map(String.init) ?? path
        let allowedPrefixes = ["get", "list", "search", "fetch", "query", "find", "summary"]
        let lower = lastSegment.lowercased()
        let allowed = allowedPrefixes.contains { lower.hasPrefix($0) }
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
    /// Esang chat has the latest exchange preloaded if the driver taps through.
    private func handleExchange(_ message: [String: Any]) async -> [String: Any] {
        lastWatchTranscript = message["transcript"] as? String
        // Don't force a deeplink — the wrist already spoke the reply.
        // Just notify realtime surface so any open iOS view can refresh.
        NotificationCenter.default.post(name: .esangRefreshSurface, object: nil)
        return ["ok": true]
    }

    // MARK: - Activation (open-on-phone hand-off)

    private func handleActivation(_ message: [String: Any]) async -> [String: Any] {
        let transcript = message["transcript"] as? String ?? ""
        lastWatchTranscript = transcript

        // Very lightweight intent routing — the watch gives us a hint in
        // `transcript`, we pick a deeplink. Full Gemini routing happens
        // only if the user explicitly opens Esang chat on the phone.
        let lower = transcript.lowercased()
        if lower.contains("wallet") {
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
            content.title = "EusoTrip"
            content.body = transcript.isEmpty
                ? "Your Apple Watch asked to continue here."
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
        // strongly-typed ESangAPI here because the emergency router is
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
        // The wrist already wrote hos.changeStatus optimistically and the
        // server reflects it in `hos.getStatus`. Trigger an immediate
        // HOSClockService poll so the phone's published status catches
        // up and — crucially — so pushToWatch fires, re-mirroring the
        // canonical backend view back onto the wrist within ~1s instead
        // of the next 5-min tick.
        NotificationCenter.default.post(name: .esangRefreshSurface, object: nil)
        return ["ok": true]
    }

    /// Direct URLRequest POST to `emergencyProtocols.activate`. We build
    /// the tRPC envelope by hand so we don't have to edit EusoTripAPI's
    /// typed routers just to light up the wrist's SOS path.
    nonisolated static func fireEmergencyMutation(
        reason: String,
        silent: Bool,
        lat: Double?,
        lon: Double?,
        api: EusoTripAPI
    ) async {
        guard let base = await api.baseURL else { return }
        let url = base.appendingPathComponent("api/trpc/emergencyProtocols.activate")
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = await api.authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        var payload: [String: Any] = [
            "reason": reason,
            "silent": silent,
            "source": "watch"
        ]
        if let lat { payload["lat"] = lat }
        if let lon { payload["lon"] = lon }
        let body: [String: Any] = ["json": payload]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
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
