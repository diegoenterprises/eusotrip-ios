//
//  PushService.swift
//  EusoTrip — APNs push registration + device-token upload.
//
//  Tiny wrapper around `UNUserNotificationCenter` that:
//    • requests authorization the first time the user signs in,
//    • calls `registerForRemoteNotifications()` to get an APNs token,
//    • upserts the hex-encoded token into the backend `push_tokens`
//      table via the `notifications.registerDevice` mutation, then
//      flags the `push` preference rows active in
//      `notifications.updatePreferences` so the fan-out is permitted.
//
//  The `notifications.registerDevice` mutation is the authoritative
//  device-registration endpoint: it upserts `{token, platform, deviceName}`
//  into the per-user `push_tokens` row the server's push service reads
//  when broadcasting. We still set `x-push-token` on the shared client
//  (header path) AND flip the preference booleans, but the explicit
//  registerDevice call is what actually populates `push_tokens` so a
//  push has a destination — flipping preferences alone never did.
//
//  Everything is no-op on the simulator (APNs isn't issued there); the
//  service just stays in `.unauthorized` and the rest of the app keeps
//  working without push.
//

import Foundation
import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class PushService: NSObject, ObservableObject,
                         UNUserNotificationCenterDelegate {

    static let shared = PushService()

    /// Registration phase — published so a Settings row can reflect it
    /// live (e.g. "Push enabled ✓" / "Push denied — open Settings").
    enum Phase: Equatable {
        case unknown
        case requesting
        case authorized(deviceTokenHex: String?)
        /// Granted, but QUIETLY. Provisional notifications never reach the lock
        /// screen — no banner, no sound, no badge, Notification Center only.
        /// Kept as a distinct phase so a Settings row can say so honestly
        /// instead of showing "Push enabled ✓" over silent delivery.
        case provisionalQuiet
        case denied
        case failed(String)
    }

    @Published private(set) var phase: Phase = .unknown
    @Published private(set) var backendRegistrationError: String? = nil

    /// Hex-encoded APNs device token (64 chars). `nil` until the system
    /// delivers one (which only happens on real devices + TestFlight).
    @Published private(set) var deviceToken: String?

    // MARK: Badge

    /// Clear the app icon badge and drop delivered notifications that the user
    /// has now acted on. The server stamps `badge: 1` on every push; without
    /// this the icon shows a "1" forever, which is a count the app cannot
    /// substantiate.
    @MainActor
    static func clearBadge() {
        let center = UNUserNotificationCenter.current()
        if #available(iOS 17.0, *) {
            center.setBadgeCount(0) { err in
                if let err { print("[PushService] setBadgeCount failed: \(err.localizedDescription)") }
            }
        } else {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }

    // MARK: Notification categories
    //
    // Registered before authorization is requested so the very first delivered
    // notification already carries its buttons. `category` on the APNs payload
    // (notificationService sets it from the notification type) selects one of
    // these; an unrecognised category simply delivers with no buttons, which is
    // why the default set stays small and every id here matches a real server
    // notification type.

    static let actionView    = "EUSO_VIEW"
    static let actionSnooze  = "EUSO_SNOOZE_15"
    static let actionDone    = "EUSO_ACK"

    /// Categories whose notification is a REMINDER about a future obligation,
    /// and so can legitimately be snoozed. An alert about something that already
    /// happened cannot — snoozing it would imply the event is still pending.
    static let snoozableCategories: Set<String> = [
        "compliance_expiring", "maintenance_due", "invoice_dunning",
    ]

    static var categories: Set<UNNotificationCategory> {
        let view = UNNotificationAction(
            identifier: actionView, title: "View", options: [.foreground]
        )
        let snooze = UNNotificationAction(
            identifier: actionSnooze, title: "Remind me in 15 min", options: []
        )
        let ack = UNNotificationAction(
            identifier: actionDone, title: "Got it", options: []
        )

        // Reminders: view + snooze. Snooze reschedules the SAME content locally,
        // which is honest — it re-states a deadline the server already proved,
        // it does not invent a new one.
        let reminder = snoozableCategories.map { id in
            UNNotificationCategory(
                identifier: id, actions: [view, snooze, ack],
                intentIdentifiers: [], options: []
            )
        }

        // Events that already happened: view only. Nothing to snooze.
        let eventIds = [
            "load_update", "bid_received", "payment_received", "message",
            "geofence_alert", "weather_alert", "weather_threshold", "system",
        ]
        let events = eventIds.map { id in
            UNNotificationCategory(
                identifier: id, actions: [view],
                intentIdentifiers: [], options: []
            )
        }

        return Set(reminder + events)
    }

    // MARK: Public API

    /// Call once after a successful sign-in. Idempotent — safe to call
    /// again on subsequent boots; the system caches the APNs token.
    func bootstrap() async {
        phase = .requesting
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Register the actionable categories before asking, so the first
        // delivered notification already carries its buttons.
        center.setNotificationCategories(Self.categories)

        do {
            let settings = await center.notificationSettings()

            switch settings.authorizationStatus {
            case .denied:
                // Asking again is a no-op once denied; only Settings can undo it.
                phase = .denied
                return

            case .authorized, .ephemeral:
                break

            case .provisional:
                // PROVISIONAL IS QUIET. iOS grants it with no prompt and then
                // delivers every notification straight to Notification Center —
                // no lock-screen banner, no sound, no badge. Requesting the full
                // option set here is the documented way to promote it, and it
                // does show the real prompt.
                let promoted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                if !promoted {
                    // Still provisional: the token is valid and silent delivery
                    // continues, so keep registering — but never report this as
                    // working push.
                    phase = .provisionalQuiet
                    await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
                    return
                }

            case .notDetermined:
                // Full authorization ONLY. `.provisional` in this option set is
                // what silenced every notification this app has ever sent: it
                // suppresses the prompt, returns granted == true, and then
                // delivers quietly forever.
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                guard granted else {
                    phase = .denied
                    return
                }

            @unknown default:
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                guard granted else {
                    phase = .denied
                    return
                }
            }

            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Called by the AppDelegate shim when APNs delivers a token.
    func didRegister(deviceToken data: Data) {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        self.deviceToken = hex
        // Do NOT promote provisionalQuiet to authorized just because a token
        // arrived. A provisional grant still yields a perfectly valid APNs
        // token — the difference is that iOS delivers QUIETLY, to Notification
        // Center only, never the lock screen. Overwriting the phase here made
        // the whole provisional-honesty state dead on arrival: bootstrap would
        // correctly detect quiet delivery, then this line would report "Push
        // enabled" moments later, and the four MeNotificationsView cases that
        // exist to say "Quiet only" became unreachable.
        if case .provisionalQuiet = self.phase {
            // keep it — the token is recorded above, the honesty is preserved
        } else {
            self.phase = .authorized(deviceTokenHex: hex)
        }

        // Wire the token into the shared API client so every
        // authenticated request includes the `x-push-token` header
        // the backend reads to register the device. Was previously
        // held only on PushService and never reached the wire.
        EusoTripAPI.shared.pushDeviceToken = hex

        // Upsert the APNs device token into the backend `push_tokens`
        // table via the first-class `notifications.registerDevice`
        // mutation, then flag the push preference rows active. Without
        // the registerDevice call the table stays empty and the push
        // fan-out has no token to deliver to — flipping the preference
        // boolean alone is not enough. A backend registration failure
        // must never crash or revoke the APNs authorization, but it is
        // surfaced through `backendRegistrationError` so Settings can
        // distinguish "iOS allowed push" from "server fan-out ready."
        let deviceName = UIDevice.current.model
        Task { [weak self] in
            guard let self else { return }
            let api = EusoTripAPI.shared

            // Register the device token in `push_tokens`. Fire-and-forget.
            struct RegisterDeviceInput: Encodable {
                let token: String
                let platform: String
                let deviceName: String?
            }
            struct RegisterDeviceAck: Decodable { let success: Bool?; let registered: Bool? }
            do {
                let ack: RegisterDeviceAck = try await api.mutation(
                    "notifications.registerDevice",
                    input: RegisterDeviceInput(
                        token: hex, platform: "ios", deviceName: deviceName
                    )
                )
                guard ack.success != false, ack.registered != false else {
                    self.backendRegistrationError = "Push permission is enabled, but the device token was not accepted by the server."
                    return
                }
                _ = try await api.notifications.updatePreferences(
                    channel: "push", category: "loads",  enabled: true
                )
                _ = try await api.notifications.updatePreferences(
                    channel: "push", category: "safety", enabled: true
                )
                _ = try await api.notifications.updatePreferences(
                    channel: "push", category: "system", enabled: true
                )
                self.backendRegistrationError = nil
            } catch {
                self.backendRegistrationError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
            #if DEBUG
            print("[PushService] registered device + flagged push preferences active")
            #endif
        }
    }

    /// Called when APNs fails to issue a token (e.g. simulator).
    func didFailToRegister(error: Error) {
        self.phase = .failed(error.localizedDescription)
        #if DEBUG
        print("[PushService] APNs registration failed: \(error.localizedDescription)")
        #endif
    }

    // MARK: UNUserNotificationCenterDelegate — foreground delivery

    /// Show banner/sound even when the app is in the foreground so
    /// driver-facing alerts (load assigned, dispatch update, HOS warning)
    /// don't get silently swallowed.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    /// Handle taps on a delivered notification. Payload `userInfo` shape
    /// from the backend push service:
    ///   { type: "load_assigned" | "hos_warning" | "dispatch_msg" | …,
    ///     loadId: 1234, route: "eld" | "fleet" | "earnings" | … }
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let route = info["route"] as? String
        let action = response.actionIdentifier
        let content = response.notification.request.content

        // "Remind me in 15 min" — reschedule the SAME content locally. This is
        // honest: it restates a deadline the server already proved rather than
        // inventing a new one, and it is only offered on categories that are
        // genuinely about a future obligation (see snoozableCategories).
        if action == PushService.actionSnooze {
            let copy = UNMutableNotificationContent()
            copy.title = content.title
            copy.body = content.body
            copy.sound = content.sound
            copy.userInfo = content.userInfo
            copy.categoryIdentifier = content.categoryIdentifier
            copy.threadIdentifier = content.threadIdentifier
            let req = UNNotificationRequest(
                // Deterministic id keyed on the original request: snoozing the
                // same reminder twice replaces it instead of stacking duplicates.
                identifier: "snooze:\(response.notification.request.identifier)",
                content: copy,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)
            )
            center.add(req) { err in
                if let err { print("[PushService] snooze reschedule failed: \(err.localizedDescription)") }
            }
            completionHandler()
            return
        }

        // "Got it" — acknowledge without navigating anywhere.
        if action == PushService.actionDone {
            Task { @MainActor in
                PushService.clearBadge()
                completionHandler()
            }
            return
        }

        Task { @MainActor in
            // A tap means the user has seen it. The server sets badge: 1 on every
            // push and nothing on the device ever cleared it, so the icon carried
            // a permanent, unprovable "1".
            PushService.clearBadge()
            // Messaging deep-link — route through the top-bar chat glyph
            // so tapping the push lands the driver on the right thread.
            PushService.shared.handleIncomingPayload(info)
            if let route {
                // Reuse the existing eSang Me-tab-detail notification so
                // the routing hop for push deep links matches the voice
                // autopilot path.
                NotificationCenter.default.post(
                    name: .esangOpenMeDetail,
                    object: route
                )
            }
            // Also request a surface refresh so the Home tab re-pulls
            // loads on any push that could have mutated server state.
            NotificationCenter.default.post(
                name: .esangRefreshSurface,
                object: nil
            )
            completionHandler()
        }
    }

    // MARK: - Background push routing
    //
    // Messaging parity requirement: the driver must keep receiving
    // messages even when they're not in the app — asleep, phone locked,
    // app suspended. iOS backgrounds the WebSocket after ~30s of no UI
    // activity, so APNs is the fallback channel. The backend fans out a
    // push with `type: "message_new"` on every inbound message; this
    // routine runs both from the tap handler and from the silent
    // background `application(_:didReceiveRemoteNotification:)`
    // delegate, so UnreadMessageStore stays accurate regardless of how
    // the payload reaches us — and WatchAuthBridge then mirrors the
    // count to the wrist so Pulse Watch shows the badge without the
    // phone app needing to be active.

    /// Fold a push payload (foreground, background, or tap) into the
    /// shared stores that drive the top-bar chat glyph on iOS and the
    /// Inbox tab badge on Pulse Watch. Safe to call with any payload;
    /// non-message types short-circuit.
    func handleIncomingPayload(_ userInfo: [AnyHashable: Any]) {
        // The server pushing anything is a decent hint that something moved,
        // and this is the one funnel every arriving push passes through (tap
        // handler + silent background wake). Throttled inside the service, a
        // no-op while signed out, and — by the cancellation rule — incapable
        // of removing a scheduled reminder unless the server proves it is gone.
        ReminderSyncService.shared.handleRemotePush()

        let type = (userInfo["type"] as? String)?.lowercased() ?? ""
        let isMessage = type == "message_new"
            || type == "message:new"
            || type == "new_message"
            || userInfo["conversationId"] != nil
            || userInfo["message"] != nil
        guard isMessage else { return }

        // Forward to any on-screen conversation view that's listening —
        // DriverConversationView dedupes by serverId. Key names mirror
        // the WebSocket payload so both fan-outs share one handler.
        var info: [AnyHashable: Any] = userInfo
        if let nested = userInfo["message"] as? [AnyHashable: Any] {
            for (k, v) in nested where info[k] == nil { info[k] = v }
        }
        NotificationCenter.default.post(
            name: .eusoMessageReceived,
            object: nil,
            userInfo: info
        )

        // Pull the authoritative total from the backend — safer than
        // local increments because a single push can represent multiple
        // fan-outs that collapsed in the APNs queue.
        UnreadMessageStore.shared.refresh()
    }

    /// Called from the AppDelegate's silent-push handler. Returns the
    /// completion-handler `UIBackgroundFetchResult` the system needs to
    /// decide how generous to be with future background slots.
    func handleBackgroundRemoteNotification(
        _ userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        handleIncomingPayload(userInfo)
        // Give UnreadMessageStore's in-flight refetch a short window to
        // land before we report back to iOS. The store coalesces, so
        // this is bounded regardless of how many pushes arrive at once.
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        return .newData
    }
}

// MARK: - AppDelegate adaptor (APNs bridge for SwiftUI)

/// SwiftUI apps don't own a `UIApplicationDelegate` by default; the
/// `@UIApplicationDelegateAdaptor` property wrapper in `EusoTripApp`
/// plugs this class in so we can receive the APNs callbacks.
final class EusoTripAppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
            [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = PushService.shared
        // Install the WCSession delegate on EVERY process launch —
        // including WatchConnectivity background wakes where no scene
        // ever renders. Without this, a killed iPhone app woken by the
        // wrist's sendMessage never installed a delegate, the message
        // timed out, and the watch's 30s auth-bootstrap poll exhausted
        // ("watch not connected to the app"). activate() is idempotent,
        // so every existing lazy call site simply becomes a no-op.
        Task { @MainActor in
            WatchAuthBridge.shared.activate()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushService.shared.didRegister(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushService.shared.didFailToRegister(error: error)
        }
    }

    /// Silent-push entry point.
    ///
    /// iOS delivers `content-available: 1` APNs pushes here even when the
    /// app is suspended or outright killed — the system wakes us for up to
    /// 30 seconds, which is plenty of time to refresh the unread store,
    /// fan the payload out over `.eusoMessageReceived`, and let the
    /// `WatchAuthBridge.pushUnreadCount` realtime observer mirror the new
    /// badge to the wrist. This is the channel that keeps Pulse Watch
    /// messaging alive when the driver is asleep with the phone on the
    /// nightstand and the Socket.IO connection has long since been
    /// suspended by iOS's 30-second foreground-only WebSocket budget.
    ///
    /// We MUST call the fetch completion handler within the 30-second
    /// window or iOS will penalize our future background-delivery budget,
    /// so `handleBackgroundRemoteNotification` bounds its own refresh
    /// wait at 1.5s and returns `.newData`.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler:
            @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            let result = await PushService.shared
                .handleBackgroundRemoteNotification(userInfo)
            completionHandler(result)
        }
    }
}
