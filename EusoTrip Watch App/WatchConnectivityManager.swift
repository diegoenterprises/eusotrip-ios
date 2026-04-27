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

final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var isReachable: Bool = false
    @Published var isActivated: Bool = false

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
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
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isActivated = state == .activated
            self.isReachable = session.isReachable
            self.applyContext(session.receivedApplicationContext)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.isReachable = session.isReachable }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { self.applyContext(applicationContext) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { self.applyContext(message) }
    }

    private func applyContext(_ ctx: [String: Any]) {
        guard let op = ctx["op"] as? String else { return }
        switch op {
        case "auth.update":
            Task { @MainActor in
                AuthStore.shared?.update(
                    token: ctx["token"] as? String,
                    userId: ctx["userId"] as? String,
                    userName: ctx["userName"] as? String,
                    role: ctx["role"] as? String
                )
            }
        case "load.active":
            Task { @MainActor in
                if let json = ctx["load"] as? [String: Any] {
                    LoadStore.shared.applyRemote(json: json)
                }
            }
        case "hos.update":
            Task { @MainActor in
                HOSStore.shared.applyRemote(
                    status: ctx["status"] as? String ?? "off",
                    driveRemainingMinutes: ctx["driveRemainingMinutes"] as? Int ?? 0,
                    windowRemainingMinutes: ctx["windowRemainingMinutes"] as? Int ?? 0
                )
            }
        default:
            break
        }
    }
}
