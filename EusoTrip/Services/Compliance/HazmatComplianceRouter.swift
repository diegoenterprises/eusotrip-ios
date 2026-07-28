//
//  HazmatComplianceRouter.swift
//  T-027 (2026-05-20) — Hazmat compliance router.
//  Jurisdiction-neutral client prompts. The live server checklist binds
//  US / Canadian / Mexican citations from the load's origin country.
//

import Foundation

public enum HazmatComplianceRouter: ComplianceRouter {
    public static let key = "hazmat"

    public static func applies(
        vertical: Vertical,
        mode: TransportMode,
        isCrossBorder: Bool
    ) -> Bool {
        vertical == .hazmat || vertical == .tankerLiquidBulk
    }

    public static func prompts(
        for transition: LoadStateTransition,
        overlays: CompositeLoadState?
    ) -> [CompliancePrompt] {
        var out: [CompliancePrompt] = []
        let hz = overlays?.hazmat ?? []

        // ERG verification — required at DRAFT before posting.
        switch transition.to {
        case .draft, .posted:
            if !hz.contains(.ergVerified) {
                out.append(.init(
                    id: "haz.erg",
                    routerKey: key,
                    severity: .blocker,
                    title: "ERG verification required",
                    body: "Confirm the shipping-paper UN number, then open its ERG 2024 response guide before posting. ERG is not classification evidence.",
                    regulatoryRef: "ERG 2024 response reference; controlling jurisdiction required",
                    documentTypes: [.ergInfo, .shippingPapers]
                ))
            }

        // Placards — must be affixed at LOADED (visible on every side).
        case .loaded:
            if !hz.contains(.placardsAffixed) {
                out.append(.init(
                    id: "haz.placards",
                    routerKey: key,
                    severity: .blocker,
                    title: "Placards not affixed",
                    body: "Compare the shipping-paper classification with every required placard and inspect every position required by the controlling jurisdiction before departure.",
                    regulatoryRef: "Controlling-jurisdiction dangerous-goods placarding rules",
                    documentTypes: [.hazmatManifest]
                ))
            }
            if !hz.contains(.segregationVerified) {
                out.append(.init(
                    id: "haz.segregation",
                    routerKey: key,
                    severity: .blocker,
                    title: "Segregation table not verified",
                    body: "Cross-check every loaded dangerous good against the controlling jurisdiction's compatibility and segregation requirements.",
                    regulatoryRef: "Controlling-jurisdiction compatibility and segregation rules",
                    documentTypes: [.segregationVerification]
                ))
            }
            if !hz.contains(.emergencyResponseReady) {
                out.append(.init(
                    id: "haz.emergency",
                    routerKey: key,
                    severity: .warning,
                    title: "Emergency response info not staged",
                    body: "Confirm the shipping document and shipment-specific emergency contact information are staged as required for the route.",
                    regulatoryRef: "Controlling-jurisdiction emergency-information rules",
                    documentTypes: [.shippingPapers]
                ))
            }

        default:
            break
        }
        return out
    }
}
