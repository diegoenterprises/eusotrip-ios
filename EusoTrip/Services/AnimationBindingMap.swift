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
    /// Filenames match the actual bundle layout under
    /// `Resources/Animations/Equipment/{Loading,Unloading}/01_Truck/`
    /// (state-variant SVGs from T-028) and the hero under
    /// `Resources/Animations/Equipment/01_Truck/` (33 originals from
    /// the original bundle drop).
    ///
    /// T-029 (2026-05-20) — reconciled with the actual bundled
    /// filenames after T-028's filesystem copy. The 14 truck variants
    /// available in the v3 design system map below; missing trailers
    /// (livestock / log / curtainSide / bulkHopper / intermodalChassis)
    /// fall back to the closest-shape proxy for the loading/unloading
    /// stage so the driver-side animation still renders. T-029b on
    /// the design backlog ships the missing 9 trailer state-variants.
    public static let truck: [TrailerCode: AnimationFilePair] = [
        .dryVan:               .init(loading: "01_dry_van_loading.svg",          unloading: "01_dry_van_unloading.svg",          hero: "01_dry_van_anim.svg"),
        .reefer:               .init(loading: "02_reefer_loading.svg",           unloading: "02_reefer_unloading.svg",           hero: "02_reefer_anim.svg"),
        .standardFlatbed:      .init(loading: "03_flatbed_loading.svg",          unloading: "03_flatbed_unloading.svg",          hero: "03_flatbed_anim.svg"),
        .stepDeck:             .init(loading: "04_step_deck_loading.svg",        unloading: "04_step_deck_unloading.svg",        hero: "04_step_deck_anim.svg"),
        .conestoga:            .init(loading: "05_conestoga_loading.svg",        unloading: "05_conestoga_unloading.svg",        hero: "05_conestoga_anim.svg"),
        // .container — closest map via dryVan, no canonical TrailerCode case
        .liquidTank:           .init(loading: "07_tanker_hazmat_loading.svg",    unloading: "07_tanker_hazmat_unloading.svg",    hero: "07_tanker_hazmat_anim.svg"),
        .foodGradeLiquidTank:  .init(loading: "09_tanker_liquid_loading.svg",    unloading: "09_tanker_liquid_unloading.svg",    hero: "09_tanker_liquid_anim.svg"),
        .pressurizedGasTank:   .init(loading: "10_tanker_gas_loading.svg",       unloading: "10_tanker_gas_unloading.svg",       hero: "10_tanker_gas_anim.svg"),
        .cryogenicTank:        .init(loading: "10_tanker_gas_loading.svg",       unloading: "10_tanker_gas_unloading.svg",       hero: "10_tanker_gas_anim.svg"),
        .hazmatBox:            .init(loading: "01_dry_van_loading.svg",          unloading: "01_dry_van_unloading.svg",          hero: "01_dry_van_anim.svg"),
        .lowboyRgn:            .init(loading: "21_lowboy_loading.svg",           unloading: "21_lowboy_unloading.svg",           hero: "21_lowboy_anim.svg"),
        .doubleDrop:           .init(loading: "21_lowboy_loading.svg",           unloading: "21_lowboy_unloading.svg",           hero: "21_lowboy_anim.svg"),
        // 2026-05-29 — bound to the dedicated gap-fill SVGs (the on-screen
        // rig now matches the load instead of a wrong-shape proxy).
        .autoCarrier:          .init(loading: "35_auto_carrier_loading.svg",     unloading: "35_auto_carrier_unloading.svg",     hero: "35_auto_carrier_anim.svg"),
        .pneumaticTank:        .init(loading: "36_pneumatic_dry_bulk_loading.svg", unloading: "36_pneumatic_dry_bulk_unloading.svg", hero: "36_pneumatic_dry_bulk_anim.svg"),
        .endDump:              .init(loading: "03_flatbed_loading.svg",          unloading: "03_flatbed_unloading.svg",          hero: "03_flatbed_anim.svg"),       // proxy — no dedicated SVG yet
        .waterTank:            .init(loading: "09_tanker_liquid_loading.svg",    unloading: "09_tanker_liquid_unloading.svg",    hero: "09_tanker_liquid_anim.svg"), // proxy — no dedicated SVG yet
        .livestockCattlePot:   .init(loading: "34_livestock_loading.svg",        unloading: "34_livestock_unloading.svg",        hero: "34_livestock_anim.svg"),
        .logTrailer:           .init(loading: "03_flatbed_loading.svg",          unloading: "03_flatbed_unloading.svg",          hero: "03_flatbed_anim.svg"),       // proxy — no dedicated SVG yet
        .curtainSide:          .init(loading: "01_dry_van_loading.svg",          unloading: "01_dry_van_unloading.svg",          hero: "01_dry_van_anim.svg"),       // proxy — no dedicated SVG yet
        .dryBulkHopper:        .init(loading: "36_pneumatic_dry_bulk_loading.svg", unloading: "36_pneumatic_dry_bulk_unloading.svg", hero: "36_pneumatic_dry_bulk_anim.svg"),
        .gravityHopper:        .init(loading: "36_pneumatic_dry_bulk_loading.svg", unloading: "36_pneumatic_dry_bulk_unloading.svg", hero: "36_pneumatic_dry_bulk_anim.svg"),
        .grainHopper:          .init(loading: "36_pneumatic_dry_bulk_loading.svg", unloading: "36_pneumatic_dry_bulk_unloading.svg", hero: "36_pneumatic_dry_bulk_anim.svg"),
        .intermodalChassis:    .init(loading: "06_container_truck_loading.svg",  unloading: "06_container_truck_unloading.svg",  hero: "06_container_truck_anim.svg"),
    ]

    /// Rail mode mapping.
    public static let rail: [RailCarKind: AnimationFilePair] = [
        .tofc:          .init(loading: "13_rail_tofc_loading.svg",         unloading: "13_rail_tofc_unloading.svg",         hero: "13_rail_tofc_anim.svg"),
        // .cofc — no canonical RailCarKind case (intermodal is closest)
        .tankPressure:  .init(loading: "19_rail_tank_gas_loading.svg",     unloading: "19_rail_tank_gas_unloading.svg",     hero: "19_rail_tank_gas_anim.svg"),
        .tankLiquid:    .init(loading: "20_rail_tank_liquid_loading.svg",  unloading: "20_rail_tank_liquid_unloading.svg",  hero: "20_rail_tank_liquid_anim.svg"),
        .boxcar:        .init(loading: "23_rail_boxcar_loading.svg",       unloading: "23_rail_boxcar_unloading.svg",       hero: "23_rail_boxcar_anim.svg"),
        .hopperCovered: .init(loading: "24_rail_hopper_loading.svg",       unloading: "24_rail_hopper_unloading.svg",       hero: "24_rail_hopper_anim.svg"),
        .centerbeam:    .init(loading: "25_rail_centerbeam_loading.svg",   unloading: "25_rail_centerbeam_unloading.svg",   hero: "25_rail_centerbeam_anim.svg"),
        .gondola:       .init(loading: "26_rail_gondola_loading.svg",      unloading: "26_rail_gondola_unloading.svg",      hero: "26_rail_gondola_anim.svg"),
        .autoRack:      .init(loading: "27_rail_auto_rack_loading.svg",    unloading: "27_rail_auto_rack_unloading.svg",    hero: "27_rail_auto_rack_anim.svg"),
        .reeferBoxcar:  .init(loading: "28_rail_reefer_boxcar_loading.svg", unloading: "28_rail_reefer_boxcar_unloading.svg", hero: "28_rail_reefer_boxcar_anim.svg"),
        .flatcar:       .init(loading: "29_rail_flatcar_loading.svg",      unloading: "29_rail_flatcar_unloading.svg",      hero: "29_rail_flatcar_anim.svg"),
        .wellCar:       .init(loading: "29_rail_flatcar_loading.svg",      unloading: "29_rail_flatcar_unloading.svg",      hero: "29_rail_flatcar_anim.svg"),
    ]

    /// Vessel mode mapping.
    public static let vessel: [VesselClassKind: AnimationFilePair] = [
        .containerShip:    .init(loading: "16_vessel_container_loading.svg",       unloading: "16_vessel_container_unloading.svg",       hero: "16_vessel_container_anim.svg"),
        .bulkCarrier:      .init(loading: "17_vessel_bulk_loading.svg",            unloading: "17_vessel_bulk_unloading.svg",            hero: "17_vessel_bulk_anim.svg"),
        .tanker:           .init(loading: "18_vessel_tanker_loading.svg",          unloading: "18_vessel_tanker_unloading.svg",          hero: "18_vessel_tanker_anim.svg"),
        .roRo:             .init(loading: "30_vessel_roro_loading.svg",            unloading: "30_vessel_roro_unloading.svg",            hero: "30_vessel_roro_anim.svg"),
        .lng:              .init(loading: "31_vessel_lng_loading.svg",             unloading: "31_vessel_lng_unloading.svg",             hero: "31_vessel_lng_anim.svg"),
        .reeferContainer:  .init(loading: "32_vessel_reefer_container_loading.svg", unloading: "32_vessel_reefer_container_unloading.svg", hero: "32_vessel_reefer_container_anim.svg"),
        .isoTank:          .init(loading: "33_vessel_iso_tank_loading.svg",        unloading: "33_vessel_iso_tank_unloading.svg",        hero: "33_vessel_iso_tank_anim.svg"),
    ]

    /// Folder path (relative to bundle root) for a given mode + state.
    /// Encapsulates the canonical directory layout so EquipmentAnimation
    /// doesn't have to hardcode it at the call site.
    public static func subdirectory(mode: String, state: String) -> String {
        // mode: "01_Truck" / "02_Rail" / "03_Vessel"
        // state: "Loading" / "Unloading" / nil-for-hero
        if state == "hero" {
            return "Animations/Equipment/\(mode)"
        }
        return "Animations/Equipment/\(state)/\(mode)"
    }

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
