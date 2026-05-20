//
//  EquipmentEquivalency.swift
//  Cross-track parity lookup: truck trailer ↔ rail car ↔ vessel class.
//
//  The audit found that iOS has 35 equipment choices but no programmatic mapping
//  between them. This file declares the canonical equivalency so:
//    - Switching mode in the wizard auto-snaps the equipment
//    - Intermodal routing knows which rail car carries which truck trailer
//    - Vessel booking knows which vessel class carries which trailer's cargo
//
//  Drop into: EusoTrip/Models/EquipmentEquivalency.swift
//

import Foundation

/// Rail car family (used to bind to rail_20-29 animation files).
public enum RailCarKind: String, CaseIterable, Codable, Hashable {
    case boxcar           = "rail_23_boxcar"
    case reeferBoxcar     = "rail_28_reefer_boxcar"
    case flatcar          = "rail_29_flatcar"
    case autoRack         = "rail_27_auto_rack"
    case tankLiquid       = "rail_20_tank_liquid"      // DOT-117 thermal jacket
    case tankPressure     = "rail_21_tank_pressure"    // DOT-105
    case hopperCovered    = "rail_24_hopper"
    case gondola          = "rail_26_gondola"
    case centerbeam       = "rail_25_centerbeam"
    case wellCar          = "rail_30_well_car"         // intermodal stack
    case tofc             = "rail_13_tofc"             // trailer on flatcar
}

/// Vessel class family (used to bind to vessel_16-33 animation files).
public enum VesselClassKind: String, CaseIterable, Codable, Hashable {
    case containerShip      = "vessel_16_container"
    case bulkCarrier        = "vessel_17_bulk"
    case tanker             = "vessel_18_tanker"
    case roRo               = "vessel_30_roro"
    case lng                = "vessel_31_lng"
    case reeferContainer    = "vessel_32_reefer_container"
    case isoTank            = "vessel_33_iso_tank"
}

/// One row in the equivalency table.
public struct EquipmentEquivalencyRow: Codable, Hashable {
    public let truck: TrailerCode?
    public let rail: RailCarKind?
    public let vessel: VesselClassKind?
    public let notes: String
}

public enum EquipmentEquivalency {

    /// The canonical equivalency map — every supported truck trailer with its
    /// rail and vessel equivalents. Use this whenever you need to convert
    /// between modes (wizard mode switch, intermodal leg builder, etc.).
    public static let rows: [EquipmentEquivalencyRow] = [
        .init(truck: .dryVan,              rail: .boxcar,         vessel: .containerShip,   notes: "General dry cargo"),
        .init(truck: .reefer,              rail: .reeferBoxcar,   vessel: .reeferContainer, notes: "Cold chain"),
        .init(truck: .standardFlatbed,     rail: .flatcar,        vessel: .roRo,            notes: "Open deck / oversized"),
        .init(truck: .stepDeck,            rail: .flatcar,        vessel: .roRo,            notes: "Tall machinery"),
        .init(truck: .lowboyRgn,           rail: .flatcar,        vessel: .roRo,            notes: "Heavy equipment"),
        .init(truck: .doubleDrop,          rail: .flatcar,        vessel: .roRo,            notes: "Extra-tall project cargo"),
        .init(truck: .conestoga,           rail: .centerbeam,     vessel: nil,              notes: "Weather-protected"),
        .init(truck: .autoCarrier,         rail: .autoRack,       vessel: .roRo,            notes: "Finished vehicles"),
        .init(truck: .liquidTank,          rail: .tankLiquid,     vessel: .tanker,          notes: "Liquid bulk (incl. food-grade if rail tank is sanitary)"),
        .init(truck: .pressurizedGasTank,  rail: .tankPressure,   vessel: .tanker,          notes: "Compressed/pressurized gases"),
        .init(truck: .cryogenicTank,       rail: nil,             vessel: .lng,             notes: "LNG / LIN / LOX (rail uncommon)"),
        .init(truck: .hazmatBox,           rail: .boxcar,         vessel: .containerShip,   notes: "Packaged hazmat — placarded"),
        .init(truck: .livestockCattlePot,  rail: nil,             vessel: nil,              notes: "USDA livestock — truck-only"),
        .init(truck: .logTrailer,          rail: .centerbeam,     vessel: nil,              notes: "Timber"),
        .init(truck: .dryBulkHopper,       rail: .hopperCovered,  vessel: .bulkCarrier,     notes: "Pneumatic bulk"),
        .init(truck: .gravityHopper,       rail: .hopperCovered,  vessel: .bulkCarrier,     notes: "Gravity discharge"),
        .init(truck: .grainHopper,         rail: .hopperCovered,  vessel: .bulkCarrier,     notes: "USDA-grade grain"),
        .init(truck: .pneumaticTank,       rail: nil,             vessel: .isoTank,         notes: "Pressure-unload dry bulk"),
        .init(truck: .endDump,             rail: .gondola,        vessel: .bulkCarrier,     notes: "Aggregate / debris"),
        .init(truck: .foodGradeLiquidTank, rail: .tankLiquid,     vessel: .isoTank,         notes: "Food-grade liquid"),
        .init(truck: .waterTank,           rail: .tankLiquid,     vessel: .isoTank,         notes: "Potable / industrial water"),
        .init(truck: .intermodalChassis,   rail: .wellCar,        vessel: .containerShip,   notes: "ISO container drayage"),
        .init(truck: .curtainSide,         rail: .boxcar,         vessel: .containerShip,   notes: "Side-access loading"),
        // Gondola has no truck equivalent — rail/vessel only
        .init(truck: nil,                  rail: .gondola,        vessel: .bulkCarrier,     notes: "Aggregate / scrap metal (no truck equivalent)"),
    ]

    /// Find the rail equivalent for a truck trailer.
    public static func railFor(_ truck: TrailerCode) -> RailCarKind? {
        rows.first { $0.truck == truck }?.rail
    }

    /// Find the vessel equivalent for a truck trailer.
    public static func vesselFor(_ truck: TrailerCode) -> VesselClassKind? {
        rows.first { $0.truck == truck }?.vessel
    }

    /// Find the truck equivalent for a rail car.
    public static func truckFor(_ rail: RailCarKind) -> TrailerCode? {
        rows.first { $0.rail == rail }?.truck
    }

    /// Find the truck equivalent for a vessel class.
    public static func truckFor(_ vessel: VesselClassKind) -> TrailerCode? {
        rows.first { $0.vessel == vessel }?.truck
    }

    /// Given a target mode + a source equipment in any mode, return the equivalent equipment in the target mode.
    public static func equivalent(of source: AnyEquipment, in mode: TransportMode) -> AnyEquipment? {
        switch (source, mode) {
        case (.truck(let t), .rail):
            return railFor(t).map { .rail($0) }
        case (.truck(let t), .vessel):
            return vesselFor(t).map { .vessel($0) }
        case (.truck, .truck):
            return source
        case (.rail(let r), .truck):
            return truckFor(r).map { .truck($0) }
        case (.rail(let r), .vessel):
            return rows.first { $0.rail == r }?.vessel.map { .vessel($0) } ?? nil
        case (.rail, .rail):
            return source
        case (.vessel(let v), .truck):
            return truckFor(v).map { .truck($0) }
        case (.vessel(let v), .rail):
            return rows.first { $0.vessel == v }?.rail.map { .rail($0) } ?? nil
        case (.vessel, .vessel):
            return source
        default:
            return nil
        }
    }
}

/// Single discriminated type that can hold any of the three equipment families.
public enum AnyEquipment: Codable, Hashable {
    case truck(TrailerCode)
    case rail(RailCarKind)
    case vessel(VesselClassKind)

    public var mode: TransportMode {
        switch self {
        case .truck: return .truck
        case .rail: return .rail
        case .vessel: return .vessel
        }
    }
}
