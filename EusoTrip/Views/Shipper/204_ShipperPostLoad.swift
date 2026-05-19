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
    @State private var tankerHoseSpec: String = ""
    @State private var tankerFitting: String = ""

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

    /// Cached lat/lng tuple of the last query so we don't re-fire
    /// the routing call on every keystroke.
    @State private var lastRoutedKey: String = ""

    /// Computed delivery ETA = pickupDate + routeDurationSeconds.
    /// Returns nil until both values are present.
    private var computedDeliveryETA: Date? {
        guard hasPickupDate, let secs = routeDurationSeconds else { return nil }
        return pickupDate.addingTimeInterval(TimeInterval(secs))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
                .padding(.horizontal, Space.s5)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s5) {
                    stepper
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
        // Autosave on every meaningful field change. Collapsed into
        // a single onChange driven by `autosaveDigest` (a hash of
        // every watched value) — chaining 30+ `.onChange` modifiers
        // overwhelmed Swift's type-checker. The persist helper
        // writes to UserDefaults (local crash recovery) AND
        // NSUbiquitousKeyValueStore (iCloud KVS — cross-device).
        .onChange(of: autosaveDigest) { _, _ in persistDraft() }
        // ERG lookup fires off a separate UN-only debouncer so
        // typing in unrelated fields doesn't trigger a re-lookup.
        .onChange(of: unNumber) { _, _ in lookupERGIfReady() }
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
        // Templates picker (loadTemplates.list — server-backed,
        // visible on web platform too for true cross-device parity)
        .sheet(isPresented: $showTemplatePicker) { templatePickerSheet }
        // Save-as-template (loadTemplates.create)
        .sheet(isPresented: $showSaveTemplateSheet) { saveTemplateSheet }
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
                Text("Class \(hit.hazardClass) · \(hit.placardName)")
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
                            Text("Post a load + tap 'Save as template' on the review step. Saved templates show up here AND on the web platform — same account, same shipping list.")
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
        return "\(o.isEmpty ? "—" : o) → \(d.isEmpty ? "—" : d)"
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
            Text("Saves to your account so you can quick-post the same lane next time. Templates sync across iOS and the web platform — same shipper, same list.")
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
                .clipShape(Capsule())
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
                city: cityFromText(origin),
                state: stateFromText(origin),
                zipCode: nil,
                address: origin.trimmingCharacters(in: .whitespaces),
                facilityName: nil
            )
            let destLoc = LoadTemplatesAPI.TemplateLocation(
                city: cityFromText(destination),
                state: stateFromText(destination),
                zipCode: nil,
                address: destination.trimmingCharacters(in: .whitespaces),
                facilityName: nil
            )
            // Build description with the equipment + subform spec so
            // the catalyst's view of the template carries the full
            // requirements at materialization time.
            let desc = composeSubmissionNotes()
            let input = LoadTemplatesAPI.CreateInput(
                name: name,
                description: desc.isEmpty ? nil : desc,
                origin: originLoc,
                destination: destLoc,
                distance: routeDistanceMeters.map { Double($0) / 1609.34 },
                commodity: properShippingName.isEmpty ? nil : properShippingName,
                cargoType: cargoType.rawValue,
                equipmentType: equipmentType.rawValue,
                weight: weightText.isEmpty ? nil : weightText,
                weightUnit: weightText.isEmpty ? nil : weightUnit.rawValue,
                rate: parseDouble(rateText),
                rateType: rateText.isEmpty ? nil : "flat",
                preferredDays: nil,
                preferredPickupTime: nil,
                specialInstructions: notes.isEmpty ? nil : notes
            )
            let ack = try await EusoTripAPI.shared.loadTemplates.create(input)
            showSaveTemplateSheet = false
            templateSaveAck = "Saved · \(ack.name ?? name)"
        } catch {
            templateSaveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Best-effort city extraction. Pulls the leading piece before
    /// the first comma so "Houston, TX, United States" → "Houston".
    private func cityFromText(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    }

    /// Best-effort state extraction. Pulls the second comma-separated
    /// piece so "Houston, TX, United States" → "TX".
    private func stateFromText(_ raw: String) -> String {
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",")
        guard parts.count >= 2 else { return "" }
        return String(parts[1]).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Draft autosave + iCloud KVS continuity

    /// JSON-encodable snapshot of every field the wizard captures.
    /// Bumped to `v: 2` when adding ERG/equipment fields beyond the
    /// original lane/cargo/rate set so older drafts in storage decode
    /// gracefully (missing fields become defaults).
    private struct PostLoadDraftSnapshot: Codable {
        var v: Int = 2
        var origin: String = ""
        var destination: String = ""
        var originLat: Double? = nil
        var originLng: Double? = nil
        var destLat: Double? = nil
        var destLng: Double? = nil
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

    private func persistDraft() {
        guard didHydrateDraft else { return }   // skip on first hydrate pass
        let snap = PostLoadDraftSnapshot(
            v: 2,
            origin: origin,
            destination: destination,
            originLat: originLat, originLng: originLng,
            destLat: destLat, destLng: destLng,
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
            savedAt: Date().timeIntervalSince1970
        )
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: draftStorageKey)
            // iCloud KVS — synchronous in-memory write; .synchronize()
            // schedules upload. Cross-device propagation handled by
            // Apple's iCloud daemon.
            NSUbiquitousKeyValueStore.default.set(data, forKey: draftStorageKey)
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
        cargoType = ShipperAPI.CargoType(rawValue: snap.cargoTypeRaw) ?? .general
        equipmentType = EquipmentChoice(rawValue: snap.equipmentTypeRaw) ?? .dryVan
        hasPickupDate = snap.hasPickupDate
        if snap.pickupDateUnix > 0 {
            pickupDate = Date(timeIntervalSince1970: snap.pickupDateUnix)
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
    }

    private func clearDraft() {
        UserDefaults.standard.removeObject(forKey: draftStorageKey)
        NSUbiquitousKeyValueStore.default.removeObject(forKey: draftStorageKey)
        NSUbiquitousKeyValueStore.default.synchronize()
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
                    // Bulk upload — XLS / XLSX / CSV / PDF / JSON
                    // for shippers, brokers, dispatchers. Routes to
                    // the existing 400_BulkUploadShell which is
                    // wired to bulkUpload.uploadAndProcess.
                    Button {
                        NotificationCenter.default.post(
                            name: .eusoShipperNavSwap,
                            object: nil,
                            userInfo: ["screenId": "400b"]   // 400b = BulkUploadShell (id below)
                        )
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
                    .accessibilityLabel("Open bulk upload — CSV / XLS / PDF")
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
                              placeholder: "City, ST or lat,lng · e.g. Houston, TX")
                    laneConnector
                    laneField(label: "DESTINATION",
                              text: $destination,
                              lat: $destLat,
                              lng: $destLng,
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
                    placeholder: placeholder
                )
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
            let tmp = origin
            origin = destination
            destination = tmp
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
            return "Add origin + destination — distance / ETA estimates auto-fill"
        }
        if isRouting {
            return "Computing distance + ETA via ESANG…"
        }
        if let err = routingError {
            return "Routing error: \(err)"
        }
        if let meters = routeDistanceMeters, let secs = routeDurationSeconds {
            let miles = Double(meters) / 1609.34
            // Mode-aware ETA + profile label. HERE Routing v8 only
            // serves the truck path; for rail / vessel / barge we
            // re-derive transit time from a mode-appropriate avg
            // speed because there's no national multi-modal router.
            // Numbers come from industry rule-of-thumbs that the
            // founder can override per-load in Step 3 pricing.
            //   • Rail intermodal: 28 mph avg incl. ramp dwell
            //     (BNSF / UP cross-country mainline)
            //   • Vessel feeder: 15 knots ≈ 17.3 mph
            //   • ATB barge tow: 7 knots ≈ 8.1 mph
            // HERE's `secs` value is reused as the truck-equivalent
            // hours; for the other modes we recompute from `miles`.
            let hours: Double = {
                switch transportMode {
                case .truck:  return Double(secs) / 3600.0
                case .rail:   return miles / 28.0
                case .vessel: return miles / 17.3
                case .barge:  return miles / 8.1
                }
            }()
            let profile: String = {
                switch transportMode {
                case .truck:  return "standard US semi"
                case .rail:   return "UP / BNSF intermodal (28 mph avg)"
                case .vessel: return "feeder vessel (15 kn)"
                case .barge:  return "ATB barge tow (7 kn)"
                }
            }()
            let etaStr: String = hours > 48
                ? String(format: "%.1f days", hours / 24.0)
                : String(format: "%.1f hr", hours)
            return String(format: "%.0f mi · %@ · %@ · ESANG-routed", miles, etaStr, profile)
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
            return
        }
        let key = "\(originLat ?? .nan),\(originLng ?? .nan)|\(destLat ?? .nan),\(destLng ?? .nan)|\(oTrim)|\(dTrim)"
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
                await MainActor.run {
                    if originLat == nil { originLat = originResolved.coord.latitude }
                    if originLng == nil { originLng = originResolved.coord.longitude }
                    if destLat == nil   { destLat   = destResolved.coord.latitude   }
                    if destLng == nil   { destLng   = destResolved.coord.longitude  }
                    self.originStateCode = originResolved.stateCode
                    self.destStateCode   = destResolved.stateCode
                }
                let resp = try await HereRoutingClient.shared.route(
                    stops: HereStops(origin: originResolved.coord,
                                     destination: destResolved.coord),
                    profile: .standardUSSemiLoaded
                )
                let totalDuration = resp.routes.first?.sections.reduce(0) { $0 + ($1.summary?.duration ?? 0) } ?? 0
                let totalLength   = resp.routes.first?.sections.reduce(0) { $0 + ($1.summary?.length ?? 0) }   ?? 0
                await MainActor.run {
                    self.routeDurationSeconds = totalDuration
                    self.routeDistanceMeters  = totalLength
                    self.isRouting = false
                    // Now that we have lane states + distance, fire
                    // the rate compare if the user has already typed
                    // a posted rate.
                    self.recomputeRateCompareIfReady()
                }
            } catch {
                await MainActor.run {
                    self.routingError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.isRouting = false
                }
            }
        }
    }

    // MARK: - ESANG rate vs market meter (rates.compareLaneRate)

    /// Fires `rates.compareLaneRate` when origin state + dest state +
    /// distance + a posted rate are all known. Web parity meter; same
    /// `LaneComparison` envelope the LoadDetailSheet renders next to
    /// the posted rate.
    private func recomputeRateCompareIfReady() {
        guard let oState = originStateCode, !oState.isEmpty,
              let dState = destStateCode,   !dState.isEmpty,
              let meters = routeDistanceMeters, meters > 0,
              let rate = parseDouble(rateText), rate > 0 else {
            rateComparison = nil
            rateCompareError = nil
            return
        }
        let miles = Double(meters) / 1609.34
        let key = "\(oState)|\(dState)|\(Int(miles))|\(Int(rate))|\(cargoType.rawValue)"
        guard key != lastRateCompareKey else { return }
        lastRateCompareKey = key
        isComparingRate = true
        rateCompareError = nil
        Task {
            do {
                let r = try await EusoTripAPI.shared.rates.compareLaneRate(
                    originState: oState,
                    destState:   dState,
                    rate:        rate,
                    distance:    miles,
                    cargoType:   cargoType.rawValue,
                    lookbackDays: 90
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
                        // Auto-populate ONLY when the user hasn't
                        // already typed a value — never overwrite
                        // explicit entry.
                        if hazmatClass.isEmpty, let cls = detail.hazardClass {
                            hazmatClass = cls
                        }
                        if properShippingName.isEmpty, let name = detail.name {
                            properShippingName = name.uppercased()
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

    /// Apply a search-hit selection from the ERG search sheet —
    /// prefills UN + class + shipping name; the subsequent
    /// `erg.searchByUN` finishes hydrating the full match.
    private func applyERGHit(_ hit: ErgAPI.SearchHit) {
        unNumber = hit.unNumber
        hazmatClass = hit.hazardClass
        properShippingName = hit.placardName.isEmpty ? hit.name.uppercased() : hit.placardName
        showErgSearchSheet = false
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
        guard let first = hits.first else {
            throw HereMapsError.providerError("No geocode result for '\(text)'")
        }
        return ResolvedAddress(
            coord: CLLocationCoordinate2D(latitude: first.position.lat, longitude: first.position.lng),
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
                Text("PICKUP")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
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
                DatePicker("Pickup", selection: $pickupDate, in: Date()..., displayedComponents: [.date])
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
            Text("DELIVERY")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
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
        if weightLbs > 0 && (oOver || dOver) {
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
        } else if weightLbs > 0 && !anyOver && !oState.isEmpty && !dState.isEmpty {
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
    fileprivate static func stateFromLane(_ raw: String) -> String {
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ",")
        guard parts.count >= 2 else { return "" }
        let candidate = String(parts[1]).trimmingCharacters(in: .whitespaces).prefix(2).uppercased()
        return String(candidate)
    }

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
    fileprivate static let trailerHazmatAllowed: [String: [String]] = [
        "liquid_tank": ["3", "5.1", "5.2", "6.1", "8"],
        "gas_tank":    ["2.1", "2.2", "2.3"],
        "hazmat_van":  ["1", "1.1", "1.2", "1.3", "1.4", "1.5", "1.6",
                        "2.1", "2.2", "2.3", "3", "4.1", "4.2", "4.3",
                        "5.1", "5.2", "6.1", "6.2", "7", "8", "9"],
        "dry_van":     ["9"],
        "reefer":      ["9"],
        "flatbed":     ["9"],
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
        return out.isEmpty ? ["—"] : out
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
        return matches.isEmpty ? ["—"] : matches
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
                Text(equipmentType.vertical.uppercased())
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(LinearGradient.diagonal)
            }
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
            reeferLowText: reeferTempLowText,
            reeferHighText: reeferTempHighText,
            preCoolRequired: preCoolRequired,
            continuousMode: continuousMode,
            flatbedStraps: flatbedStraps,
            flatbedTarps: flatbedTarps,
            flatbedChains: flatbedChains,
            flatbedEdgeProtectors: flatbedEdgeProtectors,
            oversizePermits: oversizePermits
        )
        .frame(height: 180)
    }

    @ViewBuilder
    private var equipmentSubform: some View {
        // Animation always renders — silhouette adapts to every
        // equipment + product choice. Subform-specific cards stack
        // beneath the animation.
        equipmentAnimation
        switch equipmentType {
        case .tankerHazmat, .tankerPetro, .tankerLiquid, .tankerGas, .vesselTanker:
            tankerSubform
        case .reefer:
            reeferSubform
        case .flatbed, .stepDeck, .conestoga, .oversized:
            flatbedSubform
        default:
            EmptyView()
        }
    }

    // MARK: tanker subform (hazmat / petroleum / chemicals / gas / liquid)

    @ViewBuilder
    private var tankerSubform: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "drop.triangle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(tankerSubformLabel)
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            // Hose configuration — driver/catalyst needs to know what
            // fittings + diameter to bring. Stored in `notes` on the
            // load envelope until the backend ships a structured
            // tanker spec field.
            HStack(spacing: 8) {
                tankerChip(label: "2\" cam-lock",     selected: tankerHoseSpec == "2_camlock")
                tankerChip(label: "3\" cam-lock",     selected: tankerHoseSpec == "3_camlock")
                tankerChip(label: "4\" cam-lock",     selected: tankerHoseSpec == "4_camlock")
                tankerChip(label: "Dry-disconnect",   selected: tankerHoseSpec == "dry_disconnect")
            }
            HStack(spacing: 8) {
                tankerChip(label: "API adapter",       selected: tankerFitting == "api")
                tankerChip(label: "TTMA",              selected: tankerFitting == "ttma")
                tankerChip(label: "Other",             selected: tankerFitting == "other")
                Spacer(minLength: 0)
            }
            // UN / hazmat fields surface only for the hazmat/petroleum
            // / chemicals branches (gas + liquid are food-grade or
            // non-hazmat liquids). Mirrors the web Hazmat subform.
            if cargoType == .hazmat || cargoType == .petroleum || cargoType == .chemicals {
                Divider().background(palette.borderFaint).padding(.vertical, 2)
                tankerHazmatRow
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
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
                    Text((m.name ?? "—").capitalized)
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
        case (.tankerHazmat, _):     return "TANKER · HAZMAT (MC-306) REQUIREMENTS"
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
        let tint: Color = est.sensible ? Brand.success : Brand.warning
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: est.sensible ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(tint)
                Text(est.sensible ? "VEHICLES NEEDED" : "MODE MISMATCH")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                Text("\(est.vehicleCount) × \(transportMode.displayName.lowercased())")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.4)
                    .foregroundStyle(palette.textPrimary)
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
        guard !ct.isHazmatFlavored else { return }
        unNumber = ""
        hazmatClass = ""
        packingGroup = ""
        properShippingName = ""
        tankerHoseSpec = ""
        tankerFitting = ""
        ergMatch = nil
        ergLookupError = nil
        lastErgQueryKey = ""
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
                let cls = (m.hazardClass ?? hazmatClass).isEmpty ? "—" : (m.hazardClass ?? hazmatClass)
                let pg  = packingGroup.isEmpty ? "" : " · PG \(packingGroup)"
                let hose = tankerHoseSpec.isEmpty ? "" : " · \(hoseLabel(tankerHoseSpec))"
                return "UN\(un) · Class \(cls)\(pg)\(hose)"
            }
            // 2. User has typed a UN but ERG hasn't matched yet — show
            //    what they typed honestly.
            let typedUN = unNumber.uppercased().replacingOccurrences(of: "UN", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !typedUN.isEmpty {
                let cls = hazmatClass.isEmpty ? "—" : hazmatClass
                let pg  = packingGroup.isEmpty ? "" : " · PG \(packingGroup)"
                return "UN\(typedUN) · Class \(cls)\(pg)\(isLookingUpERG ? " · looking up…" : "")"
            }
        }
        // 3. Equipment type drives the spec when no UN entered yet.
        switch equipmentType {
        case .tankerHazmat:    return "MC-306 · awaiting UN"
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
        case .oversized:       return oversizeDimsText.contains("—") ? "Oversized · dims pending" : oversizeDimsText
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
            notesField
        }
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
            return "Linehaul total — divided by route miles for the $/mile market compare."
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
                    Text(cmp.source == "national_benchmark" ? "national" : "platform")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
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
            } else if originStateCode == nil || destStateCode == nil {
                Text("Resolving lane states for market compare…")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            } else if let routeErr = routingError {
                // Route call failed — surface here too so the user
                // doesn't see a stuck "computing distance" state on
                // step 3 with no path to recover. Mirrors the route
                // meta strip on step 1.
                Text("Route error: \(routeErr) — go back to step 1 to retry")
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            } else if (routeDistanceMeters ?? 0) <= 0 {
                Text("Distance computing — meter populates after route resolves")
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

    @ViewBuilder
    private func rateMeterBody(_ cmp: RatesAPI.LaneComparison) -> some View {
        let (positionLabel, positionColor) = positionStyling(for: cmp.position)
        let (ratingLabel, ratingColor) = ratingStyling(percentile: cmp.percentile,
                                                        position: cmp.position)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(dollars(cmp.yourRate))
                    .font(.system(size: 24, weight: .bold).monospacedDigit())
                    .foregroundStyle(LinearGradient.diagonal)
                Text(String(format: "$%.2f / mi", cmp.yourRPM))
                    .font(EType.caption).monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
                Text(positionLabel)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(positionColor))
            }
            // Range bar: market min -- your rate marker -- market max
            rateRangeBar(cmp: cmp)
            HStack(spacing: Space.s2) {
                Text(ratingLabel)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(ratingColor))
                Text("\(cmp.percentile)th percentile · n=\(cmp.sampleSize)")
                    .font(EType.caption).monospacedDigit()
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
            }
            Text(cmp.recommendation)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func rateRangeBar(cmp: RatesAPI.LaneComparison) -> some View {
        // Map yourRPM into [min, max] range for the marker offset.
        let lo = cmp.marketMinRPM
        let hi = cmp.marketMaxRPM
        let v  = cmp.yourRPM
        // Clamp + normalize. If hi == lo (rare), draw the marker
        // centered.
        let pct: Double = {
            guard hi > lo else { return 0.5 }
            let raw = (v - lo) / (hi - lo)
            return min(1.0, max(0.0, raw))
        }()
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: [Brand.success, Brand.info, Brand.warning],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 8)
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(LinearGradient.diagonal, lineWidth: 2))
                    .offset(x: max(0, geo.size.width * pct - 8))
            }
        }
        .frame(height: 18)
        HStack {
            Text(String(format: "$%.2f / mi · min", lo))
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary).monospacedDigit()
            Spacer(minLength: 0)
            Text(String(format: "$%.2f / mi · avg", cmp.marketAvgRPM))
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary).monospacedDigit()
            Spacer(minLength: 0)
            Text(String(format: "$%.2f / mi · max", hi))
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary).monospacedDigit()
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
    private func ratingStyling(percentile: Int, position: String) -> (String, Color) {
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
                "Anything carriers should know — temperature ranges, dock hours, COI…",
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
            .overlay(Capsule().strokeBorder(LinearGradient.diagonal.opacity(0.55), lineWidth: 1))
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
            reviewRow(label: "Quantity",       value: parseDouble(weightText).map { "\(formatQty($0)) \(weightUnit.rawValue)" } ?? "—")

            reviewSection("FREIGHT CHARGE")
            reviewRow(label: "Posted rate",    value: parseDouble(rateText).map(dollars) ?? "—", isHero: true)
            if let cmp = rateComparison {
                Divider().overlay(palette.borderFaint)
                reviewRow(label: "Vs market",  value: "\(cmp.position.replacingOccurrences(of: "_", with: " ")) · \(cmp.percentile)th pct")
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
                reviewRow(label: "Position",   value: cmp.position.replacingOccurrences(of: "_", with: " "))
                Divider().overlay(palette.borderFaint)
                reviewRow(label: "Your $/mi",  value: String(format: "$%.2f", cmp.yourRPM))
                Divider().overlay(palette.borderFaint)
                reviewRow(label: "Market avg", value: String(format: "$%.2f / mi", cmp.marketAvgRPM))
                Divider().overlay(palette.borderFaint)
                reviewRow(label: "Percentile", value: "\(cmp.percentile)th · n=\(cmp.sampleSize)")
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
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
            if let err = routingError { return "error: \(err)" }
            return "—"
        }
        return String(format: "%.0f mi", Double(m) / 1609.34)
    }

    private var deliveryReviewText: String {
        if let eta = computedDeliveryETA {
            return deliveryETAFormatter.string(from: eta)
        }
        if hasPickupDate { return "—" }
        return "Catalyst proposes"
    }

    private var reeferTempRangeText: String {
        let lo = reeferTempLowText.trimmingCharacters(in: .whitespaces)
        let hi = reeferTempHighText.trimmingCharacters(in: .whitespaces)
        if lo.isEmpty && hi.isEmpty { return "—" }
        return "\(lo.isEmpty ? "—" : lo)°F – \(hi.isEmpty ? "—" : hi)°F"
    }

    private var flatbedGearText: String {
        var gear: [String] = []
        if flatbedStraps          { gear.append("straps") }
        if flatbedTarps           { gear.append("tarps") }
        if flatbedChains          { gear.append("chains") }
        if flatbedEdgeProtectors  { gear.append("edge protectors") }
        return gear.isEmpty ? "—" : gear.joined(separator: ", ")
    }

    private var oversizeDimsText: String {
        let l = oversizeLengthText.trimmingCharacters(in: .whitespaces)
        let w = oversizeWidthText.trimmingCharacters(in: .whitespaces)
        let h = oversizeHeightText.trimmingCharacters(in: .whitespaces)
        if l.isEmpty && w.isEmpty && h.isEmpty { return "—" }
        return "L \(l.isEmpty ? "—" : l) · W \(w.isEmpty ? "—" : w) · H \(h.isEmpty ? "—" : h) ft"
    }

    private func hoseLabel(_ raw: String) -> String {
        switch raw {
        case "2_camlock":     return "2\" cam-lock"
        case "3_camlock":     return "3\" cam-lock"
        case "4_camlock":     return "4\" cam-lock"
        case "dry_disconnect":return "Dry-disconnect"
        case "":              return "—"
        default:              return raw
        }
    }

    private func fittingLabel(_ raw: String) -> String {
        switch raw {
        case "api":   return "API adapter"
        case "ttma":  return "TTMA"
        case "other": return "Other"
        case "":      return "—"
        default:      return raw
        }
    }

    private func nonEmpty(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "—" : t
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
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
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
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
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
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't post that load")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(message)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            Button { store.reset() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
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
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                }
                Text(ctaText)
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                Capsule().fill(canAdvance
                               ? AnyShapeStyle(LinearGradient.primary)
                               : AnyShapeStyle(palette.tintNeutral.opacity(0.4)))
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canAdvance)
        .accessibilityLabel(ctaText)
    }

    private var ctaText: String {
        if case .success = store.phase, step == .review { return "Post another" }
        if step == .review {
            return isSubmitting ? "Posting…" : "Post this load"
        }
        guard let next = step.next else { return "Continue" }
        return "Continue · Step \(next.rawValue) of \(PostLoadStep.allCases.count) →"
    }

    private var canAdvance: Bool {
        if isSubmitting { return false }
        switch step {
        case .lane:
            let oTrim = origin.trimmingCharacters(in: .whitespacesAndNewlines)
            let dTrim = destination.trimmingCharacters(in: .whitespacesAndNewlines)
            return !oTrim.isEmpty && !dTrim.isEmpty
        case .equipment:
            // 2026-05-17 — Gate the equipment step on hazmat compliance
            // (49 CFR 173). If the user picked a hazmat class that's
            // not allowed on the selected trailer code, block continue
            // and surface the warning inline. Non-hazmat loads pass.
            if !hazmatClass.isEmpty {
                let code = trailerHazmatCode(for: equipmentType)
                let allowed = Self.trailerHazmatAllowed[code] ?? []
                if !allowed.contains(hazmatClass) { return false }
            }
            // 2026-05-17 — Gate on the state-overweight check too.
            // Allow advance when the user has acknowledged the
            // overweight scenario via an overweight or superload
            // permit; block when the weight exceeds the binding
            // state limit and no permit is set.
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
            // 2026-05-17 — Gate on the reefer temp-range validation.
            // When the user typed any temp value, an issue string is
            // returned by `reeferRangeIssue` and we block until they
            // either clear / correct the range or pick a different
            // equipment that doesn't need a temp window.
            if equipmentType == .reefer && reeferRangeIssue != nil { return false }
            return true
        case .pricing, .review:
            return true
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
        let pickupISO = hasPickupDate ? isoDate(pickupDate) : nil
        let weight    = parseDouble(weightText)
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
        let rateUnitWire: String = {
            switch transportMode {
            case .truck:  return "usd_per_mile"
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
        }()
        // When the user posts a vessel tanker load, the value typed in
        // the rate field is a Worldscale percent — capture it on the
        // dedicated `worldscalePct` column for downstream tanker market
        // compares, and zero out the plain dollar rate so the rate-vs-
        // market server query doesn't misread it as a truck $/mile.
        let worldscaleWire: Double? = (transportMode == .vessel && equipmentType == .vesselTanker)
            ? parseDouble(rateText)
            : nil
        let rateForWire: Double? = worldscaleWire == nil ? rate : nil
        await store.submit(
            origin: origin,
            destination: destination,
            cargoType: cargoType,
            rate: rateForWire,
            weight: weight,
            notes: composedNotes,
            pickupDate: pickupISO,
            originLat: originLat,
            originLng: originLng,
            destLat: destLat,
            destLng: destLng,
            transportMode: transportMode,
            multiVehicleCount: multiVehicleEstimate?.vehicleCount,
            permitType: permitRaw,
            worldscalePct: worldscaleWire,
            rateUnit: rateUnitWire,
            equipmentType: equipmentType.rawValue
        )
        if case .success(let ack) = store.phase {
            self.lastSuccess = ack
            resetForm()
        }
    }

    /// Concatenates equipment + subform fields into a single notes
    /// string. Web parity — the catalyst's load-detail surface
    /// surfaces these as a "REQUIREMENTS" block under the BOL.
    /// Always prepends the user's free-form notes if non-empty.
    private func composeSubmissionNotes() -> String {
        var lines: [String] = []
        if !notes.isEmpty { lines.append(notes) }
        // 2026-05-17 — Mode line is the first machine-readable token in
        // the notes block. Catalyst + dispatch parse this until the
        // server `shippers.create` input carries transport_mode
        // natively (migration 0307 + tRPC input extension).
        lines.append("Mode: \(transportMode.displayName) [\(transportMode.rawValue)] · rate-unit=\(transportMode.nativeRateUnit)")
        lines.append("Equipment: \(equipmentType.label) [\(equipmentType.rawValue)] · vertical=\(equipmentType.vertical)")
        if !weightText.isEmpty {
            lines.append("Quantity: \(weightText) \(weightUnit.rawValue) (\(weightUnit.longLabel))")
        }
        switch equipmentType {
        case .tankerHazmat, .tankerPetro, .tankerLiquid, .tankerGas, .vesselTanker:
            if !tankerHoseSpec.isEmpty { lines.append("Tanker hose: \(tankerHoseSpec)") }
            if !tankerFitting.isEmpty  { lines.append("Tanker fitting: \(tankerFitting)") }
            if !unNumber.isEmpty       { lines.append("UN: \(unNumber)") }
            if !hazmatClass.isEmpty    { lines.append("Hazmat class: \(hazmatClass)") }
            if !packingGroup.isEmpty   { lines.append("Packing group: \(packingGroup)") }
            if !properShippingName.isEmpty { lines.append("Proper shipping name: \(properShippingName)") }
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
        // Wipe autosave so the next user doesn't see stale draft.
        clearDraft()
    }

    private func parseDouble(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let cleaned = trimmed.replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
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

    private func dollars(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$0"
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

    var body: some View {
        Shell(theme: theme) {
            ShipperPostLoad()
        } nav: {
            BottomNav(
                leading: shipperNavLeading_204(),
                trailing: shipperNavTrailing_204(),
                orbState: .idle
            )
        }
    }
}

// Shipper bottom-nav doctrine — out of scope per parity mandate §1.
private func shipperNavLeading_204() -> [NavSlot] {
    [NavSlot(label: "Home",        systemImage: "house",                              isCurrent: false),
     NavSlot(label: "Create Load", systemImage: "plus.rectangle.on.rectangle.fill",   isCurrent: true)]
}

private func shipperNavTrailing_204() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
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
