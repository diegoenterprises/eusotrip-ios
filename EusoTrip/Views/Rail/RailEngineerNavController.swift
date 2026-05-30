//
//  RailEngineerNavController.swift
//  EusoTrip — Rail Engineer bottom-nav router.
//
//  Mirror of `ComplianceNavController` / `DispatchNavController` for the
//  RAIL_ENGINEER role. Canonical bottom-nav:
//
//      Home (house) · Shipments (shippingbox)
//      | Compliance (checkmark.shield) · Me (person)
//

import SwiftUI
import Combine

struct RailEngineerNavHandlerKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

extension EnvironmentValues {
    var railEngineerNavHandler: ((String) -> Void)? {
        get { self[RailEngineerNavHandlerKey.self] }
        set { self[RailEngineerNavHandlerKey.self] = newValue }
    }
}

extension Notification.Name {
    static let eusoRailNavSwap     = Notification.Name("eusoRailNavSwap")
    static let eusoRaileSangTapped = Notification.Name("eusoRaileSangTapped")
}

enum RailEngineerNavRoute {
    static let map: [String: String] = [
        "home":       "Rail550",
        "shipments":  "Rail551",
        "compliance": "Rail552",
        "me":         "Rail550",
    ]

    static let orbLabels: Set<String> = ["esang", "orb"]

    // Deep-surface routes (Rail553–590). NOT bottom-nav slots — these are the
    // 36 deep Rail Engineer screens, reachable by key via deep-link / push so
    // they're navigable beyond the 4 canonical tabs. Additive only; the bottom
    // nav `map` above is untouched.
    static let deepMap: [String: String] = [
        "shipmentDetail":      "Rail553",
        "crewHosRoster":       "Rail554",
        "consistBoard":        "Rail555",
        "account":             "Rail556",
        "statusUpdate":        "Rail557",
        "demurrageWatch":      "Rail558",
        "liveTracking":        "Rail560",
        "facilityStatus":      "Rail561",
        "gateAppointment":     "Rail562",
        "exceptionsHolds":     "Rail563",
        "borderClearance":     "Rail564",
        "containerTimeline":   "Rail565",
        "intermodalTransfer":  "Rail566",
        "chainOfCustody":      "Rail567",
        "equipmentLease":      "Rail568",
        "tenderWorkflow":      "Rail569",
        "imdgHazmatManifest":  "Rail571",
        "emissions":           "Rail572",
        "accessorialCharges":  "Rail573",
        "carrierScorecard":    "Rail574",
        "equipmentHealth":     "Rail575",
        "shipmentAmendment":   "Rail576",
        "fuelSurcharge":       "Rail577",
        "routeWeather":        "Rail578",
        "networkDisruption":   "Rail579",
        "tariffRateLookup":    "Rail580",
        "settlementSummary":   "Rail581",
        "rampSchedule":        "Rail582",
        "crossBorderInterchange": "Rail583",
        "crewCallBoard":       "Rail584",
        "equipmentPositions":  "Rail585",
        "serviceLineup":       "Rail586",
        "fraSafety":           "Rail587",
        "fleetHealth":         "Rail588",
        "transloadConnection": "Rail589",
        "documentIngest":      "Rail590",
    ]
}

@MainActor
enum RailEngineerNavDispatcher {
    static func handle(_ label: String) {
        let key = label.lowercased()

        if RailEngineerNavRoute.orbLabels.contains(key) {
            NotificationCenter.default.post(
                name: .eusoRaileSangTapped,
                object: nil
            )
            return
        }

        guard let screenId = RailEngineerNavRoute.map[key]
                ?? RailEngineerNavRoute.deepMap[label] else { return }
        NotificationCenter.default.post(
            name: .eusoRailNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }
}
