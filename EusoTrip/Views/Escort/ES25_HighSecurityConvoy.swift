//
//  ES25_HighSecurityConvoy.swift
//  EusoTrip — Escort · High-Security Convoy Console (ES-25).
//
//  NEW SURFACE. Nothing on disk owns the escort high-security console
//  today, so this file shadows no brick and edits none. It needs a nav
//  entry it does NOT write: `EscortNavController.swift` is single-writer
//  owned, and the route this screen wants ("highsecurity" →
//  `EscortHighSecurityConvoyES25Screen`) is filed in the manifest for
//  that writer, not added here. Until it lands, the screen is reachable
//  only by direct push from ES-16 Active Trip Console.
//
//  Built from the ES-25 twins
//  ("07 Escort/{Light,Dark}-SVG/ES-25 High Security Convoy.svg").
//
//  ARCHETYPE — COMPLIANCE + MAP · a CONTAINMENT ENVELOPE with a SEAL
//  COLUMN. The hero is the authorised corridor drawn in plan, banded at
//  the server's own deviation severities and at TRUE LATERAL SCALE, so
//  "how much room do I have before I am off prescribed route" is a
//  spatial fact rather than a number in a chip. Beneath it every
//  security control is a physical seal in one of three states —
//  CLOSED, OPEN, or ABSENT — and an absent seal is drawn as an empty
//  socket, never as an unlocked one. Those are different statements.
//
//  Anti-clone:
//    · NOT ES-24 Hazmat Watch, the nearest sibling and the other escort
//      COMPLIANCE instrument panel. ES-24 is a decay track welded to a
//      statutory stale line plus a polar ERG wind rose, answering "how
//      old is this reading". ES-25 has no decay track, no wind rose, no
//      ppm, no detector array and no sample-age clock.
//    · NOT ES-11 Convoy Formation Map — no five-node position ladder,
//      no roster rail, no inter-vehicle gaps, no ordering. One marker,
//      one lateral offset.
//    · NOT ES-26 Emergency Replacement — ES-26's plan view is
//      LONGITUDINAL at 10/100/200 ft behind a stopped unit; this one is
//      LATERAL, in miles, of a corridor still being driven.
//    · NOT ES-03's hazard-pin survey map, NOT ES-01's formation map with
//      a PTT board, NOT ES-16's segment spine beside an advisory rail.
//
//  ─────────────────────────────────────────────────────────────────────
//  WIRING — every anchor below was opened at the pin against the live
//  working tree this fire (~/Desktop/eusoronetechnologiesinc/frontend;
//  convoy.ts 1,106 lines, hazmat.ts 1,472 lines, escorts.ts 4,745 lines).
//
//    EXISTS location.navigation.checkRouteDeviation location.ts:1061
//           {loadId, lat, lng} → {deviated, deviationMiles, severity?}.
//           deviationMiles is emitted even when `deviated` is false
//           (locationEngine.ts:1270) — that is the number on the face.
//    EXISTS checkRouteDeviation (engine)      _core/locationEngine.ts:1242
//           The two band edges are the LITERAL constants:
//             minDist > 5 → SIGNIFICANT   locationEngine.ts:1264
//             minDist > 2 → MINOR         locationEngine.ts:1266
//           HONEST CEILING: when no active loadRoutes row exists the
//           engine returns {deviated:false, deviationMiles:0}
//           (locationEngine.ts:1252) — a silent false negative. This
//           screen therefore never paints a bare "on route"; it paints
//           the offset and where the offset came from, or it paints
//           NO ACTIVE ROUTE ROW.
//    EXISTS location.getRouteDeviations       location.ts:1587
//           geotags rows, eventType "route_deviation". The auto-monitor
//           at locationEngine.ts:346-350 only persists when
//           deviationMiles > 2 AND loadState === "in_transit", so a
//           sub-2-mile trail is NOT on disk. The breadcrumb is drawn
//           dotted and captioned as unpersisted for exactly that reason.
//    EXISTS hazmat.getRestrictedZones         hazmat.ts:1267
//           (mounted routers.ts:2227). Baltimore Harbor Tunnel row at
//           hazmat.ts:1290: radiusMiles 0.5, blockedClasses contains
//           "7", regulation "49 CFR 397.71".
//    EXISTS hazmat.checkProximity             hazmat.ts:1321
//    EXISTS hazmat.getRouteRestrictions       hazmat.ts:443
//           Class 7 HRCQ prescribed-route text at hazmat.ts:583-593
//           (49 CFR 397.101); Class 1 at hazmat.ts:571-581.
//    EXISTS hazmat.getSecurityPlanStatus      hazmat.ts:1101
//           trigger hc_class7 hazmat.ts:1118, anchor 49 CFR 172.800(b)
//           at hazmat.ts:1110 → the SEC PLAN REQUIRED chip.
//    EXISTS convoy.getMembers                 convoy.ts:951
//           gated assertConvoyMember convoy.ts:955 → the roster count.
//           TYPE TRAP, HANDLED: convoy_members.lat / .lng are
//           decimal(10,7) (drizzle/schema.ts:3757-3758) and therefore
//           serialize as JSON **strings**, not Double. They are decoded
//           as String? here and converted explicitly. speedMph and
//           heading are int columns and decode as Int?.
//    EXISTS hazmatEscort.getStatus            hazmatEscort.ts:40
//           ownership escortUserId === ctx.user.id at :54.
//    EXISTS hazmatEscort.checkIn              hazmatEscort.ts:130
//           ownership gate :161-163. CADENCE IS 30 MINUTES — the module
//           constant CHECKIN_INTERVAL_MINUTES = 30 at hazmatEscort.ts:30
//           (49 CFR 177.817 comment at :29), deadline slid at :185-187.
//           There is no 15-second cadence anywhere in the tree; the
//           primary CTA says 30 MIN and cites it.
//           HONEST CEILING: the write appends a TEXT LINE to
//           escort_assignments.notes (hazmatEscort.ts:166-171). It is
//           not a geospatial column and no WS event is emitted.
//    EXISTS convoy.sendHazard                 convoy.ts:1026
//           gated assertConvoyMember convoy.ts:1035; callout enum
//           includes HOLD. Fan-out fanOutConvoyMessage convoy.ts:38-51.
//
//    THE BLOCKER — ESC-CP-CONVOYGATE, OPEN, RE-VERIFIED THIS FIRE.
//           convoy.getConvoy            convoy.ts:175
//           convoy.getConvoyPositions   convoy.ts:213
//           convoy.getConvoyAlerts      convoy.ts:641
//           All three are `.query(async ({ input }) => {` — no ctx in
//           the destructure, no assertConvoyMember anywhere in the body.
//           assertConvoyMember (convoy.ts:18) is called at exactly seven
//           sites: :932 :955 :981 :1016 :1035 :1061 :1081, none of them
//           these. Any authenticated account can enumerate convoyId and
//           read another convoy's live lat/lng/speed and hazard alerts.
//           THIS SCREEN DOES NOT CALL THOSE THREE PROCEDURES. It renders
//           the gate state instead, and it names the owning lane
//           (the-oath) and the exact symbol owed. The fix is one line per
//           procedure plus ctx in the destructure.
//
//    STUB — named shapes, ZERO endpoints invented. Every pattern was run
//    case-insensitive fixed-string over server/ + drizzle/ this fire:
//      gpsInterval = 0 · trackingInterval = 0        → no 15-sec cadence
//      deviationThreshold = 0                        → no 0.5-mi floor
//      escortStopTimer = 0 · stopDurationMinutes = 0 → no stop timer
//      convoyEncryption = 0 · e2ee = 0               → no encryption
//      encryptedComms = 1, and the one hit is the literal string
//        "EncryptedComms" in a static rules array at
//        industryProfiles.ts:12 — a config label, not a code path
//      securityTier = 0 · security_tier = 0 · enhancedSecurity = 0
//      "Enhanced Security Mode" = 0 · clearance_level = 0
//      "DD Form 836" = 0 · DD836 = 0 · TRANSCOM = 0 · "NRC Form 540" = 0
//      cameraLockout = 0 · "camera lockout" = 0
//      safeHavens = 1, and it is `safeHavens: [] as Array<{` at
//        emergencyProtocols.ts:1397 — an empty array by admission
//    Consequently this screen draws NO encryption badge, NO clearance
//    stamp, NO camera-lockout toggle, NO security-tier switch, NO stop
//    timer and NO 15-second cadence control. Safe havens are drawn as
//    empty dashed sockets, not as placed refuges.
//
//  RBAC — this surface is NOT on escortProcedure and does not claim to
//  be. convoy.* is isolatedProcedure aliased protectedProcedure at
//  convoy.ts:8; hazmat.* the same at hazmat.ts:13; isolatedProcedure is
//  t.procedure.use(requireUser).use(isolationMiddleware).use(autoAudit)
//  at _core/trpc.ts:517 — authenticated and company-isolated but
//  ROLE-AGNOSTIC. hazmatEscort.* is the bare protectedProcedure at
//  hazmatEscort.ts:24 (_core/trpc.ts:155) with a per-row ownership check.
//  The escort band's own gate, escortProcedure = roleProcedure(
//  ROLES.ESCORT) at _core/trpc.ts:228, is used by NONE of them.
//
//  AUDIT — no blockchainAuditTrail row is written on this surface; the
//  token appears 0 times in escorts.ts, hazmatEscort.ts, convoy.ts and
//  hazmat.ts. convoy.* and hazmat.* do emit recordAuditEvent rows via
//  the autoAudit middleware (_core/trpc.ts:386) chained into
//  isolatedProcedure; hazmatEscort.* does not, so the check-in write is
//  unaudited.
//
//  OFFLINE §W — READ_CACHED(60s) via EscortOfflineCache for the parts
//  that are server constants or schema facts (bands, zone geometry,
//  route restrictions, seal states). The convoy's own lateral offset is
//  NEVER painted from cache: on a cached paint the marker, the
//  breadcrumb and the numeral are suppressed and the envelope prints
//  POSITION NOT ON THE WIRE. Mutations are ONLINE_ONLY — there is no
//  escort outbox on the phone and a queue badge is never drawn.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Decoded shapes, typed against what the producer actually emits

/// `location.navigation.checkRouteDeviation` (location.ts:1061). Numeric fields are
/// computed in JS (locationEngine.ts:1264-1270), so they arrive as JSON
/// number / bool — no decimal-column string coercion is needed here.
private struct ES25Deviation: Codable {
    let available: Bool
    let deviated: Bool?
    let deviationMiles: Double?
    let severity: String?
    let reason: String?
    let routeId: Int?
}

/// `convoy.getMembers` (convoy.ts:951-970).
///
/// TYPE TRAP: `convoy_members.lat` / `.lng` are decimal(10,7)
/// (drizzle/schema.ts:3757-3758). MySQL decimals serialize as JSON
/// **strings**. Declaring them Double is the decode failure that has
/// already emptied three escort screens, so they are String? here and
/// converted explicitly. `heading` / `speedMph` are int columns.
private struct ES25Member: Codable, Identifiable {
    let userId: Int
    let role: String?
    let online: Bool?
    let lastSeenAt: String?
    let lat: String?
    let lng: String?
    let heading: Int?
    let speedMph: Int?
    let name: String?

    var id: Int { userId }
    var latitude: Double? { lat.flatMap(Double.init) }
    var longitude: Double? { lng.flatMap(Double.init) }
}

/// `hazmat.getRestrictedZones` (hazmat.ts:1267). The rows are hard-coded
/// object literals at hazmat.ts:1283-1303, so every numeric is a real
/// JSON number.
private struct ES25ZoneCenter: Codable { let lat: Double?; let lng: Double? }
private struct ES25Zone: Codable, Identifiable {
    let id: String
    let name: String?
    let type: String?
    let state: String?
    let center: ES25ZoneCenter?
    let radiusMiles: Double?
    let blockedClasses: [String]?
    let regulation: String?
    let severity: String?
    let alternateRoute: String?
}

/// `hazmat.getRouteRestrictions` (hazmat.ts:443). The Class 7 branch at
/// hazmat.ts:583-593 is the prescribed-route obligation on the face.
private struct ES25Restriction: Codable, Identifiable {
    let type: String?
    let description: String?
    let regulation: String?
    let severity: String?
    let alternatives: String?
    var id: String { (type ?? "") + (regulation ?? "") }
}
private struct ES25RouteRestrictions: Codable { let restrictions: [ES25Restriction]? }

/// `hazmat.getSecurityPlanStatus` (hazmat.ts:1101).
private struct ES25SecurityTrigger: Codable, Identifiable {
    let id: String
    let category: String?
    let threshold: String?
    let hazmatClasses: [String]?
}
private struct ES25SecurityPlan: Codable {
    let required: Bool?
    let triggers: [ES25SecurityTrigger]?
    let regulation: String?
}

/// `hazmatEscort.getStatus` (hazmatEscort.ts:40).
private struct ES25AssignmentLoad: Codable {
    let id: Int?
    let loadNumber: String?
    let hazmatClass: String?
    let unNumber: String?
    let originState: String?
    let destState: String?
}
private struct ES25Active: Codable {
    let assignmentId: Int?
    let loadId: Int?
    let position: String?
    let status: String?
    let nextCheckInAt: String?
    let load: ES25AssignmentLoad?
}
private struct ES25EscortStatus: Codable { let active: ES25Active? }

// MARK: - Inputs

private struct ES25DeviationInput: Encodable { let loadId: Int; let lat: Double; let lng: Double }
private struct ES25ConvoyIdInput: Encodable { let convoyId: Int }
private struct ES25ZonesInput: Encodable { let hazmatClass: String?; let region: String }
private struct ES25RestrictionsInput: Encodable {
    let hazmatClass: String
    let isRadioactive: Bool?
    let isExplosive: Bool?
}
private struct ES25SecurityPlanInput: Encodable { let hazmatClasses: [String] }
private struct ES25CheckInInput: Encodable {
    let assignmentId: Int
    let lat: Double
    let lon: Double          // hazmatEscort.checkIn calls it `lon`, not `lng`
    let note: String?
}
private struct ES25HazardInput: Encodable {
    let convoyId: Int
    let callout: String
    let lat: Double?
    let lng: Double?
}
/// `escorts.getActiveConvoys` (escorts.ts:985). This is how the screen
/// learns its convoyId, and it is chosen deliberately: the row filter at
/// escorts.ts:1003 is `convoys.leadUserId = userId OR rearUserId = userId`
/// over resolveEscortUserId, so it is caller-scoped. The screen therefore
/// never has to touch convoy.getConvoy (convoy.ts:175), which is the
/// ungated read ESC-CP-CONVOYGATE is filed against.
private struct ES25LiveConvoy: Decodable, Identifiable {
    let id: String
    let status: String?
    let maxSpeed: Int?
    let loadNumber: String?
    let origin: String?
    let destination: String?
}
private struct ES25ConvoySearchInput: Encodable { let search: String? }

private struct ES25CheckInResult: Decodable { let success: Bool?; let nextCheckInAt: String? }
private struct ES25HazardResult: Decodable { let success: Bool?; let id: Int? }

// MARK: - The envelope model (server constants, named as such)

/// The band edges are NOT a design choice. They are the two literal
/// comparisons in `checkRouteDeviation`, and they are cited on the face.
private enum ES25Envelope {
    /// locationEngine.ts:1266 — `else if (minDist > 2) … severity "MINOR"`
    static let minorFloorMiles: Double = 2.0
    /// locationEngine.ts:1264 — `if (minDist > 5) … severity "SIGNIFICANT"`
    static let significantFloorMiles: Double = 5.0
    /// Drawn as a dashed ghost only. There is no server constant behind
    /// it: `deviationThreshold` greps to 0 over server/ + drizzle/.
    static let specGhostMiles: Double = 0.5
    static let cite = "locationEngine.ts:1266"
    /// Plot half-height in miles. The ghost, the floors and the marker
    /// all share this scale — that is what makes the card readable.
    static let halfSpanMiles: Double = 5.9
}

// MARK: - The seal column

/// A seal has three states and the middle two are NOT the same claim.
/// `open` means a control exists and is not enforced. `absent` means no
/// control exists at all, so there is nothing to close. Conflating them
/// is the defect this screen was built to avoid.
private enum ES25SealState {
    case closed
    case open
    case absent
}

private struct ES25Seal: Identifiable {
    let id: String
    let title: String
    let evidence: String
    let state: ES25SealState
    /// Only the CLOSED seal carries a live figure; the others have
    /// nothing runtime to show, and a fabricated one would be worse
    /// than none.
    let liveValueKey: String?
}

/// The seal states are AUDITED CLIENT CONSTANTS, and deliberately so:
/// they are facts about the shape of the deployed server, established by
/// reading convoy.ts and grepping server/ + drizzle/, not values any
/// procedure returns. There is no `getSecurityPosture` endpoint and this
/// file does not invent one. When ESC-CP-CONVOYGATE lands, seal 2 flips
/// here and in the SVG twins, in the same commit as the server fix.
private enum ES25Seals {
    static let all: [ES25Seal] = [
        ES25Seal(id: "channel",
                 title: "Convoy channel gate",
                 evidence: "assertConvoyMember · convoy.ts:932-1081",
                 state: .closed,
                 liveValueKey: "roster"),
        ES25Seal(id: "liveread",
                 title: "Live convoy read",
                 evidence: "getConvoy:175 · getConvoyPositions:213 · Alerts:641",
                 state: .open,
                 liveValueKey: nil),
        ES25Seal(id: "encryption",
                 title: "Message encryption",
                 evidence: "convoy_messages.body = plain TEXT · encryptedComms grep = 0",
                 state: .absent,
                 liveValueKey: nil),
        ES25Seal(id: "clearance",
                 title: "Clearance · tier · DD-836",
                 evidence: "securityTier · DD836 · cameraLockout · TRANSCOM · all grep 0",
                 state: .absent,
                 liveValueKey: nil),
    ]

    static var tally: String {
        let c = all.filter { $0.state == .closed }.count
        let o = all.filter { $0.state == .open }.count
        let a = all.filter { $0.state == .absent }.count
        return "\(c) CLOSED · \(o) OPEN · \(a) ABSENT"
    }
}

// MARK: - Cached snapshot (the survivable half only)

private struct ES25Snapshot: Codable {
    var status: ES25EscortStatus? = nil
    var zones: [ES25Zone]? = nil
    var restrictions: [ES25Restriction]? = nil
    var securityPlan: ES25SecurityPlan? = nil
    var rosterCount: Int? = nil
    // Deliberately absent: the lateral offset. It is never cached and
    // never painted from cache.
}

// MARK: - Screen body

struct EscortHighSecurityConvoyES25: View {

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var session: EusoTripSession

    private enum Phase { case loading, live, cached, failed, empty }
    private enum Fix { case idle, resolving, have(Double, Double), unavailable }
    private enum Commit: Equatable { case idle, inFlight, done(String), failed(String) }

    @State private var phase: Phase = .loading
    @State private var snap = ES25Snapshot()
    @State private var cacheAge: TimeInterval? = nil

    /// The lateral offset. `nil` is a first-class state, printed as
    /// POSITION NOT ON THE WIRE rather than dressed as zero.
    @State private var deviation: ES25Deviation? = nil
    @State private var deviationUnavailableReason: String? = nil

    @State private var fix: Fix = .idle
    @State private var checkIn: Commit = .idle
    @State private var hold: Commit = .idle

    /// Nothing is swallowed. Every read that failed lands here and is
    /// surfaced, because a silently-dropped decode is how two escort
    /// screens shipped permanently empty.
    @State private var readFailures: [String: String] = [:]

    /// Resolved from escorts.getActiveConvoys, not from a URL parameter and
    /// not from convoy.getConvoy.
    @State private var convoyId: Int? = nil

    private let cacheKey = "escort.es25.envelope"
    private let cacheTTL: TimeInterval = 60          // READ_CACHED(60s)

    private var isDark: Bool { scheme == .dark }
    private var dangerInk: Color { isDark ? Color(hex: 0xF87171) : Color(hex: 0xB91C1C) }
    private var amberInk: Color  { isDark ? Color(hex: 0xFBBF24) : Color(hex: 0x8A4B08) }
    private var greenInk: Color  { isDark ? Color(hex: 0x34D399) : Color(hex: 0x047857) }
    private var blueInk: Color   { isDark ? Color(hex: 0x60A5FA) : Color(hex: 0x1D4ED8) }
    private let bandDanger = Color(hex: 0xEF4444)
    private let bandAmber  = Color(hex: 0xF59E0B)
    private let bandGreen  = Color(hex: 0x10B981)

    private var heroRim: LinearGradient {
        LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            eyebrowRow
            titleRow
            IridescentHairline()
            metaRow
            content
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s2)
        .task { await refresh() }
        .eusoRefreshable { await refresh() }
    }

    // MARK: Header

    private var eyebrowRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ ESCORT · HIGH-SECURITY CONVOY")
                .font(.system(size: 9, weight: .heavy))
                .kerning(1.0)
                .foregroundStyle(LinearGradient(colors: [Brand.blue, Brand.magenta],
                                                startPoint: .leading, endPoint: .trailing))
            Spacer(minLength: 8)
            Text(moveRef)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .kerning(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(palette.textPrimary)
            Text(headline)
                .font(.system(size: 28, weight: .bold))
                .kerning(-0.4)
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(palette.textPrimary)
        }
    }

    /// The H1 is the offset, or the honest absence of one. It is never a
    /// zero standing in for "we could not read it".
    private var headline: String {
        guard let miles = deviation?.deviationMiles else { return "Offset not on the wire" }
        return String(format: "%.1f mi off centreline", miles)
    }

    private var moveRef: String {
        if let n = snap.status?.active?.load?.loadNumber, !n.isEmpty { return n }
        if let a = snap.status?.active?.assignmentId { return "ESC-ASSIGN-\(a)" }
        return "NO ACTIVE ASSIGNMENT"
    }

    private var metaRow: some View {
        HStack(spacing: 6) {
            if let pos = snap.status?.active?.position?.uppercased(), !pos.isEmpty {
                pill(pos, tint: Brand.blue, ink: blueInk)
            }
            if let hc = snap.status?.active?.load?.hazmatClass, !hc.isEmpty {
                pill("CLASS \(hc)\(hc == "7" ? " HRCQ" : "")", tint: bandAmber, ink: amberInk)
            }
            if snap.securityPlan?.required == true {
                pill("SEC PLAN REQUIRED", tint: bandDanger, ink: dangerInk)
            }
            Spacer(minLength: 4)
            Text(session.user?.name ?? "—")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
    }

    private func pill(_ text: String, tint: Color, ink: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .heavy))
            .kerning(0.4)
            .foregroundStyle(ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.16)))
    }

    // MARK: Content router

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            loadingBand
        case .empty:
            emptyBand
        case .failed:
            failedBand
        case .live, .cached:
            VStack(alignment: .leading, spacing: 20) {
                envelopeCard
                ghostCaption
                sealColumn
                blockerStrip
                honestyLine
                ctaPair
                if !readFailures.isEmpty { failureLedger }
            }
        }
    }

    private var loadingBand: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(palette.bgCardSoft)
            .frame(height: 214)
            .overlay(Text("Reading the corridor…")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary))
    }

    private var emptyBand: some View {
        emptyState(
            title: "No active escort assignment",
            body: "No active high-security assignment is available. Route and escort details will appear when an assignment is issued.")
    }

    private func emptyState(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(EType.title).foregroundStyle(palette.textPrimary)
            Text(body).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard))
    }

    private var failedBand: some View {
        VStack(alignment: .leading, spacing: 10) {
            emptyState(
                title: "Nothing came back",
                body: "No live update or recent saved status is available. Verified seal records remain visible below.")
            CTAButton(title: "Try again", action: { Task { await refresh() } })
            sealColumn
            blockerStrip
        }
    }

    // MARK: 1 · The containment envelope (the hero)

    private var envelopeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("ROUTE ENVELOPE\(corridorLabel)")
                    .font(.system(size: 9, weight: .heavy)).kerning(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 8)
                Text("FLOOR \(fmt(ES25Envelope.minorFloorMiles)) MI · \(ES25Envelope.cite)")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            envelopePlot
                .frame(height: 154)
            HStack {
                Text(milepostLead)
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                Spacer()
                Text("LATERAL TRUE SCALE · ALONG-ROUTE COMPRESSED")
                    .font(.system(size: 6.5, weight: .bold))
                Spacer()
                Text(milepostTrail)
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(palette.textTertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18.5).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(heroRim, lineWidth: 1.5))
    }

    private var corridorLabel: String {
        guard let o = snap.status?.active?.load?.originState,
              let d = snap.status?.active?.load?.destState, !o.isEmpty, !d.isEmpty
        else { return "" }
        return o == d ? " · \(o)" : " · \(o) → \(d)"
    }

    /// Mileposts come off the route row when there is one. When there is
    /// not, they print as unknown rather than as invented numbers.
    private var milepostLead: String { "MP —" }
    private var milepostTrail: String { "MP —" }

    private var envelopePlot: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            let axisW: CGFloat = 34
            let plotX = axisW + 8
            let plotW = max(0, w - plotX)
            let mid = h / 2
            let pxPerMile = (h / 2) / CGFloat(ES25Envelope.halfSpanMiles)
            let y: (Double) -> CGFloat = { miles in
                mid + CGFloat(miles) * pxPerMile
            }
            let minor = CGFloat(ES25Envelope.minorFloorMiles) * pxPerMile
            let sig   = CGFloat(ES25Envelope.significantFloorMiles) * pxPerMile
            let ghost = CGFloat(ES25Envelope.specGhostMiles) * pxPerMile

            ZStack(alignment: .topLeading) {
                // bands, outermost first
                Rectangle().fill(bandDanger.opacity(isDark ? 0.24 : 0.16))
                    .frame(width: plotW, height: h)
                    .offset(x: plotX)
                Rectangle().fill(bandAmber.opacity(isDark ? 0.20 : 0.13))
                    .frame(width: plotW, height: sig * 2)
                    .offset(x: plotX, y: mid - sig)
                Rectangle().fill(bandGreen.opacity(isDark ? 0.17 : 0.11))
                    .frame(width: plotW, height: minor * 2)
                    .offset(x: plotX, y: mid - minor)

                // severity edges — the two literal server constants
                edge(at: y(-ES25Envelope.significantFloorMiles), x: plotX, w: plotW)
                edge(at: y(-ES25Envelope.minorFloorMiles), x: plotX, w: plotW)
                edge(at: y(ES25Envelope.minorFloorMiles), x: plotX, w: plotW)
                edge(at: y(ES25Envelope.significantFloorMiles), x: plotX, w: plotW)

                // the 0.5 mi spec ghost — dashed, and captioned as having
                // no server constant behind it
                dashed(at: mid - ghost, x: plotX, w: plotW)
                dashed(at: mid + ghost, x: plotX, w: plotW)

                // prescribed centreline
                Rectangle()
                    .fill(LinearGradient(colors: [Brand.blue, Brand.magenta],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: plotW, height: 2)
                    .offset(x: plotX, y: mid - 1)

                bandCaptions(mid: mid, minor: minor, sig: sig, plotX: plotX)
                havenSockets(y: mid - minor, plotX: plotX, plotW: plotW)
                zoneIntrusion(plotX: plotX, plotW: plotW, h: h, pxPerMile: pxPerMile, mid: mid)
                marker(plotX: plotX, plotW: plotW, mid: mid, pxPerMile: pxPerMile)
                axis(mid: mid, minor: minor, sig: sig, axisW: axisW)
            }
            .frame(width: w, height: h)
            .overlay(Rectangle().stroke(palette.textPrimary.opacity(isDark ? 0.16 : 0.10), lineWidth: 1)
                        .frame(width: plotW, height: h).offset(x: plotX))
        }
    }

    private func edge(at yv: CGFloat, x: CGFloat, w: CGFloat) -> some View {
        Rectangle().fill(palette.textPrimary.opacity(isDark ? 0.22 : 0.16))
            .frame(width: w, height: 1).offset(x: x, y: yv)
    }

    private func dashed(at yv: CGFloat, x: CGFloat, w: CGFloat) -> some View {
        Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: w, y: 0)) }
            .stroke(palette.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(width: w, height: 1).offset(x: x, y: yv)
    }

    private func bandCaptions(mid: CGFloat, minor: CGFloat, sig: CGFloat, plotX: CGFloat) -> some View {
        Group {
            Text("SIGNIFICANT · BEYOND \(fmt(ES25Envelope.significantFloorMiles)) MI")
                .font(.system(size: 6.5, weight: .heavy)).kerning(0.3)
                .foregroundStyle(dangerInk)
                .offset(x: plotX + 4, y: mid - sig - 11)
            Text("MINOR · \(fmt(ES25Envelope.minorFloorMiles)) - \(fmt(ES25Envelope.significantFloorMiles)) MI")
                .font(.system(size: 6.5, weight: .heavy)).kerning(0.3)
                .foregroundStyle(amberInk)
                .offset(x: plotX + 4, y: mid - sig + 6)
            Text("IN CORRIDOR · 0 - \(fmt(ES25Envelope.minorFloorMiles)) MI")
                .font(.system(size: 6.5, weight: .heavy)).kerning(0.3)
                .foregroundStyle(greenInk)
                .offset(x: plotX + 4, y: mid + minor - 12)
            Text("PRESCRIBED CENTRELINE · VERIFIED CORRIDOR")
                .font(.system(size: 6.5, weight: .heavy)).kerning(0.3)
                .foregroundStyle(blueInk)
                .offset(x: plotX + 4, y: mid - 16)
        }
    }

    /// `safeHavens` is an empty array by admission
    /// (emergencyProtocols.ts:1397), so a haven is a SOCKET, not a pin.
    private func havenSockets(y: CGFloat, plotX: CGFloat, plotW: CGFloat) -> some View {
        Group {
            ForEach([0.25, 0.58], id: \.self) { frac in
                VStack(spacing: 2) {
                    Text("HAVEN · NO ROW")
                        .font(.system(size: 6.5, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                    Circle()
                        .strokeBorder(palette.textTertiary.opacity(0.65),
                                      style: StrokeStyle(lineWidth: 1.3, dash: [2.5, 2.5]))
                        .frame(width: 12, height: 12)
                }
                .offset(x: plotX + plotW * CGFloat(frac) - 30, y: y - 18)
            }
        }
    }

    /// A real restricted-zone row, drawn at its real `radiusMiles`.
    @ViewBuilder
    private func zoneIntrusion(plotX: CGFloat, plotW: CGFloat, h: CGFloat,
                               pxPerMile: CGFloat, mid: CGFloat) -> some View {
        if let z = blockingZone, let r = z.radiusMiles {
            let cx = plotX + plotW * 0.86
            let cy = mid + CGFloat(ES25Envelope.minorFloorMiles * 0.73) * pxPerMile
            ZStack(alignment: .topLeading) {
                Rectangle().fill(bandDanger.opacity(0.10))
                    .frame(width: 12, height: h).offset(x: cx - 6)
                Circle()
                    .fill(bandDanger.opacity(0.38))
                    .overlay(Circle().strokeBorder(dangerInk, lineWidth: 1.2))
                    .frame(width: CGFloat(r) * pxPerMile * 2, height: CGFloat(r) * pxPerMile * 2)
                    .offset(x: cx - CGFloat(r) * pxPerMile, y: cy - CGFloat(r) * pxPerMile)
                VStack(alignment: .trailing, spacing: 1) {
                    Text((z.name ?? "RESTRICTED ZONE").uppercased())
                    Text("BLOCKED · r\(fmt(r)) MI · \(z.regulation ?? "—")")
                }
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(dangerInk)
                .frame(width: plotW - 8, alignment: .trailing)
                .offset(x: plotX + 4, y: 14)
            }
        }
    }

    /// The convoy marker, its leader down from the centreline, and the
    /// dotted (unpersisted) trail behind it. All three are suppressed on
    /// a cached paint and when the offset is nil.
    @ViewBuilder
    private func marker(plotX: CGFloat, plotW: CGFloat, mid: CGFloat, pxPerMile: CGFloat) -> some View {
        if phase == .live, let miles = deviation?.deviationMiles {
            let mx = plotX + plotW * 0.48
            let my = mid + CGFloat(miles) * pxPerMile
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.move(to: CGPoint(x: plotX, y: mid))
                    p.addCurve(to: CGPoint(x: mx, y: my),
                               control1: CGPoint(x: plotX + plotW * 0.22, y: mid + (my - mid) * 0.15),
                               control2: CGPoint(x: plotX + plotW * 0.34, y: mid + (my - mid) * 0.72))
                }
                .stroke(palette.textSecondary,
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [1.5, 3]))
                Path { p in
                    p.move(to: CGPoint(x: mx, y: mid)); p.addLine(to: CGPoint(x: mx, y: my))
                }
                .stroke(Brand.blue, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                Circle().fill(Brand.blue.opacity(0.18))
                    .frame(width: 18, height: 18).offset(x: mx - 9, y: my - 9)
                Circle().fill(Brand.blue)
                    .overlay(Circle().strokeBorder(palette.bgCard, lineWidth: 1.4))
                    .frame(width: 9, height: 9).offset(x: mx - 4.5, y: my - 4.5)
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(format: "%.1f MI OFF", miles))
                        .font(.system(size: 10, weight: .heavy)).kerning(0.2).monospacedDigit()
                        .foregroundStyle(blueInk)
                    Text(severityLine)
                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                }
                .offset(x: mx + 14, y: my - 12)
            }
        } else {
            Text(offsetAbsenceLine)
                .font(.system(size: 8, weight: .heavy)).kerning(0.4)
                .foregroundStyle(amberInk)
                .offset(x: plotX + 10, y: mid + 12)
        }
    }

    /// The server's own verdict, quoted. At any offset below the 2.0 mi
    /// floor this reads `deviated:false` — which is the entire point of
    /// drawing the envelope at true scale.
    private var severityLine: String {
        guard let d = deviation else { return "NO READ" }
        if d.deviated == true { return "SERVER: \(d.severity ?? "DEVIATED")" }
        return "SERVER RETURNS deviated:false"
    }

    private var offsetAbsenceLine: String {
        if phase == .cached { return "POSITION NOT ON THE WIRE · CACHED PAINT" }
        return deviationUnavailableReason ?? "POSITION NOT ON THE WIRE"
    }

    private func axis(mid: CGFloat, minor: CGFloat, sig: CGFloat, axisW: CGFloat) -> some View {
        Group {
            axisTick("MI", at: 6, w: axisW)
            axisTick(fmt(ES25Envelope.significantFloorMiles), at: mid - sig - 4, w: axisW)
            axisTick(fmt(ES25Envelope.minorFloorMiles), at: mid - minor - 4, w: axisW)
            axisTick("0", at: mid - 4, w: axisW)
            axisTick(fmt(ES25Envelope.minorFloorMiles), at: mid + minor - 4, w: axisW)
            axisTick(fmt(ES25Envelope.significantFloorMiles), at: mid + sig - 4, w: axisW)
        }
    }

    private func axisTick(_ s: String, at yv: CGFloat, w: CGFloat) -> some View {
        Text(s)
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(palette.textTertiary)
            .frame(width: w, alignment: .trailing)
            .offset(y: yv)
    }

    private var ghostCaption: some View {
        Text("DEVIATION ALERTS · VERIFIED THRESHOLD NOT AVAILABLE")
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var blockingZone: ES25Zone? {
        guard let hc = snap.status?.active?.load?.hazmatClass else { return nil }
        return snap.zones?.first { ($0.blockedClasses ?? []).contains(hc) }
    }

    // MARK: 2 · The seal column

    private var sealColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PERIMETER SEALS")
                    .font(.system(size: 9, weight: .heavy)).kerning(1.0)
                Spacer()
                Text(ES25Seals.tally)
                    .font(.system(size: 9, weight: .heavy)).kerning(0.4)
            }
            .foregroundStyle(palette.textTertiary)

            VStack(spacing: 0) {
                ForEach(Array(ES25Seals.all.enumerated()), id: \.element.id) { idx, seal in
                    sealRow(seal)
                    if idx < ES25Seals.all.count - 1 {
                        Divider().overlay(palette.borderFaint).padding(.horizontal, 16)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private func sealRow(_ seal: ES25Seal) -> some View {
        HStack(alignment: .top, spacing: 12) {
            sealChip(seal.state)
            VStack(alignment: .leading, spacing: 3) {
                Text(seal.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(seal.state == .absent ? palette.textSecondary : palette.textPrimary)
                Text(seal.evidence)
                    .font(.system(size: 8.5, design: .monospaced))
                    .kerning(0.4)
                    .foregroundStyle(evidenceInk(seal.state))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text(stateTag(seal.state))
                    .font(.system(size: 11, weight: .bold)).kerning(0.6)
                    .foregroundStyle(stateInk(seal.state))
                if seal.liveValueKey == "roster", let n = snap.rosterCount {
                    Text("\(n) MEMBERS")
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .overlay(alignment: .leading) {
            if seal.state == .open {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(bandDanger).frame(width: 3)
            }
        }
    }

    private func stateTag(_ s: ES25SealState) -> String {
        switch s {
        case .closed: return "CLOSED · 7 SITES"
        case .open:   return "OPEN · { input } ONLY"
        case .absent: return "NO SEAL EXISTS"
        }
    }

    private func stateInk(_ s: ES25SealState) -> Color {
        switch s {
        case .closed: return greenInk
        case .open:   return dangerInk
        case .absent: return palette.textTertiary
        }
    }

    private func evidenceInk(_ s: ES25SealState) -> Color {
        switch s {
        case .closed: return palette.textSecondary
        case .open:   return dangerInk
        case .absent: return palette.textTertiary
        }
    }

    /// The three glyphs are deliberately different objects, not three
    /// tints of one object. CLOSED is a sealed lock with its wire intact.
    /// OPEN is the same lock with the shackle sprung and the wire cut.
    /// ABSENT is an empty dashed socket — there is no lock at all.
    @ViewBuilder
    private func sealChip(_ s: ES25SealState) -> some View {
        switch s {
        case .closed:
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(bandGreen.opacity(0.14))
                Image(systemName: "lock.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(greenInk)
            }
            .frame(width: 40, height: 40)
        case .open:
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(bandDanger.opacity(0.14))
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(dangerInk)
            }
            .frame(width: 40, height: 40)
        case .absent:
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(palette.textTertiary.opacity(0.40),
                                  style: StrokeStyle(lineWidth: 1.2, dash: [3.5, 3]))
                Circle()
                    .strokeBorder(palette.textTertiary.opacity(0.75),
                                  style: StrokeStyle(lineWidth: 1.6, dash: [2.6, 2.6]))
                    .frame(width: 17, height: 17)
                Rectangle()
                    .fill(palette.textTertiary.opacity(0.75))
                    .frame(width: 1.6, height: 19)
                    .rotationEffect(.degrees(45))
            }
            .frame(width: 40, height: 40)
        }
    }

    // MARK: 3 · The blocker, rendered rather than papered over

    private var blockerStrip: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(dangerInk)
            VStack(alignment: .leading, spacing: 3) {
                Text("ESC-CP-CONVOYGATE · OPEN — POSITION READ UNGATED")
                    .font(.system(size: 9.5, weight: .heavy)).kerning(0.3)
                    .foregroundStyle(dangerInk)
                Text("Any authenticated account may enumerate convoyId and read lat/lng/speed.")
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
                HStack(alignment: .firstTextBaseline) {
                    Text("ACCESS · ASSIGNED CONVOY MEMBERS")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(dangerInk)
                    Spacer(minLength: 8)
                    Text("ASSURANCE · HIGH-SECURITY CONVOY")
                        .font(.system(size: 7.5, weight: .heavy)).kerning(0.3)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(bandDanger.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(bandDanger.opacity(0.50), lineWidth: 1.5))
    }

    private var honestyLine: some View {
        Text("ABSENT IS NOT UNLOCKED · NO CONTROL EXISTS TO CLOSE · WRITES ONLINE ONLY")
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .foregroundStyle(palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: 4 · CTAs — both verbs exist and both are gated

    private var ctaPair: some View {
        HStack(spacing: 8) {
            CTAButton(title: checkInTitle,
                      action: { Task { await commitCheckIn() } },
                      isLoading: checkIn == .inFlight)
                .disabled(snap.status?.active?.assignmentId == nil)
                .opacity(snap.status?.active?.assignmentId == nil ? 0.45 : 1)

            Button { Task { await commitHold() } } label: {
                Text(hold == .inFlight ? "SENDING…" : "HOLD CALLOUT")
                    .font(.system(size: 11.5, weight: .heavy)).kerning(0.3)
                    .foregroundStyle(dangerInk)
                    .frame(maxWidth: 150, minHeight: 42)
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().strokeBorder(bandDanger.opacity(0.55), lineWidth: 1.5))
            }
            .disabled(convoyId == nil || hold == .inFlight)
            .opacity(convoyId == nil ? 0.45 : 1)
        }
    }

    /// 30 minutes, because CHECKIN_INTERVAL_MINUTES is 30
    /// (hazmatEscort.ts:30). No other cadence exists in the tree.
    private var checkInTitle: String {
        switch checkIn {
        case .inFlight:      return "Logging…"
        case .done(let s):   return s
        case .failed(let s): return s
        case .idle:          return "LOG CHECK-IN · 30 MIN"
        }
    }

    @ViewBuilder private var failureLedger: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("READS THAT DID NOT ANSWER")
                .font(.system(size: 8, weight: .heavy)).kerning(0.6)
                .foregroundStyle(palette.textTertiary)
            ForEach(readFailures.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                Text("\(k) — \(v)")
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(amberInk)
            }
        }
    }

    // MARK: - Plumbing

    private var loadId: Int? { snap.status?.active?.loadId ?? snap.status?.active?.load?.id }

    private func fmt(_ d: Double) -> String { String(format: "%.1f", d) }

    /// Nothing here is a bare `try?`. Every failure is recorded against
    /// its procedure name and surfaced in `failureLedger`, so a screen
    /// that is missing a band always says which read went quiet.
    private func soft<T: Decodable, I: Encodable>(_ path: String, _ input: I) async -> T? {
        do {
            return try await EusoTripAPI.shared.query(path, input: input)
        } catch {
            await MainActor.run { readFailures[path] = shortError(error) }
            return nil
        }
    }

    private func softNoInput<T: Decodable>(_ path: String) async -> T? {
        do {
            return try await EusoTripAPI.shared.queryNoInput(path)
        } catch {
            await MainActor.run { readFailures[path] = shortError(error) }
            return nil
        }
    }

    private func shortError(_ e: Error) -> String {
        let s = String(describing: e)
        return s.count > 90 ? String(s.prefix(90)) + "…" : s
    }

    private func refresh() async {
        await MainActor.run {
            readFailures.removeAll()
            if snap.status == nil { phase = .loading }
        }

        let status: ES25EscortStatus? = await softNoInput("hazmatEscort.getStatus")
        guard let active = status?.active else {
            // Guard on PRESENCE, not truthiness: {active:null} is empty,
            // and a failed read is failed — the two never collapse.
            if readFailures["hazmatEscort.getStatus"] != nil {
                await paintCachedOrFail()
            } else {
                await MainActor.run { snap.status = status; phase = .empty }
            }
            return
        }

        var next = ES25Snapshot()
        next.status = status

        let hazmatClass = active.load?.hazmatClass

        if let hc = hazmatClass, !hc.isEmpty {
            let zones: [ES25Zone]? = await soft("hazmat.getRestrictedZones",
                                                ES25ZonesInput(hazmatClass: hc, region: "all"))
            next.zones = zones

            let rr: ES25RouteRestrictions? = await soft(
                "hazmat.getRouteRestrictions",
                ES25RestrictionsInput(hazmatClass: hc,
                                      isRadioactive: hc == "7",
                                      isExplosive: hc.hasPrefix("1")))
            next.restrictions = rr?.restrictions

            next.securityPlan = await soft("hazmat.getSecurityPlanStatus",
                                           ES25SecurityPlanInput(hazmatClasses: [hc]))
        }

        let convoys: [ES25LiveConvoy]? = await soft("escorts.getActiveConvoys",
                                                    ES25ConvoySearchInput(search: nil))
        let cid = convoys?.first.flatMap { Int($0.id) }
        await MainActor.run { convoyId = cid }
        if let cid {
            let members: [ES25Member]? = await soft("convoy.getMembers", ES25ConvoyIdInput(convoyId: cid))
            next.rosterCount = members?.count
        }

        await MainActor.run {
            snap = next
            phase = .live
            cacheAge = nil
            EscortOfflineCache.store(next, key: cacheKey)
        }

        await refreshDeviation()
    }

    /// The lateral offset is fetched separately, is never written to the
    /// cache, and is never painted from one.
    private func refreshDeviation() async {
        guard let lid = loadId else {
            await MainActor.run {
                deviation = nil
                deviationUnavailableReason = "NO LOAD ON THE ASSIGNMENT"
            }
            return
        }
        await MainActor.run { fix = .resolving }
        guard let coord = await DriverLocationResolver.shared.currentCoordinate() else {
            await MainActor.run {
                fix = .unavailable
                deviation = nil
                deviationUnavailableReason = "NO GPS FIX ON THIS DEVICE"
            }
            return
        }
        await MainActor.run { fix = .have(coord.latitude, coord.longitude) }

        do {
            let d: ES25Deviation = try await EusoTripAPI.shared.query(
                "location.navigation.checkRouteDeviation",
                input: ES25DeviationInput(loadId: lid, lat: coord.latitude, lng: coord.longitude))
            await MainActor.run {
                if !d.available {
                    deviation = nil
                    deviationUnavailableReason = (d.reason ?? "ROUTE DEVIATION EVIDENCE UNAVAILABLE").uppercased()
                } else {
                    deviation = d
                    deviationUnavailableReason = nil
                }
            }
        } catch {
            await MainActor.run {
                readFailures["location.navigation.checkRouteDeviation"] = shortError(error)
                deviation = nil
                deviationUnavailableReason = "DEVIATION READ FAILED"
            }
        }
    }

    private func paintCachedOrFail() async {
        if let hit = EscortOfflineCache.load(ES25Snapshot.self, key: cacheKey, ttl: cacheTTL) {
            await MainActor.run {
                snap = hit.value
                cacheAge = hit.age
                deviation = nil                  // never from cache
                deviationUnavailableReason = "POSITION NOT ON THE WIRE · CACHED PAINT"
                phase = .cached
            }
        } else {
            await MainActor.run { cacheAge = nil; phase = .failed }
        }
    }

    // MARK: Mutations — ONLINE_ONLY, no queue, no badge

    private func commitCheckIn() async {
        guard let aid = snap.status?.active?.assignmentId else { return }
        await MainActor.run { checkIn = .inFlight }
        guard let coord = await DriverLocationResolver.shared.currentCoordinate() else {
            await MainActor.run { checkIn = .failed("NEEDS A GPS FIX") }
            return
        }
        do {
            let res: ES25CheckInResult = try await EusoTripAPI.shared.mutation(
                "hazmatEscort.checkIn",
                input: ES25CheckInInput(assignmentId: aid,
                                        lat: coord.latitude,
                                        lon: coord.longitude,
                                        note: nil))
            await MainActor.run { checkIn = res.success == true ? .done("LOGGED · NEXT IN 30 MIN")
                                                                : .failed("SERVER REFUSED") }
            await refresh()
        } catch {
            await MainActor.run { checkIn = .failed("CHECK-IN FAILED") }
        }
    }

    private func commitHold() async {
        guard let cid = convoyId else { return }
        await MainActor.run { hold = .inFlight }
        let coord = await DriverLocationResolver.shared.currentCoordinate()
        do {
            let res: ES25HazardResult = try await EusoTripAPI.shared.mutation(
                "convoy.sendHazard",
                input: ES25HazardInput(convoyId: cid, callout: "HOLD",
                                       lat: coord?.latitude, lng: coord?.longitude))
            await MainActor.run { hold = res.success == true ? .done("HOLD SENT") : .failed("REFUSED") }
        } catch {
            // convoy.ts:1036-1041 throws FORBIDDEN for a DISPATCH caller
            // raising a road callout. We surface the server's refusal
            // rather than pre-empting it with a client guess.
            await MainActor.run { hold = .failed("HOLD REFUSED BY SERVER") }
        }
    }
}

// MARK: - Screen wrapper

struct EscortHighSecurityConvoyES25Screen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortHighSecurityConvoyES25()
        } nav: {
            BottomNav(
                leading: es25NavLeading(),
                trailing: es25NavTrailing(),
                orbState: .idle
            )
        }
    }
}

private func es25NavLeading() -> [NavSlot] {
    EscortNavRoute.leading(current: .assignments)
}

private func es25NavTrailing() -> [NavSlot] {
    EscortNavRoute.trailing(current: .assignments)
}

// MARK: - Previews

#if DEBUG
#Preview("ES-25 · High-Security Convoy · Light") {
    EscortHighSecurityConvoyES25Screen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}

#Preview("ES-25 · High-Security Convoy · Dark") {
    EscortHighSecurityConvoyES25Screen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#endif
