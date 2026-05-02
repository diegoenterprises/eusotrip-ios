//
//  DispatchNavController.swift
//  EusoTrip 2027 UI — dispatch-mode bottom-nav router.
//
//  Mirror of Shipper / Carrier / Broker / Escort / Terminal / Admin /
//  Compliance nav controllers for the DISPATCH role. Canonical bottom
//  nav (sourced from 700_DispatchHome.swift) is:
//
//      Home (house) · Drivers (person.3.fill)
//      | Loads (shippingbox.fill) · Me (person)
//
//  Routing: `Drivers` → Dpch701 driver board; `Loads` → Dpch702 load
//  assignment (the unassigned-loads queue, which is the closest
//  surface to a "loads" hub for dispatchers); `Me` → Dpch700 home
//  until a dedicated Me brick lands.
//

import SwiftUI
import Combine

struct DispatchNavHandlerKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

extension EnvironmentValues {
    var dispatchNavHandler: ((String) -> Void)? {
        get { self[DispatchNavHandlerKey.self] }
        set { self[DispatchNavHandlerKey.self] = newValue }
    }
}

extension Notification.Name {
    static let eusoDispatchNavSwap     = Notification.Name("eusoDispatchNavSwap")
    static let eusoDispatchEsangTapped = Notification.Name("eusoDispatchEsangTapped")
}

enum DispatchNavRoute {
    static let map: [String: String] = [
        "home":    "Dpch700",
        "drivers": "Dpch701",
        "loads":   "Dpch702",
        "me":      "Dpch700",
    ]

    static let orbLabels: Set<String> = ["esang", "orb"]
}

@MainActor
enum DispatchNavDispatcher {
    static func handle(_ label: String) {
        let key = label.lowercased()

        if DispatchNavRoute.orbLabels.contains(key) {
            NotificationCenter.default.post(
                name: .eusoDispatchEsangTapped,
                object: nil
            )
            return
        }

        guard let screenId = DispatchNavRoute.map[key] else { return }
        NotificationCenter.default.post(
            name: .eusoDispatchNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }
}
