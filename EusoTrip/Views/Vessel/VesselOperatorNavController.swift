//
//  VesselOperatorNavController.swift
//  EusoTrip — Vessel Operator bottom-nav router.
//
//  Mirror of `RailEngineerNavController` for the VESSEL_OPERATOR role.
//  Canonical bottom-nav:
//
//      Home (house) · Shipments (shippingbox.fill)
//      | Compliance (checkmark.shield.fill) · Me (person)
//

import SwiftUI
import Combine

struct VesselOperatorNavHandlerKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

extension EnvironmentValues {
    var vesselOperatorNavHandler: ((String) -> Void)? {
        get { self[VesselOperatorNavHandlerKey.self] }
        set { self[VesselOperatorNavHandlerKey.self] = newValue }
    }
}

extension Notification.Name {
    static let eusoVesselNavSwap     = Notification.Name("eusoVesselNavSwap")
    static let eusoVesseleSangTapped = Notification.Name("eusoVesseleSangTapped")
}

enum VesselOperatorNavRoute {
    static let map: [String: String] = [
        "home":       "Vesl650",
        "shipments":  "Vesl651",
        "compliance": "Vesl652",
        "me":         "Vesl650",
    ]

    static let orbLabels: Set<String> = ["esang", "orb"]

    // Deep-surface routes (Vesl653–658). NOT bottom-nav slots — these are the
    // deep Vessel Operator screens, reachable by key via deep-link / push so
    // they're navigable beyond the 4 canonical tabs. Additive only; the bottom
    // nav `map` above is untouched.
    static let deepMap: [String: String] = [
        "bookingDetail":      "Vesl653",
        "crewCertifications": "Vesl654",
        "containerPositions": "Vesl655",
        "account":            "Vesl656",
        "statusUpdate":       "Vesl657",
        "demurrageWatch":     "Vesl658",
    ]
}

@MainActor
enum VesselOperatorNavDispatcher {
    static func handle(_ label: String) {
        let key = label.lowercased()

        if VesselOperatorNavRoute.orbLabels.contains(key) {
            NotificationCenter.default.post(
                name: .eusoVesseleSangTapped,
                object: nil
            )
            return
        }

        guard let screenId = VesselOperatorNavRoute.map[key]
                ?? VesselOperatorNavRoute.deepMap[label] else { return }
        NotificationCenter.default.post(
            name: .eusoVesselNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }
}
