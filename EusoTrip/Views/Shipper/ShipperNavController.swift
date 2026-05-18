//
//  ShipperNavController.swift
//  EusoTrip 2027 UI — shipper-mode bottom-nav router.
//
//  Mirror of `DriverNavController.driverNavHandler` for the SHIPPER
//  role. Reads tap labels from `BottomNav` slots and dispatches the
//  navigation event so the chrome's Home / Create Load / ESANG /
//  Loads / Me slots actually move the user.
//
//  Founder anchor 2026-04-28: "shipper is different than driver. so
//  the bottom nav needs to reflect that … home, create load, esang
//  button, loads, me." That layout was applied across all 11
//  shipper chrome screens (200-210); this controller closes the
//  wiring gap so the slots don't just paint — they navigate.
//
//  Routing strategy — ContentView injects this handler at the
//  shipper root the same way it injects `driverNavHandler` at the
//  driver root. The handler maps the slot label to a
//  NotificationCenter post that the screen registry already listens
//  for, swapping the active screen ID. Below: the env-key plumbing
//  + the canonical broadcast names.
//

import SwiftUI
import Combine

/// Slot-tap handler injected by the ContentView shipper root. Same
/// signature as `driverNavHandler` (`(String) -> Void`) so
/// `BottomNav.slot(for:)` can chain through both with a single
/// fallback ladder. When this handler is nil, the per-slot `onTap`
/// closure runs (which is a no-op by default — see all 11
/// `shipperNavLeading_NNN()` / `shipperNavTrailing_NNN()` helpers in
/// 200_ShipperHome … 210_ShipperAnalyticsDeepDive).
struct ShipperNavHandlerKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

extension EnvironmentValues {
    var shipperNavHandler: ((String) -> Void)? {
        get { self[ShipperNavHandlerKey.self] }
        set { self[ShipperNavHandlerKey.self] = newValue }
    }
}

/// Canonical notification name the shipper screen registry listens
/// for. The handler posts this whenever a NavSlot fires; the
/// registry decides what to render in response.
extension Notification.Name {
    /// `userInfo["screenId"]` — the screen registry id to swap to.
    static let eusoShipperNavSwap = Notification.Name("eusoShipperNavSwap")

    /// Pop one entry off the ShipperSurface navigation stack. Posted by
    /// the surface-level back overlay AND by any leaf screen that wants
    /// a programmatic back action ("Done" buttons on sheet-style
    /// detail screens, gesture-driven dismissals). No userInfo —
    /// `popOne()` is the only behavior. Resolves the founder's
    /// "stuck on the screen" complaint where Me-hub leaf screens had
    /// no path back to the parent hub.
    static let eusoShipperNavBack = Notification.Name("eusoShipperNavBack")

    /// Avatar-tap from the Me hero. ShipperSurface listens and
    /// presents a `PhotosPicker` sheet; on selection the picked
    /// `Data` rides through `profile.updateAvatar` so the new photo
    /// persists server-side and shows on web + iPad.
    static let eusoShipperAvatarPickRequested = Notification.Name("eusoShipperAvatarPickRequested")

    /// Fired after `profile.updateAvatar` succeeds so any surface
    /// rendering the avatar (Me hero, top-bar duAvatar, profile
    /// edit) can re-fetch and repaint. Role-agnostic — both shipper
    /// and driver listen.
    static let eusoProfileAvatarUpdated = Notification.Name("eusoProfileAvatarUpdated")

    /// Real-time broadcast from `profile.updateProfile` /
    /// `profile.updateAvatar` on the server. Fires when a remote
    /// device edits the user's profile — listening surfaces re-fetch
    /// via `profile.getMyProfile` so iPad and iPhone stay in sync
    /// while both apps are open.
    static let eusoProfileUpdated = Notification.Name("eusoProfileUpdated")
}

/// Slot-label → screen-id map. Keyed off the lowercased label string
/// the BottomNav primitive emits. Centralized so future shipper
/// chrome additions only have to touch this dictionary.
enum ShipperNavRoute {
    static let map: [String: String] = [
        "home":        "200",
        "create load": "204",
        "loads":       "201",
        // "Me" lands on 320 (MeHomeScreen) — the gateway with ACCOUNT /
        // INTEL / EUSOWALLET / NETWORK / COMPLIANCE / TERMINAL OPS /
        // SETTINGS cell groups. 202 (ShipperProfile) is reachable from
        // inside Me via the ACCOUNT → "Profile" cell.
        "me":          "320",
    ]

    /// `BottomNav` emits the orb tap as `"esang"` — surfaced via a
    /// separate notification so the chrome can present the ESANG
    /// coach sheet instead of swapping the screen.
    static let orbLabels: Set<String> = ["esang", "orb"]
}

/// Shared dispatcher used by ContentView's shipper-root closure. Pure
/// function — accepts a label, posts the right notification. Kept
/// out of ContentView so the routing logic is unit-testable.
@MainActor
enum ShipperNavDispatcher {
    static func handle(_ label: String) {
        let key = label.lowercased()

        if ShipperNavRoute.orbLabels.contains(key) {
            NotificationCenter.default.post(
                name: .eusoShippereSangTapped,
                object: nil
            )
            return
        }

        guard let screenId = ShipperNavRoute.map[key] else { return }
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }
}

extension Notification.Name {
    /// Fired when the ESANG orb is tapped on a shipper screen.
    /// Listened to by ContentView (or whichever surface owns the
    /// ESANG coach sheet visibility flag) — same role as
    /// `nav.showeSang` on the driver side.
    static let eusoShippereSangTapped = Notification.Name("eusoShippereSangTapped")
}

// MARK: - Slot identity (for canonical Shell+BottomNav wrapping)

/// Which canonical Shipper bottom-nav slot the wrapped screen "lives
/// in." Drives the `isCurrent` flag in the wrapped `BottomNav` so the
/// pill highlight matches the user's mental model. See `wrapShipperScreen`.
enum ShipperBottomNavSlot {
    case home
    case createLoad
    case loads
    case me
    /// Detail surfaces drilled from a list — none of the four slots
    /// is current; the user is "off-ring" and can tap back into any
    /// slot to leave the detail.
    case none
}

/// Wrap any bare Shipper view body in the canonical Shell + BottomNav
/// chrome. Used by the `ScreenRegistry` registration site to register
/// 219+ screens uniformly without one Screen wrapper struct per file.
/// The slot-tap handler is wired through `BottomNav`'s default tap
/// closure → env-injected `shipperNavHandler` (see `ShipperSurface`),
/// so taps land on the right notification path automatically.
///
/// Implemented as a `struct` (rather than a free function) so the
/// `@ViewBuilder content` closure is stored as a property — `Shell`
/// retains its body builder, which requires the closure to be
/// `@escaping`. SwiftUI's view-tree machinery handles the storage
/// automatically when the builder lives on a `View`-conforming type.
struct ShipperScreenWrap<Content: View>: View {
    let palette: Theme.Palette
    let currentSlot: ShipperBottomNavSlot
    @ViewBuilder var content: () -> Content

    var body: some View {
        Shell(theme: palette) {
            content()
        } nav: {
            BottomNav(
                leading: [
                    NavSlot(label: "Home",
                            systemImage: "house.fill",
                            isCurrent: currentSlot == .home),
                    NavSlot(label: "Create Load",
                            systemImage: "plus.rectangle.on.rectangle",
                            isCurrent: currentSlot == .createLoad),
                ],
                trailing: [
                    NavSlot(label: "Loads",
                            systemImage: "shippingbox.fill",
                            isCurrent: currentSlot == .loads),
                    NavSlot(label: "Me",
                            systemImage: "person.fill",
                            isCurrent: currentSlot == .me),
                ],
                orbState: .idle
            )
        }
    }
}

/// Convenience constructor used by the `ScreenRegistry` closures so
/// the call sites read the same as before (`wrapShipperScreen(palette:
/// currentSlot:) { Body() }`). Returns `some View` rather than the
/// generic `ShipperScreenWrap` because the call sites immediately
/// type-erase via `AnyView(...)`. Not main-actor-isolated because
/// `ScreenRegistry.all` is a `static let` initializer with no actor
/// context — the inner view body still runs on the main actor at
/// render time (SwiftUI handles that), but the constructor itself
/// has to be callable from the non-isolated registry initializer.
func wrapShipperScreen<Content: View>(
    palette: Theme.Palette,
    currentSlot: ShipperBottomNavSlot,
    @ViewBuilder _ content: @escaping () -> Content
) -> some View {
    ShipperScreenWrap(palette: palette, currentSlot: currentSlot, content: content)
}
