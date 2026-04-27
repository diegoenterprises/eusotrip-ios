//
//  WatchAuthBridge.swift
//  EusoTrip
//
//  Pushes auth state from the iOS app to the Apple Watch companion app
//  via WCSession.updateApplicationContext. The watch never collects
//  credentials — it only mirrors whatever the phone already signed in
//  with. When the phone signs out, we clear the watch's context too.
//
//  Paired with `AuthStore.update(token:userId:userName:role:)` on the
//  watch side (see EusoTrip Watch App/AuthStore.swift).
//

import Foundation
import WatchConnectivity

@MainActor
final class WatchAuthBridge: NSObject {
    static let shared = WatchAuthBridge()

    private var session: WCSession? {
        guard WCSession.isSupported() else { return nil }
        return WCSession.default
    }

    private override init() {
        super.init()
        activate()
    }

    func activate() {
        guard let session else { return }
        if session.delegate == nil {
            session.delegate = SessionDelegate.shared
        }
        if session.activationState != .activated {
            session.activate()
        }
    }

    /// Last auth snapshot we pushed. Kept so that (a) when the watch
    /// comes into range mid-session we can re-mirror without needing
    /// EusoTripSession to re-call push, and (b) when the watch sends an
    /// `auth.request` op we can answer immediately.
    private var cachedAuth: [String: Any]?

    /// Public getter so WatchCommandHandler can answer `auth.request`.
    var lastPushedAuthContext: [String: Any]? { cachedAuth }

    /// Persistent UserDefaults key for the last successful auth-mirror
    /// delivery timestamp. `cachedAuth` is in-memory only — it's nil on
    /// cold launch and on demo sign-in paths that bypass `push()`, which
    /// used to leave the Me-tab "Last auth sync" row showing "—" even
    /// when the wrist had been receiving auth updates fine. Persisting
    /// the timestamp means the row can surface the last known sync
    /// across app restarts without needing the in-memory context.
    private let lastSyncDefaultsKey = "watch_auth_bridge_last_sync_at"

    /// Timestamp of the most recent auth context that was actually
    /// handed to WCSession. Written whenever `push`, `republishAuth`, or
    /// the watch-initiated `auth.request` answer path succeeds. Read by
    /// the iPhone Pulse Settings screen to populate the
    /// "Last auth sync" row.
    var lastSuccessfulSyncAt: Date? {
        get {
            let ts = UserDefaults.standard.double(forKey: lastSyncDefaultsKey)
            return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        }
        set {
            if let date = newValue {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastSyncDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastSyncDefaultsKey)
            }
        }
    }

    /// Stamp a successful delivery. Called from every code path that
    /// actually hands a payload to WCSession so the persistent row can
    /// show the driver when the wrist was last informed.
    private func markSynced() {
        lastSuccessfulSyncAt = Date()
    }

    /// Called from EusoTripSession.signIn / boot once the phone has a
    /// valid bearer token + AuthUser record.
    func push(token: String, userId: String, userName: String?, role: String? = "driver") {
        activate()
        guard let session else { return }
        let context: [String: Any] = [
            "op": "auth.update",
            "token": token,
            "userId": userId,
            "userName": userName ?? "",
            "role": role ?? "driver",
            "ts": Date().timeIntervalSince1970
        ]
        cachedAuth = context
        try? session.updateApplicationContext(context)
        // Also fire as a transient message so the watch gets it even if
        // it missed the context update while asleep. If the live link
        // isn't up, queue via transferUserInfo so the wrist still picks
        // it up on the next activation — without this, first-launch
        // pairing relied on `isReachable` being true at the exact
        // moment of sign-in, which it usually isn't.
        if session.isReachable {
            session.sendMessage(context, replyHandler: nil) { _ in }
        } else {
            session.transferUserInfo(context)
        }
        markSynced()
    }

    /// Called from EusoTripSession.signOut. Sends a clear op so the
    /// watch wipes its Keychain entries.
    func clear() {
        guard let session else { return }
        let context: [String: Any] = [
            "op": "auth.update",
            "token": "",
            "userId": "",
            "userName": "",
            "role": "",
            "clear": true,
            "ts": Date().timeIntervalSince1970
        ]
        cachedAuth = nil
        try? session.updateApplicationContext(context)
        if session.isReachable {
            session.sendMessage(context, replyHandler: nil) { _ in }
        } else {
            session.transferUserInfo(context)
        }
    }

    /// Re-send the last-known auth context. Triggered by
    /// (a) the watch coming into range (WCSessionDelegate
    /// `sessionReachabilityDidChange` below), (b) the watch explicitly
    /// asking via `auth.request`, and (c) the driver tapping Resync on
    /// the Me-tab Pulse card. Returns `true` if a payload actually went
    /// out so the caller can decide whether "Last auth sync" should
    /// update.
    ///
    /// The `fallback` params let the Me-tab Resync button push from the
    /// live EusoTripSession even if `push()` was never called this run.
    /// That was the silent-fail case for the demo sign-in path and for
    /// cold-launch-before-boot() — `cachedAuth` was nil, so Resync
    /// no-op'd while the UI optimistically reset "Last auth sync" to
    /// "in 0 sec" anyway, leaving the wrist stuck on the pairing hint.
    @discardableResult
    func republishAuth(fallbackToken: String? = nil,
                       fallbackUserId: String? = nil,
                       fallbackUserName: String? = nil,
                       fallbackRole: String? = nil) -> Bool {
        guard let session else { return false }
        let ctx: [String: Any]?
        if let existing = cachedAuth {
            ctx = existing
        } else if let fallbackToken, !fallbackToken.isEmpty {
            ctx = [
                "op": "auth.update",
                "token": fallbackToken,
                "userId": fallbackUserId ?? "",
                "userName": fallbackUserName ?? "",
                "role": fallbackRole ?? "driver",
                "ts": Date().timeIntervalSince1970
            ]
        } else {
            ctx = nil
        }
        guard let ctx else { return false }
        cachedAuth = ctx
        try? session.updateApplicationContext(ctx)
        if session.isReachable {
            session.sendMessage(ctx, replyHandler: nil) { _ in }
        } else {
            // Reachability is a live-link concept. When the watch app
            // isn't in the foreground, sendMessage would fail with
            // `notReachable` — transferUserInfo queues the payload so
            // the watch receives it whenever it next activates.
            session.transferUserInfo(ctx)
        }
        markSynced()
        return true
    }

    /// Called when the active load changes on the phone so the watch
    /// has it cached offline. Snapshot shape matches WatchLoad on the
    /// wrist side (see LoadStore.applyRemote). The watch receiver reads
    /// `ctx["load"]` as a nested dict, so we wrap the snapshot here —
    /// flattening it at the top level would silently drop on the wrist.
    func pushActiveLoad(_ snapshot: [String: Any]?) {
        guard let session else { return }
        cachedLoadSnapshot = snapshot  // retained so realtime re-push works
        let ctx: [String: Any] = [
            "op": "load.active",
            "load": snapshot ?? [:],
            "cleared": (snapshot == nil),
            "ts": Date().timeIntervalSince1970
        ]
        try? session.updateApplicationContext(ctx)
        if session.isReachable {
            session.sendMessage(ctx, replyHandler: nil) { _ in }
        }
    }

    /// Called when the driver flips HOS on the phone (or the ELD does).
    /// Key names match `WatchConnectivityManager.applyContext` on the
    /// wrist — `driveRemainingMinutes` / `windowRemainingMinutes` /
    /// `cycleRemainingMinutes`. The `status` string is normalized to the
    /// watch-side enum (off / sleeper / driving / on_duty) since the
    /// iOS `hos.getStatus` payload uses "off_duty" for off-duty.
    func pushHOSUpdate(status: String, driveRemainingMinutes: Int?, windowRemainingMinutes: Int?, cycleRemainingMinutes: Int?) {
        guard let session else { return }
        let normalized = Self.normalizeHOSStatus(status)
        var ctx: [String: Any] = [
            "op": "hos.update",
            "status": normalized,
            "ts": Date().timeIntervalSince1970
        ]
        if let v = driveRemainingMinutes  { ctx["driveRemainingMinutes"]  = v }
        if let v = windowRemainingMinutes { ctx["windowRemainingMinutes"] = v }
        if let v = cycleRemainingMinutes  { ctx["cycleRemainingMinutes"]  = v }
        cachedHOSSnapshot = ctx
        try? session.updateApplicationContext(ctx)
        if session.isReachable {
            session.sendMessage(ctx, replyHandler: nil) { _ in }
        }
    }

    /// Relay a realtime event the iPhone received over its WebSocket
    /// (bid awards, settlement payments, document uploads, etc.) to
    /// the paired watch via WCSession applicationContext + sendMessage.
    /// The watch's `WatchConnectivityManager.applyContext` routes the
    /// payload by `op` field. No-op when no watch is paired.
    func relayRealtimeEvent(_ payload: [String: Any]) {
        guard let session else { return }
        try? session.updateApplicationContext(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in }
        } else {
            session.transferUserInfo(payload)
        }
    }

    /// Push the aggregate unread-message total to the watch so the
    /// wrist-side Inbox tab can render a parity badge that matches the
    /// phone's top-bar chat glyph. We snapshot the full per-conversation
    /// map too so the watch's inbox list can show a dot on the right
    /// rows even when it's offline. The watch receiver interprets the
    /// `messaging.unread` op (see `WatchConnectivityManager.applyContext`).
    func pushUnreadCount(total: Int, byConversation: [String: Int]) {
        guard let session else { return }
        let ctx: [String: Any] = [
            "op": "messaging.unread",
            "total": total,
            "byConversation": byConversation,
            "ts": Date().timeIntervalSince1970
        ]
        cachedUnreadSnapshot = ctx
        try? session.updateApplicationContext(ctx)
        if session.isReachable {
            session.sendMessage(ctx, replyHandler: nil) { _ in }
        }
    }

    // MARK: - Realtime fan-out
    //
    // RealtimeService dispatches `.esangRefreshSurface` whenever the
    // Socket.IO stream receives LOAD_STATE_CHANGED, LOAD_ASSIGNED,
    // LOAD_UPDATED, HOS_WARNING, etc. We re-send the last-known HOS +
    // load snapshots so the watch sees server-originated changes within
    // a second instead of waiting for the next 5-min HOSClock poll or
    // the next time the driver opens the iOS app.

    private var cachedLoadSnapshot: [String: Any]?
    private var cachedHOSSnapshot:  [String: Any]?
    private var cachedUnreadSnapshot: [String: Any]?
    private var realtimeObservers: [NSObjectProtocol] = []

    func startRealtimeBridge() {
        guard realtimeObservers.isEmpty else { return }
        let center = NotificationCenter.default
        realtimeObservers.append(
            center.addObserver(forName: .esangRefreshSurface, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.rebroadcast() }
            }
        )
        // Mirror the phone's `UnreadMessageStore` to the wrist whenever
        // the aggregate count changes — the watch inbox tab needs the
        // same number as the top-bar chat glyph, and the user can only
        // see parity if the two surfaces update together.
        realtimeObservers.append(
            center.addObserver(forName: .eusoUnreadCountChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.pushUnreadCount(
                        total: UnreadMessageStore.shared.total,
                        byConversation: UnreadMessageStore.shared.byConversation
                    )
                }
            }
        )
    }

    func stopRealtimeBridge() {
        for obs in realtimeObservers { NotificationCenter.default.removeObserver(obs) }
        realtimeObservers.removeAll()
    }

    /// Re-push the cached HOS + load context. The watch's
    /// `applyContext` is idempotent, so a stray duplicate is harmless.
    private func rebroadcast() {
        guard let session, session.activationState == .activated else { return }
        if let ctx = cachedHOSSnapshot {
            try? session.updateApplicationContext(ctx)
            if session.isReachable {
                session.sendMessage(ctx, replyHandler: nil) { _ in }
            }
        }
        if let snapshot = cachedLoadSnapshot {
            let ctx: [String: Any] = [
                "op": "load.active",
                "load": snapshot,
                "cleared": false,
                "ts": Date().timeIntervalSince1970
            ]
            try? session.updateApplicationContext(ctx)
            if session.isReachable {
                session.sendMessage(ctx, replyHandler: nil) { _ in }
            }
        }
        if let ctx = cachedUnreadSnapshot {
            try? session.updateApplicationContext(ctx)
            if session.isReachable {
                session.sendMessage(ctx, replyHandler: nil) { _ in }
            }
        }
    }

    /// iOS `hos.getStatus` reports "off_duty"; the watch enum expects
    /// "off". Normalize once here so every call site doesn't have to.
    private static func normalizeHOSStatus(_ raw: String) -> String {
        switch raw.lowercased() {
        case "off_duty", "offduty", "off":       return "off"
        case "sleeper", "sleeper_berth", "sb":   return "sleeper"
        case "driving", "drive", "dr":           return "driving"
        case "on_duty", "onduty", "on":          return "on_duty"
        default:                                  return "off"
        }
    }

    // MARK: - Pulse settings propagation
    //
    // Mirror user-toggled preferences down to the wrist so the watch
    // honors the phone's choices immediately (no relaunch needed).
    // Keys match what the watch-side settings observer reads from
    // applicationContext["pulseSettings"]. Unknown keys are ignored
    // wrist-side, so we can grow this without a watchOS migration.

    /// Canonical live-state snapshot of WCSession useful for the
    /// iPhone Pulse Settings screen. Pair status + reachability are
    /// different things — a paired watch is a hardware fact; a
    /// reachable watch also has the app in the foreground or
    /// background awakening. The UI distinguishes both.
    struct PairStatus {
        let activated: Bool
        let paired: Bool
        let watchAppInstalled: Bool
        let reachable: Bool
    }

    var pairStatus: PairStatus {
        guard let session else {
            return PairStatus(activated: false, paired: false, watchAppInstalled: false, reachable: false)
        }
        return PairStatus(
            activated: session.activationState == .activated,
            paired: session.isPaired,
            watchAppInstalled: session.isWatchAppInstalled,
            reachable: session.isReachable
        )
    }

    /// Push a settings-update context to the wrist. Persists on the
    /// phone in UserDefaults too so re-opening the Settings sheet
    /// shows the current state without a round-trip.
    func pushSettings(_ settings: [String: Any]) {
        UserDefaults.standard.set(settings, forKey: Self.pulseSettingsDefaultsKey)
        guard let session else { return }
        let ctx: [String: Any] = [
            "op": "settings.update",
            "pulseSettings": settings,
            "ts": Date().timeIntervalSince1970,
        ]
        try? session.updateApplicationContext(ctx)
        if session.isReachable {
            session.sendMessage(ctx, replyHandler: nil) { _ in }
        } else {
            session.transferUserInfo(ctx)
        }
        markSynced()
    }

    /// Read current Pulse settings snapshot. Defaults are intentionally
    /// wrist-friendly (haptics on, turn-by-turn on, voice wake off
    /// until the driver opts in).
    func currentSettings() -> [String: Any] {
        (UserDefaults.standard.dictionary(forKey: Self.pulseSettingsDefaultsKey)
            ?? Self.defaultPulseSettings)
    }

    private static let pulseSettingsDefaultsKey = "watch_pulse_settings_v1"

    static let defaultPulseSettings: [String: Any] = [
        "hapticsIntensity": "standard",     // "light" | "standard" | "strong"
        "turnByTurn": true,                  // when load is active
        "voiceWakeWord": false,              // "Hey ESANG" always-listen
        "drivingAutoDetect": true,           // auto-kick trip mode
        "complicationStyle": "orb",          // "orb" | "numeric" | "hos"
    ]
}

// MARK: - WCSession delegate shell
//
// The heavy lifting (message routing) lives in WatchCommandHandler. We
// keep the delegate here as a thin dispatcher so any file can activate
// the session without clobbering another's delegate.

private final class SessionDelegate: NSObject, WCSessionDelegate {
    static let shared = SessionDelegate()

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("[WatchAuthBridge] WCSession activate error: \(error.localizedDescription)")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate for the next paired watch.
        WCSession.default.activate()
    }

    /// Watch just came into range (or went out). When it becomes
    /// reachable, re-mirror the current auth context so the wrist can
    /// swap off its "Open EusoTrip on iPhone to pair" hint immediately.
    /// Also passes the live `EusoTripAPI.authToken` as fallback so a
    /// cold-launched phone (where `push(...)` hasn't run yet) still
    /// answers the watch's first auth-mirror request — without this,
    /// the wrist sat on "sign in on iPhone" until the next iOS app
    /// foreground bumped `push(...)`.
    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in
            WatchAuthBridge.shared.republishAuth(
                fallbackToken: EusoTripAPI.shared.authToken
            )
        }
    }

    // Watch → phone message — forward to the dedicated handler.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            let reply = await WatchCommandHandler.shared.handle(message)
            replyHandler(reply)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            _ = await WatchCommandHandler.shared.handle(message)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            _ = await WatchCommandHandler.shared.handle(userInfo)
        }
    }
}
