//
//  EldComplianceRouter.swift
//  EusoTrip
//
//  FMCSA 49 CFR 395 · SOR/2005-313 (CA) · NOM-087-SCT (MX).
//

import Foundation

public enum EldComplianceRouter: ComplianceRouter {
    public static let key = "eld"

    public static func applies(
        vertical: Vertical,
        mode: TransportMode,
        isCrossBorder: Bool
    ) -> Bool {
        mode == .truck
    }

    public static func prompts(
        for transition: LoadStateTransition,
        overlays: CompositeLoadState?
    ) -> [CompliancePrompt] {
        var out: [CompliancePrompt] = []
        guard let eld = overlays?.eld else {
            switch transition.to {
            case .enRouteToPickup, .enRouteToDelivery:
                out.append(.init(
                    id: "eld.evidence.unavailable",
                    routerKey: key,
                    severity: .blocker,
                    title: "ELD evidence unavailable",
                    body: "Current ELD and HOS evidence was not returned. This move remains blocked until the source refreshes.",
                    regulatoryRef: "49 CFR 395.22 / SOR-2005-313",
                    documentTypes: []
                ))
            case .delivered:
                out.append(.init(
                    id: "eld.certification.evidence.unavailable",
                    routerKey: key,
                    severity: .warning,
                    title: "Log certification evidence unavailable",
                    body: "The current log-certification state was not returned. No certification status is inferred.",
                    regulatoryRef: "49 CFR 395.30",
                    documentTypes: []
                ))
            default:
                break
            }
            return out
        }

        switch transition.to {
        case .enRouteToPickup, .enRouteToDelivery:
            if !eld.contains(.eldConnected) {
                out.append(.init(
                    id: "eld.connect",
                    routerKey: key,
                    severity: .blocker,
                    title: "ELD not connected",
                    body: "A registered ELD is required for this move per 49 CFR 395.22. Connect your provider in the ELD surface.",
                    regulatoryRef: "49 CFR 395.22 / SOR-2005-313",
                    documentTypes: []
                ))
            }
            if eld.contains(.violationActive) {
                out.append(.init(
                    id: "eld.violation",
                    routerKey: key,
                    severity: .blocker,
                    title: "Active HOS violation",
                    body: "An active Hours of Service violation is recorded. You must clear the violation or reset your cycle before proceeding.",
                    regulatoryRef: "49 CFR 395.3 / NOM-087-SCT",
                    documentTypes: []
                ))
            }
            if eld.contains(.breakRequired) {
                out.append(.init(
                    id: "eld.break",
                    routerKey: key,
                    severity: .warning,
                    title: "30-minute break required",
                    body: "You are approaching your 8-hour driving limit. A 30-minute off-duty break is required.",
                    regulatoryRef: "49 CFR 395.3(a)(3)(ii)",
                    documentTypes: []
                ))
            }

        case .delivered:
            if !eld.contains(.logsCertified) {
                out.append(.init(
                    id: "eld.certify",
                    routerKey: key,
                    severity: .warning,
                    title: "Daily logs not certified",
                    body: "Certify your daily logs for the current cycle to complete the compliance record.",
                    regulatoryRef: "49 CFR 395.30",
                    documentTypes: []
                ))
            }

        default:
            break
        }
        return out
    }
}
