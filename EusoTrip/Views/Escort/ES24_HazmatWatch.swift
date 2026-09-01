//
//  ES24_HazmatWatch.swift
//  EusoTrip — Escort · Hazmat Watch (ES-24).
//
//  Built from the ES-24 design-authority SVG pair
//  ("07 Escort/{Light,Dark}-SVG/ES-24 Hazmat Watch.svg").
//
//  ARCHETYPE — COMPLIANCE instrument panel · CADENCE STACK. The panel is
//  ordered by HOW FAST EACH NUMBER ROTS, not by topic: ambient sample,
//  four-point array, plume geometry, scheduled-check clock, ERG card.
//  Every organ is a reading welded to its own age. The signature organ is
//  the DECAY TRACK — a 0-to-40-minute age ruler with the 30-minute
//  statutory staleness boundary printed on its face — and the meta dot is
//  AMBER BY CONSTRUCTION, because nothing on this surface is sampled by a
//  machine. Anti-clone: NOT ES-02 Height Pole (an arc gauge over a street
//  map, answering an instantaneous vertical question with no time axis at
//  all); NOT ES-06 Vehicle Check (a 12-cell pass/fail BentoGrid resolved
//  once before the wheels turn). This screen has no arc, no gauge, no map
//  tiles, no route line, no pass/fail cells — it has magnitudes and ages.
//
//  CANON 2026-08-23.1 RE-SKIN (2026-08-26) — token + type-scale pass over
//  the run-1 face. Nothing about the wiring, the parsing or the honest
//  unavailable states below changed; what changed is how they are drawn.
//    · §3 TYPE SCALE — every call site is now one of 10 · 12 · 14 · 15 ·
//      17 · 28 · 34. The retired sizes (4 · 6 · 6.5 · 7 · 7.5 · 8 · 9 ·
//      9.5 · 11 · 11.5 · 13 · 26 · 38) are gone. 10 belongs to bottom-nav
//      captions only, which `BottomNav` owns; this file's floor is 12.
//    · §3 TRACKING — every positive `.tracking()` is deleted. The only
//      surviving optical tracking is -0.4 on the 28-pt screen title and
//      -0.6 on the 34-pt hero number.
//    · §1 EYEBROW — the 9-pt all-caps gradient eyebrow chip is removed
//      outright; the orientation row is sentence case at 12.
//    · §5 GRADIENTS — `LinearGradient.diagonal` / `.primary` and the
//      iridescent hairline are gone from this surface. `eusoLine` is
//      referenced EXACTLY ONCE, on the scheduled-check ring, which is the
//      one temporal spine this screen is about. `esangOrb` / `orbSpec`
//      belong to the nav orb and are not drawn in this file.
//    · §4 PALETTE — ES24Ink pins the §4 token pairs locally rather than
//      reaching across into the band-wide single-writer palette.
//    · §8 DOCK — the primary command is a FLAT #0B66E5 fill at 52 pt,
//      rx 12, with a white 15/600 label. The shared `CTAButton` is
//      gradient-backed at a 17-pt label, so it is deliberately not used.
//    · §7 NAV — BottomNav is bound to the shipped escort enum
//      HOME · ASSIGNMENTS · [ESang orb] · CORRIDOR · ME
//      (EscortNavController.swift:77-85; orb :63) with ASSIGNMENTS
//      current, because the hazmat watch is a pushed route under it.
//
//  DIVERGENCE FROM THE SVG TWIN, stated rather than hidden: the canon SVG
//  pair withdraws the ambient-gas organ outright, because a wireframe must
//  not depict a reading store the tree does not have. This view keeps the
//  organ because at runtime it renders only what the check-in log actually
//  contains — `ES24NoteParser` returns an empty set when no line carries a
//  reading, and every empty path here already prints an unavailable state
//  rather than a zero. The organ paints when there is something to paint
//  and says "no reading logged" when there is not.
//
//  WIRING (every anchor opened at the line first-hand this fire)
//    EXISTS hazmatEscort.getStatus        hazmatEscort.ts:40
//           → {active:null} | {active:{assignmentId,loadId,position,status,
//             startedAt,nextCheckInAt,notes,load{...}}}
//    EXISTS CHECKIN_INTERVAL_MINUTES = 30 hazmatEscort.ts:30 — the cadence is
//           SERVER-OWNED (49 CFR §177.817, cited at :29) but it is NOT ON THE
//           WIRE. getStatus returns only nextCheckInAt, computed server-side as
//           row.updatedAt + 30 min (hazmatEscort.ts:95-98). The staleness
//           boundary on this screen is therefore PINNED to a named client
//           mirror of that constant and is NEVER derived from a diffed pair of
//           timestamps: escortAssignments.updatedAt is written by procedures
//           that append NO sample line — escorts.updateJobStatus
//           (escorts.ts:1199) sets it on a bare status write — so
//           (nextCheckInAt − lastSample) drifts upward and would grade a rotted
//           reading LIVE with a fabricated statutory number beside it.
//    STUB   explicit interval on the wire — hazmatEscort.getStatus should
//           return checkInIntervalMinutes: CHECKIN_INTERVAL_MINUTES so the
//           client never has to mirror a statutory figure at all.
//    EXISTS hazmatEscort.checkIn  (MUT)   hazmatEscort.ts:130   ONLINE_ONLY
//           BRIEF CORRECTION, verified: the check-in procedure is NOT at :34.
//           Line 34 is `export const hazmatEscortRouter = router({`;
//           getStatus opens at :40 and checkIn at :130. File is 200 lines.
//    EXISTS erg.searchByUN                erg.ts:67
//    EXISTS erg.getEmergencyContacts      erg.ts:237  (CHEMTREC is READ, not typed)
//    EXISTS emergencyProtocols
//             .getHazmatSpillProtocol     emergencyProtocols.ts:693
//    EXISTS hazmat.getSecurityPlanStatus  hazmat.ts:1101   (TSA 172.800 · EVO-1035)
//    EXISTS hazmat.checkProximity         hazmat.ts:1321   (13-row zone table)
//    EXISTS weather.getCurrent            weather.ts:1993  (only live wind bearing)
//    EXISTS nrc.getDosimetryLog           nrc.ts:649 — plain protectedProcedure,
//           NOT the hazmat gate, so this role CAN read a dose log. This screen
//           calls it whenever the load is class 7 and paints the real cumulative
//           mrem + severity. CORRECTION ON THE RECORD: nrc.ts's own header
//           comment (:36-41) claims the whole router is hazmat-gated. Only three
//           procedures are — recordLicense :303, recordTransfer :492,
//           submitDosimetryReading :733. Verified by opening each pin; the code
//           is cited here, not the comment.
//    EXISTS-BUT-WRITE-ROLE-BLOCKED nrc.submitDosimetryReading nrc.ts:733 — gated
//           by `hazmatProcedure` (nrc.ts:66-76) which omits ROLES.ESCORT
//           (_core/trpc.ts:23). So the escort may READ a dose and may not LOG
//           one. Filed gap: add ROLES.ESCORT to the list at nrc.ts:66.
//    TYPE SEAM, carried deliberately: getDosimetryLog takes loadId as a STRING
//           (z.string().min(1) · nrc.ts:650) while hazmatEscort.getStatus returns
//           loadId as a NUMBER (hazmatEscort.ts:103). The client stringifies on
//           purpose rather than letting a silent decode failure look like an
//           empty dose log.
//    STUB   live gas telemetry — no producer exists anywhere in the tree.
//           Proposed: hazmatEscort.streamAmbient({assignmentId}) →
//           {detectorId, analyte, ppm, sampledAt, source: sensor|manual}.
//    STUB   typed reading store — readings land as free text in
//           escortAssignments.notes. Proposed hazmat_escort_readings table +
//           hazmatEscort.logReading({assignmentId,detectorId,analyte,value,
//           unit,lat,lon}).
//    STUB   detector registry — hazmatEscort.listDetectors({assignmentId}).
//    STUB   check-in photo evidence — checkIn's input (hazmatEscort.ts:132-137)
//           accepts assignmentId/lat/lon/note ONLY. Proposed photoDocumentId?.
//    STUB   school / hospital / residential receptors — no dataset. Proposed
//           hazmat.getSensitiveReceptors({lat,lng,radiusKm}).
//    STUB   condensation advisory; per-class cadence table.
//    STUB   exposure thresholds — no procedure in the tree serves a PEL/STEL/
//           IDLH figure, so the ruler is a CLIENT-SIDE table and is labelled
//           "THRESHOLDS · LOCAL TABLE" on its face. Proposed
//           hazmat.getExposureLimits({unNumber}) →
//           {analyte, pelPpm, stelPpm, idlhPpm, source, revisedAt}.
//    STUB   downwind verdict — getStatus returns NO coordinate for the tank and
//           nothing anywhere supplies the escort's bearing to it, so "YOU ARE
//           DOWNWIND OF THE TANK" is not a renderable verdict. This screen
//           prints only PLUME RUNS <compass>, which is arithmetic on the wind
//           bearing alone. Proposed hazmatEscort.getStatus →
//           load.tankLat/tankLon (or hazmatEscort.getTankPosition) so a real
//           downwind verdict could be computed against the escort's own fix.
//    STUB   position-based wind — weather.getCurrent (weather.ts:1993) accepts
//           {city,state} ONLY, and weather.byLatLon (weather.ts:1545) carries
//           wind SPEED with no direction, so there is no lat/lon wind BEARING
//           anywhere in the tree. Proposed
//           weather.getCurrentByPosition({lat,lon}) → {...,windDirection}.
//           Until it exists the rose names the station city it actually queried.
//
//  OFFLINE (§W) — mutations ONLINE_ONLY (escort outbox not yet ported,
//  PLANNED per Encyclopedia v2). A queue badge is NEVER drawn. Reads split
//  DELIBERATELY: the assignment header, the check-in schedule, the parsed
//  samples, the ERG card, the contacts, the spill protocol and the
//  security-plan verdict are READ_CACHED(90s) via EscortOfflineCache — safe
//  because every sample carries its own absolute ISO stamp, so age is
//  computed against the wall clock and a replayed snapshot cannot make a
//  reading look younger than it is. The wind observation and the zone
//  proximity are NEVER CACHED: both are position-dependent, and a cached
//  bearing on a moved vehicle would point the escort into the plume. On a
//  cached paint those two blank to UNAVAILABLE rather than holding their
//  last picture.
//
//  STALE vs LIVE — the core honesty requirement. A live reading is a solid
//  coloured numeral with a lit verdict. A stale reading (past the interval)
//  is a BRACKETED numeral over a diagonal hatch, its verdict cell shows an
//  em dash and NOT LIVE, its row rule turns dashed and its age flips to
//  danger. The two states are distinguishable at arm's length.
//
//  RBAC — hazmatEscort.* is protectedProcedure with per-row ownership
//  (hazmatEscort.ts:161-163); erg.* / hazmat.* are isolatedProcedure aliased
//  as protectedProcedure (erg.ts:9, hazmat.ts:13); weather.getCurrent is
//  public. No loads.rate, no shipper margin, no other escort's position or
//  dose reaches this surface.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI
import Combine
import CoreLocation

// MARK: - Wire projections (screen-local, private — mirror the on-disk returns)

private struct ES24EmptyInput: Encodable {}
private struct ES24UNInput: Encodable { let unNumber: String }
private struct ES24SpillInput: Encodable { let hazmatClass: String }
private struct ES24SecurityInput: Encodable { let hazmatClasses: [String] }
private struct ES24WeatherInput: Encodable { let city: String; let state: String }
private struct ES24ProximityInput: Encodable {
    let lat: Double; let lng: Double
    let hazmatClass: String; let alertRadiusMiles: Double
}
private struct ES24CheckInInput: Encodable {
    let assignmentId: Int; let lat: Double; let lon: Double; let note: String?
}

/// hazmatEscort.getStatus · hazmatEscort.ts:100-123
private struct ES24Load: Codable, Equatable {
    let id: Int?
    let loadNumber: String?
    let originCity: String?
    let originState: String?
    let destCity: String?
    let destState: String?
    let hazmatClass: String?
    let unNumber: String?
    let cargoType: String?
}

private struct ES24Active: Codable, Equatable {
    let assignmentId: Int
    let loadId: Int?
    let position: String?
    let status: String?
    let startedAt: String?
    let nextCheckInAt: String?
    let notes: String?
    let load: ES24Load?
}

private struct ES24Status: Codable, Equatable { let active: ES24Active? }

/// hazmatEscort.checkIn · hazmatEscort.ts:193-198
private struct ES24CheckInReceipt: Decodable {
    let ok: Bool?
    let assignmentId: Int?
    let checkedInAt: String?
    let nextCheckInAt: String?
}

/// erg.searchByUN · erg.ts:148-188
private struct ES24ERGGuideFull: Codable, Equatable {
    let title: String?
    let isolationDistanceMeters: Double?
    let isolationDistanceFeet: Double?
    let fireIsolationMeters: Double?
    let fireIsolationFeet: Double?
    let protectiveClothing: String?
    let evacuationNotes: String?
}

private struct ES24ProtectiveLeg: Codable, Equatable {
    let isolateMeters: Double?
    let protectKm: Double?
}
private struct ES24ProtectiveSpill: Codable, Equatable {
    let day: ES24ProtectiveLeg?
    let night: ES24ProtectiveLeg?
}
/// ergDatabase.ts:31 ProtectiveDistance
private struct ES24ProtectiveDistance: Codable, Equatable {
    let unNumber: String?
    let name: String?
    let smallSpill: ES24ProtectiveSpill?
    let largeSpill: ES24ProtectiveSpill?
    let refTable3: Bool?
}

private struct ES24ERG: Codable, Equatable {
    let found: Bool?
    let unNumber: String?
    let name: String?
    let guideNumber: Int?
    let hazardClass: String?
    let placard: String?
    let isTIH: Bool?
    let guideFull: ES24ERGGuideFull?
    let protectiveDistance: ES24ProtectiveDistance?
}

/// erg.getEmergencyContacts · erg.ts:237-243
private struct ES24Contact: Codable, Equatable {
    let name: String?; let phone: String?; let description: String?; let international: String?
}
private struct ES24Contacts: Codable, Equatable {
    let chemtrec: ES24Contact?
    let national: ES24Contact?
    let poison: ES24Contact?
    let emergency: ES24Contact?
}

/// emergencyProtocols.getHazmatSpillProtocol · emergencyProtocols.ts:702-719
private struct ES24SpillProtocol: Codable, Equatable {
    let className: String?
    let immediateActions: [String]?
    let evacuationRadius: String?
    let ppe: [String]?
    let ergGuideNumbers: [String]?
}

/// hazmat.getSecurityPlanStatus · hazmat.ts:1234-1246
private struct ES24SecurityTrigger: Codable, Equatable, Identifiable {
    let id: String
    let category: String?
    let threshold: String?
}
private struct ES24SecurityPlan: Codable, Equatable {
    let regulation: String?
    let requiresSecurityPlan: Bool?
    let triggeredBy: [ES24SecurityTrigger]?
}

/// weather.getCurrent · weather.ts:2011-2023
private struct ES24Weather: Codable, Equatable {
    let location: String?
    let windSpeed: Int?
    let windDirection: String?     // compass string via degToCompass · weather.ts:2017
    let condition: String?
    let updatedAt: String?
}

/// hazmat.checkProximity · hazmat.ts:1388-1398
private struct ES24ZoneAlert: Codable, Equatable, Identifiable {
    let zoneId: String
    let zoneName: String?
    let distanceMiles: Double?
    let severity: String?
    let alternateRoute: String?
    let alert: String?
    var id: String { zoneId }
}
private struct ES24Proximity: Codable, Equatable {
    let alerts: [ES24ZoneAlert]?
    let inRestrictedZone: Bool?
    let approachingZone: Bool?
}

/// nrc.getDosimetryLog · nrc.ts:649 (DosimetryLogDTO, nrc.ts:652-657).
/// Readable by this role — the gate is plain protectedProcedure. Only the
/// WRITE (submitDosimetryReading, nrc.ts:733) is hazmat-gated.
private struct ES24DoseReading: Codable, Equatable, Identifiable {
    let readingMrem: Double?
    let kind: String?
    let readingTime: String?
    var id: String { "\(readingTime ?? "—")-\(readingMrem ?? -1)" }
}
private struct ES24DosimetryLog: Codable, Equatable {
    let loadId: String?
    let readings: [ES24DoseReading]?
    let cumulativeMrem: Double?
    let severity: String?
}
/// loadId is a STRING here (nrc.ts:650) while getStatus hands back a NUMBER
/// (hazmatEscort.ts:103). The conversion is explicit so the seam is visible.
private struct ES24DoseInput: Encodable { let loadId: String }

// MARK: - Freshness

/// A reading's state relative to the SERVER-OWNED interval
/// (`CHECKIN_INTERVAL_MINUTES` · hazmatEscort.ts:30 · 49 CFR §177.817).
/// This is a type, not a colour decision made at the call site, because an
/// instrument panel that cannot show a reading is stale is a lie.
private enum ES24Freshness: Equatable {
    case live(ageMinutes: Int)
    case stale(ageMinutes: Int)
    case unavailable

    /// THE STALENESS BOUNDARY. Pinned to the server constant
    /// CHECKIN_INTERVAL_MINUTES = 30 (hazmatEscort.ts:30, carrying the
    /// 49 CFR §177.817 citation at :29). The server does NOT put the interval
    /// on the wire — getStatus returns only nextCheckInAt — so this named
    /// client constant mirrors it.
    ///
    /// It is deliberately a CONSTANT and never a diff of two timestamps.
    /// nextCheckInAt is computed as escortAssignments.updatedAt + 30 min
    /// (hazmatEscort.ts:95-98), and that column is written by procedures that
    /// append no sample line — escorts.updateJobStatus (escorts.ts:1199) is one
    /// — so a status write slides nextCheckInAt away from the last sample and
    /// (nextCheckInAt − lastSample) grows without limit. Grading against that
    /// difference would light a forty-minute-old H₂S reading as LIVE and print
    /// a statutory boundary that no regulation contains.
    static let statutoryIntervalMinutes = 30

    /// A caller may only ever TIGHTEN the boundary, never widen it, so no call
    /// site can promote a sample older than the statutory interval to `.live`.
    static func of(ageMinutes: Int?,
                   intervalMinutes: Int = ES24Freshness.statutoryIntervalMinutes) -> ES24Freshness {
        guard let a = ageMinutes else { return .unavailable }
        let boundary = max(1, min(intervalMinutes, statutoryIntervalMinutes))
        return a >= boundary ? .stale(ageMinutes: a) : .live(ageMinutes: a)
    }

    var isLive: Bool { if case .live = self { return true }; return false }
    var ageMinutes: Int? {
        switch self {
        case .live(let a), .stale(let a): return a
        case .unavailable: return nil
        }
    }
    var label: String {
        switch self {
        case .live(let a), .stale(let a): return "\(a) min"
        case .unavailable: return "—"
        }
    }
}

// MARK: - Sample parsing over the untyped notes column

/// A single hand-logged ambient reading recovered from `escortAssignments.notes`.
///
/// There is no typed store for these (STUB, filed above). `hazmatEscort.checkIn`
/// appends one line per check-in in the exact shape written at
/// hazmatEscort.ts:166-171:
///
///     [2026-08-10T14:20:11.000Z] lat=31.42283 lon=-103.49318 — <free note>
///
/// This screen reads the ISO stamp — which is REAL and server-written — and
/// then looks inside the free-note half for a reading using the client-side
/// convention it also writes: `POINT=<label>; PPM=<value>`. When a line carries
/// no parsable reading the row is NOT invented: the panel reports the check-in
/// with NO READING LOGGED. The ISO stamp is absolute, which is why a cached
/// snapshot can never make one of these look younger than it is.
private struct ES24Sample: Identifiable, Equatable {
    let id: String
    let point: String
    let ppm: Double?
    let loggedAt: Date

    func ageMinutes(now: Date) -> Int { max(0, Int(now.timeIntervalSince(loggedAt) / 60)) }
}

private enum ES24NoteParser {

    /// The line shape the server writes. We anchor on the bracketed ISO stamp.
    static func samples(from notes: String?) -> [ES24Sample] {
        guard let notes, !notes.isEmpty else { return [] }
        var out: [ES24Sample] = []
        for (idx, raw) in notes.split(separator: "\n").enumerated() {
            let line = String(raw)
            guard let close = line.firstIndex(of: "]"),
                  line.first == "[" else { continue }
            let stampText = String(line[line.index(after: line.startIndex)..<close])
            guard let stamp = parseISO(stampText) else { continue }
            let tail = String(line[line.index(after: close)...])
            out.append(ES24Sample(id: "\(idx)-\(stampText)",
                                  point: point(in: tail) ?? "Check-in",
                                  ppm: ppm(in: tail),
                                  loggedAt: stamp))
        }
        // newest first
        return out.sorted { $0.loggedAt > $1.loggedAt }
    }

    /// `POINT=<label>` — the convention this screen writes and reads. No match
    /// means we do not know where the sample was taken, and we say so.
    /// Returned display-ready. `value(for:)` matches the key case-insensitively
    /// and hands back an upper-cased token; canon §3 forbids shouting on the
    /// face, so the label is capitalised here rather than at each call site.
    static func point(in s: String) -> String? {
        value(for: "POINT", in: s)?.capitalized
    }

    /// `PPM=<value>`, with a tolerant fallback for "<number> ppm" typed by hand.
    static func ppm(in s: String) -> Double? {
        if let v = value(for: "PPM", in: s), let d = Double(v) { return d }
        let lower = s.lowercased()
        guard let r = lower.range(of: "ppm") else { return nil }
        let head = lower[lower.startIndex..<r.lowerBound]
        let digits = head.reversed().prefix { $0.isNumber || $0 == "." || $0 == " " }
        let token = String(digits.reversed()).trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : Double(token)
    }

    private static func value(for key: String, in s: String) -> String? {
        let upper = s.uppercased()
        guard let r = upper.range(of: "\(key)=") else { return nil }
        let rest = upper[r.upperBound...]
        let token = rest.prefix { $0 != ";" && $0 != "," && $0 != "\n" }
        let t = token.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    static func parseISO(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
    }
}

// MARK: - Analyte thresholds (CLIENT-SIDE TABLE — labelled as such on the face)

/// Exposure bands are NOT served by any procedure in the tree, so this table is
/// local and the panel prints "THRESHOLDS · LOCAL TABLE" beside it rather than
/// letting a reader assume the server judged the number.
private struct ES24Bands: Equatable {
    let analyte: String
    let pel: Double
    let stel: Double
    let idlh: Double

    static func forUN(_ un: String?) -> ES24Bands? {
        switch un {
        case "1053": return .init(analyte: "H₂S",  pel: 10,  stel: 15,  idlh: 100)
        case "1017": return .init(analyte: "Cl₂",  pel: 1,   stel: 1,   idlh: 10)
        case "1005": return .init(analyte: "NH₃",  pel: 50,  stel: 35,  idlh: 300)
        case "1076": return .init(analyte: "COCl₂", pel: 0.1, stel: 0.1, idlh: 2)
        case "1079": return .init(analyte: "SO₂",  pel: 5,   stel: 5,   idlh: 100)
        default: return nil
        }
    }

    /// Sentence case per canon §3 — the run-1 all-caps verdict chips were
    /// part of the shouting the 2026-08-23.1 gate named.
    func verdict(_ ppm: Double) -> (String, Int) {   // label, severity 0..2
        if ppm >= idlh { return ("Immediately dangerous", 2) }
        if ppm >= stel { return ("Over STEL", 2) }
        if ppm >= pel  { return ("Over PEL", 1) }
        return ("Under PEL", 0)
    }
}

// MARK: - Snapshot (position-INDEPENDENT half only — see the offline note)

private struct ES24Snapshot: Codable, Equatable {
    var status: ES24Status?
    var erg: ES24ERG?
    var contacts: ES24Contacts?
    var spill: ES24SpillProtocol?
    var security: ES24SecurityPlan?
    /// Class-7 loads only. Each reading carries its own readingTime, so this is
    /// cacheable on the same absolute-stamp argument as the ambient samples.
    var dose: ES24DosimetryLog?
}

// MARK: - Canon tokens (§4 of the 2026-08-23.1 rework spec)
//
// The shared `Theme.Palette` is band-wide and predates this gate; its
// tertiary inks and inset tracks do not carry the canon pairs. Rather than
// reach across into a single-writer file, ES-24 pins its own tokens here.
// Every value below is one row of the §4 table, light column then dark.

private enum ES24Ink {
    static func pageBg(_ dark: Bool)     -> Color { dark ? Color(hex: 0x030309) : Color(hex: 0xEEF0F5) }
    static func surface(_ dark: Bool)    -> Color { dark ? Color(hex: 0x0D0E1A) : Color(hex: 0xFFFFFF) }
    static func track(_ dark: Bool)      -> Color { dark ? Color(hex: 0x0B0C16) : Color(hex: 0xE6E9EF) }
    static func hairline(_ dark: Bool)   -> Color { dark ? Color(hex: 0x25283A) : Color(hex: 0xD8DDE6) }
    static func primary(_ dark: Bool)    -> Color { dark ? Color(hex: 0xF5F5F7) : Color(hex: 0x0D1117) }
    static func secondary(_ dark: Bool)  -> Color { dark ? Color(hex: 0xAAB2BB) : Color(hex: 0x52606D) }
    static func tertiary(_ dark: Bool)   -> Color { dark ? Color(hex: 0x7F8996) : Color(hex: 0x596978) }
    /// Action primary is deliberately identical on both twins — the CTA is
    /// the one surface that must not shift register between themes.
    static let action                     = Color(hex: 0x0B66E5)
    static func link(_ dark: Bool)       -> Color { dark ? Color(hex: 0x4DA3FF) : Color(hex: 0x075FAB) }
    static let warnDot                    = Color(hex: 0xFFA726)
    static func warnInk(_ dark: Bool)    -> Color { dark ? Color(hex: 0xFFA726) : Color(hex: 0x7A4400) }
    static let successDot                 = Color(hex: 0x00C48C)
    static func successInk(_ dark: Bool) -> Color { dark ? Color(hex: 0x00C48C) : Color(hex: 0x006B4D) }
    /// §4 IS SILENT ON A DANGER PAIR — the exemplar carries no danger state at
    /// all, and the spec's own rule is that where the exemplar is silent you say
    /// so and do not invent. A poison-gas panel still has to separate "over PEL"
    /// from "immediately dangerous to life", so this surface falls back to the
    /// SHIPPED platform token `Brand.danger` (#F44336 · DesignSystem.swift:66)
    /// on both twins rather than minting a hex that no table contains. KNOWN
    /// SHORTFALL, stated rather than hidden: #F44336 on #FFFFFF measures about
    /// 3.7:1, which clears AA-large but not AA body. The fix is a danger row in
    /// the §4 table, not a colour picked here.
    static func dangerInk(_: Bool)       -> Color { Brand.danger }
    static func accent(_ dark: Bool)     -> Color { dark ? Color(hex: 0xD28BEB) : Color(hex: 0x6B2B83) }
    static let neutralDot                 = Color(hex: 0x6B7280)
    static func ctaStroke(_ dark: Bool)  -> Color { dark ? Color(hex: 0x7F8996) : Color(hex: 0x778391) }
}

/// §5 — the only gradient this surface is allowed to reference.
private enum ES24Grad {
    /// `eusoLine`. Used EXACTLY ONCE on this screen: the scheduled-check
    /// ring, which is the one temporal spine the panel is about. Both its
    /// ends are sourced — the last check-in comes from the `[ISO]` stamp
    /// hazmatEscort.ts:167 writes itself, the far end from `nextCheckInAt`
    /// (hazmatEscort.ts:107).
    static let eusoLine = LinearGradient(
        stops: [.init(color: Color(hex: 0x1473FF), location: 0.0),
                .init(color: Color(hex: 0x813FF5), location: 0.52),
                .init(color: Color(hex: 0xBE01FF), location: 1.0)],
        startPoint: .leading, endPoint: .trailing)
}

/// §3 — the exemplar histogram, spelled out so no call site can drift
/// below the floor. 10 belongs to bottom-nav captions, which `BottomNav`
/// owns; nothing in this file is allowed to reach for it.
private enum ES24Type {
    static let heroNumber  = Font.system(size: 34, weight: .bold, design: .monospaced)
    static let screenTitle = Font.system(size: 28, weight: .bold)
    static let large       = Font.system(size: 17, weight: .semibold)
    static let largeValue  = Font.system(size: 17, weight: .bold, design: .monospaced)
    static let rowTitle    = Font.system(size: 15, weight: .semibold)
    static let value       = Font.system(size: 15, weight: .bold, design: .monospaced)
    static let chevron     = Font.system(size: 14, weight: .semibold)
    static let label       = Font.system(size: 12, weight: .semibold)
    static let body        = Font.system(size: 12, weight: .medium)
    static let mono        = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let monoStrong  = Font.system(size: 12, weight: .bold, design: .monospaced)
}

/// §6 — canon geometry: card radius rx 20 over the §4 surface with a
/// one-point hairline stroke and 16-pt inner padding. The shared
/// `LifecycleCard` clips at `Radius.md` (12), carries an `accentGradient`
/// path this gate bans, and is single-writer owned by the Shipper band, so
/// ES-24 carries its own card rather than editing across a boundary.
private struct ES24Card<Content: View>: View {
    let isDark: Bool
    var accent: Color?
    let content: Content

    init(isDark: Bool, accent: Color? = nil, @ViewBuilder content: () -> Content) {
        self.isDark = isDark
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) { content }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ES24Ink.surface(isDark))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(accent ?? ES24Ink.hairline(isDark), lineWidth: 1))
    }
}

// MARK: - Screen

struct EscortHazmatWatch: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @State private var snap = ES24Snapshot()

    /// NEVER cached — both are position-dependent. See the header offline note.
    @State private var weather: ES24Weather?
    /// Which end of the lane the wind read was keyed to. Neither end is the
    /// escort's position; the panel names the one it asked about.
    @State private var weatherFromPickup = false
    @State private var proximity: ES24Proximity?
    @State private var fix: CLLocationCoordinate2D?

    @State private var loading = true
    @State private var errorMessage: String?
    @State private var checkInFlight = false
    @State private var checkInReceipt: String?
    /// nil == live. Non-nil means we are painting a snapshot and must say so.
    @State private var cacheAge: TimeInterval?
    @State private var now = Date()

    private let cacheTTL: TimeInterval = 90
    private let cacheKey = "escort.hazmatwatch.panel"

    /// The staleness boundary this whole screen grades and prints against.
    /// PINNED to ES24Freshness's mirror of CHECKIN_INTERVAL_MINUTES
    /// (hazmatEscort.ts:30 · 49 CFR §177.817). Every "STALE AT n MIN" string on
    /// this panel prints THIS number, so the statutory figure on the face is
    /// always the statutory figure and never a derived one.
    private let intervalMinutes = ES24Freshness.statutoryIntervalMinutes

    private var isDark: Bool { colorScheme == .dark }
    private var isSnapshot: Bool { cacheAge != nil }

    private var active: ES24Active? { snap.status?.active }
    private var load: ES24Load? { active?.load }
    private var bands: ES24Bands? { ES24Bands.forUN(load?.unNumber) }
    private var samples: [ES24Sample] { ES24NoteParser.samples(from: active?.notes) }
    private var latest: ES24Sample? { samples.first { $0.ppm != nil } }

    private var heroFreshness: ES24Freshness {
        ES24Freshness.of(ageMinutes: latest?.ageMinutes(now: now), intervalMinutes: intervalMinutes)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header

                if loading && active == nil {
                    ES24Card(isDark: isDark) {
                        Text("Reading the hazmat watch…")
                            .font(ES24Type.body).foregroundStyle(ES24Ink.secondary(isDark))
                    }
                } else if active == nil {
                    noActiveWatch
                } else {
                    if let errorMessage {
                        Text(errorMessage).font(ES24Type.body)
                            .foregroundStyle(ES24Ink.dangerInk(isDark))
                    }
                    ambientSection
                    arraySection
                    plumeSection
                    scheduleSection
                    ergSection
                }
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) { ctaBar }
        .task { await load() }
        .eusoRefreshable { await load(forceNetwork: true) }
        .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { t in
            // Ages must keep counting even when nothing refetches, otherwise a
            // reading would appear to freeze at the age it had when it landed.
            now = t
        }
    }

    // MARK: Header

    /// §1 — the run-1 eyebrow (9 pt, all caps, 1.0 tracking, gradient fill)
    /// was the gate's first named defect class and is gone. What replaces it
    /// is an orientation row in sentence case at the 12-pt floor.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Escort · hazmat watch")
                    .font(ES24Type.label)
                    .foregroundStyle(ES24Ink.secondary(isDark))
                Spacer()
                if let a = active?.assignmentId {
                    Text("Assignment \(a)")
                        .font(ES24Type.mono)
                        .foregroundStyle(ES24Ink.tertiary(isDark))
                }
            }

            Text(ledgerLine).font(ES24Type.mono)
                .foregroundStyle(ES24Ink.secondary(isDark)).lineLimit(1)

            Text(headlineText)
                .font(ES24Type.screenTitle).tracking(-0.4)
                .foregroundStyle(ES24Ink.primary(isDark))
                .lineLimit(1).minimumScaleFactor(0.7)

            Text(subheadText).font(ES24Type.body)
                .foregroundStyle(ES24Ink.secondary(isDark)).lineLimit(1)

            metaRow
            Rectangle().fill(ES24Ink.hairline(isDark)).frame(height: 1)
        }
    }

    private var ledgerLine: String {
        guard let l = load else { return "No load on this assignment" }
        var parts: [String] = []
        if let un = l.unNumber { parts.append("UN\(un)") }
        if let a = bands?.analyte { parts.append(a) }
        if let c = l.hazmatClass { parts.append("Class \(c)") }
        if snap.erg?.isTIH == true { parts.append("Inhalation hazard") }
        if let n = l.loadNumber { parts.append(n) }
        return parts.isEmpty ? "No hazmat classification on this load" : parts.joined(separator: " · ")
    }

    /// The reading and its age are welded together. When there is no reading the
    /// headline says so — it does not fall back to a comfortable number.
    private var headlineText: String {
        guard let s = latest, let ppm = s.ppm else { return "No reading logged" }
        let unit = bands?.analyte ?? "ppm"
        let age = s.ageMinutes(now: now)
        return "\(fmt(ppm)) ppm \(unit) · \(age) min old"
    }

    private var subheadText: String {
        var bits: [String] = []
        if let s = samples.first {
            bits.append("Logged \(clock(s.loggedAt))")
        } else {
            bits.append("No check-in logged yet")
        }
        if let nextText = active?.nextCheckInAt, let next = ES24NoteParser.parseISO(nextText) {
            let mins = Int(next.timeIntervalSince(now) / 60)
            bits.append("next check \(clock(next))")
            bits.append(mins >= 0 ? "T-\(mins) min" : "OVERDUE \(-mins) min")
        }
        return bits.joined(separator: " · ")
    }

    /// AMBER by construction. Nothing on this surface is machine-sampled, so a
    /// green live dot here would be the panel's first lie.
    private var metaRow: some View {
        HStack(spacing: 10) {
            if let pos = active?.position {
                Text(pos.capitalized)
                    .font(ES24Type.label)
                    .foregroundStyle(positionInk(pos.uppercased()))
                    .padding(.horizontal, 12).frame(height: 22)
                    .background(Capsule().fill(positionInk(pos.uppercased()).opacity(0.16)))
            }

            ZStack {
                Circle().fill(dotColor.opacity(0.25)).frame(width: 14, height: 14)
                Circle().fill(dotColor).frame(width: 8, height: 8)
            }

            Text(dotLabel).font(ES24Type.body)
                .foregroundStyle(ES24Ink.secondary(isDark))
                .lineLimit(1)

            Spacer(minLength: 4)

            if let city = load?.destCity, let st = load?.destState {
                Text("\(city), \(st)")
                    .font(ES24Type.mono).foregroundStyle(ES24Ink.tertiary(isDark))
                    .lineLimit(1)
            }
        }
    }

    private var dotColor: Color {
        if isSnapshot { return ES24Ink.neutralDot }
        switch heroFreshness {
        case .live: return ES24Ink.warnDot       // never green — see above
        case .stale: return ES24Ink.dangerInk(isDark)
        case .unavailable: return ES24Ink.neutralDot
        }
    }

    private var dotLabel: String {
        if let age = cacheAge { return EscortOfflineCache.stalenessLine(age: age) }
        switch heroFreshness {
        case .live(let a): return "Sample \(a) min · no live feed"
        case .stale(let a): return "Stale \(a) min · past interval"
        case .unavailable: return "No reading logged · no live feed"
        }
    }

    private func positionInk(_ p: String) -> Color {
        switch p {
        case "LEAD": return ES24Ink.action
        case "CHASE": return ES24Ink.accent(isDark)
        case "STEER": return ES24Ink.warnInk(isDark)
        default: return ES24Ink.warnInk(isDark)
        }
    }

    private var noActiveWatch: some View {
        ES24Card(isDark: isDark) {
            Text("No hazmat escort assignment")
                .font(ES24Type.rowTitle).foregroundStyle(ES24Ink.primary(isDark))
            Text("You have no active hazmat escort assignment right now. Nothing on this panel has anything to measure, so nothing is drawn.")
                .font(ES24Type.body).foregroundStyle(ES24Ink.secondary(isDark))
        }
    }

    // MARK: Cadence 1 · ambient sample + decay track

    private var ambientSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Ambient sample · every \(intervalMinutes) min",
                         trailing: "Hand-logged · no sensor feed")

            ES24Card(isDark: isDark) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ambient \(bands?.analyte ?? "reading") · \(latest?.point ?? "point unknown")")
                            .font(ES24Type.label)
                            .foregroundStyle(ES24Ink.secondary(isDark)).lineLimit(1)

                        if let s = latest, let ppm = s.ppm {
                            HStack(alignment: .lastTextBaseline, spacing: 6) {
                                Text(heroFreshness.isLive ? fmt(ppm) : "[\(fmt(ppm))]")
                                    .font(ES24Type.heroNumber).tracking(-0.6)
                                    .foregroundStyle(heroInk(ppm))
                                Text("ppm").font(ES24Type.rowTitle)
                                    .foregroundStyle(ES24Ink.secondary(isDark))
                            }
                            if let b = bands {
                                let v = b.verdict(ppm)
                                Text(heroFreshness.isLive ? v.0 : "Not live")
                                    .font(ES24Type.label)
                                    .foregroundStyle(heroFreshness.isLive ? severityInk(v.1) : ES24Ink.tertiary(isDark))
                                    .padding(.horizontal, 12).padding(.vertical, 4)
                                    .background {
                                        if heroFreshness.isLive {
                                            Capsule().fill(severityInk(v.1).opacity(0.18))
                                        } else {
                                            Capsule().strokeBorder(
                                                style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                                                .foregroundStyle(ES24Ink.tertiary(isDark).opacity(0.55))
                                        }
                                    }
                            } else {
                                unavailableChip("No band table for UN\(load?.unNumber ?? "—")")
                            }
                        } else {
                            Text("—").font(ES24Type.heroNumber).tracking(-0.6)
                                .foregroundStyle(ES24Ink.tertiary(isDark))
                            unavailableChip("No reading in the check-in log")
                        }
                    }

                    Spacer(minLength: 4)
                    thresholdRuler
                }

                decayTrack.padding(.top, 8)
            }
        }
    }

    private func heroInk(_ ppm: Double) -> Color {
        guard heroFreshness.isLive else { return ES24Ink.tertiary(isDark) }
        guard let b = bands else { return ES24Ink.primary(isDark) }
        return severityInk(b.verdict(ppm).1)
    }

    private func severityInk(_ s: Int) -> Color {
        s >= 2 ? ES24Ink.dangerInk(isDark)
               : (s == 1 ? ES24Ink.warnInk(isDark) : ES24Ink.successInk(isDark))
    }

    /// The bands are a LOCAL table and the ruler says so, because no procedure
    /// in the tree serves an exposure threshold.
    private var thresholdRuler: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("Thresholds · local table")
                .font(ES24Type.body)
                .foregroundStyle(ES24Ink.tertiary(isDark))

            if let b = bands {
                let top = max(b.stel * 1.35, (latest?.ppm ?? 0) * 1.2, b.pel * 2)
                GeometryReader { geo in
                    let w = geo.size.width
                    let x = { (v: Double) in max(0, min(w, w * v / top)) }
                    ZStack(alignment: .topLeading) {
                        HStack(spacing: 0) {
                            Rectangle().fill(ES24Ink.successDot.opacity(0.30)).frame(width: x(b.pel))
                            Rectangle().fill(ES24Ink.warnDot.opacity(0.50))
                                .frame(width: max(0, x(b.stel) - x(b.pel)))
                            Rectangle().fill(ES24Ink.dangerInk(isDark).opacity(0.40))
                        }
                        .frame(height: 6).clipShape(Capsule()).padding(.top, 7)

                        Rectangle().fill(ES24Ink.warnDot).frame(width: 1.2, height: 15)
                            .offset(x: x(b.pel) - 0.6, y: 3)
                        Rectangle().fill(ES24Ink.dangerInk(isDark)).frame(width: 1.2, height: 15)
                            .offset(x: x(b.stel) - 0.6, y: 3)

                        if let ppm = latest?.ppm, heroFreshness.isLive {
                            ES24Triangle().fill(ES24Ink.warnDot)
                                .frame(width: 9, height: 7)
                                .offset(x: x(ppm) - 4.5, y: 0)
                        }
                    }
                }
                .frame(width: 150, height: 24)

                HStack(spacing: 0) {
                    Text("PEL \(fmt(b.pel))").font(ES24Type.mono)
                        .foregroundStyle(ES24Ink.warnInk(isDark))
                    Spacer(minLength: 6)
                    Text("STEL \(fmt(b.stel))").font(ES24Type.mono)
                        .foregroundStyle(ES24Ink.dangerInk(isDark))
                }
                .frame(width: 150)

                Text("IDLH \(fmt(b.idlh))").font(ES24Type.mono)
                    .foregroundStyle(ES24Ink.tertiary(isDark))
            } else {
                unavailableChip("No band table")
            }
        }
    }

    /// THE SIGNATURE ORGAN — the sample's age drawn against the statutory
    /// staleness boundary, with the past-interval zone hatched rather than
    /// merely tinted so it reads as forbidden without being read.
    private var decayTrack: some View {
        let span = Double(intervalMinutes) * 4.0 / 3.0     // 0 → interval + 1/3
        let age = Double(heroFreshness.ageMinutes ?? 0)

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Sample age").font(ES24Type.label)
                    .foregroundStyle(ES24Ink.secondary(isDark))
                Spacer(minLength: 6)
                Text("Stale at \(intervalMinutes) min · 49 CFR §177.817")
                    .font(ES24Type.body)
                    .foregroundStyle(ES24Ink.tertiary(isDark)).lineLimit(1)
            }

            GeometryReader { geo in
                let w = geo.size.width
                let x = { (m: Double) in max(0, min(w, w * m / span)) }
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        Rectangle().fill(ES24Ink.successDot.opacity(0.32))
                            .frame(width: x(Double(intervalMinutes) / 2))
                        Rectangle().fill(ES24Ink.warnDot.opacity(0.45))
                            .frame(width: x(Double(intervalMinutes)) - x(Double(intervalMinutes) / 2))
                        ES24Hatch(ink: ES24Ink.tertiary(isDark))
                            .overlay(Rectangle().stroke(ES24Ink.dangerInk(isDark).opacity(0.55), lineWidth: 1))
                    }
                    .frame(height: 8).clipShape(RoundedRectangle(cornerRadius: 4)).padding(.top, 6)

                    Rectangle().fill(ES24Ink.dangerInk(isDark)).frame(width: 1.4, height: 16)
                        .offset(x: x(Double(intervalMinutes)) - 0.7, y: 2)

                    if heroFreshness != .unavailable {
                        Rectangle()
                            .fill(heroFreshness.isLive ? ES24Ink.warnDot : ES24Ink.dangerInk(isDark))
                            .frame(width: 2, height: 16)
                            .offset(x: x(age) - 1, y: 2)
                        Text(heroFreshness.label)
                            .font(ES24Type.mono)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(heroFreshness.isLive ? ES24Ink.warnDot : ES24Ink.dangerInk(isDark)))
                            .offset(x: max(0, min(w - 62, x(age) - 31)), y: -18)
                    }
                }
            }
            .frame(height: 24).padding(.top, 16)

            HStack(spacing: 0) {
                Text("0").font(ES24Type.mono).foregroundStyle(ES24Ink.tertiary(isDark))
                Spacer()
                Text("\(intervalMinutes) · stale").font(ES24Type.monoStrong)
                    .foregroundStyle(ES24Ink.dangerInk(isDark))
                Spacer()
                Text("\(Int(span))+ min").font(ES24Type.mono)
                    .foregroundStyle(ES24Ink.tertiary(isDark))
            }
            .padding(.top, 4)
        }
    }

    // MARK: Cadence 2 · the array

    private var arraySection: some View {
        let rows = samples.prefix(4)
        let staleCount = rows.filter { $0.ageMinutes(now: now) >= intervalMinutes }.count

        return VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Detector array · \(rows.count) point\(rows.count == 1 ? "" : "s")",
                         trailing: rows.isEmpty ? "No points logged"
                                                : "\(rows.count - staleCount) live · \(staleCount) stale")

            ES24Card(isDark: isDark) {
                if rows.isEmpty {
                    Text("No check-in has been logged on this assignment.")
                        .font(ES24Type.rowTitle).foregroundStyle(ES24Ink.primary(isDark))
                    Text("There is no detector registry and no telemetry feed, so this array is exactly the check-in log and nothing more.")
                        .font(ES24Type.body).foregroundStyle(ES24Ink.secondary(isDark))
                } else {
                    HStack(spacing: 0) {
                        Text("Sample point").font(ES24Type.label)
                            .foregroundStyle(ES24Ink.secondary(isDark))
                        Spacer()
                        Text("ppm").font(ES24Type.label)
                            .foregroundStyle(ES24Ink.secondary(isDark)).frame(width: 52, alignment: .trailing)
                        Text("Verdict").font(ES24Type.label)
                            .foregroundStyle(ES24Ink.secondary(isDark)).frame(width: 104, alignment: .center)
                        Text("Age").font(ES24Type.label)
                            .foregroundStyle(ES24Ink.secondary(isDark)).frame(width: 56, alignment: .trailing)
                    }
                    Rectangle().fill(ES24Ink.hairline(isDark)).frame(height: 1)

                    ForEach(Array(rows)) { row in sampleRow(row) }

                    if samples.count > rows.count {
                        Text("\(samples.count - rows.count) older check-in\(samples.count - rows.count == 1 ? "" : "s") not shown")
                            .font(ES24Type.body)
                            .foregroundStyle(ES24Ink.tertiary(isDark))
                    }
                }
            }
        }
    }

    /// LIVE → solid numeral, lit verdict. STALE → bracketed numeral over a
    /// hatch, verdict refuses to light, dashed outline, danger-coloured age.
    private func sampleRow(_ row: ES24Sample) -> some View {
        let age = row.ageMinutes(now: now)
        let stale = age >= intervalMinutes
        let v: (String, Int)? = {
            guard let ppm = row.ppm, let b = bands else { return nil }
            return b.verdict(ppm)
        }()

        return HStack(spacing: 0) {
            Text(row.point).font(ES24Type.body)
                .foregroundStyle(stale ? ES24Ink.tertiary(isDark) : ES24Ink.primary(isDark))
                .lineLimit(1)
            Spacer(minLength: 6)

            ZStack(alignment: .trailing) {
                if stale, row.ppm != nil {
                    ES24Hatch(ink: ES24Ink.tertiary(isDark))
                        .frame(width: 40, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Text(numeral(row, stale: stale))
                    .font(ES24Type.monoStrong)
                    .foregroundStyle(stale || row.ppm == nil
                                     ? ES24Ink.tertiary(isDark)
                                     : severityInk(v?.1 ?? 0))
            }
            .frame(width: 52, alignment: .trailing)

            Group {
                if row.ppm == nil {
                    Text("No reading").font(ES24Type.body)
                        .foregroundStyle(ES24Ink.tertiary(isDark))
                        .frame(width: 96, height: 20)
                        .background {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                                .foregroundStyle(ES24Ink.tertiary(isDark).opacity(0.55))
                        }
                } else if stale || v == nil {
                    Text("Not live").font(ES24Type.body)
                        .foregroundStyle(ES24Ink.tertiary(isDark))
                        .frame(width: 96, height: 20)
                        .background {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                                .foregroundStyle(ES24Ink.tertiary(isDark).opacity(0.55))
                        }
                } else {
                    Text(v!.0).font(ES24Type.body)
                        .foregroundStyle(severityInk(v!.1))
                        .lineLimit(1).minimumScaleFactor(0.9)
                        .frame(width: 96, height: 20)
                        .background(Capsule().fill(severityInk(v!.1).opacity(0.16)))
                }
            }
            .frame(width: 104, alignment: .center)

            Text("\(age) min")
                .font(stale ? ES24Type.monoStrong : ES24Type.mono)
                .foregroundStyle(stale ? ES24Ink.dangerInk(isDark) : ES24Ink.secondary(isDark))
                .frame(width: 56, alignment: .trailing)
        }
        .frame(height: 28)
        .background {
            if stale {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(ES24Ink.tertiary(isDark).opacity(0.55))
            }
        }
    }

    private func numeral(_ row: ES24Sample, stale: Bool) -> String {
        guard let ppm = row.ppm else { return "—" }
        return stale ? "[\(fmt(ppm))]" : fmt(ppm)
    }

    // MARK: Cadence 3 · plume geometry

    private var plumeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Plume geometry · wind and ERG rings",
                         trailing: windAgeLabel)

            ES24Card(isDark: isDark,
                     accent: downwind ? ES24Ink.dangerInk(isDark).opacity(0.55) : nil) {
                HStack(alignment: .top, spacing: 12) {
                    // The rose's own caption was a 6.5-pt node inside the dial.
                    // It now sits under the dial at the 12-pt floor, where it
                    // has the width to be read.
                    VStack(spacing: 4) {
                        ES24WindRose(pal: palette,
                                     isDark: isDark,
                                     windFromBearing: windBearing,
                                     lit: weather != nil && !isSnapshot)
                            .frame(width: 104, height: 104)
                        Text(weather != nil && !isSnapshot ? "Upwind park · derived"
                                                           : "No bearing · rose unlit")
                            .font(ES24Type.body)
                            .foregroundStyle(weather != nil && !isSnapshot
                                             ? ES24Ink.successInk(isDark)
                                             : ES24Ink.tertiary(isDark))
                            .lineLimit(1).minimumScaleFactor(0.85)
                    }
                    .frame(width: 132)

                    VStack(alignment: .leading, spacing: 0) {
                        if isSnapshot || weather == nil {
                            // Never hold the last bearing. A cached or missing
                            // wind is drawn as absent, not as a picture.
                            unavailableChip(isSnapshot ? "Wind not cached · reconnect"
                                                       : "Wind unavailable · NWS did not answer")
                        } else {
                            if downwind {
                                Text("Plume runs \(downwindCompass)")
                                    .font(ES24Type.label)
                                    .foregroundStyle(ES24Ink.dangerInk(isDark))
                                    .padding(.horizontal, 9).padding(.vertical, 4)
                                    .background {
                                        Capsule().fill(ES24Ink.dangerInk(isDark).opacity(0.14))
                                            .overlay(Capsule().stroke(ES24Ink.dangerInk(isDark).opacity(0.45), lineWidth: 1))
                                    }
                            }
                            // The station's city is NOT stated here — it is
                            // stated in the caveat block below, where it is read
                            // as a qualification rather than as a location badge.
                            Text("Wind · NWS observation")
                                .font(ES24Type.label)
                                .foregroundStyle(ES24Ink.secondary(isDark))
                                .padding(.top, downwind ? 10 : 0).lineLimit(1)
                            Text(windHeadline)
                                .font(ES24Type.value)
                                .foregroundStyle(ES24Ink.primary(isDark)).padding(.top, 3)
                                .lineLimit(1).minimumScaleFactor(0.8)
                            Text(windObservedLine)
                                .font(ES24Type.mono)
                                .foregroundStyle(ES24Ink.warnInk(isDark)).padding(.top, 2)
                                .lineLimit(1).minimumScaleFactor(0.8)
                            // NOT a footnote. The bearing belongs to a station
                            // tied to one end of the lane, not to the ground the
                            // escort is standing on, and that has to be as loud
                            // as the bearing it qualifies.
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Bearing is not your position")
                                Text(windPlaceCaveat)
                                    .lineLimit(1).minimumScaleFactor(0.8)
                            }
                            .font(ES24Type.label)
                            .foregroundStyle(ES24Ink.warnInk(isDark))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(ES24Ink.warnDot.opacity(0.16))
                                    .overlay(RoundedRectangle(cornerRadius: 6)
                                        .stroke(ES24Ink.warnDot.opacity(0.55), lineWidth: 1))
                            }
                            .padding(.top, 4)
                        }

                        Rectangle().fill(ES24Ink.hairline(isDark)).frame(height: 1).padding(.vertical, 7)

                        ergRings

                        Rectangle().fill(ES24Ink.hairline(isDark)).frame(height: 1).padding(.vertical, 7)

                        receptorBlock
                    }
                }
            }
        }
    }

    /// Real ERG figures or nothing. There is no fallback ring.
    private var ergRings: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("ERG rings · UN\(load?.unNumber ?? "—")")
                .font(ES24Type.label)
                .foregroundStyle(ES24Ink.secondary(isDark))

            if let pd = snap.erg?.protectiveDistance,
               let large = pd.largeSpill,
               let day = large.day, let night = large.night,
               (day.isolateMeters ?? 0) > 0 {
                Text("Isolate \(Int(day.isolateMeters ?? 0)) m · protect \(fmt(day.protectKm ?? 0)) km by day")
                    .font(ES24Type.body)
                    .foregroundStyle(ES24Ink.primary(isDark))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text("Protect \(fmt(night.protectKm ?? 0)) km after dark")
                    .font(ES24Type.body)
                    .foregroundStyle(ES24Ink.dangerInk(isDark))
                    .lineLimit(1).minimumScaleFactor(0.8)
            } else if let iso = snap.erg?.guideFull?.isolationDistanceMeters {
                Text("Initial isolate \(Int(iso)) m · no Table 1 entry")
                    .font(ES24Type.body)
                    .foregroundStyle(ES24Ink.primary(isDark))
                    .lineLimit(1).minimumScaleFactor(0.8)
            } else {
                unavailableChip("No ERG distances for this load")
            }
        }
    }

    /// The rings are real. WHO is inside them is not known, and the panel says
    /// so instead of drawing a comforting zero.
    private var receptorBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Receptors inside rings")
                .font(ES24Type.label)
                .foregroundStyle(ES24Ink.secondary(isDark))
            Text("Not evaluated — no school, hospital or")
                .font(ES24Type.body)
                .foregroundStyle(ES24Ink.secondary(isDark))
                .lineLimit(1).minimumScaleFactor(0.8)
            Text("residential dataset exists.")
                .font(ES24Type.body)
                .foregroundStyle(ES24Ink.secondary(isDark))
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(zoneLine)
                .font(ES24Type.body)
                .foregroundStyle(proximity?.inRestrictedZone == true
                                 ? ES24Ink.dangerInk(isDark) : ES24Ink.tertiary(isDark))
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.top, 2)
        }
    }

    /// checkProximity's table is 13 hard-coded tunnels and metro zones. An empty
    /// result means the table had nothing nearby — never that the road is clear.
    private var zoneLine: String {
        if isSnapshot { return "Zones not cached · reconnect" }
        guard let p = proximity else {
            return fix == nil ? "Zones not evaluated · no GPS fix"
                              : "Zones not evaluated · call failed"
        }
        let alerts = p.alerts ?? []
        if let first = alerts.first {
            let d = first.distanceMiles.map { fmt($0) } ?? "—"
            return "\(first.alert?.capitalized ?? "Near") \(first.zoneName ?? "zone") · \(d) mi"
        }
        return "Zone table 0 of 13 in range"
    }

    private var windBearing: Double? {
        guard !isSnapshot, let c = weather?.windDirection else { return nil }
        return ES24Compass.degrees(c)
    }
    private var downwind: Bool { windBearing != nil }
    private var downwindCompass: String {
        guard let b = windBearing else { return "—" }
        return ES24Compass.name((b + 180).truncatingRemainder(dividingBy: 360))
    }
    private var windHeadline: String {
        let from = weather?.windDirection ?? "—"
        let mph = weather?.windSpeed.map { "\($0) mph" } ?? "— mph"
        return "\(from) → \(downwindCompass) \(mph)"
    }
    private var windObservedLine: String {
        guard let t = weather?.updatedAt, let d = ES24NoteParser.parseISO(t) else {
            return "Observation time unknown"
        }
        let mins = max(0, Int(now.timeIntervalSince(d) / 60))
        return "Observed \(clock(d)) · \(mins) min ago"
    }
    /// Names the city the wind was actually asked about, and which end of the
    /// lane it is, so the operator can see for themselves that it is not here.
    /// There is no coordinate-keyed wind bearing in the tree (STUB filed).
    private var windPlaceCaveat: String {
        let place = weather?.location ?? "unknown city"
        return "NWS \(place) · \(weatherFromPickup ? "pickup" : "delivery") city, not the tank"
    }

    private var windAgeLabel: String {
        if isSnapshot { return "Not cached" }
        guard let t = weather?.updatedAt, let d = ES24NoteParser.parseISO(t) else { return "NWS · —" }
        return "NWS · \(max(0, Int(now.timeIntervalSince(d) / 60))) min old"
    }

    // MARK: Cadence 4 · the scheduled-check clock

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Scheduled checks", trailing: securityLabel)

            ES24Card(isDark: isDark,
                     accent: overdue ? ES24Ink.warnDot.opacity(0.55) : nil) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle().stroke(ES24Ink.track(isDark), lineWidth: 6).frame(width: 64, height: 64)
                        // §5 — THE ONE `eusoLine` ON THIS SCREEN. The check-in
                        // interval is the single temporal spine ES-24 is about,
                        // and both its ends are sourced: the near end from the
                        // [ISO] stamp hazmatEscort.ts:167 writes, the far end
                        // from nextCheckInAt (hazmatEscort.ts:107).
                        Circle()
                            .trim(from: 0, to: CGFloat(min(1, elapsedFraction)))
                            .stroke(ES24Grad.eusoLine,
                                    style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90)).frame(width: 64, height: 64)
                        VStack(spacing: 0) {
                            Text(countdownText)
                                .font(ES24Type.largeValue)
                                .foregroundStyle(overdue ? ES24Ink.dangerInk(isDark) : ES24Ink.primary(isDark))
                            Text("min").font(ES24Type.body)
                                .foregroundStyle(ES24Ink.tertiary(isDark))
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(nextCheckText).font(ES24Type.rowTitle)
                                .foregroundStyle(ES24Ink.primary(isDark))
                                .lineLimit(1).minimumScaleFactor(0.8)
                            Spacer(minLength: 6)
                            Text("Every \(intervalMinutes) min")
                                .font(ES24Type.body)
                                .foregroundStyle(ES24Ink.tertiary(isDark))
                        }
                        Text(lastCheckText)
                            .font(ES24Type.body)
                            .foregroundStyle(ES24Ink.secondary(isDark)).lineLimit(1)

                        // Cadence roster. Every entry states WHY it is not lighting.
                        HStack(spacing: 5) {
                            stubChip("Photo not captured")
                            dosimetryChip
                        }.padding(.top, 4)
                        HStack(spacing: 5) {
                            stubChip("Condensation · no feed")
                            stubChip("Cadence not verified")
                        }
                    }
                }
            }
        }
    }

    private var isClass7: Bool { (load?.hazmatClass ?? "").hasPrefix("7") }

    /// Three honest states, in this order:
    ///   • not a class-7 load        → CLASS 7 ONLY (a category error, not a gap)
    ///   • class 7 with a real log   → the server's cumulative mrem + severity
    ///   • class 7 with an empty log → NO DOSE LOGGED, never a zero dressed as clear
    /// In every case the WRITE is unavailable to this role, which the chip says.
    @ViewBuilder private var dosimetryChip: some View {
        if !isClass7 {
            stubChip("Dosimetry · class 7 only")
        } else if let d = snap.dose, let total = d.cumulativeMrem,
                  !(d.readings ?? []).isEmpty {
            Text("Dose \(fmt(total)) mrem · \(d.severity ?? "—") · read only")
                .font(ES24Type.body)
                .foregroundStyle(ES24Ink.warnInk(isDark))
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 8).frame(height: 22)
                .background(Capsule().fill(ES24Ink.warnDot.opacity(0.16)))
        } else {
            stubChip("Dosimetry · no dose logged")
        }
    }

    private var elapsedFraction: Double {
        guard let a = heroFreshness.ageMinutes ?? samples.first.map({ $0.ageMinutes(now: now) })
        else { return 0 }
        return Double(a) / Double(max(1, intervalMinutes))
    }
    private var minutesToNext: Int? {
        guard let t = active?.nextCheckInAt, let d = ES24NoteParser.parseISO(t) else { return nil }
        return Int(d.timeIntervalSince(now) / 60)
    }
    private var overdue: Bool { (minutesToNext ?? 1) < 0 }
    private var countdownText: String {
        guard let m = minutesToNext else { return "—" }
        return m >= 0 ? "T-\(m)" : "+\(-m)"
    }
    private var nextCheckText: String {
        guard let t = active?.nextCheckInAt, let d = ES24NoteParser.parseISO(t) else {
            return "Next check time unavailable"
        }
        return overdue ? "Check overdue since \(clock(d))" : "Next check \(clock(d))"
    }
    private var lastCheckText: String {
        guard let s = samples.first else { return "No check-in on record" }
        return "Last \(clock(s.loggedAt)) · \(s.ageMinutes(now: now)) min ago"
    }
    private var securityLabel: String {
        guard let sec = snap.security else { return "Security plan not evaluated" }
        guard let req = sec.requiresSecurityPlan else { return "Security plan unknown" }
        return req ? "Security plan required · 172.800" : "Security plan not triggered"
    }

    // MARK: Cadence 5 · emergency reference

    private var ergSection: some View {
        ES24Card(isDark: isDark, accent: ES24Ink.dangerInk(isDark).opacity(0.55)) {
            HStack(spacing: 12) {
                ES24Placard(code: snap.erg?.hazardClass ?? load?.hazmatClass ?? "—",
                            label: snap.erg?.placard ?? "Placard",
                            isDark: isDark)
                    .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 3) {
                    if let g = snap.erg?.guideNumber {
                        Text("ERG guide \(g)").font(ES24Type.rowTitle)
                            .foregroundStyle(ES24Ink.accent(isDark))
                    } else {
                        Text("No ERG guide").font(ES24Type.rowTitle)
                            .foregroundStyle(ES24Ink.tertiary(isDark))
                    }
                    Text(snap.erg?.guideFull?.title ?? snap.erg?.name ?? "No UN number on the load")
                        .font(ES24Type.body)
                        .foregroundStyle(ES24Ink.secondary(isDark)).lineLimit(2)
                    if let m = snap.erg?.guideFull?.isolationDistanceMeters,
                       let f = snap.erg?.guideFull?.isolationDistanceFeet {
                        Text("Initial isolate \(Int(m)) m / \(Int(f)) ft")
                            .font(ES24Type.body)
                            .foregroundStyle(ES24Ink.primary(isDark))
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 3) {
                    Text("CHEMTREC · 24 h").font(ES24Type.body)
                        .foregroundStyle(ES24Ink.tertiary(isDark))
                    // Read from erg.getEmergencyContacts — never typed into the view.
                    if let phone = snap.contacts?.chemtrec?.phone {
                        Text(phone).font(ES24Type.value)
                            .foregroundStyle(ES24Ink.dangerInk(isDark))
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Text("Tap to call").font(ES24Type.body)
                            .foregroundStyle(ES24Ink.tertiary(isDark))
                    } else {
                        unavailableChip("No contact feed")
                    }
                }

                Image(systemName: "chevron.right").font(ES24Type.chevron)
                    .foregroundStyle(ES24Ink.tertiary(isDark))
            }
            .contentShape(Rectangle())
            .onTapGesture { callChemtrec() }

            if let radius = snap.spill?.evacuationRadius {
                Text("Spill protocol · evacuate \(radius)")
                    .font(ES24Type.body)
                    .foregroundStyle(ES24Ink.secondary(isDark)).lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if let first = snap.spill?.immediateActions?.first {
                Text(first).font(ES24Type.body)
                    .foregroundStyle(ES24Ink.secondary(isDark)).lineLimit(2)
            }
        }
    }

    // MARK: CTA bar (ONLINE_ONLY — no outbox, no queue badge, ever)

    /// §8 command dock: 52-pt tall, rx 12, primary is a FLAT #0B66E5 fill
    /// with a white 15/600 label. The shared `CTAButton` is gradient-backed
    /// at a 17-pt label, so it is deliberately not used on this surface.
    private var ctaBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ctaHonestyLine)
                .font(ES24Type.body)
                .foregroundStyle(ES24Ink.tertiary(isDark))
                .lineLimit(1).minimumScaleFactor(0.8)

            if let checkInReceipt {
                Text(checkInReceipt).font(ES24Type.body)
                    .foregroundStyle(ES24Ink.successInk(isDark))
            }

            HStack(spacing: Space.s3) {
                Button {
                    guard canCheckIn, !checkInFlight else { return }
                    Task { await logCheckIn() }
                } label: {
                    Text(canCheckIn ? "Log check-in" : "Check-in needs a GPS fix")
                        .font(ES24Type.rowTitle)
                        .foregroundStyle(Color.white)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(ES24Ink.action)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .opacity(canCheckIn && !checkInFlight ? 1 : 0.45)
                .disabled(!canCheckIn || checkInFlight)

                Button { callChemtrec() } label: {
                    Text("ERG card").font(ES24Type.rowTitle)
                        .foregroundStyle(ES24Ink.primary(isDark))
                        .frame(width: 140, height: 52)
                        .background(ES24Ink.surface(isDark))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(ES24Ink.ctaStroke(isDark), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    /// A check-in without a real fix would be a fabricated position on a safety
    /// record, so the button refuses rather than sending zeroes.
    private var canCheckIn: Bool { active != nil && fix != nil }

    private var ctaHonestyLine: String {
        "Check-in writes online only · no outbox · no queue badge"
    }

    // MARK: Small parts

    /// §8 — section label 12/600 secondary at left, 12/500 tertiary count at
    /// right. Sentence case, zero tracking; the run-1 all-caps 9-pt labels on
    /// 1.0 tracking were the gate's first named defect class.
    private func sectionLabel(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title).font(ES24Type.label)
                .foregroundStyle(ES24Ink.secondary(isDark))
            Spacer(minLength: 6)
            Text(trailing).font(ES24Type.body)
                .foregroundStyle(ES24Ink.tertiary(isDark))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private func unavailableChip(_ t: String) -> some View {
        Text(t).font(ES24Type.body)
            .foregroundStyle(ES24Ink.tertiary(isDark))
            .lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, 10).frame(height: 24)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(ES24Ink.tertiary(isDark).opacity(0.5))
            }
    }

    private func stubChip(_ t: String) -> some View { unavailableChip(t) }

    private func fmt(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
    }

    private func clock(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    /// The number is whatever `erg.getEmergencyContacts` returned. If the read
    /// failed there is no number to dial and this is a no-op — the view never
    /// carries a hard-coded emergency line.
    private func callChemtrec() {
        guard let raw = snap.contacts?.chemtrec?.phone,
              let url = URL(string: "tel://\(raw.filter(\.isNumber))") else { return }
        openURL(url)
    }

    // MARK: - Data plumbing

    /// A read whose failure degrades one cell instead of the whole fold.
    private func softQuery<T: Decodable, I: Encodable>(_ path: String, _ input: I) async -> T? {
        do { let v: T = try await EusoTripAPI.shared.query(path, input: input); return v }
        catch { return nil }
    }

    private func load(forceNetwork: Bool = false) async {
        if snap.status == nil { await MainActor.run { loading = true } }

        // Position-dependent inputs are resolved first; both consumers refuse to
        // paint without them rather than guessing.
        let coord = await DriverLocationResolver.shared.currentCoordinate()
        await MainActor.run { fix = coord }

        do {
            let status: ES24Status = try await EusoTripAPI.shared.query(
                "hazmatEscort.getStatus", input: ES24EmptyInput())

            var next = ES24Snapshot()
            next.status = status

            let un = status.active?.load?.unNumber
            let cls = status.active?.load?.hazmatClass

            // Position-INDEPENDENT reads — these are the cacheable half.
            if let un {
                next.erg = await softQuery("erg.searchByUN", ES24UNInput(unNumber: un))
            }
            next.contacts = await softQuery("erg.getEmergencyContacts", ES24EmptyInput())
            if let cls {
                next.spill = await softQuery(
                    "emergencyProtocols.getHazmatSpillProtocol",
                    ES24SpillInput(hazmatClass: ES24SpillClass.key(for: cls)))
                next.security = await softQuery(
                    "hazmat.getSecurityPlanStatus", ES24SecurityInput(hazmatClasses: [cls]))
            }

            // Class-7 dose log. The READ is open to this role (nrc.ts:649 is
            // plain protectedProcedure); only the WRITE is hazmat-gated. loadId
            // is stringified because that procedure's schema demands a string
            // while getStatus hands back a number.
            if (cls ?? "").hasPrefix("7"), let lid = status.active?.loadId {
                next.dose = await softQuery("nrc.getDosimetryLog",
                                            ES24DoseInput(loadId: String(lid)))
            }

            // Position-DEPENDENT reads — never cached, never replayed.
            // WIND IS KEYED TO A CITY, NOT TO THE ESCORT. weather.getCurrent
            // (weather.ts:1993) accepts {city,state} only, and the one
            // coordinate-taking read, weather.byLatLon (weather.ts:1545),
            // carries wind SPEED with no direction — so the escort's own fix
            // cannot buy a bearing anywhere in this tree (STUB filed). Of the
            // two cities this screen actually holds, the PICKUP city is
            // preferred: the DELIVERY city is the one place an escort standing
            // beside a staged load is provably not. Whichever city is asked
            // about is then named in the rendered caveat.
            var freshWeather: ES24Weather?
            var freshWeatherFromPickup = false
            if let city = status.active?.load?.originCity,
               let st = status.active?.load?.originState {
                freshWeatherFromPickup = true
                freshWeather = await softQuery("weather.getCurrent",
                                               ES24WeatherInput(city: city, state: st))
            } else if let city = status.active?.load?.destCity,
                      let st = status.active?.load?.destState {
                freshWeather = await softQuery("weather.getCurrent",
                                               ES24WeatherInput(city: city, state: st))
            }
            var freshProximity: ES24Proximity?
            if let coord, let cls {
                freshProximity = await softQuery(
                    "hazmat.checkProximity",
                    ES24ProximityInput(lat: coord.latitude, lng: coord.longitude,
                                       hazmatClass: cls, alertRadiusMiles: 5))
            }

            await MainActor.run {
                snap = next
                weather = freshWeather
                weatherFromPickup = freshWeatherFromPickup
                proximity = freshProximity
                cacheAge = nil
                loading = false
                errorMessage = nil
                now = Date()
            }
            EscortOfflineCache.store(next, key: cacheKey)

        } catch {
            // READ_CACHED(90s) for the position-independent half ONLY. Sample
            // ages keep counting off their own absolute stamps, so a replay
            // cannot make a reading look younger than it is.
            if let hit = EscortOfflineCache.load(ES24Snapshot.self, key: cacheKey, ttl: cacheTTL) {
                await MainActor.run {
                    snap = hit.value
                    cacheAge = hit.age
                    weather = nil          // position-dependent — blanked on purpose
                    weatherFromPickup = false
                    proximity = nil        // position-dependent — blanked on purpose
                    loading = false
                    errorMessage = nil
                    now = Date()
                }
            } else {
                await MainActor.run {
                    cacheAge = nil
                    loading = false
                    errorMessage = "Hazmat watch unavailable. Nothing on this panel is being measured right now."
                }
            }
        }
    }

    /// ONLINE_ONLY. There is no escort outbox, so a failure is reported as a
    /// failure — it is never absorbed into a queue the app does not have.
    private func logCheckIn() async {
        guard let a = active?.assignmentId, let coord = fix, !checkInFlight else { return }
        await MainActor.run { checkInFlight = true; checkInReceipt = nil; errorMessage = nil }

        // The note carries the reading using the client-side convention this
        // screen also parses. It is a convention over an untyped column, not a
        // schema — the typed store is filed as a STUB in the header.
        let note: String? = latest.map { "POINT=\($0.point)" }

        do {
            let receipt: ES24CheckInReceipt = try await EusoTripAPI.shared.mutation(
                "hazmatEscort.checkIn",
                input: ES24CheckInInput(assignmentId: a,
                                        lat: coord.latitude,
                                        lon: coord.longitude,
                                        note: note))
            await MainActor.run {
                checkInFlight = false
                if let nextAt = receipt.nextCheckInAt,
                   let d = ES24NoteParser.parseISO(nextAt) {
                    checkInReceipt = "Checked in. Next check \(clock(d))."
                } else {
                    checkInReceipt = "Checked in."
                }
            }
            await load(forceNetwork: true)
        } catch {
            await MainActor.run {
                checkInFlight = false
                errorMessage = "Check-in did not go through. Nothing was recorded and nothing is waiting to send — there is no offline queue on this screen. Try again when you have signal, and call it in over the radio if you cannot."
            }
        }
    }
}

// MARK: - Hazmat class → getHazmatSpillProtocol enum key

/// emergencyProtocols.getHazmatSpillProtocol takes the enum at
/// emergencyProtocols.ts:87-97, not the DOT class string on the load, so the
/// mapping is made explicit here rather than hidden in a call site.
private enum ES24SpillClass {
    static func key(for dotClass: String) -> String {
        switch dotClass.prefix(1) {
        case "1": return "class_1_explosives"
        case "2": return "class_2_gases"
        case "3": return "class_3_flammable_liquids"
        case "4": return "class_4_flammable_solids"
        case "5": return "class_5_oxidizers"
        case "6": return "class_6_poisons"
        case "7": return "class_7_radioactive"
        case "8": return "class_8_corrosives"
        default:  return "class_9_miscellaneous"
        }
    }
}

// MARK: - Compass (mirror of degToCompass · weather.ts:2017, read back to degrees)

private enum ES24Compass {
    private static let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                                 "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]

    static func degrees(_ compass: String) -> Double? {
        guard let i = points.firstIndex(of: compass.uppercased()) else { return nil }
        return Double(i) * 22.5
    }

    static func name(_ degrees: Double) -> String {
        let d = (degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        return points[Int((d / 22.5).rounded()) % 16]
    }
}

// MARK: - The polar wind rose (geometry organ — not a map, not a gauge)

private struct ES24WindRose: View {
    let pal: Theme.Palette
    let isDark: Bool
    /// Degrees the wind comes FROM. nil renders the rose UNLIT — a rose without
    /// a bearing must not imply a direction.
    let windFromBearing: Double?
    let lit: Bool

    var body: some View {
        GeometryReader { geo in
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let rOuter = min(geo.size.width, geo.size.height) / 2 - 10
            let rMid = rOuter * 0.656
            let rInner = rOuter * 0.3125

            ZStack {
                if lit, let from = windFromBearing {
                    let downwind = (from + 180).truncatingRemainder(dividingBy: 360)
                    ES24Wedge(centre: c, radius: rOuter, from: downwind - 22.5, to: downwind + 22.5)
                        .fill(ES24Ink.dangerInk(isDark).opacity(isDark ? 0.19 : 0.13))
                }

                Circle().stroke(ES24Ink.dangerInk(isDark).opacity(lit ? 0.35 : 0.14),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: rOuter * 2, height: rOuter * 2)
                Circle().stroke(ES24Ink.warnDot.opacity(lit ? 0.55 : 0.18), lineWidth: 1)
                    .frame(width: rMid * 2, height: rMid * 2)
                Circle().stroke(ES24Ink.dangerInk(isDark).opacity(lit ? 0.75 : 0.22), lineWidth: 1.4)
                    .frame(width: rInner * 2, height: rInner * 2)

                if lit, let from = windFromBearing {
                    // Reciprocal upwind-park arc — DERIVED arithmetic on the bearing.
                    ES24Arc(centre: c, radius: rOuter, from: from - 22.5, to: from + 22.5)
                        .stroke(ES24Ink.successDot.opacity(0.8),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    ES24WindArrow(centre: c, from: from,
                                  tailRadius: rOuter * 1.18, headRadius: rOuter * 0.5)
                        .stroke(ES24Ink.action, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                }

                // §5 — the run-1 brand gradient at the centroid is retired; the
                // load reads as a flat ink mark, not as a second EusoLine.
                Circle().fill(ES24Ink.primary(isDark)).frame(width: 13, height: 13).position(c)

                Text("N").font(ES24Type.body)
                    .foregroundStyle(pal.textTertiary)
                    .position(x: c.x, y: c.y - rOuter - 8)
            }
        }
    }
}

private struct ES24Wedge: Shape {
    let centre: CGPoint; let radius: CGFloat; let from: Double; let to: Double
    func path(in rect: CGRect) -> Path {
        var p = Path(); p.move(to: centre)
        p.addArc(center: centre, radius: radius,
                 startAngle: .degrees(from - 90), endAngle: .degrees(to - 90), clockwise: false)
        p.closeSubpath(); return p
    }
}

private struct ES24Arc: Shape {
    let centre: CGPoint; let radius: CGFloat; let from: Double; let to: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: centre, radius: radius,
                 startAngle: .degrees(from - 90), endAngle: .degrees(to - 90), clockwise: false)
        return p
    }
}

private struct ES24WindArrow: Shape {
    let centre: CGPoint; let from: Double
    let tailRadius: CGFloat; let headRadius: CGFloat
    func path(in rect: CGRect) -> Path {
        let t = from * .pi / 180
        let tail = CGPoint(x: centre.x + tailRadius * sin(t), y: centre.y - tailRadius * cos(t))
        let head = CGPoint(x: centre.x + headRadius * sin(t), y: centre.y - headRadius * cos(t))
        var p = Path(); p.move(to: tail); p.addLine(to: head)
        let dx = head.x - tail.x, dy = head.y - tail.y
        let len = max(0.001, sqrt(dx * dx + dy * dy))
        let ux = dx / len, uy = dy / len
        let base = CGPoint(x: head.x - ux * 9, y: head.y - uy * 9)
        p.move(to: head)
        p.addLine(to: CGPoint(x: base.x - uy * 5, y: base.y + ux * 5))
        p.addLine(to: CGPoint(x: base.x + uy * 5, y: base.y - ux * 5))
        p.closeSubpath(); return p
    }
}

private struct ES24Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath(); return p
    }
}

/// Diagonal hatch. One meaning only on this screen: THIS NUMBER IS NOT EVIDENCE.
private struct ES24Hatch: View {
    let ink: Color
    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 6
            }
            ctx.stroke(p, with: .color(ink.opacity(0.5)), lineWidth: 2)
        }
    }
}

/// A DOT placard is a diamond with a dark border in every light condition, so it
/// does not invert with the theme.
private struct ES24Placard: View {
    let code: String
    let label: String
    let isDark: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.white)
                .overlay(Rectangle().stroke(Color.black.opacity(0.9), lineWidth: 1.5))
                .rotationEffect(.degrees(45))
                .frame(width: 32, height: 32)
            // §3 — the run-1 placard carried its hazard word at 4 pt, the
            // smallest node in the whole band. The word now travels as the
            // accessibility label instead of as unreadable ink; the class
            // number, which is what a placard is actually read for, sits at
            // the 12-pt floor.
            Text(code)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.black.opacity(0.9))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hazard class \(code), \(label)")
    }
}

// MARK: - Registered surface wrapper

struct EscortHazmatWatchScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortHazmatWatch()
        } nav: {
            // §7 — the SHIPPED escort enum, read at the line rather than
            // recited: HOME · ASSIGNMENTS · [ESang orb] · CORRIDOR · ME.
            // `EscortNavRoute.leading` is EscortNavController.swift:77-80 and
            // `.trailing` is :82-85; the orb sits between them at :63. The
            // hazmat watch is a pushed route under ASSIGNMENTS, exactly like
            // ES-02 Height Pole, so ASSIGNMENTS stays current. Nav
            // registration is single-writer owned; this file does not touch
            // EscortNavController.swift.
            BottomNav(
                leading: EscortNavRoute.leading(current: .assignments),
                trailing: EscortNavRoute.trailing(current: .assignments),
                orbState: .idle
            )
        }
    }
}

#Preview("ES-24 · Hazmat Watch · Dark") {
    EscortHazmatWatchScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("ES-24 · Hazmat Watch · Light") {
    EscortHazmatWatchScreen(theme: Theme.light).preferredColorScheme(.light)
}
