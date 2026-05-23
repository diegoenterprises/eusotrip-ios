//
//  RailEngineerNavController.swift
//  EusoTrip — Rail Engineer bottom-nav router.
//
//  Mirror of `ComplianceNavController` / `DispatchNavController` for the
//  RAIL_ENGINEER role. Canonical bottom-nav:
//
//      Home (house) · Shipments (shippingbox)
//      | Compliance (checkmark.shield) · Me (person)
//

import SwiftUI
import Combine

struct RailEngineerNavHandlerKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

extension EnvironmentValues {
    var railEngineerNavHandler: ((String) -> Void)? {
        get { self[RailEngineerNavHandlerKey.self] }
        set { self[RailEngineerNavHandlerKey.self] = newValue }
    }
}

extension Notification.Name {
    static let eusoRailNavSwap     = Notification.Name("eusoRailNavSwap")
    static let eusoRaileSangTapped = Notification.Name("eusoRaileSangTapped")
}

enum RailEngineerNavRoute {
    static let map: [String: String] = [
        "home":       "Rail550",
        "shipments":  "Rail551",
        "compliance": "Rail552",
        "me":         "Rail550",
    ]

    static let orbLabels: Set<String> = ["esang", "orb"]
}

@MainActor
enum RailEngineerNavDispatcher {
    static func handle(_ label: String) {
        let key = label.lowercased()

        if RailEngineerNavRoute.orbLabels.contains(key) {
            NotificationCenter.default.post(
                name: .eusoRaileSangTapped,
                object: nil
            )
            return
        }

        guard let screenId = RailEngineerNavRoute.map[key] else { return }
        NotificationCenter.default.post(
            name: .eusoRailNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }
}
