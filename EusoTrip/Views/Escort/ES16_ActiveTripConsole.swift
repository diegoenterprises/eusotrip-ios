//
//  ES16_ActiveTripConsole.swift
//  EusoTrip — Escort · ES-16 Active Trip Console (the live-move spine).
//
//  Built from the ES-16 design-authority SVG pair
//  ("07 Escort/{Light,Dark}-SVG/ES-16 Active Trip Console.svg").
//  A vertical CORRIDOR SEGMENT spine with the current segment hero'd, running
//  PARALLEL to an ADVISORY CHIP RAIL whose order tracks the segments it judges.
//  Every chip declares what kind of truth it is — LIVE observation, DERIVED
//  rule, NOT EVALUATED blank, or STUB with no feed — because confusing those
//  four is how an escort gets hurt.
//
//  Wiring truth (code-traced this firing against the live working tree;
//  fingerprint md5 064a1b8459b8 · 4745 lines · mtime 2026-08-10T22:41:39-05:00):
//    REAL  escorts.getActiveTrip            escorts.ts:2787 — header, position,
//                                            convoy caps, lifecycle status.
//                                            Returns null when the escort holds
//                                            no active assignment; that is this
//                                            screen's empty state, not a spinner.
//    REAL  escorts.getCorridor              escorts.ts:3906 — the segment spine
//                                            AND the whole wind envelope:
//                                            legs[].wind (LegWindGate :318-330)
//                                            + corridor windGate reduce.
//    REAL  escorts.getRouteRestrictions     escorts.ts:2966 — the DERIVED rules
//                                            rail (oversize / hazmat / rush-hour
//                                            / weekend / night / clearance).
//    REAL  escorts.getConvoyProximity       escorts.ts:2875 — separation poll.
//    REAL  escorts.getClearanceEventHistory escorts.ts:4559 — the ES-02 log.
//                                            Returns the RAW clearance_events
//                                            row, so the decimal columns
//                                            posted_clearance_ft /
//                                            measured_clearance_ft
//                                            (drizzle/schema.ts:3877-3878)
//                                            serialize as JSON STRINGS. They are
//                                            decoded as String? and parsed at the
//                                            edge — decoding them as Double
//                                            threw typeMismatch and emptied the
//                                            whole card.
//    REAL  escorts.getPoleConfig            escorts.ts:4218 — the ARMED pole
//                                            height. The only honest source of
//                                            the poleHeightFt (>= 8) that the
//                                            clearance call demands.
//    REAL  escorts.getLowClearanceProximity escorts.ts:4335 — bridge COVERAGE.
//                                            Called with the load id, this
//                                            escort's OWN last position fix
//                                            (getConvoyProximity.escortLocation,
//                                            escorts.ts:2943) and the ARMED pole
//                                            height. If any one of the three is
//                                            missing the chip NAMES the missing
//                                            input instead of calling with a
//                                            filler value (see below).
//    REAL  escorts.updateTripStatus         escorts.ts:2849 — the CTA. ONLINE_ONLY.
//
//  WIND GATE — the envelope that EXISTS, rendered without embellishment:
//    computeLegWindGate (escorts.ts:345) samples a REAL WeatherKit windGust with
//    zero fabrication. No gust lands -> gust nil, status nil, available false.
//    This screen renders that as UNKNOWN, never as a green PROCEED. Thresholds
//    come from escortGustThresholds (escorts.ts:287, env-configurable, defaults
//    25 caution / 35 no-go, no-go floored at caution so the bands cannot
//    invert) and are PRINTED on the matrix because the gate echoes them.
//    HONEST CEILING, on the card's face: those are the common permit envelope,
//    NOT this permit's posted limit. Per-jurisdiction posted gust is not wired.
//
//  SURFACE / ICE: LegWindGate.band comes from a real weatherCode through
//    surfaceBandForCode (escorts.ts:299 — 4xxx wet, 5xxx snow, 6xxx/7xxx ice).
//    REPOINT: this header previously cited :297; the function declaration is at
//    :299 at the pinned fingerprint. Old :297, new :299.
//    ICE IS COVERED ONLY AS THIS BAND. There is no road-temperature or DOT ice
//    feed, which is exactly why the ice advisory is folded into the STUB chip
//    instead of being drawn as its own live gate.
//
//  CURFEW: the rush-hour / weekend / night rows are DERIVED by a server rules
//    engine over load weight, hazmat class, and the SERVER CLOCK
//    (escorts.ts:3026-3060) — not a posted municipal ordinance or state curfew
//    feed. Tagged DERIVED so nobody reads them as law.
//
//  BRIDGE COVERAGE: getLowClearanceProximity returns bridgesChecked /
//    datasetRows / coverageRadiusMi over a 15-row curated set across 12 states
//    (services/bridgeClearance.ts, ROUTE_BUFFER_MI 5). When bridgesChecked is 0
//    NOTHING was evaluated — this screen paints that in neutral and never in
//    green. Absence of coverage is not absence of hazard. Three preconditions
//    gate the call, and each failure is printed on the chip's face rather than
//    substituted: NO LOAD ON ASSIGNMENT, NO POSITION FIX (location_history holds
//    no row for this escort), POLE NOT ARMED (escorts.ts:4242 — the input
//    enforces poleHeightFt >= 8, and a client that guesses one gets a
//    BAD_REQUEST decoded into an empty structure list, i.e. a permanent false
//    all-clear). While a snapshot is painted this chip reads CACHED, never LIVE.
//
//  NOT WIRED ON PURPOSE: escorts.submitLocationUpdate EXISTS (escorts.ts:2018)
//    but is a NO-OP — it returns {success,timestamp} and writes nothing. This
//    surface never calls it and never claims to be reporting position.
//
//  STUB, named, never invented: school-zone windows, grade advisories, and
//    flood/high-water have no dataset, no procedure, and no feed. Those chips
//    render dashed with NO FEED on their face and are inert.
//
//  Offline duty (§W): mutations ONLINE_ONLY — the Unified Outbox is Driver-only
//    today, so no queue badge is ever drawn. Reads = READ_CACHED(60s) through
//    EscortOfflineCache for the spine and trip header. NOTHING measured is
//    allowed to wear a live face while a snapshot is painted:
//      · meta row — the staleness line REPLACES the live GPS dot and the
//        SEP figure entirely.
//      · hero leg — the same suppression, not a second printing: SEP and the
//        ETA are both withheld and the staleness line is stated in their place,
//        because an ETA stamped from Date() over stale remaining miles is a
//        fabricated arrival time.
//      · wind matrix — no verdict cell lights, no gust marker is placed, and the
//        per-leg subline withholds the cached gust instead of reprinting it.
//      · advisory rail — dims, and every chip whose value is a measurement
//        (surface band, OS/OW, bridge coverage) carries the CACHED tag with a
//        dashed edge, never the green LIVE tag.
//    A stale reading presented as live is the exact failure this screen exists
//    to prevent.
//
//  CHAIN / WHAT THE WRITE ACTUALLY PERSISTS (blueprint field 3). The only row
//    this surface writes is the escort_assignments status row, and the only
//    writer is escorts.updateTripStatus escorts.ts:2849 — read end to end at
//    :2849-2867. It does three things and no more: db.update(escortAssignments)
//    .set({status,updatedAt,startedAt?,completedAt?}) :2863, a convoys
//    completion update on `completed` :2864-2866, and its receipt :2867.
//      · blockchainAuditTrail — the TABLE IS REAL (drizzle/schema.ts:10018,
//        mysqlTable "blockchain_audit_trail", GAP-444) but NOTHING here writes
//        it: the identifier appears ZERO times in all 4745 lines of escorts.ts
//        and ZERO times in convoy.ts. STUB·named-gap: blockchain-audit co-insert
//        on escort status advance.
//      · audit row — recordAuditEvent IS imported (escorts.ts:17) and called at
//        ten sites (:110 :607 :1282 :1712 :1788 :1830 :1881 :2569 :3836
//        :4486) but NOT inside updateTripStatus. STUB·named-gap.
//      · WS broadcast — updateTripStatus emits no event, so dispatch and the
//        haul driver never learn the escort went on site. STUB·named-gap.
//    All three are printed under the lifecycle ladder rather than left to the
//    reader. The cross-linked writer escorts.logClearanceEvent :4385 DOES fan
//    out (:4524-4551) and DOES audit (:4486) — and still writes no blockchain
//    row, the same gap on a second event class. This screen only READS its rows.
//    Reads are CLOSED.
//
//  RBAC (blueprint field 4). Every procedure this screen calls lives in
//    server/routers/escorts.ts; none lives in convoy.ts, which matters, because
//    convoy.ts has NO escort role gate — convoy.ts:8 reads `import
//    { isolatedProcedure as protectedProcedure, router } from "../_core/trpc";`,
//    so its `protectedProcedure` is the framework's `isolatedProcedure`
//    (_core/trpc.ts:517) = requireUser + isolationMiddleware + autoAudit: auth,
//    isolation and audit — but still NOT a role check. REPOINT: earlier headers
//    cited _core/trpc.ts:155 (`protectedProcedure = t.procedure.use(requireUser)`),
//    a different procedure that understates the gate — old :155, new :517.
//    On escorts.ts the same identifier is a LOCAL ALIAS:
//    escorts.ts:11 imports `escortProcedure as protectedProcedure`, and
//    _core/trpc.ts:228 defines `escortProcedure = roleProcedure(ROLES.ESCORT)`
//    over the factory at _core/trpc.ts:216. REPOINT: earlier headers cited
//    _core/trpc.ts:212 for that assignment — old :212, new :228. So getActiveTrip
//    :2787, getCorridor :3906, getRouteRestrictions :2966, getConvoyProximity
//    :2875, getClearanceEventHistory :4559, getPoleConfig :4218,
//    getLowClearanceProximity :4335 and updateTripStatus :2849 carry a REAL
//    roleProcedure(ROLES.ESCORT) gate, verified at the definition line. Row scope
//    inside the gate via resolveEscortUserId escorts.ts:138. No loads.rate, no
//    shipper margin, no other driver's HOS reaches this surface.
//
//  MODE / COUNTRY / CURRENCY (blueprint field 5): transportMode TRUCK, COUNTRY
//    US (Louisiana LADOTD oversize permit envelope into Texas; compliance surface
//    is FMCSA/state OS-OW permitting). Currency is ABSENT by design — this
//    console prints zero money, so no USD/CAD/MXN decision reaches it.
//
//  WEB PARITY (blueprint field 1): /escort/active-trip, mounted
//    client/src/App.tsx:932 over client/src/pages/EscortActiveTrip.tsx
//    (lazy import App.tsx:165).
//
//  ─────────────────────────────────────────────────────────────────────────
//  CANON 2026-08-23.1 REWORK — 2026-08-26. The band was demoted BUILT →
//  NEEDS_REWORK · DA_FAIL on 2026-08-25 for four named defect classes; this
//  file carried all four. What changed, and what it cost:
//
//  §3 TYPE SCALE. 45 of this file's 49 `.system(size:)` calls were under 12
//  and 37 were under 10 — a live safety console set in 5.5–9.5px type. Every
//  size now lands on 12 · 14 · 15 · 17 · 28; nothing under 12 survives (10 is
//  reserved for bottom-nav captions, which `BottomNav` owns). All 18 positive
//  `.tracking()` calls are deleted and every display label is sentence case.
//  Server-owned strings are the exception and are printed VERBATIM, never
//  re-cased — the rush-hour title in particular (escorts.ts:3037).
//
//  §5 GRADIENTS. `LinearGradient.primary` / `.diagonal` and
//  `IridescentHairline` are gone with every reference. `ES16Grad` declares
//  `eusoLine` (used EXACTLY ONCE — the lifecycle spine) and `esangOrb` (the
//  counsel dot). The primary command is a FLAT #0B66E5 fill at 52pt, rx 12.
//
//  §8 COMPOSITION. The spine and the advisory rail ran as parallel columns,
//  which only fitted because the rail was set in 5.5–7.5px inside a 138pt
//  gutter. At the 12px floor they are STACKED rather than shrunk: every chip,
//  every source tag and every honest blank survives at a readable size.
//
//  §9 TRUTH LAW — four claims WITHDRAWN, each traced to the line that proves
//  it could not be sourced. This was the real failure, not the type:
//    W1 ARRIVAL ESTIMATE. `heroEtaLine` stamped Date() + remaining-miles-over-
//       cap and printed "ETA 10:33 CT · T-52 MIN". No procedure here returns an
//       arrival estimate; getCorridor's own `milestones[].eta` is the empty
//       string at all five push sites (escorts.ts:4023, :4024, :4025, :4026,
//       :4027). Verb SILENT — the honest state prints.
//    W2 PER-LEG MILEAGES. `perLegMiles = totalMiles / legCount`
//       (escorts.ts:3943) is ONE even division assigned to every leg
//       (escorts.ts:4010), so all legs necessarily carry the identical figure.
//       The basis is now stated on the face.
//    W3 DISTANCE TO NEXT WAYPOINT. The H1 "38.9 mi to Lake Charles" was
//       W2 × W4. `milesRemainingOnActiveLeg` is DELETED, not orphaned.
//    W4 COVERAGE AS A POSITION. `corridorCoverage` is `coverageForStatus`
//       (escorts.ts:3933 → :232-247) — a lifecycle-status lookup returning 0.85
//       for `escorting` plus 0.10 when the convoy is inside its target lead
//       distance. It has NO positional input; per-leg status derives from it at
//       escorts.ts:3992-3994. Labelled as the stage projection it is.
//  The H1 now carries the one live MEASUREMENT on the surface: chase
//  separation, a haversine over the escort's own newest location_history fix
//  and the primary's (escorts.ts:2928), read against the rear target
//  `targetRearDistanceMeters || 800` m and the warn threshold at 80% of it
//  (escorts.ts:2900-2903) — both now decoded and printed.
//
//  CHAIN. The convoy-alert RECEIVING half is CLOSED this fire (see the
//  `.esangRefreshSurface` observer on `body`). The emitting half is ES-02's,
//  not this screen's, and is not claimed. The status-advance chain stays
//  ONE-SIDED at escorts.ts:2849 and says so on its own face.
//  ─────────────────────────────────────────────────────────────────────────
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire projections (screen-local, private)

private struct ES16EmptyInput: Encodable {}
private struct ES16IdInput: Encodable { let id: String }
private struct ES16ClearanceInput: Encodable { let assignmentId: Int; let limit: Int }
private struct ES16StatusInput: Encodable { let assignmentId: Int; let status: String }
private struct ES16ProximityInput: Encodable {
    let assignmentId: Int; let lat: Double; let lng: Double
    let poleHeightFt: Double; let radiusMi: Double
}
private struct ES16PoleInput: Encodable { let assignmentId: Int }

/// `escorts.getCorridor.legs[].wind` — LegWindGate (escorts.ts:318-330).
/// Every optional is optional ON THE SERVER for a reason: nil gust means
/// WeatherKit produced nothing, and that must read as UNKNOWN, never as calm.
private struct ES16WindGate: Codable, Equatable {
    let gust: Double?
    let status: String?
    let band: String?
    let condition: String?
    let weatherCode: Int?
    let cautionMph: Double?
    let nogoMph: Double?
    let available: Bool?
}

private struct ES16WindEnvelope: Codable, Equatable {
    let gated: Bool?
    let available: Bool?
    let overallStatus: String?
    let peakGust: Double?
    let cautionMph: Double?
    let nogoMph: Double?
    let cautionLegs: Int?
    let nogoLegs: Int?
    let fetchedAt: String?
}

private struct ES16Leg: Codable, Identifiable, Equatable {
    let id: String
    let label: String?
    let origin: String?
    let destination: String?
    let miles: Double?
    let coverage: Double?
    let status: String?
    let chips: [String]?
    let wind: ES16WindGate?
}

private struct ES16Corridor: Codable, Equatable {
    let id: String
    let loadNumber: String?
    let origin: String?
    let destination: String?
    let routedMiles: Double?
    let corridorCoverage: Double?
    let legs: [ES16Leg]
    let legsCompleted: Int?
    let legsTotal: Int?
    let permitNumber: String?
    let windGate: ES16WindEnvelope?
}

private struct ES16Place: Codable, Equatable {
    let city: String?
    let state: String?
    var label: String { [city, state].compactMap { $0 }.joined(separator: ", ") }
}
private struct ES16Load: Codable, Equatable {
    let id: Int?
    let loadNumber: String?
    let cargoType: String?
    let hazmatClass: String?
    let weight: Double?
    let distance: Double?
    let origin: ES16Place?
    let destination: ES16Place?
}
private struct ES16Convoy: Codable, Equatable {
    let id: Int?
    let status: String?
    let maxSpeedMph: Int?
    let currentRearDistance: Int?
}
private struct ES16Trip: Codable, Equatable {
    let assignmentId: Int
    let assignmentStatus: String?
    let position: String?
    let startedAt: String?
    let load: ES16Load?
    let convoy: ES16Convoy?
}

/// `getRouteRestrictions.restrictions[]` (escorts.ts:2966). The server owns the
/// wording AND the hour gate (escorts.ts:3034) — the client prints the `title`
/// it is handed so the two can never drift apart. The row also carries a
/// sentence-length `description`; a 138pt rail chip has no slot that can hold it
/// without truncating it into a different sentence, so it is deliberately NOT
/// decoded here rather than decoded and dropped.
private struct ES16Restriction: Codable, Identifiable, Equatable {
    let type: String
    let severity: String
    let title: String
    var id: String { type }
}
private struct ES16Restrictions: Codable, Equatable {
    let weight: Double?
    let isOversize: Bool?
    let isHazmat: Bool?
    let isSuperload: Bool?
    let restrictions: [ES16Restriction]
}

/// The escort's own latest location_history fix (escorts.ts:2943). Real column,
/// or absent — never a placeholder point.
private struct ES16Fix: Codable, Equatable {
    let lat: Double?
    let lng: Double?
    let lastUpdate: String?
}

private struct ES16Proximity: Codable, Equatable {
    let distanceMeters: Double?
    /// The rear/lead separation TARGET the convoy row carries —
    /// `convoy.targetRearDistanceMeters || 800` for a chase escort, or
    /// `targetLeadDistanceMeters || 1200` for a lead (escorts.ts:2900-2902),
    /// returned at escorts.ts:2940. Decoded this fire so the hero can print the
    /// envelope the separation figure is being read against instead of leaving
    /// the reader to know it.
    let maxDistanceMeters: Double?
    /// 80% of the target (escorts.ts:2903).
    let warningThresholdMeters: Double?
    let status: String?
    let convoyMaxSpeed: Int?
    let escortLocation: ES16Fix?
}

/// `getClearanceEventHistory` row. The procedure returns the RAW clearance_events
/// row (escorts.ts:4568 `db.select().from(clearanceEvents)`), and
/// posted_clearance_ft / measured_clearance_ft are `decimal` columns
/// (drizzle/schema.ts:3877-3878) — MySQL/Drizzle serializes those as JSON
/// STRINGS. Typed String? and parsed at the edge, exactly as ES-17 does; typing
/// them Double threw typeMismatch on every row and the swallowed decode left
/// this card permanently empty.
private struct ES16ClearanceEvent: Codable, Identifiable, Equatable {
    let id: Int
    let eventType: String
    let structureName: String?
    let postedClearanceFt: String?
    let measuredClearanceFt: String?
    let occurredAt: String?
}

/// One warned structure off `getLowClearanceProximity.structures` — kept so the
/// chip can never say CLEAR over a corridor that returned warnings.
private struct ES16BridgeHit: Codable, Equatable {
    let marginFt: Double?
    let classification: String?
    let distanceMi: Double?
}

/// `getLowClearanceProximity` — bridgesChecked == 0 is the discriminator this
/// screen exists to respect.
private struct ES16BridgeCoverage: Codable, Equatable {
    let bridgesChecked: Int
    let datasetRows: Int
    let coverageRadiusMi: Double
    let structures: [ES16BridgeHit]?
}

/// `getPoleConfig` (escorts.ts:4218). `armed == false` means the escort has not
/// set a pole yet; the seed it offers is NOT a height this screen may call with.
private struct ES16PoleConfig: Codable, Equatable {
    let armed: Bool?
    let poleHeightFt: Double?
}

private struct ES16StatusReceipt: Decodable { let success: Bool; let newStatus: String }

/// The console snapshot written to disk for READ_CACHED(60s).
private struct ES16Snapshot: Codable {
    let trip: ES16Trip
    let corridor: ES16Corridor?
    let restrictions: ES16Restrictions?
    let proximity: ES16Proximity?
    let events: [ES16ClearanceEvent]
    let bridge: ES16BridgeCoverage?
    /// Why the bridge read did not happen, carried into the snapshot so the
    /// cached rail states the same reason the live rail did.
    let bridgeGate: String?
}

// MARK: - Advisory source state — part of the data, on purpose

private enum ES16Source: Equatable {
    /// `.cached` exists because a measurement read off a snapshot is NOT a live
    /// observation, and the difference has to be on the chip's face: the green
    /// LIVE tag is reserved for a value the server just supplied.
    case live, cached, derived, notEvaluated, stub
    var tag: String {
        switch self {
        case .live: return "Live"
        case .cached: return "Cached"
        case .derived: return "Derived"
        case .notEvaluated: return "0 checked"
        case .stub: return "No feed"
        }
    }
    var dashed: Bool { self == .stub || self == .cached }
}

private struct ES16Advisory: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
    let source: ES16Source
    let tint: Color
    var tagOverride: String? = nil
}

// MARK: - 14-kit radii (axis G)
//
// `Radius` (DesignSystem.swift:237) carries sm 8 · md 12 · lg 16 · xl 20 ·
// xxl 28 — it has NO 10-pt and NO 14-pt token. The kit's chip (10) and inner
// (14) values are therefore spelled out here as commented literals rather than
// rounded to the nearest token, which is what silently drifted them to 8/12 in
// the first place. Cards keep the real token, `Radius.xl` = 20.
private enum ES16Kit {
    /// Card corner — cards rx20. Bound to the design-system token.
    static let card: CGFloat = Radius.xl        // 20
    /// Inner surface nested inside a card — inner rx14. No token exists.
    static let inner: CGFloat = 14
    /// Chip — chips rx10. No token exists.
    static let chip: CGFloat = 10
    /// CTA corner — §6 puts the command dock at rx 12, not a capsule.
    static let cta: CGFloat = 12
}

/// CANON 2026-08-23.1 §4 — the exact token pairs, both twins. Mirrors the
/// shape the ES-09 canon rebuild established (`ES09Ink`) so the two escort
/// surfaces are checkable against the same table rather than against each other.
private enum ES16Ink {
    static func surface(_ dark: Bool)    -> Color { dark ? Color(hex: 0x0D0E1A) : Color(hex: 0xFFFFFF) }
    static func track(_ dark: Bool)      -> Color { dark ? Color(hex: 0x0B0C16) : Color(hex: 0xE6E9EF) }
    static func hairline(_ dark: Bool)   -> Color { dark ? Color(hex: 0x25283A) : Color(hex: 0xD8DDE6) }
    static func primary(_ dark: Bool)    -> Color { dark ? Color(hex: 0xF5F5F7) : Color(hex: 0x0D1117) }
    static func secondary(_ dark: Bool)  -> Color { dark ? Color(hex: 0xAAB2BB) : Color(hex: 0x52606D) }
    static func tertiary(_ dark: Bool)   -> Color { dark ? Color(hex: 0x7F8996) : Color(hex: 0x596978) }
    /// Action primary is deliberately identical on both twins — the CTA is the
    /// one surface that must not shift register between themes. §1 defect 3:
    /// the primary command is a FLAT fill, never a gradient.
    static let action                     = Color(hex: 0x0B66E5)
    static func link(_ dark: Bool)       -> Color { dark ? Color(hex: 0x4DA3FF) : Color(hex: 0x075FAB) }
    static let warnDot                    = Color(hex: 0xFFA726)
    static func warnInk(_ dark: Bool)    -> Color { dark ? Color(hex: 0xFFA726) : Color(hex: 0x7A4400) }
    static let successDot                 = Color(hex: 0x00C48C)
    static func successInk(_ dark: Bool) -> Color { dark ? Color(hex: 0x00C48C) : Color(hex: 0x006B4D) }
    /// Accent carries the chase / secondary role.
    static func accent(_ dark: Bool)     -> Color { dark ? Color(hex: 0xD28BEB) : Color(hex: 0x6B2B83) }
    static let neutralDot                 = Color(hex: 0x6B7280)
    static func ctaStroke(_ dark: Bool)  -> Color { dark ? Color(hex: 0x7F8996) : Color(hex: 0x778391) }
}

/// CANON 2026-08-23.1 §5 — the only gradients that survive the canon gate.
/// `eusoPrimary`, `eusoDiagonal` and `iridHairline` are RETIRED and every
/// reference to them is gone from this file. `esangOrb` / `orbSpec` live on the
/// bottom-nav orb, which `BottomNav` owns, so this screen declares only the one
/// gradient it actually paints.
private enum ES16Grad {
    /// `eusoLine`. Used EXACTLY ONCE on this screen: the assignment lifecycle
    /// spine, which is the one temporal object this console is about.
    static let eusoLine = LinearGradient(
        stops: [.init(color: Color(hex: 0x1473FF), location: 0.0),
                .init(color: Color(hex: 0x813FF5), location: 0.52),
                .init(color: Color(hex: 0xBE01FF), location: 1.0)],
        startPoint: .leading, endPoint: .trailing)

    /// `esangOrb` — the counsel dot, and nowhere else. Kept distinct from
    /// `eusoLine` so the once-per-screen EusoLine rule stays literally true.
    static let esangOrb = LinearGradient(
        stops: [.init(color: Color(hex: 0x1473FF), location: 0.0),
                .init(color: Color(hex: 0x813FF5), location: 0.52),
                .init(color: Color(hex: 0xBE01FF), location: 1.0)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// CANON 2026-08-23.1 §3 — the whole scale this screen is allowed to spend.
/// 10 is reserved for bottom-nav captions (owned by `BottomNav`, not by this
/// file), so the floor here is 12. RETIRED and absent from this screen after
/// the rework: 5.5 · 6.5 · 7 · 7.5 · 8 · 9 · 9.5 · 10.5 · 11 · 11.5 · 12.5.
/// Positive tracking is zero everywhere; only the 28 display line carries the
/// negative optical value.
private enum ES16Type {
    /// Only the steps this screen actually spends are declared. Carrying the
    /// unspent ones (17-mono, 15-mono) would advertise a ramp the surface does
    /// not paint, which is the same class of untruth as a value with no source.
    static let title      = Font.system(size: 28, weight: .bold)
    static let large      = Font.system(size: 17, weight: .semibold)
    static let rowTitle   = Font.system(size: 15, weight: .semibold)
    static let ctaLabel   = Font.system(size: 15, weight: .semibold)
    static let label      = Font.system(size: 12, weight: .semibold)
    static let body       = Font.system(size: 12, weight: .medium)
    static let mono       = Font.system(size: 12, weight: .medium, design: .monospaced)
    /// §3 allows exactly one 14 — the chevron glyph.
    static let chevron    = Font.system(size: 14, weight: .semibold)
}

private enum ES16Position: String {
    case lead, chase, steer, highPole
    init(wire: String?) {
        switch (wire ?? "").lowercased() {
        case "chase", "rear": self = .chase
        case "steer": self = .steer
        case "high_pole", "highpole", "pole": self = .highPole
        default: self = .lead
        }
    }
    /// §3 sentence case — these are labels, not identifiers.
    var label: String {
        switch self {
        case .lead: return "Lead"
        case .chase: return "Chase"
        case .steer: return "Steer"
        case .highPole: return "High-pole"
        }
    }
    /// §4 — the position ink is twin-dependent (the accent row is #6B2B83 light
    /// / #D28BEB dark), so this takes the scheme rather than returning a
    /// theme-invariant brand constant the way run-1 did.
    func ink(_ dark: Bool) -> Color {
        switch self {
        case .lead: return ES16Ink.action
        case .chase: return ES16Ink.accent(dark)
        case .steer: return ES16Ink.warnInk(dark)
        case .highPole: return ES16Ink.warnDot
        }
    }
}

// MARK: - Screen

struct EscortActiveTripConsole: View {
    // `@Environment(\.palette)` is gone: after the canon rework every colour on
    // this screen resolves through `ES16Ink`, which is the §4 table verbatim.
    // Leaving the environment property declared would have implied a second,
    // competing source of colour truth on a surface that must have exactly one.
    @Environment(\.colorScheme) private var colorScheme

    @State private var trip: ES16Trip?
    @State private var corridor: ES16Corridor?
    @State private var restrictions: ES16Restrictions?
    @State private var proximity: ES16Proximity?
    @State private var events: [ES16ClearanceEvent] = []
    @State private var bridge: ES16BridgeCoverage?
    /// Set when the bridge read could NOT be made; printed verbatim on the chip.
    @State private var bridgeGate: String?

    @State private var loading = true
    @State private var errorMessage: String?
    @State private var statusInFlight = false
    /// nil == live. Non-nil replaces the GPS dot and dims the advisory rail.
    @State private var cacheAge: TimeInterval?

    private let cacheTTL: TimeInterval = 60
    private let cacheKey = "escort.activetrip.corridor"

    private var isDark: Bool { colorScheme == .dark }
    private var isSnapshot: Bool { cacheAge != nil }

    private static let statusLadder = ["accepted", "en_route", "on_site", "escorting", "completed"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading && trip == nil {
                    LifecycleCard { Text("Reading the corridor…").font(ES16Type.body).foregroundStyle(ES16Ink.secondary(isDark)) }
                } else if trip == nil {
                    noActiveMove
                } else {
                    if let errorMessage {
                        Text(errorMessage).font(ES16Type.body).foregroundStyle(Brand.danger)
                    }
                    windSection
                    spineSection
                    clearanceSection
                    lifecycleLadder
                    esangRow
                }
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) { ctaBar }
        .task { await load() }
        .eusoRefreshable { await load(forceNetwork: true) }
        // CHAIN CLOSURE — DO NOT REMOVE. The height-pole / low-clearance chain is
        // real and live end to end, and until this fire it died at the process
        // edge on this surface.
        //
        //   emit   escorts.logClearanceEvent — clearance_events insert
        //          escorts.ts:4423; a strike additionally opens a first-class
        //          `clearance_strike` incident escorts.ts:4459-4463; the
        //          CONVOY_ALERT payload then fans out to the LOAD room
        //          escorts.ts:4524, DISPATCH_UPDATES escorts.ts:4525, the
        //          dispatching company's board room derived load-first
        //          escorts.ts:4544, the haul driver's USER room escorts.ts:4545
        //          and every convoy member's USER room escorts.ts:4549.
        //   receive RealtimeService.swift:519 matches `escort:convoy_alert` and
        //          re-posts it as `.esangRefreshSurface` at
        //          RealtimeService.swift:529 (name declared EusoTripApp.swift:384).
        //          That arm's own comment names ES-16 as a surface it refreshes —
        //          but ES-16 never observed the notification, so the refresh it
        //          promised never happened. This observer is that missing half.
        //
        // Scope, stated honestly: this closes the RECEIVING half only. ES-16 does
        // not emit convoy alerts — it never calls logClearanceEvent
        // (escorts.ts:4385); ES-02 owns that write. And it does not close the
        // status-advance chain, which stays one-sided at escorts.ts:2849.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await load(forceNetwork: true) }
        }
    }

    // MARK: Header

    // CANON 2026-08-23.1 §1/§3/§5: the 9px all-caps 1.0-tracked eyebrow and the
    // brand-gradient headline are both retired defect classes. The eyebrow is
    // gone outright (the exemplar carries zero ✦ — the orb is the mark), the
    // orientation line is sentence case at the 12 floor with tracking 0, and the
    // H1 is flat ink primary. IridescentHairline is a brand-gradient element and
    // is replaced by the flat hairline token.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Escort · active trip").font(ES16Type.label)
                    .foregroundStyle(ES16Ink.secondary(isDark))
                Spacer()
                if let a = trip?.assignmentId {
                    Text("Assignment \(a)").font(ES16Type.body)
                        .foregroundStyle(ES16Ink.tertiary(isDark))
                }
            }
            Text(corridorLedger).font(ES16Type.mono)
                .foregroundStyle(ES16Ink.secondary(isDark))
                .lineLimit(1).minimumScaleFactor(0.75)
            // §3 display ramp: H1 28 / 700 / -0.4, flat ink — never a gradient fill.
            Text(headlineText).font(ES16Type.title).tracking(-0.4)
                .foregroundStyle(ES16Ink.primary(isDark)).lineLimit(1).minimumScaleFactor(0.8)
            Text(subheadText).font(ES16Type.body)
                .foregroundStyle(ES16Ink.secondary(isDark))
            metaRow
            Rectangle().fill(ES16Ink.hairline(isDark)).frame(height: 1)
        }
    }

    /// The header identity line. The permit is the escort's authority to be on
    /// this road at this weight — `getCorridor.permitNumber` (escorts.ts:4183,
    /// loads.specialPermit) is printed here when the server has one, and the
    /// segment is simply absent when it does not. No "PENDING", no placeholder.
    private var corridorLedger: String {
        let load = trip?.load?.loadNumber ?? "—"
        let o = corridor?.origin ?? trip?.load?.origin?.label ?? "—"
        let d = corridor?.destination ?? trip?.load?.destination?.label ?? "—"
        // §3 sentence case — the run-1 `.uppercased()` calls were the eyebrow
        // shouting defect wearing a mono face. The permit number keeps whatever
        // case the server sent; it is an identifier, not a label.
        var line = "\(load) · \(o) → \(d)"
        if let permit = corridor?.permitNumber, !permit.isEmpty {
            line += " · permit \(permit)"
        }
        return line
    }
    /// TRUTH LAW §9. Run-1's H1 was "38.9 mi to Lake Charles" — an
    /// extrapolation over two fabrications (even-split leg miles ×
    /// lifecycle-status coverage). WITHDRAWN. The H1 now carries the one live
    /// MEASUREMENT this console owns: the chase separation, a haversine over the
    /// escort's own newest `location_history` fix and the primary's
    /// (escorts.ts:2928). That is also the number the rear escort is actually
    /// watching at 45 mph. When no fix has landed the screen says so rather than
    /// printing a zero.
    private var headlineText: String {
        guard corridor != nil || trip != nil else { return "Corridor unavailable" }
        guard let m = proximity?.distanceMeters else { return "No position fix" }
        return "\(Int((m * 3.28084).rounded())) ft"
    }
    private var subheadText: String {
        let status = (trip?.assignmentStatus ?? "").replacingOccurrences(of: "_", with: " ")
        guard proximity?.distanceMeters != nil else {
            return "Separation unavailable · \(status)"
        }
        let pos = ES16Position(wire: trip?.position).label.lowercased()
        guard let warn = proximity?.warningThresholdMeters,
              let maxD = proximity?.maxDistanceMeters else {
            return "\(pos) separation · \(status)"
        }
        return "\(pos) separation · warn at \(Int((warn * 3.28084).rounded())) ft · target \(Int((maxD * 3.28084).rounded())) ft"
    }

    private var metaRow: some View {
        HStack(spacing: Space.s3) {
            let pos = ES16Position(wire: trip?.position)
            // §4: the chase / secondary role rides the accent token. Sentence
            // case at the 12 floor, tracking 0.
            Text(pos.label).font(ES16Type.label)
                .foregroundStyle(pos.ink(isDark))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(pos.ink(isDark).opacity(isDark ? 0.24 : 0.16)))

            // The honesty law: a snapshot NEVER wears the live dot.
            if let cacheAge {
                HStack(spacing: 5) {
                    Circle().fill(ES16Ink.warnDot).frame(width: 7, height: 7)
                    Text(EscortOfflineCache.stalenessLine(age: cacheAge))
                        .font(ES16Type.mono)
                        .foregroundStyle(ES16Ink.warnInk(isDark))
                }
            } else {
                HStack(spacing: 5) {
                    ZStack {
                        Circle().fill(ES16Ink.successDot.opacity(0.25)).frame(width: 13, height: 13)
                        Circle().fill(ES16Ink.successDot).frame(width: 7, height: 7)
                    }
                    Text(separationLine).font(ES16Type.mono)
                        .foregroundStyle(ES16Ink.primary(isDark))
                }
            }
            Spacer()
        }
    }
    /// Separation is the one live MEASUREMENT on this surface: a haversine over
    /// the escort's own newest `location_history` fix and the primary's
    /// (escorts.ts:2928), against the rear target
    /// `convoy.targetRearDistanceMeters || 800` m and a warn threshold at 80% of
    /// it (escorts.ts:2902-2903). Both thresholds are printed so the figure is
    /// readable without the reader having to know the envelope.
    private var separationLine: String {
        guard let m = proximity?.distanceMeters else { return "GPS live" }
        let sep = Int((m * 3.28084).rounded())
        guard let warn = proximity?.warningThresholdMeters else { return "GPS live · \(sep) ft behind" }
        return "GPS live · \(sep) ft behind · warn at \(Int((warn * 3.28084).rounded())) ft"
    }

    private var noActiveMove: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("No active move").font(ES16Type.rowTitle)
                    .foregroundStyle(ES16Ink.primary(isDark))
                Text("You hold no assignment in accepted, en route, on site, or escorting right now.")
                    .font(ES16Type.body).foregroundStyle(ES16Ink.secondary(isDark))
            }
        }
    }

    // MARK: Wind matrix (EVO-1042 as content)

    private enum WindVerdict: String { case proceed, caution, hold, unknown, notGated }

    private var windVerdict: WindVerdict {
        guard let env = corridor?.windGate, env.gated == true else { return .notGated }
        if isSnapshot { return .unknown }               // stale wind is not a verdict
        switch env.overallStatus {
        case "go": return .proceed
        case "caution": return .caution
        case "nogo": return .hold
        default: return .unknown
        }
    }
    private var cautionThreshold: Double { corridor?.windGate?.cautionMph ?? 25 }
    private var nogoThreshold: Double { corridor?.windGate?.nogoMph ?? 35 }
    private var peakGust: Double? { isSnapshot ? nil : corridor?.windGate?.peakGust }
    private var peakGustLegIndex: Int? {
        guard let peak = peakGust, let legs = corridor?.legs,
              let leg = legs.first(where: { ($0.wind?.gust ?? -1) == peak }) else { return nil }
        return (legs.firstIndex(of: leg) ?? 0) + 1
    }
    private var surfaceBand: String? {
        corridor?.legs.compactMap { $0.wind?.band }.first { $0 != "dry" }
    }
    private var surfaceCode: Int? { corridor?.legs.compactMap { $0.wind?.weatherCode }.first }

    private var windSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            // §8 section label: 12/600 secondary left, 12/500 tertiary right.
            HStack {
                Text("Wind gate · WeatherKit")
                    .font(ES16Type.label)
                    .foregroundStyle(ES16Ink.secondary(isDark))
                Spacer()
                Text(isSnapshot ? "Cached · not live" : "Not a posted limit")
                    .font(ES16Type.body)
                    .foregroundStyle(isSnapshot ? ES16Ink.warnInk(isDark) : ES16Ink.tertiary(isDark))
            }
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    verdictCell("Proceed", "under \(Int(cautionThreshold))", ES16Ink.successDot,
                                lit: windVerdict == .proceed)
                    verdictCell("Caution", "\(Int(cautionThreshold))–\(Int(nogoThreshold) - 1)",
                                ES16Ink.warnDot, lit: windVerdict == .caution)
                    // §4 carries no danger row; the exemplar had no danger state
                    // to express. `Brand.danger` is the pre-existing house token
                    // and is kept for the one genuine hold verdict rather than a
                    // colour being invented for it. Named, not invented.
                    verdictCell("Hold", "\(Int(nogoThreshold)) and above", Brand.danger,
                                lit: windVerdict == .hold)
                }
                thresholdRuler
                HStack(alignment: .top) {
                    Text(windFootnote).font(ES16Type.body)
                        .foregroundStyle(ES16Ink.tertiary(isDark)).lineLimit(2)
                    Spacer(minLength: Space.s2)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: ES16Kit.card, style: .continuous).fill(ES16Ink.surface(isDark)))
            .overlay(RoundedRectangle(cornerRadius: ES16Kit.card, style: .continuous).strokeBorder(ES16Ink.hairline(isDark)))
        }
    }

    private func verdictCell(_ title: String, _ range: String, _ tint: Color, lit: Bool) -> some View {
        VStack(spacing: 3) {
            Text(title).font(ES16Type.label)
                .foregroundStyle(lit ? Color.white : tint)
            Text(range).font(ES16Type.mono)
                .foregroundStyle(lit ? Color.white : tint)
        }
        .frame(maxWidth: .infinity).frame(height: 44)
        .background(RoundedRectangle(cornerRadius: ES16Kit.inner, style: .continuous)
            .fill(lit ? tint : tint.opacity(isDark ? 0.16 : 0.10)))
        .overlay(RoundedRectangle(cornerRadius: ES16Kit.inner, style: .continuous)
            .strokeBorder(lit ? tint : .clear, lineWidth: 1.5))
    }

    /// 0 → 45 mph band ruler carrying the live peak gust. When no gust landed
    /// the marker is simply absent — the ruler never invents a position.
    private var thresholdRuler: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let scale = w / 45.0
            let cautionX = cautionThreshold * scale
            let nogoX = nogoThreshold * scale
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    Rectangle().fill(ES16Ink.successDot.opacity(0.28)).frame(width: cautionX)
                    Rectangle().fill(ES16Ink.warnDot.opacity(0.50)).frame(width: max(nogoX - cautionX, 0))
                    Rectangle().fill(ES16Ink.warnInk(isDark).opacity(isDark ? 0.90 : 0.50))
                }
                .frame(height: 6).clipShape(Capsule()).offset(y: 22)

                // Peak-gust marker: an ink-primary needle, the SAME marker idiom
                // as the EusoLine NOW rule, so the gust reads against both the
                // caution and the hold band in either twin. Run-1 drew it in the
                // warn tint, which in the dark column is the caution band's own
                // colour — the marker vanished into the band it was marking.
                if let gust = peakGust {
                    Rectangle().fill(ES16Ink.primary(isDark))
                        .frame(width: 2, height: 14)
                        .offset(x: min(max(gust * scale, 1), w - 2), y: 18)
                }

                // The two thresholds are printed because the gate echoes them.
                HStack(spacing: 0) {
                    Text("\(Int(cautionThreshold)) caution").font(ES16Type.body)
                        .foregroundStyle(ES16Ink.warnInk(isDark))
                    Spacer(minLength: Space.s2)
                    Text("\(Int(nogoThreshold)) hold").font(ES16Type.body)
                        .foregroundStyle(ES16Ink.tertiary(isDark))
                }
                .frame(width: w).offset(y: 0)
            }
        }
        .frame(height: 42)
    }

    private var windFootnote: String {
        guard let env = corridor?.windGate, env.gated == true else {
            return "Load is not wind-gated · OS/OW and hazmat only"
        }
        guard let gust = peakGust else {
            return isSnapshot ? "Cached read · verdict withheld until a live sample"
                              : "No real gust landed · verdict unknown, not calm"
        }
        let legPart = peakGustLegIndex.map { "leg \($0)" } ?? "corridor"
        let band = surfaceBand.map { " · \($0) band" } ?? ""
        return "Peak gust \(Int(gust)) mph on \(legPart)\(band) · gated because OS/OW · thresholds are the common permit envelope, not this permit's posted limit"
    }

    // MARK: Spine + advisory rail (the parallel columns)

    private var spineSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(spineHeader).font(ES16Type.label)
                    .foregroundStyle(ES16Ink.secondary(isDark))
                Spacer()
                // TRUTH LAW §9 — WITHDRAWN this fire: no procedure on this
                // screen returns an arrival estimate, and getCorridor's own
                // `milestones[].eta` is the empty string at all five push sites
                // (escorts.ts:4023-4027). Verb SILENT; the honest state prints.
                Text("Arrival estimate unavailable").font(ES16Type.body)
                    .foregroundStyle(ES16Ink.tertiary(isDark))
            }
            // CANON 2026-08-23.1 §3/§8: run-1 ran the spine and the advisory rail
            // as PARALLEL columns, which only fitted because the rail was set in
            // 5.5–7.5px type inside a 138pt gutter. At the 12px operational floor
            // a 138pt column cannot hold a chip label, so the two columns are
            // stacked instead of shrunk — the rail keeps every chip, every source
            // tag and every honest blank, at a size an escort can read at 45 mph.
            // The vertical order still tracks the segments the chips judge.
            segmentSpine
            advisoryRail
        }
    }
    private var spineHeader: String {
        guard let miles = corridor?.routedMiles else { return "Corridor spine" }
        return "Corridor spine · \(miles.formatted(.number.precision(.fractionLength(1)))) mi"
    }

    private var segmentSpine: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(corridor?.legs ?? []) { leg in
                if (leg.status ?? "") == "active" { heroLeg(leg) } else { compactLeg(leg) }
            }
            Rectangle().fill(ES16Ink.hairline(isDark)).frame(height: 1).padding(.top, Space.s2)
            Text(coverageBasisLine).font(ES16Type.body)
                .foregroundStyle(ES16Ink.tertiary(isDark)).padding(.top, 6)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ES16Kit.card, style: .continuous).fill(ES16Ink.surface(isDark)))
        .overlay(RoundedRectangle(cornerRadius: ES16Kit.card, style: .continuous).strokeBorder(ES16Ink.hairline(isDark)))
    }

    private func compactLeg(_ leg: ES16Leg) -> some View {
        let done = (leg.status ?? "") == "completed"
        let cautioned = (leg.chips ?? []).contains { $0.hasPrefix("WIND") }
        return HStack(alignment: .top, spacing: Space.s2) {
            ZStack {
                if done {
                    Circle().fill(ES16Ink.successDot).frame(width: 18, height: 18)
                    Image(systemName: "checkmark").font(ES16Type.body)
                        .foregroundStyle(.white)
                } else {
                    Circle().strokeBorder(cautioned ? ES16Ink.warnDot : ES16Ink.tertiary(isDark), lineWidth: 2)
                        .frame(width: 12, height: 12)
                }
            }
            .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(legIndex(leg)) · \(legRoute(leg))")
                    .font(ES16Type.rowTitle)
                    .foregroundStyle(ES16Ink.primary(isDark)).lineLimit(1).minimumScaleFactor(0.85)
                Text(compactSubline(leg, done: done, cautioned: cautioned))
                    .font(ES16Type.body)
                    .foregroundStyle(done ? ES16Ink.successInk(isDark)
                                          : (cautioned ? ES16Ink.warnInk(isDark) : ES16Ink.tertiary(isDark)))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
    /// Gated exactly as the matrix is gated (`windVerdict`): on a snapshot the
    /// per-leg gust is a stale sample, so it is WITHHELD here too. Printing
    /// "WIND CAUTION 28" three rows under a matrix that says the verdict is
    /// withheld is the same lie told twice.
    /// TRUTH LAW §9 — the per-leg mileage is NOT a surveyed leg distance. The
    /// server computes `perLegMiles = totalMiles / legCount` once
    /// (escorts.ts:3943) and assigns that ONE figure to every leg
    /// (escorts.ts:4010), so all legs necessarily carry the identical number.
    /// Run-1 printed five different leg distances, which this proc cannot
    /// produce. The basis is now stated on the face instead of implied.
    private func compactSubline(_ leg: ES16Leg, done: Bool, cautioned: Bool) -> String {
        let miles = leg.miles.map { "\($0.formatted(.number.precision(.fractionLength(1)))) mi even split" } ?? "mileage unavailable"
        if done { return "\(miles) · done" }
        if cautioned {
            if isSnapshot { return "\(miles) · cached · not judged" }
            if let g = leg.wind?.gust { return "\(miles) · wind caution \(Int(g)) mph" }
            return "\(miles) · wind caution · no gust landed"
        }
        return "\(miles) · pending"
    }

    private func heroLeg(_ leg: ES16Leg) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            ZStack {
                Circle().strokeBorder(ES16Ink.action, lineWidth: 2.5).frame(width: 16, height: 16)
                Circle().fill(ES16Ink.action).frame(width: 6, height: 6)
            }
            .frame(width: 16).padding(.top, 28)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Segment \(legIndex(leg)) of \(corridor?.legsTotal ?? (corridor?.legs.count ?? 0))")
                        .font(ES16Type.label)
                        .foregroundStyle(ES16Ink.secondary(isDark))
                    Spacer()
                    Text("Active").font(ES16Type.body)
                        .foregroundStyle(ES16Ink.action)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(ES16Ink.action.opacity(isDark ? 0.22 : 0.12)))
                }
                Text(legRoute(leg)).font(ES16Type.large)
                    .foregroundStyle(ES16Ink.primary(isDark)).lineLimit(1).minimumScaleFactor(0.85)
                // §5: the corridor bar is a plain progress track, NOT the
                // EusoLine. The one EusoLine on this screen is the lifecycle
                // spine under the ladder — the trip's own timeline.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(ES16Ink.track(isDark)).frame(height: 6)
                        Capsule().fill(ES16Ink.action)
                            .frame(width: geo.size.width * CGFloat(leg.coverage ?? 0), height: 6)
                    }
                }
                .frame(height: 6)
                Text(heroMilesLine(leg)).font(ES16Type.body)
                    .foregroundStyle(ES16Ink.secondary(isDark))
                Text(heroConvoyLine).font(ES16Type.body)
                    .foregroundStyle(isSnapshot ? ES16Ink.warnInk(isDark) : ES16Ink.secondary(isDark))
                if let eta = heroEtaLine {
                    Text(eta).font(ES16Type.body)
                        .foregroundStyle(ES16Ink.tertiary(isDark))
                }
            }
            .padding(Space.s3)
            .background(RoundedRectangle(cornerRadius: ES16Kit.inner, style: .continuous).fill(ES16Ink.track(isDark)))
            .overlay(RoundedRectangle(cornerRadius: ES16Kit.inner, style: .continuous)
                .strokeBorder(ES16Ink.action.opacity(0.35), lineWidth: 1.5))
        }
        .padding(.vertical, 6)
    }

    private func legRoute(_ leg: ES16Leg) -> String {
        if let o = leg.origin, let d = leg.destination { return "\(o) → \(d)" }
        return leg.label ?? "—"
    }
    /// TRUTH LAW §9. `leg.coverage` is NOT a position. It is derived
    /// (escorts.ts:3992-3994) from the corridor-level `coverage`, which is
    /// `coverageForStatus` (escorts.ts:3933 → escorts.ts:232-247) — a
    /// LIFECYCLE-STATUS LOOKUP returning 0.85 for `escorting`, plus 0.10 when
    /// the convoy sits inside its target lead distance. Nothing in that number
    /// is a measurement of where the convoy is, so it is labelled as the stage
    /// projection it is and the "N mi to go" extrapolation run-1 built on top of
    /// it is WITHDRAWN.
    private func heroMilesLine(_ leg: ES16Leg) -> String {
        let miles = leg.miles.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—"
        let pct = Int(((leg.coverage ?? 0) * 100).rounded())
        return "\(miles) mi even split · \(pct)% by lifecycle stage, not a position fix"
    }
    /// Separation is a LIVE measurement, so the hero suppresses it on a snapshot
    /// exactly as the meta row does — the staleness line takes the figure's
    /// place rather than the figure being reprinted without a marker. The convoy
    /// speed CAP is a convoy configuration, not a reading, so it survives.
    private var heroConvoyLine: String {
        let pos = ES16Position(wire: trip?.position).label.lowercased()
        let cap = proximity?.convoyMaxSpeed ?? trip?.convoy?.maxSpeedMph
        let capPart = "cap \(cap.map { "\($0) mph" } ?? "unavailable")"
        if let cacheAge {
            return "\(pos) · \(EscortOfflineCache.stalenessLine(age: cacheAge)) · \(capPart)"
        }
        let sep = proximity?.distanceMeters.map { "\(Int(($0 * 3.28084).rounded())) ft" } ?? "unavailable"
        return "\(pos) separation \(sep) · \(capPart)"
    }
    /// TRUTH LAW §9 — WITHDRAWN 2026-08-26. Run-1 stamped an arrival clock from
    /// `Date()` plus remaining-miles-over-cap and printed it as "ETA 10:33 CT ·
    /// T-52 MIN". Both inputs were already fabrications: the remaining miles came
    /// from an EVEN-DIVISION leg length (escorts.ts:3943/:4010) multiplied by a
    /// LIFECYCLE-STATUS constant (escorts.ts:232-247), and no procedure this
    /// screen calls returns an arrival estimate at all — getCorridor's own
    /// `milestones[].eta` is the empty string at every push site
    /// (escorts.ts:4023, :4024, :4025, :4026, :4027). An arrival time is the most
    /// dangerous number on a live safety console to invent, so the verb is SILENT
    /// and the honest state prints in tertiary ink. The missing half is a real
    /// routed-ETA source (per-leg geometry + a live position), named here and not
    /// faked. This property is kept rather than deleted so the surface keeps
    /// SAYING the estimate is unavailable instead of quietly showing nothing.
    private var heroEtaLine: String? {
        isSnapshot ? "Arrival estimate unavailable · cached corridor"
                   : "Arrival estimate unavailable · no routed-ETA source"
    }

    private var advisoryRail: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(advisories) { chip in advisoryCard(chip) }
            Rectangle().fill(ES16Ink.hairline(isDark)).frame(height: 1).padding(.top, Space.s2)
            Text("Ice reads only as the surface band above")
                .font(ES16Type.body)
                .foregroundStyle(ES16Ink.tertiary(isDark)).padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ES16Kit.card, style: .continuous).fill(ES16Ink.surface(isDark)))
        .overlay(RoundedRectangle(cornerRadius: ES16Kit.card, style: .continuous).strokeBorder(ES16Ink.hairline(isDark)))
        .opacity(isSnapshot ? 0.55 : 1)
    }

    private func advisoryCard(_ chip: ES16Advisory) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(chip.label).font(ES16Type.label)
                    .foregroundStyle(chip.source == .stub ? ES16Ink.tertiary(isDark) : chip.tint)
                    .lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Text(chip.tagOverride ?? chip.source.tag)
                    .font(ES16Type.body)
                    .foregroundStyle(tagInk(chip.source))
                    .lineLimit(1)
            }
            Text(chip.value).font(ES16Type.body)
                .foregroundStyle(chip.source == .stub ? ES16Ink.tertiary(isDark) : chip.tint)
                .lineLimit(2).minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ES16Kit.chip, style: .continuous)
            .fill(chip.source == .stub ? Color.clear : chip.tint.opacity(isDark ? 0.14 : 0.08)))
        .overlay(RoundedRectangle(cornerRadius: ES16Kit.chip, style: .continuous)
            .strokeBorder(chip.source == .stub ? ES16Ink.tertiary(isDark).opacity(0.45) : chip.tint.opacity(0.40),
                          style: StrokeStyle(lineWidth: 1, dash: chip.source.dashed ? [4, 3] : [])))
        .overlay(alignment: .leading) {
            if chip.source != .stub {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(chip.tint).frame(width: 3)
            }
        }
        .allowsHitTesting(chip.source != .stub)
    }
    private func tagInk(_ s: ES16Source) -> Color {
        switch s {
        case .live: return ES16Ink.successInk(isDark)
        case .cached, .notEvaluated: return ES16Ink.warnInk(isDark)
        default: return ES16Ink.tertiary(isDark)
        }
    }

    /// Fixed order so the rail's rhythm never shuffles under the reader between
    /// polls. Every chip carries its source state.
    private var advisories: [ES16Advisory] {
        var out: [ES16Advisory] = []

        if let env = corridor?.windGate, env.gated == true {
            // `peakGust` is nil on any snapshot, so this chip can never reach
            // its .live branch off cached weather. The two nil cases still read
            // differently, because "no sample landed" and "the sample is stale
            // and therefore withheld" are not the same statement.
            let hasGust = peakGust != nil
            out.append(ES16Advisory(
                id: "wind", label: "Wind gate",
                value: hasGust ? "\(Int(peakGust!)) mph · \(windVerdict.rawValue)"
                               : (isSnapshot ? "Cached · verdict withheld" : "No gust landed · unknown, not calm"),
                source: hasGust ? .live : (isSnapshot ? .cached : .notEvaluated),
                tint: windTint,
                tagOverride: hasGust ? nil : (isSnapshot ? nil : "No data")))
        }
        if let band = surfaceBand {
            // The band is a WeatherKit observation carried on the corridor legs.
            // Off a snapshot those legs are minutes old, so the chip declares
            // CACHED — the green LIVE tag is not available to stale weather.
            out.append(ES16Advisory(id: "surface", label: "Surface band",
                                    value: "\(band.capitalized)\(surfaceCode.map { " · code \($0)" } ?? "")",
                                    source: measuredSource, tint: ES16Ink.action))
        }
        // The rules engine owns BOTH the wording and the hour gate
        // (escorts.ts:3034). The client prints the server's own title so the two
        // can never disagree — a hardcoded "07–09" silently outlives a server
        // that moves its window.
        if let r = restrictions?.restrictions.first(where: { $0.type == "rush_hour" }) {
            out.append(ES16Advisory(id: "curfew", label: "Curfew window",
                                    value: r.title, source: .derived, tint: ES16Ink.warnInk(isDark)))
        } else if let r = restrictions?.restrictions.first(where: { $0.type == "time_restriction" }) {
            out.append(ES16Advisory(id: "night", label: "Night window",
                                    value: r.title, source: .derived, tint: ES16Ink.warnInk(isDark)))
        }
        if let r = restrictions?.restrictions.first(where: { $0.type == "weekend" }) {
            out.append(ES16Advisory(id: "weekend", label: "Weekend limit",
                                    value: r.title, source: .derived, tint: ES16Ink.warnInk(isDark)))
        }
        if let r = restrictions, r.isOversize == true, let w = r.weight {
            let fmt = NumberFormatter(); fmt.numberStyle = .decimal
            out.append(ES16Advisory(id: "osow",
                                    label: r.isSuperload == true ? "Superload" : "OS/OW route",
                                    value: "\(fmt.string(from: NSNumber(value: w)) ?? "\(Int(w))") lb · permit",
                                    source: measuredSource, tint: ES16Ink.accent(isDark)))
        }
        if let cov = bridge {
            let evaluated = cov.bridgesChecked > 0
            let hits = cov.structures ?? []
            let danger = hits.contains { ($0.classification ?? "") == "danger" }
            // Three outcomes, three faces. CLEAR is spoken ONLY when structures
            // were actually evaluated and none of them warned.
            let value: String
            let tint: Color
            if !evaluated {
                value = "Not evaluated · \(Int(cov.coverageRadiusMi)) mi radius"
                tint = ES16Ink.neutralDot
            } else if hits.isEmpty {
                value = "\(cov.bridgesChecked) checked · clear"
                tint = ES16Ink.successInk(isDark)
            } else {
                value = "\(cov.bridgesChecked) checked · \(hits.count) low"
                tint = danger ? Brand.danger : ES16Ink.warnInk(isDark)
            }
            out.append(ES16Advisory(
                id: "bridge", label: "Bridge coverage", value: value,
                source: evaluated ? measuredSource : .notEvaluated,
                tint: tint,
                tagOverride: isSnapshot && evaluated
                    ? nil : "\(cov.bridgesChecked) / \(cov.datasetRows)"))
        } else {
            // The read did NOT happen. The chip says which input was missing
            // instead of drawing a coverage figure nobody computed.
            out.append(ES16Advisory(id: "bridge", label: "Bridge coverage",
                                    value: bridgeGate ?? "Not read",
                                    source: .stub, tint: ES16Ink.neutralDot))
        }
        // STUBs — named, dashed, inert. No endpoint is invented for them.
        out.append(ES16Advisory(id: "school", label: "School zone", value: "No feed wired",
                                source: .stub, tint: ES16Ink.neutralDot))
        out.append(ES16Advisory(id: "gfi", label: "Grade · flood · ice", value: "3 advisories · no feed wired",
                                source: .stub, tint: ES16Ink.neutralDot))
        return out
    }
    /// Every chip whose value is a MEASUREMENT resolves its source through here,
    /// so a snapshot can never put the green LIVE tag on a stale reading.
    private var measuredSource: ES16Source { isSnapshot ? .cached : .live }

    private var windTint: Color {
        switch windVerdict {
        case .proceed: return ES16Ink.successInk(isDark)
        case .caution: return ES16Ink.warnInk(isDark)
        case .hold: return Brand.danger
        case .unknown, .notGated: return ES16Ink.neutralDot
        }
    }

    // MARK: Clearance log (ES-02 cross-link)

    private var clearanceSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("Clearance events · this corridor")
                    .font(ES16Type.label)
                    .foregroundStyle(ES16Ink.secondary(isDark))
                Spacer()
                Text("\(events.count) logged · open ES-02").font(ES16Type.body)
                    .foregroundStyle(ES16Ink.link(isDark))
            }
            VStack(spacing: 0) {
                if events.isEmpty {
                    Text("No clearance events logged on this corridor yet.")
                        .font(ES16Type.body).foregroundStyle(ES16Ink.secondary(isDark))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(Space.s3)
                } else {
                    ForEach(Array(events.prefix(3).enumerated()), id: \.element.id) { idx, ev in
                        if idx > 0 { Rectangle().fill(ES16Ink.hairline(isDark)).frame(height: 1) }
                        clearanceRow(ev)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: ES16Kit.card, style: .continuous).fill(ES16Ink.surface(isDark)))
            .overlay(RoundedRectangle(cornerRadius: ES16Kit.card, style: .continuous).strokeBorder(ES16Ink.hairline(isDark)))
        }
    }

    private func clearanceRow(_ ev: ES16ClearanceEvent) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Circle().fill(eventTint(ev)).frame(width: 9, height: 9).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(eventTitle(ev)) · \(ev.structureName ?? "Unnamed structure")")
                    .font(ES16Type.rowTitle)
                    .foregroundStyle(ES16Ink.primary(isDark)).lineLimit(1).minimumScaleFactor(0.85)
                Text(eventDetail(ev)).font(ES16Type.body)
                    .foregroundStyle(ES16Ink.secondary(isDark))
            }
            Spacer(minLength: 0)
            Text(shortClock(ev.occurredAt)).font(ES16Type.body)
                .foregroundStyle(ev.eventType == "clearance_check"
                                 ? ES16Ink.successInk(isDark) : ES16Ink.warnInk(isDark))
            Image(systemName: "chevron.right").font(ES16Type.chevron)
                .foregroundStyle(ES16Ink.tertiary(isDark)).padding(.top, 2)
        }
        .padding(Space.s3)
    }
    private func eventTint(_ ev: ES16ClearanceEvent) -> Color {
        switch ev.eventType {
        case "strike": return Brand.danger
        case "near_miss": return ES16Ink.warnDot
        default: return ES16Ink.successDot
        }
    }
    private func eventTitle(_ ev: ES16ClearanceEvent) -> String {
        switch ev.eventType {
        case "strike": return "Strike"
        case "near_miss": return "Near-miss"
        default: return "Check"
        }
    }
    /// Δ is computed only when BOTH figures are present — never half-filled.
    /// Both arrive as decimal STRINGS off the raw row; a string that will not
    /// parse is treated as absent rather than coerced to zero.
    private func eventDetail(_ ev: ES16ClearanceEvent) -> String {
        guard let posted = ev.postedClearanceFt.flatMap({ Double($0) }) else {
            return "No posted clearance recorded"
        }
        guard let measured = ev.measuredClearanceFt.flatMap({ Double($0) }) else {
            return "Posted \(feetInches(posted))"
        }
        let delta = posted - measured
        return "Posted \(feetInches(posted)) · pole \(feetInches(measured)) · Δ \(delta >= 0 ? "+" : "-")\(feetInches(abs(delta)))"
    }
    private func feetInches(_ ft: Double) -> String {
        let whole = Int(ft)
        return "\(whole)′\(Int(((ft - Double(whole)) * 12).rounded()))″"
    }
    private func shortClock(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    // MARK: Lifecycle ladder + ESANG + CTA

    /// §5/§8 — THE ONE EUSOLINE ON THIS SCREEN. It is the assignment's own
    /// timeline: the `updateTripStatus` enum (escorts.ts:2849-2850), whose two
    /// endpoints are the first and last members of that schema, with the NOW
    /// marker on the stage `getActiveTrip` (escorts.ts:2787) reports. Both ends
    /// are sourced from the same procedure the CTA beneath advances, so nothing
    /// about the spine is a client invention. The corridor progress bar in the
    /// hero leg is a plain action-tint track, NOT a second EusoLine.
    private var lifecycleLadder: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let n = max(Self.statusLadder.count - 1, 1)
                let idx = Self.statusLadder.firstIndex(of: trip?.assignmentStatus ?? "") ?? 0
                let reached = geo.size.width * CGFloat(idx) / CGFloat(n)
                ZStack(alignment: .leading) {
                    Capsule().fill(ES16Ink.track(isDark)).frame(height: 6)
                    Capsule().fill(ES16Grad.eusoLine).frame(width: reached, height: 6)
                    Rectangle().fill(ES16Ink.primary(isDark))
                        .frame(width: 2, height: 14)
                        .offset(x: min(max(reached - 1, 0), geo.size.width - 2), y: -4)
                }
            }
            .frame(height: 6)

            HStack(spacing: 0) {
                ForEach(Self.statusLadder, id: \.self) { st in
                    let current = st == (trip?.assignmentStatus ?? "")
                    Text(st.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(current ? ES16Type.label : ES16Type.body)
                        .foregroundStyle(current ? ES16Ink.primary(isDark) : ES16Ink.tertiary(isDark))
                        .frame(maxWidth: .infinity)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }

            // §9 — the open half of the chain, printed on the face rather than
            // left to the reader. updateTripStatus (escorts.ts:2849-2867) updates
            // the row at :2863 and completes the convoy at :2864-2866, and does
            // nothing else: no WebSocket emit, no recordAuditEvent call (it is
            // imported at escorts.ts:17 and used at ten other sites but not this
            // one), and no blockchainAuditTrail insert (the identifier appears
            // zero times in all 4,745 lines of escorts.ts).
            Text("Status write persists · no broadcast, no audit row, no chain row · one-sided")
                .font(ES16Type.body)
                .foregroundStyle(ES16Ink.tertiary(isDark))
        }
    }

    /// §8 — ESANG counsel as ONE soft region: recommendation 15/600, reason
    /// 12/500, source + proposal boundary 12/500, chevron 14/600 right. The
    /// gradient rail and the gradient wordmark of run-1 are both gone; the orb
    /// is the mark, and `esangOrb` belongs to the counsel dot alone.
    private var esangRow: some View {
        HStack(spacing: Space.s3) {
            Circle().fill(ES16Grad.esangOrb).frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(esangHeadline).font(ES16Type.rowTitle)
                    .foregroundStyle(ES16Ink.primary(isDark)).lineLimit(2)
                Text(esangDetail).font(ES16Type.body)
                    .foregroundStyle(ES16Ink.secondary(isDark)).lineLimit(2)
                Text("From the corridor wind envelope · proposal — you decide")
                    .font(ES16Type.body).foregroundStyle(ES16Ink.secondary(isDark))
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(ES16Type.chevron)
                .foregroundStyle(ES16Ink.secondary(isDark))
        }
        .padding(Space.s3)
        .background(RoundedRectangle(cornerRadius: ES16Kit.card, style: .continuous)
            .fill(isDark ? Color(hex: 0x2A2038) : Color(hex: 0xE8DDFC)))
    }
    private var esangHeadline: String {
        guard let gust = peakGust, let idx = peakGustLegIndex,
              let legs = corridor?.legs, idx <= legs.count else {
            return "Wind gate has no live verdict right now"
        }
        return "Gust hits \(Int(gust)) mph at \(legs[idx - 1].destination ?? "the next leg")"
    }
    private var esangDetail: String {
        guard let gust = peakGust else {
            return "No WeatherKit gust landed — treat the corridor as unjudged, not calm."
        }
        let headroom = Int(nogoThreshold - gust)
        guard headroom > 0 else { return "At or past the hold threshold — stage before the next span." }
        return "\(headroom) mph under hold. Stage at the next node and re-read before the span."
    }

    private var ctaBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: Space.s2) {
                // §8 command dock: 52 pt tall, rx 12. §1 defect 3 — the primary
                // command is a FLAT #0B66E5 fill, never a gradient.
                Button { Task { await advance() } } label: {
                    Text(advanceLabel).font(ES16Type.ctaLabel)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: ES16Kit.cta, style: .continuous)
                            .fill(nextStatus == nil || statusInFlight
                                  ? ES16Ink.tertiary(isDark) : ES16Ink.action))
                }
                .buttonStyle(.plain).disabled(nextStatus == nil || statusInFlight)

                Button { } label: {
                    Text("Height pole").font(ES16Type.ctaLabel)
                        .foregroundStyle(ES16Ink.primary(isDark))
                        .frame(width: 140, height: 52)
                        .background(RoundedRectangle(cornerRadius: ES16Kit.cta, style: .continuous)
                            .fill(ES16Ink.surface(isDark)))
                        .overlay(RoundedRectangle(cornerRadius: ES16Kit.cta, style: .continuous)
                            .strokeBorder(ES16Ink.ctaStroke(isDark), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    /// Purely a client affordance — the server accepts any enum value in any
    /// order (escorts.ts:2849 has no transition guard). Named, not hidden.
    private var nextStatus: String? {
        switch trip?.assignmentStatus {
        case "accepted": return "en_route"
        case "en_route": return "on_site"
        case "on_site": return "escorting"
        case "escorting": return "on_site"
        default: return nil
        }
    }
    private var advanceLabel: String {
        guard let next = nextStatus else { return "No next status" }
        return "Advance to \(next.replacingOccurrences(of: "_", with: " "))"
    }

    // MARK: Derived spine values

    private var activeLeg: ES16Leg? { corridor?.legs.first { ($0.status ?? "") == "active" } }
    private func legIndex(_ leg: ES16Leg) -> Int { ((corridor?.legs.firstIndex(of: leg)) ?? 0) + 1 }
    /// TRUTH LAW §9 — the `milesRemainingOnActiveLeg` property of run-1 is
    /// DELETED, not merely unused. It multiplied an EVEN-DIVISION leg length
    /// (escorts.ts:3943, assigned identically to every leg at escorts.ts:4010) by
    /// a LIFECYCLE-STATUS constant (escorts.ts:232-247) and presented the product
    /// as a distance still to drive. No procedure supplies a distance-to-next-
    /// waypoint, so the figure and everything built on it are withdrawn.
    ///
    /// Coverage is stated as the LIFECYCLE STAGE it actually is. `corridorCoverage`
    /// is `coverageForStatus` (escorts.ts:3933 → :232-247), a status→number lookup
    /// with no positional input whatsoever; the leg counts beside it come from the
    /// server's own `legsCompleted` / `legsTotal` (escorts.ts:4017, :4181), which
    /// are themselves derived from that same constant at escorts.ts:3992-3994.
    /// Printing the basis is the whole point of the line.
    private var coverageBasisLine: String {
        let pct = Int(((corridor?.corridorCoverage ?? 0) * 100).rounded())
        let done = corridor?.legsCompleted ?? 0
        let total = corridor?.legsTotal ?? (corridor?.legs.count ?? 0)
        return "\(done) of \(total) legs · \(pct)% by lifecycle stage, not a position fix"
    }

    // MARK: Data — READ_CACHED(60s)

    private func load(forceNetwork: Bool = false) async {
        loading = true
        defer { loading = false }

        if !forceNetwork,
           let snap = EscortOfflineCache.load(ES16Snapshot.self, key: cacheKey, ttl: cacheTTL) {
            apply(snap.value)
            cacheAge = snap.age
        }

        do {
            // getActiveTrip returns null when the escort holds no active
            // assignment — an honest empty, decoded as an optional, not an error.
            let fetchedTrip: ES16Trip? = try await EusoTripAPI.shared.query(
                "escorts.getActiveTrip", input: ES16EmptyInput())
            guard let t = fetchedTrip else {
                trip = nil; cacheAge = nil; errorMessage = nil; return
            }
            trip = t

            async let corr: ES16Corridor? = try? await EusoTripAPI.shared.query(
                "escorts.getCorridor", input: ES16IdInput(id: String(t.assignmentId)))
            async let restr: ES16Restrictions? = try? await EusoTripAPI.shared.query(
                "escorts.getRouteRestrictions", input: ES16EmptyInput())
            async let prox: ES16Proximity? = try? await EusoTripAPI.shared.query(
                "escorts.getConvoyProximity", input: ES16EmptyInput())

            let fetchedCorridor = await corr
            let fetchedRestrictions = await restr
            let fetchedProximity = await prox
            let fetchedEvents: [ES16ClearanceEvent] = (try? await EusoTripAPI.shared.query(
                "escorts.getClearanceEventHistory",
                input: ES16ClearanceInput(assignmentId: t.assignmentId, limit: 10))) ?? []

            // BRIDGE COVERAGE — the read runs only once the position fix that
            // getConvoyProximity just returned is in hand, because that fix is
            // one of its three required inputs.
            let cov = await readBridgeCoverage(
                assignmentId: t.assignmentId,
                fix: fetchedProximity?.escortLocation
            )

            corridor = fetchedCorridor
            restrictions = fetchedRestrictions
            proximity = fetchedProximity
            events = fetchedEvents
            bridge = cov.coverage
            bridgeGate = cov.gate
            cacheAge = nil
            errorMessage = nil

            EscortOfflineCache.store(ES16Snapshot(trip: t, corridor: fetchedCorridor,
                                                  restrictions: fetchedRestrictions,
                                                  proximity: fetchedProximity,
                                                  events: fetchedEvents,
                                                  bridge: cov.coverage, bridgeGate: cov.gate),
                                     key: cacheKey)
        } catch {
            if cacheAge == nil {
                errorMessage = (error as? EusoTripAPIError)?.errorDescription
                    ?? "Couldn't read the corridor. Pull to retry."
            } else {
                errorMessage = "Showing the last good corridor — the live read failed."
            }
        }
    }

    /// `escorts.getLowClearanceProximity` (escorts.ts:4335) takes five inputs and
    /// three of them are things this screen must be GIVEN, not things it may
    /// assume: the load, a real position fix, and an ARMED pole height (the
    /// input floors poleHeightFt at 8, and a guessed height returns BAD_REQUEST
    /// that decodes into an empty structure list — a permanent, confident
    /// false all-clear on a bridge-strike-prevention chip). When an input is
    /// missing this returns the reason and no coverage, and the chip prints it.
    private func readBridgeCoverage(assignmentId: Int, fix: ES16Fix?)
        async -> (coverage: ES16BridgeCoverage?, gate: String?) {
        guard let coordinate = LatLongParser.validatedCoordinate(
            latitude: fix?.lat,
            longitude: fix?.lng
        ) else {
            return (nil, "No position fix")
        }
        let pole: ES16PoleConfig
        do {
            pole = try await EusoTripAPI.shared.query(
                "escorts.getPoleConfig", input: ES16PoleInput(assignmentId: assignmentId))
        } catch {
            return (nil, "Pole status unavailable")
        }
        guard pole.armed == true, let height = pole.poleHeightFt, height >= 8 else {
            return (nil, "Pole not armed · open ES-02")
        }
        do {
            let coverage: ES16BridgeCoverage = try await EusoTripAPI.shared.query(
                "escorts.getLowClearanceProximity",
                input: ES16ProximityInput(
                    assignmentId: assignmentId,
                    lat: coordinate.latitude,
                    lng: coordinate.longitude,
                    poleHeightFt: height,
                    radiusMi: 1.5
                ))
            return (coverage, nil)
        } catch {
            return (nil, "Coverage read failed")
        }
    }

    private func apply(_ snap: ES16Snapshot) {
        trip = snap.trip
        corridor = snap.corridor
        restrictions = snap.restrictions
        proximity = snap.proximity
        events = snap.events
        bridge = snap.bridge
        bridgeGate = snap.bridgeGate
    }

    /// ONLINE_ONLY — there is no escort outbox to queue into.
    private func advance() async {
        guard let t = trip, let next = nextStatus, !statusInFlight else { return }
        statusInFlight = true
        defer { statusInFlight = false }
        do {
            let receipt: ES16StatusReceipt = try await EusoTripAPI.shared.mutation(
                "escorts.updateTripStatus",
                input: ES16StatusInput(assignmentId: t.assignmentId, status: next))
            trip = ES16Trip(assignmentId: t.assignmentId, assignmentStatus: receipt.newStatus,
                            position: t.position, startedAt: t.startedAt,
                            load: t.load, convoy: t.convoy)
            errorMessage = nil
            await load(forceNetwork: true)
        } catch {
            errorMessage = (error as? EusoTripAPIError)?.errorDescription
                ?? "Status changes need a connection — escort writes are not queued yet."
        }
    }
}

// MARK: - Glyph

// `ES16Triangle` is DELETED, not left orphaned. It existed solely to draw the
// 9.5px gust pennant on the wind ruler; that marker is now the same 2×14
// ink-primary needle idiom the EusoLine NOW rule uses, so the shape has no
// remaining caller. (canon 2026-08-23.1 rework, 2026-08-26)

// MARK: - Registered surface wrapper

struct EscortActiveTripConsoleScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortActiveTripConsole()
        } nav: {
            // The nav is rendered from the escort role enum, never by hand:
            // EscortNavController.swift — tab enum :32, NavSlots :77-85, orb
            // labels :63, dispatcher :88-106. The canonical escort bar is
            // HOME · ASSIGNMENTS · [ESang orb] · CORRIDOR · ME. There is no
            // TRIP·COMMS·PERMIT·ME bar; "trip" survives only as a legacy label
            // alias that resolves to .assignments (EscortNavController.swift:58).
            //
            // `isCurrent` inks ASSIGNMENTS because the active trip IS the
            // assignment the escort is holding — EscortNavRoute.Destination
            // .assignments = "601" (EscortNavController.swift:44), the surface
            // that boards the active assignment. CORRIDOR ("602") is the
            // formation/corridor destination and belongs to ES-11, not here.
            BottomNav(
                leading: EscortNavRoute.leading(current: .assignments),
                trailing: EscortNavRoute.trailing(current: .assignments),
                orbState: .idle
            )
        }
    }
}

#Preview("ES-16 · Active Trip Console · Dark") {
    EscortActiveTripConsoleScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("ES-16 · Active Trip Console · Light") {
    EscortActiveTripConsoleScreen(theme: Theme.light).preferredColorScheme(.light)
}
