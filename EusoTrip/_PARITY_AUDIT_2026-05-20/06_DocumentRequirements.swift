//
//  DocumentRequirements.swift
//  Canonical per-vertical document requirements — locks the Agreement Wizard
//  output to a typed contract.
//
//  Audit found 0 of 13 document suites wired in 223A_AgreementWizard.swift.
//  This file declares every required document per vertical (and the cross-border
//  overlay), so the agreement wizard can switch exhaustively and refuse to post
//  a load without all required documents attached.
//
//  Drop into: EusoTrip/Models/DocumentRequirements.swift
//

import Foundation

/// Every document type the platform tracks across all verticals.
public enum DocumentType: String, CaseIterable, Codable, Hashable {
    // Universal
    case billOfLading                       = "bill_of_lading"
    case rateConfirmation                   = "rate_confirmation"
    case commercialInvoice                  = "commercial_invoice"
    case packingList                        = "packing_list"
    case proofOfDelivery                    = "proof_of_delivery"
    case insuranceCertificate               = "insurance_certificate"

    // Hazmat
    case hazmatManifest                     = "hazmat_manifest_172_201"
    case shippingPapers                     = "shipping_papers"
    case ergInfo                            = "erg_emergency_response_info"
    case driverHazmatTrainingCert           = "driver_hazmat_training_cert"
    case segregationVerification            = "segregation_verification_177_848"

    // Tanker / liquid bulk
    case tankWashCertificate                = "tank_wash_certificate"
    case priorCommodityHistory              = "prior_three_commodities"
    case vaporRecoveryDeclaration           = "vapor_recovery_declaration"

    // Reefer / food-grade
    case temperatureSetpoint                = "temperature_setpoint"
    case fsmaCertificate                    = "fsma_certificate"
    case coldChainAttestation               = "cold_chain_attestation"
    case foodGradeWashCert                  = "food_grade_wash_cert"

    // Flatbed / open deck
    case securementLog                      = "securement_log_393"
    case tarpInventory                      = "tarp_inventory"
    case strapWLLLog                        = "strap_wll_log"

    // Auto transport
    case vehicleConditionReport             = "vehicle_condition_report"

    // Intermodal
    case uiiaInterchangeAgreement           = "uiia_interchange_agreement"
    case equipmentInterchangeReceipt        = "equipment_interchange_receipt"
    case containerSealLog                   = "container_seal_log"

    // LTL
    case nmfcFreightClassDeclaration        = "nmfc_freight_class"

    // Heavy haul
    case osowPermits                        = "osow_permits"
    case escortAgreement                    = "escort_agreement"
    case routeSurvey                        = "route_survey"
    case bridgeClearanceDeclaration         = "bridge_clearance"

    // Livestock
    case usdaHealthCertificate              = "usda_health_certificate"
    case animalWelfareCert                  = "animal_welfare_cert"
    case livestock28HrLog                   = "livestock_28hr_log"

    // Dry bulk
    case kosherCertificate                  = "kosher_cert"
    case halalCertificate                   = "halal_cert"

    // Household goods
    case hhgBillOfLading_375                = "hhg_bol_49_cfr_375"
    case householdInventory                 = "household_inventory"
    case valuationDeclaration               = "valuation_declaration"
    case customerReleaseAuthorization       = "customer_release_authorization"

    // Cross-border
    case usmcaCertificateOfOrigin           = "usmca_certificate_of_origin"
    case pedimentoMx                        = "pedimento_mx"
    case cartaPorte                         = "carta_porte_mx"
    case manifestUsAce                      = "manifest_us_ace"
    case rppCaCarm                          = "rpp_ca_carm"
    case importExportLicense                = "import_export_license"
}

public struct DocumentRequirement: Codable, Hashable {
    public let document: DocumentType
    public let requiredAt: LoadState        // when this document must be on file by
    public let blocking: Bool               // if true, FSM cannot advance past requiredAt without it
    public let regulatoryRef: String?       // e.g., "49 CFR 172.201", "USMCA Annex 5-A"
}

public enum DocumentRequirements {

    /// Canonical per-vertical document requirements. Used by the Agreement Wizard
    /// to build the document checklist when the load is posted, and by the FSM
    /// guard to block transitions to LOADED / DELIVERED if blocking docs are missing.
    public static func forVertical(_ v: Vertical) -> [DocumentRequirement] {
        switch v {
        case .generalFreight:
            return [
                .init(document: .billOfLading,     requiredAt: .loaded, blocking: true,  regulatoryRef: "49 CFR 373.101"),
                .init(document: .rateConfirmation, requiredAt: .booked, blocking: true,  regulatoryRef: nil),
            ]
        case .refrigerated:
            return [
                .init(document: .billOfLading,         requiredAt: .loaded,    blocking: true,  regulatoryRef: nil),
                .init(document: .temperatureSetpoint,  requiredAt: .atPickup,  blocking: true,  regulatoryRef: "FSMA 2011"),
                .init(document: .fsmaCertificate,      requiredAt: .draft,     blocking: true,  regulatoryRef: "21 CFR 1.900"),
                .init(document: .coldChainAttestation, requiredAt: .delivered, blocking: false, regulatoryRef: nil),
            ]
        case .hazmat:
            return [
                .init(document: .billOfLading,               requiredAt: .loaded, blocking: true, regulatoryRef: nil),
                .init(document: .hazmatManifest,             requiredAt: .loaded, blocking: true, regulatoryRef: "49 CFR 172.201"),
                .init(document: .shippingPapers,             requiredAt: .loaded, blocking: true, regulatoryRef: "49 CFR 172.200"),
                .init(document: .ergInfo,                    requiredAt: .loaded, blocking: true, regulatoryRef: "49 CFR 172.602 / ERG 2024"),
                .init(document: .driverHazmatTrainingCert,   requiredAt: .booked, blocking: true, regulatoryRef: "49 CFR 172.704"),
                .init(document: .segregationVerification,    requiredAt: .loaded, blocking: true, regulatoryRef: "49 CFR 177.848"),
            ]
        case .tankerLiquidBulk:
            return [
                .init(document: .billOfLading,             requiredAt: .loaded, blocking: true,  regulatoryRef: nil),
                .init(document: .tankWashCertificate,      requiredAt: .atPickup, blocking: true, regulatoryRef: nil),
                .init(document: .priorCommodityHistory,    requiredAt: .atPickup, blocking: true, regulatoryRef: nil),
                .init(document: .vaporRecoveryDeclaration, requiredAt: .loaded, blocking: false, regulatoryRef: "EPA Stage II"),
            ]
        case .flatbedOpenDeck:
            return [
                .init(document: .billOfLading,    requiredAt: .loaded, blocking: true,  regulatoryRef: nil),
                .init(document: .securementLog,   requiredAt: .loaded, blocking: true,  regulatoryRef: "49 CFR 393"),
                .init(document: .tarpInventory,   requiredAt: .loaded, blocking: false, regulatoryRef: nil),
                .init(document: .strapWLLLog,     requiredAt: .loaded, blocking: true,  regulatoryRef: "49 CFR 393.108"),
            ]
        case .autoTransport:
            return [
                .init(document: .billOfLading,           requiredAt: .loaded, blocking: true, regulatoryRef: nil),
                .init(document: .vehicleConditionReport, requiredAt: .atPickup, blocking: true, regulatoryRef: "49 CFR 393.130"),
            ]
        case .intermodalContainer:
            return [
                .init(document: .billOfLading,                  requiredAt: .loaded,    blocking: true, regulatoryRef: nil),
                .init(document: .uiiaInterchangeAgreement,      requiredAt: .booked,    blocking: true, regulatoryRef: "UIIA"),
                .init(document: .equipmentInterchangeReceipt,   requiredAt: .atPickup,  blocking: true, regulatoryRef: nil),
                .init(document: .containerSealLog,              requiredAt: .loaded,    blocking: true, regulatoryRef: "ISO 17712"),
            ]
        case .ltlPartial:
            return [
                .init(document: .billOfLading,                requiredAt: .loaded, blocking: true, regulatoryRef: nil),
                .init(document: .nmfcFreightClassDeclaration, requiredAt: .posted, blocking: true, regulatoryRef: "NMFC"),
            ]
        case .heavyHaulSpecialized:
            return [
                .init(document: .billOfLading,                  requiredAt: .loaded,    blocking: true,  regulatoryRef: nil),
                .init(document: .osowPermits,                   requiredAt: .booked,    blocking: true,  regulatoryRef: "state-by-state"),
                .init(document: .escortAgreement,               requiredAt: .booked,    blocking: true,  regulatoryRef: nil),
                .init(document: .routeSurvey,                   requiredAt: .draft,     blocking: true,  regulatoryRef: nil),
                .init(document: .bridgeClearanceDeclaration,    requiredAt: .loaded,    blocking: true,  regulatoryRef: nil),
            ]
        case .livestock:
            return [
                .init(document: .billOfLading,              requiredAt: .loaded,    blocking: true, regulatoryRef: nil),
                .init(document: .usdaHealthCertificate,     requiredAt: .atPickup,  blocking: true, regulatoryRef: "9 CFR 91"),
                .init(document: .animalWelfareCert,         requiredAt: .draft,     blocking: false, regulatoryRef: nil),
                .init(document: .livestock28HrLog,          requiredAt: .loaded,    blocking: true, regulatoryRef: "49 USC 80502 / 28-Hour Law"),
            ]
        case .dryBulkPneumatic:
            return [
                .init(document: .billOfLading,           requiredAt: .loaded,   blocking: true,  regulatoryRef: nil),
                .init(document: .tankWashCertificate,    requiredAt: .atPickup, blocking: true,  regulatoryRef: nil),
                .init(document: .priorCommodityHistory,  requiredAt: .atPickup, blocking: true,  regulatoryRef: nil),
                .init(document: .kosherCertificate,      requiredAt: .draft,    blocking: false, regulatoryRef: nil),
                .init(document: .halalCertificate,       requiredAt: .draft,    blocking: false, regulatoryRef: nil),
            ]
        case .householdGoods:
            return [
                .init(document: .hhgBillOfLading_375,           requiredAt: .loaded,   blocking: true, regulatoryRef: "49 CFR 375"),
                .init(document: .householdInventory,            requiredAt: .atPickup, blocking: true, regulatoryRef: "49 CFR 375.401"),
                .init(document: .valuationDeclaration,          requiredAt: .draft,    blocking: true, regulatoryRef: "49 CFR 375.701"),
                .init(document: .customerReleaseAuthorization,  requiredAt: .delivered, blocking: true, regulatoryRef: nil),
            ]
        }
    }

    /// Cross-border overlay — appended to the vertical's requirements when the
    /// load crosses any US/MX/CA border.
    public static let crossBorder: [DocumentRequirement] = [
        .init(document: .usmcaCertificateOfOrigin,  requiredAt: .draft, blocking: true, regulatoryRef: "USMCA Annex 5-A"),
        .init(document: .commercialInvoice,         requiredAt: .draft, blocking: true, regulatoryRef: nil),
        .init(document: .packingList,               requiredAt: .draft, blocking: true, regulatoryRef: nil),
        .init(document: .importExportLicense,       requiredAt: .draft, blocking: false, regulatoryRef: nil),
        .init(document: .manifestUsAce,             requiredAt: .atPickup, blocking: true, regulatoryRef: "CBP Form 7533"),
        .init(document: .pedimentoMx,               requiredAt: .atPickup, blocking: true, regulatoryRef: "Ley Aduanera"),
        .init(document: .cartaPorte,                requiredAt: .atPickup, blocking: true, regulatoryRef: "SAT Carta Porte 2024"),
        .init(document: .rppCaCarm,                 requiredAt: .atPickup, blocking: true, regulatoryRef: "CBSA CARM"),
    ]

    /// Full required-document list for a (vertical, isCrossBorder) tuple.
    public static func forShipment(vertical: Vertical, isCrossBorder: Bool) -> [DocumentRequirement] {
        var docs = forVertical(vertical)
        if isCrossBorder { docs.append(contentsOf: crossBorder) }
        return docs
    }

    /// True if every blocking document for this shipment is on file.
    public static func allBlockingDocsPresent(
        attached: Set<DocumentType>,
        vertical: Vertical,
        isCrossBorder: Bool,
        currentState: LoadState
    ) -> Bool {
        let required = forShipment(vertical: vertical, isCrossBorder: isCrossBorder)
        for req in required where req.blocking {
            // Only enforce if we have reached or passed the required-at state
            let hasReached = currentState.rawValue >= req.requiredAt.rawValue || currentState == req.requiredAt
            if hasReached && !attached.contains(req.document) {
                return false
            }
        }
        return true
    }
}
