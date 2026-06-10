//
//  EquipmentAnimation.swift
//  EusoTrip — Equipment-aware animation primitive for the post-load
//  wizard (and any other surface that needs a live equipment lockup).
//
//  v2 (2026-05-07) — replaces the v1 SwiftUI-shape silhouettes with
//  the founder-approved EusoTrip Animation Design System SVGs
//  (`/Resources/Animations/Equipment/{01_Truck, 02_Rail, 03_Vessel}/
//  NN_<name>_anim.svg`). The SVGs carry their own SMIL / CSS
//  animations, brand-lockup, and `prefers-reduced-motion` queries —
//  iOS just needs to host them transparently.
//
//  Strategy:
//    • EquipmentAnimationCache — singleton, preloads the 33 SVG
//      strings off disk at app launch so the wizard's tile selection
//      and scroll feel instant. Key = EquipmentKind raw value.
//    • EquipmentAnimationView — UIViewRepresentable wrapping a
//      WKWebView with isOpaque=false, backgroundColor=.clear,
//      scrollView.isScrollEnabled=false, bounces=false, all touch
//      handling disabled (the SwiftUI host owns hit-testing).
//    • EquipmentAnimation — public SwiftUI entry that picks the
//      right SVG for the (equipment, cargo, hazmat, …) tuple,
//      wraps the web view in a TimelineView shell so reduce-motion
//      respects the system setting via the SVG's media query.
//
//  Doctrine: feedback_lifecycle_parity_animations + animation §B.4.
//  Tanker silhouette never paints on a dry-van load. Hazmat is a
//  variant, not the default. SVG lockup centers correctly inside
//  the wizard's render frame (180pt @ 2x = 360px); the iridescent
//  E-mark pulse stays in sync with the rest of the app's brand
//  pulse rhythm because the SMIL animations use the same 1.4s
//  fundamental as the Orb / gradient hero.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import UIKit

// MARK: - Public input enums (caller-facing)

enum EquipmentKind: String, Hashable, CaseIterable {
    // Truck (01-12)
    case dryVan, reefer, flatbed, stepDeck, conestoga, container
    case tankerHazmat, tankerPetro, tankerLiquid, tankerGas
    case powerOnly, oversized
    // Rail (13-15, 19-20, 23-29)
    case railTOFC, railCOFC, railIntermodal
    case railTankGas, railTankLiquid
    case railBoxcar, railHopper, railCenterbeam, railGondola
    case railAutoRack, railReeferBoxcar, railFlatcar
    // Vessel (16-18, 30-33)
    case vesselContainer, vesselBulk, vesselTanker
    case vesselRoRo, vesselLNG, vesselReeferContainer, vesselISOTank
    // Truck — extended (21-22)
    case lowboy, hotShot
    // T-030 (2026-05-20) — 6 missing trailer types added per audit.
    // Previously these had to fall back to dryVan in every consumer,
    // which hid their distinct animation requirements (livestock pot
    // looks nothing like a dry van; end-dump's articulating bed is
    // its identity). Each maps to the canonical TrailerCode of the
    // same name from T-001's foundation.
    case livestockCattlePot, logTrailer, pneumaticTank, endDump, waterTank, curtainSide
    // Wave B (2026-06-10) — auto-carrier finally gets its own case.
    // The 35_auto_carrier SVG triplet has been on disk since the
    // 2026-05-29 gap-fill, and AnimationBindingMap already binds
    // TrailerCode.autoCarrier to it, but NO EquipmentKind case
    // existed — a vehicles/car-hauler load could never resolve to
    // the right model (LEVEL100 spec §3.1, model 35).
    case autoCarrier

    var vertical: AnimVertical {
        switch self {
        case .railTOFC, .railCOFC, .railIntermodal,
             .railTankGas, .railTankLiquid,
             .railBoxcar, .railHopper, .railCenterbeam, .railGondola,
             .railAutoRack, .railReeferBoxcar, .railFlatcar:
            return .rail
        case .vesselContainer, .vesselBulk, .vesselTanker,
             .vesselRoRo, .vesselLNG, .vesselReeferContainer, .vesselISOTank:
            return .vessel
        default:
            return .truck
        }
    }

    /// Filename of the matching SVG inside the bundle (without
    /// extension). Folder maps via `vertical`.
    var svgFilename: String {
        switch self {
        case .dryVan:                return "01_dry_van_anim"
        case .reefer:                return "02_reefer_anim"
        case .flatbed:               return "03_flatbed_anim"
        case .stepDeck:              return "04_step_deck_anim"
        case .conestoga:             return "05_conestoga_anim"
        case .container:             return "06_container_truck_anim"
        case .tankerHazmat:          return "07_tanker_hazmat_anim"
        case .tankerPetro:           return "08_tanker_petro_anim"
        case .tankerLiquid:          return "09_tanker_liquid_anim"
        case .tankerGas:             return "10_tanker_gas_anim"
        case .powerOnly:             return "11_power_only_anim"
        case .oversized:             return "12_oversized_anim"
        case .railTOFC:              return "13_rail_tofc_anim"
        case .railCOFC:              return "14_rail_cofc_anim"
        case .railIntermodal:        return "15_rail_intermodal_anim"
        case .vesselContainer:       return "16_vessel_container_anim"
        case .vesselBulk:            return "17_vessel_bulk_anim"
        case .vesselTanker:          return "18_vessel_tanker_anim"
        case .railTankGas:           return "19_rail_tank_gas_anim"
        case .railTankLiquid:        return "20_rail_tank_liquid_anim"
        case .lowboy:                return "21_lowboy_anim"
        case .hotShot:               return "22_hot_shot_anim"
        case .railBoxcar:            return "23_rail_boxcar_anim"
        case .railHopper:            return "24_rail_hopper_anim"
        case .railCenterbeam:        return "25_rail_centerbeam_anim"
        case .railGondola:           return "26_rail_gondola_anim"
        case .railAutoRack:          return "27_rail_auto_rack_anim"
        case .railReeferBoxcar:      return "28_rail_reefer_boxcar_anim"
        case .railFlatcar:           return "29_rail_flatcar_anim"
        case .vesselRoRo:            return "30_vessel_roro_anim"
        case .vesselLNG:             return "31_vessel_lng_anim"
        case .vesselReeferContainer: return "32_vessel_reefer_container_anim"
        case .vesselISOTank:         return "33_vessel_iso_tank_anim"
        // Wave B (2026-06-10) — the six T-030 proxies are DEAD. The
        // dedicated hero SVGs (34-40) shipped in the 2026-05-29
        // gap-fill drop and have been on disk ever since; these cases
        // kept pointing at closest-shape proxies, so a livestock load
        // painted a dry van and an end-dump painted a flatbed — a
        // wrong-equipment fabrication per the canonical-models
        // doctrine. Each now resolves to its own model.
        case .livestockCattlePot:    return "34_livestock_anim"
        case .autoCarrier:           return "35_auto_carrier_anim"
        case .pneumaticTank:         return "36_pneumatic_dry_bulk_anim"
        case .endDump:               return "37_end_dump_anim"
        case .waterTank:             return "38_water_tank_anim"
        case .logTrailer:            return "39_log_trailer_anim"
        case .curtainSide:           return "40_curtain_side_anim"
        }
    }

    var svgSubdirectory: String {
        switch vertical {
        case .truck:  return "Animations/Equipment/01_Truck"
        case .rail:   return "Animations/Equipment/02_Rail"
        case .vessel: return "Animations/Equipment/03_Vessel"
        }
    }

    // MARK: - T-029 · AnimationBindingMap bridge (2026-05-20)

    /// Map this EquipmentKind to the canonical AnyEquipment (the type
    /// AnimationBindingMap.files(for:) accepts). Returns nil when the
    /// EquipmentKind doesn't have a direct TrailerCode / RailCarKind /
    /// VesselClassKind counterpart yet (a few legacy edge cases —
    /// covered by the hero fallback below).
    var canonical: AnyEquipment? {
        switch self {
        // Truck → TrailerCode
        case .dryVan:                return .truck(.dryVan)
        case .reefer:                return .truck(.reefer)
        case .flatbed:               return .truck(.standardFlatbed)
        case .stepDeck:              return .truck(.stepDeck)
        case .conestoga:             return .truck(.conestoga)
        case .container:             return .truck(.intermodalChassis)
        case .tankerHazmat:          return .truck(.liquidTank)
        case .tankerPetro:           return .truck(.liquidTank)
        case .tankerLiquid:          return .truck(.foodGradeLiquidTank)
        case .tankerGas:             return .truck(.pressurizedGasTank)
        case .powerOnly:             return .truck(.dryVan)
        case .oversized:             return .truck(.standardFlatbed)
        case .lowboy:                return .truck(.lowboyRgn)
        case .hotShot:               return .truck(.dryVan)
        // Rail → RailCarKind
        case .railTOFC:              return .rail(.tofc)
        case .railCOFC:              return .rail(.tofc)
        case .railIntermodal:        return .rail(.wellCar)
        case .railTankGas:           return .rail(.tankPressure)
        case .railTankLiquid:        return .rail(.tankLiquid)
        case .railBoxcar:            return .rail(.boxcar)
        case .railReeferBoxcar:      return .rail(.reeferBoxcar)
        case .railHopper:            return .rail(.hopperCovered)
        case .railCenterbeam:        return .rail(.centerbeam)
        case .railGondola:           return .rail(.gondola)
        case .railAutoRack:          return .rail(.autoRack)
        case .railFlatcar:           return .rail(.flatcar)
        // Vessel → VesselClassKind
        case .vesselContainer:       return .vessel(.containerShip)
        case .vesselBulk:            return .vessel(.bulkCarrier)
        case .vesselTanker:          return .vessel(.tanker)
        case .vesselRoRo:            return .vessel(.roRo)
        case .vesselLNG:             return .vessel(.lng)
        case .vesselReeferContainer: return .vessel(.reeferContainer)
        case .vesselISOTank:         return .vessel(.isoTank)
        // T-030 — direct canonical mapping (each EquipmentKind case
        // maps to the matching TrailerCode from T-001's foundation).
        case .livestockCattlePot:    return .truck(.livestockCattlePot)
        case .logTrailer:            return .truck(.logTrailer)
        case .pneumaticTank:         return .truck(.pneumaticTank)
        case .endDump:               return .truck(.endDump)
        case .waterTank:             return .truck(.waterTank)
        case .curtainSide:           return .truck(.curtainSide)
        case .autoCarrier:           return .truck(.autoCarrier)
        }
    }

    /// Dedicated state-variant file stems for the six EquipmentKinds whose
    /// canonical bridge resolves to a closest-shape PROXY (no TrailerCode /
    /// RailCarKind case of their own exists), which was orphaning the 12
    /// dedicated T-028 loading/unloading SVGs that DO ship in the bundle
    /// (E2E audit §4 animations · 2026-06-09). Resolved here ahead of the
    /// bridge so each kind animates as itself, not its proxy:
    ///   08 petro · 11 power-only · 12 oversized · 14 COFC ·
    ///   15 intermodal · 22 hot-shot  (× loading + unloading = 12 files).
    private var dedicatedStateVariantStem: String? {
        switch self {
        case .tankerPetro:    return "08_tanker_petro"
        case .powerOnly:      return "11_power_only"
        case .oversized:      return "12_oversized"
        case .railCOFC:       return "14_rail_cofc"
        case .railIntermodal: return "15_rail_intermodal"
        case .hotShot:        return "22_hot_shot"
        default:              return nil
        }
    }

    /// Resolve the SVG filename for a given state via the canonical
    /// AnimationBindingMap. Replaces the legacy single-state
    /// `svgFilename` lookup. Returns nil when no binding exists OR the
    /// canonical bridge fails — callers should fall back to
    /// `svgFilename` (hero) for legacy back-compat.
    func file(for state: AnimationState) -> String? {
        // Dedicated state-variant override — un-orphans the 12 SVGs the
        // canonical proxies were shadowing (audit §4 · 2026-06-09).
        if let stem = dedicatedStateVariantStem {
            switch state {
            case .loading:    return "\(stem)_loading.svg"
            case .unloading:  return "\(stem)_unloading.svg"
            case .hero:       return "\(svgFilename).svg"
            }
        }
        guard let canonical = canonical,
              let pair = AnimationBindingMap.files(for: canonical) else {
            return nil
        }
        switch state {
        case .loading:    return pair.loading
        case .unloading:  return pair.unloading
        case .hero:       return pair.hero
        }
    }

    /// Resolve the subdirectory path inside the bundle for a state.
    /// Encapsulates the `Animations/Equipment/{Loading,Unloading}/{mode}/`
    /// layout from T-028.
    func subdirectory(for state: AnimationState) -> String {
        let mode: String = {
            switch vertical {
            case .truck:  return "01_Truck"
            case .rail:   return "02_Rail"
            case .vessel: return "03_Vessel"
            }
        }()
        switch state {
        case .hero:       return "Animations/Equipment/\(mode)"
        case .loading:    return "Animations/Equipment/Loading/\(mode)"
        case .unloading:  return "Animations/Equipment/Unloading/\(mode)"
        }
    }

    // MARK: - Wave B · shared equipment-string resolver (2026-06-10)

    /// ONE canonical equipment-string → EquipmentKind matcher for every
    /// surface (shipper LifecycleAnimationStrip, ConvoyAnimationStrip,
    /// rail/vessel live markers, driver equipment band). Replaces the
    /// two divergent private matchers that each missed the T-030 six +
    /// auto-carrier, so a livestock load painted a dry van on one
    /// screen and matched nothing on another.
    ///
    /// `raw` accepts either separator convention ("step deck" /
    /// "step_deck" / "DOT-117") — the matcher normalizes to spaces.
    /// `hazmat` promotes an otherwise-unmatched string to the hazmat
    /// tanker. `modality` is the honest last-resort shape per mode
    /// (dry van / boxcar / container ship) used only when nothing in
    /// the string matched.
    static func resolve(
        from raw: String?,
        hazmat: Bool = false,
        modality: AnimVertical = .truck
    ) -> EquipmentKind {
        let e = (raw ?? "")
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        if !e.isEmpty {
            // Vessel (checked first: "container ship" must not match
            // the container-truck token, "vessel reefer" not reefer).
            if e.contains("vessel reefer") || e.contains("reefer container")  { return .vesselReeferContainer }
            if e.contains("iso tank")                                          { return .vesselISOTank }
            if e.contains("container ship") || e.contains("vessel container") { return .vesselContainer }
            if e.contains("bulk carrier") || e.contains("vessel bulk")         { return .vesselBulk }
            if e.contains("vessel tanker") || e.contains("vlcc")               { return .vesselTanker }
            if e.contains("ro/ro") || e.contains("roro") || e.contains("ro ro") { return .vesselRoRo }
            if e.contains("lng")                                               { return .vesselLNG }

            // Rail
            if e.contains("tofc")                                              { return .railTOFC }
            if e.contains("cofc")                                              { return .railCOFC }
            if e.contains("well car") || e.contains("rail intermodal") ||
               e.contains("double stack") || e.contains("doublestack")         { return .railIntermodal }
            if e.contains("dot 105") || e.contains("rail tank gas") ||
               e.contains("tank pressure") || e.contains("pressure tank car")  { return .railTankGas }
            if e.contains("dot 117") || e.contains("dot 111") ||
               e.contains("rail tank") || e.contains("tank car")               { return .railTankLiquid }
            if e.contains("boxcar") && (e.contains("reefer") || e.contains("refrigerated")) { return .railReeferBoxcar }
            if e.contains("rail reefer")                                       { return .railReeferBoxcar }
            if e.contains("boxcar")                                            { return .railBoxcar }
            if e.contains("hopper") && (e.contains("rail") || e.contains("covered") || e.contains("grain") || modality == .rail) { return .railHopper }
            if e.contains("centerbeam")                                        { return .railCenterbeam }
            if e.contains("gondola")                                           { return .railGondola }
            if e.contains("auto rack") || e.contains("autorack")               { return .railAutoRack }
            if e.contains("flatcar")                                           { return .railFlatcar }

            // Truck — specialized first so "livestock van" never falls
            // into the generic van bucket.
            if e.contains("livestock") || e.contains("cattle")                 { return .livestockCattlePot }
            if e.contains("auto carrier") || e.contains("car hauler") ||
               e.contains("autocarrier") || e.contains("car carrier")          { return .autoCarrier }
            if e.contains("log trailer") || e.contains("logging") ||
               e.contains("timber") || e == "log" || e.hasSuffix(" logs")      { return .logTrailer }
            if e.contains("pneumatic") || e.contains("dry bulk") ||
               e.contains("grain") && modality == .truck                       { return .pneumaticTank }
            if e.contains("end dump") || e.contains("enddump")                 { return .endDump }
            if e.contains("water tank") || e.contains("water truck")           { return .waterTank }
            if e.contains("curtain") || e.contains("tautliner")                { return .curtainSide }
            if e.contains("reefer") || e.contains("refrigerated")              { return .reefer }
            if e.contains("step deck") || e.contains("stepdeck")               { return .stepDeck }
            if e.contains("conestoga")                                         { return .conestoga }
            if e.contains("lowboy") || e.contains("rgn")                       { return .lowboy }
            if e.contains("flatbed")                                           { return .flatbed }
            if e.contains("oversize") || e.contains("schnabel")                { return .oversized }
            if e.contains("hot shot") || e.contains("hotshot")                 { return .hotShot }
            if e.contains("power only") || e.contains("power") || e.contains("bobtail") { return .powerOnly }
            if e.contains("mc 331") || e.contains("mc331") ||
               e.contains("hazmat tanker") || e.contains("tanker hazmat")      { return .tankerHazmat }
            if e.contains("mc 306") || e.contains("dot 406") ||
               e.contains("petro")                                             { return .tankerPetro }
            if e.contains("dot 407") || e.contains("food grade") ||
               e.contains("liquid tank") || e.contains("tanker liquid")        { return .tankerLiquid }
            if e.contains("mc 338") || e.contains("cryo") ||
               e.contains("gas tank") || e.contains("tanker gas")              { return .tankerGas }
            if e.contains("tanker") || e.contains("tank")                      { return hazmat ? .tankerHazmat : .tankerLiquid }
            if e.contains("container") || e.contains("intermodal") ||
               e.contains("chassis")                                           { return .container }
            if e.contains("dry van") || e.contains("van")                      { return .dryVan }
        }

        // Hazmat-aware promotion before the modality floor.
        if hazmat { return .tankerHazmat }
        switch modality {
        case .truck:  return .dryVan
        case .rail:   return .railBoxcar
        case .vessel: return .vesselContainer
        }
    }

    /// Maps the `loads.cargoType` mysqlEnum (general / hazmat /
    /// refrigerated / oversized / liquid / gas / chemicals / petroleum /
    /// livestock / vehicles / timber / grain / dry_bulk / food_grade /
    /// water / intermodal / cryogenic) onto the canonical model when the
    /// load row carries no free-text equipment string (the driver-side
    /// `Load` shape). Real column values only — unknown → modality floor.
    static func resolve(
        cargoType: String?,
        hazmat: Bool = false,
        modality: AnimVertical = .truck
    ) -> EquipmentKind {
        guard modality == .truck else {
            return resolve(from: cargoType, hazmat: hazmat, modality: modality)
        }
        switch (cargoType ?? "").lowercased() {
        case "hazmat", "chemicals":  return .tankerHazmat
        case "petroleum":            return .tankerPetro
        case "liquid", "food_grade": return .tankerLiquid
        case "gas", "cryogenic":     return .tankerGas
        case "refrigerated":         return .reefer
        case "oversized":            return .oversized
        case "livestock":            return .livestockCattlePot
        case "vehicles":             return .autoCarrier
        case "timber":               return .logTrailer
        case "grain", "dry_bulk":    return .pneumaticTank
        case "water":                return .waterTank
        case "intermodal":           return .container
        default:                     return hazmat ? .tankerHazmat : .dryVan
        }
    }

    /// Short user-facing label used by the reactive top-left equipment
    /// badge inside `EquipmentAnimation`. Replaces the SVG-baked text
    /// stripped 2026-05-17 to fix viewBox clipping.
    var shortLabel: String {
        switch self {
        case .dryVan:                return "53′ DRY VAN"
        case .reefer:                return "53′ REEFER"
        case .flatbed:               return "FLATBED 48′"
        case .stepDeck:              return "STEP-DECK"
        case .conestoga:             return "CONESTOGA"
        case .container:             return "CONTAINER"
        case .tankerHazmat:          return "MC-306 HAZMAT"
        case .tankerPetro:           return "MC-306 PETROLEUM"
        case .tankerLiquid:          return "MC-307 LIQUID BULK"
        case .tankerGas:             return "MC-331 GAS / CRYO"
        case .powerOnly:             return "POWER-ONLY"
        case .oversized:             return "OVERSIZE"
        case .railTOFC:              return "TOFC TRAILER-ON-FLATCAR"
        case .railCOFC:              return "COFC CONTAINER-ON-FLATCAR"
        case .railIntermodal:        return "INTERMODAL"
        case .railTankGas:           return "TANK CAR · GAS"
        case .railTankLiquid:        return "TANK CAR · LIQUID"
        case .railBoxcar:            return "BOXCAR"
        case .railHopper:            return "COVERED HOPPER"
        case .railCenterbeam:        return "CENTERBEAM"
        case .railGondola:           return "GONDOLA"
        case .railAutoRack:          return "AUTO-RACK"
        case .railReeferBoxcar:      return "REEFER BOXCAR"
        case .railFlatcar:           return "FLATCAR"
        case .vesselContainer:       return "CONTAINER VESSEL"
        case .vesselBulk:            return "BULK CARRIER"
        case .vesselTanker:          return "TANKER"
        case .vesselRoRo:            return "RoRo / PCC"
        case .vesselLNG:             return "LNG CARRIER"
        case .vesselReeferContainer: return "REEFER VESSEL"
        case .vesselISOTank:         return "ISO-TANK VESSEL"
        case .lowboy:                return "LOWBOY / RGN"
        case .hotShot:               return "HOT-SHOT"
        // T-030 (2026-05-20) — 6 missing trailer labels.
        case .livestockCattlePot:    return "LIVESTOCK / CATTLE POT"
        case .logTrailer:            return "LOG TRAILER"
        case .pneumaticTank:         return "PNEUMATIC TANK"
        case .endDump:               return "END-DUMP"
        case .waterTank:             return "WATER TANK"
        case .curtainSide:           return "CURTAIN-SIDE / TAUTLINER"
        case .autoCarrier:           return "AUTO CARRIER"
        }
    }
}

/// T-029 · 2026-05-20 — Canonical animation state. The .hero variant
/// drives the wizard's equipment-tile selection and existing 33-SVG
/// catalog; .loading and .unloading drive the new 66-SVG state-variant
/// catalog landed in T-028. Consumed by `EquipmentKind.file(for:)`
/// + `EquipmentKind.subdirectory(for:)`.
public enum AnimationState: String, CaseIterable, Codable, Hashable {
    case hero
    case loading
    case unloading

    /// Wave B (2026-06-10) — canonical lifecycle-status → animation-state
    /// selection. Maps every one of the 49 TANKER_LOAD_STATUSES (the
    /// `loads.status` mysqlEnum, schema.additions.wave4-1.ts) onto the
    /// variant whose PROCEDURE the load is physically in:
    ///
    ///   • loading block  (at the rack / dock, pickup side)  → .loading
    ///   • unloading block (at the receiver, discharge side) → .unloading
    ///   • everything else (pre-tender, transit, paperwork,
    ///     financial, terminal, cargo-integrity exceptions)  → .hero
    ///
    /// Rail consist statuses (loading/loaded/unloading…) share the same
    /// vocabulary and resolve through the same buckets. An UNKNOWN status
    /// resolves to .hero — the transit pose is the honest neutral (the
    /// equipment exists regardless of lifecycle), never a fabricated
    /// dock procedure.
    public init(loadStatus: String) {
        switch loadStatus.lowercased() {
        // ── pickup-side procedure (Wave-4 tanker wizard + classic) ──
        case "at_pickup", "pickup_checkin",
             "locked", "backing_in", "brakes_set", "connecting",
             "loading_locked", "loading", "loading_exception",
             "loaded", "load_locked_filled":
            self = .loading
        // ── receiver-side procedure (discharge + detach wizard) ──
        case "at_delivery", "delivery_checkin",
             "discharging", "unloading", "unloading_exception",
             "unloaded", "vapor_purging", "disconnecting",
             "detaching", "released":
            self = .unloading
        // ── everything else: pre-tender / transit / paperwork /
        //    financial / terminal / cargo-integrity exceptions ──
        default:
            self = .hero
        }
    }
}

enum CargoKind: String, Hashable {
    case general, hazmat, refrigerated, oversized
    case liquid, gas, chemicals, petroleum

    /// User-facing label used by the EquipmentAnimation overlay.
    var label: String {
        switch self {
        case .general:      return "General"
        case .hazmat:       return "Hazmat"
        case .refrigerated: return "Refrigerated"
        case .oversized:    return "Oversized"
        case .liquid:       return "Liquid bulk"
        case .gas:          return "Gas / cryo"
        case .chemicals:    return "Chemicals"
        case .petroleum:    return "Petroleum"
        }
    }
}

enum AnimVertical: Hashable {
    case truck, rail, vessel
    var label: String {
        switch self {
        case .truck:  return "Truck"
        case .rail:   return "Rail"
        case .vessel: return "Vessel"
        }
    }
}

// MARK: - Cache

/// Preloads all 33 EusoTrip Animation Design System SVGs at app
/// launch so wizard tile selection and scroll feel instant. Read
/// once off disk → kept as `String` in memory (~50KB total — well
/// under our memory budget).
final class EquipmentAnimationCache {
    static let shared = EquipmentAnimationCache()

    private var store: [String: String] = [:]
    private var didPreload = false
    private let lock = NSLock()

    private init() {}

    /// Fire-once preload. Safe to call multiple times. Resolves every
    /// EquipmentKind's SVG via Bundle.main and caches the contents.
    /// Missing files log to stderr but never crash — the host falls
    /// back to a transparent placeholder.
    @MainActor
    func preload() {
        lock.lock()
        defer { lock.unlock() }
        guard !didPreload else { return }
        didPreload = true
        for kind in EquipmentKind.allCases {
            if let svg = loadSVGFromBundle(kind) {
                store[kind.rawValue] = svg
            }
        }
    }

    /// Returns the cached SVG string for `kind`. Falls back to
    /// reading from the bundle on the first miss (preload may not
    /// have run yet on cold-launch race).
    func svg(for kind: EquipmentKind) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let s = store[kind.rawValue] { return s }
        if let s = loadSVGFromBundle(kind) {
            store[kind.rawValue] = s
            return s
        }
        return nil
    }

    // MARK: - Wave B · state-variant entry point (2026-06-10)

    /// THE cache entry point for the 80-file Loading/Unloading
    /// state-variant catalog. `EquipmentKind.file(for:)` +
    /// `subdirectory(for:)` had ZERO callers since T-029 — every live
    /// surface fed the bind-less hero corpus, which silently no-op'd
    /// the entire BindableEquipmentAnimation data pipeline (LEVEL100
    /// census, bindings row "State-variant catalog": asset quality
    /// ~90, runtime reach 0).
    ///
    /// `.hero` routes through the legacy single-state path. A missing
    /// state-variant file falls back to the HERO of the SAME kind —
    /// still the load's true equipment, just the transit pose (honest
    /// degradation, never a wrong-shape proxy).
    func svg(for kind: EquipmentKind, state: AnimationState) -> String? {
        guard state != .hero else { return svg(for: kind) }
        let key = "\(kind.rawValue)#\(state.rawValue)"
        lock.lock()
        if let s = store[key] {
            lock.unlock()
            return s
        }
        if let s = loadStateVariantFromBundle(kind, state: state) {
            store[key] = s
            lock.unlock()
            return s
        }
        lock.unlock()
        #if DEBUG
        print("[EquipmentAnimationCache] missing \(state.rawValue) variant for \(kind.rawValue) — honest hero fallback")
        #endif
        return svg(for: kind)
    }

    /// Warm both procedure variants for the ACTIVE load's kind so the
    /// lifecycle swap (hero → loading → unloading) crossfades without
    /// a first-parse hitch. Called from the strips' `.task` the moment
    /// the live load's equipment resolves — the full 120-file corpus
    /// is never preloaded wholesale.
    func preloadStateVariants(for kind: EquipmentKind) {
        _ = svg(for: kind, state: .loading)
        _ = svg(for: kind, state: .unloading)
    }

    private func loadStateVariantFromBundle(
        _ kind: EquipmentKind, state: AnimationState
    ) -> String? {
        guard let file = kind.file(for: state) else { return nil }
        // AnimationBindingMap file names carry the ".svg" extension;
        // Bundle.main.url wants the stem + explicit extension.
        let stem = file.hasSuffix(".svg") ? String(file.dropLast(4)) : file
        guard let url = Bundle.main.url(
            forResource: stem,
            withExtension: "svg",
            subdirectory: kind.subdirectory(for: state)
        ) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func loadSVGFromBundle(_ kind: EquipmentKind) -> String? {
        guard let url = Bundle.main.url(
            forResource: kind.svgFilename,
            withExtension: "svg",
            subdirectory: kind.svgSubdirectory
        ) else {
            #if DEBUG
            print("[EquipmentAnimationCache] missing svg: \(kind.svgFilename) in \(kind.svgSubdirectory)")
            #endif
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

// MARK: - Public SwiftUI entry

/// Drop-in replacement for the v1 SwiftUI-shape silhouettes. Picks
/// the right SVG from `EquipmentAnimationCache` based on the
/// equipment + cargo + flag tuple, hosts it via a transparent
/// WKWebView. The TimelineView shell stays so external callers can
/// later layer SwiftUI overlays without re-architecting.
struct EquipmentAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    let equipment: EquipmentKind
    let cargo: CargoKind
    let weightUnit: String

    var tankerHose: String      = ""
    var isHazmat: Bool          = false
    var ergMatched: Bool        = false
    var reeferLowText: String   = ""
    var reeferHighText: String  = ""
    var preCoolRequired: Bool   = false
    var continuousMode: Bool    = true
    var flatbedStraps: Bool     = false
    var flatbedTarps: Bool      = false
    var flatbedChains: Bool     = false
    var flatbedEdgeProtectors: Bool = false
    var oversizePermits: Bool   = false
    /// COUNTRY-GROUP TOGGLE (Wave E engine API, additive — Wave C wires the
    /// real load region into call sites). Selects which of the authored
    /// `.country-US/-MX/-CA` regulatory groups (placards, credentials,
    /// emergency contacts) the SVG renders. nil = US default — the engine
    /// guarantees exactly ONE country group per render, never multiple.
    var country: SVGCountry?    = nil

    var body: some View {
        ZStack {
            backgroundFill
            content
            // Reactive label layer: top-left equipment label (e.g.
            // "RAIL · TOFC / TRAILER ON FLATCAR") + top-right vertical
            // and unit badges + bottom-right brand wordmark. All text
            // lives in SwiftUI now — SVGs are pure artwork. Founder
            // firing 2026-05-17: baked SVG labels were clipping at the
            // tightened viewBox; reactive overlay never clips and
            // always reflects live wizard selections.
            topLeftEquipmentLabel
            topRightBadgeStack
            bottomRightBrandWordmark
            if isHazmat {
                hazmatPulseLayer
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
    }

    /// Top-left equipment label — derives the headline + subhead from
    /// the live equipment + cargo selection. Replaces the baked SVG
    /// "53' REEFER · REFRIGERATED · COLD CHAIN" group that used to
    /// clip at the viewBox.
    private var topLeftEquipmentLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(equipmentHeadline)
                    .font(.system(size: 10, weight: .heavy)).tracking(1.2)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Rectangle()
                .fill(LinearGradient.diagonal.opacity(0.55))
                .frame(width: 36, height: 1.5)
            Text(equipmentSubhead)
                .font(.system(size: 8, weight: .semibold)).tracking(0.6)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    /// Bottom-right brand wordmark — replaces the SVG-baked "EUSOTRIP
    /// by Eusorone" lockup that lived at the top-center and clipped.
    private var bottomRightBrandWordmark: some View {
        HStack(spacing: 4) {
            Text("EUSOTRIP")
                .font(.system(size: 8, weight: .heavy)).tracking(2.0)
                .foregroundStyle(palette.textSecondary.opacity(0.6))
            Circle()
                .fill(LinearGradient.diagonal)
                .frame(width: 3, height: 3)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .allowsHitTesting(false)
    }

    /// Headline line — derived from equipment vertical + product
    /// subtype. Example outputs:
    ///   TRUCK · 53' REEFER
    ///   RAIL · TOFC TRAILER-ON-FLATCAR
    ///   VESSEL · TANKER (CRUDE)
    private var equipmentHeadline: String {
        let v = equipment.vertical.label.uppercased()
        return "\(v) · \(equipment.shortLabel)"
    }

    /// Subhead — cargo descriptor + any active flags.
    private var equipmentSubhead: String {
        var bits: [String] = [cargo.label.uppercased()]
        if isHazmat { bits.append("HAZMAT") }
        switch equipment {
        case .reefer, .vesselReeferContainer, .railReeferBoxcar:
            if !reeferLowText.isEmpty, !reeferHighText.isEmpty {
                bits.append("\(reeferLowText)–\(reeferHighText)°F")
            } else if preCoolRequired {
                bits.append("PRE-COOL")
            } else if continuousMode {
                bits.append("CONT. MODE")
            }
        case .oversized, .lowboy:
            if oversizePermits { bits.append("PERMIT") }
        case .tankerHazmat, .tankerPetro, .tankerLiquid, .tankerGas, .vesselTanker:
            if ergMatched { bits.append("ERG MATCHED") }
            if !tankerHose.isEmpty { bits.append(tankerHose.uppercased()) }
        default: break
        }
        return bits.joined(separator: " · ")
    }

    @ViewBuilder
    private var backgroundFill: some View {
        // Soft vertical gradient — subtle, never competing with the
        // SVG's own composition. The SVG's brand-lockup E-mark sits
        // on this surface.
        switch equipment.vertical {
        case .truck:
            LinearGradient(
                colors: [palette.bgCard, palette.bgCardSoft],
                startPoint: .top, endPoint: .bottom
            )
        case .rail:
            LinearGradient(
                colors: [Brand.rail.opacity(0.20), palette.bgCardSoft],
                startPoint: .top, endPoint: .bottom
            )
        case .vessel:
            LinearGradient(
                colors: [Brand.vessel.opacity(0.25), palette.bgCard],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if let svg = EquipmentAnimationCache.shared.svg(for: equipment) {
            NativeSVGView(svgString: svg, country: country)
                .padding(2)
        } else {
            // Honest fallback — never a fabricated silhouette.
            VStack(spacing: 6) {
                Image(systemName: "questionmark.square.dashed")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                Text("Animation missing")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(equipment.svgFilename)
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var topRightBadgeStack: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            Text(equipment.vertical.label.uppercased())
                .font(.system(size: 7, weight: .heavy)).tracking(0.6)
                .foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Capsule().fill(verticalBadgeColor))
            Text(weightUnit.uppercased())
                .font(.system(size: 7, weight: .heavy, design: .monospaced)).tracking(0.4)
                .foregroundStyle(LinearGradient.diagonal)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .overlay(Capsule().strokeBorder(LinearGradient.diagonal.opacity(0.6), lineWidth: 1))
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topTrailing)
    }

    private var verticalBadgeColor: Color {
        switch equipment.vertical {
        case .truck:  return Brand.blue
        case .rail:   return Brand.rail
        case .vessel: return Brand.vessel
        }
    }

    /// Hazmat radial wash. Wrapped in TimelineView so we get a 30fps
    /// pulse without invalidating the WebView. Reduce-motion freezes
    /// at static low intensity.
    @ViewBuilder
    private var hazmatPulseLayer: some View {
        if reduceMotion {
            RadialGradient(
                colors: [Brand.hazmat.opacity(ergMatched ? 0.18 : 0.10), .clear],
                center: .center, startRadius: 30, endRadius: 220
            )
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        } else {
            TimelineView(.animation(minimumInterval: 1.0/30.0)) { ctx in
                let t = ctx.date.timeIntervalSince1970
                let pulse = (sin(t * 1.6) + 1) / 2
                let intensity: Double = ergMatched ? 0.20 : 0.10
                RadialGradient(
                    colors: [Brand.hazmat.opacity(intensity * (0.5 + 0.5 * pulse)), .clear],
                    center: .center, startRadius: 30, endRadius: 220
                )
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Wave B · Driver equipment moment band (2026-06-10)

/// The driver's equipment moment — mounts the (Wave-B de-orphaned)
/// state-variant procedure animation on the driver lifecycle screens
/// where the procedure physically happens: the driver standing at the
/// rack during 016/030 sees 08_tanker_petro_loading.svg with REAL
/// bindings; 024/040/042 see the unloading/discharge variant.
///
/// The band COMPLEMENTS the bespoke gauges per screen (044's diagram
/// is the quality bar) — it never replaces them. Every moving value is
/// live-or-honestly-absent: bindings come from
/// `LoadAnimationContext.from(facts:)` (real load row), progress from
/// the canonical 49-status ramp, and an unhydrated load renders the
/// honest awaiting card — never a sample rig.
struct DriverEquipmentMoment: View {
    @Environment(\.palette) private var palette

    /// Real load facts — nil until the screen's load hydrates.
    let facts: LoadAnimationContext.DriverLoadFacts?
    /// The procedure this SCREEN hosts (016/030 → .loading,
    /// 024/040/042 → .unloading). The screen itself encodes the
    /// physical moment; status drives the progress + state chip.
    let state: AnimationState
    /// Bespoke per-screen header label ("AT THE RACK", "DISCHARGE
    /// SIDE", …) per bespoke-port-fidelity.
    var label: String = "EQUIPMENT"
    var height: CGFloat = 168

    /// Continuity clock epoch — phase carries across variant swaps.
    @State private var epoch = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: equipmentKind.iconName)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(label)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                Text(stateChip)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
            }

            if let facts,
               let svg = EquipmentAnimationCache.shared
                   .svg(for: equipmentKind, state: state) {
                BindableEquipmentAnimation(
                    svgString: svg,
                    context: LoadAnimationContext.from(facts: facts),
                    clockReference: epoch
                )
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
            } else {
                // Honest awaiting state — the load row hasn't hydrated
                // (or the catalog file is genuinely missing). Never a
                // sample rig with fabricated chips.
                VStack(spacing: 6) {
                    Image(systemName: "truck.box")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                    Text(facts == nil ? "Awaiting load data" : "Equipment animation not bundled")
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(palette.bgCardSoft)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .task(id: facts?.status) {
            // Warm both procedure variants for this kind the moment the
            // load resolves so the swap crossfades without a parse hitch.
            if facts != nil {
                EquipmentAnimationCache.shared.preloadStateVariants(for: equipmentKind)
            }
        }
    }

    private var equipmentKind: EquipmentKind {
        guard let facts else { return .dryVan }
        let modality: AnimVertical = {
            switch (facts.transportMode ?? "truck").lowercased() {
            case "rail":   return .rail
            case "vessel": return .vessel
            default:       return .truck
            }
        }()
        if let e = facts.equipmentType, !e.isEmpty {
            return EquipmentKind.resolve(
                from: e,
                hazmat: (facts.hazmatClass?.isEmpty == false),
                modality: modality
            )
        }
        return EquipmentKind.resolve(
            cargoType: facts.cargoType,
            hazmat: (facts.hazmatClass?.isEmpty == false),
            modality: modality
        )
    }

    private var stateChip: String {
        guard let facts else { return "—" }
        if let sub = facts.tankerSubState?
            .trimmingCharacters(in: .whitespacesAndNewlines), !sub.isEmpty {
            return sub.uppercased().replacingOccurrences(of: "_", with: " ")
        }
        let s = facts.status.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "—" : s.uppercased().replacingOccurrences(of: "_", with: " ")
    }
}

// MARK: - Previews

#Preview("Tanker · Hazmat · Dark") {
    EquipmentAnimation(
        equipment: .tankerHazmat,
        cargo: .hazmat,
        weightUnit: "bbl",
        isHazmat: true,
        ergMatched: true
    )
    .frame(height: 200)
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Reefer · Light") {
    EquipmentAnimation(
        equipment: .reefer,
        cargo: .refrigerated,
        weightUnit: "plt"
    )
    .frame(height: 200)
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Vessel · Container · Dark") {
    EquipmentAnimation(
        equipment: .vesselContainer,
        cargo: .general,
        weightUnit: "TEU"
    )
    .frame(height: 200)
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Rail · COFC · Light") {
    EquipmentAnimation(
        equipment: .railCOFC,
        cargo: .general,
        weightUnit: "mt"
    )
    .frame(height: 200)
    .padding()
    .preferredColorScheme(.light)
}
