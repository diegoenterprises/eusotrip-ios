//
//  709_RailConductorCabRun.swift
//  EusoTrip — Rail Conductor · Cab Run (CONDUCTOR SIDE, in the cab, mid-run).
//
//  Author of record: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//
//  Faithful 1:1 port of "05 Rail/Light-SVG/709 Rail Conductor Cab Run.svg"
//  (and its Dark twin). Same sections, same order, same values — every number
//  below is decoded from a real procedure or derived arithmetically from
//  decoded state. No mock arrays, no placeholder rows, no fabricated position.
//
//  ARCHETYPE: CAB HOME on an ORDERED WORK-POINT BOARD. The hero carries the
//  server-returned lineup as discrete nodes and keeps the latest tracking fix
//  in a separate evidence label. It never projects that fix onto a made-up
//  rail line. Remaining work + time stay right-aligned in mono. Under it: the
//  NEXT WORK EVENT card and
//  the 49 CFR §228 HOS burn strip with the 12h limit tick. It is deliberately
//  NOT the horizontal-progress stat hero of 550 and NOT the vertical spine of
//  its own sibling 712 — 709 is operational order, 712 is chronological.
//
//  ── WIRING MANIFEST ────────────────────────────────────────────────────────
//    railShipments.getRailShipments      EXISTS railShipments.ts:421   → the run's rail id + numeric shipment id
//    railShipments.getServiceLineup EXISTS railShipments.ts:1576  → ordered named work points on the ribbon
//    railShipments.getRailTracking       EXISTS railShipments.ts:1536  → position fix + event timestamps (staleness)
//    railShipments.liveTrackRailcar      EXISTS railShipments.ts:2062  → Railinc car-level fix (WARM cache 300s)
//    railShipments.getTrainConsists      EXISTS railShipments.ts:1332  → consist number, car count, conductorId/engineerId
//    railShipments.getRailCrew           EXISTS railShipments.ts:2453  → crew identity + role for the initials discs
//    railShipments.getRailCrewHOS        EXISTS railShipments.ts:2471  → §228 duty hours for the burn strip
//        SAME procedure and SAME row shape 712 gates its tie-up HOS condition on,
//        so the burn strip runs the SAME evidence predicate (tracked · trackingState
//        · observationState · source · HOSObservationClock freshness). Without it
//        the §228 verdict — bar, colour, hours remaining — is withheld, not defaulted.
//    <HOS observation provenance>        STUB · named-gap RAIL-HOS-228-PROVENANCE
//        getRailCrewHOS returns raw rail_crew_assignments rows (schema.ts:11696) and
//        that table carries NO tracked / trackingState / source / freshness /
//        observationState column, so the evidence gate reads UNVERIFIED on every live
//        row today. That is the honest state, not a defect in the gate.
//    <work-event completion write>       STUB · named-gap RAIL-CDR-709-WORK-EVENT-DONE
//    <remaining run distance in miles>   STUB · named-gap RAIL-CDR-709-RUN-DISTANCE
//        (verified absent: no rail procedure carries a remaining-distance figure, so the
//         mono readout states remaining CALLS + remaining TIME, never an invented mileage)
//    Realtime: WS_EVENTS.RAIL_CONSIST_UPDATE (:411) · RAIL_TRACKING_UPDATE (:412) ·
//              RAIL_CREW_HOS_WARNING (:409); channels RAIL_TRACKING (:625), RAIL_DISPATCH (:623).
//    RBAC: railReadProcedure (railShipments.ts:94), RAIL_CONDUCTOR (trpc.ts:33).
//    OFFLINE: READ_CACHED(180s) — a stale fix is labelled on screen ("position as of
//             HH:mm · offline"). No forward extrapolation is drawn or asserted.
//    NAV (carrier family): HOME(current) · SHIPMENTS · [orb] · COMPLIANCE · ME.
//

import SwiftUI

// MARK: - Screen

struct RailConductorCabRunScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailConductorCabRunBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: true),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Decode helpers
//
// The rail tables store decimals as strings (rail_crew_assignments.hoursOnDuty
// is decimal(6,2)) and several procedures pass numbers straight through, so
// every numeric field is read tolerantly rather than assumed.

private func flexDouble<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Double? {
    if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
    if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Double(s) }
    return nil
}

private func flexInt<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Int? {
    if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return i }
    if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Int(s) }
    if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(d) }
    return nil
}

private func parseServerDate(_ s: String?) -> Date? {
    guard let s, !s.isEmpty else { return nil }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = iso.date(from: s) { return d }
    iso.formatOptions = [.withInternetDateTime]
    if let d = iso.date(from: s) { return d }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f.date(from: s)
}

private let clockFormatter: DateFormatter = {
    let f = DateFormatter(); f.locale = .current; f.dateFormat = "HH:mm"; return f
}()

// MARK: - Data shapes

/// `railShipments.getRailShipments` row (railShipments.ts:421) — the run anchor.
private struct RunAnchor709: Decodable {
    let id: String
    let railRef: String?
    let origin: String?
    let destination: String?
    let numberOfCars: Int?
    let carrier: String?

    /// The numeric shipment id the tracking/detail procedures take.
    var numericId: Int? { Int(id.filter(\.isNumber)) }
}

/// `railShipments.getServiceLineup` (railShipments.ts:1576).
private struct Lineup709: Decodable {
    let trainSymbol: String?
    let carCount: Int?
    let scheduledCalls: Int?
    let clearedCalls: Int?
    let estimatedTransitHours: Double?
    let status: String?
    let nextCallLabel: String?
    let nextCallYardName: String?
    let calls: [LineupCall709]?

    enum CodingKeys: String, CodingKey {
        case trainSymbol, carCount, scheduledCalls, clearedCalls
        case estimatedTransitHours, status, nextCallLabel, nextCallYardName, calls
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trainSymbol           = try c.decodeIfPresent(String.self, forKey: .trainSymbol)
        carCount              = flexInt(c, .carCount)
        scheduledCalls        = flexInt(c, .scheduledCalls)
        clearedCalls          = flexInt(c, .clearedCalls)
        estimatedTransitHours = flexDouble(c, .estimatedTransitHours)
        status                = try c.decodeIfPresent(String.self, forKey: .status)
        nextCallLabel         = try c.decodeIfPresent(String.self, forKey: .nextCallLabel)
        nextCallYardName      = try c.decodeIfPresent(String.self, forKey: .nextCallYardName)
        calls                 = try c.decodeIfPresent([LineupCall709].self, forKey: .calls)
    }
}

private struct LineupCall709: Decodable, Identifiable {
    let yardName: String?
    let detail: String?
    let status: String?
    let timeLabel: String?
    var id: String { (yardName ?? "-") + "|" + (timeLabel ?? "-") + "|" + (detail ?? "-") }

    /// A call is behind the train only when the server says so.
    var isCleared: Bool {
        ["cleared", "complete", "completed", "departed", "passed", "done"]
            .contains((status ?? "").lowercased())
    }
}

/// `railShipments.getRailTracking` (railShipments.ts:1536).
private struct Tracking709: Decodable {
    let events: [TrackEvent709]?
    let currentLocation: GeoPoint709?
}

private struct TrackEvent709: Decodable {
    let eventType: String?
    let description: String?
    let timestamp: String?
    let location: GeoPoint709?
    var at: Date? { parseServerDate(timestamp) }
}

private struct GeoPoint709: Decodable {
    let lat: Double?
    let lng: Double?
    let description: String?
}

/// `railShipments.getTrainConsists` (railShipments.ts:1332) → `{ consists, total }`.
private struct ConsistEnvelope709: Decodable {
    let consists: [Consist709]?
    let total: Int?
}

private struct Consist709: Decodable, Identifiable {
    let id: Int
    let consistNumber: String?
    let totalCars: Int?
    let trainType: String?
    let status: String?
    let engineerId: Int?
    let conductorId: Int?
    let departureTime: String?
    let arrivalTime: String?

    enum CodingKeys: String, CodingKey {
        case id, consistNumber, totalCars, trainType, status
        case engineerId, conductorId, departureTime, arrivalTime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = flexInt(c, .id) ?? 0
        consistNumber = try c.decodeIfPresent(String.self, forKey: .consistNumber)
        totalCars     = flexInt(c, .totalCars)
        trainType     = try c.decodeIfPresent(String.self, forKey: .trainType)
        status        = try c.decodeIfPresent(String.self, forKey: .status)
        engineerId    = flexInt(c, .engineerId)
        conductorId   = flexInt(c, .conductorId)
        departureTime = try c.decodeIfPresent(String.self, forKey: .departureTime)
        arrivalTime   = try c.decodeIfPresent(String.self, forKey: .arrivalTime)
    }
}

/// `rail_crew_assignments` row as returned by `getRailCrew` (railShipments.ts:2453) and
/// `getRailCrewHOS` (railShipments.ts:2471). The table itself carries no display name, so the
/// name fields are decoded OPTIONALLY: when the row is enriched we render the
/// person, when it is not we render the decoded identifier — we never invent a
/// name to fill an initials disc.
private struct CrewRow709: Decodable, Identifiable {
    let id: Int
    let userId: Int?
    let consistId: Int?
    let role: String?
    let name: String?
    let crewId: String?
    let assignedAt: String?
    let relievedAt: String?
    let hoursOnDuty: Double?
    let hoursOfServiceCompliant: Bool?
    // Observation provenance — the same five fields 712 gates its §228 read on
    // (712:318) and the rail HOS surfaces 554 / 678 / 679 gate theirs on. Read
    // here so a duty figure can never be drawn without the evidence that dates
    // and sources it. Absent keys decode to nil, which fails the gate closed.
    let tracked: Bool?
    let trackingState: HOSTrackingState?
    let source: String?
    let freshness: String?
    let observationState: String?

    enum CodingKeys: String, CodingKey {
        case id, userId, consistId, role, name, crewId
        case assignedAt, relievedAt, hoursOnDuty, hoursOfServiceCompliant
        case crewName, onDutyHours
        case tracked, trackingState, source, freshness, observationState
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = flexInt(c, .id) ?? 0
        userId   = flexInt(c, .userId)
        consistId = flexInt(c, .consistId)
        role     = try c.decodeIfPresent(String.self, forKey: .role)
        name     = (try? c.decodeIfPresent(String.self, forKey: .name))
                    ?? (try? c.decodeIfPresent(String.self, forKey: .crewName)) ?? nil
        crewId   = try c.decodeIfPresent(String.self, forKey: .crewId)
        assignedAt = try c.decodeIfPresent(String.self, forKey: .assignedAt)
        relievedAt = try c.decodeIfPresent(String.self, forKey: .relievedAt)
        hoursOnDuty = flexDouble(c, .hoursOnDuty) ?? flexDouble(c, .onDutyHours)
        hoursOfServiceCompliant = try c.decodeIfPresent(Bool.self, forKey: .hoursOfServiceCompliant)
        tracked = try c.decodeIfPresent(Bool.self, forKey: .tracked)
        trackingState = try c.decodeIfPresent(HOSTrackingState.self, forKey: .trackingState)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        freshness = try c.decodeIfPresent(String.self, forKey: .freshness)
        observationState = try c.decodeIfPresent(String.self, forKey: .observationState)
    }

    var isConductor: Bool { (role ?? "").lowercased() == "conductor" }
    var isEngineer:  Bool { (role ?? "").lowercased() == "engineer" }

    /// Initials for the disc. Derived only from decoded text; when the row
    /// carries no name and no crew id we fall back to the numeric user id so
    /// the disc still holds a real identifier and never a glyph.
    var discInitials: String {
        if let n = name?.trimmingCharacters(in: .whitespaces), !n.isEmpty {
            let parts = n.split(separator: " ").prefix(2)
            let s = parts.compactMap { $0.first.map(String.init) }.joined()
            if !s.isEmpty { return s.uppercased() }
        }
        if let c = crewId?.filter(\.isLetter), c.count >= 2 {
            return String(c.suffix(2)).uppercased()
        }
        if let u = userId { return String(String(u).suffix(2)) }
        return String(String(id).suffix(2))
    }

    /// Display label for the row. Never a fabricated person.
    var displayLabel: String {
        if let n = name?.trimmingCharacters(in: .whitespaces), !n.isEmpty { return n }
        if let c = crewId, !c.isEmpty { return c }
        if let u = userId { return "Crew #\(u)" }
        return "Crew #\(id)"
    }
}

// MARK: - Body

private struct RailConductorCabRunBody: View {
    @Environment(\.palette) private var palette

    @State private var anchor: RunAnchor709? = nil
    @State private var lineup: Lineup709? = nil
    @State private var tracking: Tracking709? = nil
    @State private var consist: Consist709? = nil
    @State private var crew: [CrewRow709] = []
    @State private var hosRows: [CrewRow709] = []
    @State private var hosLoadError: String? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var loadedAt: Date = .now

    /// 49 CFR §228 — 12 hours maximum on duty (US regime; the tri-country band
    /// below names the CA and MX regimes this ceiling is swapped for).
    private let hosLimitHours: Double = 12.0
    /// READ_CACHED tier declared in the wireframe `<desc>`.
    private let cacheTTL: TimeInterval = 180

    // MARK: Derived run state

    private var calls: [LineupCall709] { lineup?.calls ?? [] }

    /// The run's named work points, trimmed to the ribbon's four anchors when
    /// the lineup is long: origin, the last cleared call, the next call, and
    /// the destination. Nothing is added that the lineup did not return.
    private var ribbonNodes: [LineupCall709] {
        guard calls.count > 4 else { return calls }
        var picked: [LineupCall709] = []
        if let first = calls.first { picked.append(first) }
        if let lastCleared = calls.dropFirst().last(where: { $0.isCleared }) { picked.append(lastCleared) }
        if let next = nextCall { picked.append(next) }
        if let last = calls.last { picked.append(last) }
        // de-duplicate while preserving order
        var seen = Set<String>()
        return picked.filter { seen.insert($0.id).inserted }
    }

    private var nextCall: LineupCall709? { calls.first(where: { !$0.isCleared }) }

    private var clearedCount: Int { lineup?.clearedCalls ?? calls.filter(\.isCleared).count }
    private var scheduledCount: Int { lineup?.scheduledCalls ?? calls.count }
    private var remainingCalls: Int { max(scheduledCount - clearedCount, 0) }

    /// Newest located tracking event — observation evidence only. Without a
    /// canonical graph projection it cannot place the train between work points.
    private var positionFix: TrackEvent709? {
        (tracking?.events ?? [])
            .filter { $0.at != nil }
            .sorted { ($0.at ?? .distantPast) > ($1.at ?? .distantPast) }
            .first
    }

    private var fixAge: TimeInterval? {
        guard let at = positionFix?.at else { return nil }
        return max(loadedAt.timeIntervalSince(at), 0)
    }

    private var isStale: Bool {
        guard let age = fixAge else { return tracking != nil }
        return age > cacheTTL
    }

    /// Hours remaining on the run: the lineup's own transit estimate scaled by
    /// the share of calls still ahead. Nil when the estimate is absent.
    private var remainingHours: Double? {
        guard let total = lineup?.estimatedTransitHours, scheduledCount > 0 else { return nil }
        return total * (Double(remainingCalls) / Double(scheduledCount))
    }

    // MARK: Derived crew + HOS state

    private var conductorRow: CrewRow709? {
        if let cid = consist?.conductorId,
           let match = crew.first(where: { $0.userId == cid }) { return match }
        if let cid = consist?.id, let match = crew.first(where: { $0.consistId == cid && $0.isConductor }) { return match }
        return crew.first(where: { $0.isConductor })
    }

    private var engineerRow: CrewRow709? {
        if let eid = consist?.engineerId,
           let match = crew.first(where: { $0.userId == eid }) { return match }
        if let cid = consist?.id, let match = crew.first(where: { $0.consistId == cid && $0.isEngineer }) { return match }
        return crew.first(where: { $0.isEngineer })
    }

    /// The signed-in conductor's dedicated §228 evidence row. Generic crew
    /// assignment data never substitutes for an unavailable HOS response.
    private var conductorHOSRow: CrewRow709? {
        if let uid = conductorRow?.userId,
           let row = hosRows.first(where: { $0.userId == uid }) { return row }
        return hosRows.first(where: { $0.isConductor })
    }

    /// The evidence gate, ported verbatim from the house exemplar so the two
    /// conductor screens can never disagree about the same §228 figure: it is
    /// the SAME predicate 712 runs at `hosEvidenceCurrent` (712:318) and the
    /// same one 554 / 678 / 679 run as `hasCurrentObservation`, read off the
    /// shared `Models/HOSStatus.swift` vocabulary rather than a parallel enum.
    private func hasCurrentObservation(_ row: CrewRow709) -> Bool {
        row.tracked == true
            && row.trackingState == .tracked
            && row.observationState == "current"
            && row.source?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && HOSObservationClock.freshness(row.freshness).isCurrent
    }

    /// A duty figure the server actually recorded. A negative, infinite or
    /// absent decimal is not a duty of zero hours.
    private func validDutyHours(_ hours: Double?) -> Double? {
        guard let hours, hours.isFinite, hours >= 0 else { return nil }
        return hours
    }

    /// A duty figure came back, whatever its provenance.
    private var hosRecorded: Bool { validDutyHours(conductorHOSRow?.hoursOnDuty) != nil }

    private var hosEvidenceCurrent: Bool {
        guard let row = conductorHOSRow, validDutyHours(row.hoursOnDuty) != nil else { return false }
        return hasCurrentObservation(row)
    }

    /// CURRENT · UNVERIFIED · MISSING — the same three states 712 renders on
    /// its HOS row (712:709). Unknown is its own visible state and is never
    /// folded into the good one.
    private var hosEvidenceStateWord: String {
        hosEvidenceCurrent ? "CURRENT" : (hosRecorded ? "UNVERIFIED" : "MISSING")
    }

    /// The §228 duty figure, released ONLY against current sourced evidence.
    /// Everything derived from it — the burn bar, the burn colour, the hours
    /// remaining — therefore withholds itself in the same breath rather than
    /// drawing a regulatory verdict over a row 712 would call UNVERIFIED.
    private var onDutyHours: Double? {
        guard hosEvidenceCurrent else { return nil }
        return validDutyHours(conductorHOSRow?.hoursOnDuty)
    }

    private var hoursRemaining: Double? {
        guard let on = onDutyHours else { return nil }
        return max(hosLimitHours - on, 0)
    }

    private var burnFraction: Double {
        guard let on = onDutyHours else { return 0 }
        return min(on / hosLimitHours, 1.0)
    }

    private var burnColor: Color {
        burnFraction > 0.85 ? Brand.danger : (burnFraction > 0.70 ? Brand.warning : Brand.success)
    }

    private var onDutyStart: Date? { parseServerDate(conductorHOSRow?.assignedAt) }

    private var dutyLimitAt: Date? {
        onDutyStart.map { $0.addingTimeInterval(hosLimitHours * 3600) }
    }

    // MARK: View

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                headline
                IridescentHairline().accessibilityHidden(true)

                if loading {
                    LifecycleCard { Text("Loading the run…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("The run could not be read. \(err)")
                } else if lineup == nil && consist == nil {
                    LifecycleCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No run assigned").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                            Text("No consist or service lineup is returned for this crew member yet.")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("No run assigned. No consist or service lineup is returned for this crew member yet.")
                } else {
                    runSequenceHero
                    if nextCall != nil {
                        notWiredCard("Set-out recording is unavailable. The work event remains open; contact rail operations to record it.")
                    }
                    sectionLabel("NEXT WORK EVENT", trailing: nextWorkTrailing)
                    nextWorkCard
                    sectionLabel("HOS BURN · 49 CFR §228", trailing: hosSectionTrailing)
                    hosBurnCard
                    sectionLabel("ON THIS CONSIST", trailing: consistTrailing)
                    consistCrewCard
                    triCountryBand
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Header

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Text("✦").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                .accessibilityHidden(true)
            Text("RAIL CONDUCTOR · CAB RUN")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.diagonal)
            Spacer()
            Text(anchor?.railRef ?? consist?.consistNumber ?? "—")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).monospaced()
                .foregroundStyle(palette.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(eyebrowAccessibilityLabel)
        .accessibilityAddTraits(.isHeader)
    }

    /// Spoken form of the eyebrow. The run reference is named only when the
    /// server returned one — the em-dash placeholder is never read as an id.
    private var eyebrowAccessibilityLabel: String {
        if let ref = anchor?.railRef ?? consist?.consistNumber, !ref.isEmpty {
            return "Rail conductor, cab run. Run \(ref)."
        }
        return "Rail conductor, cab run. No run reference returned."
    }

    private var headline: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Cab run")
                    .font(.system(size: 34, weight: .bold)).kerning(-0.6)
                    .foregroundStyle(palette.textPrimary)
                Text(headlineSubline)
                    .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let c = conductorRow {
                initialsDisc(c.discInitials, size: 40, fill: AnyShapeStyle(LinearGradient.diagonal), fontSize: 14)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cab run. \(headlineSubline).")
        .accessibilityAddTraits(.isHeader)
    }

    private var headlineSubline: String {
        var bits: [String] = []
        if let c = conductorRow { bits.append(c.displayLabel) }
        bits.append("conductor")
        if let sym = lineup?.trainSymbol ?? consist?.consistNumber { bits.append(sym) }
        if let cars = lineup?.carCount ?? consist?.totalCars ?? anchor?.numberOfCars { bits.append("\(cars) cars") }
        return bits.joined(separator: " · ")
    }

    // MARK: HERO — ordered work-point evidence

    private var runSequenceHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Wash band
            HStack {
                Text(heroBandLabel)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(Brand.info)
                Spacer()
                Text(positionFix?.location?.description ?? positionFix?.description ?? "no fix")
                    .font(.system(size: 9, weight: .semibold)).monospaced()
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16).frame(height: 40)
            .background(LinearGradient(colors: [Brand.blue.opacity(0.14), Brand.magenta.opacity(0.06)],
                                       startPoint: .leading, endPoint: .trailing))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(heroBandAccessibilityLabel)

            // Ordered calls — not a track line or location projection.
            workPointSequence
                .padding(.horizontal, 16).padding(.top, 18)

            Divider().overlay(palette.borderFaint).padding(.horizontal, 16).padding(.top, 14)
                .accessibilityHidden(true)

            // Staleness + remaining
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Circle().fill(isStale ? Brand.warning : Brand.success).frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(stalenessLine)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isStale ? Brand.warning : Brand.success)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
                Spacer(minLength: 8)
                Text(remainingReadout)
                    .font(.system(size: 15, weight: .heavy)).monospaced().monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(stalenessLine). \(remainingAccessibilityPhrase)")
        }
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    private var heroBandLabel: String {
        var bits = ["WORK-POINT SEQUENCE"]
        if let sym = lineup?.trainSymbol ?? consist?.consistNumber { bits.append(sym) }
        if let carrier = anchor?.carrier { bits.append(carrier) }
        return bits.joined(separator: " · ").uppercased()
    }

    /// Spoken form of the hero wash band. The evidence label is read as an
    /// observation, never as a projected position.
    private var heroBandAccessibilityLabel: String {
        let fix = positionFix?.location?.description ?? positionFix?.description
        if let fix, !fix.isEmpty { return "\(heroBandLabel). Latest reported location \(fix)." }
        return "\(heroBandLabel). No position fix reported."
    }

    private var stalenessLine: String {
        guard let at = positionFix?.at else { return "position not reported" }
        let stamp = clockFormatter.string(from: at)
        return isStale ? "position as of \(stamp) · offline" : "position as of \(stamp) · live"
    }

    /// Remaining CALLS and remaining TIME. Remaining MILES is a named gap —
    /// no rail procedure carries a distance-to-go figure, so we state what the
    /// server knows instead of inventing a mileage.
    private var remainingReadout: String {
        var bits: [String] = []
        if scheduledCount > 0 { bits.append("\(remainingCalls) calls") }
        if let h = remainingHours {
            let mins = Int((h * 60).rounded())
            bits.append("\(mins / 60)h \(String(format: "%02d", mins % 60))m")
        }
        return bits.isEmpty ? "—" : bits.joined(separator: " · ")
    }

    /// Spoken form of the mono remaining readout. When the server returned
    /// neither a call schedule nor a transit estimate it says so rather than
    /// reading the em-dash placeholder aloud.
    private var remainingAccessibilityPhrase: String {
        let readout = remainingReadout
        return readout == "—" ? "Remaining work not returned." : "Remaining \(readout)."
    }

    private var workPointSequence: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let inset: CGFloat = 6
            let usable = max(w - inset * 2, 1)
            let railY: CGFloat = 10

            ZStack(alignment: .topLeading) {
                // Relay glyphs communicate server-returned order only. They do
                // not imply distance, track shape, or position between calls.
                if ribbonNodes.count > 1 {
                    ForEach(0..<(ribbonNodes.count - 1), id: \.self) { idx in
                        let left = CGFloat(idx) / CGFloat(ribbonNodes.count - 1)
                        let right = CGFloat(idx + 1) / CGFloat(ribbonNodes.count - 1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                            .position(x: inset + usable * ((left + right) / 2), y: railY)
                    }
                }

                // Work-point nodes
                ForEach(Array(ribbonNodes.enumerated()), id: \.element.id) { idx, call in
                    let frac = ribbonNodes.count > 1 ? CGFloat(idx) / CGFloat(ribbonNodes.count - 1) : 0
                    nodeMarker(for: call)
                        .position(x: inset + usable * frac, y: railY)
                }

                // Node labels
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(ribbonNodes.enumerated()), id: \.element.id) { idx, call in
                        VStack(alignment: labelAlignment(idx), spacing: 2) {
                            Text(call.yardName ?? "—")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(isNextCall(call) ? Brand.warning : palette.textPrimary)
                            Text(callDetailLine(call))
                                .font(.system(size: 9)).monospaced()
                                .foregroundStyle(isNextCall(call) ? Brand.warning : palette.textTertiary)
                        }
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: frameAlignment(idx))
                    }
                }
                .offset(y: railY + 12)
            }
        }
        .frame(height: 62)
        // The ribbon is a drawing, so it is one element carrying a text
        // alternative read off the same decoded calls it plots. A blanket label
        // would have replaced the children and silenced every yard name, time
        // and call state on it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ordered rail work points")
        .accessibilityValue(workPointSequenceTextEquivalent)
    }

    /// The textual equivalent of the work-point ribbon. Every clause is read off
    /// the same decoded calls the ribbon draws — the yard name, the time or
    /// detail line under it, whether the server cleared it, and which node is
    /// the next call. Nothing is described that is not on screen, and the caveat
    /// that no track geometry or projected position is drawn is stated first.
    private var workPointSequenceTextEquivalent: String {
        let nodes = ribbonNodes
        guard !nodes.isEmpty else {
            return "No track geometry or projected train position is rendered. No work points were returned for this run."
        }
        let word = nodes.count == 1 ? "work point" : "work points"
        var bits: [String] = [
            "No track geometry or projected train position is rendered. \(nodes.count) \(word), in order:"
        ]
        for (idx, call) in nodes.enumerated() {
            var parts: [String] = ["\(idx + 1). \(call.yardName ?? "yard not reported")"]
            parts.append(callDetailSpoken(call))
            if call.isCleared { parts.append("cleared") }
            if isNextCall(call) { parts.append("next call") }
            bits.append(parts.joined(separator: ", ") + ".")
        }
        return bits.joined(separator: " ")
    }

    /// The node's second line said in words. The em-dash placeholder the ribbon
    /// prints when the lineup carried no time, detail or status is spoken as the
    /// absence it stands for.
    private func callDetailSpoken(_ call: LineupCall709) -> String {
        let line = callDetailLine(call)
        return line == "—" ? "time not reported" : line
    }

    private func labelAlignment(_ idx: Int) -> HorizontalAlignment {
        idx == 0 ? .leading : (idx == ribbonNodes.count - 1 ? .trailing : .center)
    }

    private func frameAlignment(_ idx: Int) -> Alignment {
        idx == 0 ? .leading : (idx == ribbonNodes.count - 1 ? .trailing : .center)
    }

    private func isNextCall(_ call: LineupCall709) -> Bool { call.id == nextCall?.id }

    private func callDetailLine(_ call: LineupCall709) -> String {
        [call.timeLabel, call.detail].compactMap { $0 }.first ?? (call.status ?? "—")
    }

    @ViewBuilder private func nodeMarker(for call: LineupCall709) -> some View {
        if call.isCleared {
            Circle().fill(palette.textPrimary).frame(width: 11, height: 11)
        } else if isNextCall(call) {
            Circle().fill(palette.bgCard).frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(Brand.warning, lineWidth: 2.4))
        } else {
            Circle().fill(palette.bgCard).frame(width: 11, height: 11)
                .overlay(Circle().strokeBorder(palette.textTertiary, lineWidth: 2))
        }
    }

    // MARK: NEXT WORK EVENT

    private var nextWorkTrailing: String {
        guard let h = remainingHours, remainingCalls > 0 else { return "run complete" }
        let perCall = h / Double(max(remainingCalls, 1))
        return "next in ~\(Int((perCall * 60).rounded())) min"
    }

    @ViewBuilder private var nextWorkCard: some View {
        if let call = nextCall {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Brand.hazmat.opacity(0.16)).frame(width: 40, height: 40)
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Brand.warning)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(nextWorkTitle(call))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(palette.textPrimary)
                            Text(call.detail ?? call.status ?? "no work detail returned")
                                .font(.system(size: 10)).monospaced()
                                .foregroundStyle(palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if let t = call.timeLabel {
                            Text(t).font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(Brand.warning)
                        }
                    }
                    Divider().overlay(palette.borderFaint)
                    HStack {
                        Text(runAuthorityLine)
                            .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 8)
                        Text((call.status ?? "scheduled").uppercased())
                            .font(.system(size: 10, weight: .heavy)).monospaced()
                            .foregroundStyle(palette.textPrimary)
                    }
                }
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(nextWorkAccessibilityLabel(call))
        } else {
            LifecycleCard {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No work event ahead").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text("Every call on the lineup is cleared.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("No work event ahead. Every call on the lineup is cleared.")
        }
    }

    /// Reads the next work event as one statement rather than as the six loose
    /// fragments the card is laid out from. Every clause is decoded state.
    private func nextWorkAccessibilityLabel(_ call: LineupCall709) -> String {
        var bits: [String] = ["Next work event", nextWorkTitle(call)]
        bits.append(call.detail ?? call.status ?? "no work detail returned")
        if let t = call.timeLabel { bits.append("scheduled \(t)") }
        bits.append(runAuthorityLine)
        bits.append("status \(call.status ?? "scheduled")")
        return bits.joined(separator: ". ") + "."
    }

    private func nextWorkTitle(_ call: LineupCall709) -> String {
        if let label = lineup?.nextCallLabel, !label.isEmpty,
           call.yardName == lineup?.nextCallYardName {
            return "\(label) · \(call.yardName ?? "")".trimmingCharacters(in: CharacterSet(charactersIn: " ·"))
        }
        return call.yardName ?? "Next call"
    }

    private var runAuthorityLine: String {
        if let dest = anchor?.destination, !dest.isEmpty { return "Run authority to \(dest)" }
        if let last = calls.last?.yardName { return "Run authority to \(last)" }
        return "Run authority not returned"
    }

    // MARK: HOS BURN

    /// The section's trailing text carries the evidence state as well as the
    /// ceiling, and `sectionLabel` folds both into its accessibility label —
    /// so the state is announced before the strip itself is reached.
    private var hosSectionTrailing: String {
        hosEvidenceCurrent
            ? "\(Int(hosLimitHours))h limit"
            : "\(Int(hosLimitHours))h limit · \(hosEvidenceStateWord)"
    }

    private func statePill(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).kerning(0.3).foregroundStyle(c)
            .padding(.horizontal, 10).frame(height: 20)
            .background(Capsule().fill(c.opacity(0.14)))
    }

    private var hosBurnCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                if let on = onDutyHours {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(hoursMinutes(on))
                            .font(.system(size: 22, weight: .heavy, design: .monospaced)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                        Text("on duty").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                } else {
                    // SUPPRESS THE VERDICT. Without current sourced evidence
                    // the strip draws no duty figure, no burn bar, no burn
                    // colour and no hours-remaining — it names the missing
                    // condition on the provenance line below instead.
                    Text("§228 verdict withheld")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                if let left = hoursRemaining {
                    Text("\(hoursMinutes(left)) left")
                        .font(.system(size: 13, weight: .heavy)).foregroundStyle(burnColor)
                } else {
                    statePill(hosEvidenceStateWord, Brand.warning)
                }
            }

            if onDutyHours != nil {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.textPrimary.opacity(0.08)).frame(height: 10)
                        Capsule().fill(burnColor)
                            .frame(width: geo.size.width * CGFloat(burnFraction), height: 10)
                        // The §228 limit tick, at the far end of the 12h scale.
                        Rectangle().fill(Brand.danger)
                            .frame(width: 2, height: 22)
                            .offset(x: geo.size.width - 2, y: -6)
                    }
                }
                .frame(height: 10)
                .accessibilityHidden(true)
            }

            HStack {
                Text(hosProvenanceLine)
                    .font(.system(size: 9.5)).monospaced().foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("\(Int(hosLimitHours))h §228 LIMIT")
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.danger)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hosAccessibilityLabel)
    }

    /// Spoken form of the §228 burn strip. The evidence state is spoken in the
    /// same three-state vocabulary the pill shows — a colour change alone is
    /// not a state change for a VoiceOver user. It never reports zero hours on
    /// duty, and it never reads the burn bar (withheld with the verdict).
    private var hosAccessibilityLabel: String {
        var bits: [String] = ["Hours of service burn, 49 CFR section 228."]
        if let on = onDutyHours {
            bits.append("Duty evidence current.")
            bits.append("\(hoursMinutes(on)) on duty.")
            if let left = hoursRemaining { bits.append("\(hoursMinutes(left)) left.") }
            bits.append("\(dutyWindowLine).")
        } else {
            bits.append("Section 228 verdict withheld. Duty evidence \(hosEvidenceStateWord.lowercased()).")
            bits.append("\(hosProvenanceLine).")
        }
        bits.append("\(Int(hosLimitHours)) hour section 228 limit.")
        return bits.joined(separator: " ")
    }

    private var dutyWindowLine: String {
        guard let start = onDutyStart else { return "on-duty time not recorded" }
        let limit = dutyLimitAt.map { clockFormatter.string(from: $0) } ?? "—"
        return "on duty \(clockFormatter.string(from: start)) · limit \(limit)"
    }

    /// Names the ONE evidence condition that is actually in force, walking the
    /// gate's own ladder in the gate's own order. The strip has to say what it
    /// cannot judge and why, not merely that it declined to judge.
    private var hosEvidenceGapLine: String {
        guard let row = conductorHOSRow else { return "no §228 duty row returned for this conductor" }
        guard validDutyHours(row.hoursOnDuty) != nil else { return "duty hours not recorded on the §228 row" }
        if row.tracked != true { return "duty evidence is not tracked" }
        if row.trackingState != .tracked {
            return "tracking state: \(row.trackingState?.displayName.lowercased() ?? "unavailable")"
        }
        if row.observationState != "current" {
            return "observation state: \(row.observationState ?? "unavailable"), not current"
        }
        if row.source?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            return "duty evidence names no source"
        }
        switch HOSObservationClock.freshness(row.freshness) {
        case .current:     return dutyWindowLine
        case .stale:       return "duty observation is stale"
        case .unavailable: return "duty observation carries no timestamp"
        case .invalid:     return "duty observation timestamp is unreadable"
        }
    }

    /// The strip's provenance line: the transport failure if there was one,
    /// else the duty window when the evidence is current, else the missing
    /// condition. It is never blank and never reassuring by default.
    private var hosProvenanceLine: String {
        if let err = hosLoadError { return "HOS unavailable · \(err)" }
        if hosEvidenceCurrent { return dutyWindowLine }
        return hosEvidenceGapLine
    }

    private func hoursMinutes(_ h: Double) -> String {
        let mins = Int((h * 60).rounded())
        return "\(mins / 60)h \(String(format: "%02d", mins % 60))m"
    }

    // MARK: ON THIS CONSIST

    private var consistTrailing: String {
        var bits: [String] = []
        if let n = consist?.consistNumber { bits.append(n) }
        if let cars = consist?.totalCars ?? lineup?.carCount { bits.append("\(cars) cars") }
        return bits.isEmpty ? "—" : bits.joined(separator: " · ")
    }

    @ViewBuilder private var consistCrewCard: some View {
        let rows = [conductorRow, engineerRow].compactMap { $0 }
        if rows.isEmpty {
            LifecycleCard {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No crew rows returned").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text("No crew assignment is recorded for this consist.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("No crew rows returned. No crew assignment is recorded for this consist.")
        } else {
            HStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    if idx > 0 {
                        Rectangle().fill(palette.borderFaint).frame(width: 1, height: 36)
                            .accessibilityHidden(true)
                    }
                    HStack(spacing: 10) {
                        initialsDisc(row.discInitials,
                                     size: 32,
                                     fill: row.isEngineer ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(Brand.info),
                                     fontSize: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.displayLabel)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(palette.textPrimary).lineLimit(1)
                            Text(crewDutyLine(row))
                                .font(.system(size: 9)).monospaced()
                                .foregroundStyle(palette.textTertiary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.displayLabel). \(crewDutyLine(row)).")
                }
            }
            .padding(.vertical, 14)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    /// The crew card states a duty figure, not a §228 verdict — so the figure
    /// stays, but it is marked UNVERIFIED when the row carries no current
    /// sourced observation, rather than reading as an evidenced duty total.
    private func crewDutyLine(_ row: CrewRow709) -> String {
        let role = (row.role ?? "crew").lowercased()
        guard let h = validDutyHours(row.hoursOnDuty) else { return "\(role) · duty not recorded" }
        let evidenceSuffix = hasCurrentObservation(row) ? "" : " · UNVERIFIED"
        return "\(role) · \(hoursMinutes(h)) on duty\(evidenceSuffix)"
    }

    /// Decorative: the disc's initials are always restated in full by the label
    /// beside it, so VoiceOver reads the person once rather than twice.
    private func initialsDisc(_ initials: String, size: CGFloat, fill: AnyShapeStyle, fontSize: CGFloat) -> some View {
        ZStack {
            Circle().fill(fill).frame(width: size, height: size)
            Text(initials)
                .font(.system(size: fontSize, weight: .bold)).kerning(0.4)
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }

    // MARK: Tri-country band + CTA

    private var triCountryBand: some View {
        HStack(spacing: Space.s2) {
            countryTile("US · FRA", "§228 · 12h", active: true)
            countryTile("CA · TC", "Work/Rest 2023", active: false)
            countryTile("MX · ARTF", "LRSF jornada", active: false)
        }
    }

    private func countryTile(_ top: String, _ bottom: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(top).font(.system(size: 8, weight: .heavy)).kerning(0.3)
            Text(bottom).font(.system(size: 9, weight: .heavy))
        }
        .foregroundStyle(active ? Brand.info : palette.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).frame(height: 30)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.borderSoft))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(top), \(bottom)\(active ? ", active regime" : "")")
    }

    /// Both controls are real Buttons held disabled, not styled text pretending
    /// to be tappable. Neither receiver exists: no rail procedure backs a
    /// conductor work-event completion write (RAIL-CDR-709-WORK-EVENT-DONE), and
    /// no rail procedure returns the car roster for a named consist
    /// (`getRailcars` is yard-scoped, not consist-scoped). Each carries the
    /// 0.5 disabled treatment AND states its own reason to VoiceOver, so the
    /// control is never silently inert in either modality.
    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button {} label: {
                Text("Log the set-out")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .disabled(true)
            .opacity(0.5)
            .accessibilityLabel("Log the set-out")
            .accessibilityValue("Unavailable — set-out recording is not served, so the work event stays open.")
            .accessibilityHint("Contact rail operations to record the work event.")

            Button {} label: {
                Text("Consist list")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 148)
                    .frame(minHeight: 48)
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().strokeBorder(palette.borderSoft))
            }
            .buttonStyle(.plain)
            .disabled(true)
            .opacity(0.5)
            .accessibilityLabel("Consist list")
            .accessibilityValue("Unavailable — no rail procedure returns the car roster for this consist.")
        }
    }

    private func notWiredCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Brand.warning)
                .accessibilityHidden(true)
            Text(text).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(Brand.warning.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.warning.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning. \(text)")
    }

    // MARK: Section label

    private func sectionLabel(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title).font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(trailing).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(trailing).")
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Data

    private struct RailShipmentsInput: Encodable { let limit: Int }
    private struct LineupInput: Encodable { let railId: String }
    private struct TrackingInput: Encodable { let shipmentId: Int }
    // Two shapes rather than one optional field: zod `.optional()` accepts an
    // absent key, not an explicit null, so we never encode `status: null`.
    private struct ConsistsByStatusInput: Encodable { let status: String; let limit: Int }
    private struct ConsistsAnyInput: Encodable { let limit: Int }
    private struct CrewInput: Encodable { let limit: Int }

    private func load() async {
        loading = true; loadError = nil
        loadedAt = .now

        // 1 · The run anchor. Everything downstream needs its id / railRef.
        do {
            let rows: [RunAnchor709] = try await EusoTripAPI.shared
                .query("railShipments.getRailShipments", input: RailShipmentsInput(limit: 1))
            anchor = rows.first
        } catch {
            loadError = error.eusoUserCopy
        }

        // 2 · The named work points on the ribbon.
        if let railId = anchor?.railRef, !railId.isEmpty {
            lineup = try? await EusoTripAPI.shared
                .query("railShipments.getServiceLineup", input: LineupInput(railId: railId))
        }

        // 3 · The position fix that dates the spine (READ_CACHED tier).
        if let sid = anchor?.numericId {
            tracking = try? await EusoTripAPI.shared
                .query("railShipments.getRailTracking", input: TrackingInput(shipmentId: sid))
        }

        // 4 · The consist — car count and the conductorId/engineerId that bind
        //     the crew rows to this run.
        if let env: ConsistEnvelope709 = try? await EusoTripAPI.shared
            .query("railShipments.getTrainConsists", input: ConsistsByStatusInput(status: "in_transit", limit: 1)),
           let first = env.consists?.first {
            consist = first
        } else if let env: ConsistEnvelope709 = try? await EusoTripAPI.shared
            .query("railShipments.getTrainConsists", input: ConsistsAnyInput(limit: 1)) {
            consist = env.consists?.first
        }

        // 5 · Crew identity for the two initials discs.
        crew = (try? await EusoTripAPI.shared
            .query("railShipments.getRailCrew", input: CrewInput(limit: 50))) ?? []

        // 6 · §228 duty hours for the burn strip. A transport/decoder failure
        // is not an empty roster and cannot fall back to generic crew data.
        do {
            hosRows = try await EusoTripAPI.shared
                .queryNoInput("railShipments.getRailCrewHOS")
            hosLoadError = nil
        } catch {
            hosRows = []
            hosLoadError = error.eusoUserCopy
        }

        loading = false
    }
}

#Preview("709 · Rail Conductor Cab Run · Light") {
    RailConductorCabRunScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}

#Preview("709 · Rail Conductor Cab Run · Dark") {
    RailConductorCabRunScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
