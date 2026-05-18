//
//  BrokerNavController.swift
//  EusoTrip 2027 UI — broker-mode bottom-nav router.
//
//  Mirror of `ShipperNavController` / `CarrierNavController` for the
//  BROKER role. The canonical broker bottom-nav (sourced from
//  401_BrokerTenders.swift / 402_BrokerTenderDetail.swift) is:
//
//      Home (house) · Loads (shippingbox.fill) | Carriers (person.3.fill) · Me (person)
//
//  Slot routing strategy mirrors the Shipper + Carrier stacks: the
//  surface in `RoleSurfaceRouter` injects this handler; tap dispatches
//  through `BrokerNavDispatcher.handle(_:)` which posts an
//  `eusoBrokerNavSwap` notification; the surface listens and swaps
//  the rendered `ScreenRegistry` entry by id. RBAC is enforced
//  surface-side via `RoleAccess.canRender`.
//

import SwiftUI
import Combine

struct BrokerNavHandlerKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

extension EnvironmentValues {
    var brokerNavHandler: ((String) -> Void)? {
        get { self[BrokerNavHandlerKey.self] }
        set { self[BrokerNavHandlerKey.self] = newValue }
    }
}

extension Notification.Name {
    static let eusoBrokerNavSwap     = Notification.Name("eusoBrokerNavSwap")
    static let eusoBrokereSangTapped = Notification.Name("eusoBrokereSangTapped")
}

/// Slot-label → screen-id map. `Loads` resolves to the canonical
/// Tenders board (401); `Carriers` resolves to 402 Tender Detail's
/// sibling Carrier Vet board (402b) which lists vetted carriers; `Me`
/// resolves to 404 Commission Queue as the broker's earnings hub
/// until a dedicated Me brick lands. Tapping `Me` from 400 keeps the
/// existing pattern of using a real, useful surface rather than a
/// stub Me page.
enum BrokerNavRoute {
    static let map: [String: String] = [
        "home":     "400",
        "loads":    "401",
        "carriers": "402b",
        "me":       "404",
    ]

    static let orbLabels: Set<String> = ["esang", "orb"]
}

@MainActor
enum BrokerNavDispatcher {
    static func handle(_ label: String) {
        let key = label.lowercased()

        if BrokerNavRoute.orbLabels.contains(key) {
            NotificationCenter.default.post(
                name: .eusoBrokereSangTapped,
                object: nil
            )
            return
        }

        guard let screenId = BrokerNavRoute.map[key] else { return }
        NotificationCenter.default.post(
            name: .eusoBrokerNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }
}
