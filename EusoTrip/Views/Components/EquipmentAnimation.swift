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
import WebKit

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
        // T-030 hero fallbacks — closest-shape v1 SVG until the
        // dedicated state-variant catalog ships (T-030b on the design
        // backlog). Once the 6 dedicated hero SVGs land, swap each
        // case to its own asset name.
        case .livestockCattlePot:    return "34_livestock_anim"          // dedicated SVG (2026-05-29)
        case .logTrailer:            return "39_log_trailer_anim"        // dedicated SVG (2026-05-29)
        case .pneumaticTank:         return "36_pneumatic_dry_bulk_anim" // dedicated SVG (2026-05-29)
        case .endDump:               return "37_end_dump_anim"           // dedicated SVG (2026-05-29)
        case .waterTank:             return "38_water_tank_anim"         // dedicated SVG (2026-05-29)
        case .curtainSide:           return "40_curtain_side_anim"       // dedicated SVG (2026-05-29)
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
        }
    }

    /// Resolve the SVG filename for a given state via the canonical
    /// AnimationBindingMap. Replaces the legacy single-state
    /// `svgFilename` lookup. Returns nil when no binding exists OR the
    /// canonical bridge fails — callers should fall back to
    /// `svgFilename` (hero) for legacy back-compat.
    func file(for state: AnimationState) -> String? {
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

// MARK: - WKWebView host

/// Transparent SVG-rendering web view. The SVG carries its own
/// SMIL / CSS animations + brand lockup + `prefers-reduced-motion`
/// query — iOS just hosts the document. All scrolling + bouncing is
/// disabled so the document never moves inside its tile.
private struct EquipmentAnimationWebView: UIViewRepresentable {
    let svgString: String
    let colorScheme: ColorScheme
    let country: String   // "US" | "MX" | "CA" — selects the placard/marking group

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // No JS bridge needed; the SVG runs SMIL natively. Block
        // navigation entirely — taps stay with the SwiftUI host.
        // iOS 14+ uses WKWebpagePreferences.allowsContentJavaScript;
        // the older WKPreferences.javaScriptEnabled was deprecated.
        let pagePrefs = WKWebpagePreferences()
        pagePrefs.allowsContentJavaScript = false
        config.defaultWebpagePreferences = pagePrefs
        config.suppressesIncrementalRendering = true

        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.bounces = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.scrollView.showsVerticalScrollIndicator = false
        view.scrollView.showsHorizontalScrollIndicator = false
        view.scrollView.isUserInteractionEnabled = false
        view.isUserInteractionEnabled = false   // pass touches to host
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        // Forward the SwiftUI color scheme to WebKit so the SVG's
        // `@media (prefers-color-scheme: dark)` rules actually fire.
        // Without this, WKWebView inherits the system trait, which on
        // a dark-themed app screen with light system style produces a
        // light-mode SVG rendering — exactly the "sticks out like a
        // sore thumb" mismatch the founder flagged 2026-05-16.
        view.overrideUserInterfaceStyle = (colorScheme == .dark) ? .dark : .light
        // Wrap the bare SVG markup in an HTML document with a
        // transparent body so the rendered surface composites
        // cleanly under SwiftUI's hierarchy. width=device-width
        // viewport prevents WebKit from upscaling the SVG.
        let html = """
        <!DOCTYPE html>
        <html><head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <style>
          html, body {
            margin: 0; padding: 0;
            background: transparent;
            width: 100%; height: 100%;
            overflow: hidden;
            -webkit-touch-callout: none;
            -webkit-user-select: none;
          }
          svg {
            display: block;
            width: 100%; height: 100%;
          }
          /* Country placard selector — the equipment SVGs carry
             .country-US / .country-MX / .country-CA marking groups
             (DOT·PHMSA / SCT·NOM / TDG). Show only the operating
             country's group; pure CSS so it works with JS disabled. */
          .country-US, .country-MX, .country-CA { display: none !important; }
          .country-\(country) { display: inline !important; }
        </style>
        </head><body>
        \(svgString)
        </body></html>
        """
        view.loadHTMLString(html, baseURL: Bundle.main.bundleURL)
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
    /// Operating country ("US" | "MX" | "CA") of the load's jurisdiction —
    /// selects which placard/marking group the SVG shows (DOT·PHMSA /
    /// SCT·NOM / TDG). Defaults to US.
    var operatingCountry: String = "US"

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
            EquipmentAnimationWebView(svgString: svg, colorScheme: colorScheme, country: operatingCountry)
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
