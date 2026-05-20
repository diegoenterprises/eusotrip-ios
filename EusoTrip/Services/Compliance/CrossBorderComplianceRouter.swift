//
//  CrossBorderComplianceRouter.swift
//  T-027 (2026-05-20) — Cross-border (US/MX/CA) compliance router.
//  USMCA Annex 5-A · CBP ACE (US) · CBSA CARM (CA) · SAT Carta Porte (MX).
//

import Foundation

public enum CrossBorderComplianceRouter: ComplianceRouter {
    public static let key = "cross_border"

    public static func applies(
        vertical: Vertical,
        mode: TransportMode,
        isCrossBorder: Bool
    ) -> Bool {
        isCrossBorder
    }

    public static func prompts(
        for transition: LoadStateTransition,
        overlays: CompositeLoadState?
    ) -> [CompliancePrompt] {
        var out: [CompliancePrompt] = []
        let cb = overlays?.crossBorder ?? []

        switch transition.to {
        case .draft, .posted:
            if !cb.contains(.usmcaCertificateOnFile) {
                out.append(.init(
                    id: "cb.usmca",
                    routerKey: key,
                    severity: .blocker,
                    title: "USMCA Certificate of Origin missing",
                    body: "Upload USMCA Certificate of Origin if claiming preferential treatment. Required for tariff-free clearance.",
                    regulatoryRef: "USMCA Annex 5-A",
                    documentTypes: [.usmcaCertificateOfOrigin, .commercialInvoice, .packingList]
                ))
            }

        case .atPickup:
            // Customs filings — must be filed before pickup so they can
            // clear during transit.
            if !cb.contains(.customsFiled) {
                out.append(.init(
                    id: "cb.customsfile",
                    routerKey: key,
                    severity: .blocker,
                    title: "Customs filing not submitted",
                    body: "Submit destination-country customs filing (US-ACE / CA-CARM / MX-SAT) before pickup so the load can clear at the border without delay.",
                    regulatoryRef: "CBP ACE · CBSA CARM · SAT Carta Porte",
                    documentTypes: [.manifestUsAce, .rppCaCarm, .cartaPorte, .pedimentoMx]
                ))
            }

        case .enRouteToDelivery:
            // Approaching the border — if customs hasn't cleared yet,
            // surface the lane status.
            if !cb.contains(.customsCleared) {
                out.append(.init(
                    id: "cb.customsstatus",
                    routerKey: key,
                    severity: .warning,
                    title: "Customs clearance pending",
                    body: "Filing accepted, awaiting clearance. Driver should stage at the broker's holding area if clearance hasn't fired by arrival.",
                    regulatoryRef: "CBP ACE",
                    documentTypes: []
                ))
            }

        case .atDelivery:
            if !cb.contains(.clearedBorder) {
                out.append(.init(
                    id: "cb.clearance",
                    routerKey: key,
                    severity: .blocker,
                    title: "Border clearance not recorded",
                    body: "Border-crossing event must be logged + signed before delivery POD. Customs broker confirms the crossing.",
                    regulatoryRef: "CBP / CBSA / SAT",
                    documentTypes: [.manifestUsAce, .cartaPorte]
                ))
            }

        default:
            break
        }
        return out
    }
}
