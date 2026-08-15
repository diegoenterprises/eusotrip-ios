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

struct VesselShipperNavHandlerKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

extension EnvironmentValues {
    var vesselOperatorNavHandler: ((String) -> Void)? {
        get { self[VesselOperatorNavHandlerKey.self] }
        set { self[VesselOperatorNavHandlerKey.self] = newValue }
    }

    var vesselShipperNavHandler: ((String) -> Void)? {
        get { self[VesselShipperNavHandlerKey.self] }
        set { self[VesselShipperNavHandlerKey.self] = newValue }
    }
}

extension Notification.Name {
    static let eusoVesselNavSwap     = Notification.Name("eusoVesselNavSwap")
    static let eusoVesseleSangTapped = Notification.Name("eusoVesseleSangTapped")
    static let eusoVesselShipperNavSwap = Notification.Name("eusoVesselShipperNavSwap")
    static let eusoVesselShipperNavBack = Notification.Name("eusoVesselShipperNavBack")
    static let eusoVesselShippereSangTapped = Notification.Name("eusoVesselShippereSangTapped")
}

enum VesselShipperNavRoute {
    static let map: [String: String] = [
        "home": "Vesl001",
        "bookings": "Vesl011",
        "loads": "Vesl011",
        "shipments": "Vesl011",
        "track": "Vesl012",
        "compliance": "Vesl006",
        "me": "320",
        "wallet": "290",
        "create": "Vesl010",
        "create booking": "Vesl010",
        "create load": "Vesl010",
        "post a load": "Vesl010",
    ]

    static let orbLabels: Set<String> = ["esang", "orb"]
}

@MainActor
enum VesselShipperNavDispatcher {
    static func handle(_ label: String) {
        let key = label
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
        if VesselShipperNavRoute.orbLabels.contains(key) {
            NotificationCenter.default.post(name: .eusoVesselShippereSangTapped, object: nil)
            return
        }
        guard let screenId = VesselShipperNavRoute.map[key] else { return }
        NotificationCenter.default.post(
            name: .eusoVesselShipperNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }
}

enum VesselOperatorNavRoute {
    static let map: [String: String] = [
        "home":       "Vesl650",
        "shipments":  "Vesl651",
        "compliance": "Vesl652",
        "me":         "Vesl656",
        // 2026-06-09 alias sweep (audit M24 / Wave-11 minors): the
        // operator-pool ports Vesl008/Vesl009 carry the legacy SVG
        // slot labels "Loads" / "Track" — no map entry made those
        // slots silent dead-taps. Alias the verbatim labels onto
        // registered operator screens (labels are wireframe-verbatim).
        "loads":      "Vesl651",   // Vessel Operator · Shipments board
        "track":      "Vesl660",   // Vessel · Live Position
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
