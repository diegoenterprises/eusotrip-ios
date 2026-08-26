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

        // 2026-08-17 · B/L + RELEASE-DOCUMENTS BAND (Vesl679/714/715/718/719/
        // 763/765/766/767/768). These ten screens shipped their SVG twins and
        // Swift ports but carried no route key, so every one of them was an
        // unreachable orphan while its own header asserted a SHIPMENTS mount.
        // Registering the keys is the whole cure; the bottom-nav `map` above
        // is untouched and the four canonical tabs are unchanged.
        //
        // Documents-of-title (negotiable — surrender/endorse gated):
        "telexRelease":       "Vesl679",
        "blDraftApproval":    "Vesl715",
        "cargoRelease":       "Vesl718",
        "electronicBL":       "Vesl719",
        "blDuplicateCheck":   "Vesl763",
        "letterOfCredit":     "Vesl765",
        "letterOfIndemnity":  "Vesl766",
        "masterHouseBL":      "Vesl768",
        // Non-negotiable / pre-issue documents:
        "shippingInstructions": "Vesl714",
        "seaWaybill":         "Vesl767",

        // 2026-08-18 · vessel §17 · PORT-FORMALITIES & RECORD-BOOKS BAND (844-853).
        // The last ten identities in the vessel catalog to reach Views/Vessel. They
        // are registered here as well as in the ContentView registry because the
        // 834-843 band above was given a registry row and never a route key, which
        // is the same unreachable-orphan class the B/L band was cured of earlier —
        // a registry entry is reachable from the surface list, a deep link or a push
        // payload still lands nowhere. Filed for 834-843 rather than fixed here,
        // because that band is not in this fire's claim manifest.
        //
        // MARPOL record books (regulated logbooks — signature is irreversible):
        "oilRecordBook":      "Vesl844",
        "garbageRecordBook":  "Vesl845",
        // Crew (MLC 2006 / STCW):
        "crewChange":         "Vesl846",
        "hoursOfRest":        "Vesl847",
        // Port formalities (IMO FAL Convention):
        "singleWindow":       "Vesl848",
        "generalDeclaration": "Vesl849",
        "shipStores":         "Vesl850",
        "portClearance":      "Vesl851",
        // Port account + sailing window:
        "portDisbursement":   "Vesl852",
        "tidalWindow":        "Vesl853",
    ]

    /// Case-insensitive resolution for `deepMap`. The map keys are lowerCamel
    /// by convention but deep links and push payloads arrive in whatever case
    /// the sender used; matching only the exact literal is how a registered
    /// route still reads as a dead tap in the field.
    static func deepRoute(for key: String) -> String? {
        if let hit = deepMap[key] { return hit }
        let folded = key.folding(options: .caseInsensitive, locale: nil)
        return deepMap.first { $0.key.folding(options: .caseInsensitive, locale: nil) == folded }?.value
    }
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
                ?? VesselOperatorNavRoute.deepRoute(for: label) else { return }
        NotificationCenter.default.post(
            name: .eusoVesselNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }
}
