//
//  TrailerCode.swift
//  Canonical trailer / equipment code enum — locked from production wizard 2026-05-20.
//
//  23 trailer types. This enum is the only legal way to reference equipment in
//  Swift code. Display strings ("53' Dry Van", "MC-306 Tanker") MUST resolve through
//  this enum. Server payloads MUST use the rawValue. Animation files MUST key off it.
//
//  Drop into: EusoTrip/Models/TrailerCode.swift
//

import Foundation

/// The 23 trailer / equipment types supported by EusoTrip's Post-Load Wizard.
/// Order matches the production wizard's display order (All Trailer Types section).
public enum TrailerCode: String, CaseIterable, Codable, Hashable, Identifiable {
    // Hazmat-eligible (4)
    case liquidTank             = "liquid_tank"
    case pressurizedGasTank     = "pressurized_gas_tank"
    case cryogenicTank          = "cryogenic_tank"
    case hazmatBox              = "hazmat_box"

    // General + temperature-controlled
    case dryVan                 = "dry_van"
    case reefer                 = "reefer"

    // Open deck / specialized
    case standardFlatbed        = "standard_flatbed"
    case stepDeck               = "step_deck"
    case lowboyRgn              = "lowboy_rgn"
    case doubleDrop             = "double_drop"
    case conestoga              = "conestoga"
    case autoCarrier            = "auto_carrier"

    // Live + raw materials
    case livestockCattlePot     = "livestock_cattle_pot"
    case logTrailer             = "log_trailer"

    // Bulk hopper family
    case dryBulkHopper          = "dry_bulk_hopper"
    case gravityHopper          = "gravity_hopper"
    case grainHopper            = "grain_hopper"

    // Specialty tank + dump
    case pneumaticTank          = "pneumatic_tank"
    case endDump                = "end_dump"
    case foodGradeLiquidTank    = "food_grade_liquid_tank"
    case waterTank              = "water_tank"

    // Intermodal + curtain
    case intermodalChassis      = "intermodal_chassis"
    case curtainSide            = "curtain_side"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .liquidTank:           return "Liquid Tank Trailer"
        case .pressurizedGasTank:   return "Pressurized Gas Tank"
        case .cryogenicTank:        return "Cryogenic Tank"
        case .hazmatBox:            return "Hazmat Box / Van"
        case .dryVan:               return "Dry Van"
        case .reefer:               return "Refrigerated (Reefer)"
        case .standardFlatbed:      return "Standard Flatbed"
        case .stepDeck:             return "Step Deck / Drop Deck"
        case .lowboyRgn:            return "Lowboy / RGN"
        case .doubleDrop:           return "Double Drop / Stretch"
        case .conestoga:            return "Conestoga (Rolling-Tarp)"
        case .autoCarrier:          return "Auto Carrier / Car Hauler"
        case .livestockCattlePot:   return "Livestock / Cattle Pot"
        case .logTrailer:           return "Log Trailer"
        case .dryBulkHopper:        return "Dry Bulk / Hopper"
        case .gravityHopper:        return "Gravity Hopper"
        case .grainHopper:          return "Grain Hopper"
        case .pneumaticTank:        return "Pneumatic Tank"
        case .endDump:              return "End Dump Trailer"
        case .foodGradeLiquidTank:  return "Food-Grade Liquid Tank"
        case .waterTank:            return "Water Tank"
        case .intermodalChassis:    return "Intermodal Chassis"
        case .curtainSide:          return "Curtain Side / Tautliner"
        }
    }

    public var shortSpec: String {
        switch self {
        case .liquidTank:           return "MC-306 / DOT-406 / DOT-407"
        case .pressurizedGasTank:   return "MC-331 for LPG, ammonia, compressed gases"
        case .cryogenicTank:        return "LNG, LIN, LOX, LH2"
        case .hazmatBox:            return "Packaged hazmat: batteries, chemicals, oxidizers"
        case .dryVan:               return "Enclosed 53' for palletized & specialty cargo"
        case .reefer:               return "Nose-mount refrigeration: food, pharma, chemicals"
        case .standardFlatbed:      return "Steel, lumber, equipment, oversized loads"
        case .stepDeck:             return "Tall machinery — lower deck for extra clearance"
        case .lowboyRgn:            return "Heavy equipment: excavators, dozers, cranes"
        case .doubleDrop:           return "Extra-tall cargo: transformers, generators"
        case .conestoga:            return "Weather-protected flatbed: coils, machinery"
        case .autoCarrier:          return "Vehicle transport: 7-10 cars, dealer/auction/OEM"
        case .livestockCattlePot:   return "Live animal transport — USDA/FMCSA regulated"
        case .logTrailer:           return "Timber: sawlogs, pulpwood, tree-length (49 CFR 393.116)"
        case .dryBulkHopper:        return "Pneumatic: cement, lime, flour, plastic pellets"
        case .gravityHopper:        return "Gravity discharge: grain, sand, aggregate"
        case .grainHopper:          return "USDA-grade grain: corn, wheat, soybeans, rice, barley"
        case .pneumaticTank:        return "Pressure-unload for cement, flour, powder, pellets"
        case .endDump:              return "Hydraulic end-dump for aggregate, sand, debris"
        case .foodGradeLiquidTank:  return "Milk, juice, cooking oil, wine, liquid sugar"
        case .waterTank:            return "Potable, non-potable, industrial water"
        case .intermodalChassis:    return "ISO container chassis for port drayage / intermodal"
        case .curtainSide:          return "Side-access loading for building materials, machinery"
        }
    }

    /// True if this trailer is eligible to carry placarded hazmat under DOT regs.
    public var isHazmatEligible: Bool {
        switch self {
        case .liquidTank, .pressurizedGasTank, .cryogenicTank, .hazmatBox: return true
        case .intermodalChassis: return true   // depends on cargo
        default: return false
        }
    }

    /// True if this trailer requires reefer / food-grade subform during posting.
    public var requiresReeferSubform: Bool {
        switch self {
        case .reefer, .foodGradeLiquidTank: return true
        default: return false
        }
    }

    /// Default vertical the trailer biases toward when no vertical is yet chosen.
    public var defaultVertical: Vertical {
        switch self {
        case .liquidTank, .pressurizedGasTank, .cryogenicTank, .hazmatBox:
            return .hazmat
        case .reefer, .foodGradeLiquidTank:
            return .refrigerated
        case .standardFlatbed, .stepDeck, .conestoga:
            return .flatbedOpenDeck
        case .lowboyRgn, .doubleDrop:
            return .heavyHaulSpecialized
        case .autoCarrier:
            return .autoTransport
        case .livestockCattlePot:
            return .livestock
        case .logTrailer:
            return .flatbedOpenDeck
        case .dryBulkHopper, .gravityHopper, .grainHopper, .pneumaticTank, .endDump:
            return .dryBulkPneumatic
        case .waterTank:
            return .tankerLiquidBulk
        case .intermodalChassis:
            return .intermodalContainer
        case .dryVan, .curtainSide:
            return .generalFreight
        }
    }

    /// Driver endorsements required to legally operate this trailer.
    /// CDL-A is implied for every Class 8 combination.
    public var requiredEndorsements: Set<DriverEndorsement> {
        var s: Set<DriverEndorsement> = []
        if isHazmatEligible { s.insert(.hazmat); s.insert(.xCombination) }
        switch self {
        case .liquidTank, .pressurizedGasTank, .cryogenicTank,
             .foodGradeLiquidTank, .waterTank, .pneumaticTank:
            s.insert(.tanker)
        case .autoCarrier:
            s.insert(.doublesTriples)   // some auto-haul rigs are doubles
        default: break
        }
        return s
    }

    /// Trailers that should appear when the wizard's vertical filter is set to `v`.
    public static func filtered(by v: Vertical) -> [TrailerCode] {
        return allCases.filter { $0.defaultVertical == v }
    }
}

/// Driver endorsements (FMCSA).
public enum DriverEndorsement: String, CaseIterable, Codable, Hashable {
    case hazmat         = "H"
    case xCombination   = "X"   // tanker + hazmat
    case tanker         = "N"
    case doublesTriples = "T"
    case passenger      = "P"
    case schoolBus      = "S"
}
