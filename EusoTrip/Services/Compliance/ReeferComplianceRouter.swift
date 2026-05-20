//
//  ReeferComplianceRouter.swift
//  T-027 (2026-05-20) — Refrigerated cold-chain compliance router.
//  FSMA 2011 · 21 CFR 1.900 · FDA cold-chain rule.
//

import Foundation

public enum ReeferComplianceRouter: ComplianceRouter {
    public static let key = "reefer"

    public static func applies(
        vertical: Vertical,
        mode: TransportMode,
        isCrossBorder: Bool
    ) -> Bool {
        vertical == .refrigerated
    }

    public static func prompts(
        for transition: LoadStateTransition,
        overlays: CompositeLoadState?
    ) -> [CompliancePrompt] {
        var out: [CompliancePrompt] = []
        let rf = overlays?.reefer ?? []

        switch transition.to {
        case .draft, .posted:
            if !rf.contains(.fsmaCertificateOnFile) {
                out.append(.init(
                    id: "reefer.fsma",
                    routerKey: key,
                    severity: .blocker,
                    title: "FSMA certificate missing",
                    body: "Carrier must have a current FSMA 2011 sanitary transport certificate on file before this load posts.",
                    regulatoryRef: "FSMA 2011 / 21 CFR 1.900",
                    documentTypes: [.fsmaCertificate]
                ))
            }

        case .atPickup, .loaded:
            if !rf.contains(.tempSetpointConfirmed) {
                out.append(.init(
                    id: "reefer.setpoint",
                    routerKey: key,
                    severity: .blocker,
                    title: "Temperature setpoint not confirmed",
                    body: "Driver must enter the loading-temp setpoint + verify the reefer unit reflects it before leaving the dock.",
                    regulatoryRef: "FSMA 2011 · shipper-required temp",
                    documentTypes: [.temperatureSetpoint]
                ))
            }

        case .atDelivery, .unloaded:
            if !rf.contains(.coldChainVerified) {
                out.append(.init(
                    id: "reefer.coldchain",
                    routerKey: key,
                    severity: .blocker,
                    title: "Cold-chain verification pending",
                    body: "Download the reefer's temperature log and confirm the trace stayed within tolerance before signing POD.",
                    regulatoryRef: "FSMA 2011 · 21 CFR 1.908",
                    documentTypes: [.coldChainAttestation, .temperatureSetpoint]
                ))
            }

        case .podSigned, .delivered:
            if !rf.contains(.tempLogSealed) {
                out.append(.init(
                    id: "reefer.logseal",
                    routerKey: key,
                    severity: .warning,
                    title: "Temp log not sealed",
                    body: "Seal the reefer temp log to lock the data trail for the receiver's audit chain.",
                    regulatoryRef: "FSMA 2011 record-keeping",
                    documentTypes: [.coldChainAttestation]
                ))
            }

        default:
            break
        }
        return out
    }
}
