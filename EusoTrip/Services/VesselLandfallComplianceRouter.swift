//
//  VesselLandfallComplianceRouter.swift
//  EusoTrip
//
//  IMO SOLAS · USCG (US) · TC (CA) · SEMAR (MX).
//

import Foundation

public enum VesselLandfallComplianceRouter: ComplianceRouter {
    public static let key = "vessel_landfall"

    public static func applies(
        vertical: Vertical,
        mode: TransportMode,
        isCrossBorder: Bool
    ) -> Bool {
        mode == .vessel
    }

    public static func prompts(
        for transition: LoadStateTransition,
        overlays: CompositeLoadState?
    ) -> [CompliancePrompt] {
        var out: [CompliancePrompt] = []
        let vl = overlays?.vesselLandfall ?? []

        switch transition.to {
        case .enRouteToDelivery:
            if !vl.contains(.noticeOfArrival) {
                out.append(.init(
                    id: "vsl.noa",
                    routerKey: key,
                    severity: .blocker,
                    title: "Notice of Arrival (NOA) missing",
                    body: "A 96-hour or 24-hour Notice of Arrival (NOA) must be filed with the destination port authority before landfall.",
                    regulatoryRef: "33 CFR 160.212 / IMO SOLAS",
                    documentTypes: [.vesselNoa]
                ))
            }
            if !vl.contains(.healthCleared) {
                out.append(.init(
                    id: "vsl.pratique",
                    routerKey: key,
                    severity: .warning,
                    title: "Free Pratique pending",
                    body: "Health clearance (Free Pratique) is required before vessel berthing. Awaiting port health officer clearance.",
                    regulatoryRef: "42 CFR 71.31",
                    documentTypes: []
                ))
            }

        case .atDelivery:
            if !vl.contains(.customsReleased) {
                out.append(.init(
                    id: "vsl.customs",
                    routerKey: key,
                    severity: .blocker,
                    title: "Vessel customs release missing",
                    body: "The vessel and its cargo must be cleared by customs (CBP / CBSA / SAT) before discharge begins.",
                    regulatoryRef: "19 CFR 4.30",
                    documentTypes: [.customsRelease]
                ))
            }
            if !vl.contains(.securityCleared) {
                out.append(.init(
                    id: "vsl.isps",
                    routerKey: key,
                    severity: .blocker,
                    title: "ISPS security clearance missing",
                    body: "International Ship and Port Facility Security (ISPS) clearance is required before cargo operations.",
                    regulatoryRef: "ISPS Code Part A",
                    documentTypes: []
                ))
            }

        default:
            break
        }
        return out
    }
}
