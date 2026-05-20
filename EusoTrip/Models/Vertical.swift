//
//  Vertical.swift
//  Canonical industry-vertical enum — locked from production wizard 2026-05-20.
//
//  This is the SOURCE OF TRUTH. Every Swift surface that references an industry
//  vertical (wizard, agreements, FSM overlays, compliance routing, fee multipliers,
//  driver checklists, broker rate sheets) must consume this enum. Adding/removing
//  a vertical here forces every downstream switch to be exhaustive at compile time.
//
//  Drop into: EusoTrip/Models/Vertical.swift
//

import Foundation

/// The 12 industry verticals supported by EusoTrip's Post-Load Wizard.
/// Order matches the production wizard's display order (Industry Vertical section).
public enum Vertical: String, CaseIterable, Codable, Hashable, Identifiable {
    case generalFreight          = "general_freight"
    case refrigerated            = "refrigerated"
    case hazmat                  = "hazmat"
    case tankerLiquidBulk        = "tanker_liquid_bulk"
    case flatbedOpenDeck         = "flatbed_open_deck"
    case autoTransport           = "auto_transport"
    case intermodalContainer     = "intermodal_container"
    case ltlPartial              = "ltl_partial"
    case heavyHaulSpecialized    = "heavy_haul_specialized"
    case livestock               = "livestock"
    case dryBulkPneumatic        = "dry_bulk_pneumatic"
    case householdGoods          = "household_goods"

    public var id: String { rawValue }

    /// Human-readable label as shown in the wizard.
    public var displayName: String {
        switch self {
        case .generalFreight:       return "General Freight"
        case .refrigerated:         return "Refrigerated / Temperature-Controlled"
        case .hazmat:               return "Hazardous Materials"
        case .tankerLiquidBulk:     return "Tanker / Liquid Bulk"
        case .flatbedOpenDeck:      return "Flatbed / Open Deck"
        case .autoTransport:        return "Auto Transport"
        case .intermodalContainer:  return "Intermodal / Container"
        case .ltlPartial:           return "LTL / Partial Load"
        case .heavyHaulSpecialized: return "Heavy Haul / Specialized"
        case .livestock:            return "Livestock / Live Animals"
        case .dryBulkPneumatic:     return "Dry Bulk / Pneumatic"
        case .householdGoods:       return "Household Goods / Moving"
        }
    }

    /// SF Symbol shown in the wizard card.
    public var systemImage: String {
        switch self {
        case .generalFreight:       return "shippingbox"
        case .refrigerated:         return "snowflake"
        case .hazmat:               return "exclamationmark.triangle"
        case .tankerLiquidBulk:     return "drop.fill"
        case .flatbedOpenDeck:      return "truck.box"
        case .autoTransport:        return "car.2"
        case .intermodalContainer:  return "cube.box"
        case .ltlPartial:           return "square.stack.3d.up"
        case .heavyHaulSpecialized: return "scalemass"
        case .livestock:            return "person.2"
        case .dryBulkPneumatic:     return "mountain.2"
        case .householdGoods:       return "house"
        }
    }

    /// Regulatory overlay applied to this vertical's FSM and document requirements.
    public var complianceOverlay: ComplianceOverlay {
        switch self {
        case .generalFreight:       return .none
        case .refrigerated:         return .coldChain
        case .hazmat:               return .hazmat
        case .tankerLiquidBulk:     return .tanker
        case .flatbedOpenDeck:      return .securement
        case .autoTransport:        return .autoTransport
        case .intermodalContainer:  return .intermodal
        case .ltlPartial:           return .ltl
        case .heavyHaulSpecialized: return .heavyHaul
        case .livestock:            return .livestock
        case .dryBulkPneumatic:     return .dryBulk
        case .householdGoods:       return .householdGoods
        }
    }

    /// True if this vertical normally implies hazardous cargo (drives placard + ERG flow).
    public var isHazmatVertical: Bool {
        switch self {
        case .hazmat, .tankerLiquidBulk: return true
        default: return false
        }
    }

    /// True if this vertical typically requires multi-vehicle composition.
    public var typicallyMultiVehicle: Bool {
        switch self {
        case .heavyHaulSpecialized, .autoTransport: return true
        default: return false
        }
    }
}

/// Regulatory overlay buckets — each one drives a unique FSM overlay state set,
/// document-requirement list, fee multiplier, and driver/dispatch UI branch.
public enum ComplianceOverlay: String, Codable, Hashable {
    case none
    case coldChain      // FSMA, FDA, USDA cold-chain
    case hazmat         // 49 CFR 172, ERG, placards, segregation (177.848)
    case tanker         // 49 CFR 178, vapor recovery, tank wash
    case securement     // 49 CFR 393
    case autoTransport  // 49 CFR 393.130, per-vehicle VCRs
    case intermodal     // AAR, ISO 1496, UIIA, EIR
    case ltl            // NMFC freight class
    case heavyHaul      // OS/OW permits, escorts, route surveys, bridge clearance
    case livestock      // USDA health cert, 28-hr law (FMCSA 395.8 livestock)
    case dryBulk        // bonded sites, dust suppression, prior commodity wash
    case householdGoods // 49 CFR 375, HHG BOL, inventory, valuation
}
