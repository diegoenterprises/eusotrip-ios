//
//  EusoTripApp.swift
//  EusoTrip
//
//  EusoTrip by Eusorone Technologies, Inc.
//  Powered by ESANG AI™
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@main
struct EusoTripApp: App {
    /// AppDelegate adaptor — SwiftUI needs this to receive APNs
    /// `didRegisterForRemoteNotificationsWithDeviceToken` callbacks.
    @UIApplicationDelegateAdaptor(EusoTripAppDelegate.self) private var appDelegate

    /// Universal keyboard dismiss-on-swipe (founder bug 2026-05-23 —
    /// keyboard would appear and get stuck on screen on every form,
    /// blocking the screen even when the user no longer needed to
    /// type). Setting `keyboardDismissMode = .interactive` on the
    /// UIScrollView appearance proxy propagates to every
    /// UIScrollView-backed surface: SwiftUI ScrollView, List, Form,
    /// TableView, plus any UIKit-backed inputs. Swiping down on the
    /// keyboard now follows the finger and dismisses, matching
    /// system Messages / Mail behavior.
    ///
    /// Guarded with `#if canImport(UIKit)` so the same struct still
    /// compiles for the watchOS target (which doesn't ship UIKit).
    init() {
        #if canImport(UIKit)
        UIScrollView.appearance().keyboardDismissMode = .interactive
        #endif
    }

    @StateObject private var session = EusoTripSession()
    /// Session-scoped driver profile (name / email / CDL / phone / avatar).
    /// Injected here so Home greeting, Me tab header, and Settings ACCOUNT
    /// card all read from a single source of truth and ProfileEditView
    /// writes propagate everywhere the moment the user taps Save.
    @StateObject private var profile = DriverProfileStore()
    /// Shared push service — exposes APNs phase + device token. Stays
    /// `.unknown` on simulator; auto-bootstraps once signed in on device.
    @StateObject private var push = PushService.shared
    /// Shared realtime service — connects to /ws after sign-in, broadcasts
    /// live LOAD_STATE_CHANGED + dispatch events via NotificationCenter.
    @StateObject private var realtime = RealtimeService.shared
    /// Shared geofence observer — watches pickup + delivery regions,
    /// drives `TripEvent.geofenceEntered` into `DriverTripController`.
    @StateObject private var geo = GeofenceService.shared
    /// Shared HOS observer — polls `hos.getStatus` on a slow timer and
    /// fires `TripEvent.hosLimitApproached` when drive time nears 11h.
    @StateObject private var hos = HOSClockService.shared
    /// Gates AppRoot behind the branded Lottie intro on cold launch.
    @State private var introFinished = false
    /// True while the app is in `.inactive` / `.background` so the
    /// app-switcher snapshot iOS captures shows the brand splash
    /// instead of the live driver session (PII, payment forms,
    /// signature pads). Privacy hardening per audit (2026-04-25).
    @Environment(\.scenePhase) private var scenePhase
    @State private var isResigning = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                if introFinished {
                    AppRoot()
                        .environmentObject(session)
                        .environmentObject(profile)
                        .environmentObject(push)
                        .environmentObject(realtime)
                        .environmentObject(geo)
                        .environmentObject(hos)
                        .withEusoTripWatchBridge()
                        .transition(.opacity)
                } else {
                    IntroSplash(onFinish: {
                        withAnimation(.easeInOut(duration: 0.45)) {
                            introFinished = true
                        }
                    })
                    .transition(.opacity)
                    .task {
                        // Preload the 33 EusoTrip Animation Design
                        // System SVGs while the splash is up so
                        // wizard tile selection + scroll feel
                        // instant the first time the user opens
                        // Post a Load.
                        EquipmentAnimationCache.shared.preload()
                    }
                }

                // Privacy blur — overlays a brand-tinted veil on top of
                // every visible screen the moment the scene goes
                // inactive (app switcher, control center, incoming
                // call). iOS captures the snapshot from THIS state, so
                // SSN forms, signature pads, payment sheets, and
                // wallet balances never leak into the recents row.
                if isResigning {
                    ZStack {
                        Color.black.opacity(0.95)
                        VStack(spacing: 16) {
                            // Real brand mark, not the truck.box SF
                            // symbol — drivers seeing this in the app
                            // switcher should see the EusoTrip logo,
                            // not a generic SF Symbol that reads as
                            // a placeholder. Asset lives at
                            // `Assets.xcassets/EusoTripLogo.imageset`.
                            Image("EusoTripLogo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 96, height: 96)
                            Text("EUSOTRIP")
                                .font(.system(size: 18, weight: .heavy)).tracking(4)
                                .foregroundStyle(LinearGradient.diagonal)
                        }
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Show the brand veil before iOS snapshots us.
                let resigning = (newPhase != .active)
                withAnimation(.easeInOut(duration: 0.10)) {
                    isResigning = resigning
                }
            }
            .task {
                #if DEBUG
                // Debug-only regression fence. In release this is a no-op
                // (the function is guarded internally) — ensures seeded
                // mock data can't sneak back into a shipped build without
                // the dev build crashing first.
                MockDataGuard.runSelfCheck()
                #endif
                await session.boot()
                // Proactively trigger the iOS "Allow EusoTrip to use
                // your location?" prompt at app launch. WeatherService
                // also requests it lazily on first fetch, but that
                // race occasionally lost to the home view rendering
                // first — leaving the dashboard with no weather card
                // AND no prompt. Idempotent: a no-op if status is
                // already determined. Founder report 2026-05-05.
                //
                // No `await` — `requestPermissionIfNeeded()` is sync
                // and `WeatherService` is `@MainActor`. The enclosing
                // `.task` already runs on the main actor, so this is a
                // same-actor call (the prior `await` produced the
                // "No 'async' operations occur within 'await'" warning).
                WeatherService.shared.requestPermissionIfNeeded()
            }
            // Canonical global sign-out listener. Every Sign-out cell in
            // the app (Me hub, Settings hub, Driver Me, Shipper Me hero
            // dropdown, etc.) posts the same notification name —
            // `eusoLogoutRequested` — and this single subscriber routes
            // them all to `session.signOut()`. Resolves the founder
            // 2026-05-04 report ("sign out takes you to home screen ...
            // there is sign out in multiple spots and they dont work").
            .onReceive(NotificationCenter.default.publisher(
                for: Notification.Name("eusoLogoutRequested"))) { _ in
                Task { await session.signOut() }
            }
            // Side-effect wiring: APNs + realtime + observers all latch
            // onto the session phase. Booting them before sign-in is
            // harmless (the APNs prompt fires, the socket connects with
            // no auth token and drops), but we hold until `.signedIn`
            // so the push prompt arrives at a moment the user can
            // contextualize it ("You're in. Keep me posted on loads?").
            .onChange(of: session.phase) { _, newPhase in
                if newPhase == .signedIn {
                    Task { await push.bootstrap() }
                    realtime.connect()
                    hos.start()
                    // Seed the top-bar chat glyph badge from the
                    // authoritative `messages.getUnreadCount` procedure
                    // right after sign-in; the store keeps itself in
                    // sync thereafter via `.eusoMessageReceived`
                    // WebSocket fan-outs + pull-to-refresh from the
                    // inbox. Paired watches get the same count mirrored
                    // through `WatchAuthBridge` below.
                    UnreadMessageStore.shared.refresh()
                    // Forward every realtime Socket.IO fan-out
                    // (LOAD_STATE_CHANGED, HOS_WARNING, etc.) to the
                    // paired watch so the wrist reflects server events
                    // within ~1s instead of waiting for the 5-min poll.
                    WatchAuthBridge.shared.startRealtimeBridge()
                    // F13 — attach the inbound-convoy realtime observer
                    // so envelopes the backend pushes to this driver get
                    // fan-out to the wrist via WCSession. The outbound
                    // path (wrist → phone → server) is already live via
                    // WatchCommandHandler's `convoy.envelope` op, which
                    // calls into ConvoyPhoneBridge regardless of whether
                    // the realtime bridge has been started.
                    ConvoyPhoneBridge.shared.startRealtimeBridge()
                } else {
                    realtime.disconnect()
                    hos.stop()
                    geo.clearAll()
                    WatchAuthBridge.shared.stopRealtimeBridge()
                    ConvoyPhoneBridge.shared.stop()
                }
            }
            // Deep link: eusotrip://reset?token=<uuid>
            .onOpenURL { handleDeepLink($0) }
        }
    }

    private func handleDeepLink(_ url: URL) {
        // Vendor OAuth callback — `eusotrip://oauth/callback/<vendor>?code=…&state=…`
        // Forwarded to the HardwareCapabilitiesView observer so the
        // form can call `capabilities.exchangeOAuthCode` immediately.
        if VendorOAuthCallback.handle(url: url) { return }

        guard url.scheme == "eusotrip",
              url.host == "reset",
              let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "token" })?.value
        else { return }
        NotificationCenter.default.post(
            name: .eusoResetPasswordDeepLink,
            object: nil,
            userInfo: ["token": token]
        )
    }
}

extension Notification.Name {
    static let eusoResetPasswordDeepLink = Notification.Name("eusoResetPasswordDeepLink")
    /// Fired by the ESANG autopilot when the assistant reply contains a
    /// `<<<ACTION:refresh>>>` token. Any visible surface can observe this
    /// and re-run its loader (pull-to-refresh parity for voice).
    static let esangRefreshSurface = Notification.Name("esangRefreshSurface")

    /// Fired by the ESANG autopilot when the assistant navigates to a
    /// Me-tab sub-route (ELD, Fleet, Zeun, Tax, …). The `object` is the
    /// raw value of the `MeDetailRoute` to present. `DriverMePane`
    /// observes this and opens its sub-sheet at the requested route.
    ///
    /// Canonical voice examples:
    ///   "open my ELD"          → userInfo raw = "eld"
    ///   "fleet management"     → raw = "fleet"
    ///   "take me to Zeun"      → raw = "zeun"
    ///   "show my Eusowallet"   → raw = "earnings"
    static let esangOpenMeDetail = Notification.Name("esangOpenMeDetail")

    /// Fired by `RealtimeService` when Socket.IO delivers a `message:new`
    /// event on any `conversation:<id>` room we've joined. `userInfo`
    /// carries the backend payload verbatim — `conversationId`,
    /// `messageId`, `senderId`, `senderName`, `content`, `messageType`,
    /// `timestamp`. The active `DriverConversationView` appends the
    /// message; `DriverMessagesSheet` bumps the preview + unread count;
    /// the top-bar glyph badge increments via `UnreadMessageStore`.
    static let eusoMessageReceived = Notification.Name("eusoMessageReceived")

    /// Fired when `UnreadMessageStore` refreshes its aggregate count —
    /// observers that render an unread dot on the top-bar chat glyph
    /// re-read `UnreadMessageStore.shared.total` when this fires.
    static let eusoUnreadCountChanged = Notification.Name("eusoUnreadCountChanged")

    /// Fired by any driver-facing CTA that triggers an action the backend
    /// will eventually own (instant payout, claim bonus, file IFTA, etc.).
    /// Per the MeDetailScreens doctrine these views are "production-quality
    /// previews" — they need to acknowledge the tap, record it, and emit a
    /// signal that a future wave's backend adapter can intercept. The
    /// `object` is a stable string key (e.g. "wallet.instant-payout"); the
    /// app-level toast layer + analytics both listen here so no tap is
    /// ever a silent no-op. `userInfo` is free-form per action.
    static let eusoMeActionFired = Notification.Name("eusoMeActionFired")

    /// Fired by any Me-detail CTA that wants to open the pre-trip DVIR
    /// flow. `DriverNavController` observes this, pops the Me sheet, and
    /// advances into `011_PretripDVIR`. Previously the "Start pre-trip
    /// DVIR" buttons on MeDvirView + MeZeunView were dead closures.
    static let eusoStartPretripDVIR = Notification.Name("eusoStartPretripDVIR")

    /// Fired by `RealtimeService` whenever the backend pushes a
    /// `notification:new` event on `user:<myId>`. Carries the full
    /// payload (`type`, `title`, `message`, `data?`, `actionUrl?`) in
    /// `userInfo`. The toast layer + Me > Notifications hub observe
    /// this so any wallet / safety / training / dispatch notification
    /// surfaces in-app even when push is throttled.
    static let eusoNotificationReceived = Notification.Name("eusoNotificationReceived")

    /// Fired by `RealtimeService` when a dispatcher hand-assigns a load
    /// to me. Drivers should refetch their queue and surface an in-app
    /// "New load assigned" banner. `userInfo` carries the dispatch
    /// payload (`loadId`, `loadNumber`, `dispatcherId`, etc.).
    static let eusoLoadAssigned = Notification.Name("eusoLoadAssigned")

    /// Fired by `RealtimeService` when an active load gets reassigned
    /// off me (rescind / dispatcher override). Active load surfaces
    /// should drop the user back to the queue and refresh.
    static let eusoLoadReassigned = Notification.Name("eusoLoadReassigned")

    /// Fired by `RealtimeService` when ANY shipper posts a new load to
    /// the marketplace (server emits `load:posted` on the
    /// `marketplace` channel after `loads.create` succeeds). Drivers
    /// subscribe via `RealtimeService.joinMarketplace()` once at
    /// session start so the load board updates in real time. `userInfo`
    /// carries the load summary (`loadId`, `loadNumber`, `equipment`,
    /// `origin`, `destination`, lat/lng, `distance`, `rate`,
    /// `pickupDate`, `isHazmat`, `isCrossBorder`).
    static let eusoLoadPosted = Notification.Name("eusoLoadPosted")

    /// Fired by `RealtimeService` when the shipper accepts a bid the
    /// driver placed — backend emits `bid:awarded` to the catalyst's
    /// COMPANY room (auto-joined). My Bids / My Loads / Home should
    /// re-poll, and the toast layer should celebrate the win.
    static let eusoBidAwarded = Notification.Name("eusoBidAwarded")
}
