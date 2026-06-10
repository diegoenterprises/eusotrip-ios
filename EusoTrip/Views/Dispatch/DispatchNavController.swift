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

enum DispatchNavRoute {
    static let map: [String: String] = [
        "home":  "Disp400",
        "board": "Disp401",
        "comms": "Dpch721",
        // 2026-05-21 — dedicated Dispatch Me hub (Dpch713). Was "Dpch700"
        // (Home), which made the "Me" tab a silent dead-end that bounced
        // the dispatcher back to the screen they were already on.
        "me":    "Dpch713",
        // 2026-06-09 alias sweep (audit M24): ~20 dispatch screens still
        // carry the legacy SVG slot labels "Drivers" / "Loads" in their
        // BottomNav rows. Those labels had no map entry, so the slots
        // were silent dead-taps (the dispatcher's `guard let` returns).
        // Alias them onto the registered boards instead of relabeling
        // every bespoke port (the labels are wireframe-verbatim).
        "drivers": "Dpch701",   // Dispatch · Driver Board (registered)
        "loads":   "Dpch702",   // Dispatch · Load Assignment (registered)
        "dispatch": "Disp401",  // Dpch710A Convoy Composer's "Dispatch" slot → canonical board
    ]

    static let orbLabels: Set<String> = ["esang", "orb"]
}

@MainActor
enum DispatchNavDispatcher {
    static func handle(_ label: String) {
        let key = label.lowercased()

        if DispatchNavRoute.orbLabels.contains(key) {
            NotificationCenter.default.post(
                name: .eusoDispatcheSangTapped,
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
