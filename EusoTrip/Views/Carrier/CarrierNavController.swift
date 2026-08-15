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

enum CarrierNavTab {
    case home, loads, drivers, me, none
}

/// Carrier/Catalyst bottom-nav contract. Every accepted label resolves to
/// a `.carrier` screen so legacy Catalyst chrome cannot switch the user into
/// the parallel `.catalyst` registry family. Deep links must post a typed
/// `.eusoCarrierNavSwap` payload directly instead of expanding this tab map.
enum CarrierNavRoute {
    enum Destination: String {
        case home = "300"
        case loads = "301"
        case drivers = "304"
        case me = "350"
        case dispatch = "303"
        case earnings = "312"
        case fleet = "320"
        case bids = "308"
    }

    private static let map: [String: Destination] = [
        "home": .home,
        "loads": .loads,
        "drivers": .drivers,
        "me": .me,
        // Verbatim labels retained by older Carrier and Catalyst screens.
        "dispatch": .dispatch,
        "wallet": .earnings,
        "fleet": .fleet,
        "my loads": .loads,
        "bids": .bids,
        "network": .drivers,
        "match": .bids,
        "matches": .bids,
        "find": .loads,
    ]

    private static let orbLabels: Set<String> = ["esang", "orb"]

    static func screenId(for label: String) -> String? {
        map[normalize(label)]?.rawValue
    }

    static func isOrb(_ label: String) -> Bool {
        orbLabels.contains(normalize(label))
    }

    private static func normalize(_ label: String) -> String {
        label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func leading(current: CarrierNavTab = .none) -> [NavSlot] {
        [NavSlot(label: "Home", systemImage: "house", isCurrent: current == .home),
         NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: current == .loads)]
    }

    static func trailing(current: CarrierNavTab = .none) -> [NavSlot] {
        [NavSlot(label: "Drivers", systemImage: "person.2", isCurrent: current == .drivers),
         NavSlot(label: "Me", systemImage: "person", isCurrent: current == .me)]
    }
}

/// Shared dispatcher. Accepts a role-local label and emits exactly one
/// Carrier notification; unknown labels emit nothing.
@MainActor
enum CarrierNavDispatcher {
    static func handle(_ label: String) {
        if CarrierNavRoute.isOrb(label) {
            NotificationCenter.default.post(
                name: .eusoCarriereSangTapped,
                object: nil
            )
            return
        }

        guard let screenId = CarrierNavRoute.screenId(for: label) else { return }
        NotificationCenter.default.post(
            name: .eusoCarrierNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }
}
