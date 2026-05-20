//
//  HeavyHaulComplianceRouter.swift
//  T-027 (2026-05-20) — Heavy haul / OS-OW compliance router.
//  Per-state OS/OW permits · 49 CFR 393 (securement) · 49 CFR 393.86 (bridge clearance).
//

import Foundation

public enum HeavyHaulComplianceRouter: ComplianceRouter {
    public static let key = "heavy_haul"

    public static func applies(
        vertical: Vertical,
        mode: TransportMode,
        isCrossBorder: Bool
    ) -> Bool {
        vertical == .heavyHaulSpecialized
    }

    public static func prompts(
        for transition: LoadStateTransition,
        overlays: CompositeLoadState?
    ) -> [CompliancePrompt] {
        var out: [CompliancePrompt] = []
        let hh = overlays?.heavyHaul ?? []

        switch transition.to {
        case .draft, .posted:
            if !hh.contains(.permitsVerified) {
                out.append(.init(
                    id: "heavy.permits",
                    routerKey: key,
                    severity: .blocker,
                    title: "OS/OW permits missing",
                    body: "Upload + verify the per-state OS/OW permits for every state the lane traverses before this load posts.",
                    regulatoryRef: "per-state DOT OS/OW",
                    documentTypes: [.osowPermits]
                ))
            }
            if !hh.contains(.routeSurveyComplete) {
                out.append(.init(
                    id: "heavy.routesurvey",
                    routerKey: key,
                    severity: .blocker,
                    title: "Route survey incomplete",
                    body: "Route survey must identify low bridges, weight-restricted roads, and pilot car staging points before posting.",
                    regulatoryRef: "carrier SOP / state DOT",
                    documentTypes: [.routeSurvey]
                ))
            }

        case .booked:
            if !hh.contains(.escortsAssigned) {
                out.append(.init(
                    id: "heavy.escorts",
                    routerKey: key,
                    severity: .blocker,
                    title: "Escort agreement not in place",
                    body: "Assign lead + chase + (if required) state trooper / bridge clearance pilot before booking.",
                    regulatoryRef: "49 CFR 393 / per-state escort rules",
                    documentTypes: [.escortAgreement]
                ))
            }

        case .loaded:
            if !hh.contains(.bridgeClearanceVerified) {
                out.append(.init(
                    id: "heavy.bridge",
                    routerKey: key,
                    severity: .blocker,
                    title: "Bridge clearance not verified",
                    body: "Driver must verify all bridges on the route meet the loaded height + weight before EN_ROUTE_TO_DELIVERY.",
                    regulatoryRef: "49 CFR 393.86",
                    documentTypes: [.bridgeClearanceDeclaration]
                ))
            }
            if !hh.contains(.convoyComposed) {
                out.append(.init(
                    id: "heavy.convoy",
                    routerKey: key,
                    severity: .warning,
                    title: "Convoy not composed",
                    body: "Multi-vehicle heavy-haul moves should be composed through 710A so the lifecycle FSM advances atomically across all vehicles.",
                    regulatoryRef: "carrier SOP",
                    documentTypes: []
                ))
            }

        default:
            break
        }
        return out
    }
}
