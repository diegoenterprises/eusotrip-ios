//
//  EscortNavController.swift
//  EusoTrip 2027 UI — escort-mode bottom-nav router.
//
//  Mirror of `ShipperNavController` / `CarrierNavController` for the
//  ESCORT role. The canonical bottom-nav (sourced from
//  600_EscortHome.swift) is:
//
//      Home (house.fill) · Assignments (shield.lefthalf.filled)
//      | Corridor (map) · Me (person)
//

import SwiftUI
import Combine

struct EscortNavHandlerKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

extension EnvironmentValues {
    var escortNavHandler: ((String) -> Void)? {
        get { self[EscortNavHandlerKey.self] }
        set { self[EscortNavHandlerKey.self] = newValue }
    }
}

extension Notification.Name {
    static let eusoEscortNavSwap     = Notification.Name("eusoEscortNavSwap")
    static let eusoEscorteSangTapped = Notification.Name("eusoEscorteSangTapped")
}

/// `Assignments` resolves to 601 Assignment Detail (which boards the
/// active assignment when present, empty-states when not — the only
/// "list" surface the escort track has today is hidden inside the
/// home dashboard, so 601 doubles as the assignments surface). `Me`
/// routes to 600 home until the escort Me brick lands.
enum EscortNavRoute {
    static let map: [String: String] = [
        "home":        "600",
        "assignments": "601",
        "corridor":    "602",
        "me":          "600",
    ]

    static let orbLabels: Set<String> = ["esang", "orb"]
}

@MainActor
enum EscortNavDispatcher {
    static func handle(_ label: String) {
        let key = label.lowercased()

        if EscortNavRoute.orbLabels.contains(key) {
            NotificationCenter.default.post(
                name: .eusoEscorteSangTapped,
                object: nil
            )
            return
        }

        guard let screenId = EscortNavRoute.map[key] else { return }
        NotificationCenter.default.post(
            name: .eusoEscortNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }
}
