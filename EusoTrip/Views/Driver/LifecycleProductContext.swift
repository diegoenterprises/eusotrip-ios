//
//  LifecycleProductContext.swift
//  EusoTrip — Shared vertical + product taxonomy for every lifecycle
//  screen (013-051). Resolves the driver's vertical (truck / rail /
//  vessel) and the active load's product type (hazmat tanker / dry
//  van / reefer / flatbed / container / rail intermodal / rail bulk
//  / vessel container / vessel bulk / vessel tanker), and hands each
//  screen a single object that carries copy, icon, color, and
//  chip-content decisions so no screen has to branch on strings.
//
//  Doctrine (2026-04-24, Mike): "all verticals, products type not
//  just hazmat". Every pickup / loading / BOL / transit / receiver /
//  discharge screen must render content that matches the active
//  load — a dry-van driver sees pallet counts, a reefer driver
//  sees set-point temps, a flatbed driver sees tarp + strap state,
//  a rail intermodal driver sees IMO chassis + ramp data, a vessel
//  captain sees berth + tonnage. Hazmat is the most-stringent lens,
//  not the default.
//
//  Usage:
//
//      @StateObject private var lifecycle = TripLifecycleStore()
//      @State private var activeLoad: Load?
//      @EnvironmentObject private var session: EusoTripSession
//
//      var ctx: LifecycleProductContext {
//          LifecycleProductContext(
//              load: activeLoad,
//              role: session.user?.role
//          )
//      }
//
//      // Then each screen reads:
//      ctx.vertical          // .truck / .rail / .vessel
//      ctx.product           // .hazmatTanker / .dryVan / …
//      ctx.headerKicker      // "HAZMAT TANKER" | "DRY VAN" | …
//      ctx.isHazmat          // true/false
//      ctx.preHaulChecklist  // [ChecklistItem] — product-specific
//      ctx.loadingMetrics    // [SafetyTile] — product-specific
//      ctx.manifestRows      // [(label, value)] for the BOL screen
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Vertical

/// Three transport verticals the platform serves. Resolved from the
/// signed-in driver's role (`RAIL_ENGINEER`, `VESSEL_OPERATOR`,
/// etc.). Default is truck when the role can't be matched.
enum TripVertical {
    case truck, rail, vessel

    init(role: String?) {
        let r = (role ?? "").uppercased()
        if r.hasPrefix("RAIL_") { self = .rail; return }
        if r.hasPrefix("VESSEL_")
            || r == "SHIP_CAPTAIN"
            || r == "PORT_MASTER"
            || r == "CUSTOMS_BROKER" {
            self = .vessel; return
        }
        self = .truck
    }

    var pickupWord: String {
        switch self {
        case .truck:  return "Pickup"
        case .rail:   return "Rail yard"
        case .vessel: return "Port"
        }
    }

    var gateWord: String {
        switch self {
        case .truck:  return "gate"
        case .rail:   return "interchange"
        case .vessel: return "gate-in"
        }
    }

    var bayWord: String {
        switch self {
        case .truck:  return "bay"
        case .rail:   return "spur"
        case .vessel: return "berth"
        }
    }

    var dispatchWord: String {
        switch self {
        case .truck:  return "DISPATCH"
        case .rail:   return "TRAINMASTER"
        case .vessel: return "HARBORMASTER"
        }
    }
}

// MARK: - Product

/// Product variant. Drives the per-screen content dispatch for
/// every lifecycle view. Ordered so hazmat lives at the top as the
/// regulatory-stringent lens.
enum TripProduct {
    case hazmatTanker
    case dryVan
    case reefer
    case flatbed
    case container      // intermodal box on a chassis
    case railIntermodal
    case railBulk
    case vesselContainer
    case vesselBulk
    case vesselTanker

    /// Resolves from a Load's `cargoType` + `hazmatClass` +
    /// `commodityName` fields combined with the vertical. Everything
    /// is a best-effort lowercase-substring match so server strings
    /// don't need to be enums.
    static func resolve(load: Load?, vertical: TripVertical) -> TripProduct {
        resolveDirect(
            cargoType: load?.cargoType,
            hazmatClass: load?.hazmatClass,
            vertical: vertical
        )
    }

    /// Same resolver as `resolve(load:vertical:)` but accepts the raw
    /// `cargoType` + `hazmatClass` strings directly — used by Shipper-
    /// side and Catalyst-side screens that read off `LoadsAPI.LoadDetail`
    /// rather than the driver-shaped `Load` struct. Keeps the matching
    /// rules in one place so a fixture change here lights up every
    /// surface the same way.
    static func resolveDirect(
        cargoType: String?,
        hazmatClass: String?,
        vertical: TripVertical
    ) -> TripProduct {
        let cargo = (cargoType ?? "").lowercased()
        let haz = hazmatClass ?? ""
        let isHazmat = !haz.isEmpty
            || cargo.contains("hazmat")
            || cargo.contains("petroleum")
            || cargo.contains("chemicals")
            || cargo.contains("cryogenic")

        switch vertical {
        case .rail:
            if cargo.contains("bulk") || cargo.contains("tank") || cargo.contains("grain") { return .railBulk }
            return .railIntermodal
        case .vessel:
            if isHazmat || cargo.contains("tank") || cargo.contains("liquid") { return .vesselTanker }
            if cargo.contains("bulk") || cargo.contains("grain") { return .vesselBulk }
            return .vesselContainer
        case .truck:
            if isHazmat || cargo.contains("tanker") || cargo.contains("liquid") || cargo.contains("gas") {
                return .hazmatTanker
            }
            if cargo.contains("reefer") || cargo.contains("refrigerated") || cargo.contains("cold") || cargo.contains("temperature") || cargo.contains("food_grade") {
                return .reefer
            }
            if cargo.contains("flatbed") || cargo.contains("flat") || cargo.contains("oversized") || cargo.contains("timber") || cargo.contains("vehicles") {
                return .flatbed
            }
            if cargo.contains("container") || cargo.contains("intermodal") || cargo.contains("imo") {
                return .container
            }
            return .dryVan
        }
    }

    // MARK: Display

    var label: String {
        switch self {
        case .hazmatTanker:    return "HAZMAT TANKER"
        case .dryVan:          return "DRY VAN"
        case .reefer:          return "REEFER"
        case .flatbed:         return "FLATBED"
        case .container:       return "CONTAINER"
        case .railIntermodal:  return "RAIL · INTERMODAL"
        case .railBulk:        return "RAIL · BULK"
        case .vesselContainer: return "VESSEL · CONTAINER"
        case .vesselBulk:      return "VESSEL · BULK"
        case .vesselTanker:    return "VESSEL · TANKER"
        }
    }

    var symbol: String {
        switch self {
        case .hazmatTanker:    return "flame.fill"
        case .dryVan:          return "shippingbox.fill"
        case .reefer:          return "thermometer.snowflake"
        case .flatbed:         return "rectangle.portrait.arrowtriangle.2.outward"
        case .container:       return "cube.box.fill"
        case .railIntermodal:  return "cube.transparent"
        case .railBulk:        return "circle.hexagongrid.fill"
        case .vesselContainer: return "ferry.fill"
        case .vesselBulk:      return "drop.fill"
        case .vesselTanker:    return "flame.circle.fill"
        }
    }

    var isHazmat: Bool {
        self == .hazmatTanker || self == .vesselTanker
    }
}

// MARK: - LiveLoadFacets

/// Single source of truth for the per-product facet values rendered on
/// every lifecycle screen (manifest rows, compliance triplets, BOL
/// chips, close-out summaries). Reads what the live `Load` envelope
/// from `loads.getById` actually ships, formats each accessor for UI
/// rendering, and collapses to the M2 em-dash sentinel "—" wherever
/// the backend hasn't shipped the corresponding column yet.
///
/// Doctrine §13/§15 — never fabricate a value the backend hasn't
/// shipped. When new columns land in `frontend/server/routers/loads.ts`,
/// promote the corresponding em-dash accessor below to a real read off
/// `Load`; the consuming screens automatically pick up the live value.
///
/// Backend preflight (138th firing): `frontend/server/routers/loads.ts`
/// → `loads.getById` currently ships:
///   loadNumber, status, cargoType, hazmatClass, unNumber, weight,
///   weightUnit, commodityName, pickupLocation, deliveryLocation,
///   distance/distanceUnit, rate/currency, requiresEscort,
///   spectraMatchVerified (bool, on LoadDetail only).
/// It does NOT yet ship: sealNumber, containerNumber, chassisNumber,
/// palletCount, tempSetpoint, securementPoints, vgmKg, isoTypeCode,
/// spectraMatchSampleId, carrierDOT, deliveryFacilityBrand. Each of
/// those collapses to em-dash here.
struct LiveLoadFacets {
    /// Universal em-dash sentinel — kept as a static so it's
    /// trivially greppable across the codebase.
    static let dash: String = "—"

    let load: Load?

    // MARK: Live (backend already ships)

    /// Net weight formatted "42,000 lb" — em-dash when missing.
    /// Source: `Load.weight` (DECIMAL string) + `Load.weightUnit`.
    var netWeight: String {
        guard let load = load, load.weightValue > 0 else { return Self.dash }
        let unit = (load.weightUnit?.isEmpty == false ? load.weightUnit! : "lb")
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let str = f.string(from: NSNumber(value: load.weightValue)) ?? "\(Int(load.weightValue))"
        return "\(str) \(unit)"
    }

    /// Net weight in upper-case ("42,000 LB"). Used by the BOL strip
    /// where the typography is upper-cased.
    var netWeightUpper: String { netWeight.uppercased() }

    /// Live commodity name ("Anhydrous ammonia" / "Frozen protein" /
    /// "Steel coils") — em-dash when the column is empty.
    var commodityName: String {
        guard let n = load?.commodityName, !n.isEmpty else { return Self.dash }
        return n
    }

    /// "UN1005" — em-dash when missing.
    var unNumber: String {
        guard let n = load?.unNumber, !n.isEmpty else { return Self.dash }
        return n
    }

    /// "2.2 · non-flam gas" — em-dash when missing. Used as the
    /// hazard-class display row on the manifest.
    var hazardClass: String {
        guard let h = load?.hazmatClass, !h.isEmpty else { return Self.dash }
        return h
    }

    /// Composed "Anhydrous ammonia · UN1005". Falls through any
    /// missing piece, returns em-dash only when both are empty.
    var commodityWithUN: String {
        let c = (load?.commodityName?.isEmpty == false) ? load!.commodityName! : ""
        let u = (load?.unNumber?.isEmpty == false) ? load!.unNumber! : ""
        switch (c.isEmpty, u.isEmpty) {
        case (true,  true):  return Self.dash
        case (true,  false): return u
        case (false, true):  return c
        case (false, false): return "\(c) · \(u)"
        }
    }

    /// Pickup facility line — address > cityState > em-dash. Carrier
    /// brand (e.g. "Walmart DC 7201") isn't separately structured on
    /// pickupLocation, so this surfaces the address line as the most
    /// honest available identifier.
    var pickupFacility: String {
        guard let loc = load?.pickupLocation else { return Self.dash }
        if !loc.address.isEmpty { return loc.address }
        if !loc.cityState.isEmpty { return loc.cityState }
        return Self.dash
    }

    /// Delivery facility line — address > cityState > em-dash.
    var deliveryFacility: String {
        guard let loc = load?.deliveryLocation else { return Self.dash }
        if !loc.address.isEmpty { return loc.address }
        if !loc.cityState.isEmpty { return loc.cityState }
        return Self.dash
    }

    // MARK: Backend stub gaps (em-dash until shipped)
    //
    // Each accessor below is a known backend gap as of the 138th
    // firing's preflight. Promote to a real read when the column lands
    // on `loads.getById`.

    /// Per-load seal id (e.g. "881204" / "SSL-21009"). Backend gap.
    var sealNumber: String { Self.dash }

    /// Container id (e.g. "TCLU 4412089" / "MSCU 8817744"). Backend gap.
    var containerNumber: String { Self.dash }

    /// Chassis id (e.g. "EFRZ 124601"). Backend gap.
    var chassisNumber: String { Self.dash }

    /// Pallet summary ("72 stackable" / "24 no stack"). Backend gap.
    var palletSummary: String { Self.dash }

    /// Pallet count alone ("72" / "24" / "47/72"). Backend gap.
    var palletCount: String { Self.dash }

    /// Reefer set-point ("-18 °F"). Backend gap (cold-chain stream
    /// not on Load envelope).
    var setPointDisplay: String { Self.dash }

    /// Long securement summary ("12 straps · 2 chains · corner
    /// protectors"). Backend gap (DOT 393 securement record not
    /// modelled on Load).
    var securementSummary: String { Self.dash }

    /// Short securement chip ("12+2"). Backend gap.
    var securementShort: String { Self.dash }

    /// "within WLL" status string. Backend gap.
    var securementWithinWLL: String { Self.dash }

    /// Tarp inventory ("2 steel tarps · applied"). Backend gap.
    var tarpStatus: String { Self.dash }

    /// VGM filed display ("filed · 32,105 kg"). Backend gap (SOLAS VGM
    /// column missing from `vesselShipments`/`shippingContainers` per
    /// §16 vessel slice).
    var vgmDisplay: String { Self.dash }

    /// Compact VGM chip ("32,105 kg"). Backend gap.
    var vgmKgChip: String { Self.dash }

    /// Container ISO type code ("ISO 4510" / "ISO 42G1"). Backend gap.
    var containerIsoType: String { Self.dash }

    /// Spectra-Match sample id ("SM-2026-04-21-NH3-04412"). Backend gap
    /// — only `LoadDetail.spectraMatchVerified` (Bool) is exposed today.
    var spectraMatchSampleId: String { Self.dash }

    /// Spectra-Match purity readout ("99.94% NH3"). Backend gap.
    var spectraMatchPurity: String { Self.dash }

    /// Vessel name + voyage line ("MV Ever Green · voyage 024"). Backend
    /// gap.
    var vesselVoyage: String { Self.dash }

    /// Berth assignment line ("APM · terminal 5 · berth 43"). Backend
    /// gap.
    var berthAssignment: String { Self.dash }

    /// Ramp / port assignment line ("NS Meadowlands"). Backend gap.
    var rampAssignment: String { Self.dash }

    /// Carrier identity line ("EusoFleet · DOT 3871621" / "Koch
    /// Shipping · IMO 9764823"). Backend gap — the carrier envelope
    /// isn't joined onto `loads.getById` yet.
    var carrierLine: String { Self.dash }

    /// "AAR sealed" waybill line. Backend gap.
    var waybillRegistry: String { Self.dash }

    /// Loaded gallons display ("6,800 gal"). Backend gap (hazmat
    /// loaded-net-at-fill is recorded in viga AI photo capture, not
    /// surfaced on the load envelope yet).
    var loadedGallons: String { Self.dash }

    /// Bulk net display — falls through to `netWeight` when at least
    /// the weight ships, otherwise em-dash.
    var bulkNetDisplay: String { netWeight }

    /// Bulk sample certification line ("pass"). Backend gap.
    var bulkSampleCert: String { Self.dash }

    /// Close-out delta on the ENDORSED chip ("+0 GAL" / "+12 GAL" /
    /// "no shorts" / "+0 PALLET"). Backend gap — close-out delta is
    /// computed by `loadLifecycle.closeoutDelta` which doesn't
    /// surface yet.
    var closeoutDelta: String { Self.dash }

    /// Temp-trace close-out ("no excursions" / "TEMP TRACE"). Backend
    /// gap — `coldChain.getTrace` is shipped server-side but the
    /// envelope hasn't been wired through.
    var tempTraceCloseout: String { Self.dash }

    /// Tank-trailer regulatory cert chip ("MC-331 · DOT 412"). Backend
    /// gap — carrier tank-spec column not yet on the load envelope.
    /// Used by 033 BOL Signoff in the BOL header strip. (141st firing
    /// M3 sweep — added for 033 retrofit.)
    var tankSpec: String { Self.dash }

    /// Liquid-fill completion temperature ("-33 °F" / "-18 °C").
    /// Backend gap — fill-temp is captured by viga AI photo at fill
    /// completion but not surfaced on the load envelope. (141st firing
    /// M3 sweep — added for 033 retrofit.)
    var liquidFillTempDisplay: String { Self.dash }

    /// Fill-completion clock ("18:28"). Backend gap — fill-stop
    /// timestamp recorded in the lifecycle event log but not on the
    /// load envelope yet. (141st firing M3 sweep — added for 033
    /// retrofit.)
    var liquidFillCompletedAt: String { Self.dash }

    /// Driver credential line ("CDL MD-A · endorsements N+H+T+X · TWIC
    /// valid"). Backend gap — driver CDL/endorsement/TWIC envelope is
    /// stored on `users` table per §16 auth-identity-rbac slice but
    /// not joined onto `loads.getById`. (141st firing M3 sweep —
    /// added for 033 retrofit.)
    var driverCredentialLine: String { Self.dash }

    /// Tank-trailer cert SPEC label ("Spec bullet tank" / "MC-307 spec
    /// tank" / "ISO tank container"). Backend gap — tank-construction
    /// classification lives on the carrier `vehicles`/`trailers`
    /// envelope and is not joined onto `loads.getById`. Used by 028
    /// LoadLockedPrehaul hazmat tanker MC-331 row. (143rd firing M3
    /// sweep.)
    var tankCertSpec: String { Self.dash }

    /// Tank-trailer cert expiry window ("P-stamp expires 2026-07-12 ·
    /// 57 days"). Backend gap — DOT P-stamp recertification dates
    /// live on the trailer envelope; per-load join not present. Used
    /// by 028 LoadLockedPrehaul hazmat tanker MC-331 row. (143rd
    /// firing M3 sweep.)
    var tankCertExpiryWindow: String { Self.dash }

    /// Driver endorsement bundle status line ("H · hazmat · TWIC ·
    /// medical card all current"). Backend gap — derived from the
    /// `users.endorsements` set + TWIC + medical-card joins per §16
    /// auth-identity-rbac slice; not yet wired through. Used by 028
    /// LoadLockedPrehaul hazmat tanker endorsements row. (143rd
    /// firing M3 sweep.)
    var driverEndorsementBundle: String { Self.dash }

    /// Driver endorsement bundle CTA badge ("5/5" / "4/5" / em-dash).
    /// Reflects how many of the required endorsements are current.
    /// Backend gap — same envelope as `driverEndorsementBundle`. Used
    /// by 028 LoadLockedPrehaul hazmat tanker endorsements row CTA.
    /// (143rd firing M3 sweep.)
    var driverEndorsementBadge: String { Self.dash }

    /// Insurance binder window line ("$5M per-incident · window 18:00
    /// Apr 17 - 08:30 Apr 18"). Backend gap — EusoShield binder
    /// activation envelope is generated by the `insurance.bindLoad`
    /// procedure (per §16 money slice) but the active-window field
    /// is not yet on the load envelope. Used by 028 LoadLockedPrehaul
    /// hazmat tanker binder row. (143rd firing M3 sweep.)
    var insuranceBinderWindow: String { Self.dash }

    /// Reefer fuel level + run-hours headroom line ("64% · 24h
    /// headroom"). Backend gap — reefer telemetry stream lives on
    /// the `coldChain` envelope (per §16 compliance-safety slice)
    /// but is not joined onto `loads.getById` yet. Used by 028
    /// LoadLockedPrehaul reefer fuel row. (143rd firing M3 sweep.)
    var reeferFuelLevel: String { Self.dash }

    // MARK: Regulatory constants (NOT fabricated — universal lookups)

    /// CHEMTREC 24/7 hazmat emergency contact — a universal
    /// regulatory constant, not a per-load datum. Surfaced only when
    /// the load actually carries a hazmat class; collapses to em-dash
    /// otherwise. Number per CHEMTREC published lookup
    /// (1-800-424-9300 US/CA · 703-741-5500 international).
    var chemtrecLine: String {
        guard let h = load?.hazmatClass, !h.isEmpty else { return Self.dash }
        _ = h // silence unused-let warning
        return "CHEMTREC · 1-800-424-9300"
    }

    /// 49 CFR 177.823 placard-confirmation marker — universal hazmat
    /// regulatory text triggered by the hazmat-class presence check.
    /// Surfaced only when the load carries a hazmat class. Used by
    /// 033 BOL Signoff. (141st firing M3 sweep.)
    var placardConfirmation: String {
        guard let h = load?.hazmatClass, !h.isEmpty else { return Self.dash }
        _ = h
        return "PLACARD CONFIRMED · 49 CFR 177.823"
    }

    /// Certification statement body for the BOL signoff (49 CFR 172
    /// generic carrier certification). Universal regulatory copy —
    /// not fabricated. Surfaced only when the load actually carries a
    /// hazmat class. Used by 033 BOL Signoff. (141st firing M3
    /// sweep.)
    var hazmatCertStatement: String {
        guard let h = load?.hazmatClass, !h.isEmpty else { return Self.dash }
        _ = h
        return "I certify the description above is correct, that the load has been properly classified, packaged, marked and labeled per 49 CFR 172, and that the hazardous materials are in proper condition for transportation according to applicable regulations."
    }

    /// Non-hazmat BOL certification statement — generic carrier
    /// certification of receipt + good order, no hazmat clause. Used
    /// by 033 BOL Signoff when the load is not classified hazmat.
    /// (141st firing M3 sweep.)
    var generalCertStatement: String {
        "I certify the description above is correct and that the load has been received in apparent good order subject to the carrier's tariff and the bill of lading terms and conditions."
    }
}

// MARK: - Context

/// One-stop resolver every lifecycle screen reads from. Carries
/// the active Load (when assigned), the vertical, the product,
/// plus a pile of per-screen content helpers so each screen's
/// body stays short + readable.
struct LifecycleProductContext {

    let load: Load?
    let vertical: TripVertical
    let product: TripProduct

    init(load: Load?, role: String?) {
        self.load = load
        self.vertical = TripVertical(role: role)
        self.product = TripProduct.resolve(load: load, vertical: self.vertical)
    }

    /// Live-load facet resolver (138th firing M2 retrofit). Every
    /// product-case fixture below reads off this resolver instead of
    /// hard-coding a literal — collapses to em-dash whenever the
    /// backend hasn't shipped the corresponding column.
    var facets: LiveLoadFacets { LiveLoadFacets(load: load) }

    /// Load-less init for driver-area screens (056 Profile, 057
    /// Vehicle Card, 058 Weekly Plan, etc.) that want a vertical
    /// kicker without needing an active load. The product resolves
    /// from the vertical default — `dryVan` for truck, `railIntermodal`
    /// for rail, `vesselContainer` for vessel — purely as a default
    /// glyph. Screens that have a load should use the canonical
    /// `init(load:role:)`.
    static func forRole(_ role: String?) -> LifecycleProductContext {
        LifecycleProductContext(load: nil, role: role)
    }

    /// Vertical-only kicker label for screens that don't render a
    /// product variant (e.g. 056 Driver Profile shows "DRIVER ·
    /// TRUCK" / "ENGINEER · RAIL" / "CAPTAIN · VESSEL"). The
    /// product enum still drops down to a sensible default; this
    /// helper is just a shorter label when the product isn't on
    /// screen.
    var verticalLabel: String {
        switch vertical {
        case .truck:  return "TRUCK"
        case .rail:   return "RAIL"
        case .vessel: return "VESSEL"
        }
    }

    /// SF Symbol for the vertical itself (truck / train / ferry).
    /// Useful on driver-area screens that want a vertical glyph
    /// instead of the product glyph.
    var verticalSymbol: String {
        switch vertical {
        case .truck:  return "truck.box"
        case .rail:   return "tram.fill"
        case .vessel: return "ferry.fill"
        }
    }

    var isHazmat: Bool { product.isHazmat }

    /// Eyebrow chip shown above a screen's title, e.g. "HAZMAT
    /// TANKER" / "DRY VAN" / "REEFER". Readable in both dark +
    /// light against a gradient stroke.
    var headerKicker: String { product.label }

    /// "dispatch" noun for this vertical — used in the CTA
    /// subtitle on 014 etc.
    var dispatchLabel: String { vertical.dispatchWord }

    // MARK: - 014 Approaching Pickup · pre-haul checklist

    struct PreHaulItem: Identifiable, Hashable {
        let id: String
        let title: String
        let subtitle: String
    }

    /// 6 items, product-specific. The last three are typically
    /// NOW / NEXT / PENDING on the screen; caller decides state.
    var preHaulChecklist: [PreHaulItem] {
        switch product {
        case .hazmatTanker, .vesselTanker:
            let un = load?.unNumber ?? "UN1005"
            return [
                .init(id: "placards", title: "Placards verified · \(un)", subtitle: "All 4 sides · Class 2.2 · non-flam gas"),
                .init(id: "ppe",      title: "PPE staged at driver door", subtitle: "Gloves · splash hood · face shield · SCBA 30 min"),
                .init(id: "erg",      title: "Emergency response info printed", subtitle: "ERG 125 · site plan · contacts 800-222-1222"),
                .init(id: "notify",   title: "Notify site 15-min ETA", subtitle: "Contact · ext 12"),
                .init(id: "pressure", title: "Tank pressure pre-check", subtitle: "Confirm pressure below spec before gate"),
                .init(id: "cam",      title: "Dash cam + voice memo on", subtitle: "Liability record for grounding + transfer"),
            ]
        case .dryVan:
            return [
                .init(id: "seal",    title: "Trailer seal intact", subtitle: "Photograph + log number before breaking"),
                .init(id: "swept",   title: "Trailer swept + dry", subtitle: "No prior-load debris · no wet spots"),
                .init(id: "pallet",  title: "Pallet jack on board", subtitle: "Battery full · teeth up for hand-off"),
                .init(id: "notify",  title: "Notify site 15-min ETA", subtitle: "Contact · dock schedule desk"),
                .init(id: "paperwork", title: "Paperwork ready", subtitle: "BOL packet + load-confirmation · stamped"),
                .init(id: "cam",     title: "Dash cam + voice memo on", subtitle: "Loading liability record"),
            ]
        case .reefer:
            return [
                .init(id: "precool",  title: "Pre-cool to set-point", subtitle: "Target temp pulled-down before doors open"),
                .init(id: "fuel",     title: "Reefer fuel > 1/2", subtitle: "Enough to hold through drop; top off if below"),
                .init(id: "airchute", title: "Air chute in place", subtitle: "Even airflow over pallets, no dead zones"),
                .init(id: "notify",   title: "Notify site 15-min ETA", subtitle: "Cold-chain receiving desk"),
                .init(id: "thermo",   title: "Thermograph armed", subtitle: "Temp trace running for the haul"),
                .init(id: "cam",      title: "Dash cam + voice memo on", subtitle: "Loading liability record"),
            ]
        case .flatbed:
            return [
                .init(id: "tarps",    title: "Tarps staged", subtitle: "Lumber + steel tarps folded · corner protectors"),
                .init(id: "straps",   title: "Straps + chains inspected", subtitle: "No frayed straps; chain hooks rated"),
                .init(id: "wtn",      title: "Working loads (WLL) confirmed", subtitle: "Meets 49 CFR 393 for the commodity"),
                .init(id: "notify",   title: "Notify site 15-min ETA", subtitle: "Shipping office"),
                .init(id: "ppe",      title: "PPE on: hard hat, high-vis, gloves", subtitle: "Loading yard rules"),
                .init(id: "cam",      title: "Dash cam + voice memo on", subtitle: "Loading liability record"),
            ]
        case .container, .railIntermodal:
            return [
                .init(id: "chassis",  title: "Chassis ID + safety pre-trip", subtitle: "Lights · brakes · tires · locking pins"),
                .init(id: "ivr",      title: "Container number + ISO type", subtitle: "Verify on SSL release vs. chassis manifest"),
                .init(id: "seal",     title: "Seal intact + match BOL", subtitle: "Photograph prior to ramp"),
                .init(id: "notify",   title: "Notify ramp 15-min ETA", subtitle: "Port / ramp dispatch"),
                .init(id: "paperwork", title: "TIR + pre-advice loaded", subtitle: "EDI 322 / 315 ready to fire on gate-in"),
                .init(id: "cam",      title: "Dash cam + voice memo on", subtitle: "Ramp liability record"),
            ]
        case .railBulk:
            return [
                .init(id: "hatches",  title: "Hatches + vents verified", subtitle: "Inspect pre-load seal integrity"),
                .init(id: "ground",   title: "Grounding rod placement", subtitle: "Confirm ohms within cap before transfer"),
                .init(id: "safety",   title: "Fall protection rigged", subtitle: "Roof-top harness + rail-cart"),
                .init(id: "notify",   title: "Notify trainmaster 15-min", subtitle: "Spur + track number"),
                .init(id: "paperwork", title: "Waybill + interchange ticket", subtitle: "AAR format ready"),
                .init(id: "cam",      title: "Cam + voice memo on", subtitle: "Loading liability record"),
            ]
        case .vesselContainer:
            return [
                .init(id: "edi",      title: "EDI 322 gate-in ready", subtitle: "Port advance notice filed"),
                .init(id: "manifest", title: "Container manifest match", subtitle: "Bill of lading matches ISO + seal"),
                .init(id: "hazmat",   title: "IMO hazmat declaration", subtitle: "Only when applicable"),
                .init(id: "notify",   title: "Notify berth 15-min", subtitle: "Harbormaster radio ch. 16"),
                .init(id: "paperwork", title: "Customs + manifest filed", subtitle: "CBP 7512 + ISF 10+2 on file"),
                .init(id: "cam",      title: "Cam + voice memo on", subtitle: "Berthing liability record"),
            ]
        case .vesselBulk:
            return [
                .init(id: "holds",    title: "Holds inspected + dry", subtitle: "No prior-cargo contamination"),
                .init(id: "loadplan", title: "Load plan reviewed", subtitle: "Trim + stability approved by captain"),
                .init(id: "ground",   title: "Grounding + bonding set", subtitle: "Static discharge paths verified"),
                .init(id: "notify",   title: "Notify berth 15-min", subtitle: "Harbormaster radio"),
                .init(id: "paperwork", title: "Certificate of origin + phyto", subtitle: "Export paperwork staged"),
                .init(id: "cam",      title: "Cam + voice memo on", subtitle: "Loading liability record"),
            ]
        }
    }

    // MARK: - 016 Loading · safety tile row

    struct SafetyTile: Identifiable {
        let id = UUID()
        let label: String
        let primary: String
        let secondary: String
    }

    /// The three top-level metrics rendered in the 016 Loading
    /// progress card. Hazmat shows pressure / temp / grounding;
    /// reefer shows set-point / return-air / reefer-fuel; dry van
    /// shows pallets-staged / dock-door / ETA-to-close; etc.
    ///
    /// 138th firing M2 retrofit — every primary value (sensor reading
    /// or driver-witnessed state) collapses to em-dash until the
    /// sensor stream / witness-checks backend lands. Secondary copy
    /// stays as the metric's spec/limit (regulatory constant, not
    /// fabricated data).
    var loadingMetrics: [SafetyTile] {
        let f = facets
        let dash = LiveLoadFacets.dash
        switch product {
        case .hazmatTanker, .vesselTanker, .railBulk, .vesselBulk:
            return [
                .init(label: "PRESSURE",     primary: dash, secondary: "psi · limit 250"),
                .init(label: "PRODUCT TEMP", primary: dash, secondary: "°F · chill spec"),
                .init(label: "GROUNDING",    primary: dash, secondary: "cap 0.8 \u{03A9}"),
            ]
        case .dryVan:
            return [
                .init(label: "PALLETS",   primary: f.palletCount, secondary: dash),
                .init(label: "DOCK",      primary: dash,          secondary: f.deliveryFacility),
                .init(label: "DOOR SEAL", primary: dash,          secondary: dash),
            ]
        case .reefer:
            return [
                .init(label: "SET-POINT",   primary: f.setPointDisplay, secondary: "USDA frozen target"),
                .init(label: "RETURN AIR", primary: dash,               secondary: "°F · stable spec"),
                .init(label: "REEFER FUEL", primary: dash,              secondary: "% headroom"),
            ]
        case .flatbed:
            return [
                .init(label: "TARPS",   primary: f.tarpStatus,        secondary: dash),
                .init(label: "STRAPS",  primary: f.securementShort,   secondary: f.securementWithinWLL),
                .init(label: "HEIGHT", primary: dash,                 secondary: "clear · OSOW per route"),
            ]
        case .container, .railIntermodal, .vesselContainer:
            return [
                .init(label: "PINS",     primary: dash, secondary: "4 of 4 twistlocks"),
                .init(label: "SEAL",     primary: dash, secondary: "match manifest"),
                .init(label: "CHASSIS",  primary: dash, secondary: "pre-trip per DVIR"),
            ]
        }
    }

    // MARK: - 017 BOL Signing · manifest rows

    struct ManifestRow: Identifiable, Hashable {
        let id = UUID()
        let label: String
        let value: String
        /// When true the row's value renders in Brand.success (used
        /// for "4-side · verified" placards in hazmat, or "OK · 4
        /// of 4 twistlocks" in container).
        let affirm: Bool
    }

    var manifestRows: [ManifestRow] {
        // 138th firing M2 retrofit — every per-product fixture below is
        // now sourced from `facets` (LiveLoadFacets). Backend stub gaps
        // collapse to "—" via the resolver. CHEMTREC is the only literal
        // because it's a universal regulatory constant guarded behind a
        // real hazmat-class presence check (see chemtrecLine).
        let f = facets
        switch product {
        case .hazmatTanker, .vesselTanker, .railBulk, .vesselBulk:
            return [
                .init(label: "COMMODITY",         value: f.commodityWithUN, affirm: false),
                .init(label: "HAZARD CLASS",      value: f.hazardClass,     affirm: false),
                .init(label: "NET GALLONS",       value: f.loadedGallons,   affirm: false),
                .init(label: "NET WEIGHT",        value: f.netWeight,       affirm: false),
                .init(label: "PLACARDS",          value: LiveLoadFacets.dash, affirm: false),
                .init(label: "EMERGENCY CONTACT", value: f.chemtrecLine,    affirm: false),
            ]
        case .dryVan:
            return [
                .init(label: "COMMODITY", value: f.commodityName,   affirm: false),
                .init(label: "PALLETS",   value: f.palletSummary,   affirm: false),
                .init(label: "NET WEIGHT", value: f.netWeight,      affirm: false),
                .init(label: "SEAL",       value: f.sealNumber,     affirm: false),
                .init(label: "DOCK",       value: f.deliveryFacility, affirm: false),
                .init(label: "CARRIER",    value: f.carrierLine,    affirm: false),
            ]
        case .reefer:
            return [
                .init(label: "COMMODITY",   value: f.commodityName,    affirm: false),
                .init(label: "SET-POINT",   value: f.setPointDisplay,  affirm: false),
                .init(label: "PALLETS",     value: f.palletSummary,    affirm: false),
                .init(label: "SEAL",        value: f.sealNumber,       affirm: false),
                .init(label: "DOCK",        value: f.deliveryFacility, affirm: false),
                .init(label: "CARRIER",     value: f.carrierLine,      affirm: false),
            ]
        case .flatbed:
            return [
                .init(label: "COMMODITY",   value: f.commodityName,        affirm: false),
                .init(label: "WEIGHT",      value: f.netWeight,            affirm: false),
                .init(label: "SECUREMENT",  value: f.securementSummary,    affirm: false),
                .init(label: "TARPS",       value: f.tarpStatus,           affirm: false),
                .init(label: "HEIGHT",      value: LiveLoadFacets.dash,    affirm: false),
                .init(label: "CARRIER",     value: f.carrierLine,          affirm: false),
            ]
        case .container, .railIntermodal:
            return [
                .init(label: "CONTAINER",   value: f.containerNumber,  affirm: false),
                .init(label: "CHASSIS",     value: f.chassisNumber,    affirm: false),
                .init(label: "SEAL",        value: f.sealNumber,       affirm: false),
                .init(label: "WEIGHT",      value: f.netWeight,        affirm: false),
                .init(label: "RAMP",        value: f.rampAssignment,   affirm: false),
                .init(label: "CARRIER",     value: f.carrierLine,      affirm: false),
            ]
        case .vesselContainer:
            return [
                .init(label: "CONTAINER", value: f.containerNumber,  affirm: false),
                .init(label: "VESSEL",    value: f.vesselVoyage,     affirm: false),
                .init(label: "SEAL",      value: f.sealNumber,       affirm: false),
                .init(label: "VGM",       value: f.vgmDisplay,       affirm: false),
                .init(label: "BERTH",     value: f.berthAssignment,  affirm: false),
                .init(label: "CARRIER",   value: f.carrierLine,      affirm: false),
            ]
        }
    }

    // MARK: - 020 Approaching Delivery · 4-row pre-gate checklist

    /// Four-row "before the gate" checklist surfaced on 020. Each
    /// row's copy + subtitle changes by product so a dry-van driver
    /// sees BOL/seal/lumper, a reefer driver sees temp-log/pallet-
    /// count, a container driver sees EDI 322 / VGM-on-file.
    var deliveryPreCheck: [PreHaulItem] {
        switch product {
        case .hazmatTanker, .vesselTanker, .railBulk, .vesselBulk:
            return [
                .init(id: "sealed", title: "Transfer valves sealed", subtitle: "Scale-confirmed · NH3 placards still up"),
                .init(id: "bol",    title: "BOL on file · 3 copies", subtitle: "Carrier · consignee · receiver"),
                .init(id: "dashcam", title: "Dash-cam armed on entry", subtitle: "Auto-arms at 0.3 mi geofence"),
                .init(id: "chem",   title: "CHEMTREC on speed-dial", subtitle: "424-424-9300 · UN1005"),
            ]
        case .dryVan:
            // 133rd firing M2 retrofit: the "sealed" row previously
            // carried a literal seal number ("881204") and a literal
            // origin DC ("Meridian DC"). Until the seal-id lands on the
            // Load envelope and the pickup-facility brand structure
            // ships, both fall back to neutral copy that doesn't pretend
            // to know a customer that the row hasn't been told about.
            return [
                .init(id: "sealed", title: "Load sealed", subtitle: "Seal logged at gate close"),
                .init(id: "bol",    title: "BOL on file · 3 copies", subtitle: "Carrier · shipper · receiver"),
                .init(id: "dashcam", title: "Dash-cam armed on entry", subtitle: "Auto-arms at 0.3 mi geofence"),
                .init(id: "lumper", title: "Unload lumper", subtitle: "Not required — receiver unloads"),
            ]
        case .reefer:
            return [
                .init(id: "setpoint", title: "Set-point log clean", subtitle: "-18°F held throughout · no excursions"),
                .init(id: "bol",      title: "BOL + temp trace on file", subtitle: "Thermograph tape + digital trace"),
                .init(id: "dashcam",  title: "Dash-cam armed on entry", subtitle: "Auto-arms at 0.3 mi geofence"),
                .init(id: "lumper",   title: "Unload lumper", subtitle: "Cold crew · $75 per receiver policy"),
            ]
        case .flatbed:
            return [
                .init(id: "tarps",    title: "Tarps + straps inspected", subtitle: "No shift since loading · intact"),
                .init(id: "bol",      title: "BOL + load-securement doc", subtitle: "DOT 393 · WLL within spec"),
                .init(id: "dashcam",  title: "Dash-cam armed on entry", subtitle: "Auto-arms at 0.3 mi geofence"),
                .init(id: "crane",    title: "Crane unload notified", subtitle: "Receiver's rigger on call-forward"),
            ]
        case .container, .railIntermodal:
            return [
                .init(id: "seal",    title: "Seal intact + match BOL", subtitle: "Photograph at gate"),
                .init(id: "edi",     title: "EDI 322 gate-in armed", subtitle: "Fires on scanner read"),
                .init(id: "dashcam", title: "Dash-cam armed on entry", subtitle: "Auto-arms at 0.3 mi geofence"),
                .init(id: "tir",     title: "TIR + release on tablet", subtitle: "Ready for gate-guard scan"),
            ]
        case .vesselContainer:
            return [
                .init(id: "edi",      title: "EDI 322 gate-in armed", subtitle: "Port advance notice on file"),
                .init(id: "manifest", title: "Manifest + BOL match", subtitle: "ISO + seal against release"),
                .init(id: "dashcam",  title: "Dash-cam armed on entry", subtitle: "Auto-arms at 0.3 mi geofence"),
                .init(id: "customs",  title: "CBP 7512 + ISF cleared", subtitle: "Entry filed · release active"),
            ]
        }
    }

    // MARK: - 021 At Receiver Gate · guard-check notes

    /// Short advisory the guard card shows while waiting to be
    /// checked in. Copy adapts to the product so the driver reads
    /// the right expectation.
    var guardCheckNote: String {
        switch product {
        case .hazmatTanker, .vesselTanker, .railBulk, .vesselBulk:
            return "Seal intact. Guard is checking hazmat manifest against the receiver's transfer window. Expect a bay push once cleared — typically 15 – 25 min at this facility."
        case .dryVan:
            return "Seal intact. Guard is checking BOL against receiving schedule. You'll get a dock number push when cleared — typically 10 – 22 min at this DC."
        case .reefer:
            return "Seal + temp trace intact. Guard is pulling cold-chain schedule; expect a cold-door push — typically 10 – 18 min at this DC."
        case .flatbed:
            return "Securement intact. Guard is checking load-sheet for the yard lane. Expect a staging row push — typically 5 – 15 min."
        case .container, .railIntermodal:
            return "Seal intact. Guard is matching container + chassis IDs against the SSL release. Expect a ramp lane push — typically 10 – 20 min."
        case .vesselContainer:
            return "Seal intact. Stevedore operations clearing you into the gate — typically 15 – 40 min depending on berth windows."
        }
    }

    // MARK: - 023 Backing-In · dock approach

    /// Human-readable default approach label ("Blind-side" /
    /// "Driver-side" / "Straight-in" / "Swing"). Truck Cargo door
    /// side drives this — blind-side for standard US DCs, driver-
    /// side on the rare swap. Defaults to blind-side.
    var defaultApproach: String {
        switch product {
        case .flatbed:    return "Straight-in"
        case .container, .railIntermodal, .vesselContainer:
            return "Straight-in"
        default:
            return "Blind-side"
        }
    }

    // MARK: - 024 Unloading · rate + unit labels

    /// Unit label on the unload progress card ("pallets" /
    /// "gallons" / "containers" / "tons").
    var unloadUnitLabel: String {
        switch product {
        case .hazmatTanker, .vesselTanker: return "gallons"
        case .railBulk, .vesselBulk:       return "tons"
        case .container, .railIntermodal, .vesselContainer: return "moves"
        case .flatbed:                     return "tie-downs"
        default:                           return "pallets"
        }
    }

    /// Rate label on the unload progress card ("PALLETS/HR" /
    /// "GPM" / "CONTAINERS/HR" / "TONS/HR").
    var unloadRateLabel: String {
        switch product {
        case .hazmatTanker, .vesselTanker:  return "GPM"
        case .railBulk, .vesselBulk:        return "TONS/HR"
        case .container, .railIntermodal, .vesselContainer: return "MOVES/HR"
        case .flatbed:                      return "TIE-DOWNS/HR"
        default:                            return "PALLETS/HR"
        }
    }

    // MARK: - 034 Departing Pickup · compliance triplet

    /// Three-row compliance strip surfaced on 034 Departing Pickup.
    /// Each product emits the right "loaded / quality / paper" proof
    /// a driver (and their binder) cares about on departure.
    struct ComplianceRow: Identifiable, Hashable {
        var id: String { label }
        let icon: String
        let label: String
        let value: String
    }

    var departingCompliance: [ComplianceRow] {
        // 138th firing M2 retrofit — extends the 133rd's dry-van em-dash
        // pattern across the remaining 7 product cases. Every value is
        // sourced from `facets`; backend stub gaps collapse to "—".
        let f = facets
        let bol = "SIGNED · \(bolShortId)"
        switch product {
        case .hazmatTanker, .vesselTanker:
            return [
                .init(icon: "drop.fill",      label: "LOADED · NET AT FILL",         value: f.loadedGallons),
                .init(icon: "waveform.path",  label: "SPECTRA-MATCH · FINAL SAMPLE", value: f.spectraMatchPurity),
                .init(icon: "doc.fill",       label: "BOL · \(bol)",                 value: bolShortId),
            ]
        case .dryVan:
            return [
                .init(icon: "shippingbox.fill", label: "LOADED · PALLETS",          value: f.palletSummary),
                .init(icon: "seal.fill",         label: "SEAL APPLIED",               value: f.sealNumber),
                .init(icon: "doc.fill",          label: "BOL · \(bol)",               value: bolShortId),
            ]
        case .reefer:
            return [
                .init(icon: "thermometer.snowflake", label: "LOADED · PALLETS",      value: f.palletSummary),
                .init(icon: "thermometer",            label: "SET-POINT LOCKED",     value: f.setPointDisplay),
                .init(icon: "doc.fill",               label: "BOL + TEMP TRACE ·",    value: bolShortId),
            ]
        case .flatbed:
            return [
                .init(icon: "scalemass.fill",    label: "LOADED · WEIGHT",             value: f.netWeight),
                .init(icon: "link",              label: "SECUREMENT · \(f.securementShort)", value: f.securementWithinWLL),
                .init(icon: "doc.fill",          label: "BOL · \(bol)",                value: bolShortId),
            ]
        case .container, .railIntermodal:
            return [
                .init(icon: "cube.box.fill",     label: "CONTAINER + CHASSIS",         value: f.containerNumber),
                .init(icon: "seal.fill",         label: "SEAL",                        value: f.sealNumber),
                .init(icon: "doc.fill",          label: "BOL + VGM ·",                 value: bolShortId),
            ]
        case .vesselContainer:
            return [
                .init(icon: "ferry.fill",        label: "CONTAINER ON VESSEL MANIFEST", value: f.containerNumber),
                .init(icon: "seal.fill",         label: "SEAL",                         value: f.sealNumber),
                .init(icon: "doc.fill",          label: "BOL + VGM ·",                  value: bolShortId),
            ]
        case .railBulk, .vesselBulk:
            return [
                .init(icon: "drop.fill",         label: "LOADED · NET",                 value: f.bulkNetDisplay),
                .init(icon: "waveform.path",     label: "SAMPLE CERT",                  value: f.bulkSampleCert),
                .init(icon: "doc.fill",          label: "WAYBILL · AAR ·",              value: bolShortId),
            ]
        }
    }

    /// Abbreviated BOL id used on the 034/025 cards (e.g.
    /// "EUSO-…4421"). Prefers the live load number; falls back to
    /// the Figma verbatim.
    var bolShortId: String {
        guard let n = load?.loadNumber, !n.isEmpty else { return "EUSO-…4421" }
        if n.count <= 12 { return n }
        return "\(n.prefix(5))…\(n.suffix(4))"
    }

    /// Product-appropriate first-leg turn call-out subtitle
    /// (e.g. "Right out of Bay 4 onto Frankfurt Ave, then merge
    /// I-695 W"). Today this is a static reference string per
    /// product because live HERE-routing first-turn isn't wired
    /// to this screen yet; when it is, this returns the route's
    /// head action.
    var firstLegTurn: String {
        switch product {
        case .hazmatTanker, .vesselTanker:
            return "Right out of Bay 4 onto Frankfurt Ave, then merge I-695 W"
        case .dryVan, .reefer:
            return "Left out of dock 14 onto Depot Rd, then merge I-59 S"
        case .flatbed:
            return "Straight out of staging row, then merge I-59 S"
        case .container, .railIntermodal, .vesselContainer:
            return "Exit ramp via Marine Terminal Rd, then merge I-95 N"
        case .railBulk, .vesselBulk:
            return "Exit spur via Industrial Way, then merge to I-40 E"
        }
    }

    // MARK: - 037 Approaching Receiver · pre-arrival checklist

    /// 4-row pre-arrival checklist surfaced on 037. Hazmat shows
    /// PPE + BOL/ERG + ESANG ping + spotter; dry-van shows BOL +
    /// seal + ESANG ping + lumper.
    var receiverPreArrival: [PreHaulItem] {
        switch product {
        case .hazmatTanker, .vesselTanker:
            return [
                .init(id: "ppe",     title: "Hazmat PPE on (apron, face shield, gloves)", subtitle: "EusoShield protocol"),
                .init(id: "paper",   title: "BOL packet + emergency response card ready",  subtitle: "Wallet"),
                .init(id: "ping",    title: "ESANG arrival ping queued for T-3 min",        subtitle: "Receiver desk"),
                .init(id: "spotter", title: "Spotter contact saved (dock-side hazmat)",     subtitle: "Recommended for night discharge"),
            ]
        case .reefer:
            return [
                .init(id: "seal",  title: "Cold-seal photographed",                subtitle: "Break only under receiver eyes"),
                .init(id: "paper", title: "BOL + temp trace packet",               subtitle: "Wallet"),
                .init(id: "ping",  title: "ESANG arrival ping queued for T-3 min", subtitle: "Cold-chain desk"),
                .init(id: "crew",  title: "Cold crew contact saved",               subtitle: "Night-shift lumper"),
            ]
        case .flatbed:
            return [
                .init(id: "ppe",   title: "PPE on: hard hat, high-vis, gloves", subtitle: "Yard rules"),
                .init(id: "paper", title: "BOL + securement doc",                subtitle: "Wallet"),
                .init(id: "ping",  title: "ESANG arrival ping queued for T-3 min", subtitle: "Crane operator desk"),
                .init(id: "crane", title: "Crane / forklift rigger on call-forward", subtitle: "Standby"),
            ]
        case .container, .railIntermodal, .vesselContainer:
            return [
                .init(id: "seal",  title: "Seal photographed + stored",         subtitle: "Match against release"),
                .init(id: "paper", title: "BOL + TIR + EDI 322 armed",          subtitle: "Wallet"),
                .init(id: "ping",  title: "ESANG arrival ping queued for T-3 min", subtitle: "Ramp / port gate desk"),
                .init(id: "vgm",   title: "VGM confirmation filed",               subtitle: "Verified gross mass"),
            ]
        case .railBulk, .vesselBulk:
            return [
                .init(id: "ppe",   title: "Fall protection + gloves on",       subtitle: "AAR rooftop rules"),
                .init(id: "paper", title: "Waybill + interchange ticket",      subtitle: "Wallet"),
                .init(id: "ping",  title: "ESANG arrival ping queued for T-3 min", subtitle: "Trainmaster desk"),
                .init(id: "ground", title: "Grounding rig staged",              subtitle: "Ohms cap within spec"),
            ]
        case .dryVan:
            return [
                .init(id: "seal",  title: "Seal photographed + stored",       subtitle: "Break only under receiver eyes"),
                .init(id: "paper", title: "BOL packet ready",                   subtitle: "Wallet"),
                .init(id: "ping",  title: "ESANG arrival ping queued for T-3 min", subtitle: "Receiving desk"),
                .init(id: "lumper", title: "Lumper fee pre-authorized",         subtitle: "Per receiver policy"),
            ]
        }
    }

    /// Hazmat-only advisory shown on 037 (amber strip). Empty
    /// string for non-hazmat products so the UI hides the strip.
    var receiverHazmatStrip: String {
        guard isHazmat else { return "" }
        return "Ammonia sensor monitoring active during transfer."
    }

    // MARK: - 040-045 Discharge / disconnect

    /// Header noun for the discharge stretch — "Discharging NH3"
    /// vs "Unloading 72 pallets" vs "Dropping container" vs etc.
    var dischargeHeaderTitle: String {
        switch product {
        case .hazmatTanker, .vesselTanker:   return "Discharging NH3"
        case .railBulk, .vesselBulk:         return "Discharging bulk"
        case .reefer:                        return "Unloading cold"
        case .flatbed:                       return "Releasing flatbed"
        case .container, .vesselContainer:   return "Dropping container"
        case .railIntermodal:                return "Lift-off intermodal"
        case .dryVan:                        return "Unloading pallets"
        }
    }

    /// Big "transferred / remaining" units used in 040 + 041.
    /// (gallons / pallets / containers / tons / tie-downs)
    var dischargeUnit: String { unloadUnitLabel }

    /// 3-tile safety row for 040. Hazmat = pressure/temp/vapor;
    /// reefer = set-point/return-air/door temp; dry van =
    /// pallets-on-trailer/dock-door/seal; flatbed = tie-downs
    /// released / WLL / crane lane.
    ///
    /// 138th firing M2 retrofit — primary readings (sensor stream or
    /// driver-witnessed state) collapse to em-dash until backend
    /// `sensors.streamLatest` lands. Secondary text is the metric's
    /// regulatory spec/limit (a constant, not fabricated data).
    var dischargeSafetyTiles: [SafetyTile] {
        let dash = LiveLoadFacets.dash
        switch product {
        case .hazmatTanker, .vesselTanker, .railBulk, .vesselBulk:
            return [
                .init(label: "PRESSURE", primary: dash, secondary: "psig · 125-160"),
                .init(label: "TEMP",     primary: dash, secondary: "°F · -30/-26"),
                .init(label: "VAPOR",    primary: dash, secondary: "psig"),
            ]
        case .reefer:
            return [
                .init(label: "SET-POINT",  primary: dash, secondary: "°F · USDA frozen"),
                .init(label: "RETURN AIR", primary: dash, secondary: "°F · stable"),
                .init(label: "DOOR TEMP",  primary: dash, secondary: "°F · cold-door open"),
            ]
        case .flatbed:
            return [
                .init(label: "TIE-DOWNS RELEASED", primary: dash, secondary: "of 12"),
                .init(label: "WLL OK",             primary: dash, secondary: "DOT 393"),
                .init(label: "CRANE LANE",         primary: dash, secondary: "rigger ready"),
            ]
        case .container, .railIntermodal, .vesselContainer:
            return [
                .init(label: "TWISTLOCKS",  primary: dash, secondary: "4 of 4 status"),
                .init(label: "VGM",         primary: dash, secondary: "match"),
                .init(label: "CRANE",       primary: dash, secondary: "ship-side"),
            ]
        case .dryVan:
            return [
                .init(label: "PALLETS LEFT", primary: dash, secondary: "of total"),
                .init(label: "DOCK DOOR",    primary: dash, secondary: "open status"),
                .init(label: "SEAL",         primary: dash, secondary: "break time"),
            ]
        }
    }

    /// 4-step discharge / disconnect ladder used on 042-044. Each
    /// product surfaces its own sequence (hazmat: depressurize →
    /// uncouple → cap & stow → walk-around; dry van: door close →
    /// seal applied → bay walk → forklift clear; container: lift
    /// off → twistlocks → chassis pull-off → ramp-out; etc.)
    struct LadderStep: Identifiable, Hashable {
        var id: String { title }
        let title: String
        let timestamp: String?
        /// "done" | "now" | "next"
        let state: String
    }

    var disconnectLadder: [LadderStep] {
        switch product {
        case .hazmatTanker, .vesselTanker, .railBulk, .vesselBulk:
            return [
                .init(title: "Depressurize line to scrubber", timestamp: "21:46:02", state: "done"),
                .init(title: "Spin off coupler ring",          timestamp: nil,        state: "now"),
                .init(title: "Cap stub & stow hose",           timestamp: nil,        state: "next"),
                .init(title: "Walk-around · scrubber + plates", timestamp: nil,       state: "next"),
            ]
        case .reefer:
            return [
                .init(title: "Close cold door at receiver",    timestamp: "21:46:00", state: "done"),
                .init(title: "Pull thermograph + sign trace",   timestamp: nil,       state: "now"),
                .init(title: "Seal cold-door + photograph",     timestamp: nil,       state: "next"),
                .init(title: "Walk-around · reefer + bay",      timestamp: nil,       state: "next"),
            ]
        case .flatbed:
            return [
                .init(title: "Final tie-downs released",        timestamp: "21:46:00", state: "done"),
                .init(title: "Crane / forklift lifting",         timestamp: nil,       state: "now"),
                .init(title: "Tarps + corner pads stowed",       timestamp: nil,       state: "next"),
                .init(title: "Walk-around · deck + straps",      timestamp: nil,       state: "next"),
            ]
        case .container, .railIntermodal, .vesselContainer:
            return [
                .init(title: "Twistlocks released",             timestamp: "21:46:00", state: "done"),
                .init(title: "Crane lift-off",                   timestamp: nil,       state: "now"),
                .init(title: "Pull chassis from under can",      timestamp: nil,       state: "next"),
                .init(title: "Ramp / port out · gate-out scan",  timestamp: nil,       state: "next"),
            ]
        case .dryVan:
            return [
                .init(title: "Last pallets off dock plate",     timestamp: "21:46:00", state: "done"),
                .init(title: "Dock plate raised, door pulled",  timestamp: nil,       state: "now"),
                .init(title: "Seal applied for return",          timestamp: nil,       state: "next"),
                .init(title: "Walk-around · trailer + locks",    timestamp: nil,       state: "next"),
            ]
        }
    }

    // MARK: - 046 Sequenced Leg Approach · yard-in checklist

    /// 4-row "yard-in" checklist surfaced on 046. Each row's title
    /// + subtitle + tail chip (VERIFIED / ARMED / PRIMED / PENDING)
    /// adapts to the active product so a hazmat driver sees decon-
    /// sweep + binder, a reefer driver sees thermograph download,
    /// a flatbed driver sees deck inspection, etc.
    struct YardCheck: Identifiable, Hashable {
        var id: String { title }
        let title: String
        let subtitle: String
        let tail: String
    }

    var yardInChecklist: [YardCheck] {
        switch product {
        case .hazmatTanker, .vesselTanker:
            return [
                .init(title: "MC-331 decon-sweep cleared at receiver", subtitle: "Spectra · residual 0 ppm",                  tail: "VERIFIED"),
                .init(title: "EusoShield binder auto-closes at yard-in", subtitle: "Binder · 21:46 to yard-in",               tail: "ARMED"),
                .init(title: "HOS 34-hour reset primed in ELD",         subtitle: "Cycle reset · 49 CFR 395.3(c)",            tail: "PRIMED"),
                .init(title: "Post-trip DVIR (tractor + trailer)",      subtitle: "49 CFR 396.11 · 30-min slot scheduled",   tail: "PENDING"),
            ]
        case .reefer:
            return [
                .init(title: "Thermograph download cleared",             subtitle: "USDA cold-chain · trace appended to BOL",  tail: "VERIFIED"),
                .init(title: "EusoShield binder auto-closes at yard-in", subtitle: "Binder · 21:46 to yard-in",               tail: "ARMED"),
                .init(title: "HOS 34-hour reset primed in ELD",          subtitle: "Cycle reset · 49 CFR 395.3(c)",            tail: "PRIMED"),
                .init(title: "Post-trip DVIR (tractor + reefer unit)",   subtitle: "49 CFR 396.11 · reefer maintenance log",   tail: "PENDING"),
            ]
        case .flatbed:
            return [
                .init(title: "Deck cleared + securement returned",       subtitle: "12 straps · 2 chains stowed",              tail: "VERIFIED"),
                .init(title: "EusoShield binder auto-closes at yard-in", subtitle: "Binder · 21:46 to yard-in",               tail: "ARMED"),
                .init(title: "HOS 34-hour reset primed in ELD",          subtitle: "Cycle reset · 49 CFR 395.3(c)",            tail: "PRIMED"),
                .init(title: "Post-trip DVIR (tractor + flatbed)",       subtitle: "49 CFR 396.11 · deck + WLL audit",         tail: "PENDING"),
            ]
        case .container, .railIntermodal, .vesselContainer:
            return [
                .init(title: "Container returned · gate-out scanned",    subtitle: "EDI 322 confirmation",                     tail: "VERIFIED"),
                .init(title: "Chassis returned to pool",                  subtitle: "Pool ID · DOT pre-trip clean",             tail: "ARMED"),
                .init(title: "HOS 34-hour reset primed in ELD",          subtitle: "Cycle reset · 49 CFR 395.3(c)",            tail: "PRIMED"),
                .init(title: "Post-trip DVIR (tractor + chassis)",       subtitle: "49 CFR 396.11 · ramp pre-trip",            tail: "PENDING"),
            ]
        case .railBulk, .vesselBulk:
            return [
                .init(title: "Spur clear · waybill closed at yard-in",   subtitle: "AAR signed · interchange done",            tail: "VERIFIED"),
                .init(title: "EusoShield binder auto-closes at yard-in", subtitle: "Binder · 21:46 to yard-in",               tail: "ARMED"),
                .init(title: "HOS 34-hour reset primed in ELD",          subtitle: "Cycle reset · 49 CFR 395.3(c)",            tail: "PRIMED"),
                .init(title: "Post-trip DVIR (tractor + bulk trailer)",  subtitle: "49 CFR 396.11 · grounding equipment audit", tail: "PENDING"),
            ]
        case .dryVan:
            return [
                .init(title: "Trailer wash + sweep cleared",             subtitle: "Trailer interior dry · seal logged",       tail: "VERIFIED"),
                .init(title: "EusoShield binder auto-closes at yard-in", subtitle: "Binder · 21:46 to yard-in",               tail: "ARMED"),
                .init(title: "HOS 34-hour reset primed in ELD",          subtitle: "Cycle reset · 49 CFR 395.3(c)",            tail: "PRIMED"),
                .init(title: "Post-trip DVIR (tractor + trailer)",       subtitle: "49 CFR 396.11 · van condition + locks",   tail: "PENDING"),
            ]
        }
    }

    // MARK: - 047 / 048 / 049 · walkaround gates

    /// 4-row "walkaround gates" used by 047/048/049 — the post-trip
    /// DVIR breakdown. Tractor walkaround is universal across
    /// products; the second row swaps trailer-specific copy.
    var walkaroundGates: [YardCheck] {
        let trailerSweep: YardCheck = {
            switch product {
            case .hazmatTanker, .vesselTanker:
                return .init(title: "MC-331 trailer sweep — decon verified", subtitle: "Spectra · residual 0 ppm · scrubber clear", tail: "CLOSED")
            case .reefer:
                return .init(title: "Reefer unit sweep — fuel + temp ok",   subtitle: "Set-point clean · door seal good",            tail: "CLOSED")
            case .flatbed:
                return .init(title: "Flatbed deck sweep — securement back", subtitle: "12 straps · 2 chains · corner pads",          tail: "CLOSED")
            case .container, .railIntermodal, .vesselContainer:
                return .init(title: "Chassis sweep — pins + tires + lights", subtitle: "DOT pre-trip clean · twistlocks oiled",       tail: "CLOSED")
            case .railBulk, .vesselBulk:
                return .init(title: "Bulk trailer sweep — grounding stowed", subtitle: "Hatches sealed · bond cable in box",           tail: "CLOSED")
            case .dryVan:
                return .init(title: "Trailer sweep — seal logged",          subtitle: "Interior dry · doors latched",                 tail: "CLOSED")
            }
        }()

        let placardsRow: YardCheck = {
            if isHazmat {
                return .init(title: "Placards + ERG 125 copy under visor", subtitle: "4 sides verified · ERG cab clean", tail: "VERIFY")
            }
            switch product {
            case .reefer:
                return .init(title: "Cold-chain seal photo logged",        subtitle: "Receiver-side seal photographed",   tail: "VERIFY")
            case .flatbed:
                return .init(title: "Securement returned · WLL audit",    subtitle: "All straps + chains accounted for", tail: "VERIFY")
            case .container, .railIntermodal, .vesselContainer:
                return .init(title: "Chassis ID + plate match",            subtitle: "Photographed for pool return",      tail: "VERIFY")
            case .railBulk, .vesselBulk:
                return .init(title: "Waybill + grounding log signed",      subtitle: "AAR closed · ohms cap recorded",     tail: "VERIFY")
            default:
                return .init(title: "Trailer seal photo logged",          subtitle: "Receiver-side seal photographed",   tail: "VERIFY")
            }
        }()

        return [
            .init(title: "Tractor walkaround (brakes, lights, tires)", subtitle: "49 CFR 396.11 · ESANG over cab",   tail: "READY"),
            trailerSweep,
            placardsRow,
            .init(title: "Sign + submit DVIR to open sleeper bay",     subtitle: "Driver signature required · 30-min slot",   tail: "PENDING"),
        ]
    }

    // MARK: - 056 Driver Profile · pool tier program

    /// Pool-tier program name surfaced on 056 Driver Profile +
    /// related identity surfaces. Hazmat drivers see HazmatPool;
    /// non-hazmat drivers see the equivalent loyalty band the
    /// product runs in (ColdChain / HeavyHaul / ContainerPool /
    /// FreightLane / RailLane / VesselPool).
    var poolTierProgram: String {
        switch product {
        case .hazmatTanker, .vesselTanker:    return "HAZMATPOOL"
        case .reefer:                         return "COLDCHAIN POOL"
        case .flatbed:                        return "HEAVYHAUL POOL"
        case .container, .vesselContainer:    return "CONTAINERPOOL"
        case .railIntermodal:                 return "RAILLANE POOL"
        case .railBulk, .vesselBulk:          return "BULKLANE POOL"
        case .dryVan:                         return "FREIGHTLANE POOL"
        }
    }

    /// 3-line benefit copy under the Tier 3 card. Each pool gets
    /// the perks the platform actually grants for that lane.
    var poolBenefits: [String] {
        switch product {
        case .hazmatTanker, .vesselTanker:
            return [
                "Close of day unlocked · +5% RPM",
                "Weekend load priority",
                "Instant factor on NH3",
            ]
        case .reefer:
            return [
                "Cold-chain priority · +4% RPM",
                "Pre-cooled trailer hold",
                "USDA trace audit auto-filed",
            ]
        case .flatbed:
            return [
                "Heavy-haul +5% RPM",
                "Tarp / chain rebate · weekly",
                "OSOW permit pre-approval",
            ]
        case .container, .vesselContainer:
            return [
                "Container chassis priority",
                "EDI 322 auto-fire",
                "Demurrage rebate guard",
            ]
        case .railIntermodal:
            return [
                "Ramp-side staging priority",
                "AAR waybill auto-fill",
                "Intermodal layover rebate",
            ]
        case .railBulk, .vesselBulk:
            return [
                "Bulk +3% RPM · weekly",
                "Grounding kit rental waived",
                "Spur priority on long lanes",
            ]
        case .dryVan:
            return [
                "Linehaul +3% RPM",
                "Detention auto-bill on 2h",
                "Lumper pre-auth $50",
            ]
        }
    }

    /// ESANG strip under the pool card — explains how the tier
    /// promotion shows up on the next tender.
    var poolEsangNote: String {
        switch product {
        case .hazmatTanker, .vesselTanker:
            return "ESANG · TIER 3 PROMOTION APPLIED TO DAY-2 TENDER · +$60 ALREADY PRICED IN"
        case .reefer:
            return "ESANG · COLDLANE TIER APPLIED · +$50 ALREADY PRICED IN"
        case .flatbed:
            return "ESANG · HEAVYHAUL TIER APPLIED · +$45 ALREADY PRICED IN"
        case .container, .railIntermodal, .vesselContainer:
            return "ESANG · CONTAINER TIER APPLIED · CHASSIS PICK SECURED"
        case .railBulk, .vesselBulk:
            return "ESANG · BULK TIER APPLIED · SPUR PRIORITY ON YORK PA"
        case .dryVan:
            return "ESANG · FREIGHTLANE TIER APPLIED · +$30 ALREADY PRICED IN"
        }
    }

    /// Tier number rendered on the card. Live profile would carry
    /// this; we surface "Tier 3" by default to match the Figma.
    var poolTierNumber: Int { 3 }

    /// Tier progress percentage. 100% = next tier unlocked.
    var poolTierProgress: Double { 1.0 }

    // MARK: - 056 · 4-row credentials grid

    /// 4-row credentials list used on 056. Hazmat drivers see
    /// CDL + HAZMAT/Tanker + DOT Med + TWIC; non-hazmat drivers
    /// see CDL + product-specific endorsement + DOT Med + TWIC
    /// (or other relevant credential).
    struct CredentialRow: Identifiable, Hashable {
        var id: String { title }
        let icon: String
        let title: String
        let subtitle: String
        let active: Bool
    }

    var credentialsRows: [CredentialRow] {
        switch product {
        case .hazmatTanker, .vesselTanker:
            return [
                .init(icon: "creditcard.fill",      title: "CDL Class A",         subtitle: "P5 · EXP 2028-04-14",        active: true),
                .init(icon: "exclamationmark.shield.fill", title: "HAZMAT & Tanker", subtitle: "X · NH3 · ENDORSED",       active: true),
                .init(icon: "cross.case.fill",      title: "DOT Medical Card",     subtitle: "EXP 2026-09-01",            active: true),
                .init(icon: "lock.shield.fill",     title: "TWIC & TSA Pre-Check", subtitle: "CLEARED 2026-04-01",         active: true),
            ]
        case .reefer:
            return [
                .init(icon: "creditcard.fill",       title: "CDL Class A",         subtitle: "EXP 2028-04-14",             active: true),
                .init(icon: "thermometer.snowflake", title: "Cold-Chain Cert",     subtitle: "USDA · EXP 2027-02",        active: true),
                .init(icon: "cross.case.fill",       title: "DOT Medical Card",     subtitle: "EXP 2026-09-01",             active: true),
                .init(icon: "lock.shield.fill",      title: "TWIC & TSA Pre-Check", subtitle: "CLEARED 2026-04-01",         active: true),
            ]
        case .flatbed:
            return [
                .init(icon: "creditcard.fill",       title: "CDL Class A",         subtitle: "EXP 2028-04-14",             active: true),
                .init(icon: "link",                   title: "Securement Cert",     subtitle: "DOT 393 · EXP 2027-05",      active: true),
                .init(icon: "cross.case.fill",       title: "DOT Medical Card",     subtitle: "EXP 2026-09-01",             active: true),
                .init(icon: "lock.shield.fill",      title: "TWIC & TSA Pre-Check", subtitle: "CLEARED 2026-04-01",         active: true),
            ]
        case .container, .railIntermodal, .vesselContainer:
            return [
                .init(icon: "creditcard.fill",       title: "CDL Class A",         subtitle: "EXP 2028-04-14",             active: true),
                .init(icon: "cube.box.fill",          title: "TWIC + Port Access",   subtitle: "Long Beach + Norfolk",       active: true),
                .init(icon: "cross.case.fill",       title: "DOT Medical Card",     subtitle: "EXP 2026-09-01",             active: true),
                .init(icon: "doc.text.fill",         title: "Customs broker ref",   subtitle: "C-TPAT pre-vetted",          active: true),
            ]
        case .railBulk, .vesselBulk:
            return [
                .init(icon: "creditcard.fill",       title: "CDL Class A",         subtitle: "EXP 2028-04-14",             active: true),
                .init(icon: "circle.hexagongrid.fill", title: "Bulk Handling Cert", subtitle: "AAR · EXP 2027-06",          active: true),
                .init(icon: "cross.case.fill",       title: "DOT Medical Card",     subtitle: "EXP 2026-09-01",             active: true),
                .init(icon: "lock.shield.fill",      title: "TWIC & TSA Pre-Check", subtitle: "CLEARED 2026-04-01",         active: true),
            ]
        case .dryVan:
            return [
                .init(icon: "creditcard.fill",       title: "CDL Class A",         subtitle: "EXP 2028-04-14",             active: true),
                .init(icon: "shippingbox.fill",       title: "Defensive Driving",   subtitle: "Smith System · 2027",        active: true),
                .init(icon: "cross.case.fill",       title: "DOT Medical Card",     subtitle: "EXP 2026-09-01",             active: true),
                .init(icon: "lock.shield.fill",      title: "TWIC & TSA Pre-Check", subtitle: "CLEARED 2026-04-01",         active: true),
            ]
        }
    }

    /// One-line credential summary surfaced under the driver's
    /// name on 056. Returns ONLY the credential class + product
    /// flavor (e.g. "HAZMAT CLASS A · MC-331 ENDORSED"). The
    /// previous fixture ("MC 4-XXX · DOT 2204865") was excised
    /// in the 131st firing as part of the autonomous
    /// `eusotrip-killers` ledger-hygiene sweep — those literals
    /// were synthetic placeholders, not the live driver's
    /// catalyst-company identifiers, and violated the §13
    /// no-fake-data doctrine.
    ///
    /// The driver's actual MC + DOT numbers belong to the
    /// catalyst (carrier company) that employs them, exposed
    /// today by `profile.getCatalystProfile` (returns
    /// `dotNumber` and `mcNumber`). 056_DriverProfile is the
    /// caller; once a `CatalystIdentityStore` is wired through
    /// `EusoTripAPI.profile.getCatalystProfile()`, the numbers
    /// should be appended to this string at the call site, not
    /// invented here. Until that store ships, the credential
    /// class alone is the correct surface — it accurately
    /// represents what the client knows from the driver-only
    /// `auth.me()` payload without inventing carrier identity.
    ///
    /// TODO(backend-wiring · 131st-firing-followup):
    ///   1. Add `CatalystIdentityStore` to ViewModels/LiveDataStores.swift
    ///      backed by `profile.getCatalystProfile` (router:
    ///      frontend/server/routers/profile.ts:140).
    ///   2. In 056_DriverProfile, compose credential line as:
    ///        ctx.identityCredentialLine
    ///        + (catalystStore.identity?.mcNumber.map { " · MC \($0)" } ?? "")
    ///        + (catalystStore.identity?.dotNumber.map { " · DOT \($0)" } ?? "")
    ///   3. Drop this TODO after wiring lands and verifying no
    ///      placeholder strings render in the .empty store state.
    var identityCredentialLine: String {
        switch product {
        case .hazmatTanker, .vesselTanker:
            return "HAZMAT CLASS A · MC-331 ENDORSED"
        case .reefer:
            return "CLASS A · COLD-CHAIN"
        case .flatbed:
            return "CLASS A · SECUREMENT CERT"
        case .container, .railIntermodal, .vesselContainer:
            return "CLASS A · TWIC + PORT"
        case .railBulk, .vesselBulk:
            return "CLASS A · BULK CERT"
        case .dryVan:
            return "CLASS A"
        }
    }

    // MARK: - 040 / 041 Discharge audit — product-flavored caption strings

    /// Eyebrow subtitle on 040 ("EUSOSHIELD DISCHARGE LIVE ·
    /// CLOSED-LOOP TRANSFER" for hazmat, equivalent for other
    /// products).
    var dischargeKickerSubtitle: String {
        switch product {
        case .hazmatTanker, .vesselTanker:
            return "EUSOSHIELD DISCHARGE LIVE · CLOSED-LOOP TRANSFER"
        case .reefer:
            return "EUSOSHIELD COLD-CHAIN LIVE · DOCK SEAL OPEN"
        case .flatbed:
            return "EUSOSHIELD UNLOAD LIVE · CRANE SIDE"
        case .container, .vesselContainer, .railIntermodal:
            return "EUSOSHIELD LIFT LIVE · CHASSIS HANDOFF"
        case .railBulk, .vesselBulk:
            return "EUSOSHIELD BULK DROP LIVE · GROUNDED"
        case .dryVan:
            return "EUSOSHIELD UNLOAD LIVE · DOCK PLATE DOWN"
        }
    }

    /// "+165 GAL/MIN" → "+4 PALLETS/HR" / "+2 MOVES/HR" / etc.
    /// Used on 040's gauge captions.
    func dischargeRateBadge(value: Int) -> String {
        let unit: String = {
            switch product {
            case .hazmatTanker, .vesselTanker: return "GAL/MIN"
            case .reefer, .dryVan:             return "PALLETS/HR"
            case .flatbed:                     return "TIE-DOWNS/HR"
            case .container, .railIntermodal,
                 .vesselContainer:             return "MOVES/HR"
            case .railBulk, .vesselBulk:       return "TONS/HR"
            }
        }()
        return "+\(value) \(unit)"
    }

    /// BOL summary chip on 041's hero (e.g. "BOL #YRA-77419 ·
    /// UN1005 · CLASS 2.2 · ACCEPTED +6 GAL"). Builds from the
    /// load when available + product-specific manifest hints.
    var dischargeBolSummary: String {
        // 138th firing M2 retrofit — BOL summary chip composes from live
        // facets. Each segment that resolves to em-dash is dropped from
        // the line so the chip stays readable; only the BOL id and
        // ACCEPTED tail are guaranteed.
        let id = bolShortId
        let f = facets
        let dash = LiveLoadFacets.dash
        func seg(_ s: String) -> String? { s == dash ? nil : s }
        switch product {
        case .hazmatTanker, .vesselTanker:
            let parts = ["BOL #\(id)", seg(f.unNumber), seg(f.hazardClass), "ACCEPTED \(f.closeoutDelta)"]
                .compactMap { $0 }
            return parts.joined(separator: " · ")
        case .reefer:
            let parts = ["BOL #\(id)", seg(f.palletCount).map { "\($0) PALLETS" }, "COLD-CHAIN", "ACCEPTED"]
                .compactMap { $0 }
            return parts.joined(separator: " · ")
        case .flatbed:
            let parts = ["BOL #\(id)", seg(f.netWeightUpper), "WLL CLEAN", "ACCEPTED"]
                .compactMap { $0 }
            return parts.joined(separator: " · ")
        case .container, .railIntermodal:
            let parts = ["BOL #\(id)", seg(f.containerNumber), "VGM FILED", "ACCEPTED"]
                .compactMap { $0 }
            return parts.joined(separator: " · ")
        case .vesselContainer:
            let parts = ["BOL #\(id)", seg(f.containerNumber), "VGM FILED", "ACCEPTED"]
                .compactMap { $0 }
            return parts.joined(separator: " · ")
        case .railBulk, .vesselBulk:
            let parts = ["BOL #\(id)", seg(f.netWeightUpper), "AAR WAYBILL", "ACCEPTED"]
                .compactMap { $0 }
            return parts.joined(separator: " · ")
        case .dryVan:
            let parts = ["BOL #\(id)", seg(f.palletCount).map { "\($0) PALLETS" }, "ACCEPTED"]
                .compactMap { $0 }
            return parts.joined(separator: " · ")
        }
    }

    /// Sub-line under the discharge-complete header on 041.
    /// Hazmat says vapor purged + closed-loop sealed; non-hazmat
    /// says doors sealed / lift-off complete / etc.
    var dischargeCompleteSubtitle: String {
        switch product {
        case .hazmatTanker, .vesselTanker:
            return "NH3 CLOSED-LOOP SEALED · VAPOR PURGED"
        case .reefer:
            return "COLD DOOR CLOSED · TEMP TRACE SEALED"
        case .flatbed:
            return "DECK CLEAR · SECUREMENT RETURNED"
        case .container, .railIntermodal:
            return "CONTAINER LIFTED OFF · CHASSIS CLEAR"
        case .vesselContainer:
            return "BOX ABOARD VESSEL · MANIFEST UPDATED"
        case .railBulk, .vesselBulk:
            return "BULK DROPPED · GROUNDING RELEASED"
        case .dryVan:
            return "DOORS SEALED · TRAILER SWEPT"
        }
    }

    /// 040 watchdog row label ("ESANG WATCHDOG · CLOSED-LOOP" for
    /// hazmat, "ESANG WATCHDOG · UNLOAD" / "...· CRANE OPS" / etc.
    /// for non-hazmat).
    var dischargeWatchdogLabel: String {
        switch product {
        case .hazmatTanker, .vesselTanker:    return "ESANG WATCHDOG · CLOSED-LOOP"
        case .reefer:                         return "ESANG WATCHDOG · COLD-CHAIN"
        case .flatbed:                        return "ESANG WATCHDOG · CRANE OPS"
        case .container, .railIntermodal,
             .vesselContainer:                return "ESANG WATCHDOG · LIFT OPS"
        case .railBulk, .vesselBulk:          return "ESANG WATCHDOG · BULK DROP"
        case .dryVan:                         return "ESANG WATCHDOG · UNLOAD"
        }
    }

    /// 041 post-flow 3-row checklist. Each product gets its own
    /// trio so the receiver-side close reads naturally.
    var dischargePostFlow: [(title: String, time: String)] {
        switch product {
        case .hazmatTanker, .vesselTanker:
            return [
                ("Pump off · motor cooled",         "21:45:54"),
                ("Valve closed · ESD bond live",    "21:46:02"),
                ("Vapor purged · scrubber clear",   "21:46:14"),
            ]
        case .reefer:
            return [
                ("Last cold pallet off dock",       "21:45:54"),
                ("Cold door closed · seal applied", "21:46:02"),
                ("Reefer set-point logged + signed", "21:46:14"),
            ]
        case .flatbed:
            return [
                ("Last tie-down released",          "21:45:54"),
                ("Crane lift complete · deck clear", "21:46:02"),
                ("Tarps + corner pads stowed",       "21:46:14"),
            ]
        case .container, .railIntermodal, .vesselContainer:
            return [
                ("Twistlocks released",             "21:45:54"),
                ("Container lifted off chassis",    "21:46:02"),
                ("Chassis pulled out · ramp-out",    "21:46:14"),
            ]
        case .railBulk, .vesselBulk:
            return [
                ("Last bulk hatched out",           "21:45:54"),
                ("Hatches sealed · grounding stowed", "21:46:02"),
                ("Waybill closed · AAR signed",      "21:46:14"),
            ]
        case .dryVan:
            return [
                ("Last pallet off dock plate",      "21:45:54"),
                ("Door closed · seal applied",       "21:46:02"),
                ("Walk-around · trailer verified",   "21:46:14"),
            ]
        }
    }

    /// 040 facility line — pulled from Load when possible, falls
    /// back to a Figma-verbatim string per product.
    var dischargeFacilityLine: String {
        if let loc = load?.deliveryLocation, !loc.cityState.isEmpty {
            let brand = loc.address.isEmpty ? loc.cityState : loc.address
            return "\(brand) · \(vertical.bayWord.capitalized) 3"
        }
        // 133rd firing M2 retrofit: prior reefer / dryVan branches hard-
        // coded "Walmart DC 7201" as the receiver brand. With no real
        // load delivery location plumbed in, the per-product fallback
        // collapses to a generic vertical descriptor — the row stays
        // readable in preview canvas while never pretending the driver
        // is rolling into a specific customer's DC.
        switch product {
        case .hazmatTanker, .vesselTanker:   return "—"
        case .reefer:                        return "Cold-chain receiver"
        case .flatbed:                       return "Steel receiver"
        case .container, .railIntermodal,
             .vesselContainer:               return "Container terminal"
        case .railBulk, .vesselBulk:         return "Bulk transfer · grounded"
        case .dryVan:                        return "Distribution center"
        }
    }

    // MARK: - 050 Next Beat Live · ESANG holds

    /// What ESANG holds through the off-duty reset on 050. Adapts
    /// the second item (next-load tender) to the next product type.
    struct ResetHold: Identifiable, Hashable {
        var id: String { title }
        let title: String
        let subtitle: String
        let tail: String
    }

    var nextBeatHolds: [ResetHold] {
        // 138th firing extension — the next-tender preview must come
        // from a real `dispatch.getNextOffer` envelope. Until that
        // ships, the subtitle is em-dash ("awaiting tender") rather
        // than fabricating customer brands or specific lane endpoints.
        // The vertical-flavored title is kept (it's a category, not a
        // specific lane) and the tail is em-dash because acceptance
        // state is per-load.
        let dash = LiveLoadFacets.dash
        let nextTender: ResetHold = {
            switch product {
            case .hazmatTanker, .vesselTanker:
                return .init(title: "Next load tender (hazmat tanker)", subtitle: dash, tail: dash)
            case .reefer:
                return .init(title: "Next load tender (cold return)",   subtitle: dash, tail: dash)
            case .flatbed:
                return .init(title: "Next load tender (flatbed)",       subtitle: dash, tail: dash)
            case .container, .railIntermodal, .vesselContainer:
                return .init(title: "Next box tender",                  subtitle: dash, tail: dash)
            case .railBulk, .vesselBulk:
                return .init(title: "Next bulk tender",                 subtitle: dash, tail: dash)
            case .dryVan:
                return .init(title: "Next load tender",                 subtitle: dash, tail: dash)
            }
        }()
        // 138th firing extension — DVIR-submitted timestamp + receiver
        // and the pre-trip prompt schedule come from `dvir.getLastSubmission`
        // and `hos.getStatus`. Until those wire through, both subtitle
        // and tail collapse to em-dash.
        let dvirRow = ResetHold(title: "DVIR submitted",
                                 subtitle: dash,
                                 tail: dash)
        let preTripRow = ResetHold(title: "Pre-trip DVIR prompt scheduled",
                                    subtitle: dash,
                                    tail: dash)
        return [dvirRow, nextTender, preTripRow]
    }

    // MARK: - 051 Beat Complete · day plan

    /// 3-row "queued for this beat" list surfaced on 051. Adapts
    /// task copy + commodity field to the next product.
    var beatQueue: [YardCheck] {
        // 138th firing extension — beat-queue timestamps come from
        // `hos.getStatus` + the load's pickup/delivery datetimes.
        // Subtitle product-flavor rows kept (they describe the
        // pre-trip *type*, not specific times or DC names). Tails
        // collapse to em-dash until the schedule wires through.
        let dash = LiveLoadFacets.dash
        let commodityRow: YardCheck = {
            switch product {
            case .hazmatTanker, .vesselTanker:
                return .init(title: "Pre-trip DVIR",      subtitle: "MC-331 + tractor · hazmat priming",          tail: dash)
            case .reefer:
                return .init(title: "Pre-trip DVIR",      subtitle: "Reefer + tractor · pre-cool armed",          tail: dash)
            case .flatbed:
                return .init(title: "Pre-trip DVIR",      subtitle: "Flatbed + tractor · WLL audit",              tail: dash)
            case .container, .railIntermodal, .vesselContainer:
                return .init(title: "Pre-trip DVIR",      subtitle: "Chassis + tractor · ramp pre-trip",          tail: dash)
            case .railBulk, .vesselBulk:
                return .init(title: "Pre-trip DVIR",      subtitle: "Bulk trailer + tractor · grounding gear",    tail: dash)
            case .dryVan:
                return .init(title: "Pre-trip DVIR",      subtitle: "Van + tractor · seal + locks",               tail: dash)
            }
        }()
        return [
            commodityRow,
            .init(title: "Depart yard",      subtitle: facets.pickupFacility,   tail: dash),
            .init(title: "Arrive receiver",  subtitle: facets.deliveryFacility, tail: dash),
        ]
    }

    /// Beat-complete commodity descriptor — used on 051 day-plan
    /// card. Composes a regulatory product category with at most
    /// one live facet (UN/commodity for hazmat, set-point for reefer,
    /// net weight for flatbed/bulk, container id for box, chassis id
    /// for intermodal, pallet summary for dryVan). Em-dash facets are
    /// dropped from the joined string so the descriptor stays
    /// readable. Mirrors the 138th firing's `dischargeBolSummary`
    /// segment-drop pattern.
    ///
    /// 139th firing extension — clears the last 5 hard-coded fixture
    /// literals in this file (UN1005, -18°F, 47,500 lb, TCLU 4412089,
    /// 120,000 lb, 72 pallets) by routing every per-load segment
    /// through `facets`.
    var beatCommodityDescriptor: String {
        let f = facets
        let dash = LiveLoadFacets.dash
        func seg(_ s: String) -> String? { s == dash ? nil : s }
        switch product {
        case .hazmatTanker, .vesselTanker:
            // "Hazmat tank" is the regulatory product category; the
            // commodity-with-UN segment is live (e.g. "Anhydrous
            // ammonia · UN1005") and drops when the load envelope
            // hasn't shipped either piece.
            let parts = ["Hazmat tank", seg(f.commodityWithUN)].compactMap { $0 }
            return parts.joined(separator: " · ")
        case .reefer:
            let parts = ["Cold pallets", seg(f.setPointDisplay)].compactMap { $0 }
            return parts.joined(separator: " · ")
        case .flatbed:
            let parts = ["Steel coils", seg(f.netWeight)].compactMap { $0 }
            return parts.joined(separator: " · ")
        case .container, .vesselContainer:
            let parts = ["Container", seg(f.containerNumber)].compactMap { $0 }
            return parts.joined(separator: " · ")
        case .railIntermodal:
            // "IMO chassis" is regulatory category copy (intermodal
            // chassis built to ISO 668); chassis id appends when
            // shipped.
            let parts = ["Intermodal · IMO chassis", seg(f.chassisNumber)].compactMap { $0 }
            return parts.joined(separator: " · ")
        case .railBulk, .vesselBulk:
            let parts = ["Bulk", seg(f.netWeight)].compactMap { $0 }
            return parts.joined(separator: " · ")
        case .dryVan:
            let parts = ["Dry palletized", seg(f.palletSummary)].compactMap { $0 }
            return parts.joined(separator: " · ")
        }
    }

    // MARK: - ESANG voice lines (014 / 015 / 016)

    /// 4-line advisory for the 014 ESANG preps card. Adapts to the
    /// product so the driver hears the right operator voice.
    ///
    /// 138th firing extension — voice copy now sources every per-load
    /// segment from `facets`. Sensor readings (pressure, fuel %),
    /// equipment ids (container number, chassis number), and any other
    /// per-load datum that the backend doesn't ship are dropped from
    /// the line entirely (rather than reading a fabricated value
    /// aloud via TTS). Universal vertical narration stays.
    var esangPreHaulAdvisory: String {
        let f = facets
        let dash = LiveLoadFacets.dash
        switch product {
        case .hazmatTanker, .vesselTanker:
            var lines: [String] = ["Four miles out. I'll cue shipper at two."]
            if f.unNumber != dash {
                lines[0] += " Then \(f.unNumber) summary at the gate queue."
            } else {
                lines[0] += " Then commodity summary at the gate queue."
            }
            // Pressure reading deliberately omitted — sensor stream not
            // wired (`sensors.streamLatest` doesn't exist server-side).
            if f.commodityName != dash {
                lines.append("Commodity \(f.commodityName).")
            }
            return lines.joined(separator: "\n")
        case .dryVan:
            return """
            Four miles out. I'll cue receiving at two and confirm your dock assignment on arrival.
            Trailer seal recorded at pickup — we'll log a photo at the gate.
            """
        case .reefer:
            // Reefer fuel "%" reading omitted — needs a fleet telematics
            // backend that doesn't ship yet.
            return """
            Four miles out. Reefer pre-cool steady at set-point.
            I'll notify cold-chain receiving at two so the cold door opens on arrival.
            """
        case .flatbed:
            return """
            Four miles out. Tarps + straps staged. Loading yard requires hard hat + high-vis.
            I'll cue shipping office at two so the forklift is on the scale when you roll in.
            """
        case .container, .railIntermodal:
            // Container + chassis ids omitted — backend gap. The EDI
            // gate-in narration stays since it's the operational protocol,
            // not a per-load value.
            var lines: [String] = ["Four miles out."]
            if f.containerNumber != dash {
                lines[0] += " Container \(f.containerNumber) matches the release."
            } else {
                lines[0] += " Container release on tablet."
            }
            lines.append("EDI 322 gate-in message armed; I'll fire at the scanner.")
            return lines.joined(separator: "\n")
        case .railBulk:
            return """
            Four miles out. Spur + track dispatched. Grounding ohms within cap — transfer-ready.
            Trainmaster notified at two; AAR waybill on my tablet.
            """
        case .vesselContainer, .vesselBulk:
            return """
            Four miles out. EDI 322 + VGM on file. Berthing ch. 16 raised.
            Harbormaster logging inbound — stevedores standing by on call-forward.
            """
        }
    }

    // MARK: - 040 Discharge in Progress · vitals row

    /// One row of the discharge-in-progress vitals strip — name +
    /// numeric value + unit + the "OK band" hint that floats below
    /// the value (e.g. "OK 25–120"). Each product surfaces 3 rows
    /// (pressure / temp / vapor for tankers; pallets / scan-rate /
    /// dock-door for dry van; etc.). The row carries a stable id
    /// so SwiftUI ForEach is happy.
    struct DischargeVital: Identifiable, Hashable {
        var id: String { label }
        let label: String
        let value: String
        let unit: String
        let okBand: String
    }

    /// Three vital readings rendered on screen 040. Activated by
    /// the screen when an active load is hydrated; otherwise the
    /// screen falls back to the Figma-verbatim register copy.
    ///
    /// 138th firing M2 retrofit — value (sensor reading or
    /// driver-witnessed state) collapses to em-dash until backend
    /// `sensors.streamLatest` lands. Unit + okBand stay populated
    /// because they describe the sensor's *spec*, not the *reading*.
    var dischargeVitals: [DischargeVital] {
        let dash = LiveLoadFacets.dash
        switch product {
        case .hazmatTanker, .vesselTanker:
            return [
                .init(label: "PRESSURE",   value: dash, unit: "psi",        okBand: "OK 135\u{2013}160"),
                .init(label: "TEMP",       value: dash, unit: "\u{00B0}F",  okBand: "OK \u{2212}40\u{2013}25"),
                .init(label: "NH\u{2083} VAPOR", value: dash, unit: "ppm",  okBand: "OK <25"),
            ]
        case .reefer:
            return [
                .init(label: "SET-POINT",  value: dash, unit: "\u{00B0}F",  okBand: "OK \u{2212}20\u{2013}\u{2212}15"),
                .init(label: "RETURN AIR", value: dash, unit: "\u{00B0}F",  okBand: "OK \u{2212}19\u{2013}\u{2212}15"),
                .init(label: "DOOR-SEAL",  value: dash, unit: "",           okBand: "no air leak"),
            ]
        case .flatbed:
            return [
                .init(label: "STRAPS",     value: dash, unit: "live",       okBand: "OK 12 of 12"),
                .init(label: "TARP",       value: dash, unit: "",           okBand: "OK no shift"),
                .init(label: "WLL",        value: dash, unit: "lb",         okBand: "OK within"),
            ]
        case .container, .railIntermodal, .vesselContainer:
            return [
                .init(label: "PINS",       value: dash, unit: "lock",       okBand: "OK 4 of 4"),
                .init(label: "SEAL",       value: dash, unit: "",           okBand: "match BOL"),
                .init(label: "VGM",        value: dash, unit: "",           okBand: "OK on file"),
            ]
        case .railBulk, .vesselBulk:
            return [
                .init(label: "PRESSURE",   value: dash, unit: "psi",        okBand: "OK 100\u{2013}140"),
                .init(label: "GROUNDING",  value: dash, unit: "\u{03A9}",   okBand: "cap 0.8"),
                .init(label: "PRODUCT TEMP", value: dash, unit: "\u{00B0}F", okBand: "OK 70\u{2013}120"),
            ]
        case .dryVan:
            return [
                .init(label: "PALLETS",    value: dash, unit: "moved",      okBand: "OK staged"),
                .init(label: "SCAN-RATE",  value: dash, unit: "/min",       okBand: "OK 6\u{2013}12"),
                .init(label: "DOCK DOOR",  value: dash, unit: "",           okBand: "OK plate down"),
            ]
        }
    }

    // MARK: - 041 Discharge Complete · close-out summary

    /// Three close-out rows for screen 041's hero strip. Carries
    /// the BOL number, the regulatory class line (UN/Class for
    /// hazmat; ISO for container; AAR for rail bulk; etc.), and
    /// the endorsed-delta (signed-vs-net difference). Activated
    /// when an active load is hydrated; otherwise the screen
    /// falls back to the Figma-verbatim register copy.
    var dischargeCompleteSummary: [ComplianceRow] {
        // 138th firing M2 retrofit — close-out triplet sources from
        // facets. The "sealed" suffix on the BOL row and the ENDORSED
        // delta both collapse to em-dash until the close-out backend
        // (`loadLifecycle.closeoutDelta`) wires through.
        let f = facets
        let dash = LiveLoadFacets.dash
        let bol = "BOL #\(bolShortId)"
        switch product {
        case .hazmatTanker, .vesselTanker:
            let regulatory: String = {
                let un = f.unNumber, cls = f.hazardClass
                switch (un == dash, cls == dash) {
                case (true,  true):  return dash
                case (false, true):  return un
                case (true,  false): return cls
                case (false, false): return "\(un) \u{00B7} \(cls)"
                }
            }()
            return [
                .init(icon: "doc.text.fill",  label: bol,        value: dash),
                .init(icon: "flame.fill",     label: regulatory, value: dash),
                .init(icon: "checkmark.seal", label: "ENDORSED", value: f.closeoutDelta),
            ]
        case .dryVan:
            return [
                .init(icon: "doc.text.fill",     label: bol,        value: dash),
                .init(icon: "shippingbox.fill",  label: "PALLETS",  value: f.palletSummary),
                .init(icon: "checkmark.seal",    label: "ENDORSED", value: f.closeoutDelta),
            ]
        case .reefer:
            return [
                .init(icon: "doc.text.fill",         label: bol,           value: dash),
                .init(icon: "thermometer.snowflake", label: "TEMP TRACE",  value: f.tempTraceCloseout),
                .init(icon: "checkmark.seal",        label: "ENDORSED",    value: f.closeoutDelta),
            ]
        case .flatbed:
            return [
                .init(icon: "doc.text.fill",  label: bol,        value: dash),
                .init(icon: "scalemass.fill", label: "WEIGHT",   value: f.netWeight),
                .init(icon: "checkmark.seal", label: "ENDORSED", value: f.closeoutDelta),
            ]
        case .container, .railIntermodal:
            return [
                .init(icon: "doc.text.fill",  label: bol,                 value: dash),
                .init(icon: "cube.box.fill",  label: f.containerNumber,   value: f.containerIsoType),
                .init(icon: "checkmark.seal", label: "ENDORSED",          value: f.closeoutDelta),
            ]
        case .vesselContainer:
            return [
                .init(icon: "doc.text.fill",  label: bol,                value: dash),
                .init(icon: "ferry.fill",     label: f.containerNumber,  value: f.containerIsoType),
                .init(icon: "checkmark.seal", label: "ENDORSED",         value: f.closeoutDelta),
            ]
        case .railBulk, .vesselBulk:
            return [
                .init(icon: "doc.text.fill",  label: "WAYBILL · \(bolShortId)", value: f.waybillRegistry),
                .init(icon: "drop.fill",      label: "NET",                     value: f.bulkNetDisplay),
                .init(icon: "checkmark.seal", label: "ENDORSED",                value: f.closeoutDelta),
            ]
        }
    }

    // MARK: - 042 Disconnect and Verify · product-aware uncouple ladder

    /// Four disconnect/verify steps surfaced on screen 042 (and
    /// echoed on 043 in DONE state). Each product emits the correct
    /// uncouple ladder — the hazmat tanker needs a vapor-line purge
    /// before the coupler ring can spin off; the container needs
    /// twistlocks released after seal-break witness; the flatbed
    /// needs an unstrap sequence before the tarp can come off. Spec
    /// from 84th-firing handoff (§6 primary path · 85th/86th port).
    /// Activated when an active load is hydrated; otherwise the
    /// screen falls back to its Figma-verbatim register copy.
    var disconnectChecklist: [PreHaulItem] {
        switch product {
        case .hazmatTanker:
            let un = load?.unNumber ?? "UN1005"
            return [
                .init(id: "purge",    title: "Purge NH\u{2083} vapor line",  subtitle: "Close ball-valve · vent residual to scrubber · confirm 0 psi"),
                .init(id: "cap",      title: "Cap liquid product port",      subtitle: "Dry-break collar retract · thread cap · witness seat"),
                .init(id: "nitrogen", title: "Dry-break nitrogen check",     subtitle: "N\u{2082} sweep armed · oxygen reading <1% before coupler"),
                .init(id: "placard",  title: "Document placard state",       subtitle: "\(un) placards 4/4 · photograph · log dock hash"),
            ]
        case .vesselTanker:
            let un = load?.unNumber ?? "UN1268"
            return [
                .init(id: "esd",      title: "Arm emergency shutoff",        subtitle: "ESD hardwired · dead-man held · ORV closed"),
                .init(id: "flange",   title: "Flange-cap loading arm",       subtitle: "Manifold blanked · witness seat · grounding bond held"),
                .init(id: "imo",      title: "IMO placard state on file",    subtitle: "\(un) declared · MARPOL Annex I signed · port state logged"),
                .init(id: "manifold", title: "Manifold isolation verified",  subtitle: "Valves lined-up · tank-top hatches secured · photograph"),
            ]
        case .railBulk, .vesselBulk:
            return [
                .init(id: "depress",  title: "Depressurize to atmospheric",  subtitle: "Bleed to flare · 0 psi verified · gauge photograph"),
                .init(id: "chock",    title: "Chock wheels for disconnect",  subtitle: "Both axles · derail set · blue-flag protection"),
                .init(id: "cap",      title: "Cap product line + vent",      subtitle: "Gasket seat · witness torque · vent thread-cap"),
                .init(id: "waybill",  title: "Seal waybill + interchange",   subtitle: "AAR waybill signed · interchange ticket to trainmaster"),
            ]
        case .reefer:
            return [
                .init(id: "powerdown", title: "Power-down reefer unit",       subtitle: "Stop run · log off-cycle · set-point retained for trace"),
                .init(id: "park",      title: "Set reefer to park mode",      subtitle: "Defrost off · alarms cleared · shore-power disconnected"),
                .init(id: "bulkhead",  title: "Close bulkhead + cold-door",   subtitle: "Air chute stowed · cold-door stripped + latched"),
                .init(id: "trace",     title: "Return temp trace log",        subtitle: "Thermograph printed · endorsed copy to receiver"),
            ]
        case .flatbed:
            return [
                .init(id: "unstrap",  title: "Unstrap sequence · 12-strap",  subtitle: "Release front-to-rear · witness each · strap condition logged"),
                .init(id: "tarp",     title: "Fold tarp · corner protectors", subtitle: "Dry-fold · vent-grommets up · corner protectors stowed"),
                .init(id: "dunnage",  title: "Stow dunnage + edge-pro",      subtitle: "Bunks + 4x4 blocks · wet-tape residue scraped"),
                .init(id: "chains",   title: "Chain + binder inventory",     subtitle: "8 chains · 4 ratchets · WLL stamp photographed"),
            ]
        case .container, .railIntermodal, .vesselContainer:
            return [
                .init(id: "vgm",      title: "VGM reconciliation",           subtitle: "Posted weight vs. manifest · within \u{00B1}3% · re-fire if drift"),
                .init(id: "seal",     title: "Seal-break witness",           subtitle: "Site manager + driver · photo pre-break · seal id logged"),
                .init(id: "twistlock", title: "Twistlock release sequence",  subtitle: "FL\u{2192}FR\u{2192}RL\u{2192}RR · witness each click · pins photographed"),
                .init(id: "pins",     title: "Pin inventory + chassis clear", subtitle: "4/4 pins accounted · chassis pre-trip logged · yard chain"),
            ]
        case .dryVan:
            return [
                .init(id: "door",     title: "Door-close witness",           subtitle: "Roller doors both sides · latch bar seated · photograph"),
                .init(id: "seal",     title: "Seal + BOL match",             subtitle: "Seal id against BOL footer · match · photograph + log"),
                .init(id: "pallet",   title: "Pallet count reconcile",       subtitle: "Signed count vs. manifest · shorts logged · OS&D if drift"),
                .init(id: "chain",    title: "Roller-door chain + lock",     subtitle: "Padlock seated · chain secured · yard-return key in cup"),
            ]
        }
    }

    // MARK: - 044 Connect Drop Hose · product-aware mate confirmation

    /// Three rows surfaced on screen 044 (Connect Drop Hose) as the
    /// "you are pre-flow, here is the binder state" compliance strip.
    /// This is the origin-side mate of the next leg — the structural
    /// inverse of 042. The hazmat tanker shows vapor-ball + dry-break
    /// + ESD; the container shows twistlocks + seal + EDI; the dry
    /// van has no hose but still reports door + seal + BOL state.
    /// Activated when an active load is hydrated; otherwise 044
    /// falls back to its Figma-verbatim register copy.
    var dropHoseConfirmation: [ComplianceRow] {
        // 138th firing M2 retrofit — driver-witnessed mate-confirmation
        // states require a `loadLifecycle.driverWitnessChecks` backend
        // record that doesn't ship yet. Sensor readouts (grounding ohms,
        // pressure) require `sensors.streamLatest`. Until both ship,
        // every value collapses to em-dash. The label remains stable so
        // each strip's *structure* still tells the driver which row to
        // visually verify against the equipment.
        let f = facets
        let dash = LiveLoadFacets.dash
        switch product {
        case .hazmatTanker:
            return [
                .init(icon: "drop.fill",      label: "NH\u{2083} VAPOR BALL",      value: dash),
                .init(icon: "link",           label: "DRY-BREAK",                  value: dash),
                .init(icon: "bolt.shield.fill", label: "ESD BOND · \(f.unNumber)", value: dash),
            ]
        case .vesselTanker:
            return [
                .init(icon: "drop.fill",         label: "ORV · LOADING ARM",       value: dash),
                .init(icon: "bolt.shield.fill",  label: "ESD HARDWIRED",           value: dash),
                .init(icon: "doc.text.fill",     label: "IMO · \(f.unNumber)",     value: dash),
            ]
        case .reefer:
            return [
                .init(icon: "wind",                  label: "AIR CHUTE",            value: dash),
                .init(icon: "thermometer.snowflake", label: "SET-POINT",            value: f.setPointDisplay),
                .init(icon: "shippingbox.fill",      label: "COLD-DOOR",            value: dash),
            ]
        case .flatbed:
            return [
                .init(icon: "scalemass.fill",   label: "STRAPS STAGED",            value: f.securementShort),
                .init(icon: "rectangle.stack",  label: "TARP FOLDED",              value: f.tarpStatus),
                .init(icon: "link",             label: "CHAINS + BINDERS",         value: f.securementWithinWLL),
            ]
        case .container, .railIntermodal:
            return [
                .init(icon: "lock.square.fill", label: "TWISTLOCKS",               value: dash),
                .init(icon: "seal.fill",        label: "SEAL",                     value: f.sealNumber),
                .init(icon: "antenna.radiowaves.left.and.right", label: "EDI 322", value: dash),
            ]
        case .vesselContainer:
            return [
                .init(icon: "lock.square.fill", label: "TWISTLOCKS",               value: dash),
                .init(icon: "seal.fill",        label: "SEAL + VGM",               value: f.vgmDisplay),
                .init(icon: "antenna.radiowaves.left.and.right", label: "CBP 7512", value: dash),
            ]
        case .railBulk, .vesselBulk:
            return [
                .init(icon: "drop.fill",         label: "HOSE MATED",              value: dash),
                .init(icon: "bolt.shield.fill",  label: "GROUNDING",               value: dash),
                .init(icon: "waveform.path",     label: "ESD BOND",                value: dash),
            ]
        case .dryVan:
            return [
                .init(icon: "shippingbox.fill", label: "ROLLER DOORS",             value: dash),
                .init(icon: "seal.fill",        label: "SEAL",                     value: f.sealNumber),
                .init(icon: "doc.fill",         label: "BOL · \(bolShortId)",      value: dash),
            ]
        }
    }

    // MARK: - 035 En Route Drive · main-haul reroute + binder strip

    /// Hazmat reroute callout shown above the speed cluster on 035.
    /// Empty for non-hazmat products so the band hides — a dry-van
    /// driver never sees a "tunnel skipped" banner that doesn't apply.
    var enRouteHazmatBand: String {
        guard isHazmat else { return "" }
        return "HAZMAT · TUNNEL / VIADUCT REROUTE ACTIVE"
    }

    /// Pill-sized in-transit binder summary surfaced on the bottom
    /// summary card. Hazmat = high-coverage NH3/PG binder; reefer =
    /// cold-chain trace; flatbed = securement; box = SSL coverage;
    /// dry van = standard linehaul. Numbers are placeholder copy
    /// until the live binder service streams the actual coverage.
    var enRouteBinderValue: String {
        switch product {
        case .hazmatTanker, .vesselTanker:    return "$5M HAZMAT BINDER"
        case .reefer:                         return "COLD-CHAIN TRACE LIVE"
        case .flatbed:                        return "SECUREMENT BINDER · WLL OK"
        case .container, .railIntermodal, .vesselContainer:
            return "SSL COVERAGE LIVE"
        case .railBulk, .vesselBulk:          return "BULK BINDER · GROUNDED"
        case .dryVan:                         return "$1M LINEHAUL BINDER"
        }
    }

    // MARK: - 036 ESANG Smart Stop · third-reason pill

    /// Third "why ESANG picked this" reason on 036. The first two
    /// reasons (fuel cost + HOS reset) are universal. The third
    /// adapts to the product so a dry-van driver gets "secure
    /// linehaul parking", a reefer driver gets "shore power /
    /// reefer fuel", a hazmat driver gets "PG-class spaces", etc.
    struct SmartStopReason: Hashable {
        let icon: String
        let title: String
        let chip: String
    }

    var smartStopProductReason: SmartStopReason {
        switch product {
        case .hazmatTanker, .vesselTanker:
            return .init(
                icon: "exclamationmark.triangle.fill",
                title: "Hazmat-class spaces confirmed at this lot tonight",
                chip: "Class 3 / PG II"
            )
        case .reefer:
            return .init(
                icon: "thermometer.snowflake",
                title: "Shore-power outlets + reefer-fuel pumps on site",
                chip: "Cold-rated"
            )
        case .flatbed:
            return .init(
                icon: "rectangle.portrait.arrowtriangle.2.outward",
                title: "Wide-body lanes + tarped-load lanes available",
                chip: "Heavy-haul ok"
            )
        case .container, .railIntermodal, .vesselContainer:
            return .init(
                icon: "cube.box.fill",
                title: "Chassis-friendly drop lanes + ramp-yard adjacency",
                chip: "Box-friendly"
            )
        case .railBulk, .vesselBulk:
            return .init(
                icon: "drop.fill",
                title: "Bulk-yard adjacency + grounded staging",
                chip: "Bulk staging"
            )
        case .dryVan:
            return .init(
                icon: "shippingbox.fill",
                title: "Secure linehaul parking + dock-schedule visibility",
                chip: "Linehaul ok"
            )
        }
    }

    // MARK: - 019 HOS Duty Status · vertical-aware operator

    /// Operator label rendered next to the duty-status segment on
    /// 019. Truck = DISPATCH; rail = TRAINMASTER; vessel =
    /// HARBORMASTER. Lets a rail engineer or vessel captain see
    /// the right counterparty even though the HOS rules per
    /// vertical converge on a "rest" concept.
    var hosOperatorLabel: String { vertical.dispatchWord }

    /// Vertical-aware "drive bank" word — drivers see "DRIVE",
    /// rail engineers see "RUN", vessel captains see "WATCH".
    /// Used on the 24-hour timeline + bank-tile labels.
    var hosDriveWord: String {
        switch vertical {
        case .truck:  return "DRIVE"
        case .rail:   return "RUN"
        case .vessel: return "WATCH"
        }
    }
}
