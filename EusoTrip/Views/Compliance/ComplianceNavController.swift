//
//  ComplianceNavController.swift
//  EusoTrip 2027 UI — compliance-mode bottom-nav router.
//
//  Mirror of `ShipperNavController` / `CarrierNavController` for the
//  COMPLIANCE_OFFICER role. The canonical bottom-nav (sourced from
//  900_ComplianceOfficerHome.swift) is:
//
//      Home (house) · Drivers (person.3.fill)
//      | Audits (doc.text.magnifyingglass) · Me (person)
//
//  Routing: `Drivers` resolves to 901 Expiring Docs (closest surface
//  to a driver-document compliance board today); `Audits` resolves to
//  902 Violations (audit-trail board); `Me` routes to 900 home until
//  a dedicated Me brick lands.
//

import SwiftUI
import Combine

struct ComplianceNavHandlerKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

extension EnvironmentValues {
    var complianceNavHandler: ((String) -> Void)? {
        get { self[ComplianceNavHandlerKey.self] }
        set { self[ComplianceNavHandlerKey.self] = newValue }
    }
}

extension Notification.Name {
    static let eusoComplianceNavSwap     = Notification.Name("eusoComplianceNavSwap")
    static let eusoComplianceeSangTapped = Notification.Name("eusoComplianceeSangTapped")
}

enum ComplianceNavRoute {
    static let map: [String: String] = [
        "home":    "900",
        "drivers": "901",
        "audits":  "902",
        "me":      "900",
    ]

    static let orbLabels: Set<String> = ["esang", "orb"]
}

@MainActor
enum ComplianceNavDispatcher {
    static func handle(_ label: String) {
        let key = label.lowercased()

        if ComplianceNavRoute.orbLabels.contains(key) {
            NotificationCenter.default.post(
                name: .eusoComplianceeSangTapped,
                object: nil
            )
            return
        }

        guard let screenId = ComplianceNavRoute.map[key] else { return }
        NotificationCenter.default.post(
            name: .eusoComplianceNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }
}
