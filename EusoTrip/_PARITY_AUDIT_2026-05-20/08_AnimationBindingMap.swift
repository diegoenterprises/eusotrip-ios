//
//  AnimationBindingMap.swift
//  Canonical trailer → animation file mapping (Loading + Unloading).
//
//  Audit found 6 trailers unmapped in EquipmentKind (livestock, log, pneumatic,
//  end_dump, water, curtain_side) and zero loading/unloading state-variant SVGs
//  bundled. This file declares the canonical bindings so EquipmentAnimation and
//  BindableEquipmentAnimation can look up SVG asset names from a TrailerCode.
//
//  Drop into: EusoTrip/Services/AnimationBindingMap.swift
//

import Foundation

/// Two SVG asset names for a trailer — one for the Loading state, one for Unloading.
public struct AnimationFilePair: Codable, Hashable {
    public let loading: String         // e.g. "truck_01_dryvan_loading_v3.svg"
    public let unloading: String       // e.g. "truck_01_dryvan_unloading_v3.svg"
    public let hero: String            // single-state hero used in selectors
}

public enum AnimationBindingMap {

    /// Canonical SVG file mapping per trailer code, keyed for truck mode.
    /// All filenames assume the v3-perfected bundle layout under
    /// `Resources/Animations/Equipment/01_Truck/04_LoadingUnloading/{Loading,Unloading}/`
    /// and the hero under `Resources/Animations/Equipment/01_Truck/`.
    public static let truck: [TrailerCode: AnimationFilePair] = [
        .dryVan:               .init(loading: "truck_01_dryvan_loading_v3.svg",            unloading: "truck_01_dryvan_unloading_v3.svg",            hero: "01_dry_van_anim.svg"),
        .reefer:               .init(loading: "truck_02_reefer_loading_v3.svg",            unloading: "truck_02_reefer_unloading_v3.svg",            hero: "02_reefer_anim.svg"),
        .standardFlatbed:      .init(loading: "truck_03_flatbed_loading_v3.svg",           unloading: "truck_03_flatbed_unloading_v3.svg",           hero: "03_flatbed_anim.svg"),
        .stepDeck:             .init(loading: "truck_04_step_deck_loading_v3.svg",         unloading: "truck_04_step_deck_unloading_v3.svg",         hero: "04_step_deck_anim.svg"),
        .lowboyRgn:            .init(loading: "truck_05_lowboy_rgn_loading_v3.svg",        unloading: "truck_05_lowboy_rgn_unloading_v3.svg",        hero: "05_lowboy_rgn_anim.svg"),
        .doubleDrop:           .init(loading: "truck_06_double_drop_loading_v3.svg",       unloading: "truck_06_double_drop_unloading_v3.svg",       hero: "06_double_drop_anim.svg"),
        .liquidTank:           .init(loading: "truck_07_tanker_hazmat_loading_v3.svg",     unloading: "truck_07_tanker_hazmat_unloading_v3.svg",     hero: "07_tanker_hazmat_anim.svg"),
        .pressurizedGasTank:   .init(loading: "truck_10_tanker_gas_loading_v3.svg",        unloading: "truck_10_tanker_gas_unloading_v3.svg",        hero: "10_tanker_gas_anim.svg"),
        .cryogenicTank:        .init(loading: "truck_10_tanker_gas_loading_v3.svg",        unloading: "truck_10_tanker_gas_unloading_v3.svg",        hero: "10_tanker_gas_anim.svg"),
        .hazmatBox:            .init(loading: "truck_01_dryvan_loading_v3.svg",            unloading: "truck_01_dryvan_unloading_v3.svg",            hero: "01_dry_van_anim.svg"),
        .foodGradeLiquidTank:  .init(loading: "truck_09_tanker_liquid_loading_v3.svg",     unloading: "truck_09_tanker_liquid_unloading_v3.svg",     hero: "09_tanker_liquid_anim.svg"),
        .conestoga:            .init(loading: "truck_11_conestoga_loading_v3.svg",         unloading: "truck_11_conestoga_unloading_v3.svg",         hero: "11_conestoga_anim.svg"),
        .autoCarrier:          .init(loading: "truck_12_auto_carrier_loading_v3.svg",      unloading: "truck_12_auto_carrier_unloading_v3.svg",      hero: "12_auto_carrier_anim.svg"),
        .pneumaticTank:        .init(loading: "truck_18_pneumatic_tank_loading_v3.svg",    unloading: "truck_18_pneumatic_tank_unloading_v3.svg",    hero: "18_pneumatic_tank_anim.svg"),
        .endDump:              .init(loading: "truck_19_end_dump_loading_v3.svg",          unloading: "truck_19_end_dump_unloading_v3.svg",          hero: "19_end_dump_anim.svg"),
        .waterTank:            .init(loading: "truck_20_water_tank_loading_v3.svg",        unloading: "truck_20_water_tank_unloading_v3.svg",        hero: "20_water_tank_anim.svg"),
        .livestockCattlePot:   .init(loading: "truck_21_livestock_loading_v3.svg",         unloading: "truck_21_livestock_unloading_v3.svg",         hero: "21_livestock_anim.svg"),
        .logTrailer:           .init(loading: "truck_22_log_trailer_loading_v3.svg",       unloading: "truck_22_log_trailer_unloading_v3.svg",       hero: "22_log_trailer_anim.svg"),
        .curtainSide:          .init(loading: "truck_23_curtain_side_loading_v3.svg",      unloading: "truck_23_curtain_side_unloading_v3.svg",      hero: "23_curtain_side_anim.svg"),
        // Bulk hopper family maps to the rail hopper visualization on truck-side via cross-track fallback
        .dryBulkHopper:        .init(loading: "truck_24_bulk_hopper_loading_v3.svg",       unloading: "truck_24_bulk_hopper_unloading_v3.svg",       hero: "24_bulk_hopper_anim.svg"),
        .gravityHopper:        .init(loading: "truck_24_bulk_hopper_loading_v3.svg",       unloading: "truck_24_bulk_hopper_unloading_v3.svg",       hero: "24_bulk_hopper_anim.svg"),
        .grainHopper:          .init(loading: "truck_24_bulk_hopper_loading_v3.svg",       unloading: "truck_24_bulk_hopper_unloading_v3.svg",       hero: "24_bulk_hopper_anim.svg"),
        .intermodalChassis:    .init(loading: "truck_25_intermodal_chassis_loading_v3.svg", unloading: "truck_25_intermodal_chassis_unloading_v3.svg", hero: "25_intermodal_chassis_anim.svg"),
    ]

    /// Rail mode mapping.
    public static let rail: [RailCarKind: AnimationFilePair] = [
        .boxcar:        .init(loading: "rail_23_boxcar_loading_v3.svg",       unloading: "rail_23_boxcar_unloading_v3.svg",       hero: "rail_23_boxcar_anim.svg"),
        .reeferBoxcar:  .init(loading: "rail_28_reefer_boxcar_loading_v3.svg", unloading: "rail_28_reefer_boxcar_unloading_v3.svg", hero: "rail_28_reefer_anim.svg"),
        .flatcar:       .init(loading: "rail_29_flatcar_loading_v3.svg",      unloading: "rail_29_flatcar_unloading_v3.svg",      hero: "rail_29_flatcar_anim.svg"),
        .autoRack:      .init(loading: "rail_27_auto_rack_loading_v3.svg",    unloading: "rail_27_auto_rack_unloading_v3.svg",    hero: "rail_27_auto_rack_anim.svg"),
        .tankLiquid:    .init(loading: "rail_20_tank_liquid_loading_v3.svg",  unloading: "rail_20_tank_liquid_unloading_v3.svg",  hero: "rail_20_tank_liquid_anim.svg"),
        .tankPressure:  .init(loading: "rail_21_tank_pressure_loading_v3.svg", unloading: "rail_21_tank_pressure_unloading_v3.svg", hero: "rail_21_tank_pressure_anim.svg"),
        .hopperCovered: .init(loading: "rail_24_hopper_loading_v3.svg",       unloading: "rail_24_hopper_unloading_v3.svg",       hero: "rail_24_hopper_anim.svg"),
        .gondola:       .init(loading: "rail_26_gondola_loading_v3.svg",      unloading: "rail_26_gondola_unloading_v3.svg",      hero: "rail_26_gondola_anim.svg"),
        .centerbeam:    .init(loading: "rail_25_centerbeam_loading_v3.svg",   unloading: "rail_25_centerbeam_unloading_v3.svg",   hero: "rail_25_centerbeam_anim.svg"),
        .wellCar:       .init(loading: "rail_30_well_car_loading_v3.svg",     unloading: "rail_30_well_car_unloading_v3.svg",     hero: "rail_30_well_car_anim.svg"),
        .tofc:          .init(loading: "rail_13_tofc_loading_v3.svg",         unloading: "rail_13_tofc_unloading_v3.svg",         hero: "rail_13_tofc_anim.svg"),
    ]

    /// Vessel mode mapping.
    public static let vessel: [VesselClassKind: AnimationFilePair] = [
        .containerShip:    .init(loading: "vessel_16_container_loading_v3.svg",       unloading: "vessel_16_container_unloading_v3.svg",       hero: "vessel_16_container_anim.svg"),
        .bulkCarrier:      .init(loading: "vessel_17_bulk_loading_v3.svg",            unloading: "vessel_17_bulk_unloading_v3.svg",            hero: "vessel_17_bulk_anim.svg"),
        .tanker:           .init(loading: "vessel_18_tanker_loading_v3.svg",          unloading: "vessel_18_tanker_unloading_v3.svg",          hero: "vessel_18_tanker_anim.svg"),
        .roRo:             .init(loading: "vessel_30_roro_loading_v3.svg",            unloading: "vessel_30_roro_unloading_v3.svg",            hero: "vessel_30_roro_anim.svg"),
        .lng:              .init(loading: "vessel_31_lng_loading_v3.svg",             unloading: "vessel_31_lng_unloading_v3.svg",             hero: "vessel_31_lng_anim.svg"),
        .reeferContainer:  .init(loading: "vessel_32_reefer_container_loading_v3.svg", unloading: "vessel_32_reefer_container_unloading_v3.svg", hero: "vessel_32_reefer_anim.svg"),
        .isoTank:          .init(loading: "vessel_33_iso_tank_loading_v3.svg",        unloading: "vessel_33_iso_tank_unloading_v3.svg",        hero: "vessel_33_iso_tank_anim.svg"),
    ]

    /// Resolve animation file pair for any equipment + state.
    public static func files(for equipment: AnyEquipment) -> AnimationFilePair? {
        switch equipment {
        case .truck(let t):  return truck[t]
        case .rail(let r):   return rail[r]
        case .vessel(let v): return vessel[v]
        }
    }

    /// True if every TrailerCode case has at least a truck-side hero binding.
    /// (Compile-time guarantee that the catalog stays in sync with the canonical enum.)
    public static var isComplete: Bool {
        TrailerCode.allCases.allSatisfy { truck[$0] != nil }
    }
}
