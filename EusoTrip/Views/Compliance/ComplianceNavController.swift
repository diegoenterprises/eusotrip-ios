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
//  902 Violations (audit-trail board); `Me` resolves to the dedicated
//  903 Compliance Me hub.
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

enum ComplianceNavTab {
    case home, drivers, audits, me, none
}

enum ComplianceNavRoute {
    enum Destination: String {
        case home = "900"
        case drivers = "901"
        case audits = "902"
        case me = "903"
    }

    private static let map: [String: Destination] = [
        "home": .home,
        "drivers": .drivers,
        "audits": .audits,
        "me": .me,
        // 2026-06-09 alias sweep (audit M24 / Wave-11 minors): 1111
        // OnboardingWizard's chrome labels its slots "Tiers" / "Docs".
        // "docs" aliases onto the registered Expiring Docs board.
        // "tiers" is intentionally UNMAPPED: it is only ever emitted by
        // 1111's own current slot, and the wizard is not a registered
        // ScreenRegistry surface (RIOS flow hosts it directly) — there
        // is no honest registered destination to alias it to. Current-
        // tab taps are no-ops by convention, so the slot stays inert
        // rather than fabricating a target.
        "docs": .drivers,
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

    static func leading(current: ComplianceNavTab = .none) -> [NavSlot] {
        [NavSlot(label: "Home", systemImage: "house", isCurrent: current == .home),
         NavSlot(label: "Drivers", systemImage: "person.3.fill", isCurrent: current == .drivers)]
    }

    static func trailing(current: ComplianceNavTab = .none) -> [NavSlot] {
        [NavSlot(label: "Audits", systemImage: "doc.text.magnifyingglass", isCurrent: current == .audits),
         NavSlot(label: "Me", systemImage: "person", isCurrent: current == .me)]
    }
}

@MainActor
enum ComplianceNavDispatcher {
    static func handle(_ label: String) {
        if ComplianceNavRoute.isOrb(label) {
            NotificationCenter.default.post(
                name: .eusoComplianceeSangTapped,
                object: nil
            )
            return
        }

        guard let screenId = ComplianceNavRoute.screenId(for: label) else { return }
        NotificationCenter.default.post(
            name: .eusoComplianceNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }
}
