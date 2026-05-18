//
//  AdminNavController.swift
//  EusoTrip 2027 UI — admin-mode bottom-nav router.
//
//  Mirror of `ShipperNavController` / `CarrierNavController` for the
//  ADMIN / SUPER_ADMIN role. The canonical bottom-nav (sourced from
//  800_AdminHome.swift) is:
//
//      Home (house.fill) · Tickets (ticket.fill)
//      | Tenants (building.2) · Me (person)
//

import SwiftUI
import Combine

struct AdminNavHandlerKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

extension EnvironmentValues {
    var adminNavHandler: ((String) -> Void)? {
        get { self[AdminNavHandlerKey.self] }
        set { self[AdminNavHandlerKey.self] = newValue }
    }
}

extension Notification.Name {
    static let eusoAdminNavSwap     = Notification.Name("eusoAdminNavSwap")
    static let eusoAdmineSangTapped = Notification.Name("eusoAdmineSangTapped")
}

/// `Tickets` resolves to 801 Control Tower (the platform exception /
/// SLA feed — the closest surface to a ticket queue today; an
/// EusoTicket-branded admin work-ticket board can land later under
/// 804+ and this map will pick it up). `Tenants` resolves to 802
/// Tenants list. `Me` routes to 800 home until the admin Me brick
/// lands.
enum AdminNavRoute {
    static let map: [String: String] = [
        "home":    "800",
        "tickets": "801",
        "tenants": "802",
        "me":      "800",
    ]

    static let orbLabels: Set<String> = ["esang", "orb"]
}

@MainActor
enum AdminNavDispatcher {
    static func handle(_ label: String) {
        let key = label.lowercased()

        if AdminNavRoute.orbLabels.contains(key) {
            NotificationCenter.default.post(
                name: .eusoAdmineSangTapped,
                object: nil
            )
            return
        }

        guard let screenId = AdminNavRoute.map[key] else { return }
        NotificationCenter.default.post(
            name: .eusoAdminNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }
}
