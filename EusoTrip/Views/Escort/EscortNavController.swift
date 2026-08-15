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

enum EscortNavTab {
    case home, assignments, corridor, me, none
}

/// `Assignments` resolves to 601 Assignment Detail (which boards the
/// active assignment when present, empty-states when not — the only
/// "list" surface the escort track has today is hidden inside the
/// home dashboard, so 601 doubles as the assignments surface). `Me`
/// resolves to the dedicated 620 Escort Me hub.
enum EscortNavRoute {
    enum Destination: String {
        case home = "600"
        case assignments = "601"
        case corridor = "602"
        case me = "620"
        case comms = "603"
        case permits = "607"
    }

    private static let map: [String: Destination] = [
        "home": .home,
        "assignments": .assignments,
        "corridor": .corridor,
        "me": .me,
        // New-wave Escort screens retained these established labels. They
        // now resolve inside the Escort registry instead of silently dying.
        "trip": .assignments,
        "comms": .comms,
        "permit": .permits,
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

    static func leading(current: EscortNavTab = .none) -> [NavSlot] {
        [NavSlot(label: "Home", systemImage: "house", isCurrent: current == .home),
         NavSlot(label: "Assignments", systemImage: "shield.lefthalf.filled", isCurrent: current == .assignments)]
    }

    static func trailing(current: EscortNavTab = .none) -> [NavSlot] {
        [NavSlot(label: "Corridor", systemImage: "map", isCurrent: current == .corridor),
         NavSlot(label: "Me", systemImage: "person", isCurrent: current == .me)]
    }
}

@MainActor
enum EscortNavDispatcher {
    static func handle(_ label: String) {
        if EscortNavRoute.isOrb(label) {
            NotificationCenter.default.post(
                name: .eusoEscorteSangTapped,
                object: nil
            )
            return
        }

        guard let screenId = EscortNavRoute.screenId(for: label) else { return }
        NotificationCenter.default.post(
            name: .eusoEscortNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }
}
