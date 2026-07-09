//
//  VesselMoneyCountryDone.swift
//  EusoTrip 2027 · 06 Vessel · COUNTRY-DONE data for the MONEY band (STATIC-REVIEWED — NOT compile-verified
//  in the Cowork lane; ⌘B owned by the-oath-apply).
//
//  Fire 2026-06-15 §vessel-money-countrydone (658 · 684 · 700 · 665 · 741).
//  These five money screens were already SCREEN-DONE (purpose-built, golden-caliber, distinct archetypes:
//  D&D watch / settlement / freight-bill audit / demurrage dispute / per-diem tracking). This fire takes them
//  to COUNTRY-DONE by adding the SAME reusable component already shipped on the customs cluster
//  (TriCountryAuthorityBand / CountrySegment in VesselTriCountryAuthorityBand.swift) — NO new component.
//
//  Money-band country variation is THINNER than customs: it is currency + port authority + the demurrage /
//  detention / per-diem free-time TARIFF REGIME (no AEO moat strip — that is filing-surfaces only). US row is
//  real today (vessel-native procedures); CA/MX live only in the cross-border router, so they paint STANDBY
//  and surface named-gaps to the-oath.
//
//  NAMED GAPS (one per screen, surfaced to the-oath):
//    vessel.getDemurrageRegime({shipmentId,country})  -> 658
//    vessel.getSettlementRegime({shipmentId,country}) -> 684  (getVesselSettlement.currency set; CA/MX port-charge recompute is the gap)
//    vessel.getTariffRegime({invoiceId,country})      -> 700
//    vessel.getDisputeRegime({claimId,country})       -> 665
//    vessel.getPerDiemRegime({containerId,country})   -> 741
//  Each returns {authority, basis/freeTime, ratePerDay?, currency}. Port operatingAuthority real-verified live
//  via port_lookup (CA: Vancouver Fraser Port Authority / Prince Rupert / Montreal Port Authority;
//  MX: API Manzanillo / Lázaro Cárdenas / Veracruz).
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

enum VesselMoneyCountryDone {

    // 658 Vessel Demurrage & Detention Watch — replaces the ESang pull/dispute row (the gate-out tick still
    // drives the hero meter; the band fills the freed slot above the CTA pair).
    static let demurrageWatch: [CountryRegime] = [
        .init(code: "US", authority: "FMC · OSRA 46 CFR 541",
              detail: "free time per MTO tariff · USOAK/USLGB/USHOU · USD", consequence: nil, state: .active),
        .init(code: "CA", authority: "CBSA · CTA carrier tariff",
              detail: "VFPA terminal storage · CAVAN/CAPRR/CAMTR · CAD", consequence: nil, state: .standby),
        .init(code: "MX", authority: "SAT · API estadías",
              detail: "almacenaje + 16% IVA · MXZLO/MXLZC/MXVER · MXN", consequence: nil, state: .standby),
    ]
    // Insert below the by-container ledger, above the CTA pair:
    //   TriCountryAuthorityBand(title: "TRI-COUNTRY D&D · AUTHORITY + FREE-TIME + CURRENCY",
    //                           regimes: VesselMoneyCountryDone.demurrageWatch)

    // 684 Vessel Settlement — replaces the secondary activity feed. Only the freight/demurrage/port-charge
    // legs FX by discharge country; platform fee + factoring stay USD-platform.
    static let settlement: [CountryRegime] = [
        .init(code: "US", authority: "USLGB · USD",
              detail: "MTO/terminal tariff (FMC) · THC + wharfage", consequence: nil, state: .active),
        .init(code: "CA", authority: "CAVAN · CAD",
              detail: "Vancouver Fraser Port Authority tariff · CBSA/CTA", consequence: nil, state: .standby),
        .init(code: "MX", authority: "MXZLO · MXN",
              detail: "API maniobras/almacenaje · SAT", consequence: nil, state: .standby),
    ]

    // 700 Vessel Freight Bill Audit — replaces the recoverable summary strip (+$180 net already in hero).
    static let freightAudit: [CountryRegime] = [
        .init(code: "US", authority: "FMC-filed tariff + MTO THC",
              detail: "audit basis · USOAK/USLGB · USD", consequence: "+$180 NET", state: .active),
        .init(code: "CA", authority: "CTA · VFPA THC",
              detail: "carrier-filed tariff · CAD", consequence: nil, state: .standby),
        .init(code: "MX", authority: "API maniobras · SAT",
              detail: "THC schedule · MXN", consequence: nil, state: .standby),
    ]

    // 665 Vessel Demurrage Dispute — placed in the open gap above the CTA (no element dropped).
    static let dispute: [CountryRegime] = [
        .init(code: "US", authority: "FMC charge complaint",
              detail: "OSRA 46 CFR 541 D&D billing rule · USD", consequence: nil, state: .active),
        .init(code: "CA", authority: "CTA carrier-tariff",
              detail: "free-time terms dispute · CAD", consequence: nil, state: .standby),
        .init(code: "MX", authority: "SAT/API estadías",
              detail: "Aduanas review · MXN", consequence: nil, state: .standby),
    ]

    // 741 Vessel Per Diem Tracking — DENSE (ESang return-plan is the soul, preserved). Uses the 3-pill
    // CountrySegment instead of a band. The tiered rate ladder ($150/$200/$275/$350) is the US schedule.
    static let perDiemSegment: [CountryChip] = [
        .init(code: "US · FMC", instrument: "tiered $/day · USD", active: true),
        .init(code: "CA · CTA", instrument: "carrier tariff · CAD", active: false),
        .init(code: "MX · SAT/API", instrument: "estadías · MXN", active: false),
    ]
    // Insert above the CTA pair:
    //   CountrySegment(chips: VesselMoneyCountryDone.perDiemSegment)
}
