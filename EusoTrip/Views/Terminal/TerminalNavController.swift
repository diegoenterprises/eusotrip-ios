//
//  TerminalNavController.swift
//  EusoTrip 2027 UI — terminal-mode bottom-nav router.
//
//  Mirror of `ShipperNavController` / `CarrierNavController` for the
//  TERMINAL_MANAGER role. The canonical bottom-nav (sourced from
//  700_TerminalHome.swift) is:
//
//      Home (house.fill) · Movements (shippingbox.fill)
//      | Yard (map) · Me (person)
//

import SwiftUI
import Combine

struct TerminalNavHandlerKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

extension EnvironmentValues {
    var terminalNavHandler: ((String) -> Void)? {
        get { self[TerminalNavHandlerKey.self] }
        set { self[TerminalNavHandlerKey.self] = newValue }
    }
}

extension Notification.Name {
    static let eusoTerminalNavSwap     = Notification.Name("eusoTerminalNavSwap")
    static let eusoTerminaleSangTapped = Notification.Name("eusoTerminaleSangTapped")
}

/// `Movements` resolves to 701 Gate Queue (the canonical inbound /
/// outbound movement surface). `Me` routes to 700 home until the
/// terminal Me brick lands.
enum TerminalNavRoute {
    static let map: [String: String] = [
        "home":      "700",
        "movements": "701",
        "yard":      "702",
        "me":        "700",
    ]

    static let orbLabels: Set<String> = ["esang", "orb"]
}

@MainActor
enum TerminalNavDispatcher {
    static func handle(_ label: String) {
        let key = label.lowercased()

        if TerminalNavRoute.orbLabels.contains(key) {
            NotificationCenter.default.post(
                name: .eusoTerminaleSangTapped,
                object: nil
            )
            return
        }

        guard let screenId = TerminalNavRoute.map[key] else { return }
        NotificationCenter.default.post(
            name: .eusoTerminalNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }
}
