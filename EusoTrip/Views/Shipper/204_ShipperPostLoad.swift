//
//  204_ShipperPostLoad.swift
//  EusoTrip — Shipper · Post a Load (brick 204).
//
//  Parity-reconciled to `02 Shipper/Code/204_ShipperPostLoad.swift` per
//  _PARITY_PROMPT_FOR_CODING_TEAM_2026-04-29.md. Wireframe canon
//  applied: 4-step stepper (LANE → EQUIPMENT → PRICING → REVIEW),
//  TopBar (eyebrow + step counter + back chevron + Post a load title
//  + close X), IridescentHairline, lane card with bullet-circle
//  endpoints + dashed connector + swap button, route-meta pill,
//  schedule tile pair, equipment preview (locked behind step 2 with
//  hazmat diamond glyph), target rate estimate card, Continue/Submit
//  CTA per-step.
//
//  Real data preserved: ShipperPostLoadStore + shippers.create
//  mutation pipeline (validation, optional fields → nil coalesce,
//  reset form on success). Form bindings unchanged. Cargo type
//  picker kept on the EQUIPMENT step. Weight/rate/notes on the
//  PRICING step.
//
//  Persona canon (§11): Diego Usoro · Eusorone Technologies (companyId 1).
//  §11.2 anchor MATRIX-50 row this brick is calibrated against:
//    LD-260427-A38FB12C7E · Houston TX → Dallas TX · MC-306 · UN1203 ·
//    50,000 lb · target $1,950 (= $8.16/mi, +3% above $7.92/mi spot).
//
//  BottomNav: Home / Create Load (current) / Loads / Me — out of scope
//  per parity mandate §1.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation

// MARK: - 4-step state machine

private enum PostLoadStep: Int, CaseIterable, Identifiable {
    case lane      = 1
    case equipment = 2
    case pricing   = 3
    case review    = 4

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .lane:      return "LANE"
        case .equipment: return "EQUIPMENT"
        case .pricing:   return "PRICING"
        case .review:    return "REVIEW"
        }
    }
    var next: PostLoadStep? { PostLoadStep(rawValue: rawValue + 1) }
    var prev: PostLoadStep? { PostLoadStep(rawValue: rawValue - 1) }
}

// MARK: - Screen root

struct ShipperPostLoad: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var store = ShipperPostLoadStore()

    // Wizard state
    @State private var step: PostLoadStep = .lane

    // Form state — preserved from prior surface
    @State private var origin: String = ""
    @State private var destination: String = ""
    // Geocoded coordinates captured by `HereAddressField`. Sent with
    // `shippers.create` so distance / map render without a server-
    // side re-geocode round-trip. Founder report 2026-05-05 — the
    // 204 Post Load screen was using plain `TextField` for
    // origin/destination, not the autocomplete-aware HereAddressField
    // that step 250 uses, so users typing "Housto" got iOS keyboard
    // predictions but no platform autocomplete. Swapped below.
    @State private var originLat: Double? = nil
    @State private var originLng: Double? = nil
    @State private var destLat: Double? = nil
    @State private var destLng: Double? = nil
    @State private var originCountryCode: String = "US"
    @State private var destinationCountryCode: String = "US"
    @State private var cargoType: ShipperAPI.CargoType = .general
    @State private var hasPickupDate: Bool = false
    @State private var pickupDate: Date = Date()
    @State private var weightText: String = ""
    @State private var rateText: String = ""
    @State private var notes: String = ""

    // 2026-05-17 — Multi-modal transport-mode picker on Step 1. Cascades
    // to the Step 2 equipment chip filter so the user sees rail chips
    // when they pick rail, vessel chips when they pick vessel, etc.
    // Persists onto loads.transport_mode via shippers.create.
    @State private var transportMode: TransportMode = .truck

    // Equipment type picker — all verticals + product types per the
    // founder's "all verticals" doctrine. The selected type is sent
    // as `equipmentType` on `shippers.create`. Default = dry van.
    @State private var equipmentType: EquipmentChoice = .dryVan

    // Hazmat / tanker subform fields. Stored locally and packed into
    // the `notes` field at submit time (server schema doesn't yet
    // ship structured tanker spec columns; web parity).
    @State private var unNumber: String = ""
    @State private var hazmatClass: String = ""
    @State private var packingGroup: String = ""
    @State private var properShippingName: String = ""

    // ─── 2026-08-07 · cargo-classification attestation ────────────────
    // The poster's determination + evidence, captured through the ONE
    // shared primitive (Views/Components/CargoClassificationAttestation).
    // `shippers.create` requires it on EVERY post — general freight
    // included — and refuses with PRECONDITION_FAILED without it.
    // Starts empty: no determination, no source, no evidence reference.
    // Nothing on this screen (cargo chip, trailer, ERG match, vertical)
    // is ever allowed to fill it in.
    @State private var cargoAttestation = CargoClassificationAttestation()
    @State private var tankerHoseSpec: String = ""
    @State private var tankerFitting: String = ""
    // 2026-06-03 — data-driven equipment requirements (EquipmentRequirementsCatalog,
    // from the 25/19-agent multimodal research). Per equipmentType: groupKey ->
    // selected option keys, and groupKey -> "Other (specify)" free text. Every
    // equipment type now has its real requirement options; nothing blocks.
    @State private var equipReqSel: [String: Set<String>] = [:]
    @State private var equipReqOther: [String: String] = [:]
    // ─── Catalyst Requirements (web parity, 2026-05-20) ───
    // Web wizard Step 7 captures min safety score (0-100) + a set of
    // CDL endorsements the catalyst's driver must hold. iOS now matches
    // — values land in composeSubmissionNotes() until shippers.create
    // gains structured columns. See loads.ts:155-156 for the loads
    // route equivalent.
    @State private var catalystMinSafetyScore: Double = 80
    @State private var catalystEndorsements: Set<String> = []
    @State private var showCatalystRequirements: Bool = false
    // ─── Per-mode carrier-eligibility requirements (2026-06-01) ───
    // Founder bug: the catalyst card rendered TRUCK reqs (FMCSA CSA
    // score + CDL endorsements) in EVERY mode. A shipper posting a
    // vessel / rail / barge load was asked for a "CDL endorsement",
    // which is nonsense on water or rail. These sets capture the
    // RIGHT regulatory eligibility gates the shipper demands of any
    // carrier bidding the load, per mode. They serialize into
    // composeSubmissionNotes() the same way the truck reqs do until
    // shippers.create gains structured per-mode requirement columns.
    //   • vessel  → SOLAS / IMO-IMDG / ISM / ISPS / STCW / SIRE vetting
    //   • rail    → AAR interchange rule compliance / FRA / PTC
    //   • barge   → USCG COI / Subchapter M / Tankerman-PIC / inland TWIC
    // No fabricated numbers — these are documented, selectable
    // regulatory regimes the carrier must attest to.
    @State private var catalystVesselRequirements: Set<String> = []
    @State private var catalystRailRequirements: Set<String> = []
    @State private var catalystBargeRequirements: Set<String> = []

    // ERG (Emergency Response Guidebook) lookup state. When the user
    // types a UN number, debounce → fire `erg.searchByUN` → if a
    // match is found, auto-populate hazmat class + proper shipping
    // name + ERG guide. Web parity with the platform's ERG database.
    @State private var ergMatch: ErgAPI.MaterialDetail? = nil
    @State private var isLookingUpERG: Bool = false
    @State private var ergLookupError: String? = nil
    @State private var lastErgQueryKey: String = ""
    @State private var showErgSearchSheet: Bool = false
    @State private var ergSearchQuery: String = ""
    @State private var ergSearchHits: [ErgAPI.SearchHit] = []
    @State private var isSearchingERG: Bool = false

    // Non-hazmat commodity lookup state — the ERG-parity sibling for
    // non-hazardous cargo. When the chosen cargo type is NOT hazmat-
    // flavored the wizard surfaces a typeahead against the right
    // `commodity.*` proc (chemical / petroleum / reefer / container /
    // STCC) and pins the chosen product into `properShippingName`
    // (and the reefer temp band, for the reefer lookup). Mirrors the
    // ERG search-sheet + binding pattern exactly.
    @State private var showCommoditySearchSheet: Bool = false
    @State private var commoditySearchQuery: String = ""
    @State private var commoditySearchHits: [CommodityLookupAPI.CommodityHit] = []
    @State private var isSearchingCommodity: Bool = false
    @State private var commodityLookupError: String? = nil
    /// The selected non-hazmat commodity, pinned into the structured
    /// block (mirrors `ergMatch` for the hazmat branch).
    @State private var commodityMatch: CommodityLookupAPI.CommodityHit? = nil

    // Reefer subform.
    @State private var reeferTempLowText:  String = ""
    @State private var reeferTempHighText: String = ""
    @State private var preCoolRequired:    Bool = false
    @State private var continuousMode:     Bool = true

    // Flatbed / oversized subform.
    @State private var flatbedStraps:          Bool = false
    @State private var flatbedTarps:           Bool = false
    @State private var flatbedChains:          Bool = false
    @State private var flatbedEdgeProtectors:  Bool = false
    @State private var oversizeLengthText:     String = ""
    @State private var oversizeWidthText:      String = ""
    @State private var oversizeHeightText:     String = ""
    @State private var oversizePermits:        Bool = false
    @State private var permitType:             PermitType = .none

    /// Quantity-unit choice — auto-defaults from equipment + cargo
    /// type but the user can override. Carriers measure freight in
    /// units that match the product, not pounds for everything.
    /// Petroleum runs on barrels / gallons, dry bulk on bushels /
    /// tons, palletized freight on pallets / lbs, vessel containers
    /// on TEUs / metric tons. Web parity: same unit menu the
    /// platform's web shipper UI surfaces.
    @State private var weightUnit: MeasurementUnit = .pounds

    @State private var lastSuccess: ShipperAPI.PostLoadAck? = nil

    // A completed Port Intelligence draft assessment is one-use and bound to
    // the exact cargo/lane fingerprint on the server. Keep its local signature
    // so any edit makes the result visibly stale before the user can post.
    @State private var portIntelligenceAssessment: PortIntelAssessment? = nil
    @State private var portIntelligenceAssessmentSignature: String? = nil
    @State private var portIntelligenceAcknowledged: Bool = false
    @State private var isAssessingPortIntelligence: Bool = false
    @State private var portIntelligenceError: String? = nil

    private struct PostLoadCountry: Identifiable {
        let code: String
        let name: String
        var id: String { code }
    }

    private static let postLoadCountries: [PostLoadCountry] = Locale.isoRegionCodes
        .filter { $0.count == 2 }
        .compactMap { code in
            guard let name = Locale.current.localizedString(forRegionCode: code) else { return nil }
            return PostLoadCountry(code: code.uppercased(), name: name)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    // F-ANIMATION (2026-06-14) — founder ask: a bespoke professional
    // "Load posted" celebration, then a return to a fresh Step-1. On a
    // successful post we raise this full-bleed overlay (the house
    // celebration, zero SF Symbols) instead of leaving the user parked on
    // Review with a static check banner. Dismissing it (auto or tap)
    // resets the form and snaps the wizard back to the Lane step.
    @State private var showPostedCelebration: Bool = false

    // MARK: - Autosave + cross-device continuity
    //
    // Founder ask 2026-05-07: "truly autosaves in case phone dies or
    // app closes" + "save on one device it should show up in their
    // account on the other, pure continuity".
    //
    // Strategy:
    // 1. Local crash-recovery: UserDefaults via PostLoadDraftSnapshot.
    // 2. Cross-device: NSUbiquitousKeyValueStore (Apple's free iCloud
    //    KVS — auto-syncs across user's devices, ~1KB / draft fits
    //    well under 1MB cap).
    // 3. Server-backed templates for true cross-platform parity:
    //    `loadTemplates.create` saves a named template; web platform
    //    sees it via the same router.
    @State private var didHydrateDraft: Bool = false
    @State private var showTemplatePicker: Bool = false
    @State private var showSaveTemplateSheet: Bool = false
    @State private var savingTemplate: Bool = false
    @State private var templateSaveAck: String? = nil
    @State private var templateSaveError: String? = nil
    @State private var templateNameDraft: String = ""

    // Templates picker state (loadTemplates.list)
    @State private var templates: [LoadTemplatesAPI.Template] = []
    @State private var isLoadingTemplates: Bool = false
    @State private var templateSearchQuery: String = ""

    // Doc-router classifier sheets (Templates "Scan to pre-fill" +
    // Bulk pill). Both surfaces route through 204_DocumentClassifierSheet
    // which calls `documentRouter.classifyAndRoute` / `classifyBatch`
    // against Gemini Vision and hands back extractedFields the wizard
    // can apply.
    @State private var showDocClassifierSingle: Bool = false
    @State private var showDocClassifierBulk: Bool = false
    /// Provenance of a document pre-fill.
    ///
    /// 2026-08-12 — these two were WRITTEN by `applyClassifiedDocument`
    /// and rendered by nothing: the comment promised a banner that did
    /// not exist. So a scan silently overwrote the lane, the equipment,
    /// the cargo type, the weight, the rate AND the hazmat identity
    /// (UN number, hazard class, packing group, proper shipping name)
    /// with no mark on the screen saying a machine had put them there.
    /// Those are regulated fields; a machine reading of them must be a
    /// proposal a human accepts, never a silent commit.
    ///
    /// The banner below now renders, names every field the scan wrote,
    /// and stays until the shipper acknowledges it.
    @State private var prefillBannerType: String? = nil
    @State private var prefillBannerSummary: String? = nil
    /// Human-readable names of the fields the last scan wrote, in the
    /// order the form reads. A field the reader did not return is NOT
    /// listed — it was never touched.
    @State private var prefillFieldLabels: [String] = []
    /// Field names that carry regulatory weight, tracked separately so
    /// the banner can call them out first.
    @State private var prefillRegulatedLabels: [String] = []
    /// Flipped by the shipper tapping "I've checked these".
    @State private var prefillAcknowledged: Bool = false
    /// Most recent batch result — when the user dismisses the bulk
    /// sheet with a "route N docs" tap we flip this on; ESANG then
    /// surfaces a routing summary on the wizard.
    @State private var bulkBannerCount: Int = 0
    @State private var bulkBannerTopType: String? = nil

    /// Equipment-type choice covering truck (dry van / reefer /
    /// flatbed / step deck / conestoga / container / tanker variants
    /// / power-only), rail (TOFC / COFC / intermodal container),
    /// and vessel (container / bulk / tanker) verticals. Web parity
    /// with the platform's full LoadEquipmentType enum. Stored as
    /// the raw string sent to `shippers.create` so the catalyst's
    /// dispatcher / driver knows what physical asset to roll.
    enum EquipmentChoice: String, CaseIterable, Identifiable {
        // ── Truck (12) ─────────────────────────────────────────────
        case dryVan        = "dry_van"
        case reefer        = "reefer"
        case flatbed       = "flatbed"
        case stepDeck      = "step_deck"
        case conestoga     = "conestoga"
        case container     = "container"
        case tankerHazmat  = "tanker_hazmat"
        case tankerPetro   = "tanker_petroleum"
        case tankerLiquid  = "tanker_liquid"
        case tankerGas     = "tanker_gas"
        case powerOnly     = "power_only"
        case oversized     = "oversized"
        // ── Truck extended (2) ────────────────────────────────────
        case lowboy        = "lowboy"
        case hotShot       = "hot_shot"
        // ── Rail (12) ──────────────────────────────────────────────
        // 2026-05-18 — expanded from 3 to 12 to match the rail SVGs
        // already on disk. Founder firing: hazmat tank cars, hoppers,
        // boxcars, autoracks, centerbeam flatcars, well cars, gondolas,
        // reefer boxcars must all be selectable so cargo↔equipment
        // auto-snap can land on a rail-accurate type.
        case railTOFC          = "rail_tofc"
        case railCOFC          = "rail_cofc"
        case railIntermodal    = "rail_intermodal"
        case railTankGas       = "rail_tank_gas"
        case railTankLiquid    = "rail_tank_liquid"
        case railBoxcar        = "rail_boxcar"
        case railReeferBoxcar  = "rail_reefer_boxcar"
        case railHopper        = "rail_hopper"
        case railCenterbeam    = "rail_centerbeam"
        case railGondola       = "rail_gondola"
        case railAutoRack      = "rail_auto_rack"
        case railFlatcar       = "rail_flatcar"
        // ── Vessel (7) ─────────────────────────────────────────────
        // Same expansion — adds RoRo (autos), LNG carrier, reefer
        // container ship, and ISO-tank ship so vessel shippers get
        // an honest list instead of "container / bulk / tanker".
        case vesselContainer        = "vessel_container"
        case vesselBulk             = "vessel_bulk"
        case vesselTanker           = "vessel_tanker"
        case vesselRoRo             = "vessel_roro"
        case vesselLNG              = "vessel_lng"
        case vesselReeferContainer  = "vessel_reefer_container"
        case vesselISOTank          = "vessel_iso_tank"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .dryVan:                return "Dry van"
            case .reefer:                return "Reefer"
            case .flatbed:               return "Flatbed"
            case .stepDeck:              return "Step deck"
            case .conestoga:             return "Conestoga"
            case .container:             return "Container"
            case .tankerHazmat:          return "Tanker · Hazmat"
            case .tankerPetro:           return "Tanker · Petroleum"
            case .tankerLiquid:          return "Tanker · Liquid bulk"
            case .tankerGas:             return "Tanker · Gas"
            case .powerOnly:             return "Power only"
            case .oversized:             return "Oversized"
            case .lowboy:                return "Lowboy"
            case .hotShot:               return "Hot shot"
            case .railTOFC:              return "Rail · TOFC"
            case .railCOFC:              return "Rail · COFC"
            case .railIntermodal:        return "Rail · Intermodal"
            case .railTankGas:           return "Rail · Tank · Gas"
            case .railTankLiquid:        return "Rail · Tank · Liquid"
            case .railBoxcar:            return "Rail · Boxcar"
            case .railReeferBoxcar:      return "Rail · Reefer boxcar"
            case .railHopper:            return "Rail · Hopper"
            case .railCenterbeam:        return "Rail · Centerbeam"
            case .railGondola:           return "Rail · Gondola"
            case .railAutoRack:          return "Rail · Autorack"
            case .railFlatcar:           return "Rail · Flatcar"
            case .vesselContainer:       return "Vessel · Container"
            case .vesselBulk:            return "Vessel · Bulk"
            case .vesselTanker:          return "Vessel · Tanker"
            case .vesselRoRo:            return "Vessel · RoRo"
            case .vesselLNG:             return "Vessel · LNG"
            case .vesselReeferContainer: return "Vessel · Reefer container"
            case .vesselISOTank:         return "Vessel · ISO tank"
            }
        }

        var systemImage: String {
            switch self {
            case .dryVan:                return "shippingbox.fill"
            case .reefer:                return "thermometer.snowflake"
            case .flatbed:               return "rectangle.expand.vertical"
            case .stepDeck:              return "rectangle.split.2x1"
            case .conestoga:             return "shippingbox.and.arrow.backward"
            case .container:             return "cube.box.fill"
            case .tankerHazmat:          return "exclamationmark.triangle.fill"
            case .tankerPetro:           return "fuelpump.fill"
            case .tankerLiquid:          return "drop.triangle.fill"
            case .tankerGas:             return "wind"
            case .powerOnly:             return "bolt.car.fill"
            case .oversized:             return "arrow.up.left.and.arrow.down.right"
            case .lowboy:                return "rectangle.bottomthird.inset.filled"
            case .hotShot:               return "bolt.fill"
            case .railTOFC:              return "tram.fill"
            case .railCOFC:              return "tram"
            case .railIntermodal:        return "cube.transparent.fill"
            case .railTankGas:           return "wind"
            case .railTankLiquid:        return "drop.triangle.fill"
            case .railBoxcar:            return "shippingbox.fill"
            case .railReeferBoxcar:      return "thermometer.snowflake"
            case .railHopper:            return "leaf.fill"
            case .railCenterbeam:        return "rectangle.split.3x1"
            case .railGondola:           return "rectangle"
            case .railAutoRack:          return "car.2.fill"
            case .railFlatcar:           return "rectangle.expand.vertical"
            case .vesselContainer:       return "ferry.fill"
            case .vesselBulk:            return "ferry"
            case .vesselTanker:          return "drop.fill"
            case .vesselRoRo:            return "car.fill"
            case .vesselLNG:             return "flame.fill"
            case .vesselReeferContainer: return "snowflake"
            case .vesselISOTank:         return "drop.circle.fill"
            }
        }

        var vertical: String {
            switch self {
            case .railTOFC, .railCOFC, .railIntermodal,
                 .railTankGas, .railTankLiquid,
                 .railBoxcar, .railReeferBoxcar,
                 .railHopper, .railCenterbeam, .railGondola,
                 .railAutoRack, .railFlatcar:
                return "rail"
            case .vesselContainer, .vesselBulk, .vesselTanker,
                 .vesselRoRo, .vesselLNG,
                 .vesselReeferContainer, .vesselISOTank:
                return "vessel"
            default:
                return "truck"
            }
        }

        /// Mode-compatibility filter for the Step 2 chip strip. Rail
        /// equipment only surfaces when the shipper picked Rail mode,
        /// vessel equipment only when Vessel. Barge maps to the
        /// vessel surface for now (purpose-built barge animations
        /// not yet on disk — vesselBulk/vesselTanker render the
        /// closest equivalent for inland-waterway flows).
        ///
        /// Founder firing 2026-05-18: rail/vessel pickers were
        /// returning only 3 types each, forcing the wizard to
        /// auto-snap to a truck when the cargo was incompatible
        /// with the 3 surfaced rail / vessel types. Now the full
        /// SVG set ships through.
        func compatible(with mode: TransportMode) -> Bool {
            switch mode {
            case .truck:  return vertical == "truck"
            case .rail:   return vertical == "rail"
            case .vessel: return vertical == "vessel"
            case .barge:  return vertical == "vessel"
            }
        }
    }

    /// Quantity-measurement unit. The wizard surfaces a dynamic
    /// subset based on the user's equipment + cargo type — petroleum
    /// runs on barrels / gallons, grain on bushels, palletized
    /// freight on pallets, vessel containers on TEUs / metric tons.
    /// Founder ask 2026-05-07: 'lbs alone is just too basic'.
    enum MeasurementUnit: String, CaseIterable, Identifiable {
        // Mass
        case pounds        = "lbs"
        case kilograms     = "kg"
        case shortTons     = "ton"           // 2000 lb US ton
        case metricTons    = "mt"            // 1000 kg
        // Liquid volume
        case gallons       = "gal"           // US gallons
        case barrels       = "bbl"           // 42 US gallons (oil)
        case liters        = "L"
        case cubicMeters   = "m³"
        // Solid volume / count
        case bushels       = "bu"
        case pallets       = "plt"
        case cases         = "cs"
        case cartons       = "ctn"
        case rolls         = "rl"
        case bundles       = "bdl"
        case feu           = "FEU"           // 40-ft container equiv (vessel)
        case teu           = "TEU"           // 20-ft container equiv (vessel)
        case pieces        = "pcs"

        var id: String { rawValue }
        var label: String { rawValue }
        var longLabel: String {
            switch self {
            case .pounds:      return "Pounds"
            case .kilograms:   return "Kilograms"
            case .shortTons:   return "Short tons (US)"
            case .metricTons:  return "Metric tons"
            case .gallons:     return "Gallons (US)"
            case .barrels:     return "Barrels (oil)"
            case .liters:      return "Liters"
            case .cubicMeters: return "Cubic meters"
            case .bushels:     return "Bushels"
            case .pallets:     return "Pallets"
            case .cases:       return "Cases"
            case .cartons:     return "Cartons"
            case .rolls:       return "Rolls"
            case .bundles:     return "Bundles"
            case .feu:         return "FEU (40' container)"
            case .teu:         return "TEU (20' container)"
            case .pieces:      return "Pieces"
            }
        }
    }

    /// Permit type — surfaced inside the flatbed/oversized subform
    /// when the load needs DOT/state oversize/superload authorization.
    /// Mirrors the four real permit families a US oversized carrier
    /// books against state DOTs:
    ///   • `.tripPermit` — single-trip oversize/overweight, most
    ///     common, state-by-state filing
    ///   • `.annualOversize` — fleet annual oversize, repeat lanes
    ///   • `.superload` — > legal annual oversize bounds, requires
    ///     route survey + escort + utility coordination
    ///   • `.overweightOnly` — within oversize dimensions but axle/
    ///     gross weight exceeds 80k lb (e.g., 90k lb intermodal)
    ///   • `.hazmatRoute` — hazmat-routed corridor permit
    ///   • `.none` — no special permit (default)
    /// Serialized as the raw string into the `notes` field on
    /// `shippers.create` until the backend ships a structured permit
    /// type column.
    enum PermitType: String, CaseIterable, Identifiable {
        case none           = "none"
        case tripPermit     = "trip_permit"
        case annualOversize = "annual_oversize"
        case superload      = "superload"
        case overweightOnly = "overweight_only"
        case hazmatRoute    = "hazmat_route"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .none:           return "No permit"
            case .tripPermit:     return "Trip permit"
            case .annualOversize: return "Annual oversize"
            case .superload:      return "Superload"
            case .overweightOnly: return "Overweight-only"
            case .hazmatRoute:    return "Hazmat route"
            }
        }
        var systemImage: String {
            switch self {
            case .none:           return "minus.circle"
            case .tripPermit:     return "doc.text.fill"
            case .annualOversize: return "calendar.badge.clock"
            case .superload:      return "truck.box.badge.clock"
            case .overweightOnly: return "scalemass.fill"
            case .hazmatRoute:    return "exclamationmark.triangle.fill"
            }
        }
        var hint: String {
            switch self {
            case .none:           return "Within legal limits · no DOT filing"
            case .tripPermit:     return "Single trip · state-by-state filing"
            case .annualOversize: return "Annual fleet authorization · repeat lanes"
            case .superload:      return "Route survey + escort + utility coordination"
            case .overweightOnly: return "> 80k lb gross / axle exceedance"
            case .hazmatRoute:    return "Hazmat-routed corridor per 49 CFR 397"
            }
        }
    }

    /// Suggested unit options based on equipment + cargo type.
    /// First entry is the default. User can pick any value from
    /// `MeasurementUnit.allCases` via the menu — these are the
    /// short list surfaced first.
    private var suggestedUnits: [MeasurementUnit] {
        switch equipmentType {
        case .tankerHazmat, .tankerPetro:
            return [.barrels, .gallons, .pounds, .kilograms]
        case .tankerLiquid:
            return [.gallons, .liters, .barrels, .pounds]
        case .tankerGas:
            return [.gallons, .cubicMeters, .pounds, .kilograms]
        case .reefer:
            // Reefer cargo varies hugely; surface produce + protein
            // common units. Pallets is a common reefer unit.
            return [.pallets, .pounds, .kilograms, .cases]
        case .flatbed, .stepDeck, .conestoga, .oversized:
            return [.pounds, .kilograms, .shortTons, .pieces]
        case .container, .railTOFC, .railCOFC, .railIntermodal:
            return [.pounds, .kilograms, .shortTons, .metricTons]
        case .vesselContainer:
            return [.teu, .feu, .metricTons, .pounds]
        case .vesselBulk:
            return [.metricTons, .shortTons, .bushels, .pounds]
        case .vesselTanker:
            return [.barrels, .metricTons, .gallons, .liters]
        case .powerOnly:
            return [.pounds, .kilograms, .pallets]
        case .dryVan:
            switch cargoType {
            case .general:        return [.pounds, .pallets, .cases, .kilograms]
            case .refrigerated:   return [.pallets, .pounds, .kilograms]
            case .hazmat:         return [.pounds, .kilograms, .pieces]
            case .oversized:      return [.pounds, .pieces, .shortTons]
            case .liquid, .gas, .chemicals, .petroleum:
                return [.gallons, .pounds, .barrels, .liters]
            }
        // New cases from the 2026-05-18 enum expansion — sensible
        // defaults that match the equipment's cargo affordances.
        case .lowboy, .hotShot:
            return [.pounds, .kilograms, .shortTons, .pieces]
        case .railTankGas:
            return [.gallons, .cubicMeters, .pounds, .kilograms]
        case .railTankLiquid:
            return [.gallons, .liters, .barrels, .pounds]
        case .railBoxcar, .railReeferBoxcar:
            return [.pallets, .pounds, .kilograms, .cases]
        case .railHopper, .railGondola:
            return [.bushels, .shortTons, .metricTons, .pounds]
        case .railCenterbeam, .railFlatcar:
            return [.pounds, .kilograms, .shortTons, .pieces]
        case .railAutoRack:
            return [.pieces, .pounds, .kilograms]
        case .vesselRoRo:
            return [.pieces, .metricTons, .pounds]
        case .vesselLNG:
            return [.cubicMeters, .metricTons, .pounds, .kilograms]
        case .vesselReeferContainer:
            return [.teu, .feu, .pallets, .metricTons]
        case .vesselISOTank:
            return [.gallons, .liters, .metricTons, .barrels]
        }
    }

    /// Recompute the default unit when the equipment type changes —
    /// only if the user hasn't already overridden to a non-default
    /// unit.
    private func resyncWeightUnit() {
        guard let first = suggestedUnits.first else { return }
        if !suggestedUnits.contains(weightUnit) {
            weightUnit = first
        }
    }

    private let deliveryETAFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d · HH:mm"
        return f
    }()

    // MARK: - HERE Routing — distance + ETA estimation
    //
    // Founder bug 2026-05-07: "the eta calculating still doesnt work
    // mate. still missing the enhancements you made to that post a
    // load wizard." The earlier copy promised "ETA computed · Auto-set
    // from pickup + lane" but never actually fired a router request.
    //
    // Fix: when origin + destination + pickupDate are all set, hit
    // `HereRoutingClient.route(stops:profile:)` with a standard US
    // semi truck profile. Store the resulting distance (meters) +
    // duration (seconds), derive the deliveryETA from pickupDate +
    // duration, and surface real values in the delivery tile.
    @State private var routeDistanceMeters: Int? = nil
    @State private var routeDurationSeconds: Int? = nil
    @State private var routingError: String? = nil
    @State private var isRouting: Bool = false

    /// Resolved state codes from the geocode hit. Used by the ESANG
    /// rate-vs-market meter on step 3 (Pricing) — `rates.compareLaneRate`
    /// is keyed by origin/destination state codes.
    @State private var originStateCode: String? = nil
    @State private var destStateCode: String? = nil

    /// ESANG AI rate market position (above/at/below market) for the
    /// posted rate vs comparable platform + national-benchmark loads.
    /// Web parity (founder ask 2026-05-07): the wizard now shows the
    /// same gradient meter the web Post Load form uses. Wired to
    /// `rates.compareLaneRate`.
    @State private var rateComparison: RatesAPI.LaneComparison? = nil
    @State private var rateCompareError: String? = nil
    @State private var isComparingRate: Bool = false
    @State private var lastRateCompareKey: String = ""

    /// Per-load Worldscale-100 flat ($/MT) for vessel TANKER loads.
    /// A WS% rate is meaningless without the lane's WS-100 flat to
    /// convert it against — when this is empty the server returns
    /// referenceReason='needs_ws100_flat' and the meter shows the
    /// honest "enter the WS-100 flat" prompt rather than inventing a
    /// WS-100 feed. Surfaced as an input on the vessel-tanker rate
    /// subform; nil/empty everywhere else.
    @State private var worldscaleFlatText: String = ""

    /// Cached lat/lng tuple of the last query so we don't re-fire
    /// the routing call on every keystroke.
    @State private var lastRoutedKey: String = ""

    /// Computed delivery ETA = pickupDate + routeDurationSeconds.
    /// Returns nil until both values are present.
    private var computedDeliveryETA: Date? {
        guard hasPickupDate, let secs = routeDurationSeconds else { return nil }
        return pickupDate.addingTimeInterval(TimeInterval(secs))
    }

    /// Stable lower bound for the pickup `DatePicker` — the start of the
    /// current calendar day. Using `startOfDay` (rather than the moving
    /// `Date()` instant) keeps the bound constant across renders so the
    /// bound and the selected `pickupDate` can never momentarily disagree.
    ///
    /// Crash fix (2026-06-13, founder report "resume draft → freeze then
    /// crash"): a restored draft whose saved `pickupDate` was earlier than
    /// `Date()` (e.g. a draft saved on a previous day, or a date the user
    /// set then time passed) bound a value OUTSIDE the picker's `in:` range
    /// on the very first (Lane) step shown after Resume. SwiftUI's compact
    /// `DatePicker` traps when its selection falls outside its range. The
    /// hydrate pass now clamps the restored date into this range, and the
    /// picker reads the same stable bound — so the two always agree.
    private var pickupLowerBound: Date {
        Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
                .padding(.horizontal, Space.s5)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s5) {
                    stepper
                    if prefillBannerType != nil { prefillProvenanceBanner }
                    if let ack = lastSuccess {
                        successBanner(ack)
                    }
                    if case .error(let message) = store.phase {
                        errorBanner(message)
                    }
                    stepBody
                    continueOrSubmitCTA
                    Color.clear.frame(height: 96)
                }
                .padding(Space.s5)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .screenTileRoot()
        // F-ANIMATION (2026-06-14) — bespoke "Load posted" celebration on
        // top of the wizard. Push-nav surface keeps its chrome; the overlay
        // is a brand-native full-bleed cover that auto-returns to a fresh
        // Step-1 when it finishes.
        .overlay {
            if showPostedCelebration, let ack = lastSuccess {
                PostLoadPostedCelebration(
                    loadNumber: ack.loadNumber,
                    onContinue: finishCelebrationAndReset
                )
                .transition(.opacity)
                .zIndex(50)
            }
        }
        // Re-fire HERE Routing whenever the lane endpoints' lat/lng
        // change. Address-field selection populates these and bumps
        // a rebuild; we reactively trigger the route computation so
        // the delivery tile populates as soon as a valid lane exists.
        .onChange(of: originLat) { _, _ in recomputeETAIfReady() }
        .onChange(of: originLng) { _, _ in recomputeETAIfReady() }
        .onChange(of: destLat)   { _, _ in recomputeETAIfReady() }
        .onChange(of: destLng)   { _, _ in recomputeETAIfReady() }
        // Also re-fire when the typed strings settle — fall-back
        // path for users who paste / type without tapping a
        // suggestion. `recomputeETAIfReady` will geocode the typed
        // text inline.
        .onChange(of: origin)      { _, _ in recomputeETAIfReady() }
        .onChange(of: destination) { _, _ in recomputeETAIfReady() }
        .onChange(of: transportMode) { _, _ in recomputeETAIfReady() }
        // Rate compare fires when posted rate or cargo type changes —
        // independent of routing, so the meter updates without
        // re-geocoding.
        .onChange(of: rateText)  { _, _ in recomputeRateCompareIfReady() }
        .onChange(of: cargoType) { _, _ in recomputeRateCompareIfReady() }
        // Hydrate any in-progress draft on first appear (crash
        // recovery + iCloud cross-device continuity). Skip on
        // subsequent appears so navigating back to step 1 doesn't
        // wipe in-progress edits.
        .onAppear {
            if !didHydrateDraft {
                hydrateDraftIfPresent()
                didHydrateDraft = true
            }
        }
        // Cancel the pending debounced-persist work item on dismiss.
        // Navigating BACK tears down this view while a 0.7s
        // `draftPersistWork` may still be queued; letting it fire
        // would read now-stale @State and crash ("crashed when going
        // back in post load"). Mirror the `voice.cancel()` teardown
        // pattern in 053_ESangDispatchChat.
        .onDisappear { draftPersistWork?.cancel() }
        // Autosave on every meaningful field change. Collapsed into
        // a single onChange driven by `autosaveDigest` (a hash of
        // every watched value) — chaining 30+ `.onChange` modifiers
        // overwhelmed Swift's type-checker. The persist helper
        // writes to UserDefaults (local crash recovery) AND
        // NSUbiquitousKeyValueStore (iCloud KVS — cross-device).
        .onChange(of: autosaveDigest) { _, _ in scheduleDraftPersist() }
        // ERG lookup fires off a separate UN-only debouncer so
        // typing in unrelated fields doesn't trigger a re-lookup.
        .onChange(of: unNumber) { _, _ in lookupERGIfReady() }
        // One-way mirror of the host-owned regulated identity into the
        // shared attestation. The attestation is what goes on the wire, so
        // the shipper is never asked for the same field twice and the two
        // can never disagree.
        .onChange(of: cargoIdentityDigest) { _, _ in mirrorCargoIdentityIntoAttestation() }
        // Listen to remote iCloud KVS changes — when the user edits
        // the draft on another signed-in device, NSUbiquitousKVStore
        // posts a change notification; we re-hydrate so the in-flight
        // wizard reflects the remote edits.
        .onReceive(NotificationCenter.default.publisher(
            for: NSUbiquitousKeyValueStore.didChangeExternallyNotification
        )) { _ in
            hydrateDraftIfPresent()
        }
        // ERG search sheet (typeahead by name)
        .sheet(isPresented: $showErgSearchSheet) { ergSearchSheet }
        // Commodity search sheet (non-hazmat ERG-parity typeahead)
        .sheet(isPresented: $showCommoditySearchSheet) { commoditySearchSheet }
        // Templates picker (loadTemplates.list — server-backed,
        // visible on web platform too for true cross-device parity)
        .sheet(isPresented: $showTemplatePicker) { templatePickerSheet }
        // Save-as-template (loadTemplates.create)
        .sheet(isPresented: $showSaveTemplateSheet) { saveTemplateSheet }
        // Doc-router classifier — "Scan to pre-fill" (single doc).
        // Routes through documentRouter.classifyAndRoute (Gemini
        // Vision against the 60-type taxonomy) and pre-fills the
        // wizard from the extracted fields.
        .sheet(isPresented: $showDocClassifierSingle) {
            DocumentClassifierSheet(
                mode: .prefillWizard,
                callerContext: "shipper Post-Load Templates",
                onApplySingle: { doc in
                    applyClassifiedDocument(doc)
                },
                onDispatchBatch: { _ in }
            )
        }
        // Doc-router classifier — Bulk (up to 30 docs). Routes
        // through documentRouter.classifyBatch. After classification
        // we split: load-shaped docs (rate_confirmation,
        // bill_of_lading, load_tender, load_csv, run_ticket) feed
        // bulkImport.executeImport on the server-side; everything
        // else surfaces with its dispatchTarget so the user can
        // route it intentionally (COIs → certificates.upload,
        // 1099s → tax.upload, etc.).
        .sheet(isPresented: $showDocClassifierBulk) {
            DocumentClassifierSheet(
                mode: .batch,
                callerContext: "shipper Post-Load Bulk",
                onApplySingle: { _ in },
                onDispatchBatch: { docs in
                    routeBulkClassified(docs)
                }
            )
        }
    }

    // MARK: - ERG search sheet

    private var ergSearchSheet: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("ERG · Find a material")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Button { showErgSearchSheet = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                TextField("UN number or material name", text: $ergSearchQuery)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .tint(LinearGradient.diagonal)
                    .autocorrectionDisabled()
                    .onSubmit { searchERG() }
                    .onChange(of: ergSearchQuery) { _, _ in searchERG() }
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            if isSearchingERG {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7).tint(LinearGradient.diagonal)
                    Text("Searching ERG…")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.s2) {
                    ForEach(ergSearchHits) { hit in
                        Button { applyERGHit(hit) } label: {
                            ergSearchRow(hit)
                        }
                        .buttonStyle(.plain)
                    }
                    if ergSearchHits.isEmpty && !ergSearchQuery.isEmpty && !isSearchingERG {
                        Text("No ERG match for '\(ergSearchQuery)'")
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                            .padding(.top, Space.s4)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s5)
        .background(palette.bgPrimary)
    }

    @ViewBuilder
    private func ergSearchRow(_ hit: ErgAPI.SearchHit) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("UN\(hit.unNumber)")
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("Guide \(hit.guide)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                    if hit.isTIH == true {
                        Text("TIH").font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(Brand.danger))
                    }
                }
                Text(hit.name.capitalized)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                if let placardName = hit.placardName, !placardName.isEmpty {
                    Text("Response placard reference · \(placardName)")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                } else {
                    Text("ERG response reference · verify classification separately")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Commodity search sheet (non-hazmat ERG-parity typeahead)

    private var commoditySearchSheet: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("Find a commodity")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Button { showCommoditySearchSheet = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                TextField(commodityCardPlaceholder, text: $commoditySearchQuery)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .tint(LinearGradient.diagonal)
                    .autocorrectionDisabled()
                    .onSubmit { searchCommodity() }
                    .onChange(of: commoditySearchQuery) { _, _ in searchCommodity() }
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            if isSearchingCommodity {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7).tint(LinearGradient.diagonal)
                    Text("Searching commodities…")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.s2) {
                    ForEach(commoditySearchHits) { hit in
                        Button { applyCommodityHit(hit) } label: {
                            commoditySearchRow(hit)
                        }
                        .buttonStyle(.plain)
                    }
                    if commoditySearchHits.isEmpty && !commoditySearchQuery.isEmpty && !isSearchingCommodity {
                        Text("No commodity match for '\(commoditySearchQuery)'")
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                            .padding(.top, Space.s4)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s5)
        .background(palette.bgPrimary)
    }

    @ViewBuilder
    private func commoditySearchRow(_ hit: CommodityLookupAPI.CommodityHit) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let code = hit.code, !code.isEmpty {
                        Text(code)
                            .font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    if let cat = hit.category, !cat.isEmpty {
                        Text(cat)
                            .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Text(hit.name)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                Text(commodityMatchSubtitle(hit))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Templates picker sheet (loadTemplates.list)

    private var templatePickerSheet: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("Saved templates")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Button { showTemplatePicker = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
            }

            // Scan-to-pre-fill card — opens the doc-router classifier
            // in single-doc mode. Drop a Rate Confirmation / BOL /
            // Load Tender / Run Ticket and we fill the wizard from
            // the extracted fields.
            Button {
                showTemplatePicker = false
                showDocClassifierSingle = true
            } label: {
                HStack(spacing: Space.s3) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(LinearGradient.diagonal.opacity(0.18))
                        Image(systemName: "sparkles.tv.fill")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Scan to pre-fill")
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundStyle(palette.textPrimary)
                            Text("ESANG AI")
                                .font(.system(size: 8, weight: .heavy)).tracking(0.7)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(LinearGradient.diagonal))
                        }
                        Text("Drop a Rate Con, BOL, Load Tender or Run Ticket. Gemini Vision pre-fills lane, equipment, cargo, weight and rate.")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(Space.s3)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(LinearGradient.diagonal.opacity(0.45)))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                TextField("Search by name, lane, commodity", text: $templateSearchQuery)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .tint(LinearGradient.diagonal)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await loadTemplatesList() } }
                    .onChange(of: templateSearchQuery) { _, _ in
                        Task { await loadTemplatesList() }
                    }
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

            if isLoadingTemplates {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7).tint(LinearGradient.diagonal)
                    Text("Loading templates…")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.s2) {
                    ForEach(templates) { tpl in
                        Button { applyTemplate(tpl) } label: {
                            templateRow(tpl)
                        }
                        .buttonStyle(.plain)
                    }
                    if templates.isEmpty && !isLoadingTemplates {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No saved templates yet")
                                .font(EType.bodyStrong)
                                .foregroundStyle(palette.textPrimary)
                            Text("Post a load + tap 'Save as template' on the review step. Saved templates show up here AND on the web platform, same account, same shipping list.")
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, Space.s4)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s5)
        .background(palette.bgPrimary)
    }

    @ViewBuilder
    private func templateRow(_ tpl: LoadTemplatesAPI.Template) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: 36, height: 36)
                Image(systemName: tpl.isFavorite == true ? "star.fill" : "rectangle.stack.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(tpl.name)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                Text(templateLaneText(tpl))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                Text(templateMetaText(tpl))
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func templateLaneText(_ tpl: LoadTemplatesAPI.Template) -> String {
        let o = locationDisplay(tpl.origin)
        let d = locationDisplay(tpl.destination)
        if o.isEmpty && d.isEmpty { return "Lane not set" }
        return "\(o.isEmpty ? "-" : o) → \(d.isEmpty ? "-" : d)"
    }

    private func templateMetaText(_ tpl: LoadTemplatesAPI.Template) -> String {
        var bits: [String] = []
        if let eq = tpl.equipmentType, !eq.isEmpty { bits.append(eq) }
        if let cargo = tpl.cargoType, !cargo.isEmpty { bits.append(cargo) }
        if let count = tpl.useCount, count > 0 { bits.append("used \(count)×") }
        return bits.joined(separator: " · ")
    }

    private func locationDisplay(_ loc: LoadTemplatesAPI.Template.Location?) -> String {
        guard let loc else { return "" }
        let c = (loc.city ?? "").trimmingCharacters(in: .whitespaces)
        let s = (loc.state ?? "").trimmingCharacters(in: .whitespaces)
        if !c.isEmpty && !s.isEmpty { return "\(c), \(s)" }
        if !c.isEmpty { return c }
        return s
    }

    private func loadTemplatesList() async {
        isLoadingTemplates = true
        defer { isLoadingTemplates = false }
        do {
            let q = templateSearchQuery.trimmingCharacters(in: .whitespaces)
            let rows = try await EusoTripAPI.shared.loadTemplates.list(
                search: q.isEmpty ? nil : q,
                favoritesOnly: nil,
                includeArchived: nil
            )
            self.templates = rows
        } catch {
            self.templates = []
        }
    }

    /// Hydrate the wizard from a saved template. Origin / destination
    /// are reconstructed from the template's Location columns; lat/lng
    /// will fall back to geocoding via the existing
    /// `recomputeETAIfReady` path. Equipment + cargo + hazmat fields
    /// pre-populate where the template carries them.
    private func applyTemplate(_ tpl: LoadTemplatesAPI.Template) {
        if let o = tpl.origin {
            origin = locationDisplay(o)
            originLat = nil; originLng = nil
        }
        if let d = tpl.destination {
            destination = locationDisplay(d)
            destLat = nil; destLng = nil
        }
        if let raw = tpl.cargoType,
           let mapped = ShipperAPI.CargoType(rawValue: raw) {
            cargoType = mapped
        }
        if let raw = tpl.equipmentType,
           let mapped = EquipmentChoice(rawValue: raw) {
            equipmentType = mapped
        }
        if let w = tpl.weight, !w.isEmpty { weightText = w }
        if let raw = tpl.weightUnit,
           let mapped = MeasurementUnit(rawValue: raw) {
            weightUnit = mapped
        }
        if let r = tpl.rate, !r.isEmpty   { rateText = r }
        if let un = tpl.unNumber, !un.isEmpty { unNumber = un }
        if let cls = tpl.hazmatClass, !cls.isEmpty { hazmatClass = cls }
        if let desc = tpl.description, !desc.isEmpty { notes = desc }
        showTemplatePicker = false
        templateSaveAck = "Loaded · \(tpl.name)"
        // Returning to step 1 forces the user to confirm the lane
        // and lets the geocode fallback re-resolve coordinates.
        step = .lane
    }

    // MARK: - Doc-router classifier pre-fill

    /// SCANNED · UNCONFIRMED banner. Names exactly which fields a
    /// machine filled in and refuses to fade until the shipper says
    /// they have looked. Regulated fields are listed first and in the
    /// danger tone — an incorrect hazard class on a posted load is a
    /// placarding and emergency-response failure, not a typo.
    @ViewBuilder
    private var prefillProvenanceBanner: some View {
        let regulated = prefillRegulatedLabels
        let ordinary = prefillFieldLabels.filter { !regulated.contains($0) }
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(prefillAcknowledged ? palette.textSecondary : Brand.warning)
                Text(prefillAcknowledged ? "SCAN CHECKED BY YOU" : "SCANNED · UNCONFIRMED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(prefillAcknowledged ? palette.textSecondary : Brand.warning)
                Spacer(minLength: 0)
                if let t = prefillBannerType {
                    Text(t.replacingOccurrences(of: "_", with: " ").uppercased())
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            if let summary = prefillBannerSummary, !summary.isEmpty {
                Text(summary)
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if prefillFieldLabels.isEmpty {
                Text("The document was read but nothing in it matched a field on this form. Every value below is still yours.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if !regulated.isEmpty {
                    Text("REGULATED FIELDS FILLED BY THE READER")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                        .foregroundStyle(Brand.danger)
                    Text(regulated.joined(separator: " · "))
                        .font(EType.mono(.micro)).foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Check each of these against the paper before you post. A wrong hazard class or UN number posts a load that cannot be placarded or responded to correctly.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !ordinary.isEmpty {
                    Text("ALSO FILLED BY THE READER")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                        .foregroundStyle(palette.textTertiary)
                    Text(ordinary.joined(separator: " · "))
                        .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !prefillAcknowledged {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { prefillAcknowledged = true }
                } label: {
                    Text("I've checked these")
                        .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(prefillAcknowledged ? palette.borderFaint : Brand.warning.opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// Applies an `extractedFields` dictionary from
    /// `documentRouter.classifyAndRoute` onto the wizard's @State
    /// fields. Field keys come from the Gemini Vision master prompt
    /// (server-side `documentRouter.ts`) and are doc-type-specific —
    /// the keys this maps are the union across rate_confirmation /
    /// bill_of_lading / load_tender / run_ticket / load_csv. Unknown
    /// keys are ignored so future server-side additions are
    /// forward-compatible.
    private func applyClassifiedDocument(_ doc: ClassifiedDocument) {
        let fields = doc.fields
        // Every assignment below appends its own label. The banner then
        // reports what a machine actually wrote — not what it might
        // have written — so the list can never overstate the scan.
        var wrote: [String] = []
        var wroteRegulated: [String] = []

        // — Lane —
        if let originCity = fields["originCity"] ?? fields["pickupCity"] ?? fields["shipperCity"] ?? fields["origin"] {
            let state = fields["originState"] ?? fields["pickupState"] ?? fields["shipperState"]
            origin = [originCity, state].compactMap { $0?.isEmpty == false ? $0 : nil }
                        .joined(separator: ", ")
            originLat = nil; originLng = nil
            wrote.append("Origin")
        }
        if let destCity = fields["destinationCity"] ?? fields["deliveryCity"] ?? fields["consigneeCity"] ?? fields["destination"] {
            let state = fields["destinationState"] ?? fields["deliveryState"] ?? fields["consigneeState"]
            destination = [destCity, state].compactMap { $0?.isEmpty == false ? $0 : nil }
                            .joined(separator: ", ")
            destLat = nil; destLng = nil
            wrote.append("Destination")
        }

        // — Equipment —
        if let rawEq = fields["equipmentType"] ?? fields["equipment"] ?? fields["trailerType"],
           let mapped = EquipmentChoice(rawValue: rawEq.lowercased().replacingOccurrences(of: " ", with: "_"))
                        ?? EquipmentChoice.allCases.first(where: { $0.rawValue == rawEq.lowercased() }) {
            equipmentType = mapped
            wrote.append("Equipment")
        }

        // — Cargo type —
        if let rawCargo = fields["cargoType"] ?? fields["commodityType"] ?? fields["commodity"],
           let mapped = ShipperAPI.CargoType(rawValue: rawCargo.lowercased()) {
            cargoType = mapped
            wrote.append("Cargo type")
        }

        // — Weight —
        if let w = fields["weight"] ?? fields["totalWeight"] ?? fields["weightLbs"], !w.isEmpty {
            weightText = w
            wroteRegulated.append("Weight")
        }
        if let unit = fields["weightUnit"]?.lowercased() {
            switch unit {
            case "lb", "lbs", "pound", "pounds": weightUnit = .pounds
            case "kg", "kgs", "kilogram", "kilograms": weightUnit = .kilograms
            case "mt", "metric_ton", "metric_tons", "tonne", "tonnes": weightUnit = .metricTons
            default: break
            }
            if !wroteRegulated.contains("Weight") { wroteRegulated.append("Weight unit") }
        }

        // — Rate —
        if let r = fields["rate"] ?? fields["totalRate"] ?? fields["lineHaul"] ?? fields["amount"], !r.isEmpty {
            // Strip $ + commas — wizard expects a numeric string.
            rateText = r.replacingOccurrences(of: "$", with: "")
                        .replacingOccurrences(of: ",", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
            wrote.append("Rate")
        }

        // — Pickup date —
        if let raw = fields["pickupDate"] ?? fields["readyDate"] ?? fields["shipDate"], !raw.isEmpty,
           let parsed = ISO8601DateFormatter().date(from: raw)
                        ?? DateFormatter.iso_yMd.date(from: raw)
                        ?? DateFormatter.iso_mDy.date(from: raw) {
            // Clamp into the pickup picker's range — a scanned/template
            // ready-date in the past would otherwise bind out-of-range and
            // trap the compact DatePicker (same crash class as the draft
            // resume path).
            pickupDate = max(parsed, pickupLowerBound)
            hasPickupDate = true
            wrote.append("Pickup date")
        }

        // — Hazmat (if doc carried it) —
        // 49 CFR identity. Written as a PROPOSAL and named in the
        // banner; the shipper confirms before this load can post.
        if let un = fields["unNumber"] ?? fields["UN"], !un.isEmpty {
            unNumber = un
            wroteRegulated.append("UN number")
        }
        if let cls = fields["hazmatClass"] ?? fields["hazardClass"], !cls.isEmpty {
            hazmatClass = cls
            wroteRegulated.append("Hazard class")
        }
        if let pg = fields["packingGroup"], !pg.isEmpty {
            packingGroup = pg
            wroteRegulated.append("Packing group")
        }
        if let psn = fields["properShippingName"] ?? fields["shippingName"], !psn.isEmpty {
            properShippingName = psn
            wroteRegulated.append("Proper shipping name")
        }

        // — Notes / description —
        if let desc = fields["description"] ?? fields["commodityDescription"] ?? fields["specialInstructions"], !desc.isEmpty {
            notes = notes.isEmpty ? desc : notes + "\n" + desc
            wrote.append("Notes")
        }

        prefillBannerType = doc.classifiedType
        prefillBannerSummary = doc.summary
        prefillRegulatedLabels = wroteRegulated
        prefillFieldLabels = wroteRegulated + wrote
        // A fresh scan is unconfirmed again, no matter what the
        // shipper acknowledged about the previous one.
        prefillAcknowledged = false
        step = .lane
    }

    /// Routes a batch from `documentRouter.classifyBatch`. Load-shaped
    /// docs (rate_confirmation, bill_of_lading, load_tender,
    /// run_ticket) → if exactly one, apply it as a pre-fill; if
    /// multiple, hand off the first as pre-fill and surface the rest
    /// via NotificationCenter so the host shell can stack them as
    /// drafts. Everything else → route to its `dispatchTarget`
    /// (which is the canonical tRPC procedure for that doc type).
    private func routeBulkClassified(_ docs: [ClassifiedDocument]) {
        guard !docs.isEmpty else { return }
        let loadShaped: Set<String> = [
            "rate_confirmation",
            "bill_of_lading",
            "load_tender",
            "run_ticket",
            "load_csv",
        ]
        let loads = docs.filter { loadShaped.contains($0.classifiedType) }
        let nonLoads = docs.filter { !loadShaped.contains($0.classifiedType) }

        if let first = loads.first {
            applyClassifiedDocument(first)
        }

        // Hand the rest to the shell — it can stack them on the
        // "Loads" tab as draft posts. Listener lives in
        // 200_ShipperHome which routes to the drafts queue.
        let payload: [[String: Any]] = docs.dropFirst(loads.isEmpty ? 0 : 1).map { d in
            [
                "classifiedType": d.classifiedType,
                "dispatchTarget": d.dispatchTarget ?? "",
                "confidence": d.confidence,
                "summary": d.summary,
            ]
        }
        if !payload.isEmpty {
            NotificationCenter.default.post(
                name: .eusoShipperBulkClassifiedRouted,
                object: nil,
                userInfo: ["docs": payload]
            )
        }

        bulkBannerCount = docs.count
        bulkBannerTopType = (loads.first?.classifiedType) ?? (nonLoads.first?.classifiedType)
        if !loads.isEmpty {
            templateSaveAck = "Pre-filled from \(loads.count) load doc\(loads.count == 1 ? "" : "s") · \(nonLoads.count) other doc\(nonLoads.count == 1 ? "" : "s") queued"
        } else {
            templateSaveAck = "Routed \(nonLoads.count) doc\(nonLoads.count == 1 ? "" : "s")"
        }
    }

    // MARK: - Save-as-template sheet (loadTemplates.create)

    private var saveTemplateSheet: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack {
                Text("Save as template")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Button { showSaveTemplateSheet = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
            Text("Saves to your account so you can quick-post the same lane next time. Templates sync across iOS and the web platform, same shipper, same list.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("TEMPLATE NAME")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                TextField("Houston → Austin · Tanker · Hazmat",
                          text: $templateNameDraft)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .tint(LinearGradient.diagonal)
                    .padding(Space.s3)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            if let err = templateSaveError {
                Text(err)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                Task { await saveAsTemplate() }
            } label: {
                HStack(spacing: 8) {
                    if savingTemplate {
                        ProgressView().scaleEffect(0.7).tint(.white)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 12, weight: .heavy))
                    }
                    Text(savingTemplate ? "Saving…" : "Save template")
                        .font(.system(size: 14, weight: .heavy))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(savingTemplate || templateNameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            Spacer(minLength: 0)
        }
        .padding(Space.s5)
        .background(palette.bgPrimary)
    }

    private func saveAsTemplate() async {
        let name = templateNameDraft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        savingTemplate = true
        templateSaveError = nil
        defer { savingTemplate = false }
        do {
            let originLoc = LoadTemplatesAPI.TemplateLocation(
                city: cityFromText(origin, countryCode: originCountryCode),
                state: stateFromText(origin, countryCode: originCountryCode),
                zipCode: nil,
                address: origin.trimmingCharacters(in: .whitespaces),
                facilityName: nil,
                countryCode: originCountryCode.uppercased(),
                lat: originLat,
                lng: originLng
            )
            let destLoc = LoadTemplatesAPI.TemplateLocation(
                city: cityFromText(destination, countryCode: destinationCountryCode),
                state: stateFromText(destination, countryCode: destinationCountryCode),
                zipCode: nil,
                address: destination.trimmingCharacters(in: .whitespaces),
                facilityName: nil,
                countryCode: destinationCountryCode.uppercased(),
                lat: destLat,
                lng: destLng
            )
            // Build description with the equipment + subform spec so
            // the catalyst's view of the template carries the full
            // requirements at materialization time.
            let desc = composeSubmissionNotes()
            let templateQuantity = parseDouble(weightText)
            let isMassUnit = [MeasurementUnit.pounds, .kilograms, .shortTons, .metricTons]
                .contains(weightUnit)
            let templatePermit: String? = permitType == .none ? nil : permitType.rawValue
            let input = LoadTemplatesAPI.CreateInput(
                name: name,
                description: desc.isEmpty ? nil : desc,
                origin: originLoc,
                destination: destLoc,
                distance: routeDistanceMeters.map { Double($0) / 1609.34 },
                commodity: properShippingName.isEmpty ? nil : properShippingName,
                cargoType: cargoType.rawValue,
                equipmentType: equipmentType.rawValue,
                weight: isMassUnit && templateQuantity != nil ? weightText : nil,
                weightUnit: isMassUnit && templateQuantity != nil ? weightUnit.rawValue : nil,
                rate: parseDouble(rateText),
                rateType: rateText.isEmpty ? nil : "flat",
                preferredDays: nil,
                preferredPickupTime: nil,
                specialInstructions: notes.isEmpty ? nil : notes,
                category: commodityMatch?.category ?? cargoType.rawValue,
                physicalState: portIntelligencePhysicalState,
                trailerType: equipmentType.rawValue,
                quantity: templateQuantity == nil ? nil : weightText,
                quantityUnit: templateQuantity == nil ? nil : weightUnit.rawValue,
                hazmatClass: nonBlank(hazmatClass),
                unNumber: nonBlank(unNumber),
                packingGroup: nonBlank(packingGroup),
                properShippingName: nonBlank(properShippingName),
                transportMode: transportMode.rawValue,
                originCountry: originCountryCode.uppercased(),
                destinationCountry: destinationCountryCode.uppercased(),
                permitType: templatePermit
            )
            let ack = try await EusoTripAPI.shared.loadTemplates.create(input)
            showSaveTemplateSheet = false
            templateSaveAck = "Saved · \(ack.name ?? name)"
        } catch {
            templateSaveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func localityParts(_ raw: String, countryCode: String) -> (city: String, state: String) {
        var parts = raw.split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let country = countryCode.uppercased()
        var countryLabels = Set([country.lowercased()])
        if let localized = Locale.current.localizedString(forRegionCode: country)?.lowercased() {
            countryLabels.insert(localized)
        }
        if country == "US" {
            countryLabels.formUnion(["usa", "united states", "united states of america"])
        }
        if let last = parts.last?.lowercased(), countryLabels.contains(last) {
            parts.removeLast()
        }
        guard let statePart = parts.last else { return ("", "") }
        let state = statePart.split(separator: " ").first.map(String.init) ?? statePart
        let city = parts.count >= 2 ? parts[parts.count - 2] : parts[0]
        return (city, state)
    }

    private func cityFromText(_ raw: String, countryCode: String) -> String {
        localityParts(raw, countryCode: countryCode).city
    }

    private func stateFromText(_ raw: String, countryCode: String) -> String {
        localityParts(raw, countryCode: countryCode).state
    }

    // MARK: - Draft autosave + iCloud KVS continuity

    /// JSON-encodable snapshot of every field the wizard captures.
    /// Bumped to `v: 2` when adding ERG/equipment fields beyond the
    /// original lane/cargo/rate set so older drafts in storage decode
    /// gracefully (missing fields become defaults).
    private struct PostLoadDraftSnapshot: Codable, Sendable {
        var v: Int = 2
        var origin: String = ""
        var destination: String = ""
        var originLat: Double? = nil
        var originLng: Double? = nil
        var destLat: Double? = nil
        var destLng: Double? = nil
        var originCountryCode: String? = nil
        var destinationCountryCode: String? = nil
        var cargoTypeRaw: String = "general"
        var equipmentTypeRaw: String = "dry_van"
        var hasPickupDate: Bool = false
        var pickupDateUnix: Double = 0
        var weightText: String = ""
        var rateText: String = ""
        var notes: String = ""
        var unNumber: String = ""
        var hazmatClass: String = ""
        var packingGroup: String = ""
        var properShippingName: String = ""
        var tankerHoseSpec: String = ""
        var tankerFitting: String = ""
        var reeferTempLowText: String = ""
        var reeferTempHighText: String = ""
        var preCoolRequired: Bool = false
        var continuousMode: Bool = true
        var flatbedStraps: Bool = false
        var flatbedTarps: Bool = false
        var flatbedChains: Bool = false
        var flatbedEdgeProtectors: Bool = false
        var oversizeLengthText: String = ""
        var oversizeWidthText: String = ""
        var oversizeHeightText: String = ""
        var oversizePermits: Bool = false
        var permitTypeRaw: String = "none"
        var weightUnitRaw: String = "lbs"
        var savedAt: Double = 0
        // v3 (2026-05-23) — persist transportMode so restoring an
        // autosaved vessel draft doesn't render with default truck
        // mode + vessel equipment (founder bug: VESSEL ghost-state
        // after restore). Older drafts without this field decode to
        // the default value and the post-hydrate equipment-compat
        // check below snaps equipment to a mode-coherent option.
        var transportModeRaw: String = "truck"
    }

    /// Single hash of every autosaved field. Drives one `.onChange`
    /// call — chaining 30+ `.onChange` modifiers tripped Swift's
    /// type-checker timeout. Built imperatively so the type-checker
    /// has nothing to infer beyond `String + String`.
    private var autosaveDigest: String {
        var s = ""
        s += origin; s += "|"
        s += destination; s += "|"
        s += originLat.map { String($0) } ?? ""; s += "|"
        s += originLng.map { String($0) } ?? ""; s += "|"
        s += destLat.map { String($0) } ?? ""; s += "|"
        s += destLng.map { String($0) } ?? ""; s += "|"
        s += originCountryCode; s += "|"
        s += destinationCountryCode; s += "|"
        s += cargoType.rawValue; s += "|"
        s += equipmentType.rawValue; s += "|"
        s += String(hasPickupDate); s += "|"
        s += String(Int(pickupDate.timeIntervalSince1970)); s += "|"
        s += weightText; s += "|"
        s += rateText; s += "|"
        s += notes; s += "|"
        s += unNumber; s += "|"
        s += hazmatClass; s += "|"
        s += packingGroup; s += "|"
        s += properShippingName; s += "|"
        s += tankerHoseSpec; s += "|"
        s += tankerFitting; s += "|"
        s += reeferTempLowText; s += "|"
        s += reeferTempHighText; s += "|"
        s += String(preCoolRequired); s += "|"
        s += String(continuousMode); s += "|"
        s += String(flatbedStraps); s += "|"
        s += String(flatbedTarps); s += "|"
        s += String(flatbedChains); s += "|"
        s += String(flatbedEdgeProtectors); s += "|"
        s += oversizeLengthText; s += "|"
        s += oversizeWidthText; s += "|"
        s += oversizeHeightText; s += "|"
        s += String(oversizePermits); s += "|"
        s += permitType.rawValue; s += "|"
        s += weightUnit.rawValue
        return s
    }

    /// Per-user draft key — guards against draft cross-contamination
    /// when multiple accounts share a device. Falls back to a shared
    /// key when no userId is signed in (rare; pre-auth state).
    private var draftStorageKey: String {
        let uid = session.user?.id ?? "anon"
        return "shipper.postLoadDraft.\(uid)"
    }

    /// Debounced autosave. The autosave digest changes on every keystroke;
    /// persisting on each one encoded JSON to UserDefaults AND fired
    /// `NSUbiquitousKeyValueStore.synchronize()` on the MAIN THREAD per
    /// character — per-keystroke iCloud I/O that can hang the post-load
    /// screen ("posting a load froze and crashed" — April, build 712).
    /// Coalesce to a single write ~0.7s after typing settles.
    @State private var draftPersistWork: DispatchWorkItem? = nil
    private func scheduleDraftPersist() {
        draftPersistWork?.cancel()
        let work = DispatchWorkItem { persistDraft() }
        draftPersistWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private func persistDraft() {
        guard didHydrateDraft else { return }   // skip on first hydrate pass
        let snap = PostLoadDraftSnapshot(
            v: 2,
            origin: origin,
            destination: destination,
            originLat: originLat, originLng: originLng,
            destLat: destLat, destLng: destLng,
            originCountryCode: originCountryCode,
            destinationCountryCode: destinationCountryCode,
            cargoTypeRaw: cargoType.rawValue,
            equipmentTypeRaw: equipmentType.rawValue,
            hasPickupDate: hasPickupDate,
            pickupDateUnix: pickupDate.timeIntervalSince1970,
            weightText: weightText,
            rateText: rateText,
            notes: notes,
            unNumber: unNumber,
            hazmatClass: hazmatClass,
            packingGroup: packingGroup,
            properShippingName: properShippingName,
            tankerHoseSpec: tankerHoseSpec,
            tankerFitting: tankerFitting,
            reeferTempLowText: reeferTempLowText,
            reeferTempHighText: reeferTempHighText,
            preCoolRequired: preCoolRequired,
            continuousMode: continuousMode,
            flatbedStraps: flatbedStraps,
            flatbedTarps: flatbedTarps,
            flatbedChains: flatbedChains,
            flatbedEdgeProtectors: flatbedEdgeProtectors,
            oversizeLengthText: oversizeLengthText,
            oversizeWidthText: oversizeWidthText,
            oversizeHeightText: oversizeHeightText,
            oversizePermits: oversizePermits,
            permitTypeRaw: permitType.rawValue,
            weightUnitRaw: weightUnit.rawValue,
            savedAt: Date().timeIntervalSince1970,
            transportModeRaw: transportMode.rawValue
        )
        // The snapshot was built on the main actor above because it reads
        // SwiftUI @State. Everything below — JSON encode, UserDefaults, and
        // (critically) the iCloud KVS .synchronize() — must NOT run on the
        // main thread; per-keystroke KVS sync on main froze the post-load
        // screen ("posting a load froze and crashed" — April, build 712).
        // PostLoadDraftSnapshot is explicitly Sendable so Swift concurrency
        // can verify that the value crossing this queue boundary is safe.
        let key = draftStorageKey
        DispatchQueue.global(qos: .utility).async {
            guard let data = try? JSONEncoder().encode(snap) else { return }
            UserDefaults.standard.set(data, forKey: key)
            // iCloud KVS — synchronous in-memory write; .synchronize()
            // schedules upload. Cross-device propagation handled by
            // Apple's iCloud daemon.
            NSUbiquitousKeyValueStore.default.set(data, forKey: key)
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    private func hydrateDraftIfPresent() {
        // Prefer iCloud copy when present (most-recently-edited
        // device wins); fall back to local UserDefaults.
        let cloud = NSUbiquitousKeyValueStore.default.data(forKey: draftStorageKey)
        let local = UserDefaults.standard.data(forKey: draftStorageKey)
        let chosen: Data? = {
            switch (cloud, local) {
            case (let c?, let l?):
                let cs = (try? JSONDecoder().decode(PostLoadDraftSnapshot.self, from: c))?.savedAt ?? 0
                let ls = (try? JSONDecoder().decode(PostLoadDraftSnapshot.self, from: l))?.savedAt ?? 0
                return cs >= ls ? c : l
            case (let c?, nil): return c
            case (nil, let l?): return l
            default: return nil
            }
        }()
        guard let data = chosen,
              let snap = try? JSONDecoder().decode(PostLoadDraftSnapshot.self, from: data) else {
            return
        }
        origin = snap.origin
        destination = snap.destination
        originLat = snap.originLat; originLng = snap.originLng
        destLat = snap.destLat; destLng = snap.destLng
        originCountryCode = snap.originCountryCode ?? "US"
        destinationCountryCode = snap.destinationCountryCode ?? "US"
        cargoType = ShipperAPI.CargoType(rawValue: snap.cargoTypeRaw) ?? .general
        equipmentType = EquipmentChoice(rawValue: snap.equipmentTypeRaw) ?? .dryVan
        hasPickupDate = snap.hasPickupDate
        if snap.pickupDateUnix > 0 {
            // Clamp the restored date into the pickup picker's range. A
            // draft saved on a previous day (or with a pickup date the user
            // set then let lapse) decodes to a `pickupDate` earlier than the
            // `DatePicker`'s lower bound; binding an out-of-range selection
            // into the compact picker on the first (Lane) step shown after
            // Resume froze then crashed the app (founder report 2026-06-13).
            // `max(restored, pickupLowerBound)` keeps a still-valid future
            // date intact and snaps a lapsed one forward to today.
            let restored = Date(timeIntervalSince1970: snap.pickupDateUnix)
            pickupDate = max(restored, pickupLowerBound)
        }
        weightText = snap.weightText
        rateText = snap.rateText
        notes = snap.notes
        unNumber = snap.unNumber
        hazmatClass = snap.hazmatClass
        packingGroup = snap.packingGroup
        properShippingName = snap.properShippingName
        tankerHoseSpec = snap.tankerHoseSpec
        tankerFitting = snap.tankerFitting
        reeferTempLowText = snap.reeferTempLowText
        reeferTempHighText = snap.reeferTempHighText
        preCoolRequired = snap.preCoolRequired
        continuousMode = snap.continuousMode
        flatbedStraps = snap.flatbedStraps
        flatbedTarps = snap.flatbedTarps
        flatbedChains = snap.flatbedChains
        flatbedEdgeProtectors = snap.flatbedEdgeProtectors
        oversizeLengthText = snap.oversizeLengthText
        oversizeWidthText = snap.oversizeWidthText
        oversizeHeightText = snap.oversizeHeightText
        oversizePermits = snap.oversizePermits
        if let pt = PermitType(rawValue: snap.permitTypeRaw) {
            permitType = pt
        }
        if let unit = MeasurementUnit(rawValue: snap.weightUnitRaw) {
            weightUnit = unit
        }
        // Restore transport mode (v3+). Falls back to .truck when the
        // draft predates the field.
        if let restoredMode = TransportMode(rawValue: snap.transportModeRaw) {
            transportMode = restoredMode
        }
        // Post-hydrate safety net — if the restored equipmentType is
        // not mode-compatible (e.g. v1/v2 draft with vesselBulk +
        // default truck mode), snap to the mode's canonical default.
        // Same logic as autoSnapEquipmentForMode but executed
        // synchronously so the first render is already consistent.
        if !equipmentType.compatible(with: transportMode) {
            let snapped = cargoType.defaultEquipment(currentEquipment: equipmentType, mode: transportMode)
                ?? cargoType.defaultEquipmentFallback(mode: transportMode)
            equipmentType = snapped
        }
    }

    private func clearDraft() {
        UserDefaults.standard.removeObject(forKey: draftStorageKey)
        NSUbiquitousKeyValueStore.default.removeObject(forKey: draftStorageKey)
    }

    // MARK: - TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ SHIPPER · POST A LOAD · STEP \(step.rawValue) / \(PostLoadStep.allCases.count)")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(autosaveLine)
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Button(action: backTapped) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Text("Post a load")
                    .font(EType.display)
                    .foregroundStyle(palette.textPrimary)
                Spacer()

                // Templates + Bulk upload only surface on step 1.
                // Hydrating templates mid-wizard would clobber
                // unsaved entries; bulk upload is a separate flow.
                if step == .lane {
                    Button {
                        showTemplatePicker = true
                        Task { await loadTemplatesList() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.stack")
                                .font(.system(size: 11, weight: .heavy))
                            Text("Templates")
                                .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                        }
                        .foregroundStyle(LinearGradient.diagonal)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .overlay(Capsule().strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open saved load templates")
                    // Bulk upload — up to 30 docs in one sheet.
                    // Routes through `documentRouter.classifyBatch`
                    // (Gemini Vision against the 60-type taxonomy)
                    // and splits results: load-shaped docs into
                    // bulkImport.executeImport, everything else
                    // into the type-appropriate dispatch target
                    // (COIs, 1099s, agreements, EIN letters, etc.).
                    Button {
                        showDocClassifierBulk = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up.on.square")
                                .font(.system(size: 11, weight: .heavy))
                            Text("Bulk")
                                .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                        }
                        .foregroundStyle(LinearGradient.diagonal)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .overlay(Capsule().strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open bulk upload - CSV / XLS / PDF")
                }

                Button(action: closeTapped) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel and discard draft")
            }
            .padding(.top, Space.s2)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    private var autosaveLine: String {
        switch store.phase {
        case .submitting: return "POSTING…"
        case .success:    return "POSTED"
        case .error:      return "DRAFT · ERROR"
        case .idle:       return "DRAFT · AUTOSAVED"
        }
    }

    private func backTapped() {
        if let p = step.prev {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) { step = p }
        } else {
            NotificationCenter.default.post(name: .eusoShipperPostLoadDismiss, object: nil)
        }
    }

    private func closeTapped() {
        NotificationCenter.default.post(name: .eusoShipperPostLoadDismiss, object: nil)
    }

    // MARK: - Stepper

    private var stepper: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(PostLoadStep.allCases) { s in
                    stepDot(for: s)
                    if s != PostLoadStep.allCases.last {
                        Rectangle()
                            .fill(s.rawValue < step.rawValue
                                  ? AnyShapeStyle(LinearGradient.primary)
                                  : AnyShapeStyle(palette.textTertiary.opacity(0.20)))
                            .frame(height: 2)
                    }
                }
            }
            HStack(spacing: 0) {
                ForEach(PostLoadStep.allCases) { s in
                    Text(s.label)
                        .font(EType.micro).tracking(0.5)
                        .foregroundStyle(s == step
                                         ? AnyShapeStyle(palette.textPrimary)
                                         : AnyShapeStyle(palette.textTertiary))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, Space.s2)
    }

    private func stepDot(for s: PostLoadStep) -> some View {
        let isActive = (s == step)
        let isComplete = (s.rawValue < step.rawValue)
        return ZStack {
            Circle()
                .fill((isActive || isComplete)
                      ? AnyShapeStyle(LinearGradient.primary)
                      : AnyShapeStyle(palette.bgCard))
                .overlay(Circle().strokeBorder(palette.borderFaint))
                .frame(width: 28, height: 28)
            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
            } else {
                Text("\(s.rawValue)")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(isActive ? .white : palette.textTertiary)
            }
        }
        .accessibilityLabel("Step \(s.rawValue) of \(PostLoadStep.allCases.count)" +
                            (isActive ? ", current" : isComplete ? ", complete" : ""))
    }

    // MARK: - Step body switch

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .lane:      laneStepBody
        case .equipment: equipmentStepBody
        case .pricing:   pricingStepBody
        case .review:    reviewStepBody
        }
    }

    // MARK: - Step 1: LANE

    @ViewBuilder
    private var laneStepBody: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            // Pre-fill / template / bulk-classify confirmation —
            // surfaces immediately after Templates or Bulk lands on
            // the lane step so the user sees what changed.
            if let toast = templateSaveAck {
                templateAckBanner(toast)
            }
            laneSection
            routeMetaPill
            modePickerSection      // 2026-05-17 — Google-Maps-style picker
            scheduleSection
        }
    }

    /// Multi-modal transport-mode picker. Replaces the implicit
    /// truck-only assumption with an honest 4-mode row (truck / rail /
    /// vessel / barge). Selection cascades to Step 2's equipment chip
    /// filter — picking Rail surfaces rail equipment chips, Vessel
    /// surfaces vessel chips. Founder firing 2026-05-17: "look at the
    /// timing for each accessible transportation method... in our case
    /// it would embody the vessel, truck, rail."
    @ViewBuilder
    private var modePickerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox.and.arrow.backward")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("MODE")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text(transportMode.nativeRateUnit)
                    .font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 6) {
                ForEach(TransportMode.allCases) { mode in
                    modeRow(mode)
                }
            }
        }
    }

    @ViewBuilder
    private func modeRow(_ mode: TransportMode) -> some View {
        let selected = transportMode == mode
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                transportMode = mode
                autoSnapEquipmentForMode(mode)
            }
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(selected ? AnyShapeStyle(LinearGradient.diagonal)
                                   : AnyShapeStyle(Color.clear))
                    .frame(width: 3, height: 28)
                Image(systemName: mode.sfSymbol)
                    .font(.system(size: 16, weight: .heavy))
                    .frame(width: 24)
                    .foregroundStyle(palette.textPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.displayName.uppercased())
                        .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textPrimary)
                    Text(modeSubtitle(mode))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                if selected {
                    Text("SELECTED")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(LinearGradient.diagonal))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                selected ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.12))
                         : AnyShapeStyle(palette.bgCard.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        selected ? Brand.blue.opacity(0.55) : palette.borderFaint,
                        lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
    }

    private func modeSubtitle(_ mode: TransportMode) -> String {
        switch mode {
        case .truck:  return "Door-to-door · 1–3 days · highest cost/ton"
        case .rail:   return "Carload + intermodal · 3–7 days · ¼ of truck cost"
        case .vessel: return "Port-to-port · 5–40 days · cheapest per ton-mile"
        case .barge:  return "Inland waterway · 5–14 days · lowest $/ton bulk"
        }
    }

    /// Snap equipment to a mode-compatible default when the user picks
    /// a new transport mode. Truck stays on dryVan; rail → railTOFC;
    /// vessel → vesselContainer; barge falls back to truck for the
    /// equipment list (no dedicated barge equipment in EquipmentChoice
    /// yet — that's a follow-up ship).
    private func autoSnapEquipmentForMode(_ mode: TransportMode) {
        // Skip if current equipment is already mode-compatible.
        if equipmentType.compatible(with: mode) { return }
        // Otherwise pick a (cargo × mode)-coherent equipment from the
        // canonical mapping table so a Hazmat + Rail flip lands on a
        // tank car, not a generic railTOFC. Falls back to the mode's
        // first canonical equipment when the cargo type has no
        // mode-specific snap (general / any cargo).
        let proposed = cargoType.defaultEquipment(currentEquipment: equipmentType, mode: mode)
            ?? cargoType.defaultEquipmentFallback(mode: mode)
        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
            equipmentType = proposed
        }
    }

    private var laneSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LANE")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            // Swap-arrows is vertically centered so it sits at the
            // connector dot row — between the Origin clear-X and the
            // Destination clear-X (each HereAddressField renders its
            // own xmark.circle.fill). Anchoring it .topTrailing would
            // overlap the Origin X.
            ZStack(alignment: .trailing) {
                VStack(alignment: .leading, spacing: 0) {
                    laneField(label: "ORIGIN",
                              text: $origin,
                              lat: $originLat,
                              lng: $originLng,
                              countryCode: $originCountryCode,
                              placeholder: "City, ST or lat,lng · e.g. Houston, TX")
                    laneConnector
                    laneField(label: "DESTINATION",
                              text: $destination,
                              lat: $destLat,
                              lng: $destLng,
                              countryCode: $destinationCountryCode,
                              placeholder: "City, ST or lat,lng · e.g. Dallas, TX")
                }
                .padding(Space.s4)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                            .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

                Button(action: swapEndpoints) {
                    swapButton
                }
                .buttonStyle(.plain)
                .padding(.trailing, Space.s4)
                .accessibilityLabel("Swap origin and destination")
            }
        }
    }

    /// Lane row — origin or destination — uses `HereAddressField` for
    /// HERE-Geocoding-backed autocomplete + raw "lat,lng" paste
    /// support. Founder report 2026-05-05: the prior plain
    /// `TextField` produced ZERO autocomplete suggestions (only iOS
    /// keyboard's own predictive bar showed); now real HERE place
    /// suggestions appear inline.
    private func laneField(
        label: String,
        text: Binding<String>,
        lat: Binding<Double?>,
        lng: Binding<Double?>,
        countryCode: Binding<String>,
        placeholder: String
    ) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle()
                    .stroke(LinearGradient.primary, lineWidth: 2)
                    .frame(width: 14, height: 14)
                Circle()
                    .fill(LinearGradient.primary)
                    .frame(width: 5, height: 5)
            }
            .padding(.top, 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                HereAddressField(
                    text: text,
                    lat: lat,
                    lng: lng,
                    placeholder: placeholder,
                    country: hereCountryFilter(countryCode.wrappedValue)
                )
                .disabled(isSubmitting)
                Picker("Country", selection: countryCode) {
                    ForEach(Self.postLoadCountries) { country in
                        Text("\(country.code) · \(country.name)").tag(country.code)
                    }
                }
                .pickerStyle(.menu)
                .font(EType.caption)
                .tint(palette.textSecondary)
                .disabled(isSubmitting)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var laneConnector: some View {
        Rectangle()
            .fill(LinearGradient.primary)
            .frame(width: 2, height: 24)
            .mask(
                VStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { _ in
                        Rectangle().frame(width: 2, height: 2)
                    }
                }
            )
            .padding(.leading, 6)
            .padding(.vertical, 4)
    }

    private var swapButton: some View {
        ZStack {
            Circle().fill(palette.bgCard).frame(width: 32, height: 32)
            Circle().strokeBorder(palette.borderFaint).frame(width: 32, height: 32)
            VStack(spacing: 2) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .heavy))
                Image(systemName: "arrow.left")
                    .font(.system(size: 9, weight: .heavy))
            }
            .foregroundStyle(palette.textPrimary)
        }
    }

    private func swapEndpoints() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
            let previousOrigin = origin
            let previousOriginLat = originLat
            let previousOriginLng = originLng
            let previousOriginState = originStateCode
            let previousOriginCountry = originCountryCode
            origin = destination
            originLat = destLat
            originLng = destLng
            originStateCode = destStateCode
            originCountryCode = destinationCountryCode
            destination = previousOrigin
            destLat = previousOriginLat
            destLng = previousOriginLng
            destStateCode = previousOriginState
            destinationCountryCode = previousOriginCountry
        }
    }

    private func hereCountryFilter(_ alpha2: String) -> String? {
        switch alpha2.uppercased() {
        case "US": return "USA"
        case "CA": return "CAN"
        case "MX": return "MEX"
        default: return nil
        }
    }

    private var routeMetaPill: some View {
        // When routing is healthy / pending, the pill is a single-line
        // status. When HERE rejects with a parse error, we expand to
        // multi-line + smaller font so the founder can READ the full
        // server response (founder bug 2026-05-17: three rounds of
        // guessing failed because the pill truncated HERE's `cause`
        // mid-sentence; only "Malformed request · Error while parsin…"
        // was visible).
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: routingError != nil
                  ? "exclamationmark.triangle.fill"
                  : "arrow.triangle.swap")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(routingError != nil
                                 ? AnyShapeStyle(Brand.warning)
                                 : AnyShapeStyle(LinearGradient.primary))
                .padding(.top, routingError != nil ? 2 : 0)
            Text(routeMetaText)
                .font(.system(size: routingError != nil ? 10 : 12,
                              weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(routingError != nil ? 6 : 1)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if routingError != nil {
                Button {
                    lastRoutedKey = ""
                    recomputeETAIfReady()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry route validation")
            }
        }
        .padding(.horizontal, Space.s4).padding(.vertical, 10)
        .background(LinearGradient(colors: [Brand.blue.opacity(0.06),
                                            Brand.magenta.opacity(0.06)],
                                   startPoint: .leading, endPoint: .trailing))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private var routeMetaText: String {
        let oTrim = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let dTrim = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if oTrim.isEmpty || dTrim.isEmpty {
            return "Add origin + destination - distance / ETA estimates auto-fill"
        }
        if isRouting {
            return "Computing distance + ETA via ESANG…"
        }
        // Mode-specific status comes FIRST. `routingError` only ever describes a
        // HERE *truck* routing outcome, so showing it while Rail/Vessel/Barge is
        // selected made the banner read "Route unavailable ... switch to
        // rail/vessel" even after the user had switched — advice the screen
        // could never satisfy, because this branch was unreachable behind it.
        if transportMode != .truck, endpointsResolved {
            switch transportMode {
            case .rail:
                return "Endpoints verified - rail geometry requires a connected rail routing provider"
            case .vessel:
                return "Ports verified - voyage geometry requires a connected marine routing provider"
            case .barge:
                return "Terminals verified - waterway geometry requires a connected barge routing provider"
            case .truck:
                break
            }
        }
        if let err = routingError {
            return "Route unavailable: \(err)"
        }
        if let meters = routeDistanceMeters, let secs = routeDurationSeconds {
            let miles = Double(meters) / 1609.34
            let hours = Double(secs) / 3600.0
            let etaStr: String = hours > 48
                ? String(format: "%.1f days", hours / 24.0)
                : String(format: "%.1f hr", hours)
            return String(format: "%.0f mi · %@ · standard US semi · HERE-routed", miles, etaStr)
        }
        // Both addresses present and `recomputeETAIfReady` is in flight.
        return "Estimating distance · ETA · best-route via ESANG"
    }

    /// Fire HERE Routing whenever the lane endpoints OR pickup
    /// schedule change. Debounced via `lastRoutedKey`. When lat/lng
    /// haven't been captured yet (user typed an address but never
    /// tapped a HERE suggestion), forward-geocodes the typed text
    /// first so the ETA computes regardless of whether the user
    /// picked from the dropdown. Founder bug 2026-05-07: "ETA
    /// calculating still doesnt work mate" — typing 'Houston, TX'
    /// + 'Austin, TX' previously left the delivery tile stuck on
    /// 'Awaiting addresses · Pick HERE suggestions' because the
    /// HereAddressField only captures coordinates on tap.
    private func recomputeETAIfReady() {
        let oTrim = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let dTrim = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oTrim.isEmpty, !dTrim.isEmpty else {
            routeDistanceMeters = nil
            routeDurationSeconds = nil
            routingError = nil
            isRouting = false
            lastRoutedKey = ""
            return
        }
        let requestedMode = transportMode
        let key = "\(requestedMode.rawValue)|\(originLat ?? .nan),\(originLng ?? .nan)|\(destLat ?? .nan),\(destLng ?? .nan)|\(oTrim)|\(dTrim)"
        guard key != lastRoutedKey else { return }
        lastRoutedKey = key
        isRouting = true
        routingError = nil
        Task {
            do {
                let originResolved = try await ensureResolved(
                    text: oTrim,
                    cachedLat: originLat,
                    cachedLng: originLng
                )
                let destResolved = try await ensureResolved(
                    text: dTrim,
                    cachedLat: destLat,
                    cachedLng: destLng
                )
                // Backfill the @State bindings so the wizard's
                // submit step has resolved coordinates + state
                // codes without a second geocode round-trip. The
                // state codes also feed the ESANG rate compare on
                // step 3.
                let stillCurrent = await MainActor.run { () -> Bool in
                    guard self.lastRoutedKey == key else { return false }
                    if originLat == nil { originLat = originResolved.coord.latitude }
                    if originLng == nil { originLng = originResolved.coord.longitude }
                    if destLat == nil   { destLat   = destResolved.coord.latitude   }
                    if destLng == nil   { destLng   = destResolved.coord.longitude  }
                    self.originStateCode = originResolved.stateCode
                    self.destStateCode   = destResolved.stateCode
                    self.recomputeRateCompareIfReady()
                    return true
                }
                guard stillCurrent else { return }

                guard requestedMode == .truck else {
                    await MainActor.run {
                        guard self.lastRoutedKey == key else { return }
                        self.routeDistanceMeters = nil
                        self.routeDurationSeconds = nil
                        self.routingError = nil
                        self.isRouting = false
                        self.recomputeRateCompareIfReady()
                    }
                    return
                }
                let resp = try await HereRoutingClient.shared.route(
                    stops: HereStops(origin: originResolved.coord,
                                     destination: destResolved.coord),
                    profile: .standardUSSemiLoaded
                )
                let totalDuration = resp.routes.first?.sections.reduce(0) { $0 + ($1.summary?.duration ?? 0) } ?? 0
                let totalLength   = resp.routes.first?.sections.reduce(0) { $0 + ($1.summary?.length ?? 0) }   ?? 0
                await MainActor.run {
                    guard self.lastRoutedKey == key else { return }
                    // Founder report 2026-06-01: every mode rendered
                    // "0 mi · 0.0 hr" for a Houston Port → LA Port
                    // lane because HERE truck routing returns an empty
                    // route (no sections / no summary) for two
                    // seaport waypoints — the dock-side coords land
                    // off any truck road. Old code stored 0/0 in
                    // routeDistanceMeters and the UI happily formatted
                    // it. Treat a zero result as a routing failure
                    // and surface a real message so the user knows to
                    // refine the address (e.g. "Houston, TX" instead
                    // of "Port of Houston").
                    if totalLength == 0 || totalDuration == 0 {
                        self.routeDistanceMeters  = nil
                        self.routeDurationSeconds = nil
                        self.routingError = routeUnavailableMessage
                    } else {
                        self.routeDurationSeconds = totalDuration
                        self.routeDistanceMeters  = totalLength
                        self.routingError = nil
                    }
                    self.isRouting = false
                    // Now that we have lane states + distance, fire
                    // the rate compare if the user has already typed
                    // a posted rate.
                    self.recomputeRateCompareIfReady()
                }
            } catch {
                await MainActor.run {
                    guard self.lastRoutedKey == key else { return }
                    // `ensureResolved` runs ABOVE the `requestedMode == .truck`
                    // guard, so a geocode failure landed here for every mode and
                    // humanRouteMessage(_:) falls through to the truck-routing
                    // copy ("switch to rail/vessel…") for any unrecognised error.
                    // That is why switching mode never cleared the banner. Only
                    // truck mode owns a routing error; for the other modes the
                    // coordinate-based `endpointsResolved` gate is what decides.
                    self.routingError = requestedMode == .truck
                        ? humanRouteMessage(for: error)
                        : nil
                    self.isRouting = false
                }
            }
        }
    }

    private var routeUnavailableMessage: String {
        "Try a city-level address or switch to rail/vessel if the lane is not truck-routable."
    }

    private var endpointsResolved: Bool {
        validCoordinate(lat: originLat, lng: originLng)
            && validCoordinate(lat: destLat, lng: destLng)
    }

    private var laneReadyForPosting: Bool {
        let hasAddresses = !origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasAddresses,
              countrySelectionIsValid,
              endpointsResolved,
              !isRouting else {
            return false
        }
        // `routingError` describes a HERE TRUCK routing outcome only. It used to
        // sit in the guard above, which made the non-truck early return below
        // unreachable: a truck-routing failure blocked posting in Rail, Vessel
        // and Barge too, even though those modes never needed truck geometry.
        // `endpointsResolved` above is the real gate for them — it is
        // coordinate-based, so a genuine geocode failure still blocks posting.
        guard transportMode == .truck else { return true }
        guard routingError == nil else { return false }
        return (routeDistanceMeters ?? 0) > 0 && (routeDurationSeconds ?? 0) > 0
    }

    private var countrySelectionIsValid: Bool {
        let originCode = originCountryCode.uppercased()
        let destinationCode = destinationCountryCode.uppercased()
        guard originCode.count == 2, destinationCode.count == 2 else { return false }
        if transportMode == .truck || transportMode == .rail {
            let northAmerica = Set(["US", "CA", "MX"])
            return northAmerica.contains(originCode) && northAmerica.contains(destinationCode)
        }
        return true
    }

    private var portIntelligenceIsRequired: Bool {
        transportMode != .truck
    }

    private var portIntelligenceProductName: String {
        properShippingName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var portIntelligencePhysicalState: String {
        switch cargoType {
        case .gas:
            return "gas"
        case .liquid, .petroleum, .chemicals:
            return "liquid"
        default:
            return "solid"
        }
    }

    private var portIntelligenceVehicleCount: Int? {
        multiVehicleEstimate
            .map(\.vehicleCount)
            .flatMap { (1...999).contains($0) ? $0 : nil }
    }

    private var portIntelligencePermit: String? {
        guard equipmentType == .oversized
                || equipmentType == .flatbed
                || equipmentType == .stepDeck
                || equipmentType == .conestoga,
              permitType != .none else {
            return nil
        }
        return permitType.rawValue
    }

    private var currentPortIntelligenceSignature: String {
        [
            portIntelligenceProductName,
            commodityMatch?.category ?? cargoType.rawValue,
            portIntelligencePhysicalState,
            unNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            hazmatClass.trimmingCharacters(in: .whitespacesAndNewlines),
            transportMode.rawValue,
            parseDouble(weightText).map { String($0) } ?? "",
            weightUnit.rawValue,
            origin.trimmingCharacters(in: .whitespacesAndNewlines),
            destination.trimmingCharacters(in: .whitespacesAndNewlines),
            originCountryCode.uppercased(),
            destinationCountryCode.uppercased(),
            equipmentType.rawValue,
            portIntelligenceVehicleCount.map { String($0) } ?? "",
            hasPickupDate ? isoDate(pickupDate) : "",
            portIntelligencePermit ?? "",
        ].joined(separator: "\u{1F}")
    }

    private var hasCurrentPortIntelligenceAssessment: Bool {
        portIntelligenceAssessment != nil
            && portIntelligenceAssessmentSignature == currentPortIntelligenceSignature
    }

    private var portIntelligenceAllowsPosting: Bool {
        guard portIntelligenceIsRequired else {
            guard hasCurrentPortIntelligenceAssessment, let assessment = portIntelligenceAssessment else {
                return true
            }
            if assessment.preflight.gate == "blocked" { return false }
            return assessment.preflight.gate != "acknowledgement_required"
                || portIntelligenceAcknowledged
        }
        guard hasCurrentPortIntelligenceAssessment, let assessment = portIntelligenceAssessment else {
            return false
        }
        switch assessment.preflight.gate {
        case "ready":
            return true
        case "acknowledgement_required":
            return portIntelligenceAcknowledged
        default:
            return false
        }
    }

    @MainActor
    private func assessPortIntelligence() async {
        portIntelligenceError = nil
        portIntelligenceAcknowledged = false

        guard laneReadyForPosting else {
            portIntelligenceError = "Resolve the route and both countries before running Port Intelligence."
            return
        }
        guard !portIntelligenceProductName.isEmpty else {
            portIntelligenceError = "Select or enter the exact commodity or product before assessment."
            return
        }
        guard let quantity = parseDouble(weightText), quantity > 0 else {
            portIntelligenceError = "Enter a positive cargo quantity before assessment."
            return
        }

        isAssessingPortIntelligence = true
        defer { isAssessingPortIntelligence = false }

        let request = PortIntelAssessmentInput(
            requestKey: UUID().uuidString,
            title: "\(portIntelligenceProductName) · \(shortAddress(origin)) to \(shortAddress(destination))",
            draft: .init(
                productName: portIntelligenceProductName,
                category: commodityMatch?.category ?? cargoType.rawValue,
                physicalState: portIntelligencePhysicalState,
                unNumber: nonBlank(unNumber),
                hazmatClass: nonBlank(hazmatClass),
                transportMode: transportMode.rawValue,
                quantity: quantity,
                quantityUnit: weightUnit.rawValue,
                origin: origin.trimmingCharacters(in: .whitespacesAndNewlines),
                destination: destination.trimmingCharacters(in: .whitespacesAndNewlines),
                originCountry: originCountryCode.uppercased(),
                destinationCountry: destinationCountryCode.uppercased(),
                equipment: equipmentType.rawValue,
                vesselClass: nil,
                multiVehicleCount: portIntelligenceVehicleCount,
                pickupDate: hasPickupDate ? isoDate(pickupDate) : nil,
                specialPermit: portIntelligencePermit
            )
        )

        do {
            let result: PortIntelAssessment = try await EusoTripAPI.shared.mutation(
                "portIntelligence.assessLoadDraft",
                input: request
            )
            portIntelligenceAssessment = result
            portIntelligenceAssessmentSignature = currentPortIntelligenceSignature
        } catch {
            portIntelligenceAssessment = nil
            portIntelligenceAssessmentSignature = nil
            portIntelligenceError = (error as? EusoTripAPIError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func validCoordinate(lat: Double?, lng: Double?) -> Bool {
        guard let lat, let lng,
              (-90.0...90.0).contains(lat),
              (-180.0...180.0).contains(lng) else { return false }
        return !(lat == 0 && lng == 0)
    }

    private func humanRouteMessage(for error: Error) -> String {
        let raw = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let lower = raw.lowercased()
        if lower.contains("no truck route") || lower.contains("route between") || lower.contains("routing") {
            return routeUnavailableMessage
        }
        if lower.contains("malformed") || lower.contains("parsing") || lower.contains("invalid") {
            return "The route provider could not read one of these locations. Pick a city-level suggestion and retry."
        }
        if lower.contains("offline") || lower.contains("network") || lower.contains("timed") {
            return "Route estimate is temporarily unavailable. Check the connection and retry."
        }
        return routeUnavailableMessage
    }

    // MARK: - ESANG rate vs market meter (rates.compareLaneRate)

    /// The canonical wire-side rate unit for the current mode +
    /// equipment selection. Mirrors the value `submit()` persists on
    /// the load (`shippers.create.rateUnit`) so the rate-vs-market
    /// query and the posted load agree on the unit — never hard-code
    /// nil here, or the server has to GUESS the unit (which the
    /// zero-fabrication envelope forbids).
    private var rateUnitWire: String {
        switch transportMode {
        // 2026-06-13 — the truck rate field is a FLAT LINEHAUL TOTAL
        // (not a per-mile figure), so wire it as 'flat' and let the
        // server divide by distance exactly ONCE into the canonical
        // $/mi benchmark. Sending 'usd_per_mile' made the server treat
        // the total as already-per-mile (no division), then the client
        // re-divided yourRPM again → the iOS↔web parity divergence.
        // (Restore a per-mile wire only if a dedicated per-mile field
        // is ever added.)
        case .truck:  return "flat"
        case .rail:   return "usd_per_ton_mile"
        case .vessel:
            switch equipmentType {
            case .vesselTanker:    return "worldscale"
            case .vesselContainer: return "usd_per_feu"
            case .vesselBulk:      return "usd_per_metric_ton"
            default:               return "flat"
            }
        case .barge:  return "usd_per_ton_mile"
        }
    }

    private var rateCompareRequiresDistance: Bool {
        switch rateUnitWire {
        case "flat", "usd_total":
            return true
        default:
            return false
        }
    }

    /// TRUE when the rate field holds a Worldscale percent (vessel
    /// tanker), not a dollar amount. The value the user types is a WS%
    /// and CANNOT be benchmarked without a per-load Worldscale-100 flat.
    private var rateIsWorldscalePct: Bool {
        transportMode == .vessel && equipmentType == .vesselTanker
    }

    /// Origin-leg country code ('US' | 'MX' | 'CA') the server uses to
    /// scope the benchmark cohort + currency. Resolved from the same
    /// state→country rule the server applies to mint loads.originCountry.
    private var laneCountryWire: String {
        LoadAnimationContext.countryCode(
            forState: originStateForRateCompare
        ).uppercased()
    }

    private var originStateForRateCompare: String {
        Self.normalizedStateCode(originStateCode) ?? Self.stateFromLane(origin)
    }

    private var destStateForRateCompare: String {
        Self.normalizedStateCode(destStateCode) ?? Self.stateFromLane(destination)
    }

    /// Fires `rates.compareLaneRate` when origin state + dest state +
    /// distance + a posted rate are all known. Web parity meter; same
    /// `LaneComparison` envelope the LoadDetailSheet renders next to
    /// the posted rate.
    private func recomputeRateCompareIfReady() {
        let oState = originStateForRateCompare
        let dState = destStateForRateCompare
        guard !oState.isEmpty,
              !dState.isEmpty,
              let rate = parseDouble(rateText), rate > 0 else {
            rateComparison = nil
            rateCompareError = nil
            return
        }
        let distanceMiles = routeDistanceMeters.map { Double($0) / 1609.34 }
        if rateCompareRequiresDistance, (distanceMiles ?? 0) <= 0 {
            rateComparison = nil
            rateCompareError = nil
            return
        }
        let miles = distanceMiles ?? 0
        // For a WS% tanker rate the dollar `rate` field is actually a
        // Worldscale percent — capture it on its own param and pass the
        // per-load Worldscale-100 flat (if the wizard ever captures one)
        // as the conversion basis. Absent a flat, the server honestly
        // returns referenceReason='needs_ws100_flat' (no WS-100 feed
        // invented). For all other modes worldscalePct stays nil.
        let unitWire   = rateUnitWire
        let wsPct      = rateIsWorldscalePct ? rate : nil
        let wsFlatRef  = rateIsWorldscalePct ? parseDouble(worldscaleFlatText) : nil
        let countryW   = laneCountryWire
        let key = "\(oState)|\(dState)|\(Int(miles))|\(Int(rate))|\(cargoType.rawValue)|\(unitWire)|\(equipmentType.rawValue)|\(countryW)|\(wsFlatRef.map { Int($0) } ?? -1)"
        guard key != lastRateCompareKey else { return }
        lastRateCompareKey = key
        isComparingRate = true
        rateCompareError = nil
        Task {
            do {
                // 2026-05-19 — pipe transportMode + commodity through
                // so the server can branch units (rail $/car-mile,
                // vessel $/MT, etc.) and tap Gemini for market intel
                // when platform data is thin.
                // 2026-06-13 — STOP hard-coding rateUnit:nil. Pass the
                // real wire unit + (for WS% tankers) the Worldscale pct
                // and per-load WS-100 flat + equipmentType + country so
                // the server can normalize into the canonical envelope
                // instead of guessing the unit.
                let r = try await EusoTripAPI.shared.rates.compareLaneRate(
                    originState: oState,
                    destState:   dState,
                    rate:        rate,
                    distance:    miles,
                    cargoType:   cargoType.rawValue,
                    lookbackDays: 90,
                    transportMode: transportMode.rawValue,
                    rateUnit:    unitWire,
                    commodity:   cargoType.rawValue,
                    worldscalePct: wsPct,
                    worldscaleFlatRef: wsFlatRef,
                    equipmentType: equipmentType.rawValue,
                    country: countryW
                )
                await MainActor.run {
                    self.rateComparison = r
                    self.isComparingRate = false
                }
            } catch {
                await MainActor.run {
                    self.rateCompareError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.isComparingRate = false
                }
            }
        }
    }

    // MARK: - ERG (Emergency Response Guidebook) lookup

    /// Fires `erg.searchByUN` when the user types a 4-digit UN
    /// number. Auto-populates hazmat class + proper shipping name +
    /// ERG guide on a successful match. Web parity with the
    /// platform's ERG database — same router (`erg.searchByUN`).
    private func lookupERGIfReady() {
        let raw = unNumber.uppercased()
            .replacingOccurrences(of: "UN", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Server requires at least 4 digits to lookup. Bail otherwise.
        guard raw.count >= 4, raw.allSatisfy(\.isNumber) else {
            ergMatch = nil
            ergLookupError = nil
            return
        }
        let key = raw
        guard key != lastErgQueryKey else { return }
        lastErgQueryKey = key
        isLookingUpERG = true
        ergLookupError = nil
        Task {
            do {
                let detail = try await EusoTripAPI.shared.erg.searchByUN(raw)
                await MainActor.run {
                    self.isLookingUpERG = false
                    if detail.found {
                        self.ergMatch = detail
                        // ERG is an emergency-response reference, not
                        // legal dangerous-goods classification evidence.
                        if let name = detail.name,
                           shouldReplaceProperShippingName(with: name) {
                            properShippingName = name
                        }
                    } else {
                        self.ergMatch = nil
                        self.ergLookupError = "UN\(raw) not found in ERG"
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLookingUpERG = false
                    self.ergLookupError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    /// Apply a search-hit selection from the ERG response-reference
    /// sheet. UN + material name may accelerate entry, but ERG never
    /// writes the legally controlled hazmat-class field.
    private func applyERGHit(_ hit: ErgAPI.SearchHit) {
        unNumber = hit.unNumber
        if !hit.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            properShippingName = hit.name
        }
        showErgSearchSheet = false
    }

    private func shouldReplaceProperShippingName(with materialName: String) -> Bool {
        let current = properShippingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !materialName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if current.isEmpty { return true }
        let generic = [
            "flammable", "flammable liquid", "combustible liquid",
            "corrosive", "poison", "oxidizer", "miscellaneous"
        ]
        return generic.contains(current.lowercased())
    }

    /// `erg.search` typeahead — debounced inside the search sheet
    /// onSubmit / commit, fired with the current `ergSearchQuery`.
    private func searchERG() {
        let q = ergSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            ergSearchHits = []
            return
        }
        isSearchingERG = true
        Task {
            do {
                let resp = try await EusoTripAPI.shared.erg.search(query: q, limit: 12)
                await MainActor.run {
                    self.ergSearchHits = resp.results
                    self.isSearchingERG = false
                }
            } catch {
                await MainActor.run {
                    self.ergSearchHits = []
                    self.isSearchingERG = false
                }
            }
        }
    }

    // MARK: - Non-hazmat commodity lookup (ERG-parity)

    /// `commodity.*` typeahead — debounced inside the commodity search
    /// sheet. Dispatches to the proc the active (cargoType, equipment,
    /// mode) tuple selects. Mirrors `searchERG()`.
    private func searchCommodity() {
        let q = commoditySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            commoditySearchHits = []
            return
        }
        let proc = activeCommodityProc
        isSearchingCommodity = true
        commodityLookupError = nil
        Task {
            do {
                let api = EusoTripAPI.shared.commodity
                let resp: CommodityLookupAPI.SearchResponse
                switch proc {
                case .chemical:      resp = try await api.searchChemical(query: q, limit: 12)
                case .petroleum:     resp = try await api.searchPetroleum(query: q, limit: 12)
                case .reefer:        resp = try await api.searchReefer(query: q, limit: 12)
                case .containerType: resp = try await api.searchContainerType(query: q, limit: 12)
                case .stcc:          resp = try await api.searchStcc(query: q, limit: 12)
                }
                await MainActor.run {
                    self.commoditySearchHits = resp.results
                    self.isSearchingCommodity = false
                }
            } catch {
                await MainActor.run {
                    self.commoditySearchHits = []
                    self.isSearchingCommodity = false
                    self.commodityLookupError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    /// Apply a commodity search-hit selection — pins the product into
    /// `properShippingName` (the single commodity source of truth) and,
    /// for the reefer lookup, auto-fills the temp band ONLY when the
    /// user hasn't already typed one (never overwrite explicit entry),
    /// mirroring the ERG auto-fill rule.
    private func applyCommodityHit(_ hit: CommodityLookupAPI.CommodityHit) {
        commodityMatch = hit
        commodityLookupError = nil
        properShippingName = hit.name
        if hit.preCool == true { preCoolRequired = true }
        if let lo = hit.tempLowF, reeferTempLowText.isEmpty {
            reeferTempLowText = formatTemp(lo)
        }
        if let hi = hit.tempHighF, reeferTempHighText.isEmpty {
            reeferTempHighText = formatTemp(hi)
        }
        showCommoditySearchSheet = false
    }

    /// Format a °F temperature for the reefer text fields — drops a
    /// trailing ".0" so a whole number reads "40", not "40.0".
    private func formatTemp(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }

    /// Resolved geocode hit — coordinate + state code. Used by both
    /// the routing step (needs lat/lng) and the rate compare step
    /// (needs state code).
    private struct ResolvedAddress {
        let coord: CLLocationCoordinate2D
        let stateCode: String?
    }

    /// Returns a resolved address for the given typed text. Uses
    /// cached lat/lng (set by the address field on suggestion-tap)
    /// when both are present; otherwise forward-geocodes via the
    /// EusoTrip routing backend. State code is sourced from the
    /// geocode hit's address payload.
    private func ensureResolved(
        text: String,
        cachedLat: Double?,
        cachedLng: Double?
    ) async throws -> ResolvedAddress {
        if let lat = cachedLat, let lng = cachedLng {
            // Reverse-geocode for the state code — the lat/lng might
            // have been pasted directly, so we still need a state
            // resolution for the rate compare. Best-effort; falls
            // back to nil stateCode which compareLaneRate accepts.
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            let state = try? await HereGeocodingClient.shared
                .reverseGeocode(at: coord, limit: 1)
                .first?
                .address.stateCode
            return ResolvedAddress(coord: coord, stateCode: state ?? nil)
        }
        let hits = try await HereGeocodingClient.shared.geocode(query: text, limit: 1)
        guard let first = hits.first, let pos = first.position else {
            throw HereMapsError.providerError("No geocode result for '\(text)'")
        }
        return ResolvedAddress(
            coord: CLLocationCoordinate2D(latitude: pos.lat, longitude: pos.lng),
            stateCode: first.address.stateCode
        )
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SCHEDULE")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                pickupTile
                deliveryTile
            }
        }
    }

    private var pickupTile: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // Mode-correct origin term — truck "PICKUP WINDOW", vessel-tanker
                // "LOAD LAYCAN", vessel-container "ERD", rail "WANT DATE" (TransportLexicon).
                Text(TransportLexicon.short(.originWindow, mode: transportMode, equipmentRaw: equipmentType.rawValue).uppercased())
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                // The "Schedule" label was inside the Toggle's title
                // string and `.labelsHidden()` failed to hide it
                // under dynamic type, so the founder saw "Sched-\nule"
                // wrap inside a tiny pill on the Post Load screen
                // (2026-05-05). Splitting the label out as a sibling
                // Text + passing an empty title to Toggle bypasses
                // both the label-hidden bug and the wrap.
                Text("SCHEDULE")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Toggle("", isOn: $hasPickupDate.animation(.spring(response: 0.22, dampingFraction: 0.85)))
                    .toggleStyle(GradientToggleStyle())
                    .labelsHidden()
            }
            if hasPickupDate {
                // `in: pickupLowerBound...` (start-of-today) — NOT `Date()...`.
                // A moving `Date()` lower bound can momentarily exclude an
                // equal selection, and a restored past `pickupDate` falling
                // outside the range traps the compact picker. The hydrate
                // pass clamps `pickupDate` into this same bound so selection
                // and range are always consistent.
                DatePicker("Pickup", selection: $pickupDate, in: pickupLowerBound..., displayedComponents: [.date])
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(LinearGradient.diagonal)
                    .disabled(isSubmitting)
            } else {
                Text("Catalyst proposes")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("Leave blank or schedule")
                    .font(EType.caption).monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var deliveryTile: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Mode-correct destination term — truck "DELIVERY WINDOW", vessel
            // "DISCHARGE LAYCAN", rail "DELIVERY SPOT" (TransportLexicon).
            Text(TransportLexicon.short(.destinationWindow, mode: transportMode, equipmentRaw: equipmentType.rawValue).uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
            // Real ETA when both pickup is set + HERE returned a
            // duration. Falls back to honest copy otherwise.
            if let eta = computedDeliveryETA {
                Text(deliveryETAFormatter.string(from: eta))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ESANG-routed · pickup + lane")
                    .font(EType.caption).monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            } else if hasPickupDate && isRouting {
                Text("Computing…")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("ESANG-routed")
                    .font(EType.caption).monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            } else if hasPickupDate {
                Text("Add addresses")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("Type or pick a suggestion")
                    .font(EType.caption).monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            } else {
                Text("Catalyst proposes")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("Set after pickup is scheduled")
                    .font(EType.caption).monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: - Step 2: EQUIPMENT

    @ViewBuilder
    private var equipmentStepBody: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            cargoTypePicker
            equipmentTypePicker
            weightField
            equipmentPreviewSection
            equipmentSubform
            // 2026-05-17 — Pre-submit hazmat compliance gates.
            // Mirrors the server-side checks in loads.create
            // (TRAILER_HAZMAT_ALLOWED + SEGREGATION_TABLE per
            // 49 CFR 173 / 177.848) so the user sees the violation
            // BEFORE the wizard fires the mutation. Hidden when
            // hazmatClass is empty.
            hazmatComplianceCard
            // 2026-05-17 — State-overweight pre-flight. Server-side
            // loads.create enforces STATE_WEIGHT_LIMITS (federal 80k
            // baseline, MI=164k, MT=131.06k, ND=105.5k, SD/NV=129k).
            // Catching it client-side gives the user the same
            // amber-pill remediation pattern as the hazmat card
            // (suggest permit type or splitting into multiple loads).
            overweightComplianceCard
        }
    }

    /// State-overweight pre-flight. Renders nothing when the typed
    /// weight is empty / under both state limits. Surfaces amber when
    /// the load exceeds either origin or destination state limit, with
    /// the specific remediation: oversized permit, or split into the
    /// computed N-vehicle minimum.
    @ViewBuilder
    private var overweightComplianceCard: some View {
        let weightLbs = parseWeightLbs(weightText, unit: weightUnit)
        let oState = originStateCode ?? Self.stateFromLane(origin)
        let dState = destStateCode ?? Self.stateFromLane(destination)
        let oLimit = Self.stateWeightLimit(oState)
        let dLimit = Self.stateWeightLimit(dState)
        let oOver = !oState.isEmpty && weightLbs > Double(oLimit)
        let dOver = !dState.isEmpty && weightLbs > Double(dLimit)
        let anyOver = oOver || dOver
        // State weight limits are HIGHWAY truck limits (federal 80k lb
        // + per-state exceptions). They do not apply to rail (FRA /
        // car-specific) or vessel/barge (vessel class deadweight).
        // Founder bug 2026-05-31: a 35,000 MT vessel load was tripping
        // the overweight warning because the card never checked the
        // transport mode — vessel-DWT-scale weights ALWAYS exceed
        // truck-axle-scale state limits.
        let modeAppliesToStateLimits = (transportMode == .truck)
        if modeAppliesToStateLimits, weightLbs > 0 && (oOver || dOver) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "scalemass.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Brand.warning)
                    Text("OVERWEIGHT LANE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(Brand.warning)
                    Spacer(minLength: 0)
                    Text("Federal 80k · State-specific exceptions")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                }
                Text(overweightCopy(weightLbs: weightLbs, oState: oState, oLimit: oLimit, oOver: oOver, dState: dState, dLimit: dLimit, dOver: dOver))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                // Remediation row: tap-to-set the most appropriate permit.
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                            permitType = .overweightOnly
                            oversizePermits = true
                        }
                    } label: {
                        Text("Set Overweight-only permit")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(LinearGradient.diagonal))
                    }.buttonStyle(.plain)
                    if let split = suggestedSplit(weightLbs: weightLbs, limit: min(oLimit, dLimit)) {
                        Text("or split into \(split) loads")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Brand.warning.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Brand.warning.opacity(0.35), lineWidth: 1)
            )
        } else if modeAppliesToStateLimits, weightLbs > 0 && !anyOver && !oState.isEmpty && !dState.isEmpty {
            // Subtle green confirmation so the wizard tells the user
            // the lane passes the gate — silence is ambiguous.
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Brand.success)
                Text("\(Int(weightLbs).formatted()) lb within \(oState)/\(dState) gross-weight limits")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: - Equipment Recommender helpers (Tier 2 #40)

    /// Best-effort commodity description for the equipment agent.
    /// Prefers a fresh free-form `notes` description; falls back to
    /// the canonical cargo category. Trimmed to under 200 chars so
    /// the agent prompt stays predictable.
    private func equipmentRecommenderCommodityString() -> String {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return String(trimmed.prefix(200))
        }
        return cargoType.rawValue.replacingOccurrences(of: "_", with: " ")
    }

    /// Equipment-agent vertical: "TRUCK" | "RAIL" | "VESSEL".
    /// Barge folds into VESSEL since the server side equipment
    /// catalog uses the same set for both.
    private func equipmentRecommenderVerticalString() -> String {
        switch transportMode {
        case .truck:  return "TRUCK"
        case .rail:   return "RAIL"
        case .vessel: return "VESSEL"
        case .barge:  return "VESSEL"
        }
    }

    /// Apply a server-recommended trailerKey to the picker. The app
    /// accepts legacy server aliases, then only mutates when the key
    /// resolves to a real EquipmentChoice.
    private func applyRecommendedTrailerKey(_ trailerKey: String) {
        let normalized = normalizedRecommendedTrailerKey(trailerKey)
        if let match = EquipmentChoice(rawValue: normalized) {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                equipmentType = match
            }
        }
    }

    private func normalizedRecommendedTrailerKey(_ raw: String) -> String {
        let key = raw
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        switch key {
        case "tanker_petro", "tanker_petroleum", "petroleum_tanker":
            return EquipmentChoice.tankerPetro.rawValue
        case "food_grade_tank", "water_tank", "chemical_tank", "dot_407", "dot407",
             "mc_307", "mc307", "cargo_tank":
            return EquipmentChoice.tankerLiquid.rawValue
        case "hazmat_tanker", "chemical_tanker", "tanker_chemical", "dot_412",
             "dot412", "mc_312", "mc312":
            return EquipmentChoice.tankerHazmat.rawValue
        case "double_drop", "rgn", "removable_gooseneck":
            return EquipmentChoice.lowboy.rawValue
        case "hotshot", "gooseneck", "gooseneck_flatbed":
            return EquipmentChoice.hotShot.rawValue
        case "bulk_hopper", "grain_hopper", "log_trailer", "livestock", "auto_carrier":
            return EquipmentChoice.flatbed.rawValue
        case "vessel_ro_ro", "vessel_roro", "roro", "vessel_ro-ro":
            return EquipmentChoice.vesselRoRo.rawValue
        case "iso_tank", "vessel_isotank":
            return EquipmentChoice.vesselISOTank.rawValue
        default:
            return key
        }
    }

    /// Parse the user's typed weight + unit and convert to pounds.
    /// Returns 0 for unparseable input or units with no mass meaning
    /// (TEU/FEU/pallets etc.).
    private func parseWeightLbs(_ text: String, unit: MeasurementUnit) -> Double {
        guard let v = Double(text.replacingOccurrences(of: ",", with: "")) else { return 0 }
        switch unit {
        case .pounds:     return v
        case .kilograms:  return v * 2.20462
        case .shortTons:  return v * 2000
        case .metricTons: return v * 2204.62
        case .gallons:    return v * 7  // ~7 lb/gal for refined product (rough)
        case .barrels:    return v * 294 // 42 gal × 7 lb/gal
        case .liters:     return v * 1.85
        case .cubicMeters: return v * 1850
        default:          return 0
        }
    }

    /// Suggested split — how many vehicles needed so each falls
    /// under the binding state limit. Returns nil for limits ≤ 0
    /// or single-vehicle loads.
    private func suggestedSplit(weightLbs: Double, limit: Int) -> Int? {
        guard limit > 0, weightLbs > Double(limit) else { return nil }
        return Int((weightLbs / Double(limit)).rounded(.up))
    }

    private func overweightCopy(weightLbs: Double, oState: String, oLimit: Int, oOver: Bool, dState: String, dLimit: Int, dOver: Bool) -> String {
        let wInt = Int(weightLbs)
        if oOver && dOver {
            return "\(wInt.formatted()) lb exceeds both \(oState) (\(oLimit.formatted())) and \(dState) (\(dLimit.formatted())) state limits. Requires an overweight permit or load split."
        }
        if oOver {
            return "\(wInt.formatted()) lb exceeds the \(oState) origin limit of \(oLimit.formatted()) lb. Requires an overweight permit or load split."
        }
        return "\(wInt.formatted()) lb exceeds the \(dState) destination limit of \(dLimit.formatted()) lb. Requires an overweight permit or load split."
    }

    /// State-specific gross-weight ceiling (lbs). Mirrors
    /// `STATE_WEIGHT_LIMITS` in loads.ts:279. Defaults to the
    /// federal 80,000 lb limit when the state isn't in the override
    /// list (which covers most of the 50 states).
    fileprivate static func stateWeightLimit(_ state: String) -> Int {
        switch state.uppercased() {
        case "MI": return 164_000
        case "MT": return 131_060
        case "ND": return 105_500
        case "SD": return 129_000
        case "NV": return 129_000
        default:   return 80_000
        }
    }

    /// Best-effort state extraction from a free-form address line.
    /// "Houston, TX, United States" → "TX".
    private static func normalizedStateCode(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let upper = trimmed.uppercased()
        if upper.count == 2, upper.range(of: #"^[A-Z]{2}$"#, options: .regularExpression) != nil {
            return upper
        }
        return stateNameToCode[upper]
    }

    fileprivate static func stateFromLane(_ raw: String) -> String {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: ",")
        guard !cleaned.isEmpty else { return "" }

        let countryTokens: Set<String> = [
            "US", "USA", "U.S.", "U.S.A.", "UNITED STATES", "UNITED STATES OF AMERICA",
            "CA", "CAN", "CANADA",
            "MX", "MEX", "MEXICO"
        ]

        let commaParts = cleaned
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for part in commaParts.reversed() {
            let upper = part.uppercased()
            if countryTokens.contains(upper) { continue }
            if let exact = normalizedStateCode(upper) { return exact }
            let words = upper
                .split(whereSeparator: { !$0.isLetter })
                .map(String.init)
                .filter { !$0.isEmpty }
            for count in stride(from: min(words.count, 4), through: 1, by: -1) {
                let phrase = words.suffix(count).joined(separator: " ")
                if countryTokens.contains(phrase) { continue }
                if let mapped = stateNameToCode[phrase] { return mapped }
            }
            if let last = words.last, let exact = normalizedStateCode(last) { return exact }
        }

        let words = cleaned.uppercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { !$0.isEmpty && !countryTokens.contains($0) }
        for count in stride(from: min(words.count, 4), through: 1, by: -1) {
            let phrase = words.suffix(count).joined(separator: " ")
            if let mapped = stateNameToCode[phrase] { return mapped }
        }
        if let last = words.last, let exact = normalizedStateCode(last) { return exact }
        return ""
    }

    private static let stateNameToCode: [String: String] = [
        "ALABAMA": "AL", "ALASKA": "AK", "ARIZONA": "AZ", "ARKANSAS": "AR",
        "CALIFORNIA": "CA", "COLORADO": "CO", "CONNECTICUT": "CT", "DELAWARE": "DE",
        "DISTRICT OF COLUMBIA": "DC", "WASHINGTON DC": "DC",
        "FLORIDA": "FL", "GEORGIA": "GA", "HAWAII": "HI", "IDAHO": "ID",
        "ILLINOIS": "IL", "INDIANA": "IN", "IOWA": "IA", "KANSAS": "KS",
        "KENTUCKY": "KY", "LOUISIANA": "LA", "MAINE": "ME", "MARYLAND": "MD",
        "MASSACHUSETTS": "MA", "MICHIGAN": "MI", "MINNESOTA": "MN", "MISSISSIPPI": "MS",
        "MISSOURI": "MO", "MONTANA": "MT", "NEBRASKA": "NE", "NEVADA": "NV",
        "NEW HAMPSHIRE": "NH", "NEW JERSEY": "NJ", "NEW MEXICO": "NM", "NEW YORK": "NY",
        "NORTH CAROLINA": "NC", "NORTH DAKOTA": "ND", "OHIO": "OH", "OKLAHOMA": "OK",
        "OREGON": "OR", "PENNSYLVANIA": "PA", "RHODE ISLAND": "RI", "SOUTH CAROLINA": "SC",
        "SOUTH DAKOTA": "SD", "TENNESSEE": "TN", "TEXAS": "TX", "UTAH": "UT",
        "VERMONT": "VT", "VIRGINIA": "VA", "WASHINGTON": "WA", "WEST VIRGINIA": "WV",
        "WISCONSIN": "WI", "WYOMING": "WY",
        "ALBERTA": "AB", "BRITISH COLUMBIA": "BC", "MANITOBA": "MB", "NEW BRUNSWICK": "NB",
        "NEWFOUNDLAND AND LABRADOR": "NL", "NOVA SCOTIA": "NS", "ONTARIO": "ON",
        "PRINCE EDWARD ISLAND": "PE", "QUEBEC": "QC", "SASKATCHEWAN": "SK",
        "AGUASCALIENTES": "AG", "BAJA CALIFORNIA": "BC", "BAJA CALIFORNIA SUR": "BS",
        "CAMPECHE": "CM", "CHIAPAS": "CS", "CHIHUAHUA": "CH", "COAHUILA": "CO",
        "COLIMA": "CL", "DURANGO": "DG", "GUANAJUATO": "GT", "GUERRERO": "GR",
        "HIDALGO": "HG", "JALISCO": "JA", "MEXICO CITY": "CX", "CIUDAD DE MEXICO": "CX",
        "MICHOACAN": "MI", "MORELOS": "MO", "NAYARIT": "NA", "NUEVO LEON": "NL",
        "OAXACA": "OA", "PUEBLA": "PU", "QUERETARO": "QT", "QUINTANA ROO": "QR",
        "SAN LUIS POTOSI": "SL", "SINALOA": "SI", "SONORA": "SO", "TABASCO": "TB",
        "TAMAULIPAS": "TM", "TLAXCALA": "TL", "VERACRUZ": "VE", "YUCATAN": "YU",
        "ZACATECAS": "ZA"
    ]

    /// 49 CFR 177.848 hazmat compliance card. Renders nothing for
    /// non-hazmat loads, a green confirmation pill for compatible
    /// combinations, and a tinted-amber warning card with the
    /// specific regulatory citation for incompatible combos.
    /// Doctrine reference: "Hazmat is the most stringent lens"
    /// (memory: feedback_doctrine_parity).
    @ViewBuilder
    private var hazmatComplianceCard: some View {
        if !hazmatClass.isEmpty {
            let trailerCode = trailerHazmatCode(for: equipmentType)
            let allowedClasses = Self.trailerHazmatAllowed[trailerCode] ?? []
            let trailerOk = allowedClasses.contains(hazmatClass)
            let cdlEndorsements = Self.requiredCdlEndorsements(
                hazmatClass: hazmatClass,
                trailerCode: trailerCode
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: trailerOk ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(trailerOk ? Brand.success : Brand.warning)
                    Text(trailerOk ? "HAZMAT COMPATIBLE" : "HAZMAT INCOMPATIBLE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(trailerOk ? Brand.success : Brand.warning)
                    Spacer(minLength: 0)
                    Text("49 CFR 173")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                }
                if trailerOk {
                    Text("Class \(hazmatClass) is approved for \(equipmentType.label). CDL endorsements required: \(cdlEndorsements.joined(separator: " + "))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Class \(hazmatClass) cannot be transported on \(equipmentType.label). Permitted equipment: \(Self.equipmentLabels(forHazmatClass: hazmatClass).joined(separator: ", ")).")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 2026-05-17 — 49 CFR 177.848 co-load segregation
                // advisory. Surfaces the list of hazmat classes that
                // ARE allowed adjacent to the primary class on the
                // same vehicle. Future-compat for when compartment
                // UI lands: the same `compatibleHazmatClasses` /
                // `firstSegregationViolation` helpers will gate the
                // compartment picker.
                if trailerOk {
                    let compatible = Self.compatibleHazmatClasses(for: hazmatClass)
                    if !compatible.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("49 CFR 177.848 · CO-LOAD COMPATIBILITY")
                                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                                .foregroundStyle(palette.textTertiary)
                            Text("Compatible adjacent classes: \(compatible.joined(separator: ", "))")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill((trailerOk ? Brand.success : Brand.warning).opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder((trailerOk ? Brand.success : Brand.warning).opacity(0.35), lineWidth: 1)
            )
        }
    }

    /// Map the wizard's EquipmentChoice enum onto the server's
    /// trailer-code dictionary (`liquid_tank`, `gas_tank`,
    /// `hazmat_van`, etc.) so the same allow-list table works
    /// for both client + server.
    private func trailerHazmatCode(for choice: EquipmentChoice) -> String {
        switch choice {
        case .tankerHazmat, .tankerPetro, .tankerLiquid, .vesselTanker,
             .railTankLiquid, .vesselISOTank:
            return "liquid_tank"
        case .tankerGas, .railTankGas, .vesselLNG:
            return "gas_tank"
        case .dryVan, .powerOnly, .hotShot,
             .railBoxcar, .railReeferBoxcar:
            return "dry_van"
        case .reefer, .vesselReeferContainer:
            return "reefer"
        case .flatbed, .stepDeck, .conestoga, .oversized, .lowboy,
             .railFlatcar, .railCenterbeam, .railGondola, .railHopper,
             .railAutoRack, .vesselRoRo:
            return "flatbed"
        case .container, .railCOFC, .railIntermodal,
             .vesselContainer, .vesselBulk:
            return "hazmat_van"
        case .railTOFC:
            return "flatbed"
        }
    }

    // MARK: - 49 CFR hazmat tables (mirror of server _core/hazmatConstants.ts)

    /// Trailer code → allowed hazmat classes. Mirrors
    /// `TRAILER_HAZMAT_ALLOWED` server-side; both sides must agree
    /// or the wizard's pre-flight check and the server's create
    /// check will disagree.
    // 2026-06-03 — corrected per 25-agent multimodal compliance research
    // (_EQUIPMENT_REQUIREMENTS_MATRIX_*). ROOT CAUSE of "I can't go to the
    // next screen": dry_van/reefer/flatbed previously allowed ONLY ["9"], so
    // any non-Class-9 packaged DG on a van/reefer/open-deck/rail/RoRo/ISO load
    // hard-blocked Continue — factually wrong, since packaged/placarded DG of
    // essentially every class is legal in those units per 49 CFR 173/174/177 +
    // IMDG. Equipment restriction only genuinely applies to BULK-in-tank. These
    // lists now drive an ADVISORY warning only — canAdvance no longer hard-gates
    // on them (see canAdvance). The full packaged set:
    fileprivate static let allPackagedClasses: [String] = [
        "1", "1.1", "1.2", "1.3", "1.4", "1.5", "1.6",
        "2.1", "2.2", "2.3", "3", "4.1", "4.2", "4.3",
        "5.1", "5.2", "6.1", "6.2", "7", "8", "9",
    ]
    fileprivate static let trailerHazmatAllowed: [String: [String]] = [
        // Bulk-in-tank: genuine spec restrictions (these stay meaningful).
        "liquid_tank": ["2.1", "2.2", "2.3", "3", "4.3", "5.1", "5.2", "6.1", "6.2", "8", "9"],
        "gas_tank":    ["2.1", "2.2", "2.3"],
        // Packaged-freight units carry essentially any class with proper
        // packaging + securement + placarding.
        "hazmat_van":  allPackagedClasses,
        "dry_van":     allPackagedClasses,                                  // boxcar/van: 49 CFR 173/174
        "flatbed":     allPackagedClasses,                                  // open deck: 393 securement + placard
        "reefer":      ["2.2", "3", "4.1", "5.2", "6.1", "6.2", "8", "9"],  // temp-controlled classes
    ]

    /// 49 CFR 177.848 — for each hazmat class, the list of classes
    /// it CANNOT be co-loaded with on the same vehicle. Mirrors the
    /// `SEGREGATION_TABLE` in server _core/hazmatConstants.ts so the
    /// wizard's pre-flight and the server's compartment check use
    /// the same truth table.
    fileprivate static let hazmatSegregationTable: [String: [String]] = [
        "1":   ["2.1","2.2","2.3","3","4.1","4.2","4.3","5.1","5.2","6.1","7","8"],
        "1.1": ["2.1","2.3","3","4.1","4.2","4.3","5.1","5.2","6.1","7","8"],
        "2.1": ["1","1.1","2.3","3","4.1","4.2","4.3","5.1","5.2","6.1","7","8"],
        "2.3": ["1.1","2.1","3","4.1","4.2","4.3","5.1","5.2","6.1","8"],
        "3":   ["1","1.1","2.1","2.3","4.1","4.3","5.1","5.2","6.1","7","8"],
        "4.1": ["1","1.1","2.1","2.3","3","4.3","5.1","5.2","6.1","7","8"],
        "4.2": ["1","1.1","2.1","2.3","3","5.1","5.2","7","8"],
        "4.3": ["1","1.1","2.1","2.3","3","4.1","5.1","5.2","6.1","7","8"],
        "5.1": ["1","1.1","2.1","2.3","3","4.1","4.2","4.3","6.1","7","8"],
        "5.2": ["1","1.1","2.1","2.3","3","4.1","4.2","4.3","6.1","7"],
        "6.1": ["1","1.1","2.1","2.3","3","4.1","4.3","5.1","5.2","7","8"],
        "7":   ["1","1.1","2.1","3","4.1","4.2","4.3","5.1","5.2","6.1","8"],
        "8":   ["1","1.1","2.1","2.3","3","4.1","4.2","4.3","5.1","6.1","7"],
    ]

    /// Given a primary hazmat class, return the list of all known
    /// classes that ARE allowed to be co-loaded. Used by the hazmat
    /// compliance card to surface the "Compatible co-loads" advisory
    /// when the user is shipping a hazmat tanker (single-compartment
    /// today; multi-compartment when that UI lands).
    fileprivate static func compatibleHazmatClasses(for cls: String) -> [String] {
        let allKnown = ["1","1.1","2.1","2.2","2.3","3","4.1","4.2","4.3","5.1","5.2","6.1","6.2","7","8","9"]
        let forbidden = Set(hazmatSegregationTable[cls] ?? [])
        return allKnown.filter { $0 != cls && !forbidden.contains($0) }
    }

    /// Multi-compartment check, ready for when compartment UI lands.
    /// Returns the first incompatible pair found, or nil when every
    /// pair in the list is mutually compatible. Pass `(class, label)`
    /// tuples so the caller can format the violation with cargo names.
    fileprivate static func firstSegregationViolation(
        _ compartments: [(hazmatClass: String, label: String)]
    ) -> (a: String, b: String, aLabel: String, bLabel: String)? {
        for i in 0..<compartments.count {
            for j in (i + 1)..<compartments.count {
                let a = compartments[i].hazmatClass
                let b = compartments[j].hazmatClass
                if let forbidden = hazmatSegregationTable[a], forbidden.contains(b) {
                    return (a, b, compartments[i].label, compartments[j].label)
                }
            }
        }
        return nil
    }

    /// Compute CDL endorsement letters for the lane: H (hazmat),
    /// N (tanker), X (combined H+N).
    fileprivate static func requiredCdlEndorsements(hazmatClass: String, trailerCode: String) -> [String] {
        let isTank = trailerCode.contains("tank")
        if !hazmatClass.isEmpty && isTank { return ["X"] }
        var out: [String] = []
        if !hazmatClass.isEmpty { out.append("H") }
        if isTank { out.append("N") }
        return out.isEmpty ? ["-"] : out
    }

    /// Human-readable list of equipment labels that accept the
    /// given hazmat class. Used to recommend a compatible trailer
    /// when the user picked an incompatible one.
    fileprivate static func equipmentLabels(forHazmatClass cls: String) -> [String] {
        var matches: [String] = []
        for (code, allowed) in trailerHazmatAllowed where allowed.contains(cls) {
            switch code {
            case "liquid_tank": matches.append("Tanker · Petroleum / Liquid")
            case "gas_tank":    matches.append("Tanker · Gas")
            case "hazmat_van":  matches.append("Hazmat van / Container")
            case "dry_van":     matches.append("Dry van")
            case "reefer":      matches.append("Reefer")
            case "flatbed":     matches.append("Flatbed / Step deck")
            default:            break
            }
        }
        return matches.isEmpty ? ["-"] : matches
    }

    /// Equipment-type picker — covers truck / rail / vessel
    /// verticals + every product type (dry van, reefer, flatbed,
    /// step deck, conestoga, container, tanker variants, power-only,
    /// oversized, rail TOFC/COFC/intermodal, vessel container/bulk/
    /// tanker). Web parity with the LoadEquipmentType enum on the
    /// server (serialized to `equipmentType` on `shippers.create`).
    private var equipmentTypePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("EQUIPMENT TYPE")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                // 2026-05-23 — read from transportMode (the chip-strip
                // filter source of truth), not equipmentType.vertical.
                // The two could drift after an autosave restore where
                // equipmentType retained a vessel value but the new
                // session's mode was truck. Founder VESSEL-ghost bug.
                Text(transportMode.displayName.uppercased())
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            // ESANG Equipment Recommender — Tier 2 #40 ship 2026-05-21.
            // Fires once cargo description + weight are filled in.
            // Tap a recommendation row to apply it as the active
            // equipment choice.
            EquipmentRecommenderWidget(
                commodity: equipmentRecommenderCommodityString(),
                weightLbs: parseWeightLbs(weightText, unit: weightUnit) > 0
                    ? Int(parseWeightLbs(weightText, unit: weightUnit))
                    : nil,
                vertical: equipmentRecommenderVerticalString(),
                companyId: Int(session.user?.companyId ?? ""),
                originState: originStateCode,
                destState: destStateCode,
                isOverdimensional: equipmentType == .oversized
                    || equipmentType == .lowboy,
                cargoTypeRaw: cargoType.rawValue,
                hazmatUnNumber: unNumber,
                hazmatClass: hazmatClass,
                hazmatPackingGroup: packingGroup,
                // Rest of the hazmat profile — proper shipping name +
                // the ERG-resolved guide number and inhalation-hazard
                // flag — so ESANG reasons on the actual substance for
                // ANY material, not just whatever UN id was typed.
                hazmatProperShippingName: properShippingName,
                hazmatErgGuide: ergMatch?.guideNumber.map(String.init) ?? "",
                hazmatInhalationHazard: ergMatch?.isTIH ?? false,
                // Per-vertical profile: reefer setpoint + oversized dims
                // the user entered, so recs are vertical-aware (reefer
                // trailer for refrigerated, RGN/lowboy for oversized),
                // not just cargo-category-aware.
                reeferTempLow: reeferTempLowText,
                reeferTempHigh: reeferTempHighText,
                oversizeLengthFt: Double(oversizeLengthText.trimmingCharacters(in: .whitespaces)),
                oversizeWidthFt: Double(oversizeWidthText.trimmingCharacters(in: .whitespaces)),
                oversizeHeightFt: Double(oversizeHeightText.trimmingCharacters(in: .whitespaces)),
                onApply: { applyRecommendedTrailerKey($0) },
                currentSelection: equipmentType.rawValue
            )
            // ScrollViewReader wraps the horizontal chip strip so we
            // can `scrollTo` the selected equipment chip whenever
            // `equipmentType` changes — including the cascade from a
            // cargo-driven auto-snap. Without this, picking Vessel
            // Tanker from `autoSnapEquipmentForCargo(.petroleum)`
            // leaves the visible chips on Dry Van / Reefer / Flatbed
            // and the user can't see why VESSEL lit up in the corner
            // label.
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // 2026-05-17 — mode-filtered chip set. Picking
                        // Rail on Step 1 collapses the chip strip to
                        // rail equipment only; Vessel → vessel; Truck/
                        // Barge → truck. Keeps the user inside a
                        // coherent mental model and forces autoSnap
                        // to do the right thing if they change modes.
                        ForEach(EquipmentChoice.allCases.filter { $0.compatible(with: transportMode) }) { choice in
                            Button {
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                                    equipmentType = choice
                                }
                            } label: {
                                equipmentChip(for: choice)
                            }
                            .buttonStyle(.plain)
                            .disabled(isSubmitting)
                            .id(choice)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear {
                    // Bring the active chip into view on first render
                    // so the user immediately sees their hydrated
                    // draft selection (e.g., a Vessel Tanker draft
                    // restored from iCloud).
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(equipmentType, anchor: .center)
                        }
                    }
                }
                .onChange(of: equipmentType) { _, newValue in
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func equipmentChip(for choice: EquipmentChoice) -> some View {
        let on = (equipmentType == choice)
        HStack(spacing: 6) {
            Image(systemName: choice.systemImage)
                .font(.system(size: 10, weight: .heavy))
            Text(choice.label)
                .font(.system(size: 11, weight: .heavy)).tracking(0.4)
        }
        .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(palette.textSecondary))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(on ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard)))
        .overlay(Capsule().strokeBorder(on ? AnyShapeStyle(.clear) : AnyShapeStyle(palette.borderFaint), lineWidth: 1))
    }

    /// Cargo-type-specific equipment subform. Web parity (founder ask
    /// 2026-05-07): hazmat tanker needs hose specs / fittings; reefer
    /// needs temp range + pre-cool flag; flatbed needs straps / tarps;
    /// chemicals + gas + petroleum extend the hazmat shape.
    /// State lives on @State vars below — they all flow into the
    /// `shippers.create` payload at submit time so the catalyst's
    /// driver knows what gear they need.
    /// Live equipment animation — silhouette + ambient motion that
    /// reacts to every wizard selection (cargo type, equipment type,
    /// hazmat, hose spec, reefer temp range / pre-cool / continuous,
    /// flatbed straps / tarps / chains / edge protectors, oversized
    /// permits, ERG match). Doctrine: tanker silhouette never paints
    /// on a dry-van load; hazmat is a variant, not the default.
    @ViewBuilder
    private var equipmentAnimation: some View {
        EquipmentAnimation(
            equipment: equipmentType.animationKind,
            cargo: cargoType.animationKind,
            weightUnit: weightUnit.rawValue,
            tankerHose: tankerHoseSpec,
            isHazmat: cargoType == .hazmat || cargoType == .petroleum
                       || cargoType == .chemicals || cargoType == .gas
                       || equipmentType == .tankerHazmat,
            ergMatched: ergMatch?.found == true,
            hazmatClassText: hazmatClass,
            unNumberText: unNumber,
            commodityName: ergMatch?.name ?? properShippingName,
            reeferLowText: reeferTempLowText,
            reeferHighText: reeferTempHighText,
            preCoolRequired: preCoolRequired,
            continuousMode: continuousMode,
            flatbedStraps: flatbedStraps,
            flatbedTarps: flatbedTarps,
            flatbedChains: flatbedChains,
            flatbedEdgeProtectors: flatbedEdgeProtectors,
            oversizePermits: oversizePermits,
            // COUNTRY DIMENSION (Wave C): a load being posted is by
            // definition on its origin leg, so the preview renders the
            // ORIGIN state's regulatory group (DOT vs SCT vs TDG placards,
            // credentials, units) — resolved via the same state→country
            // rule the server uses to mint loads.originCountry. An
            // un-geocoded / unknown origin renders the US default.
            country: LoadAnimationContext.svgCountry(
                forState: (originStateCode?.isEmpty == false)
                    ? originStateCode
                    : Self.stateFromLane(origin)
            )
        )
        .frame(height: 180)
    }

    // Founder bug 2026-06-01: every vessel-side liquid/gas carrier
    // (LNG, ISO tank, tanker) used to fall to `default: EmptyView()`,
    // so for a Vessel · LNG · Gas selection the subform vanished
    // and Step 3 of 4 had no hazmat fields to fill in (blocked
    // Continue). Equivalent fall-throughs existed for rail tank
    // cars and rail reefer / centerbeam / gondola / flatcar.
    @ViewBuilder
    private var equipmentSubform: some View {
        // Animation always renders — silhouette adapts to every
        // equipment + product choice. Subform-specific cards stack
        // beneath the animation.
        equipmentAnimation
        // Comprehensive, mode/vertical/country-correct requirement options
        // for EVERY one of the 33 equipment types (data-driven catalog). This
        // replaces the old `default: EmptyView()` (18+ types had no form) and
        // gives tankers their REAL per-mode connections (vessel flanges, rail
        // BOV, ISO T-codes) instead of blanket truck cam-locks.
        catalogRequirementsSection
        switch equipmentType {
        case .reefer, .railReeferBoxcar, .vesselReeferContainer:
            reeferSubform   // structured LOW/HIGH temperature window
        default:
            EmptyView()
        }
        // SINGLE commodity / dangerous-goods identity block — shown for
        // EVERY equipment type, sourced once from the structured fields.
        // The per-equipment catalog no longer asks commodity or hazmat
        // class (those groups were removed), so this is the only place
        // the load's product + UN/Class/PG/PSN is captured:
        //   • hazmat-flavored cargo → universal Dangerous-goods card
        //     (UN / Class / PG / PSN + ERG lookup, the sole owner of
        //     {UN, hazmatClass, packingGroup, PSN}).
        //   • non-hazmat cargo      → ERG-parity commodity lookup
        //     (chemical / petroleum / reefer / container / STCC).
        if cargoType.isHazmatFlavored {
            dangerousGoodsCard
        } else {
            commodityLookupCard
        }
        // 2026-08-07 — the attestation itself, on EVERY cargo type. The
        // cards above capture the cargo's IDENTITY; this captures the
        // poster's legal DETERMINATION about it plus the evidence behind
        // it. `shippers.create` requires it either way, and a hazmat chip
        // is not a classification.
        cargoClassificationCard
    }

    // MARK: - Cargo-classification attestation (shared primitive)

    /// The one attestation control, shared with the 250-259 wizard and the
    /// recurring composer. This screen already owns the regulated identity
    /// fields (UN / class / PG / proper shipping name) on the Dangerous-goods
    /// card, so it declares them as host-captured and the control does not
    /// ask for them twice.
    private var cargoClassificationCard: some View {
        CargoClassificationAttestationCard(
            attestation: $cargoAttestation,
            context: cargoClassificationContext,
            hostCaptures: [.unNumber, .hazmatClass, .properShippingName, .packingGroup]
        )
    }

    /// The load facts the server's classification assessor needs that this
    /// attestation does not own, so the missing-input list the shipper reads
    /// is the same list the server would return.
    private var cargoClassificationContext: CargoClassificationAttestation.CargoContext {
        CargoClassificationAttestation.CargoContext(
            productName: properShippingName.trimmingCharacters(in: .whitespacesAndNewlines),
            equipmentType: equipmentType.rawValue,
            transportMode: transportMode.rawValue,
            quantity: parseDouble(weightText),
            quantityUnit: weightUnit.rawValue
        )
    }

    /// Digest of the host-owned regulated identity. Drives the one-way
    /// mirror below.
    private var cargoIdentityDigest: String {
        [unNumber, hazmatClass, packingGroup, properShippingName,
         cargoType.rawValue].joined(separator: "\u{1F}")
    }

    /// Mirror the identity the poster typed on THIS screen into the
    /// attestation, so the attestation stays the single wire source of truth
    /// and the shipper never types the same field twice.
    ///
    /// `properShippingName` is only mirrored for hazmat-flavored cargo. On a
    /// general load that same text field holds the plain commodity name (it
    /// is what feeds `productName`), and a commodity name is not a 49 CFR
    /// 172.101 proper shipping name. Mirroring it would put a regulated
    /// identifier on a not-regulated load and the server would — correctly —
    /// refuse the post.
    private func mirrorCargoIdentityIntoAttestation() {
        cargoAttestation.unNumber = unNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        cargoAttestation.hazmatClass = hazmatClass.trimmingCharacters(in: .whitespacesAndNewlines)
        cargoAttestation.properShippingName = cargoType.isHazmatFlavored
            ? properShippingName.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let pg = packingGroup.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        cargoAttestation.packingGroup = CargoClassificationAttestation.PackingGroup(rawValue: pg)
    }

    /// Honest, specific reason the Post button is dark. Nil when the
    /// attestation is complete.
    private var cargoClassificationBlockReason: String? {
        cargoAttestation.blockReason(context: cargoClassificationContext)
    }

    // MARK: - Data-driven equipment requirements (all 33 equipment types)

    private func equipReqIsOther(_ o: EquipReqOption) -> Bool {
        let l = o.label.lowercased(); return l.contains("other") && l.contains("specify")
    }
    private func equipReqToggle(_ groupKey: String, _ optKey: String) {
        var s = equipReqSel[groupKey] ?? []
        if s.contains(optKey) { s.remove(optKey) } else { s.insert(optKey) }
        equipReqSel[groupKey] = s
    }
    private func equipReqGroupHasOther(_ g: EquipReqGroup) -> Bool {
        guard let sel = equipReqSel[g.key] else { return false }
        return g.options.contains { sel.contains($0.key) && equipReqIsOther($0) }
    }

    @ViewBuilder
    private var catalogRequirementsSection: some View {
        let raw = equipmentType.rawValue
        let groups = EquipmentRequirementsCatalog.groups(forRaw: raw)
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: Space.s3) {
                if let h = EquipmentRequirementsCatalog.header(forRaw: raw) {
                    HStack(spacing: 6) {
                        Image(systemName: "checklist")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text(h.uppercased())
                            .font(EType.micro).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                ForEach(groups) { g in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(g.label.uppercased())
                            .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(palette.textSecondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)],
                                  alignment: .leading, spacing: 6) {
                            ForEach(g.options) { o in
                                let sel = (equipReqSel[g.key] ?? []).contains(o.key)
                                Button { equipReqToggle(g.key, o.key) } label: {
                                    Text(o.label)
                                        .font(.system(size: 11, weight: .semibold))
                                        .lineLimit(2).multilineTextAlignment(.leading)
                                        .minimumScaleFactor(0.8)
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Capsule().fill(sel
                                            ? AnyShapeStyle(LinearGradient.diagonal)
                                            : AnyShapeStyle(palette.bgCardSoft)))
                                        .foregroundStyle(sel
                                            ? AnyShapeStyle(Color.white)
                                            : AnyShapeStyle(palette.textPrimary))
                                        .overlay(Capsule().strokeBorder(sel
                                            ? AnyShapeStyle(Color.clear)
                                            : AnyShapeStyle(palette.borderFaint), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if equipReqGroupHasOther(g) {
                            TextField("Specify…", text: Binding(
                                get: { equipReqOther[g.key] ?? "" },
                                set: { equipReqOther[g.key] = $0 }))
                                .font(EType.body)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .fill(palette.bgCardSoft))
                        }
                    }
                }
                if let c = EquipmentRequirementsCatalog.citation(forRaw: raw), !c.isEmpty {
                    Text(c)
                        .font(.system(size: 9))
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal.opacity(0.35), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: universal Dangerous-goods card (any equipment · hazmat-flavored cargo)

    /// THE single owner of the load's {UN, hazmatClass, packingGroup,
    /// PSN} for hazmat-flavored cargo on ANY equipment. The per-
    /// equipment catalog no longer asks hazmat class anywhere, so this
    /// card is the only place the dangerous-goods identity is captured.
    /// The ERG lookup auto-fills class + PSN; the structured fields are
    /// the source of truth. Header reads the tanker-family context when
    /// the equipment is a tank, else a generic dangerous-goods label.
    @ViewBuilder
    private var dangerousGoodsCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "drop.triangle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(dangerousGoodsCardLabel)
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Divider().background(palette.borderFaint).padding(.vertical, 2)
            tankerHazmatRow
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    /// Header label for the Dangerous-goods card — surfaces the tanker-
    /// family paperwork context (MC-306 / IMO / MC-331) when the
    /// equipment is a tank, else a generic dangerous-goods header so a
    /// hazmat-flavored load on a dry van / flatbed / box still reads
    /// correctly.
    private var dangerousGoodsCardLabel: String {
        switch equipmentType {
        case .tankerHazmat, .tankerPetro, .tankerLiquid, .tankerGas,
             .vesselTanker, .vesselLNG, .vesselISOTank,
             .railTankLiquid, .railTankGas:
            return tankerSubformLabel
        default:
            return "DANGEROUS GOODS · 49 CFR 172"
        }
    }

    // MARK: universal Commodity-lookup card (any equipment · non-hazmat cargo)

    /// Which `commodity.*` proc serves the active (cargoType, equipment,
    /// mode) tuple. This is the ERG-parity dispatch: refrigerated →
    /// reefer, container equipment → ISO size-type, rail → STCC,
    /// petroleum → petroleum grades, everything else → chemical/product.
    /// Drives the card label, the placeholder, and the search call.
    private enum CommodityProc {
        case chemical, petroleum, reefer, containerType, stcc
    }

    private var activeCommodityProc: CommodityProc {
        // Petroleum is hazmat-flavored so this card won't render for it,
        // but the dispatch stays complete per spec.
        if cargoType == .petroleum { return .petroleum }
        if cargoType == .refrigerated
            || equipmentType == .reefer
            || equipmentType == .railReeferBoxcar
            || equipmentType == .vesselReeferContainer { return .reefer }
        switch equipmentType {
        case .container, .railTOFC, .railCOFC, .railIntermodal,
             .vesselContainer, .vesselReeferContainer:
            return .containerType
        default:
            break
        }
        if transportMode == .rail { return .stcc }
        return .chemical
    }

    private var commodityCardLabel: String {
        switch activeCommodityProc {
        case .chemical:      return "COMMODITY · PRODUCT LOOKUP"
        case .petroleum:     return "COMMODITY · PETROLEUM GRADE"
        case .reefer:        return "COMMODITY · PERISHABLE (REEFER)"
        case .containerType: return "COMMODITY · ISO CONTAINER TYPE"
        case .stcc:          return "COMMODITY · RAIL STCC"
        }
    }

    private var commodityCardPlaceholder: String {
        switch activeCommodityProc {
        case .chemical:      return "e.g. Latex resin"
        case .petroleum:     return "e.g. Diesel"
        case .reefer:        return "e.g. Fresh berries"
        case .containerType: return "e.g. 40' high cube"
        case .stcc:          return "e.g. Corn, grain"
        }
    }

    /// ERG-parity commodity card — shown for NON-hazmat cargo on any
    /// equipment. A typeahead row + a free-text product field, both
    /// pinned into `properShippingName` (the single commodity source of
    /// truth alongside the top cargoType chip). The reefer lookup also
    /// auto-fills `reeferTempLowText` / `reeferTempHighText`.
    @ViewBuilder
    private var commodityLookupCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(commodityCardLabel)
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                // Commodity search button — opens a typeahead sheet,
                // mirroring the ERG search row. Web parity with the
                // platform's `commodity.*` lookups.
                Button { showCommoditySearchSheet = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 9, weight: .heavy))
                        Text("Lookup")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    }
                    .foregroundStyle(LinearGradient.diagonal)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Divider().background(palette.borderFaint).padding(.vertical, 2)
            // Structured product field — same single PSN binding the
            // hazmat branch writes, so the load carries exactly one
            // commodity regardless of which card captured it.
            hazmatTextField(label: "Commodity / product",
                            text: $properShippingName,
                            placeholder: commodityCardPlaceholder,
                            width: nil)
            if isSearchingCommodity {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6).tint(LinearGradient.diagonal)
                    Text("Looking up commodity…")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            } else if let m = commodityMatch {
                commodityMatchChip(m)
            } else if let err = commodityLookupError {
                Text(err)
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    /// Compact "commodity matched" chip — product name + category +
    /// (for reefer) the recommended temp band. Mirrors `ergMatchChip`.
    @ViewBuilder
    private func commodityMatchChip(_ m: CommodityLookupAPI.CommodityHit) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.name)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(commodityMatchSubtitle(m))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }

    private func commodityMatchSubtitle(_ m: CommodityLookupAPI.CommodityHit) -> String {
        var bits: [String] = []
        if let code = m.code, !code.isEmpty { bits.append(code) }
        if let cat = m.category, !cat.isEmpty { bits.append(cat) }
        if let lo = m.tempLowF, let hi = m.tempHighF {
            bits.append("\(Int(lo))–\(Int(hi)) °F")
        }
        if let note = m.note, !note.isEmpty { bits.append(note) }
        return bits.isEmpty ? "Selected" : bits.joined(separator: " · ")
    }

    @ViewBuilder
    private var tankerHazmatRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Brand.warning)
                Text("HAZMAT · 49 CFR 172")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                // ERG search button — opens a typeahead sheet so the
                // user can find any UN material by name when they
                // don't know the number. Web parity with the
                // platform's `erg.search`.
                Button { showErgSearchSheet = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 9, weight: .heavy))
                        Text("ERG search")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    }
                    .foregroundStyle(LinearGradient.diagonal)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                hazmatTextField(label: "UN", text: $unNumber, placeholder: "UN1267", width: 90)
                hazmatTextField(label: "Class", text: $hazmatClass, placeholder: "3", width: 80)
                hazmatTextField(label: "PG", text: $packingGroup, placeholder: "II", width: 70)
            }
            hazmatTextField(label: "Proper shipping name",
                            text: $properShippingName,
                            placeholder: "Crude oil",
                            width: nil)
            // Live ERG match chip — prefilled by `erg.searchByUN`.
            if isLookingUpERG {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6).tint(LinearGradient.diagonal)
                    Text("Looking up UN in ERG database…")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            } else if let m = ergMatch, m.found {
                ergMatchChip(m)
            } else if let err = ergLookupError {
                Text(err)
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
            }
        }
    }

    /// Compact "ERG matched" chip — material name + guide # + TIH /
    /// water-reactive flags. Tapping opens the existing 096 ERG
    /// detail surface for the full guide page.
    @ViewBuilder
    private func ergMatchChip(_ m: ErgAPI.MaterialDetail) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text((m.name ?? "-").capitalized)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    if m.isTIH == true {
                        Text("TIH")
                            .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Brand.danger))
                    }
                    if m.isWR == true {
                        Text("WR")
                            .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Brand.info))
                    }
                }
                Text(ergMatchSubtitle(m))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }

    private func ergMatchSubtitle(_ m: ErgAPI.MaterialDetail) -> String {
        var bits: [String] = []
        if let g = m.guideNumber { bits.append("Guide \(g)") }
        if let c = m.hazardClass { bits.append("Class \(c)") }
        if let p = m.placard, !p.isEmpty { bits.append(p) }
        return bits.joined(separator: " · ")
    }

    @ViewBuilder
    private func tankerChip(label: String, selected: Bool) -> some View {
        Button {
            toggleTankerSpec(label: label)
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(palette.textSecondary))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(selected ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCardSoft)))
                .overlay(Capsule().strokeBorder(selected ? AnyShapeStyle(.clear) : AnyShapeStyle(palette.borderFaint), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Header label for the tanker subform — distinguishes the four
    /// real tanker contexts so the user doesn't see "TANKER · HAZMAT
    /// REQUIREMENTS" on a Vessel-Tanker with food-grade petroleum or
    /// on a tanker_gas/tanker_liquid pull. The label drives the
    /// catalyst's dispatcher to the right paperwork pack (MC-306 truck
    /// vs IMO 2/IMO 3 vessel cert vs MC-331 cryo gas).
    private var tankerSubformLabel: String {
        switch (equipmentType, cargoType.isHazmatFlavored) {
        case (.vesselTanker, true):  return "VESSEL TANKER · HAZMAT REQUIREMENTS"
        case (.vesselTanker, false): return "VESSEL TANKER REQUIREMENTS"
        case (.tankerHazmat, _):     return "TANKER · HAZMAT (DOT-407) REQUIREMENTS"
        case (.tankerPetro, _):      return "TANKER · PETROLEUM (MC-306) REQUIREMENTS"
        case (.tankerLiquid, true):  return "TANKER · LIQUID BULK (MC-307) · HAZMAT"
        case (.tankerLiquid, false): return "TANKER · LIQUID BULK (MC-307) REQUIREMENTS"
        case (.tankerGas, _):        return "TANKER · GAS/CRYO (MC-331) REQUIREMENTS"
        default:                     return "TANKER REQUIREMENTS"
        }
    }

    private func toggleTankerSpec(label: String) {
        let key: String
        switch label {
        case "2\" cam-lock":     key = "2_camlock"
        case "3\" cam-lock":     key = "3_camlock"
        case "4\" cam-lock":     key = "4_camlock"
        case "Dry-disconnect":   key = "dry_disconnect"
        case "API adapter":      key = "api"
        case "TTMA":             key = "ttma"
        case "Other":            key = "other"
        default:                 return
        }
        if ["2_camlock", "3_camlock", "4_camlock", "dry_disconnect"].contains(key) {
            tankerHoseSpec = (tankerHoseSpec == key) ? "" : key
        } else {
            tankerFitting = (tankerFitting == key) ? "" : key
        }
    }

    @ViewBuilder
    private func hazmatTextField(label: String,
                                 text: Binding<String>,
                                 placeholder: String,
                                 width: CGFloat?) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(EType.micro).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
            TextField(placeholder, text: text)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .tint(LinearGradient.diagonal)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(width: width, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    // MARK: reefer subform

    @ViewBuilder
    private var reeferSubform: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "thermometer.snowflake")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("REEFER REQUIREMENTS")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                // 2026-05-17 — Surface the expected commodity band
                // (frozen / chilled / ambient) so the user sees the
                // target temp window for the cargo they're shipping
                // before they type the actual range.
                if let band = reeferTargetBand {
                    Text(band.label)
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(band.tint))
                }
            }
            HStack(spacing: 8) {
                reeferTempField(label: "LOW °F",  binding: $reeferTempLowText,  placeholder: "33")
                reeferTempField(label: "HIGH °F", binding: $reeferTempHighText, placeholder: "40")
            }
            // 2026-05-17 — Inline validation card. Renders only when
            // the typed range has something wrong: low ≥ high, range
            // exceeds reefer hardware (-30°F to 80°F), or range doesn't
            // overlap the cargo's expected commodity band. Doctrine:
            // catch the error here, not at delivery when a frozen load
            // melted because the user typed 50°F.
            if let issue = reeferRangeIssue {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Brand.warning)
                    Text(issue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Brand.warning.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(Brand.warning.opacity(0.35), lineWidth: 1)
                )
            }
            Toggle("Pre-cool required",
                   isOn: $preCoolRequired.animation(.spring(response: 0.22, dampingFraction: 0.85)))
                .toggleStyle(GradientToggleStyle())
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Toggle("Continuous mode",
                   isOn: $continuousMode.animation(.spring(response: 0.22, dampingFraction: 0.85)))
                .toggleStyle(GradientToggleStyle())
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    /// One of three FDA-aligned reefer bands. Renders as a small pill
    /// in the reefer subform header so the user knows which window
    /// applies to their cargo before they type.
    private struct ReeferBand {
        let label: String
        let lowF: Double
        let highF: Double
        let tint: Color
    }

    /// Pick a temperature band from the selected cargo + commodity.
    /// Frozen for proteins / ice cream / frozen fish, chilled for
    /// fresh produce + dairy, ambient for shelf-stable. Returns nil
    /// for non-refrigerated cargo so the pill doesn't render.
    private var reeferTargetBand: ReeferBand? {
        guard equipmentType == .reefer else { return nil }
        let commodity = properShippingName.lowercased()
        let frozenKeywords  = ["frozen", "ice cream", "ice-cream", "icecream"]
        let chilledKeywords = ["produce", "fresh", "dairy", "milk", "berries", "lettuce", "fish", "seafood", "poultry", "beef", "pork"]
        let ambientKeywords = ["pharma", "wine", "chocolate", "ambient"]
        if frozenKeywords.contains(where: commodity.contains) {
            return ReeferBand(label: "FROZEN -20 to 0 °F", lowF: -20, highF: 0, tint: Brand.blue)
        }
        if chilledKeywords.contains(where: commodity.contains) {
            return ReeferBand(label: "CHILLED 32 to 40 °F", lowF: 32, highF: 40, tint: Brand.info)
        }
        if ambientKeywords.contains(where: commodity.contains) {
            return ReeferBand(label: "AMBIENT 50 to 70 °F", lowF: 50, highF: 70, tint: Brand.success)
        }
        // Cargo type alone: refrigerated → chilled by default.
        if cargoType == .refrigerated {
            return ReeferBand(label: "CHILLED 32 to 40 °F", lowF: 32, highF: 40, tint: Brand.info)
        }
        return nil
    }

    /// Return a one-line issue string when the typed range is wrong,
    /// or nil when everything is fine (including the no-input case).
    /// Order of checks: parseability → hardware range → low<high →
    /// band overlap.
    private var reeferRangeIssue: String? {
        let lowStr  = reeferTempLowText.trimmingCharacters(in: .whitespaces)
        let highStr = reeferTempHighText.trimmingCharacters(in: .whitespaces)
        if lowStr.isEmpty && highStr.isEmpty { return nil }
        guard let low = Double(lowStr), let high = Double(highStr) else {
            return "Enter numeric °F values for both LOW and HIGH."
        }
        // Reefer trailer hardware envelope (Carrier / Thermo King
        // standard units operate ~-30°F to ~80°F).
        if low < -30 { return "Low temp \(Int(low))°F is below the reefer hardware floor (-30°F)." }
        if high > 80 { return "High temp \(Int(high))°F exceeds the reefer hardware ceiling (80°F)." }
        if low > high { return "Low temp must be less than or equal to high temp." }
        if let band = reeferTargetBand {
            // No overlap = the range is wrong for the commodity.
            if high < band.lowF || low > band.highF {
                return "\(Int(low))–\(Int(high))°F does not overlap the \(band.label) window. Verify cargo + temp."
            }
        }
        return nil
    }

    @ViewBuilder
    private func reeferTempField(label: String,
                                 binding: Binding<String>,
                                 placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 4) {
                TextField(placeholder, text: binding)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .tint(LinearGradient.diagonal)
                    .keyboardType(.numbersAndPunctuation)
                    .frame(width: 60)
                Text("°F")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
    }

    // MARK: flatbed subform

    @ViewBuilder
    private var flatbedSubform: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.expand.vertical")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("FLATBED · OVERSIZED REQUIREMENTS")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 8) {
                flatbedFlag(title: "Straps", selected: flatbedStraps)
                    .onTapGesture { flatbedStraps.toggle() }
                flatbedFlag(title: "Tarps", selected: flatbedTarps)
                    .onTapGesture { flatbedTarps.toggle() }
                flatbedFlag(title: "Chains", selected: flatbedChains)
                    .onTapGesture { flatbedChains.toggle() }
                flatbedFlag(title: "Edge protectors", selected: flatbedEdgeProtectors)
                    .onTapGesture { flatbedEdgeProtectors.toggle() }
            }
            HStack(spacing: 8) {
                hazmatTextField(label: "Length (ft)", text: $oversizeLengthText, placeholder: "53", width: 110)
                hazmatTextField(label: "Width (ft)",  text: $oversizeWidthText,  placeholder: "8.5", width: 110)
            }
            HStack(spacing: 8) {
                hazmatTextField(label: "Height (ft)", text: $oversizeHeightText, placeholder: "13.5", width: 110)
                Toggle("Permits required",
                       isOn: $oversizePermits.animation(.spring(response: 0.22, dampingFraction: 0.85)))
                    .toggleStyle(GradientToggleStyle())
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
            }
            // Permit Type — only shows when `oversizePermits` is on.
            // Wired to permitType state so the catalyst's dispatcher
            // knows which DOT filing to book against (trip / annual /
            // superload / overweight-only / hazmat-routed). Default
            // .none = no permit needed.
            if oversizePermits {
                permitTypePicker
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    /// Permit-type chip strip. Surfaces the four real permit families
    /// a US oversized carrier books against state DOTs plus the
    /// hazmat-route corridor permit. Drives the eventual filing
    /// downstream of `shippers.create`.
    @ViewBuilder
    private var permitTypePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.badge.gearshape")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("PERMIT TYPE")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text(permitType.hint)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PermitType.allCases) { type in
                        Button {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                                permitType = type
                            }
                        } label: {
                            permitChip(for: type)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSubmitting)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func permitChip(for type: PermitType) -> some View {
        let on = (permitType == type)
        HStack(spacing: 5) {
            Image(systemName: type.systemImage)
                .font(.system(size: 9, weight: .heavy))
            Text(type.label)
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
        }
        .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(palette.textSecondary))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(on ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCardSoft)))
        .overlay(Capsule().strokeBorder(on ? AnyShapeStyle(.clear) : AnyShapeStyle(palette.borderFaint), lineWidth: 1))
    }

    @ViewBuilder
    private func flatbedFlag(title: String, selected: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(selected ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
            Text(title)
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(selected ? AnyShapeStyle(palette.textPrimary) : AnyShapeStyle(palette.textSecondary))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(palette.bgCardSoft))
        .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    private var cargoTypePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("CARGO TYPE")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                // Mirror the EQUIPMENT TYPE eyebrow — show the active
                // mode so the user understands why this chip strip
                // shrank from 8 to whatever subset rail / vessel /
                // barge accept.
                Text(transportMode.displayName.uppercased())
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            // ScrollViewReader so the selected cargo chip auto-centers
            // on equipment-driven auto-snap (Reefer picked → cargo
            // jumps to refrigerated → chip scrolls into view).
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // 2026-05-18 — mode-filtered cargo strip. Rail
                        // surfaces all 8, vessel drops oversized (RoRo
                        // covers it under General), barge drops reefer
                        // + gas + oversized. Truck keeps the full set.
                        ForEach(ShipperAPI.CargoType.allCases.filter { transportMode.acceptsCargo($0) }) { type in
                            Button {
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                                    cargoType = type
                                }
                            } label: {
                                cargoChip(for: type)
                            }
                            .buttonStyle(.plain)
                            .disabled(isSubmitting)
                            .id(type)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(cargoType, anchor: .center)
                        }
                    }
                }
                .onChange(of: cargoType) { _, newValue in
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cargoChip(for type: ShipperAPI.CargoType) -> some View {
        let on = (cargoType == type)
        HStack(spacing: 6) {
            Image(systemName: type.systemImage)
                .font(.system(size: 10, weight: .heavy))
            Text(type.label)
                .font(.system(size: 11, weight: .heavy)).tracking(0.4)
        }
        .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(palette.textSecondary))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(on ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard)))
        .overlay(Capsule().strokeBorder(on ? AnyShapeStyle(.clear) : AnyShapeStyle(palette.borderFaint), lineWidth: 1))
    }

    private var weightField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("QUANTITY")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text(unitGuidanceText)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: weightUnitIcon)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 18)
                TextField("0", text: $weightText)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .tint(LinearGradient.diagonal)
                    .keyboardType(.decimalPad)
                    .disabled(isSubmitting)
                weightUnitMenu
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

            // 2026-05-17 — multi-vehicle calculator advisory. Fires the
            // moment we have a parseable barrel quantity and a mode +
            // equipment. Symbiotic "how many vehicles do you need?" line
            // — answers the founder ask "[platform] symbiotic to user's
            // mind ... like a glove". Surfaced only for liquid bulk (bbl/
            // mt) flows; non-petroleum cargo (palletized / TEU) follow
            // in the next ship.
            if let estimate = multiVehicleEstimate {
                multiVehicleAdvisory(estimate)
            }
        }
        .onChange(of: equipmentType) { _, newValue in
            resyncWeightUnit()
            autoSnapCargoForEquipment(newValue)
        }
        .onChange(of: cargoType)     { _, newValue in
            resyncWeightUnit()
            autoSnapEquipmentForCargo(newValue)
            clearHazmatFieldsIfNoLongerHazmat(newValue)
        }
        .onChange(of: transportMode) { _, newMode in
            // Mode flip on Step 1 must propagate into Step 2: the
            // equipment chip strip already filters by mode (line 2416),
            // but if the user had already selected a truck-tanker on
            // Step 2 then switched to RAIL on Step 1, the "TRUCK"
            // eyebrow + truck animation would persist until they
            // manually picked a rail chip. Auto-snap closes the loop.
            autoSnapEquipmentForMode(newMode)
            // Cargo set may also need pruning — if the previously
            // chosen cargo isn't compatible with the new mode, snap
            // it to General which all modes accept.
            if !newMode.acceptsCargo(cargoType) {
                cargoType = .general
            }
        }
    }

    /// Compute the multi-vehicle estimate when we have a parseable
    /// barrel quantity (or convert from gallons → bbl) and a tanker-
    /// flavored equipment + mode. Returns nil when the inputs don't
    /// support an honest estimate — never fabricate a count.
    private var multiVehicleEstimate: LoadCapacityEstimate? {
        guard let qty = parseDouble(weightText), qty > 0 else { return nil }
        // Convert to barrels if the user typed gallons (42 gal = 1 bbl).
        let barrels: Double
        switch weightUnit {
        case .barrels: barrels = qty
        case .gallons: barrels = qty / 42.0
        case .liters:  barrels = qty / 158.987  // 1 bbl = 158.987 L
        default: return nil // weight-only / pallet-only / TEU flows — skip
        }
        // Only run for tanker-flavored equipment.
        let key: String
        switch equipmentType {
        case .tankerPetro:    key = "mc306_petroleum"
        case .tankerHazmat:   key = "mc307_chemical"
        case .tankerLiquid:   key = "mc306_petroleum"
        case .tankerGas:      key = "mc331_pressure"
        case .railTOFC, .railCOFC, .railIntermodal: key = "dot117_crude"
        case .vesselTanker:   key = "dot117_crude"  // unused for vessel branch
        default: return nil
        }
        return LoadCapacityCalculator.estimateCrude(
            barrels: barrels,
            mode: transportMode,
            equipmentKey: key,
            vesselClass: nil
        )
    }

    /// Symbiotic advisory card — surfaces vehicle count + utilization +
    /// (when impractical) suggested alt-mode. Tap-to-adopt the alt mode
    /// when ESANG suggests one (e.g. 1,870 trucks → switch to rail).
    @ViewBuilder
    private func multiVehicleAdvisory(_ est: LoadCapacityEstimate) -> some View {
        // Distinguish "we need more input from you" (e.g. vessel class
        // not yet picked) from "this mode is genuinely a bad fit for
        // this quantity". Founder bug 2026-05-31: the same warning
        // tint + "MODE MISMATCH" label was firing for both, scaring
        // shippers into thinking a coherent Vessel + Vessel-Tanker +
        // Hazmat combo was rejected when really the estimator was
        // waiting on the user to choose the vessel class.
        let needsMoreInput = !est.sensible && est.vehicleCount == 0
            && est.advisory.lowercased().contains("vessel class")
        let tint: Color = est.sensible ? Brand.success
                                       : (needsMoreInput ? Brand.info : Brand.warning)
        let iconName: String = est.sensible ? "checkmark.seal.fill"
                                            : (needsMoreInput ? "info.circle.fill" : "exclamationmark.triangle.fill")
        let label: String = est.sensible ? "VEHICLES NEEDED"
                                         : (needsMoreInput ? "PICK A VESSEL CLASS" : "MODE MISMATCH")
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                if est.vehicleCount > 0 {
                    Text("\(est.vehicleCount) × \(transportMode.displayName.lowercased())")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.4)
                        .foregroundStyle(palette.textPrimary)
                }
            }
            Text(est.advisory)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let alt = est.suggestedAltMode {
                Button {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                        transportMode = alt
                        autoSnapEquipmentForMode(alt)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: alt.sfSymbol)
                        Text("Switch to \(alt.displayName)")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(LinearGradient.diagonal))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
    }

    /// When the user picks an equipment type, propose the matching
    /// cargo type if the current one doesn't fit. Animated so the
    /// chip strip shifts visibly — telegraphs the cross-coupling so
    /// the user knows the change cascaded. No-ops for equipment that
    /// accepts any cargo (dry van, container, power-only, etc.).
    private func autoSnapCargoForEquipment(_ eq: EquipmentChoice) {
        guard let proposed = eq.defaultCargoType(currentCargo: cargoType) else { return }
        // Idempotency guard — never re-assign the same value. This snap and
        // `autoSnapEquipmentForCargo` are mutually triggered via the Step-2
        // `weightField` `.onChange(of:)` pair; assigning an equal value would
        // still open a `withAnimation` transaction and could re-enter the
        // companion handler. Only mutate on a real change so the ping-pong
        // always terminates.
        guard cargoType != proposed else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
            cargoType = proposed
        }
    }

    /// When the user picks a cargo type, propose the matching
    /// equipment type if the current one is incompatible. Refrigerated
    /// → reefer, petroleum → MC-306 tanker, etc. Keeps the equipment
    /// preview + animation + requirements subform aligned with the
    /// cargo selection (founder bug 2026-05-16: refrigerated chosen
    /// but vessel-tanker animation kept painting).
    private func autoSnapEquipmentForCargo(_ ct: ShipperAPI.CargoType) {
        guard let proposed = ct.defaultEquipment(currentEquipment: equipmentType, mode: transportMode) else { return }
        // Idempotency guard — see `autoSnapCargoForEquipment`. Only mutate on
        // a real change so the cargo↔equipment auto-snap pair can never
        // oscillate or re-enter.
        guard equipmentType != proposed else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
            equipmentType = proposed
        }
    }

    /// Companion to autoSnapEquipmentForCargo — fires when the
    /// Reset UN / hazard class / packing group / ERG match / hose
    /// configuration when the user pivots cargo away from a hazmat-
    /// flavored type. Without this, a UN1267 lookup from a previous
    /// petroleum draft stays cached on the wizard state and leaks
    /// into the equipment preview + the eventual `shippers.create`
    /// payload — exactly what showed up in the 2026-05-16 screenshot.
    private func clearHazmatFieldsIfNoLongerHazmat(_ ct: ShipperAPI.CargoType) {
        // Switching TO a non-hazmat cargo: drop the hazmat identity so a
        // stale UN/class/PG/PSN + ERG match can't leak onto a general /
        // reefer / oversized load. The commodity lookup re-pins PSN.
        if !ct.isHazmatFlavored {
            unNumber = ""
            hazmatClass = ""
            packingGroup = ""
            properShippingName = ""
            tankerHoseSpec = ""
            tankerFitting = ""
            ergMatch = nil
            ergLookupError = nil
            lastErgQueryKey = ""
            commodityMatch = nil
            commodityLookupError = nil
        } else {
            // Switching TO a hazmat-flavored cargo: drop a stale non-hazmat
            // commodity match (the ERG branch re-pins PSN on UN lookup) so
            // the two lookups never cross-contaminate.
            commodityMatch = nil
            commodityLookupError = nil
        }
    }

    /// Menu picker — surfaces the suggested unit list at the top
    /// (most-relevant for the current equipment + cargo combo) and
    /// the full list under "Other units" so any unit is reachable.
    private var weightUnitMenu: some View {
        Menu {
            Section("Suggested for \(equipmentType.label)") {
                ForEach(suggestedUnits) { u in
                    Button {
                        weightUnit = u
                    } label: {
                        if weightUnit == u {
                            Label(u.longLabel, systemImage: "checkmark")
                        } else {
                            Text(u.longLabel)
                        }
                    }
                }
            }
            Section("Other units") {
                ForEach(MeasurementUnit.allCases.filter { !suggestedUnits.contains($0) }) { u in
                    Button { weightUnit = u } label: {
                        Text(u.longLabel)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(weightUnit.label)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    /// SF Symbol that swaps with the unit so the icon reflects the
    /// physical reality of the chosen measurement.
    private var weightUnitIcon: String {
        switch weightUnit {
        case .pounds, .kilograms, .shortTons, .metricTons: return "scalemass.fill"
        case .gallons, .liters:                            return "drop.fill"
        case .barrels:                                     return "drop.triangle.fill"
        case .cubicMeters:                                 return "cube.fill"
        case .bushels:                                     return "leaf.fill"
        case .pallets:                                     return "shippingbox.fill"
        case .cases, .cartons:                             return "shippingbox.and.arrow.backward.fill"
        case .rolls, .bundles:                             return "rectangle.stack.fill"
        case .feu, .teu:                                   return "cube.box.fill"
        case .pieces:                                      return "number"
        }
    }

    /// Hint copy under the QUANTITY label — explains why the
    /// suggested units differ for this equipment combo.
    private var unitGuidanceText: String {
        switch equipmentType {
        case .tankerHazmat, .tankerPetro:    return "PETROLEUM · BBL = 42 US GAL"
        case .tankerLiquid, .tankerGas:      return "LIQUID / GAS"
        case .reefer:                        return "REEFER · PALLET COMMON"
        case .vesselContainer:               return "VESSEL · TEU/FEU = ISO CONTAINER"
        case .vesselBulk:                    return "BULK · METRIC TONS / BUSHELS"
        case .vesselTanker:                  return "VESSEL TANKER · BBL/MT"
        case .flatbed, .stepDeck, .conestoga, .oversized:
            return "FLATBED · LBS / TONS / PIECES"
        default:                             return ""
        }
    }

    private var equipmentPreviewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EQUIPMENT · PREVIEW")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .top, spacing: Space.s3) {
                glyph(for: cargoType)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(cargoType.label)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(equipmentSpecText)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                    Text(equipmentNoteText)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    @ViewBuilder
    private func glyph(for type: ShipperAPI.CargoType) -> some View {
        let lower = type.label.lowercased()
        if type.label.lowercased() == "hazmat" || lower.contains("petroleum") || lower.contains("chemicals") || lower.contains("liquid") || lower.contains("gas") || lower.contains("cryogenic") {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Brand.hazmat.opacity(0.16))
                Rectangle()
                    .stroke(Brand.hazmat, lineWidth: 2)
                    .frame(width: 24, height: 24)
                    .rotationEffect(.degrees(45))
                Text("3")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color(hex: 0xB27300))
                    .offset(y: 4)
            }
        } else if lower.contains("refrigerated") || lower.contains("food") {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Brand.info.opacity(0.12))
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Brand.info, lineWidth: 2)
                    .frame(width: 30, height: 24)
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(palette.bgCardSoft)
                Image(systemName: type.systemImage)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
        }
    }

    /// Equipment spec hint — DYNAMIC. Reads the live ERG match and
    /// user-entered UN/Class/PG when the cargo type is hazmat-flavored;
    /// falls back to the equipment-type default otherwise. Founder bug
    /// 2026-05-16 (screenshot): selecting Refrigerated + Reefer still
    /// painted "UN1267 · Class 3 · 2\" cam-lock · Petroleum Crude Oil"
    /// because an ERG match cached from an earlier petroleum lookup
    /// leaked across the cargo-type switch. The cargo-type gate below
    /// keeps the hazmat-derived spec confined to hazmat/petroleum/
    /// chemicals/gas cargo, exactly the surfaces where UN + ERG + hose
    /// configuration are actually meaningful.
    private var equipmentSpecText: String {
        // Only consider ERG/UN-derived spec when the user has chosen a
        // hazmat-flavored cargo. Refrigerated/general/intermodal etc.
        // skip straight to the equipment-type default.
        if cargoType.isHazmatFlavored {
            // 1. Hazmat case → derive from ERG match + user fields.
            if let m = ergMatch, m.found, let un = m.unNumber {
                let cls = (m.hazardClass ?? hazmatClass).isEmpty ? "-" : (m.hazardClass ?? hazmatClass)
                let pg  = packingGroup.isEmpty ? "" : " · PG \(packingGroup)"
                let hose = tankerHoseSpec.isEmpty ? "" : " · \(hoseLabel(tankerHoseSpec))"
                return "UN\(un) · Class \(cls)\(pg)\(hose)"
            }
            // 2. User has typed a UN but ERG hasn't matched yet — show
            //    what they typed honestly.
            let typedUN = unNumber.uppercased().replacingOccurrences(of: "UN", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !typedUN.isEmpty {
                let cls = hazmatClass.isEmpty ? "-" : hazmatClass
                let pg  = packingGroup.isEmpty ? "" : " · PG \(packingGroup)"
                return "UN\(typedUN) · Class \(cls)\(pg)\(isLookingUpERG ? " · looking up…" : "")"
            }
        }
        // 3. Equipment type drives the spec when no UN entered yet.
        switch equipmentType {
        case .tankerHazmat:    return "DOT-407 · awaiting UN"
        case .tankerPetro:     return "MC-306 · petroleum"
        case .tankerLiquid:    return "MC-307 · food-grade liner"
        case .tankerGas:       return "MC-331 · gas / cryo"
        case .reefer:          return reeferTempLowText.isEmpty
                                       ? "53′ Reefer · spec pending"
                                       : "53′ Reefer · \(reeferTempLowText)–\(reeferTempHighText)°F"
        case .flatbed:         return "Flatbed · 48′/53′ · standard"
        case .stepDeck:        return "Step deck · 48′/53′"
        case .conestoga:       return "Conestoga · curtain-side"
        case .container:       return "20′ / 40′ / 53′ ISO container"
        case .oversized:       return oversizeDimsText.contains("-") ? "Oversized · dims pending" : oversizeDimsText
        case .powerOnly:       return "Power-only · driver bring own trailer"
        case .railTOFC:        return "Rail · TOFC (trailer-on-flatcar)"
        case .railCOFC:        return "Rail · COFC (container-on-flatcar)"
        case .railIntermodal:  return "Rail · intermodal container"
        case .vesselContainer: return "Vessel · ISO container"
        case .vesselBulk:      return "Vessel · bulk hold"
        case .vesselTanker:    return "Vessel · tanker"
        case .dryVan:          return "53′ Dry Van · standard"
        // New equipment cases — surface honest one-liners so the
        // preview header reflects the picked equipment instead of
        // hitting the switch's missing-case error.
        case .lowboy:                return "Lowboy · 53′ heavy-haul deck"
        case .hotShot:               return "Hot shot · gooseneck flatbed"
        case .railTankGas:           return "Rail tank car · pressure (gas)"
        case .railTankLiquid:        return "Rail tank car · non-pressure (liquid)"
        case .railBoxcar:            return "Rail boxcar · 50′ / 60′ standard"
        case .railReeferBoxcar:      return "Rail reefer boxcar · mech refrigeration"
        case .railHopper:            return "Rail hopper · covered grain / plastic"
        case .railCenterbeam:        return "Rail centerbeam flatcar · lumber / pipe"
        case .railGondola:           return "Rail gondola · scrap / aggregate"
        case .railAutoRack:          return "Rail autorack · multi-level"
        case .railFlatcar:           return "Rail flatcar · machinery / heavy haul"
        case .vesselRoRo:            return "Vessel · RoRo (autos / project cargo)"
        case .vesselLNG:             return "Vessel · LNG carrier"
        case .vesselReeferContainer: return "Vessel · reefer container ship"
        case .vesselISOTank:         return "Vessel · ISO tank container"
        }
    }

    private var equipmentNoteText: String {
        // ERG match drives the safety-note line ONLY when cargo is
        // hazmat-flavored. Cargo-type gate prevents Crude-Oil ERG names
        // from contaminating a Refrigerated preview after the user
        // pivots cargo (2026-05-16 founder bug).
        if cargoType.isHazmatFlavored {
            if let m = ergMatch, m.found {
                var bits: [String] = []
                if let g = m.guideNumber { bits.append("ERG Guide \(g)") }
                if m.isTIH == true        { bits.append("⚠ Toxic-by-inhalation") }
                if m.isWR  == true        { bits.append("⚠ Water-reactive") }
                if let n = m.name, !n.isEmpty { bits.append(n.capitalized) }
                return bits.isEmpty ? "CHEMTREC +1-800-424-9300" : bits.joined(separator: " · ")
            }
            if let err = ergLookupError, !err.isEmpty {
                return err
            }
        }
        switch cargoType.label.lowercased() {
        case "hazmat", "petroleum", "chemicals", "gas", "cryogenic":
            return "CHEMTREC +1-800-424-9300 · enter UN to load ERG"
        case "refrigerated", "food_grade", "food grade":
            return "Continuous temp logging · last-load-out check"
        case "intermodal":
            return "Chassis pool · per diem after free time"
        default:
            return "Standard tender · no special notes"
        }
    }

    // MARK: - Step 3: PRICING

    @ViewBuilder
    private var pricingStepBody: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            rateField
            targetRateCard
            catalystRequirementsCard
            notesField
        }
    }

    /// Catalyst requirements — collapsible card. The shipper sets the
    /// regulatory eligibility gate a carrier must clear to bid this
    /// load. Founder bug 2026-06-01: this card rendered TRUCK reqs
    /// (FMCSA CSA score + CDL endorsements) in EVERY mode — asking a
    /// vessel / rail / barge shipper for a "CDL endorsement," which is
    /// meaningless on water or rail. The card now switches on
    /// `transportMode` and renders the RIGHT requirement set:
    ///   • truck  → FMCSA CSA / safety score + CDL endorsements (H/N/X/T/P/S)
    ///   • vessel → SOLAS / IMO-IMDG / ISM / ISPS / STCW crew certs / SIRE vetting
    ///   • rail   → AAR interchange rule compliance / FRA / PTC
    ///   • barge  → USCG COI / Subchapter M / Tankerman-PIC / inland TWIC
    /// All sets serialize into composeSubmissionNotes() so the catalyst's
    /// dispatcher sees the right gate at dispatch time (web parity —
    /// LoadCreationWizard Step 7).
    @ViewBuilder
    private var catalystRequirementsCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    showCatalystRequirements.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.shield.checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("CATALYST REQUIREMENTS")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Spacer(minLength: 0)
                    if let summary = catalystRequirementsSummary {
                        Text(summary)
                            .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(LinearGradient.diagonal))
                    }
                    Image(systemName: showCatalystRequirements ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showCatalystRequirements {
                VStack(alignment: .leading, spacing: Space.s4) {
                    // Mode-gated requirement set. Founder bug fix: the
                    // truck-only CSA/CDL block no longer leaks into
                    // vessel / rail / barge posts.
                    switch transportMode {
                    case .truck:  truckCatalystRequirements
                    case .vessel: vesselCatalystRequirements
                    case .rail:   railCatalystRequirements
                    case .barge:  bargeCatalystRequirements
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// Header summary pill text — mode-aware. Only shows when the
    /// shipper has set a non-default gate so an untouched card reads
    /// clean.
    private var catalystRequirementsSummary: String? {
        switch transportMode {
        case .truck:
            if catalystEndorsements.isEmpty && catalystMinSafetyScore == 80 { return nil }
            return "\(catalystEndorsements.count) endorsement\(catalystEndorsements.count == 1 ? "" : "s") · ≥\(Int(catalystMinSafetyScore))"
        case .vessel:
            if catalystVesselRequirements.isEmpty { return nil }
            return "\(catalystVesselRequirements.count) cert\(catalystVesselRequirements.count == 1 ? "" : "s")"
        case .rail:
            if catalystRailRequirements.isEmpty { return nil }
            return "\(catalystRailRequirements.count) req\(catalystRailRequirements.count == 1 ? "" : "s")"
        case .barge:
            if catalystBargeRequirements.isEmpty { return nil }
            return "\(catalystBargeRequirements.count) req\(catalystBargeRequirements.count == 1 ? "" : "s")"
        }
    }

    // MARK: - Per-mode catalyst requirement bodies

    /// TRUCK — FMCSA CSA safety score + CDL endorsements (the original
    /// content, preserved verbatim). H = Hazmat, N = Tank, X = H+N,
    /// T = Doubles/Triples, P = Passenger, S = School Bus.
    @ViewBuilder
    private var truckCatalystRequirements: some View {
        // Min safety score slider
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Min FMCSA safety score")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
                Text("\(Int(catalystMinSafetyScore))")
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Slider(value: $catalystMinSafetyScore, in: 50...100, step: 5) {
                Text("Safety score")
            }
            .tint(Brand.magenta)
            Text("Carriers below this CSA / safety score are filtered out of bid eligibility.")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        // Endorsement chips
        VStack(alignment: .leading, spacing: 6) {
            Text("Required CDL endorsements")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            let endorsementCodes: [(code: String, label: String)] = [
                ("H", "Hazmat"),
                ("N", "Tank"),
                ("X", "H+N"),
                ("T", "Doubles/Triples"),
                ("P", "Passenger"),
                ("S", "School Bus"),
            ]
            // Two-column grid of toggle chips
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(endorsementCodes, id: \.code) { e in
                    let selected = catalystEndorsements.contains(e.code)
                    Button {
                        if selected { catalystEndorsements.remove(e.code) }
                        else        { catalystEndorsements.insert(e.code) }
                    } label: {
                        catalystRequirementChip(code: e.code, label: e.label, selected: selected)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Drivers must hold every selected endorsement on their CDL to bid this load.")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// VESSEL — maritime carrier-vetting certs. SOLAS hull/equipment,
    /// IMO IMDG (hazmat at sea), ISM safety-management, ISPS port-facility
    /// security, STCW crew certification, SIRE 2.0 tanker vetting
    /// (OCIMF). These are the real eligibility gates a shipper sets for
    /// an ocean carrier — there is no CDL or FMCSA CSA score at sea.
    @ViewBuilder
    private var vesselCatalystRequirements: some View {
        let codes: [(code: String, label: String)] = [
            ("SOLAS", "Hull/equip"),
            ("IMO",   "IMDG hazmat"),
            ("ISM",   "Safety mgmt"),
            ("ISPS",  "Port security"),
            ("STCW",  "Crew certs"),
            ("SIRE",  "Tanker vet"),
        ]
        catalystChipSet(
            heading: "Required vessel certifications",
            note: "Carriers must hold every selected maritime certification to bid this load. SIRE 2.0 (OCIMF) vetting applies to tanker tonnage.",
            codes: codes,
            selection: $catalystVesselRequirements
        )
    }

    /// RAIL — interchange + federal-rail compliance. AAR Interchange
    /// Rules (railcar interchange / mechanical), FRA (Federal Railroad
    /// Administration safety), PTC (Positive Train Control). No CDL /
    /// FMCSA on the rail network.
    @ViewBuilder
    private var railCatalystRequirements: some View {
        let codes: [(code: String, label: String)] = [
            ("AAR", "Interchange"),
            ("FRA", "Fed. rail"),
            ("PTC", "Train control"),
        ]
        catalystChipSet(
            heading: "Required rail compliance",
            note: "Carriers must attest to every selected rail-network requirement to bid this load. AAR Interchange Rules govern railcar mechanical interchange.",
            codes: codes,
            selection: $catalystRailRequirements
        )
    }

    /// BARGE — inland-waterway USCG regime. Certificate of Inspection
    /// (COI), Subchapter M towing-vessel compliance (46 CFR 136-144),
    /// Tankerman-PIC for liquid-bulk transfer, TWIC credential. No CDL /
    /// FMCSA on inland waterways.
    @ViewBuilder
    private var bargeCatalystRequirements: some View {
        let codes: [(code: String, label: String)] = [
            ("COI",     "USCG insp."),
            ("SUBM",    "Subchapter M"),
            ("TANKPIC", "Tankerman"),
            ("TWIC",    "TWIC cred."),
        ]
        catalystChipSet(
            heading: "Required barge / USCG compliance",
            note: "Carriers must attest to every selected USCG requirement to bid this load. Tankerman-PIC applies to liquid-bulk transfer operations.",
            codes: codes,
            selection: $catalystBargeRequirements
        )
    }

    /// Shared chip-set builder for the non-truck modes — a heading, a
    /// 3-up toggle grid, and an explainer. Reuses the exact bespoke chip
    /// visual the truck endorsement grid uses so every mode reads
    /// identically.
    @ViewBuilder
    private func catalystChipSet(
        heading: String,
        note: String,
        codes: [(code: String, label: String)],
        selection: Binding<Set<String>>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(heading)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(codes, id: \.code) { e in
                    let selected = selection.wrappedValue.contains(e.code)
                    Button {
                        if selected { selection.wrappedValue.remove(e.code) }
                        else        { selection.wrappedValue.insert(e.code) }
                    } label: {
                        catalystRequirementChip(code: e.code, label: e.label, selected: selected)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(note)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One toggle chip — bespoke gradient-fill-when-selected pill,
    /// faint-bordered card otherwise. Shared by every mode so the look
    /// is identical across truck / vessel / rail / barge.
    @ViewBuilder
    private func catalystRequirementChip(code: String, label: String, selected: Bool) -> some View {
        VStack(spacing: 1) {
            Text(code)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(selected ? .white : palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 8, weight: .semibold)).tracking(0.3)
                .foregroundStyle(selected ? .white.opacity(0.85) : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6).padding(.horizontal, 4)
        .background(
            Group {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient.diagonal)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.bgCardSoft)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(selected ? Color.clear : palette.borderFaint)
        )
    }

    private var rateField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("POSTED RATE")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                // 2026-05-17 — Mode-native rate unit pill. Truck loads
                // read "$/mile", rail "$/ton-mile", vessel container
                // "$/FEU", vessel tanker "WS", vessel bulk "$/MT", barge
                // "$/ton-mile". Replaces the silent USD-only chrome that
                // implied every load was rated like a dry van.
                Text(rateUnitLabel)
                    .font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(0.4)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: rateUnitIcon)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 18)
                TextField("0", text: $rateText)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .tint(LinearGradient.diagonal)
                    .keyboardType(.decimalPad)
                    .disabled(isSubmitting)
                Text(rateUnitSuffix)
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            // Mode-aware hint copy. Tanker vessel loads read in WS, dry
            // vessel containers in $/FEU — the user shouldn't have to
            // remember which axis they're pricing on.
            Text(rateUnitHint)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // Worldscale-100 flat — the per-load conversion basis a WS%
            // rate needs to be benchmarked. Without it the rate-vs-market
            // meter honestly reports referenceReason='needs_ws100_flat'
            // (we don't invent a WS-100 feed). Tanker-only.
            if rateIsWorldscalePct {
                worldscaleFlatField
            }
        }
    }

    /// The per-load Worldscale-100 flat ($/MT) input — only shown for
    /// vessel tanker loads. Optional; when filled, the server can
    /// convert the WS% rate into the canonical $/MT and benchmark it.
    private var worldscaleFlatField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("WORLDSCALE-100 FLAT (OPTIONAL)")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("$/MT")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(0.4)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 18)
                TextField("0", text: $worldscaleFlatText)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .tint(LinearGradient.diagonal)
                    .keyboardType(.decimalPad)
                    .disabled(isSubmitting)
                    .onChange(of: worldscaleFlatText) { _, _ in recomputeRateCompareIfReady() }
                Text("$/MT")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            Text("The lane's published WS-100 flat. Enter it so ESANG can convert your WS% into $/MT and benchmark it.")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Short pill label for the rate unit. Mode + equipment driven.
    private var rateUnitLabel: String {
        switch transportMode {
        case .truck:  return "$/MILE"
        case .rail:   return "$/TON-MILE"
        case .vessel:
            switch equipmentType {
            case .vesselTanker:    return "WORLDSCALE"
            case .vesselContainer: return "$/FEU"
            case .vesselBulk:      return "$/MT"
            default:               return "USD"
            }
        case .barge:  return "$/TON-MILE"
        }
    }

    /// Trailing suffix shown inside the field next to the typed value.
    /// Reads as "USD" for fiat amounts and "WS" for Worldscale.
    private var rateUnitSuffix: String {
        transportMode == .vessel && equipmentType == .vesselTanker ? "WS" : "USD"
    }

    /// SF Symbol leading the rate input. Money for fiat-priced modes,
    /// percent for Worldscale (because WS is a percent-of-flat-rate).
    private var rateUnitIcon: String {
        transportMode == .vessel && equipmentType == .vesselTanker
            ? "percent" : "dollarsign.circle"
    }

    /// Mode-aware explainer copy under the input.
    private var rateUnitHint: String {
        switch transportMode {
        case .truck:
            return "Linehaul total - divided by route miles for the $/mile market compare."
        case .rail:
            return "Posted in $ per ton-mile; rail freight industry standard for unit/manifest traffic."
        case .vessel:
            switch equipmentType {
            case .vesselTanker:
                return "Worldscale percent vs the published flat rate (e.g. WS 75 = 75% of WS 100 flat for the lane). Tanker market norm."
            case .vesselContainer:
                return "$ per Forty-foot Equivalent Unit (FEU). Liner trade-lane benchmark."
            case .vesselBulk:
                return "$ per Metric Tonne for the full voyage charter (Capesize / Panamax dry bulk)."
            default:
                return "Posted rate in USD for the full voyage."
            }
        case .barge:
            return "Posted in $ per ton-mile; inland waterway industry standard."
        }
    }

    /// ESANG AI rate-vs-market meter — replaces the prior stub
    /// "estimate vs spot" copy. Wired to `rates.compareLaneRate`
    /// (web-parity surface) and renders:
    ///   • Position pill: BELOW MARKET / AT MARKET / ABOVE MARKET
    ///     (color-coded against Brand.success / .info / .warning)
    ///   • Position rating: poor / fair / good / excellent based on
    ///     percentile bands (≤25 / 26-50 / 51-80 / 81+)
    ///   • Range bar: market min — your rate — market max
    ///   • RPM line: your $/mi vs market avg $/mi · sample size
    ///   • Recommendation copy from the server
    /// Surfaces the empty/loading/error states honestly.
    @ViewBuilder
    private var targetRateCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ESANG · RATE VS MARKET")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                if let cmp = rateComparison {
                    Text(sourceBadgeLabel(cmp.source))
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(cmp.source == "gemini" ? .white : palette.textTertiary)
                        .padding(.horizontal, cmp.source == "gemini" ? 6 : 0)
                        .padding(.vertical, cmp.source == "gemini" ? 2 : 0)
                        .background(
                            Group {
                                if cmp.source == "gemini" {
                                    Capsule().fill(LinearGradient.diagonal)
                                }
                            }
                        )
                }
            }
            if isComparingRate {
                Text("Comparing your rate against the lane…")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            } else if let err = rateCompareError {
                Text("Rate compare error: \(err)")
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
            } else if let cmp = rateComparison {
                rateMeterBody(cmp)
            } else if (parseDouble(rateText) ?? 0) <= 0 {
                Text("Add posted rate to see ESANG market position")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            } else if originStateForRateCompare.isEmpty || destStateForRateCompare.isEmpty {
                Text(isRouting ? "Resolving lane states for market compare…" : "Add origin and destination state codes to compare this lane.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            } else if let routeErr = routingError {
                // Route call failed — surface here too so the user
                // doesn't see a stuck "computing distance" state on
                // step 3 with no path to recover. Mirrors the route
                // meta strip on step 1.
                Text(rateCompareRequiresDistance
                     ? "Route error: \(routeErr) - go back to step 1 to retry"
                     : "Route ETA unavailable. ESANG is using the typed lane states for this market compare.")
                    .font(EType.caption)
                    .foregroundStyle(rateCompareRequiresDistance ? Brand.danger : palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if rateCompareRequiresDistance && (routeDistanceMeters ?? 0) <= 0 {
                Text("Distance computing - meter populates after route resolves")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(LinearGradient.diagonal.opacity(rateComparison == nil ? 0.25 : 0.55), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    /// Renders the rate-vs-market meter per the CANONICAL render
    /// contract (identical to web). The server is the SOLE authority:
    ///
    ///   • comparable == true → full card: value + $/unit, position
    ///     pill, FILLED range slider, 'Nth percentile · n=N', and the
    ///     recommendation. (The rich render we always shipped.)
    ///   • comparable == false → NEVER a position pill / percentile
    ///     number / filled slider (zero-fabrication mandate). Branch on
    ///     referenceReason:
    ///       - 'insufficient_data' → greyed reference band, label
    ///         'Reference only · n=N comparable loads'.
    ///       - 'needs_ws100_flat' → 'Enter the lane Worldscale-100 flat
    ///         to benchmark this WS% rate' (no band, no verdict).
    ///       - 'unit_unconvertible'/'unconvertible' → honest
    ///         'Can't benchmark this rate type yet'.
    @ViewBuilder
    private func rateMeterBody(_ cmp: RatesAPI.LaneComparison) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if cmp.comparable {
                comparableMeter(cmp)
            } else {
                switch cmp.referenceReason {
                case "needs_ws100_flat":
                    needsWorldscaleFlatBody(cmp)
                case "unit_unconvertible", "unconvertible":
                    unconvertibleBody(cmp)
                default:
                    // insufficient_data (and any unknown reason) → honest
                    // greyed reference band, no verdict.
                    referenceOnlyBody(cmp)
                }
            }
            // Honest benchmark provenance receipt (e.g. 'Baltic BDTI ·
            // reference only · feed not connected'). This is a LABEL
            // ONLY — the percentile / position / filled slider stay
            // gated on cmp.comparable above, so a verdictEligible=false
            // citation can NEVER add a verdict, only name the source.
            benchmarkCitationLabel(cmp)
        }
    }

    /// Renders the server's honest benchmark provenance label under the
    /// meter when present. Never contributes a verdict signal — the
    /// position/percentile/slider are gated on `cmp.comparable`, so even
    /// a `verdictEligible == false` citation only names the source.
    @ViewBuilder
    private func benchmarkCitationLabel(_ cmp: RatesAPI.LaneComparison) -> some View {
        if let citation = cmp.benchmarkCitation,
           !citation.label.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: citation.connected ? "checkmark.seal" : "info.circle")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                Text(citation.label)
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// FULL verdict card — only reached when the server says the rate
    /// is comparable (platform_data, n>=3, normalized to the canonical
    /// unit + currency).
    @ViewBuilder
    private func comparableMeter(_ cmp: RatesAPI.LaneComparison) -> some View {
        let position = cmp.position ?? ""
        let percentile = cmp.percentile ?? 0
        let (positionLabel, positionColor) = positionStyling(for: position)
        let (ratingLabel, ratingColor) = ratingStyling(
            percentile: percentile,
            position: position,
            source: cmp.source,
            sampleSize: cmp.sampleSize
        )
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(headlineRateText(cmp))
                    .font(.system(size: 24, weight: .bold).monospacedDigit())
                    .foregroundStyle(LinearGradient.diagonal)
                Text(perUnitSubtitle(cmp))
                    .font(EType.caption).monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
                if !positionLabel.isEmpty {
                    Text(positionLabel)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(positionColor))
                }
            }
            // Range bar: market min -- your rate marker -- market max.
            // Only drawn when the server actually returned a band.
            if cmp.marketMinRPM != nil, cmp.marketMaxRPM != nil {
                rateRangeBar(cmp: cmp, filled: true)
            }
            HStack(spacing: Space.s2) {
                Text(ratingLabel)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(ratingColor))
                Text("\(percentile)th percentile · n=\(cmp.sampleSize)")
                    .font(EType.caption).monospacedDigit()
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
            }
            if !cmp.recommendation.isEmpty {
                Text(cmp.recommendation)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// referenceReason == 'insufficient_data'. Reference band GREYED,
    /// NO position pill, NO percentile number, NO filled slider. Honest
    /// 'Reference only · n=N comparable loads' label.
    @ViewBuilder
    private func referenceOnlyBody(_ cmp: RatesAPI.LaneComparison) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(headlineRateText(cmp))
                    .font(.system(size: 24, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
                Text(perUnitSubtitle(cmp))
                    .font(EType.caption).monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
                Text("REFERENCE ONLY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(palette.bgCardSoft))
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
            }
            // Greyed, UNFILLED reference band (no marker / no verdict)
            // when the server reported a national reference range.
            if cmp.marketMinRPM != nil, cmp.marketMaxRPM != nil {
                rateRangeBar(cmp: cmp, filled: false)
            }
            Text("Reference only · n=\(cmp.sampleSize) comparable loads")
                .font(EType.caption).monospacedDigit()
                .foregroundStyle(palette.textTertiary)
            if !cmp.recommendation.isEmpty {
                Text(cmp.recommendation)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// referenceReason == 'needs_ws100_flat'. A WS% rate can't be
    /// benchmarked without the lane's Worldscale-100 flat — no band, no
    /// verdict, just the honest ask. (We DON'T invent a WS-100 feed.)
    @ViewBuilder
    private func needsWorldscaleFlatBody(_ cmp: RatesAPI.LaneComparison) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(headlineRateText(cmp))
                    .font(.system(size: 24, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                Text("Enter the lane Worldscale-100 flat to benchmark this WS% rate")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// referenceReason == 'unit_unconvertible' / 'unconvertible' (or
    /// source == 'unconvertible'). Honest: we can't benchmark this rate
    /// type yet.
    @ViewBuilder
    private func unconvertibleBody(_ cmp: RatesAPI.LaneComparison) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(headlineRateText(cmp))
                    .font(.system(size: 24, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                Text("Can't benchmark this rate type yet")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The headline value, rendered HONESTLY for the entered unit. For
    /// a WS% tanker rate this is the Worldscale percent the user typed
    /// (e.g. "WS 75") — NEVER a fabricated dollar figure. For everything
    /// else it's the server-echoed dollar rate.
    private func headlineRateText(_ cmp: RatesAPI.LaneComparison) -> String {
        if rateIsWorldscalePct {
            // Show the WS% as entered. yourRate carries the percent in
            // the WS% branch.
            let pct = parseDouble(rateText) ?? cmp.yourRate
            return "WS \(Int(pct.rounded()))"
        }
        return dollars(cmp.yourRate, currency: cmp.currency)
    }

    /// The $/unit subtitle next to the headline. For a WS% rate we ONLY
    /// show a converted $/MT when the server actually converted it
    /// (worldscaleConverted == true with a normalized value) — never
    /// the '$75 · $0.05/MT' trap of treating the percent as dollars.
    private func perUnitSubtitle(_ cmp: RatesAPI.LaneComparison) -> String {
        // CANONICAL: the server's normValue is the user's own rate
        // already normalized into the benchmark's canonical unit +
        // currency. Read it directly (never re-divide yourRPM) — this is
        // what makes $/FEU, $/ton-mi, WS→$/MT and the iOS↔web parity
        // agree. Mirrors web's `num(cmp.normValue) ?? num(cmp.yourRPM)`.
        let v = cmp.normValue ?? cmp.yourRPM
        if rateIsWorldscalePct {
            guard cmp.worldscaleConverted, v > 0 else { return "" }
            return formatPerUnit(v, unit: cmp.canonicalUnit, currency: cmp.currency)
        }
        return formatPerUnit(v, unit: cmp.unit ?? cmp.canonicalUnit, currency: cmp.currency)
    }

    /// Market range bar. `filled == true` draws the gradient track +
    /// the positioned "your rate" marker (the comparable verdict). When
    /// `filled == false` the track is GREYED with NO marker — a plain
    /// reference band that makes no claim about where the rate sits
    /// (zero-fabrication: no marker = no implied verdict).
    @ViewBuilder
    private func rateRangeBar(cmp: RatesAPI.LaneComparison, filled: Bool) -> some View {
        // Optional band — the server omits these when it can't
        // benchmark. Caller only invokes this when both are present.
        let lo = cmp.marketMinRPM ?? 0
        let hi = cmp.marketMaxRPM ?? 0
        let unit = cmp.unit ?? cmp.canonicalUnit
        // CANONICAL marker position: the user's rate normalized into the
        // SAME canonical unit the band is in. Re-dividing yourRPM here
        // placed the marker in the wrong spot for $/FEU, $/ton-mi and
        // WS→$/MT. normValue is already in-band; fall back to yourRPM
        // only for an old server.
        let v  = cmp.normValue ?? cmp.yourRPM
        // Clamp + normalize. If hi == lo (rare), draw the marker
        // centered.
        let pct: Double = {
            guard hi > lo else { return 0.5 }
            let raw = (v - lo) / (hi - lo)
            return min(1.0, max(0.0, raw))
        }()
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                if filled {
                    Capsule()
                        .fill(LinearGradient(colors: [Brand.success, Brand.info, Brand.warning],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(height: 8)
                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(LinearGradient.diagonal, lineWidth: 2))
                        .offset(x: max(0, geo.size.width * pct - 8))
                } else {
                    // Greyed reference band — NO marker.
                    Capsule()
                        .fill(palette.bgCardSoft)
                        .frame(height: 8)
                        .overlay(Capsule().strokeBorder(palette.borderFaint))
                }
            }
        }
        .frame(height: 18)
        HStack {
            Text("\(formatPerUnit(lo, unit: unit, currency: cmp.currency)) · min")
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary).monospacedDigit()
            Spacer(minLength: 0)
            if let avg = cmp.marketAvgRPM {
                Text("\(formatPerUnit(avg, unit: unit, currency: cmp.currency)) · avg")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary).monospacedDigit()
                Spacer(minLength: 0)
            }
            Text("\(formatPerUnit(hi, unit: unit, currency: cmp.currency)) · max")
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary).monospacedDigit()
        }
    }

    /// Format a per-unit rate for display. Falls back to "$X.XX / mi"
    /// when the server doesn't report a unit (older deploys), and
    /// otherwise uses the server's unit label ($/mi, $/car-mile,
    /// $/MT, etc.) so the card adapts to whichever mode the user picked.
    private func formatPerUnit(_ value: Double, unit: String?, currency: String = "USD") -> String {
        let label = (unit?.isEmpty == false ? unit! : "$/mi")
            .replacingOccurrences(of: "$/", with: "")
        let prefix = currencyPrefix(currency)
        return String(format: "%@%.2f / %@", prefix, value, label)
    }

    /// Short source badge — "platform" (real loads), "ai" (Gemini),
    /// or "national" (fallback). Gemini gets the gradient pill so
    /// the user knows the answer came from real-time market intel.
    private func sourceBadgeLabel(_ source: String) -> String {
        switch source {
        case "platform_data":      return "platform"
        case "gemini":             return "ESANG AI · live"
        case "national_benchmark",
             "national_reference": return "national"
        case "unconvertible":      return "no benchmark"
        default:                   return source
        }
    }

    /// Server emits position uppercase like "ABOVE_MARKET". Map to
    /// human label + color for the pill.
    private func positionStyling(for raw: String) -> (String, Color) {
        switch raw.uppercased() {
        case "ABOVE_MARKET": return ("ABOVE MARKET", Brand.warning)
        case "BELOW_MARKET": return ("BELOW MARKET", Brand.info)
        case "AT_MARKET":    return ("AT MARKET",    Brand.success)
        default:             return (raw,            Brand.neutral)
        }
    }

    /// ESANG AI quality rating from the percentile + position. The
    /// shipper's posted rate is "excellent" for them when it's at
    /// or below the lane's midpoint (saves them money) and "poor"
    /// when it's at the high end (carrier-favorable, shipper pays
    /// more than they need to). Position label still flips the
    /// shipper-vs-carrier framing in the pill above.
    private func ratingStyling(
        percentile: Int,
        position: String,
        source: String,
        sampleSize: Int
    ) -> (String, Color) {
        // 2026-05-19 — source-aware. When the server falls back to
        // the national benchmark (no real platform comparables AND
        // Gemini's market lookup also failed), it returns
        // `percentile = 50` as a default — which the old buckets
        // mapped to "GOOD" regardless of the actual rate. That made
        // the card always read GOOD on thin lanes, which is exactly
        // what the founder flagged. New rules:
        //
        //   • source == national_benchmark, sampleSize == 0 →
        //     "REFERENCE" pill (neutral). No claim that the rate is
        //     good or bad — we just don't have data to judge.
        //   • Otherwise — percentile-driven rating as before.
        if source == "national_benchmark" && sampleSize == 0 {
            return ("REFERENCE", Brand.neutral)
        }
        // For shippers: lower rate = better deal. Percentile ≤25
        // means your rate is in the bottom quartile of comparable
        // lanes — excellent for the shipper. ≥80th percentile is
        // poor (overpaying). The middle bands: 26-50 = good, 51-79
        // = fair.
        switch percentile {
        case 0...25:  return ("EXCELLENT", Brand.success)
        case 26...50: return ("GOOD",      Brand.info)
        case 51...79: return ("FAIR",      Brand.warning)
        default:      return ("POOR",      Brand.danger)
        }
    }
    private var notesField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOTES (OPTIONAL)")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            TextField(
                "Anything carriers should know, temperature ranges, dock hours, COI…",
                text: $notes,
                axis: .vertical
            )
            .font(EType.body)
            .foregroundStyle(palette.textPrimary)
            .tint(LinearGradient.diagonal)
            .lineLimit(3...6)
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .disabled(isSubmitting)
        }
    }

    // MARK: - Step 4: REVIEW

    @ViewBuilder
    private var reviewStepBody: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            eusoTicketTypeBanner
            reviewSummaryCard
            // 2026-08-07 — the attestation is bound to the same state as the
            // copy on the equipment step, so it reads and edits identically.
            // It is repeated here because this is the screen where the load
            // actually posts, and the poster must be able to see and change
            // what they are attesting to at the moment they commit.
            cargoClassificationCard
            portIntelligenceReviewCard
            equipmentReviewCard
            esangMarketReviewCard
            saveAsTemplateCTA
            if let toast = templateSaveAck {
                templateAckBanner(toast)
            }
        }
    }

    /// Save-as-template CTA on the review step. Persists the current
    /// wizard state as a named template via `loadTemplates.create`
    /// — same record the web shipper sees in their saved-templates
    /// list, so the next time they open the post-load wizard on
    /// either platform, they can hydrate from the saved template.
    private var saveAsTemplateCTA: some View {
        Button {
            templateNameDraft = suggestedTemplateName
            templateSaveError = nil
            showSaveTemplateSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 12, weight: .heavy))
                Text("Save as template")
                    .font(.system(size: 13, weight: .heavy)).tracking(0.4)
            }
            .foregroundStyle(LinearGradient.diagonal)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.55), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func templateAckBanner(_ msg: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
            Button { templateSaveAck = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// Default template name suggestion — uses the lane (origin →
    /// destination) when both are present, otherwise the equipment +
    /// cargo combo. Web parity: matches the suggested-name format
    /// the platform's quick-save uses.
    private var suggestedTemplateName: String {
        let oTrim = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let dTrim = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if !oTrim.isEmpty && !dTrim.isEmpty {
            // "Houston, TX → Austin, TX · Tanker · Hazmat"
            return "\(shortAddress(oTrim)) → \(shortAddress(dTrim)) · \(equipmentType.label)"
        }
        return "\(equipmentType.label) · \(cargoType.label)"
    }

    /// Trim the trailing ", United States" / ", USA" so the suggested
    /// name fits in the suggested name field without truncation.
    private func shortAddress(_ s: String) -> String {
        var trimmed = s
        for suffix in [", United States", ", USA", ", US"] {
            if trimmed.hasSuffix(suffix) {
                trimmed = String(trimmed.dropLast(suffix.count))
            }
        }
        return trimmed
    }

    /// Banner showing what EusoTicket the load will generate. Web
    /// parity: the wizard data IS the EusoTicket. BOL for general
    /// freight, Run Ticket for crude oil / hazmat / petroleum tanker
    /// (per-haul measurement), Haul Receipt for the post-POD copy.
    /// Driver views the same record via 106B; shipper via 303 / 304 /
    /// 305.
    private var eusoTicketTypeBanner: some View {
        let (kind, blurb, icon) = eusoTicketKindForCurrentSelection
        return HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Will generate · \(kind)")
                    .font(.system(size: 13, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textPrimary)
                Text(blurb)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.55), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    /// Resolves the EusoTicket kind based on current selections.
    /// Crude oil / hazmat / petroleum / chemicals tankers and bulk-
    /// liquid loads → Run Ticket (per-haul measurement). Everything
    /// else → BOL. Haul Receipt is generated POST-POD by the carrier
    /// — not chosen here.
    private var eusoTicketKindForCurrentSelection: (kind: String, blurb: String, icon: String) {
        let isTanker = [EquipmentChoice.tankerHazmat, .tankerPetro, .tankerLiquid, .tankerGas, .vesselTanker].contains(equipmentType)
        let isHazmat = cargoType == .hazmat || cargoType == .petroleum || cargoType == .chemicals || cargoType == .gas
        if isTanker || isHazmat {
            return (
                kind: "Run Ticket",
                blurb: "Per-haul measurement record. Driver + shipper view the same EusoTicket. Required for crude / hazmat / tanker.",
                icon: "drop.triangle.fill"
            )
        }
        return (
            kind: "BOL · Bill of Lading",
            blurb: "Standard bill of lading. Acts as the receipt + chain-of-custody record. Driver + shipper view the same EusoTicket.",
            icon: "doc.richtext.fill"
        )
    }

    private var reviewSummaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            reviewSection("LANE")
            reviewRow(label: "Origin",      value: nonEmpty(origin))
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Destination", value: nonEmpty(destination))
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Distance",    value: distanceReviewText)
            if let warning = routeReviewWarningText {
                Divider().overlay(palette.borderFaint)
                routeReviewWarning(message: warning)
            }
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Pickup",      value: hasPickupDate ? formatDate(pickupDate) : "Catalyst proposes")
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Delivery ETA", value: deliveryReviewText)

            reviewSection("CARGO + EQUIPMENT")
            reviewRow(label: "Cargo type",     value: cargoType.label)
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Equipment",      value: equipmentType.label)
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Vertical",       value: equipmentType.vertical.uppercased())
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Quantity",       value: parseDouble(weightText).map { "\(formatQty($0)) \(weightUnit.rawValue)" } ?? "-")

            reviewSection("FREIGHT CHARGE")
            reviewRow(label: "Posted rate",    value: parseDouble(rateText).map { dollars($0) } ?? "-", isHero: true)
            if let cmp = rateComparison {
                Divider().overlay(palette.borderFaint)
                reviewRow(label: "Vs market",  value: vsMarketSummary(cmp))
            }

            if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                reviewSection("NOTES")
                reviewRow(label: "Free-form",  value: notes)
            }
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
    }

    private var portIntelligenceReviewCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("PORT INTELLIGENCE")
                    .font(EType.micro)
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                if portIntelligenceIsRequired {
                    Text("REQUIRED")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(Brand.warning)
                }
            }

            if isAssessingPortIntelligence {
                HStack(spacing: 8) {
                    ProgressView().tint(LinearGradient.diagonal)
                    Text("Assessing live facility, route, evidence, and restriction records…")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            } else if let error = portIntelligenceError {
                Text(error)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let assessment = portIntelligenceAssessment, hasCurrentPortIntelligenceAssessment {
                let gate = assessment.preflight.gate
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: portIntelligenceGateIcon(gate))
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(portIntelligenceGateColor(gate))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(gate.replacingOccurrences(of: "_", with: " ").uppercased())
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Text("\(assessment.preflight.counts.viable) viable · \(assessment.preflight.counts.conditional) conditional · \(assessment.preflight.counts.insufficientEvidence) unresolved · \(assessment.preflight.counts.blocked) blocked")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                        if let strategy = assessment.strategies.first {
                            Text(strategy.destinationName ?? "Evidence-backed route strategy")
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }

                if gate == "acknowledgement_required" {
                    Toggle(isOn: $portIntelligenceAcknowledged) {
                        Text("I acknowledge the documented evidence gaps")
                            .font(EType.caption)
                            .foregroundStyle(palette.textPrimary)
                    }
                    .tint(Brand.warning)
                }
            } else if portIntelligenceAssessment != nil {
                Text("Cargo or route details changed. Refresh the assessment before posting.")
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
            } else {
                Text(portIntelligenceIsRequired
                     ? "No current assessment is bound to this draft."
                     : "No assessment has been run for this truck lane.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            Button {
                Task { await assessPortIntelligence() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "sparkle.magnifyingglass")
                    Text(hasCurrentPortIntelligenceAssessment ? "Refresh assessment" : "Assess route")
                }
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isAssessingPortIntelligence || isSubmitting)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    portIntelligenceAssessment?.preflight.gate == "blocked"
                        && hasCurrentPortIntelligenceAssessment
                        ? Brand.danger
                        : palette.borderFaint,
                    lineWidth: 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func portIntelligenceGateIcon(_ gate: String) -> String {
        switch gate {
        case "ready": return "checkmark.seal.fill"
        case "blocked": return "xmark.octagon.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }

    private func portIntelligenceGateColor(_ gate: String) -> Color {
        switch gate {
        case "ready": return Brand.success
        case "blocked": return Brand.danger
        default: return Brand.warning
        }
    }

    /// Shows the equipment-specific subform fields only when the
    /// selection actually has a subform (tanker / reefer / flatbed).
    /// Otherwise renders nothing — keeps step 4 honest about what
    /// data is in the record.
    @ViewBuilder
    private var equipmentReviewCard: some View {
        switch equipmentType {
        case .tankerHazmat, .tankerPetro, .tankerLiquid, .tankerGas, .vesselTanker:
            tankerReviewCard
        case .reefer:
            reeferReviewCard
        case .flatbed, .stepDeck, .conestoga, .oversized:
            flatbedReviewCard
        default:
            EmptyView()
        }
    }

    private var tankerReviewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            reviewSection("TANKER REQUIREMENTS")
            reviewRow(label: "Hose spec",      value: hoseLabel(tankerHoseSpec))
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Fitting",        value: fittingLabel(tankerFitting))
            if cargoType == .hazmat || cargoType == .petroleum || cargoType == .chemicals {
                Divider().overlay(palette.borderFaint)
                reviewRow(label: "UN",             value: nonEmpty(unNumber))
                Divider().overlay(palette.borderFaint)
                reviewRow(label: "Hazmat class",   value: nonEmpty(hazmatClass))
                Divider().overlay(palette.borderFaint)
                reviewRow(label: "Packing group",  value: nonEmpty(packingGroup))
                Divider().overlay(palette.borderFaint)
                reviewRow(label: "Shipping name",  value: nonEmpty(properShippingName))
            }
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var reeferReviewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            reviewSection("REEFER REQUIREMENTS")
            reviewRow(label: "Temp range", value: reeferTempRangeText)
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Pre-cool",   value: preCoolRequired ? "Required" : "Not required")
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Mode",       value: continuousMode ? "Continuous" : "Cycling")
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var flatbedReviewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            reviewSection("FLATBED · OVERSIZED REQUIREMENTS")
            reviewRow(label: "Securing",    value: flatbedGearText)
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Dimensions",  value: oversizeDimsText)
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Permits",     value: oversizePermits ? "Required" : "Not required")
            if oversizePermits {
                Divider().overlay(palette.borderFaint)
                reviewRow(label: "Permit type", value: permitType.label)
            }
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    /// ESANG market meter reprised on the review step so the shipper
    /// sees their final price posture before submitting.
    @ViewBuilder
    private var esangMarketReviewCard: some View {
        if let cmp = rateComparison {
            VStack(alignment: .leading, spacing: 0) {
                reviewSection("ESANG · RATE VS MARKET")
                if cmp.comparable {
                    // Full verdict — server confirmed comparable.
                    reviewRow(label: "Position",   value: (cmp.position ?? "").replacingOccurrences(of: "_", with: " "))
                    Divider().overlay(palette.borderFaint)
                    reviewRow(label: "Your rate",  value: perUnitSubtitle(cmp).isEmpty
                                ? formatPerUnit(cmp.normValue ?? cmp.yourRPM, unit: cmp.canonicalUnit, currency: cmp.currency)
                                : perUnitSubtitle(cmp))
                    if let avg = cmp.marketAvgRPM {
                        Divider().overlay(palette.borderFaint)
                        reviewRow(label: "Market avg", value: formatPerUnit(avg, unit: cmp.unit ?? cmp.canonicalUnit, currency: cmp.currency))
                    }
                    if let pct = cmp.percentile {
                        Divider().overlay(palette.borderFaint)
                        reviewRow(label: "Percentile", value: "\(pct)th · n=\(cmp.sampleSize)")
                    }
                } else {
                    // Not comparable — honest single row, no fabricated
                    // position/percentile/market band.
                    reviewRow(label: "Status", value: vsMarketSummary(cmp))
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    /// One-line "vs market" summary honoring the canonical envelope —
    /// the verdict ONLY when comparable, else the honest reason.
    private func vsMarketSummary(_ cmp: RatesAPI.LaneComparison) -> String {
        guard cmp.comparable else {
            switch cmp.referenceReason {
            case "needs_ws100_flat":   return "Needs WS-100 flat"
            case "unit_unconvertible", "unconvertible":
                return "Not benchmarkable yet"
            default:                   return "Reference only · n=\(cmp.sampleSize)"
            }
        }
        let pos = (cmp.position ?? "").replacingOccurrences(of: "_", with: " ")
        if let pct = cmp.percentile { return "\(pos) · \(pct)th pct" }
        return pos
    }

    private func reviewSection(_ title: String) -> some View {
        Text(title)
            .font(EType.micro).tracking(0.8)
            .foregroundStyle(LinearGradient.diagonal)
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, 6)
    }

    private func reviewRow(label: String, value: String, isHero: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(value)
                .font(isHero ? .system(size: 22, weight: .bold) : EType.bodyStrong)
                .foregroundStyle(isHero ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textPrimary))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    private var distanceReviewText: String {
        guard let m = routeDistanceMeters, m > 0 else {
            if routingError != nil { return "Route unavailable" }
            return "-"
        }
        return String(format: "%.0f mi", Double(m) / 1609.34)
    }

    private var deliveryReviewText: String {
        if let eta = computedDeliveryETA {
            return deliveryETAFormatter.string(from: eta)
        }
        if routingError != nil { return "Pending route" }
        if hasPickupDate { return "-" }
        return "Catalyst proposes"
    }

    private var routeReviewWarningText: String? {
        guard let routingError else { return nil }
        return routingError
    }

    private func routeReviewWarning(message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Brand.warning)
                .padding(.top, 2)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .background(Brand.warning.opacity(0.08))
    }

    private var reeferTempRangeText: String {
        let lo = reeferTempLowText.trimmingCharacters(in: .whitespaces)
        let hi = reeferTempHighText.trimmingCharacters(in: .whitespaces)
        if lo.isEmpty && hi.isEmpty { return "-" }
        return "\(lo.isEmpty ? "-" : lo)°F – \(hi.isEmpty ? "-" : hi)°F"
    }

    private var flatbedGearText: String {
        var gear: [String] = []
        if flatbedStraps          { gear.append("straps") }
        if flatbedTarps           { gear.append("tarps") }
        if flatbedChains          { gear.append("chains") }
        if flatbedEdgeProtectors  { gear.append("edge protectors") }
        return gear.isEmpty ? "-" : gear.joined(separator: ", ")
    }

    private var oversizeDimsText: String {
        let l = oversizeLengthText.trimmingCharacters(in: .whitespaces)
        let w = oversizeWidthText.trimmingCharacters(in: .whitespaces)
        let h = oversizeHeightText.trimmingCharacters(in: .whitespaces)
        if l.isEmpty && w.isEmpty && h.isEmpty { return "-" }
        return "L \(l.isEmpty ? "-" : l) · W \(w.isEmpty ? "-" : w) · H \(h.isEmpty ? "-" : h) ft"
    }

    private func hoseLabel(_ raw: String) -> String {
        switch raw {
        case "2_camlock":     return "2\" cam-lock"
        case "3_camlock":     return "3\" cam-lock"
        case "4_camlock":     return "4\" cam-lock"
        case "dry_disconnect":return "Dry-disconnect"
        case "":              return "-"
        default:              return raw
        }
    }

    private func fittingLabel(_ raw: String) -> String {
        switch raw {
        case "api":   return "API adapter"
        case "ttma":  return "TTMA"
        case "other": return "Other"
        case "":      return "-"
        default:      return raw
        }
    }

    private func nonEmpty(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "-" : t
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE · MMM d"
        return f.string(from: d)
    }

    // MARK: - Banners

    private func successBanner(_ ack: ShipperAPI.PostLoadAck) -> some View {
        let kind = eusoTicketKindForCurrentSelection.kind
        return HStack(alignment: .top, spacing: 8) {
            // Bespoke brand-disc check (zero SF Symbols).
            ZStack {
                Circle().fill(LinearGradient.diagonal)
                PostLoadBannerCheck()
                    .stroke(.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .padding(4)
            }
            .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text("Load posted · \(kind) generated")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(loadNumberSubtitle(ack))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                Text("Driver views the same EusoTicket from their Loads tab.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button { withAnimation { lastSuccess = nil } } label: {
                PostLoadBannerClose()
                    .stroke(palette.textTertiary, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .frame(width: 13, height: 13)
                    .padding(2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func loadNumberSubtitle(_ ack: ShipperAPI.PostLoadAck) -> String {
        let trimmed = ack.loadNumber.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Bids will land in your Bids inbox." }
        return "\(trimmed) · bids will land in your Bids inbox."
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Bespoke warning triangle with a "!" notch (zero SF Symbols).
            ZStack {
                PostLoadWarningTriangle()
                    .fill(Brand.danger)
                PostLoadBangMark()
                    .stroke(.white, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .padding(.bottom, 1)
            }
            .frame(width: 15, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't post this load")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(Self.humanizePostError(message))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            Button { store.reset() } label: {
                PostLoadBannerClose()
                    .stroke(palette.textTertiary, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .frame(width: 13, height: 13)
                    .padding(2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Error humanizer
    //
    // The server can hand back a tRPC BAD_REQUEST whose `message` is a
    // raw, JSON-stringified Zod issues array — e.g.
    //   [{"origin":"number","code":"too_small","minimum":1,
    //     "path":["multiVehicleCount"],"message":"Too small: …"}]
    // The errorFormatter (_core/trpc.ts) only rewrites SQL-shaped
    // errors, so a validation failure reaches us verbatim. We must
    // NEVER show that array (or any JSON / [{…}] blob) to the shipper.
    //
    // This maps a raw validation payload to a clean, human sentence,
    // naming the offending field whenever the issue path is parseable,
    // and falls back to a friendly retry line for everything else.
    static func humanizePostError(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Something went wrong posting this load. Please try again."
        }

        // Only intercept machine-shaped payloads — a JSON array/object
        // or anything that mentions a Zod issue code. A normal,
        // already-human server sentence is passed through untouched.
        let looksLikeJSON = trimmed.hasPrefix("[") || trimmed.hasPrefix("{")
        let mentionsZodCode = trimmed.contains("\"code\"")
            || trimmed.contains("invalid_type")
            || trimmed.contains("too_small")
            || trimmed.contains("too_big")
            || trimmed.contains("\"path\"")
        guard looksLikeJSON || mentionsZodCode else { return trimmed }

        // Try to name the specific field from the first issue's `path`.
        if let field = firstZodFieldPath(in: trimmed) {
            if let label = postFieldLabel(field) {
                return "Couldn't post this load — please check the \(label) and try again."
            }
            return "Couldn't post this load — please check the highlighted fields and try again."
        }

        // Couldn't resolve a field — generic, friendly, no JSON.
        return "Couldn't post this load — please review your details and try again."
    }

    /// Pulls the first `"path":["fieldName", …]` leaf field name out of
    /// a stringified Zod issues array, without a JSON decode (the blob
    /// shape isn't fixed across Zod/tRPC versions). Returns nil when no
    /// path token is present.
    private static func firstZodFieldPath(in raw: String) -> String? {
        guard let pathRange = raw.range(of: "\"path\"") else { return nil }
        let after = raw[pathRange.upperBound...]
        guard let bracket = after.firstIndex(of: "[") else { return nil }
        let tail = after[after.index(after: bracket)...]
        guard let close = tail.firstIndex(of: "]") else { return nil }
        let inside = tail[tail.startIndex..<close]
        // Take the LAST quoted segment in the path (the leaf field).
        let segments = inside
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"")) }
            .filter { !$0.isEmpty }
        return segments.last
    }

    /// Maps a server field name to a shipper-friendly label. Returns nil
    /// for fields with no clean consumer-facing analog, so the caller
    /// falls back to the generic "highlighted fields" phrasing.
    private static func postFieldLabel(_ field: String) -> String? {
        switch field {
        case "origin", "originPort", "originLat", "originLng":
            return "pickup location"
        case "destination", "destPort", "destLat", "destLng":
            return "delivery location"
        case "rate", "worldscalePct", "worldscaleFlat":
            return "rate"
        case "weight":
            return "weight"
        case "rateUnit":
            return "rate unit"
        case "cargoType", "equipmentType", "trailer", "vesselClass":
            return "equipment & cargo details"
        case "permitType":
            return "permit selection"
        case "multiVehicleCount":
            return "load quantity"
        case "pickupDate":
            return "pickup date"
        case "transportMode", "vertical":
            return "transport mode"
        default:
            return nil
        }
    }

    // MARK: - Continue / Submit CTA

    private var continueOrSubmitCTA: some View {
        Button(action: continueOrSubmit) {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else if step == .review {
                    // Bespoke send glyph (zero SF Symbols).
                    PostLoadSendGlyph()
                        .fill(.white)
                        .frame(width: 15, height: 15)
                }
                Text(ctaText)
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(canAdvance
                               ? AnyShapeStyle(LinearGradient.primary)
                               : AnyShapeStyle(palette.tintNeutral.opacity(0.4)))
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canAdvance)
        .accessibilityLabel(ctaText)
    }

    private var ctaText: String {
        if case .success = store.phase, step == .review { return "Post another" }
        if step == .review {
            if isSubmitting { return "Posting…" }
            // Name the gate that is stopping the post instead of showing a
            // dark button with no explanation.
            if cargoAttestation.dangerousGoodsStatus == .undetermined {
                return "Attest cargo classification"
            }
            if cargoClassificationBlockReason != nil {
                return "Complete cargo classification"
            }
            return "Post this load"
        }
        guard let next = step.next else { return "Continue" }
        return "Continue · Step \(next.rawValue) of \(PostLoadStep.allCases.count) →"
    }

    private var canAdvance: Bool {
        if isSubmitting { return false }
        switch step {
        case .lane:
            return laneReadyForPosting
        case .equipment:
            // 2026-05-17 — Gate the equipment step on hazmat compliance
            // (49 CFR 173). If the user picked a hazmat class that's
            // not allowed on the selected trailer code, block continue
            // and surface the warning inline. Non-hazmat loads pass.
            // 2026-06-03 — WARN-NOT-BLOCK (founder mandate: no shipper ever
            // stuck at "Continue"). The hazmat class↔equipment check is now
            // ADVISORY only — hazmatComplianceCard renders an amber "VERIFY"
            // with a packaging/segregation/placarding acknowledgement, but
            // Continue is never disabled on it. Also a truck-federal rule
            // (49 CFR 177), so it would never have applied to rail (174/AAR)
            // or vessel (IMDG) anyway. No `return false` here by design.
            // 2026-05-17 — Gate on the state-overweight check too.
            // Allow advance when the user has acknowledged the
            // overweight scenario via an overweight or superload
            // permit; block when the weight exceeds the binding
            // state limit and no permit is set.
            //
            // 2026-06-01 — Gate ONLY when transportMode == .truck.
            // State weight limits are federal-highway truck rules
            // (49 CFR 658). They don't apply to rail (FRA per-car),
            // vessel (deadweight tonnage), or barge (USACE waterway
            // class). Founder report: a 35,000 MT vessel-tanker
            // hazmat load with every field filled green still showed
            // a dim Continue because 77M lb >> any state's 80k-lb
            // truck limit. Mirror the same `transportMode == .truck`
            // gate already on overweightComplianceCard so the
            // visible UI + the gating logic agree.
            if transportMode == .truck {
                let wLbs = parseWeightLbs(weightText, unit: weightUnit)
                if wLbs > 0 {
                    let oState = originStateCode ?? Self.stateFromLane(origin)
                    let dState = destStateCode ?? Self.stateFromLane(destination)
                    let oLimit = Self.stateWeightLimit(oState)
                    let dLimit = Self.stateWeightLimit(dState)
                    let oOver  = !oState.isEmpty && wLbs > Double(oLimit)
                    let dOver  = !dState.isEmpty && wLbs > Double(dLimit)
                    let permitsOK = oversizePermits && (permitType == .overweightOnly || permitType == .superload || permitType == .annualOversize || permitType == .tripPermit)
                    if (oOver || dOver) && !permitsOK { return false }
                }
            }
            // 2026-05-17 — Gate on the reefer temp-range validation.
            // When the user typed any temp value, an issue string is
            // returned by `reeferRangeIssue` and we block until they
            // either clear / correct the range or pick a different
            // equipment that doesn't need a temp window.
            // 2026-06-03 — reefer temp-range is ADVISORY (a value outside the
            // -30/+80°F standard envelope means "specialty unit / dry ice /
            // LN2", not an invalid load). Surfaced as a warning on the reefer
            // sub-form; never blocks Continue.
            return true
        case .pricing:
            return laneReadyForPosting
        case .review:
            // 2026-08-07 — a load cannot post without the poster's cargo
            // classification. The button stays dark and `ctaText` says
            // exactly what is missing; it never posts a guess.
            return laneReadyForPosting
                && portIntelligenceAllowsPosting
                && cargoClassificationBlockReason == nil
        }
    }

    private func continueOrSubmit() {
        if step == .review {
            if case .success = store.phase {
                resetForm()
                store.reset()
                step = .lane
                return
            }
            Task { await submit() }
        } else if let next = step.next {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                step = next
            }
        }
    }

    // MARK: - Submit pipeline (preserved verbatim)

    private var isSubmitting: Bool {
        if case .submitting = store.phase { return true }
        return false
    }

    private func submit() async {
        guard laneReadyForPosting else {
            if routingError == nil {
                routingError = transportMode == .truck
                    ? "A verified truck route is required before this load can be posted."
                    : "Both endpoints must be verified before this load can be posted."
            }
            return
        }
        guard portIntelligenceAllowsPosting else {
            portIntelligenceError = portIntelligenceIsRequired
                ? "Complete the current Port Intelligence gate before posting this load."
                : "Resolve the current Port Intelligence result before posting this load."
            return
        }
        // 2026-08-07 — final classification gate. Re-mirror first so a field
        // edited in the same run loop as the tap is included, then refuse
        // with the exact missing inputs rather than posting a guess.
        mirrorCargoIdentityIntoAttestation()
        if let reason = cargoClassificationBlockReason {
            store.reportSubmissionRefusal(reason)
            return
        }
        let pickupISO = hasPickupDate ? isoDate(pickupDate) : nil
        let quantity  = parseDouble(weightText)
        let isMassUnit = [MeasurementUnit.pounds, .kilograms, .shortTons, .metricTons]
            .contains(weightUnit)
        let weight = isMassUnit ? quantity : nil
        let massUnit = isMassUnit ? weightUnit.rawValue : nil
        let rate      = parseDouble(rateText)
        // Pack equipment-type + subform spec into the `notes` field
        // so the catalyst's dispatcher / driver gets the full
        // requirements at dispatch time. Server schema doesn't yet
        // have structured tanker / reefer / flatbed columns; web
        // parity at the application layer.
        let composedNotes = composeSubmissionNotes()
        // 2026-05-17 — wire the Step-1 multi-modal picker + Step-2
        // equipment + permit fields through to `shippers.create` so
        // the load row carries the full picker context (mode →
        // vesselClass / permitType / equipmentType / rateUnit). The
        // server resolves defaults for any nil field, so submission
        // remains valid even when the user keeps the wizard on Truck +
        // dry van.
        let permitRaw: String? = (equipmentType == .oversized || equipmentType == .flatbed
                                  || equipmentType == .stepDeck || equipmentType == .conestoga)
            ? permitType.rawValue
            : nil
        // Shared with the rate-vs-market meter — single source of truth
        // for the wire unit (see the `rateUnitWire` computed property).
        let rateUnitWireValue = rateUnitWire
        // When the user posts a vessel tanker load, the value typed in
        // the rate field is a Worldscale percent — capture it on the
        // dedicated `worldscalePct` column for downstream tanker market
        // compares, and zero out the plain dollar rate so the rate-vs-
        // market server query doesn't misread it as a truck $/mile.
        let worldscaleWire: Double? = rateIsWorldscalePct
            ? parseDouble(rateText)
            : nil
        // Per-load Worldscale-100 flat captured on the tanker subform —
        // the conversion basis the server needs to benchmark a WS% rate.
        let worldscaleFlatWire: Double? = rateIsWorldscalePct
            ? parseDouble(worldscaleFlatText)
            : nil
        let rateForWire: Double? = worldscaleWire == nil ? rate : nil
        let currentAssessment = hasCurrentPortIntelligenceAssessment
            ? portIntelligenceAssessment
            : nil
        await store.submit(
            origin: origin,
            destination: destination,
            cargoType: cargoType,
            productName: nonBlank(properShippingName),
            category: commodityMatch?.category ?? cargoType.rawValue,
            physicalState: portIntelligencePhysicalState,
            // The attestation carries the determination, the evidence and the
            // regulated identity (mirrored from this screen's hazmat card
            // above). It is the single wire source of truth for all of it.
            classification: cargoAttestation,
            classificationContext: cargoClassificationContext,
            rate: rateForWire,
            weight: weight,
            weightUnit: massUnit,
            quantity: quantity,
            quantityUnit: weightUnit.rawValue,
            notes: composedNotes,
            pickupDate: pickupISO,
            originLat: originLat,
            originLng: originLng,
            destLat: destLat,
            destLng: destLng,
            originCountry: originCountryCode.uppercased(),
            destinationCountry: destinationCountryCode.uppercased(),
            transportMode: transportMode,
            // F-ANIMATION root-cause fix (2026-06-14): the server schema is
            // `multiVehicleCount: z.number().int().min(1).max(999).optional()`
            // (shippers.ts:106). The vessel estimator returns vehicleCount == 0
            // when no vessel class is picked yet (MultiModalCore.estimateCrude →
            // the "needs vessel class" branch) and can exceed 999 for a very
            // large barrel quantity. Sending 0 / >999 tripped Zod's .min(1) /
            // .max(999) and the raw issues array leaked to the user as
            // "Couldn't post that load [ { ... } ]". Elide the field entirely
            // when it isn't a valid 1...999 fleet count — the server treats its
            // absence as "single conveyance / not estimated", which is correct
            // for a vessel-tanker post that hasn't resolved a vessel class.
            multiVehicleCount: multiVehicleEstimate
                .map(\.vehicleCount)
                .flatMap { (1...999).contains($0) ? $0 : nil },
            permitType: permitRaw,
            worldscalePct: worldscaleWire,
            worldscaleFlat: worldscaleFlatWire,
            rateUnit: rateUnitWireValue,
            equipmentType: equipmentType.rawValue,
            portIntelligenceAssessmentId: currentAssessment?.publicId,
            portIntelligenceAcknowledged: portIntelligenceAcknowledged
        )
        if case .success(let ack) = store.phase {
            self.lastSuccess = ack
            // Raise the bespoke "Load posted" celebration. The overlay owns
            // the reset-to-fresh-Step-1 (on auto-dismiss or a "Post another"
            // tap) so the form isn't wiped out from under the animation.
            withAnimation(.easeOut(duration: 0.25)) {
                showPostedCelebration = true
            }
        }
    }

    /// Tear the celebration down and return the wizard to a FRESH Step-1:
    /// clear every @State load field (resetForm), flip the store back to
    /// idle, drop the inline success banner, and snap the step index to
    /// `.lane`. Invoked on the overlay's auto-dismiss or its CTA tap.
    private func finishCelebrationAndReset() {
        resetForm()
        store.reset()
        lastSuccess = nil
        // The next load starts with no scan behind it.
        prefillBannerType = nil
        prefillBannerSummary = nil
        prefillFieldLabels = []
        prefillRegulatedLabels = []
        prefillAcknowledged = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
            showPostedCelebration = false
            step = .lane
        }
    }

    /// Concatenates equipment + subform fields into a single notes
    /// string. Web parity — the catalyst's load-detail surface
    /// surfaces these as a "REQUIREMENTS" block under the BOL.
    /// Always prepends the user's free-form notes if non-empty.
    private func composeSubmissionNotes() -> String {
        var lines: [String] = []
        if !notes.isEmpty { lines.append(notes) }
        // Catalyst Requirements — mode-aware (2026-06-01 founder fix).
        // TRUCK keeps the FMCSA CSA score + CDL-endorsement lines verbatim
        // (server loads.ts:242-243 parses "Min Safety Score:" and
        // "Required Endorsements:"). Non-truck modes serialize the RIGHT
        // regulatory gate so the catalyst dispatcher never sees a "CDL
        // endorsement" on a vessel / rail / barge post.
        switch transportMode {
        case .truck:
            // Min safety score is always serialized so the catalyst knows
            // the gate; endorsements only when the shipper selected some.
            lines.append("Min Safety Score: \(Int(catalystMinSafetyScore))")
            if !catalystEndorsements.isEmpty {
                let sorted = catalystEndorsements.sorted()
                lines.append("Required Endorsements: \(sorted.joined(separator: ", "))")
            }
        case .vessel:
            if !catalystVesselRequirements.isEmpty {
                let sorted = catalystVesselRequirements.sorted()
                lines.append("Required Vessel Certs: \(sorted.joined(separator: ", "))")
            }
        case .rail:
            if !catalystRailRequirements.isEmpty {
                let sorted = catalystRailRequirements.sorted()
                lines.append("Required Rail Compliance: \(sorted.joined(separator: ", "))")
            }
        case .barge:
            if !catalystBargeRequirements.isEmpty {
                let sorted = catalystBargeRequirements.sorted()
                lines.append("Required Barge/USCG Compliance: \(sorted.joined(separator: ", "))")
            }
        }
        // 2026-05-17 — Mode line is the first machine-readable token in
        // the notes block. Catalyst + dispatch parse this until the
        // server `shippers.create` input carries transport_mode
        // natively (migration 0307 + tRPC input extension).
        lines.append("Mode: \(transportMode.displayName)")
        lines.append("Rate basis: \(transportMode.nativeRateUnit)")
        lines.append("Equipment: \(equipmentType.label)")
        if !weightText.isEmpty {
            lines.append("Quantity: \(weightText) \(weightUnit.rawValue) (\(weightUnit.longLabel))")
        }
        // 2026-06-03 — data-driven equipment requirements (every equipment type).
        // Each selected requirement group → "Group: option, option (+ Other: …)".
        // 2026-06-05 — the catalog no longer carries commodity or hazmat-class
        // groups (those were consolidated to the single top cargo chip + the
        // universal Dangerous-goods / Commodity card), so this loop now emits
        // ONLY genuine per-equipment requirements (tank spec, lining, wash,
        // securement, power, docs).
        for g in EquipmentRequirementsCatalog.groups(forRaw: equipmentType.rawValue) {
            let sel = equipReqSel[g.key] ?? []
            guard !sel.isEmpty else { continue }
            var picks = g.options.filter { sel.contains($0.key) }.map { $0.label }
            let other = (equipReqOther[g.key] ?? "").trimmingCharacters(in: .whitespaces)
            if !other.isEmpty { picks.append("Other: \(other)") }
            if !picks.isEmpty { lines.append("\(g.label): \(picks.joined(separator: ", "))") }
        }
        // 2026-06-05 — SINGLE commodity + dangerous-goods identity block.
        // Emitted once here from the structured fields (the universal
        // Dangerous-goods / Commodity card), into dedicated machine-readable
        // tokens — never duplicated into the per-equipment loop above or the
        // free-text notes below.
        lines.append("Cargo: \(cargoType.label) [\(cargoType.rawValue)]")
        if !properShippingName.isEmpty { lines.append("Commodity / PSN: \(properShippingName)") }
        if cargoType.isHazmatFlavored {
            if !unNumber.isEmpty    { lines.append("UN: \(unNumber)") }
            if !hazmatClass.isEmpty { lines.append("Hazmat class: \(hazmatClass)") }
            if !packingGroup.isEmpty { lines.append("Packing group: \(packingGroup)") }
        }
        switch equipmentType {
        case .tankerHazmat, .tankerPetro, .tankerLiquid, .tankerGas, .vesselTanker:
            if !tankerHoseSpec.isEmpty { lines.append("Tanker hose: \(tankerHoseSpec)") }
            if !tankerFitting.isEmpty  { lines.append("Tanker fitting: \(tankerFitting)") }
        case .reefer:
            if !reeferTempLowText.isEmpty || !reeferTempHighText.isEmpty {
                lines.append("Reefer temp: \(reeferTempLowText)–\(reeferTempHighText)°F")
            }
            lines.append("Pre-cool: \(preCoolRequired ? "yes" : "no") · Continuous: \(continuousMode ? "yes" : "no")")
        case .flatbed, .stepDeck, .conestoga, .oversized:
            var gear: [String] = []
            if flatbedStraps          { gear.append("straps") }
            if flatbedTarps           { gear.append("tarps") }
            if flatbedChains          { gear.append("chains") }
            if flatbedEdgeProtectors  { gear.append("edge protectors") }
            if !gear.isEmpty { lines.append("Securing: \(gear.joined(separator: ", "))") }
            if !oversizeLengthText.isEmpty || !oversizeWidthText.isEmpty || !oversizeHeightText.isEmpty {
                lines.append("Dimensions: L=\(oversizeLengthText) W=\(oversizeWidthText) H=\(oversizeHeightText) ft")
            }
            if oversizePermits {
                lines.append("Permits required: \(permitType.label) · \(permitType.hint)")
            }
        default:
            break
        }
        return lines.joined(separator: "\n")
    }

    private func resetForm() {
        origin = ""
        destination = ""
        originLat = nil; originLng = nil
        destLat   = nil; destLng   = nil
        originCountryCode = "US"
        destinationCountryCode = "US"
        cargoType = .general
        equipmentType = .dryVan
        hasPickupDate = false
        pickupDate = Date()
        weightText = ""
        weightUnit = .pounds
        rateText = ""
        notes = ""
        unNumber = ""
        hazmatClass = ""
        packingGroup = ""
        properShippingName = ""
        // A fresh post is a fresh attestation. Nothing carries over — the
        // previous load's determination says nothing about the next one.
        cargoAttestation = CargoClassificationAttestation()
        tankerHoseSpec = ""
        tankerFitting = ""
        reeferTempLowText = ""
        reeferTempHighText = ""
        preCoolRequired = false
        continuousMode = true
        flatbedStraps = false
        flatbedTarps = false
        flatbedChains = false
        flatbedEdgeProtectors = false
        oversizeLengthText = ""
        oversizeWidthText = ""
        oversizeHeightText = ""
        oversizePermits = false
        permitType = .none
        ergMatch = nil
        ergLookupError = nil
        rateComparison = nil
        routeDistanceMeters = nil
        routeDurationSeconds = nil
        routingError = nil
        portIntelligenceAssessment = nil
        portIntelligenceAssessmentSignature = nil
        portIntelligenceAcknowledged = false
        portIntelligenceError = nil
        // Catalyst requirements — reset every mode's gate to default so
        // the next post doesn't carry a prior load's eligibility set.
        catalystMinSafetyScore = 80
        catalystEndorsements = []
        catalystVesselRequirements = []
        catalystRailRequirements = []
        catalystBargeRequirements = []
        // Wipe autosave so the next user doesn't see stale draft.
        clearDraft()
    }

    private func parseDouble(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let cleaned = trimmed.replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
    }

    private func nonBlank(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date)
    }

    /// Formats a quantity value — integer for whole numbers (so
    /// "9800" reads as "9,800" not "9,800.0"), one decimal for
    /// fractional quantities (e.g. "12.5 bbl"). Mirrors the web
    /// platform's quantity-display rule.
    private func formatQty(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            f.maximumFractionDigits = 0
        } else {
            f.maximumFractionDigits = 2
        }
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Currency-aware symbol so a MX/CA benchmark labels honestly. The
    /// USD/CAD/MXN dollar glyphs collide ('$'), so disambiguate CAD→'CA$'
    /// and MXN→'MX$' (matching web); everything else stays '$'.
    private func currencyPrefix(_ c: String) -> String {
        switch c.uppercased() {
        case "CAD": return "CA$"
        case "MXN": return "MX$"
        default:    return "$"
        }
    }

    /// Currency-aware whole-dollar headline. Defaults to USD for the
    /// existing call sites; the rate-vs-market card passes cmp.currency
    /// so a MX/CA lane reads 'MX$1,200' / 'CA$1,200' instead of '$1,200'.
    private func dollars(_ value: Double, currency: String = "USD") -> String {
        let prefix = currencyPrefix(currency)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let body = f.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        return "\(prefix)\(body)"
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let eusoShipperPostLoadDismiss = Notification.Name("eusoShipperPostLoadDismiss")
}

// MARK: - Mode → Cargo compatibility
//
// File-local extension that documents which cargo types a given
// transport mode accepts in this wizard. Single source of truth used
// by the cargo-chip filter (Step 2) and the mode-flip auto-snap.
// Truck accepts everything; rail can't carry oversized in the same
// sense as truck (heavy-haul oversize is a specialty surface); etc.
//
// Founder firing 2026-05-18: the cargo picker was rendering all 8
// cargo types regardless of mode. Now rail/vessel/barge prune to
// the cargos those modes practically serve.

extension TransportMode {
    /// Cargo types this mode actually serves. The wizard filters
    /// the chip strip by this set; the mode-flip auto-snap uses it
    /// to decide whether to also reset the cargoType to `.general`.
    var acceptedCargoTypes: Set<ShipperAPI.CargoType> {
        switch self {
        case .truck:
            // Truck does everything — historical default.
            return Set(ShipperAPI.CargoType.allCases)
        case .rail:
            // Rail moves all eight categories at scale (bulk + intermodal
            // + tank cars + autoracks + flatcars). Even oversized has a
            // rail equivalent (centerbeam / depressed-center flatcars).
            return Set(ShipperAPI.CargoType.allCases)
        case .vessel:
            // Vessel: container, bulk, tanker, RoRo cover everything
            // except the truck-shaped "oversized" category which on
            // vessel becomes RoRo or break-bulk under General.
            return [.general, .hazmat, .refrigerated, .liquid, .gas, .chemicals, .petroleum]
        case .barge:
            // Inland barge: bulk + tank + dry cargo. No reefer, no
            // gas (gas barges exist but aren't on EusoTrip's barge
            // shipper flow yet), no oversized.
            return [.general, .hazmat, .liquid, .chemicals, .petroleum]
        }
    }

    func acceptsCargo(_ cargo: ShipperAPI.CargoType) -> Bool {
        acceptedCargoTypes.contains(cargo)
    }
}

// MARK: - Wizard → EquipmentAnimation taxonomy bridges
//
// EquipmentChoice + ShipperAPI.CargoType are wizard-internal enums;
// EquipmentKind + CargoKind are component-level enums (in
// EquipmentAnimation.swift). Mapping is 1:1 by raw value where the
// rawValues match, with fallbacks for cases where the wizard has
// types the component doesn't model 1:1.

fileprivate extension ShipperPostLoad.EquipmentChoice {
    var animationKind: EquipmentKind {
        switch self {
        case .dryVan:                return .dryVan
        case .reefer:                return .reefer
        case .flatbed:               return .flatbed
        case .stepDeck:              return .stepDeck
        case .conestoga:             return .conestoga
        case .container:             return .container
        case .tankerHazmat:          return .tankerHazmat
        case .tankerPetro:           return .tankerPetro
        case .tankerLiquid:          return .tankerLiquid
        case .tankerGas:             return .tankerGas
        case .powerOnly:             return .powerOnly
        case .oversized:             return .oversized
        case .lowboy:                return .lowboy
        case .hotShot:               return .hotShot
        case .railTOFC:              return .railTOFC
        case .railCOFC:              return .railCOFC
        case .railIntermodal:        return .railIntermodal
        case .railTankGas:           return .railTankGas
        case .railTankLiquid:        return .railTankLiquid
        case .railBoxcar:            return .railBoxcar
        case .railReeferBoxcar:      return .railReeferBoxcar
        case .railHopper:            return .railHopper
        case .railCenterbeam:        return .railCenterbeam
        case .railGondola:           return .railGondola
        case .railAutoRack:          return .railAutoRack
        case .railFlatcar:           return .railFlatcar
        case .vesselContainer:       return .vesselContainer
        case .vesselBulk:            return .vesselBulk
        case .vesselTanker:          return .vesselTanker
        case .vesselRoRo:            return .vesselRoRo
        case .vesselLNG:             return .vesselLNG
        case .vesselReeferContainer: return .vesselReeferContainer
        case .vesselISOTank:         return .vesselISOTank
        }
    }
}

fileprivate extension ShipperAPI.CargoType {
    var animationKind: CargoKind {
        switch self {
        case .general:      return .general
        case .hazmat:       return .hazmat
        case .refrigerated: return .refrigerated
        case .oversized:    return .oversized
        case .liquid:       return .liquid
        case .gas:          return .gas
        case .chemicals:    return .chemicals
        case .petroleum:    return .petroleum
        }
    }

    /// True for cargo types where 49 CFR 172 hazmat metadata (UN
    /// number, hazard class, ERG guide, packing group, CHEMTREC) is
    /// meaningful. Used to gate hazmat-derived text in the equipment
    /// preview so ERG matches don't leak across a cargo-type switch.
    /// `liquid` and `gas` count as hazmat-flavored because food-grade
    /// liquids are the exception, not the rule — most non-water bulk
    /// liquids carry a UN number.
    var isHazmatFlavored: Bool {
        switch self {
        case .hazmat, .petroleum, .chemicals, .gas, .liquid:
            return true
        case .general, .refrigerated, .oversized:
            return false
        }
    }

    /// The default equipment type to snap to when the user picks this
    /// cargo type. Drives the auto-coherence between cargo and
    /// equipment so the animation + preview + requirements subform
    /// stay in sync. Returns nil when the current equipment is already
    /// compatible for the active mode.
    ///
    /// Founder firing 2026-05-18: was previously mode-blind — Hazmat
    /// + Rail always landed on `tankerHazmat` (a truck silhouette) and
    /// Refrigerated + Vessel always landed on `reefer` (also truck).
    /// The mode parameter forces the snap onto a vertical-coherent
    /// equipment so the animation paints correctly the first time.
    func defaultEquipment(
        currentEquipment: ShipperPostLoad.EquipmentChoice,
        mode: TransportMode
    ) -> ShipperPostLoad.EquipmentChoice? {
        // Compute the canonical target for this (cargo, mode) tuple,
        // then return nil if the user's existing equipment already
        // serves the cargo on the active mode.
        let target = canonicalEquipment(mode: mode)
        let acceptable = acceptableEquipment(mode: mode)
        return acceptable.contains(currentEquipment) ? nil : target
    }

    /// Non-optional variant — always returns a sensible equipment for
    /// the (cargo, mode) pair. Used by the mode-flip auto-snap where
    /// we need a guaranteed value even when the current selection
    /// happens to already be in the acceptable set (because it isn't
    /// — that's why we're snapping).
    func defaultEquipmentFallback(mode: TransportMode) -> ShipperPostLoad.EquipmentChoice {
        canonicalEquipment(mode: mode)
    }

    /// Single canonical equipment per (cargo, mode). The "if I had
    /// to pick one" choice — used when the user's current selection
    /// isn't acceptable.
    private func canonicalEquipment(mode: TransportMode) -> ShipperPostLoad.EquipmentChoice {
        switch (self, mode) {
        // Refrigerated
        case (.refrigerated, .truck):  return .reefer
        case (.refrigerated, .rail):   return .railReeferBoxcar
        case (.refrigerated, .vessel): return .vesselReeferContainer
        case (.refrigerated, .barge):  return .vesselReeferContainer

        // Hazmat / Chemicals
        case (.hazmat, .truck), (.chemicals, .truck):  return .tankerHazmat
        case (.hazmat, .rail), (.chemicals, .rail):    return .railTankLiquid
        case (.hazmat, .vessel), (.chemicals, .vessel):return .vesselISOTank
        case (.hazmat, .barge), (.chemicals, .barge):  return .vesselTanker

        // Petroleum
        case (.petroleum, .truck):  return .tankerPetro
        case (.petroleum, .rail):   return .railTankLiquid
        case (.petroleum, .vessel): return .vesselTanker
        case (.petroleum, .barge):  return .vesselTanker

        // Liquid bulk
        case (.liquid, .truck):  return .tankerLiquid
        case (.liquid, .rail):   return .railTankLiquid
        case (.liquid, .vessel): return .vesselTanker
        case (.liquid, .barge):  return .vesselTanker

        // Gas
        case (.gas, .truck):  return .tankerGas
        case (.gas, .rail):   return .railTankGas
        case (.gas, .vessel): return .vesselLNG
        case (.gas, .barge):  return .vesselLNG

        // Oversized
        case (.oversized, .truck):  return .oversized
        case (.oversized, .rail):   return .railFlatcar
        case (.oversized, .vessel): return .vesselRoRo
        case (.oversized, .barge):  return .vesselBulk

        // General
        case (.general, .truck):  return .dryVan
        case (.general, .rail):   return .railBoxcar
        case (.general, .vessel): return .vesselContainer
        case (.general, .barge):  return .vesselContainer
        }
    }

    /// Equipment that's considered "good enough" for this cargo on
    /// this mode — auto-snap only fires when the user's current pick
    /// falls outside this set.
    private func acceptableEquipment(mode: TransportMode) -> Set<ShipperPostLoad.EquipmentChoice> {
        switch (self, mode) {
        case (.refrigerated, .truck):  return [.reefer]
        case (.refrigerated, .rail):   return [.railReeferBoxcar, .railBoxcar]
        case (.refrigerated, .vessel): return [.vesselReeferContainer, .vesselContainer]
        case (.refrigerated, .barge):  return [.vesselReeferContainer, .vesselContainer]

        case (.hazmat, .truck), (.chemicals, .truck):
            return [.tankerHazmat, .tankerLiquid, .tankerGas]
        case (.hazmat, .rail), (.chemicals, .rail):
            return [.railTankLiquid, .railTankGas]
        case (.hazmat, .vessel), (.chemicals, .vessel):
            return [.vesselISOTank, .vesselTanker, .vesselLNG]
        case (.hazmat, .barge), (.chemicals, .barge):
            return [.vesselTanker, .vesselISOTank]

        case (.petroleum, .truck):
            return [.tankerPetro, .tankerHazmat, .tankerLiquid]
        case (.petroleum, .rail):
            return [.railTankLiquid]
        case (.petroleum, .vessel), (.petroleum, .barge):
            return [.vesselTanker, .vesselISOTank]

        case (.liquid, .truck):
            return [.tankerLiquid, .tankerPetro, .tankerHazmat]
        case (.liquid, .rail):
            return [.railTankLiquid]
        case (.liquid, .vessel), (.liquid, .barge):
            return [.vesselTanker, .vesselISOTank]

        case (.gas, .truck):
            return [.tankerGas, .tankerHazmat]
        case (.gas, .rail):
            return [.railTankGas]
        case (.gas, .vessel), (.gas, .barge):
            return [.vesselLNG, .vesselTanker]

        case (.oversized, .truck):
            return [.oversized, .flatbed, .stepDeck, .lowboy, .hotShot]
        case (.oversized, .rail):
            return [.railFlatcar, .railCenterbeam, .railGondola]
        case (.oversized, .vessel):
            return [.vesselRoRo, .vesselBulk]
        case (.oversized, .barge):
            return [.vesselBulk]

        case (.general, .truck):
            return [.dryVan, .reefer, .flatbed, .stepDeck, .conestoga, .container, .powerOnly, .hotShot]
        case (.general, .rail):
            return [.railBoxcar, .railTOFC, .railCOFC, .railIntermodal, .railGondola, .railCenterbeam, .railHopper, .railAutoRack, .railFlatcar]
        case (.general, .vessel):
            return [.vesselContainer, .vesselBulk, .vesselRoRo, .vesselReeferContainer]
        case (.general, .barge):
            return [.vesselContainer, .vesselBulk]
        }
    }
}

fileprivate extension ShipperPostLoad.EquipmentChoice {
    /// The default cargo type to snap to when the user picks this
    /// equipment type. Reefer equipment implies refrigerated cargo;
    /// hazmat tanker implies hazmat. Mirror of `defaultEquipment`.
    func defaultCargoType(currentCargo: ShipperAPI.CargoType) -> ShipperAPI.CargoType? {
        switch self {
        case .reefer:
            return currentCargo == .refrigerated ? nil : .refrigerated
        case .tankerHazmat:
            return currentCargo == .hazmat ? nil : .hazmat
        case .tankerPetro:
            return currentCargo == .petroleum ? nil : .petroleum
        case .tankerLiquid:
            return currentCargo == .liquid ? nil : .liquid
        case .tankerGas:
            return currentCargo == .gas ? nil : .gas
        case .oversized:
            return currentCargo == .oversized ? nil : .oversized
        case .dryVan, .flatbed, .stepDeck, .conestoga, .container,
             .powerOnly, .lowboy, .hotShot,
             .railTOFC, .railCOFC, .railIntermodal,
             .railBoxcar, .railReeferBoxcar, .railHopper,
             .railCenterbeam, .railGondola, .railAutoRack, .railFlatcar,
             .vesselContainer, .vesselBulk, .vesselTanker,
             .vesselRoRo, .vesselLNG, .vesselReeferContainer, .vesselISOTank:
            return nil // any cargo type can ride
        // Mode-specific tanker equipment maps to its native cargo.
        case .railTankGas:
            return currentCargo == .gas ? nil : .gas
        case .railTankLiquid:
            return currentCargo == .liquid ? nil : .liquid
        }
    }
}

// MARK: - Screen wrapper

struct ShipperPostLoadScreen: View {
    let theme: Theme.Palette
    @EnvironmentObject private var session: EusoTripSession

    /// nil = entry-gate shown (founder asked for a list-of-drafts +
    /// new-load-post screen BEFORE the wizard so the autosaved draft
    /// from a previous session doesn't silently load when they meant
    /// to start a fresh post). Resume / Fresh both transition to the
    /// wizard; the gate never re-shows in the same screen instance.
    @State private var entryChoice: EntryChoice? = nil

    private enum EntryChoice { case resume, fresh }

    private var draftStorageKey: String {
        let uid = session.user?.id ?? "anon"
        return "shipper.postLoadDraft.\(uid)"
    }

    var body: some View {
        Shell(theme: theme) {
            if let _ = entryChoice {
                // Wizard takes over. `clearDraft` was called by the
                // .fresh branch before this state flip, so the wizard's
                // hydrate pass finds nothing.
                ShipperPostLoad()
            } else {
                PostLoadDraftsEntryBody(
                    storageKey: draftStorageKey,
                    onResume: { entryChoice = .resume },
                    onFresh: {
                        UserDefaults.standard.removeObject(forKey: draftStorageKey)
                        NSUbiquitousKeyValueStore.default.removeObject(forKey: draftStorageKey)
                        entryChoice = .fresh
                    }
                )
            }
        } nav: {
            BottomNav(
                leading: shipperNavLeading_204(),
                trailing: shipperNavTrailing_204(),
                orbState: .idle
            )
        }
    }
}

/// Entry gate for Post-a-Load — surfaces the single autosaved draft
/// (if any) plus a New-load-post CTA. Reads the wizard's own storage
/// key directly (UserDefaults + iCloud KVS) so there's one source of
/// truth and no separate draft-list service to maintain. Multi-draft
/// support is a follow-up; this entry contract stays the same.
private struct PostLoadDraftsEntryBody: View {
    @Environment(\.palette) private var palette
    let storageKey: String
    let onResume: () -> Void
    let onFresh: () -> Void

    /// Minimal summary used for the draft card — decodes a subset of
    /// the wizard's PostLoadDraftSnapshot fields (Codable matches by
    /// key name; extra fields in the source are ignored).
    private struct DraftSummary: Codable {
        var origin: String = ""
        var destination: String = ""
        var cargoTypeRaw: String = "general"
        var transportModeRaw: String = "truck"
        var equipmentTypeRaw: String = "dry_van"
        var savedAt: Double = 0
    }

    @State private var summary: DraftSummary? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            // Eyebrow + title — mirrors the wizard header so the
            // visual rhythm matches when the gate hands off.
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("✦ SHIPPER · POST A LOAD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Drafts")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, Space.s4)
            .padding(.horizontal, Space.s4)

            if let s = summary, hasUsefulFields(s) {
                draftCard(s)
                    .padding(.horizontal, Space.s4)
            } else {
                emptyDraftsCard
                    .padding(.horizontal, Space.s4)
            }

            // Always-visible "+ New load post" CTA. Tap wipes the
            // autosave first (in onFresh) so the wizard mounts clean.
            Button(action: onFresh) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 17, weight: .heavy))
                    Text("New load post")
                        .font(.system(size: 15, weight: .heavy))
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Space.s4)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { summary = loadSummary() }
    }

    private func hasUsefulFields(_ s: DraftSummary) -> Bool {
        !s.origin.isEmpty || !s.destination.isEmpty || s.savedAt > 0
    }

    private var emptyDraftsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NO SAVED DRAFTS")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text("Start a new load post and the wizard autosaves as you fill it in. You can come back here to pick up where you left off.")
                .font(.system(size: 13))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(palette.borderFaint))
    }

    private func draftCard(_ s: DraftSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("DRAFT · AUTOSAVED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                Text(s.transportModeRaw.uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(alignment: .leading, spacing: 4) {
                row(label: "ORIGIN", value: s.origin.isEmpty ? "-" : s.origin)
                row(label: "DESTINATION", value: s.destination.isEmpty ? "-" : s.destination)
                row(label: "CARGO", value: s.cargoTypeRaw.replacingOccurrences(of: "_", with: " ").capitalized)
                row(label: "EQUIPMENT", value: s.equipmentTypeRaw.replacingOccurrences(of: "_", with: " ").capitalized)
                row(label: "SAVED", value: savedAtLabel(s.savedAt))
            }
            Button(action: onResume) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 15, weight: .heavy))
                    Text("Resume draft")
                        .font(.system(size: 14, weight: .heavy))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(palette.bgCard))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(LinearGradient.diagonal.opacity(0.4), lineWidth: 1)
        )
    }

    private func row(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
        }
    }

    private func savedAtLabel(_ unix: Double) -> String {
        guard unix > 0 else { return "-" }
        let date = Date(timeIntervalSince1970: unix)
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    private func loadSummary() -> DraftSummary? {
        // Prefer iCloud KVS over local UserDefaults (same precedence
        // the wizard uses in hydrateDraftIfPresent).
        let cloud = NSUbiquitousKeyValueStore.default.data(forKey: storageKey)
        let local = UserDefaults.standard.data(forKey: storageKey)
        let chosen: Data? = {
            switch (cloud, local) {
            case (let c?, let l?):
                let cs = (try? JSONDecoder().decode(DraftSummary.self, from: c))?.savedAt ?? 0
                let ls = (try? JSONDecoder().decode(DraftSummary.self, from: l))?.savedAt ?? 0
                return cs >= ls ? c : l
            case (let c?, nil): return c
            case (nil, let l?): return l
            default: return nil
            }
        }()
        guard let data = chosen else { return nil }
        return try? JSONDecoder().decode(DraftSummary.self, from: data)
    }
}

// Doc-router (Templates + Bulk) notification + date parsing helpers.
extension Notification.Name {
    /// Fired by 204 Post-Load after a Bulk classifier session routes
    /// docs. `userInfo["docs"]` is an `[[String: Any]]` summarizing
    /// per-doc classifiedType / dispatchTarget / confidence / summary
    /// for everything beyond the first load-shaped doc (which got
    /// applied as a wizard pre-fill). The shipper Home/Loads tab
    /// listens and queues non-load docs into the appropriate inbox
    /// (certificates, agreements, etc.).
    static let eusoShipperBulkClassifiedRouted =
        Notification.Name("eusoShipperBulkClassifiedRouted")
}

extension DateFormatter {
    /// `YYYY-MM-DD` — the most common Gemini-extracted date shape.
    static let iso_yMd: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    /// `MM/DD/YYYY` — US BOL / Rate Con convention.
    static let iso_mDy: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "MM/dd/yyyy"
        return f
    }()
}

// Shipper bottom-nav doctrine — out of scope per parity mandate §1.
private func shipperNavLeading_204() -> [NavSlot] {
    RoleNav.shipperLeading(current: .createLoad)
}

private func shipperNavTrailing_204() -> [NavSlot] {
    RoleNav.shipperTrailing(current: .none)
}

// MARK: - Previews

#Preview("204 · Shipper · Post Load · Night") {
    ShipperPostLoadScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("204 · Shipper · Post Load · Afternoon") {
    ShipperPostLoadScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
