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

enum AdminNavTab {
    case home, tickets, tenants, me, none
}

/// `Tickets` resolves to 801 Control Tower (the platform exception /
/// SLA feed — the closest surface to a ticket queue today; an
/// EusoTicket-branded admin work-ticket board can land later under
/// 804+ and this map will pick it up). `Tenants` resolves to 802
/// Tenants list. `Me` routes to the dedicated 804 Admin Me hub
/// (comment re-verified against shipped code 2026-06-09; an older
/// revision said Me collapsed onto 800 Home).
enum AdminNavRoute {
    enum Destination: String {
        case home = "800"
        case tickets = "801"
        case tenants = "802"
        case me = "804"
    }

    private static let map: [String: Destination] = [
        "home": .home,
        "tickets": .tickets,
        "tenants": .tenants,
        "me": .me,
        // 2026-06-09 alias sweep (audit M24 / Wave-11 minors): 801's
        // own chrome labels its slot "Tower" (Control Tower) — no map
        // entry made it a silent dead-tap. Self-alias onto the
        // registered 801 so the tap performs a proper tab reset.
        "tower": .tickets,
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

    static func leading(current: AdminNavTab = .none) -> [NavSlot] {
        [NavSlot(label: "Home", systemImage: "house", isCurrent: current == .home),
         NavSlot(label: "Tickets", systemImage: "ticket.fill", isCurrent: current == .tickets)]
    }

    static func trailing(current: AdminNavTab = .none) -> [NavSlot] {
        [NavSlot(label: "Tenants", systemImage: "building.2", isCurrent: current == .tenants),
         NavSlot(label: "Me", systemImage: "person", isCurrent: current == .me)]
    }
}

@MainActor
enum AdminNavDispatcher {
    static func handle(_ label: String) {
        if AdminNavRoute.isOrb(label) {
            NotificationCenter.default.post(
                name: .eusoAdmineSangTapped,
                object: nil
            )
            return
        }

        guard let screenId = AdminNavRoute.screenId(for: label) else { return }
        NotificationCenter.default.post(
            name: .eusoAdminNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }
}
