//
//  LivestockComplianceRouter.swift
//  T-027 (2026-05-20) — Livestock compliance router.
//  USDA health cert · 49 USC 80502 / FMCSA 395.8 (28-hr law).
//

import Foundation

public enum LivestockComplianceRouter: ComplianceRouter {
    public static let key = "livestock"

    public static func applies(
        vertical: Vertical,
        mode: TransportMode,
        isCrossBorder: Bool
    ) -> Bool {
        vertical == .livestock
    }

    public static func prompts(
        for transition: LoadStateTransition,
        overlays: CompositeLoadState?
    ) -> [CompliancePrompt] {
        var out: [CompliancePrompt] = []
        let ls = overlays?.livestock ?? []

        switch transition.to {
        case .draft, .posted:
            if !ls.contains(.healthCertOnFile) {
                out.append(.init(
                    id: "livestock.healthcert",
                    routerKey: key,
                    severity: .blocker,
                    title: "USDA health certificate missing",
                    body: "Shipper must upload the species-specific USDA health certificate before livestock load posts.",
                    regulatoryRef: "9 CFR 91 / USDA APHIS",
                    documentTypes: [.usdaHealthCertificate]
                ))
            }

        case .atPickup:
            if !ls.contains(.usdaInspectionPassed) {
                out.append(.init(
                    id: "livestock.usdainspect",
                    routerKey: key,
                    severity: .blocker,
                    title: "USDA inspection not logged",
                    body: "Pre-load USDA / state veterinary inspection must be logged before animals can be loaded.",
                    regulatoryRef: "9 CFR 91 / state vet",
                    documentTypes: [.usdaHealthCertificate, .animalWelfareCert]
                ))
            }

        case .loaded:
            if !ls.contains(.timer28hArmed) {
                out.append(.init(
                    id: "livestock.timer",
                    routerKey: key,
                    severity: .blocker,
                    title: "28-hr timer not armed",
                    body: "Arm the 28-hr clock at loaded-doors-closed. Animals can't be in continuous transit more than 28 hours without food, water, and rest.",
                    regulatoryRef: "49 USC 80502 / FMCSA 395.8",
                    documentTypes: [.livestock28HrLog]
                ))
            }

        case .enRouteToDelivery, .atDelivery:
            // Rest-required prompt — if the FSM transition was triggered
            // while the timer was past 28h, escalate to blocker.
            if ls.contains(.restRequired) {
                out.append(.init(
                    id: "livestock.rest",
                    routerKey: key,
                    severity: .blocker,
                    title: "28-hr rest stop required",
                    body: "Animals have been in transit > 28h. Driver must pull to a pen / rest stop with food + water before continuing.",
                    regulatoryRef: "49 USC 80502",
                    documentTypes: [.livestock28HrLog]
                ))
            }

        default:
            break
        }
        return out
    }
}
