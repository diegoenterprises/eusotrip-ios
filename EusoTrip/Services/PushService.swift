//
//  PushService.swift
//  EusoTrip — APNs push registration + device-token upload.
//
//  Tiny wrapper around `UNUserNotificationCenter` that:
//    • requests authorization the first time the user signs in,
//    • calls `registerForRemoteNotifications()` to get an APNs token,
//    • hands the hex-encoded token up to the backend by flipping the
//      `push` channel on in `notifications.updatePreferences` (the
//      backend wires the current user's device token at the same moment
//      via the existing push-service layer — see `server/routers/push.ts`).
//
//  Why this exists at all: the tRPC catalog does not yet expose a
//  dedicated `notifications.registerDevice` mutation, but the server's
//  push service does read from the per-user `pushTokens` table when
//  broadcasting, and it upserts that row whenever a client hits the
//  push-settings surface while authenticated. Until a first-class device
//  registration endpoint ships, calling `notifications.updatePreferences`
//  with `{channel:"push", category:"loads", enabled:true}` on the same
//  session is enough to flag the row active — the token itself is
//  captured server-side from the `x-push-token` header when present.
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
        case denied
        case failed(String)
    }

    @Published private(set) var phase: Phase = .unknown

    /// Hex-encoded APNs device token (64 chars). `nil` until the system
    /// delivers one (which only happens on real devices + TestFlight).
    @Published private(set) var deviceToken: String?

    // MARK: Public API

    /// Call once after a successful sign-in. Idempotent — safe to call
    /// again on subsequent boots; the system caches the APNs token.
    func bootstrap() async {
        phase = .requesting
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        do {
            let granted = try await center.requestAuthorization(
                options: [.alert, .badge, .sound, .provisional]
            )
            guard granted else {
                phase = .denied
                return
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
        self.phase = .authorized(deviceTokenHex: hex)

        // Wire the token into the shared API client so every
        // authenticated request includes the `x-push-token` header
        // the backend reads to register the device. Was previously
        // held only on PushService and never reached the wire.
        EusoTripAPI.shared.pushDeviceToken = hex

        // Flag the push row active on the backend. The server reads
        // the `x-push-token` header out-of-band; tRPC body just toggles
        // the preference boolean. Best-effort — failure leaves the
        // local phase `.authorized` so the UI still shows it worked.
        Task { [weak self] in
            guard let self else { return }
            let api = EusoTripAPI.shared
            _ = try? await api.notifications.updatePreferences(
                channel: "push", category: "loads",  enabled: true
            )
            _ = try? await api.notifications.updatePreferences(
                channel: "push", category: "safety", enabled: true
            )
            _ = try? await api.notifications.updatePreferences(
                channel: "push", category: "system", enabled: true
            )
            #if DEBUG
            print("[PushService] flagged push preferences active · token=\(self.deviceToken?.prefix(8) ?? "<nil>")…")
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
        Task { @MainActor in
            // Messaging deep-link — route through the top-bar chat glyph
            // so tapping the push lands the driver on the right thread.
            PushService.shared.handleIncomingPayload(info)
            if let route {
                // Reuse the existing ESang Me-tab-detail notification so
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
