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
//    REAL  escorts.getLowClearanceProximity escorts.ts:4335 — bridge COVERAGE,
//                                            reported honestly (see below).
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
//    surfaceBandForCode (escorts.ts:297 — 4xxx wet, 5xxx snow, 6xxx/7xxx ice).
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
//    green. Absence of coverage is not absence of hazard.
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
//    EscortOfflineCache for the spine and trip header. While a snapshot is
//    painted the staleness line REPLACES the live GPS dot and the advisory rail
//    dims to CACHED, and the wind matrix refuses to light a verdict cell — a
//    stale wind reading presented as live is the exact failure this screen
//    exists to prevent.
//
//  CHAIN: reads CLOSED. updateTripStatus is ONE-SIDED — it persists and closes
//    the convoy row but emits no WebSocket event and writes no audit row, so
//    dispatch and the haul driver never learn the escort went on site. Named
//    for the-oath, not papered over.
//
//  RBAC: registered role .escort only; every procedure resolves the caller's own
//  assignment server-side (resolveEscortUserId escorts.ts:138). No loads.rate,
//  no shipper margin, no other driver's HOS reaches this surface.
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
    let loadId: Int; let lat: Double; let lng: Double
    let poleHeightFt: Double; let radiusMi: Double
}

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

private struct ES16Proximity: Codable, Equatable {
    let distanceMeters: Double?
    let warningThresholdMeters: Double?
    let status: String?
    let convoyMaxSpeed: Int?
}

private struct ES16ClearanceEvent: Codable, Identifiable, Equatable {
    let id: Int
    let eventType: String
    let structureName: String?
    let postedClearanceFt: Double?
    let measuredClearanceFt: Double?
    let occurredAt: String?
}

/// `getLowClearanceProximity` — bridgesChecked == 0 is the discriminator this
/// screen exists to respect.
private struct ES16BridgeCoverage: Codable, Equatable {
    let bridgesChecked: Int
    let datasetRows: Int
    let coverageRadiusMi: Double
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
}

// MARK: - Advisory source state — part of the data, on purpose

private enum ES16Source: Equatable {
    case live, derived, notEvaluated, stub
    var tag: String {
        switch self {
        case .live: return "LIVE"
        case .derived: return "DERIVED"
        case .notEvaluated: return "0 CHECKED"
        case .stub: return "STUB"
        }
    }
    var dashed: Bool { self == .stub }
}

private struct ES16Advisory: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
    let source: ES16Source
    let tint: Color
    var tagOverride: String? = nil
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
    var label: String {
        switch self {
        case .lead: return "LEAD"
        case .chase: return "CHASE"
        case .steer: return "STEER"
        case .highPole: return "HIGH-POLE"
        }
    }
    var ink: Color {
        switch self {
        case .lead: return Brand.blue
        case .chase: return Brand.escort
        case .steer: return Brand.warning
        case .highPole: return Brand.hazmat
        }
    }
}

// MARK: - Screen

struct EscortActiveTripConsole: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    @State private var trip: ES16Trip?
    @State private var corridor: ES16Corridor?
    @State private var restrictions: ES16Restrictions?
    @State private var proximity: ES16Proximity?
    @State private var events: [ES16ClearanceEvent] = []
    @State private var bridge: ES16BridgeCoverage?

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
                    LifecycleCard { Text("Reading the corridor…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if trip == nil {
                    noActiveMove
                } else {
                    if let errorMessage {
                        Text(errorMessage).font(EType.caption).foregroundStyle(Brand.danger)
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
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ESCORT · ACTIVE TRIP").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer()
                if let a = trip?.assignmentId {
                    Text("ASSIGNMENT \(a)").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Text(corridorLedger).font(EType.mono(.micro))
                .foregroundStyle(palette.textSecondary).lineLimit(1)
            Text(headlineText).font(.system(size: 27, weight: .bold)).tracking(-0.6)
                .foregroundStyle(LinearGradient.diagonal).lineLimit(1).minimumScaleFactor(0.8)
            Text(subheadText).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            metaRow
            IridescentHairline()
        }
    }

    private var corridorLedger: String {
        let load = trip?.load?.loadNumber ?? "—"
        let o = corridor?.origin ?? trip?.load?.origin?.label ?? "—"
        let d = corridor?.destination ?? trip?.load?.destination?.label ?? "—"
        return "\(load) · \(o.uppercased()) → \(d.uppercased())"
    }
    private var headlineText: String {
        guard let leg = activeLeg, let remaining = milesRemainingOnActiveLeg else {
            return corridor == nil ? "Corridor unavailable" : "Between segments"
        }
        return "\(remaining.formatted(.number.precision(.fractionLength(1)))) mi to \(leg.destination ?? "next node")"
    }
    private var subheadText: String {
        guard let leg = activeLeg else { return "—" }
        let total = corridor?.legsTotal ?? (corridor?.legs.count ?? 0)
        let status = (trip?.assignmentStatus ?? "").replacingOccurrences(of: "_", with: " ")
        return "Segment \(legIndex(leg)) of \(total) · \(status)"
    }

    private var metaRow: some View {
        HStack(spacing: Space.s3) {
            let pos = ES16Position(wire: trip?.position)
            Text(pos.label).font(.system(size: 10, weight: .heavy)).tracking(0.5)
                .foregroundStyle(pos.ink)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(pos.ink.opacity(isDark ? 0.24 : 0.16)))

            // The honesty law: a snapshot NEVER wears the live dot.
            if let cacheAge {
                HStack(spacing: 5) {
                    Circle().fill(Brand.warning).frame(width: 7, height: 7)
                    Text(EscortOfflineCache.stalenessLine(age: cacheAge))
                        .font(.system(size: 10, weight: .semibold).monospaced())
                        .foregroundStyle(Brand.warning)
                }
            } else {
                HStack(spacing: 5) {
                    ZStack {
                        Circle().fill(Brand.success.opacity(0.25)).frame(width: 13, height: 13)
                        Circle().fill(Brand.success).frame(width: 7, height: 7)
                    }
                    Text(separationLine).font(.system(size: 10.5, weight: .semibold).monospaced())
                        .foregroundStyle(palette.textPrimary)
                }
            }
            Spacer()
        }
    }
    private var separationLine: String {
        guard let m = proximity?.distanceMeters else { return "GPS LIVE" }
        return "GPS LIVE · SEP \(Int((m * 3.28084).rounded())) FT"
    }

    private var noActiveMove: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("No active move").font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("You hold no assignment in accepted, en route, on site, or escorting right now.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
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
            HStack {
                Text("WIND GATE · PROCEED / CAUTION / HOLD")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(isSnapshot ? "CACHED · NOT LIVE" : "WEATHERKIT · LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(isSnapshot ? Brand.warning : palette.textTertiary)
            }
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    verdictCell("PROCEED", "< \(Int(cautionThreshold)) MPH", Brand.success,
                                lit: windVerdict == .proceed)
                    verdictCell("CAUTION", "\(Int(cautionThreshold))–\(Int(nogoThreshold) - 1) MPH",
                                Brand.warning, lit: windVerdict == .caution)
                    verdictCell("HOLD", "≥ \(Int(nogoThreshold)) MPH", Brand.danger,
                                lit: windVerdict == .hold)
                }
                thresholdRuler
                HStack(alignment: .top) {
                    Text(windFootnote).font(.system(size: 7, weight: .bold).monospaced())
                        .foregroundStyle(palette.textTertiary).lineLimit(2)
                    Spacer(minLength: Space.s2)
                    Text("NOT A POSTED LIMIT").font(.system(size: 7, weight: .bold).monospaced())
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        }
    }

    private func verdictCell(_ title: String, _ range: String, _ tint: Color, lit: Bool) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(lit ? Color.white : tint)
            Text(range).font(.system(size: 8, weight: .bold).monospaced())
                .foregroundStyle(lit ? Color.white : tint)
        }
        .frame(maxWidth: .infinity).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(lit ? tint : tint.opacity(isDark ? 0.16 : 0.10)))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
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
                    Rectangle().fill(Brand.success.opacity(0.35)).frame(width: cautionX)
                    Rectangle().fill(Brand.warning.opacity(0.55)).frame(width: max(nogoX - cautionX, 0))
                    Rectangle().fill(Brand.danger.opacity(0.40))
                }
                .frame(height: 6).clipShape(Capsule()).offset(y: 14)

                Rectangle().fill(Brand.warning).frame(width: 1.2, height: 14).offset(x: cautionX, y: 10)
                Rectangle().fill(Brand.danger).frame(width: 1.2, height: 14).offset(x: nogoX, y: 10)
                Text("\(Int(cautionThreshold))").font(.system(size: 7, weight: .bold).monospaced())
                    .foregroundStyle(Brand.warning).offset(x: cautionX - 5, y: 26)
                Text("\(Int(nogoThreshold))").font(.system(size: 7, weight: .bold).monospaced())
                    .foregroundStyle(Brand.danger).offset(x: nogoX - 5, y: 26)

                if let gust = peakGust {
                    VStack(spacing: 1) {
                        Text("\(Int(gust))").font(.system(size: 9.5, weight: .heavy).monospaced())
                            .foregroundStyle(Brand.warning)
                        ES16Triangle().fill(Brand.warning).frame(width: 10, height: 7)
                    }
                    .offset(x: min(max(gust * scale, 8), w - 8) - 8, y: -4)
                }
            }
        }
        .frame(height: 36)
    }

    private var windFootnote: String {
        guard let env = corridor?.windGate, env.gated == true else {
            return "LOAD IS NOT WIND-GATED · OS/OW AND HAZMAT ONLY"
        }
        guard let gust = peakGust else {
            return isSnapshot ? "CACHED READ · VERDICT WITHHELD UNTIL A LIVE SAMPLE"
                              : "NO REAL GUST LANDED · VERDICT UNKNOWN, NOT CALM"
        }
        let legPart = peakGustLegIndex.map { "LEG \($0)" } ?? "CORRIDOR"
        let band = surfaceBand.map { " · \($0.uppercased()) BAND" } ?? ""
        return "PEAK GUST \(Int(gust)) MPH \(legPart)\(band) · GATED BECAUSE OS/OW"
    }

    // MARK: Spine + advisory rail (the parallel columns)

    private var spineSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(spineHeader).font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("ADVISORY RAIL").font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .top, spacing: Space.s2) {
                segmentSpine
                advisoryRail.frame(width: 138)
            }
        }
    }
    private var spineHeader: String {
        guard let miles = corridor?.routedMiles else { return "CORRIDOR SPINE" }
        return "CORRIDOR SPINE · \(miles.formatted(.number.precision(.fractionLength(1)))) MI"
    }

    private var segmentSpine: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(corridor?.legs ?? []) { leg in
                if (leg.status ?? "") == "active" { heroLeg(leg) } else { compactLeg(leg) }
            }
            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.top, Space.s2)
            Text(coverageBasisLine).font(.system(size: 7, weight: .bold).monospaced())
                .foregroundStyle(palette.textTertiary).padding(.top, 6)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
    }

    private func compactLeg(_ leg: ES16Leg) -> some View {
        let done = (leg.status ?? "") == "completed"
        let cautioned = (leg.chips ?? []).contains { $0.hasPrefix("WIND") }
        return HStack(alignment: .top, spacing: Space.s2) {
            ZStack {
                if done {
                    Circle().fill(Brand.success).frame(width: 14, height: 14)
                    Image(systemName: "checkmark").font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(.white)
                } else {
                    Circle().strokeBorder(cautioned ? Brand.warning : palette.textTertiary, lineWidth: 2)
                        .frame(width: 12, height: 12)
                }
            }
            .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(legIndex(leg)) \(legRoute(leg).uppercased())")
                    .font(.system(size: 8, weight: .bold).monospaced())
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(compactSubline(leg, done: done, cautioned: cautioned))
                    .font(.system(size: 7, weight: .bold).monospaced())
                    .foregroundStyle(done ? Brand.success : (cautioned ? Brand.warning : palette.textTertiary))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
    private func compactSubline(_ leg: ES16Leg, done: Bool, cautioned: Bool) -> String {
        let miles = leg.miles.map { "\($0.formatted(.number.precision(.fractionLength(1)))) MI" } ?? "— MI"
        if done { return "\(miles) · DONE" }
        if cautioned, let g = leg.wind?.gust { return "\(miles) · WIND CAUTION \(Int(g))" }
        return "\(miles) · PENDING"
    }

    private func heroLeg(_ leg: ES16Leg) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            ZStack {
                Circle().strokeBorder(LinearGradient.primary, lineWidth: 2.5).frame(width: 16, height: 16)
                Circle().fill(Brand.blue).frame(width: 6, height: 6)
            }
            .frame(width: 16).padding(.top, 28)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("SEGMENT \(legIndex(leg)) OF \(corridor?.legsTotal ?? (corridor?.legs.count ?? 0))")
                        .font(.system(size: 7.5, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("ACTIVE").font(.system(size: 7, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Brand.blue)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Brand.blue.opacity(isDark ? 0.22 : 0.16)))
                }
                Text(legRoute(leg)).font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.85)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.textPrimary.opacity(0.08)).frame(height: 5)
                        Capsule().fill(LinearGradient.primary)
                            .frame(width: geo.size.width * CGFloat(leg.coverage ?? 0), height: 5)
                    }
                }
                .frame(height: 5)
                Text(heroMilesLine(leg)).font(.system(size: 7.5, weight: .bold).monospaced())
                    .foregroundStyle(palette.textPrimary)
                Text(heroConvoyLine).font(.system(size: 7.5, weight: .bold).monospaced())
                    .foregroundStyle(palette.textSecondary)
                if let eta = heroEtaLine {
                    Text(eta).font(.system(size: 7.5, weight: .bold).monospaced())
                        .foregroundStyle(Brand.blue)
                }
            }
            .padding(Space.s3)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Brand.blue.opacity(0.35), lineWidth: 1.5))
        }
        .padding(.vertical, 6)
    }

    private func legRoute(_ leg: ES16Leg) -> String {
        if let o = leg.origin, let d = leg.destination { return "\(o) → \(d)" }
        return leg.label ?? "—"
    }
    private func heroMilesLine(_ leg: ES16Leg) -> String {
        let miles = leg.miles.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—"
        let remaining = milesRemainingOnActiveLeg.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—"
        return "\(miles) MI · \(remaining) TO GO · \(Int(((leg.coverage ?? 0) * 100).rounded()))%"
    }
    private var heroConvoyLine: String {
        let pos = ES16Position(wire: trip?.position).label
        let sep = proximity?.distanceMeters.map { "\(Int(($0 * 3.28084).rounded())) FT" } ?? "— FT"
        let cap = proximity?.convoyMaxSpeed ?? trip?.convoy?.maxSpeedMph
        return "\(pos) SEP \(sep) · CAP \(cap.map { "\($0) MPH" } ?? "— MPH")"
    }
    /// ETA is computed from REAL remaining miles and the REAL convoy speed cap.
    /// If either is missing it is omitted rather than estimated.
    private var heroEtaLine: String? {
        guard let remaining = milesRemainingOnActiveLeg,
              let cap = proximity?.convoyMaxSpeed ?? trip?.convoy?.maxSpeedMph, cap > 0 else { return nil }
        let minutes = Int((remaining / Double(cap) * 60).rounded())
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return "ETA \(f.string(from: Date().addingTimeInterval(TimeInterval(minutes * 60)))) · T-\(minutes) MIN"
    }

    private var advisoryRail: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(advisories) { chip in advisoryCard(chip) }
            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.top, Space.s2)
            Text("ICE COVERED ONLY AS\nSURFACE BAND ABOVE")
                .font(.system(size: 6.5, weight: .bold).monospaced())
                .foregroundStyle(palette.textTertiary).padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .opacity(isSnapshot ? 0.55 : 1)
    }

    private func advisoryCard(_ chip: ES16Advisory) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(chip.label).font(.system(size: 7, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(chip.source == .stub ? palette.textTertiary : chip.tint)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(chip.tagOverride ?? chip.source.tag)
                    .font(.system(size: 5.5, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(tagInk(chip.source))
            }
            Text(chip.value).font(.system(size: 7.5, weight: .heavy).monospaced())
                .foregroundStyle(chip.source == .stub ? palette.textTertiary : chip.tint)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.sm + 2, style: .continuous)
            .fill(chip.source == .stub ? Color.clear : chip.tint.opacity(isDark ? 0.14 : 0.08)))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm + 2, style: .continuous)
            .strokeBorder(chip.source == .stub ? palette.textTertiary.opacity(0.45) : chip.tint.opacity(0.40),
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
        case .live: return Brand.success
        case .notEvaluated: return Brand.warning
        default: return palette.textTertiary
        }
    }

    /// Fixed order so the rail's rhythm never shuffles under the reader between
    /// polls. Every chip carries its source state.
    private var advisories: [ES16Advisory] {
        var out: [ES16Advisory] = []

        if let env = corridor?.windGate, env.gated == true {
            let hasGust = peakGust != nil
            out.append(ES16Advisory(
                id: "wind", label: "WIND GATE",
                value: hasGust ? "\(Int(peakGust!)) MPH · \(windVerdict.rawValue.uppercased())"
                               : "NO GUST DATA · UNKNOWN",
                source: hasGust ? .live : .notEvaluated,
                tint: windTint,
                tagOverride: hasGust ? nil : "NO DATA"))
        }
        if let band = surfaceBand {
            out.append(ES16Advisory(id: "surface", label: "SURFACE BAND",
                                    value: "\(band.uppercased())\(surfaceCode.map { " · CODE \($0)" } ?? "")",
                                    source: .live, tint: Brand.blue))
        }
        if let r = restrictions?.restrictions.first(where: { $0.type == "rush_hour" }) {
            _ = r
            out.append(ES16Advisory(id: "curfew", label: "CURFEW WINDOW",
                                    value: "07–09 ON · NEXT 16–18", source: .derived, tint: Brand.warning))
        } else if restrictions?.restrictions.contains(where: { $0.type == "time_restriction" }) == true {
            out.append(ES16Advisory(id: "night", label: "NIGHT WINDOW",
                                    value: "22–05 PERMITTED", source: .derived, tint: Brand.warning))
        }
        if restrictions?.restrictions.contains(where: { $0.type == "weekend" }) == true {
            out.append(ES16Advisory(id: "weekend", label: "WEEKEND LIMIT",
                                    value: "RESTRICTED TODAY", source: .derived, tint: Brand.warning))
        }
        if let r = restrictions, r.isOversize == true, let w = r.weight {
            let fmt = NumberFormatter(); fmt.numberStyle = .decimal
            out.append(ES16Advisory(id: "osow",
                                    label: r.isSuperload == true ? "SUPERLOAD" : "OS/OW ROUTE",
                                    value: "\(fmt.string(from: NSNumber(value: w)) ?? "\(Int(w))") LB · PERMIT",
                                    source: .live, tint: Brand.escort))
        }
        if let cov = bridge {
            let evaluated = cov.bridgesChecked > 0
            out.append(ES16Advisory(
                id: "bridge", label: "BRIDGE COVER",
                value: evaluated ? "\(cov.bridgesChecked) CHECKED · CLEAR"
                                 : "NOT EVALUATED · \(Int(cov.coverageRadiusMi))MI",
                source: evaluated ? .live : .notEvaluated,
                tint: evaluated ? Brand.success : Brand.neutral,
                tagOverride: "\(cov.bridgesChecked) / \(cov.datasetRows)"))
        }
        // STUBs — named, dashed, inert. No endpoint is invented for them.
        out.append(ES16Advisory(id: "school", label: "SCHOOL ZONE", value: "NO FEED WIRED",
                                source: .stub, tint: Brand.neutral))
        out.append(ES16Advisory(id: "gfi", label: "GRADE·FLOOD·ICE", value: "3 · NO FEED WIRED",
                                source: .stub, tint: Brand.neutral))
        return out
    }
    private var windTint: Color {
        switch windVerdict {
        case .proceed: return Brand.success
        case .caution: return Brand.warning
        case .hold: return Brand.danger
        case .unknown, .notGated: return Brand.neutral
        }
    }

    // MARK: Clearance log (ES-02 cross-link)

    private var clearanceSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("CLEARANCE EVENTS · THIS CORRIDOR")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(events.count) LOGGED · ES-02").font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 0) {
                if events.isEmpty {
                    Text("No clearance events logged on this corridor yet.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(Space.s3)
                } else {
                    ForEach(Array(events.prefix(3).enumerated()), id: \.element.id) { idx, ev in
                        if idx > 0 { Rectangle().fill(palette.borderFaint).frame(height: 1) }
                        clearanceRow(ev)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        }
    }

    private func clearanceRow(_ ev: ES16ClearanceEvent) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Circle().fill(eventTint(ev)).frame(width: 9, height: 9).padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(eventTitle(ev)) · \(ev.structureName ?? "Unnamed structure")")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(eventDetail(ev)).font(.system(size: 7.5, weight: .bold).monospaced())
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            Text(shortClock(ev.occurredAt)).font(.system(size: 8, weight: .bold).monospaced())
                .foregroundStyle(ev.eventType == "clearance_check" ? Brand.success : Brand.warning)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.textTertiary).padding(.top, 2)
        }
        .padding(Space.s3)
    }
    private func eventTint(_ ev: ES16ClearanceEvent) -> Color {
        switch ev.eventType {
        case "strike": return Brand.danger
        case "near_miss": return Brand.warning
        default: return Brand.success
        }
    }
    private func eventTitle(_ ev: ES16ClearanceEvent) -> String {
        switch ev.eventType {
        case "strike": return "STRIKE"
        case "near_miss": return "NEAR-MISS"
        default: return "CHECK"
        }
    }
    /// Δ is computed only when BOTH figures are present — never half-filled.
    private func eventDetail(_ ev: ES16ClearanceEvent) -> String {
        guard let posted = ev.postedClearanceFt else { return "NO POSTED CLEARANCE RECORDED" }
        guard let measured = ev.measuredClearanceFt else { return "POSTED \(feetInches(posted))" }
        let delta = posted - measured
        return "POSTED \(feetInches(posted)) · POLE \(feetInches(measured)) · Δ \(delta >= 0 ? "+" : "-")\(feetInches(abs(delta)))"
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

    private var lifecycleLadder: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 0) {
                ForEach(Self.statusLadder, id: \.self) { st in
                    let current = st == (trip?.assignmentStatus ?? "")
                    Text(st.replacingOccurrences(of: "_", with: " ").uppercased())
                        .font(.system(size: 7.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(current ? Color.white : (st == nextStatus ? Brand.blue : palette.textTertiary))
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                        .background { if current { Capsule().fill(Brand.blue) } }
                }
            }
            .padding(.horizontal, 4).padding(.vertical, 3)
            .background(Capsule().fill(palette.textPrimary.opacity(0.04)))

            Text("STATUS WRITES PERSIST BUT EMIT NO WS EVENT AND NO AUDIT ROW · ONE-SIDED")
                .font(.system(size: 7, weight: .bold).monospaced())
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var esangRow: some View {
        HStack(spacing: Space.s3) {
            Circle().fill(LinearGradient.diagonal).frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("ESANG").font(.system(size: 9.5, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(esangHeadline).font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(palette.textPrimary).lineLimit(1)
                }
                Text(esangDetail).font(.system(size: 8)).foregroundStyle(palette.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s3)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(LinearGradient.diagonal).frame(width: 3)
        }
    }
    private var esangHeadline: String {
        guard let gust = peakGust, let idx = peakGustLegIndex,
              let legs = corridor?.legs, idx <= legs.count else {
            return "· Wind gate has no live verdict right now"
        }
        return "· Gust hits \(Int(gust)) at \(legs[idx - 1].destination ?? "the next leg")"
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
                Button { Task { await advance() } } label: {
                    HStack(spacing: Space.s2) {
                        Image(systemName: "arrow.right").font(.system(size: 12, weight: .heavy))
                        Text(advanceLabel).font(.system(size: 12.5, weight: .heavy)).tracking(0.3)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .background(Capsule().fill(nextStatus == nil || statusInFlight
                                               ? AnyShapeStyle(palette.textTertiary)
                                               : AnyShapeStyle(LinearGradient.primary)))
                }
                .buttonStyle(.plain).disabled(nextStatus == nil || statusInFlight)

                Button { } label: {
                    Text("HEIGHT POLE").font(.system(size: 11.5, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(Brand.hazmat)
                        .frame(width: 132, height: 42)
                        .background(Capsule().fill(palette.bgCard))
                        .overlay(Capsule().strokeBorder(Brand.hazmat.opacity(0.55), lineWidth: 1.5))
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
        guard let next = nextStatus else { return "NO NEXT STATUS" }
        return "ADVANCE → \(next.replacingOccurrences(of: "_", with: " ").uppercased())"
    }

    // MARK: Derived spine values

    private var activeLeg: ES16Leg? { corridor?.legs.first { ($0.status ?? "") == "active" } }
    private func legIndex(_ leg: ES16Leg) -> Int { ((corridor?.legs.firstIndex(of: leg)) ?? 0) + 1 }
    /// Derived from the leg's own coverage — the server projects no
    /// remaining-miles field, so this is arithmetic on real numbers, not a
    /// guess.
    private var milesRemainingOnActiveLeg: Double? {
        guard let leg = activeLeg, let miles = leg.miles else { return nil }
        return ((miles * (1 - (leg.coverage ?? 0))) * 10).rounded() / 10
    }
    /// Coverage stated on the LEG-COUNT basis the server actually computes, so
    /// the mile basis is never implied.
    private var coverageBasisLine: String {
        let pct = Int(((corridor?.corridorCoverage ?? 0) * 100).rounded())
        let done = corridor?.legsCompleted ?? 0
        let total = corridor?.legsTotal ?? (corridor?.legs.count ?? 0)
        guard let active = activeLeg else { return "COVERAGE \(pct)% · \(done) OF \(total) LEGS" }
        return "COVERAGE \(pct)% · \(done) OF \(total) LEGS + \(Int(((active.coverage ?? 0) * 100).rounded()))% LEG \(legIndex(active))"
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

            corridor = fetchedCorridor
            restrictions = fetchedRestrictions
            proximity = fetchedProximity
            events = fetchedEvents
            cacheAge = nil
            errorMessage = nil

            EscortOfflineCache.store(ES16Snapshot(trip: t, corridor: fetchedCorridor,
                                                  restrictions: fetchedRestrictions,
                                                  proximity: fetchedProximity,
                                                  events: fetchedEvents, bridge: bridge),
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

    private func apply(_ snap: ES16Snapshot) {
        trip = snap.trip
        corridor = snap.corridor
        restrictions = snap.restrictions
        proximity = snap.proximity
        events = snap.events
        bridge = snap.bridge
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

private struct ES16Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Registered surface wrapper

struct EscortActiveTripConsoleScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortActiveTripConsole()
        } nav: {
            // Escort role enum TRIP·COMMS·PERMIT·ME — the active trip IS the
            // TRIP tab, mirroring ES-01/ES-02/ES-05.
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
