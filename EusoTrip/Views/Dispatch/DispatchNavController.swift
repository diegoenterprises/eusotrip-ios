//
//  DispatchNavController.swift
//  EusoTrip 2027 UI — dispatch-mode bottom-nav router.
//
//  Mirror of Shipper / Carrier / Broker / Escort / Terminal / Admin /
//  Compliance nav controllers for the DISPATCH role. Canonical bottom
//  nav (sourced from the 400/401/405 Dispatcher SVGs — the 700-series
//  Home/Drivers/Loads was a quarantined invention, see _quarantine_700)
//  is:
//
//      Home (house) · Board (rectangle.split.3x1.fill)
//      | Comms (bubble.left.and.bubble.right.fill) · Me (person)
//
//  Routing: `Home` → Disp400 live-desk (canonical 400 port: KPI hero +
//  live-drivers strip + tender queue); `Board` → Disp401 lifecycle
//  kanban (canonical 401 port); `Comms` → Dpch721 Comms Hub (canonical
//  405 port); `Me` → Dpch713 dispatch Me hub. Driver roster (Dpch701)
//  and load queue (Dpch702) remain reachable from the Me hub.
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
    static let eusoDispatcheSangTapped = Notification.Name("eusoDispatcheSangTapped")
}

enum DispatchNavTab {
    case home, board, comms, me, none
}

enum DispatchNavRoute {
    enum Destination: String {
        case home = "Disp400"
        case board = "Disp401"
        case comms = "Dpch721"
        case me = "Dpch713"
        case drivers = "Dpch701"
        case loads = "Dpch702"
    }

    private static let map: [String: Destination] = [
        "home": .home,
        "board": .board,
        "comms": .comms,
        // 2026-05-21 — dedicated Dispatch Me hub (Dpch713). Was "Dpch700"
        // (Home), which made the "Me" tab a silent dead-end that bounced
        // the dispatcher back to the screen they were already on.
        "me": .me,
        // 2026-06-09 alias sweep (audit M24): ~20 dispatch screens still
        // carry the legacy SVG slot labels "Drivers" / "Loads" in their
        // BottomNav rows. Those labels had no map entry, so the slots
        // were silent dead-taps (the dispatcher's `guard let` returns).
        // Alias them onto the registered boards instead of relabeling
        // every bespoke port (the labels are wireframe-verbatim).
        "drivers": .drivers,
        "loads": .loads,
        "dispatch": .board,
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

    static func leading(current: DispatchNavTab = .none) -> [NavSlot] {
        [NavSlot(label: "Home", systemImage: "house", isCurrent: current == .home),
         NavSlot(label: "Board", systemImage: "rectangle.split.3x1.fill", isCurrent: current == .board)]
    }

    static func trailing(current: DispatchNavTab = .none) -> [NavSlot] {
        [NavSlot(label: "Comms", systemImage: "bubble.left.and.bubble.right.fill", isCurrent: current == .comms),
         NavSlot(label: "Me", systemImage: "person", isCurrent: current == .me)]
    }
}

@MainActor
enum DispatchNavDispatcher {
    static func handle(_ label: String) {
        if DispatchNavRoute.isOrb(label) {
            NotificationCenter.default.post(
                name: .eusoDispatcheSangTapped,
                object: nil
            )
            return
        }

        guard let screenId = DispatchNavRoute.screenId(for: label) else { return }
        NotificationCenter.default.post(
            name: .eusoDispatchNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }
}
