//
//  CarrierNavController.swift
//  EusoTrip 2027 UI — carrier-mode bottom-nav router.
//
//  Mirror of `ShipperNavController` for the CATALYST (carrier) role.
//  Reads tap labels from `BottomNav` slots and dispatches the
//  navigation event so the chrome's Home / Loads / Drivers / Me slots
//  actually move the user. The bottom-nav layout is the canonical
//  carrier shape from `300_CarrierHome.swift:528-535`:
//
//      Home (house.fill) · Loads (shippingbox) | Drivers (person.2) · Me (person)
//
//  Routing strategy — `RoleSurfaceRouter`'s `CarrierSurface` injects
//  this handler at the carrier root the same way `ShipperSurface`
//  injects `shipperNavHandler`. The handler maps the slot label to a
//  NotificationCenter post that the surface listens for, swapping the
//  active screen ID through `ScreenRegistry`.
//

import SwiftUI
import Combine

/// Slot-tap handler injected by the carrier root. Same signature as
/// `driverNavHandler` / `shipperNavHandler` (`(String) -> Void`) so
/// `BottomNav.slot(for:)` can chain through any role's handler with a
/// uniform fallback ladder. When this handler is nil, the per-slot
/// `onTap` closure runs (which is a no-op by default — see all 21
/// `carrierNavLeading_NNN()` / `carrierNavTrailing_NNN()` helpers in
/// `300_CarrierHome` … `320_CarrierVehiclesList`).
struct CarrierNavHandlerKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

extension EnvironmentValues {
    var carrierNavHandler: ((String) -> Void)? {
        get { self[CarrierNavHandlerKey.self] }
        set { self[CarrierNavHandlerKey.self] = newValue }
    }
}

/// Canonical notifications. The screen-swap signal carries
/// `userInfo["screenId"]`; the orb signal is parameterless.
extension Notification.Name {
    static let eusoCarrierNavSwap     = Notification.Name("eusoCarrierNavSwap")
    static let eusoCarriereSangTapped = Notification.Name("eusoCarriereSangTapped")
}

/// Slot-label → screen-id map. Keyed off the lowercased label string
/// the BottomNav primitive emits. Centralized so future carrier
/// chrome additions only have to touch this dictionary.
///
/// `Loads` resolves to `301_CarrierLoads` (the "all my loads" board);
/// `Drivers` resolves to `304_CarrierDrivers` (the dispatch /
/// driver-assignment hub); `Me` resolves to `350_CarrierMe` — the
/// canonical Catalyst Me hub with identity hero, full surface index
/// (Account / Operations / Fleet / Financials / Compliance /
/// Support), and the founder-mandated sign-out button. Founder ask
/// 2026-05-07: "catalyst profile has not sign out button" + "make
/// sure all necessary screens outside of active load and load board
/// is accessible".
enum CarrierNavRoute {
    static let map: [String: String] = [
        "home":    "300",
        "loads":   "301",
        "drivers": "304",
        "me":      "350",
        // Catalyst SpectraMatch sub-surface deep-links — not in the
        // bottom-nav slots (the canonical Carrier nav is Home /
        // Loads / Drivers / Me) but addressable from in-screen CTAs
        // and notification deep-links. Carrier users can navigate
        // here because `RoleAccess.allowedScreenRoles(for:.catalyst)`
        // includes `.catalyst`. Surface lookup spans both
        // `.carrier` and `.catalyst` registries (see
        // `CarrierSurface.current`).
        "matches":         "501",
        "catalyst":        "500",
        "catalyst home":   "500",
        "match detail":    "502",
    ]

    /// `BottomNav` emits the orb tap as `"esang"`.
    static let orbLabels: Set<String> = ["esang", "orb"]
}

/// Shared dispatcher. Pure function — accepts a label, posts the right
/// notification. Kept out of view code so the routing logic is unit-
/// testable.
@MainActor
enum CarrierNavDispatcher {
    static func handle(_ label: String) {
        let key = label.lowercased()

        if CarrierNavRoute.orbLabels.contains(key) {
            NotificationCenter.default.post(
                name: .eusoCarriereSangTapped,
                object: nil
            )
            return
        }

        guard let screenId = CarrierNavRoute.map[key] else { return }
        NotificationCenter.default.post(
            name: .eusoCarrierNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }
}
