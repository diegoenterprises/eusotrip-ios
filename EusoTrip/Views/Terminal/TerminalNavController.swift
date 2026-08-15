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

enum TerminalNavTab {
    case home, movements, yard, me, none
}

/// `Movements` resolves to 701 Gate Queue (the canonical inbound /
/// outbound movement surface). `Me` resolves to the dedicated 703
/// Terminal Me hub.
enum TerminalNavRoute {
    enum Destination: String {
        case home = "700"
        case movements = "701"
        case yard = "702"
        case me = "703"
    }

    private static let map: [String: Destination] = [
        "home": .home,
        "movements": .movements,
        "yard": .yard,
        "me": .me,
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

    static func leading(current: TerminalNavTab = .none) -> [NavSlot] {
        [NavSlot(label: "Home", systemImage: "house", isCurrent: current == .home),
         NavSlot(label: "Movements", systemImage: "shippingbox.fill", isCurrent: current == .movements)]
    }

    static func trailing(current: TerminalNavTab = .none) -> [NavSlot] {
        [NavSlot(label: "Yard", systemImage: "map", isCurrent: current == .yard),
         NavSlot(label: "Me", systemImage: "person", isCurrent: current == .me)]
    }
}

@MainActor
enum TerminalNavDispatcher {
    static func handle(_ label: String) {
        if TerminalNavRoute.isOrb(label) {
            NotificationCenter.default.post(
                name: .eusoTerminaleSangTapped,
                object: nil
            )
            return
        }

        guard let screenId = TerminalNavRoute.screenId(for: label) else { return }
        NotificationCenter.default.post(
            name: .eusoTerminalNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }
}
