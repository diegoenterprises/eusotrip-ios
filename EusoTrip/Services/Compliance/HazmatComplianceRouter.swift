//
//  HazmatComplianceRouter.swift
//  T-027 (2026-05-20) — Hazmat compliance router.
//  49 CFR 172 (ERG) · 49 CFR 172.504 (placards) · 49 CFR 177.848 (segregation)
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
                    body: "Look up the UN number in ERG 2024 and confirm the emergency response info before posting.",
                    regulatoryRef: "49 CFR 172.602 / ERG 2024",
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
                    body: "Affix placards on all four sides + verify class number, UN number, and PSN are legible before departure.",
                    regulatoryRef: "49 CFR 172.504",
                    documentTypes: [.hazmatManifest]
                ))
            }
            if !hz.contains(.segregationVerified) {
                out.append(.init(
                    id: "haz.segregation",
                    routerKey: key,
                    severity: .blocker,
                    title: "Segregation table not verified",
                    body: "Cross-check loaded materials against 49 CFR 177.848 to ensure no incompatible classes share the trailer.",
                    regulatoryRef: "49 CFR 177.848",
                    documentTypes: [.segregationVerification]
                ))
            }
            if !hz.contains(.emergencyResponseReady) {
                out.append(.init(
                    id: "haz.emergency",
                    routerKey: key,
                    severity: .warning,
                    title: "Emergency response info not staged",
                    body: "Confirm shipping papers + CHEMTREC contact are within driver's reach.",
                    regulatoryRef: "49 CFR 172.602",
                    documentTypes: [.shippingPapers]
                ))
            }

        default:
            break
        }
        return out
    }
}
