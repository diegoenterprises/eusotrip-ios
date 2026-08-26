//
//  712_RailConductorJobBriefingTieUp.swift
//  EusoTrip — Rail Conductor · Job Briefing and Tie-Up (CONDUCTOR SIDE, shift bookends).
//
//  Author of record: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//
//  Faithful 1:1 port of "05 Rail/Light-SVG/712 Rail Conductor Job Briefing and
//  Tie-Up.svg" (and its Dark twin). Same sections, same order, same values —
//  every value below is decoded from a real procedure or derived from decoded
//  state. No mock arrays, no placeholder rows, no fabricated sign-off.
//
//  ARCHETYPE: TIMELINE + SIGN-OFF GATE on a VERTICAL SHIFT SPINE. One
//  continuous vertical rule runs from the on-duty call, through the 49 CFR
//  §218.99 job briefing acknowledgement and the run's work events, to the
//  tie-up report; the timestamp sits in a mono LEFT GUTTER outside the rule and
//  the event sits to its right. Completed nodes solid, current node ringed in
//  the house gradient, future nodes hollow. There is no queued node: neither
//  sign-off has a write to queue (both verified absent server-side), so a
//  dashed queued ring would assert a pending regulatory sign-off that does not
//  exist. Deliberately unlike its sibling 709, which is horizontal and
//  spatial; this one is vertical and chronological.
//
//  ── WIRING MANIFEST ────────────────────────────────────────────────────────
//    railShipments.getRailCrew           EXISTS railShipments.ts:2453  → crew row: role, assignedAt, relievedAt, hoursOnDuty
//    railShipments.getRailCrewHOS        EXISTS railShipments.ts:2471  → §228 duty hours for the gate's HOS condition
//    railShipments.getCrewHOS            EXISTS railShipments.ts:2236  → CloudMoyo per-crewMemberId HOS (secondary read)
//    railShipments.getTrainConsists      EXISTS railShipments.ts:1332  → the consist this shift is tied to
//    railShipments.getRailShipments      EXISTS railShipments.ts:421   → the run anchor (numeric shipment id)
//    railShipments.getRailShipmentDetail EXISTS railShipments.ts:543   → rail_shipment_events → the completed work-event nodes
//    railShipments.getRailInspections EXISTS railShipments.ts:3030  → the briefing / inspection record behind the §218.99 node
//    briefing acknowledgement WRITE      STUB · named-gap RAIL-CDR-712-BRIEFING-ACK
//    tie-up submission WRITE             STUB · named-gap RAIL-CDR-712-TIEUP-SUBMIT
//        Both VERIFIED ABSENT: grep of railShipments.ts, railMechanical.ts, railGate.ts
//        and railTrust.ts returns zero matches for tieUp / jobBriefing / briefingAck /
//        safetyBriefing / 218.99. These are regulatory sign-offs, so both CTAs render an
//        honest "not yet wired" state and never a fabricated success.
//    Realtime (when the writes land): WS_EVENTS.RAIL_CONSIST_UPDATE (:411) on ack,
//        RAIL_CREW_HOS_WARNING (:409) when the recorded duty crosses the limit;
//        channel WS_CHANNELS.RAIL_DISPATCH (:623).
//    RBAC: railReadProcedure (railShipments.ts:94), RAIL_CONDUCTOR (trpc.ts:33).
//    OFFLINE: ONLINE_ONLY(regulatory sign-off of record) for both writes, and
//        READ_CACHED for the reads that build the spine. §218.99 and §228 sign-offs
//        are records of record: they are never held on device and replayed. The
//        earlier QUEUE(compliance) declaration was never honoured in the Swift —
//        there is no queue lane here, and the CTA comment below already states the
//        rule ("a regulatory sign-off is never queued here and never faked"). If a
//        queued lane is ever authorised for these writes, the queued node returns
//        with it (see NodeState712).
//    NAV (carrier family): HOME · SHIPMENTS · [orb] · COMPLIANCE(current) · ME.
//

import SwiftUI

// MARK: - Screen

struct RailConductorJobBriefingTieUpScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailConductorJobBriefingTieUpBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Decode helpers

private func flex712Double<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Double? {
    if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
    if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Double(s) }
    return nil
}

private func flex712Int<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Int? {
    if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return i }
    if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Int(s) }
    if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(d) }
    return nil
}

private func parse712Date(_ s: String?) -> Date? {
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

private let clock712: DateFormatter = {
    let f = DateFormatter(); f.locale = .current; f.dateFormat = "HH:mm"; return f
}()

// MARK: - Data shapes

private struct RunAnchor712: Decodable {
    let id: String
    let railRef: String?
    let destination: String?
    var numericId: Int? { Int(id.filter(\.isNumber)) }
}

private struct ConsistEnvelope712: Decodable {
    let consists: [Consist712]?
    let total: Int?
}

private struct Consist712: Decodable {
    let id: Int?
    let consistNumber: String?
    let totalCars: Int?
    let conductorId: Int?
    let engineerId: Int?

    enum CodingKeys: String, CodingKey { case id, consistNumber, totalCars, conductorId, engineerId }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = flex712Int(c, .id)
        consistNumber = try c.decodeIfPresent(String.self, forKey: .consistNumber)
        totalCars     = flex712Int(c, .totalCars)
        conductorId   = flex712Int(c, .conductorId)
        engineerId    = flex712Int(c, .engineerId)
    }
}

/// `rail_crew_assignments` row (getRailCrew railShipments.ts:2453 / getRailCrewHOS railShipments.ts:2471).
private struct CrewRow712: Decodable, Identifiable {
    let id: String
    let userId: Int?
    let consistId: Int?
    let role: String?
    let name: String?
    let crewId: String?
    let assignedAt: String?
    let relievedAt: String?
    let hoursOnDuty: Double?
    let tracked: Bool?
    let trackingState: HOSTrackingState?
    let source: String?
    let freshness: String?
    let observationState: String?

    enum CodingKeys: String, CodingKey {
        case id, userId, consistId, role, name, crewId, assignedAt, relievedAt, hoursOnDuty
        case crewName, onDutyHours
        case tracked, trackingState, source, freshness, observationState
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let stringId = try? c.decodeIfPresent(String.self, forKey: .id),
           !stringId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            id = stringId
        } else if let intId = flex712Int(c, .id) {
            id = String(intId)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: c,
                debugDescription: "Rail crew HOS rows require a stable identity."
            )
        }
        userId    = flex712Int(c, .userId)
        consistId = flex712Int(c, .consistId)
        role      = try c.decodeIfPresent(String.self, forKey: .role)
        name      = (try? c.decodeIfPresent(String.self, forKey: .name))
                     ?? (try? c.decodeIfPresent(String.self, forKey: .crewName)) ?? nil
        crewId    = try c.decodeIfPresent(String.self, forKey: .crewId)
        assignedAt = try c.decodeIfPresent(String.self, forKey: .assignedAt)
        relievedAt = try c.decodeIfPresent(String.self, forKey: .relievedAt)
        hoursOnDuty = flex712Double(c, .hoursOnDuty) ?? flex712Double(c, .onDutyHours)
        tracked = try c.decodeIfPresent(Bool.self, forKey: .tracked)
        trackingState = try c.decodeIfPresent(HOSTrackingState.self, forKey: .trackingState)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        freshness = try c.decodeIfPresent(String.self, forKey: .freshness)
        observationState = try c.decodeIfPresent(String.self, forKey: .observationState)
    }

    var isConductor: Bool { (role ?? "").lowercased() == "conductor" }

    /// Initials for the sign-off disc — derived only from decoded text, never
    /// invented, and never replaced by a glyph.
    var discInitials: String {
        if let n = name?.trimmingCharacters(in: .whitespaces), !n.isEmpty {
            let s = n.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined()
            if !s.isEmpty { return s.uppercased() }
        }
        if let c = crewId?.filter(\.isLetter), c.count >= 2 { return String(c.suffix(2)).uppercased() }
        if let u = userId { return String(String(u).suffix(2)) }
        return String(String(id).suffix(2))
    }

    var displayLabel: String {
        if let n = name?.trimmingCharacters(in: .whitespaces), !n.isEmpty { return n }
        if let c = crewId, !c.isEmpty { return c }
        if let u = userId { return "Crew #\(u)" }
        return "Crew #\(id)"
    }
}

/// `railShipments.getRailShipmentDetail` (railShipments.ts:543) — only the fields the spine uses.
private struct ShipmentDetail712: Decodable {
    let shipmentNumber: String?
    let status: String?
    let events: [ShipmentEvent712]?
}

private struct ShipmentEvent712: Decodable {
    let id: Int?
    let eventType: String?
    let description: String?
    let timestamp: String?
    let location: EventLocation712?

    enum CodingKeys: String, CodingKey { case id, eventType, description, timestamp, location }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = flex712Int(c, .id)
        eventType   = try c.decodeIfPresent(String.self, forKey: .eventType)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        timestamp   = try c.decodeIfPresent(String.self, forKey: .timestamp)
        location    = try? c.decodeIfPresent(EventLocation712.self, forKey: .location)
    }

    var at: Date? { parse712Date(timestamp) }
}

private struct EventLocation712: Decodable {
    let lat: Double?
    let lng: Double?
    let description: String?
}

/// `railShipments.getRailInspections` (railShipments.ts:3030) — the projected row.
private struct Inspection712: Decodable, Identifiable {
    let id: String
    let type: String?
    let date: String?
    let location: String?
    let status: String?
    let inspector: String?
    let notes: String?
    let passed: Bool?

    var at: Date? { parse712Date(date) }

    /// True when this inspection row IS the §218.99 job briefing record.
    var isJobBriefing: Bool {
        let hay = [(type ?? ""), (notes ?? "")].joined(separator: " ").lowercased()
        return hay.contains("briefing") || hay.contains("218.99") || hay.contains("job brief")
    }
}

// MARK: - Spine node model (assembled from decoded rows only)

/// No `queued` state: a queued node stands for a WRITE held on device awaiting
/// commit, and neither sign-off on this screen has a write to hold — both are
/// verified absent server-side (RAIL-CDR-712-BRIEFING-ACK, RAIL-CDR-712-TIEUP-SUBMIT)
/// and both CTAs are really disabled. Constructing a queued node today would
/// assert a pending regulatory sign-off that does not exist. When either write
/// lands, restore `case queued` here plus its dashed-amber-ring branch in
/// `nodeDot` and its `Brand.warning` branch in `chipColor`.
private enum NodeState712 { case committed, current, future }

private struct SpineNode712: Identifiable {
    let id: String
    let at: Date?
    let title: String
    let detail: String
    let state: NodeState712
    let chip: String
}

// MARK: - Body

private struct RailConductorJobBriefingTieUpBody: View {
    @Environment(\.palette) private var palette

    @State private var anchor: RunAnchor712? = nil
    @State private var consist: Consist712? = nil
    @State private var crew: [CrewRow712] = []
    @State private var hosRows: [CrewRow712] = []
    @State private var detail: ShipmentDetail712? = nil
    @State private var inspections: [Inspection712] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    private let hosLimitHours: Double = 12.0   // 49 CFR §228, US regime

    // MARK: Derived

    private var conductorRow: CrewRow712? {
        if let cid = consist?.conductorId, let m = crew.first(where: { $0.userId == cid }) { return m }
        if let cid = consist?.id, let m = crew.first(where: { $0.consistId == cid && $0.isConductor }) { return m }
        return nil
    }

    private var onDutyAt: Date? { parse712Date(conductorRow?.assignedAt) }
    private var relievedAt: Date? { parse712Date(conductorRow?.relievedAt) }

    private var conductorHOSRow: CrewRow712? {
        if let uid = conductorRow?.userId,
           let row = hosRows.first(where: { $0.userId == uid }) { return row }
        return hosRows.first(where: { $0.isConductor })
    }

    private var onDutyHours: Double? {
        guard hosEvidenceCurrent else { return nil }
        return validDutyHours(conductorHOSRow?.hoursOnDuty)
    }

    private var hoursRemaining: Double? {
        onDutyHours.map { max(hosLimitHours - $0, 0) }
    }

    /// The server-side briefing record, if one exists.
    private var briefingRecord: Inspection712? { inspections.first(where: { $0.isJobBriefing }) }

    private var briefingCommitted: Bool { briefingRecord != nil }
    private var hosRecorded: Bool { validDutyHours(conductorHOSRow?.hoursOnDuty) != nil }
    private var hosEvidenceCurrent: Bool {
        guard let row = conductorHOSRow, validDutyHours(row.hoursOnDuty) != nil else { return false }
        return row.tracked == true
            && row.trackingState == .tracked
            && row.observationState == "current"
            && row.source?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && HOSObservationClock.freshness(row.freshness).isCurrent
    }

    /// The tie-up gate, shown and never hidden: BOTH conditions must be
    /// COMMITTED (not merely queued) before a tie-up can be submitted.
    private var gateSatisfiedCount: Int {
        (briefingCommitted ? 1 : 0) + (hosEvidenceCurrent ? 1 : 0)
    }
    private var gateOpen: Bool { gateSatisfiedCount == 2 }

    /// The gap card names the blocker that is ACTUALLY in force, on the same
    /// `gateOpen` state the gate block below renders from. When the gate is open
    /// the only blocker left is the missing submit procedure — the screen must
    /// not read "open" and "closed" in the same traversal.
    private var signOffGapCopy: String {
        if gateOpen {
            return "Briefing acknowledgement and tie-up submission are unavailable. The compliance gate is open, \(gateSatisfiedCount) of 2 committed, but no tie-up submit procedure exists; contact crew management to record either sign-off."
        }
        return "Briefing acknowledgement and tie-up submission are unavailable. The compliance gate remains closed, \(gateSatisfiedCount) of 2 committed; contact crew management to record either sign-off."
    }

    /// The submit CTA is disabled either way — the tie-up write does not exist —
    /// but it states the reason that is true right now rather than asserting a
    /// closed gate over an open one.
    private var submitTieUpSpokenValue: String {
        if gateOpen {
            return "Unavailable. The compliance gate is open, \(gateSatisfiedCount) of 2 committed, but tie-up submission is not wired. Contact crew management to record the sign-off."
        }
        return "Unavailable. Tie-up submission is not wired and the compliance gate remains closed, \(gateSatisfiedCount) of 2 committed. Contact crew management to record the sign-off."
    }

    /// Work-event nodes, oldest first — exactly the rows the server returned.
    private var workEvents: [ShipmentEvent712] {
        (detail?.events ?? [])
            .filter { $0.at != nil }
            .sorted { ($0.at ?? .distantPast) < ($1.at ?? .distantPast) }
    }

    /// The spine. Assembled from decoded rows; a node the server has no basis
    /// for is rendered hollow with an honest label rather than omitted or faked.
    private var spine: [SpineNode712] {
        var nodes: [SpineNode712] = []

        // 1 · On-duty call
        nodes.append(SpineNode712(
            id: "onduty",
            at: onDutyAt,
            title: "On-duty call",
            detail: onDutyAt == nil ? "on-duty time not recorded" : "§228 duty clock starts",
            state: onDutyAt == nil ? .future : .committed,
            chip: onDutyAt == nil ? "MISSING" : "LOGGED"))

        // 2 · §218.99 job briefing
        let briefState: NodeState712 = briefingCommitted ? .committed : .future
        nodes.append(SpineNode712(
            id: "briefing",
            at: briefingRecord?.at,
            title: "Job briefing acknowledged",
            detail: briefingDetailLine,
            state: briefState,
            chip: briefingCommitted ? "LOGGED" : "NOT ACKED"))

        // 3…n · The run's work events, verbatim from rail_shipment_events
        let latest = workEvents.last
        for ev in workEvents {
            let isLatest = ev.id != nil && ev.id == latest?.id
            nodes.append(SpineNode712(
                id: "ev-\(ev.id ?? 0)-\(ev.timestamp ?? "")",
                at: ev.at,
                title: prettyEventType(ev.eventType),
                detail: ev.description ?? ev.location?.description ?? (ev.eventType ?? "—"),
                state: isLatest ? .current : .committed,
                chip: isLatest ? "NOW" : "LOGGED"))
        }

        // n+1 · Tie-up report
        let tieState: NodeState712 = relievedAt != nil ? .committed : .future
        nodes.append(SpineNode712(
            id: "tieup",
            at: relievedAt,
            title: "Tie-up report",
            detail: tieUpDetailLine,
            state: tieState,
            chip: relievedAt != nil ? "LOGGED" : (gateOpen ? "OPEN" : "GATED")))

        return nodes
    }

    private var briefingDetailLine: String {
        if let r = briefingRecord {
            let who = r.inspector.map { " · \($0)" } ?? ""
            return "49 CFR §218.99\(who)"
        }
        return "49 CFR §218.99 · not acknowledged"
    }

    /// The spine node reads off the SAME `gateOpen` state the gate block below
    /// renders from. When the gate is open the tie-up is not gated — the only
    /// thing still holding it is the missing submit procedure, which is what
    /// the gap card and the disabled CTA already say. The screen must not read
    /// "gated" and "open" in one traversal.
    private var tieUpDetailLine: String {
        if relievedAt != nil { return (anchor?.destination ?? "relieved") }
        if gateOpen { return "gate open · \(gateSatisfiedCount) of 2 committed · submit not wired" }
        return "gated below · \(gateSatisfiedCount) of 2 committed"
    }

    private func prettyEventType(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "Run event" }
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: View

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                headline
                chipRow
                IridescentHairline().accessibilityHidden(true)

                if loading {
                    LifecycleCard { Text("Loading the shift record…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Shift record unavailable. \(err)")
                } else if conductorRow == nil {
                    LifecycleCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No duty record").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                            Text("No crew assignment is recorded for this crew member, so a shift cannot be reconstructed.")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("No duty record. No crew assignment is recorded for this crew member, so a shift cannot be reconstructed.")
                } else {
                    shiftSpineHero
                    notWiredCard(signOffGapCopy)
                    sectionLabel("SIGN-OFF · §218.99 AND §228", trailing: "gate shown, not hidden")
                    signOffCard
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
            Text("RAIL CONDUCTOR · JOB BRIEFING")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.diagonal)
            Spacer()
            Text("49 CFR §218.99")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).monospaced()
                .foregroundStyle(palette.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rail conductor, job briefing. 49 CFR section 218.99.")
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Shift record")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                // Overflow glyph with no receiver behind it — never announced as a control.
                Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .accessibilityHidden(true)
            }
            Text(headlineSubline)
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headlineSubline: String {
        var bits: [String] = []
        if let c = conductorRow { bits.append(c.displayLabel) }
        if let d = onDutyAt { bits.append("on duty \(clock712.string(from: d))") }
        else { bits.append("on-duty time not recorded") }
        if let sym = consist?.consistNumber ?? anchor?.railRef { bits.append(sym) }
        return bits.joined(separator: " · ")
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            chip(briefingChipText, briefingCommitted ? Brand.success : palette.textTertiary)
            chip(relievedAt != nil ? "TIE-UP FILED" : "TIE-UP OPEN", relievedAt != nil ? Brand.success : Brand.warning)
            chip("SIGN-OFF UNAVAILABLE", Brand.warning)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(briefingChipText). \(relievedAt != nil ? "Tie-up filed" : "Tie-up open"). Sign-off unavailable.")
    }

    private var briefingChipText: String {
        if let r = briefingRecord, let at = r.at { return "BRIEFED \(clock712.string(from: at))" }
        if briefingCommitted { return "BRIEFED" }
        return "NOT BRIEFED"
    }

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).kerning(0.3).foregroundStyle(c)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderSoft))
    }

    // MARK: HERO — the vertical shift spine

    private var shiftSpineHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SHIFT SPINE · ON DUTY TO TIE-UP")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(Brand.info)
                Spacer()
                Text(spineBandTrailing)
                    .font(.system(size: 9, weight: .semibold)).monospaced()
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, 16).frame(height: 38)
            .background(LinearGradient(colors: [Brand.blue.opacity(0.14), Brand.magenta.opacity(0.06)],
                                       startPoint: .leading, endPoint: .trailing))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Shift spine, on duty to tie-up. \(spineBandTrailing).")
            .accessibilityAddTraits(.isHeader)

            // The continuous rule. It is drawn ONCE, behind the rows, so it runs
            // unbroken through the card — the rows never chop it into segments.
            ZStack(alignment: .topLeading) {
                GeometryReader { _ in
                    Rectangle()
                        .fill(palette.textPrimary.opacity(0.20))
                        .frame(width: 2)
                        .padding(.vertical, 10)
                        .offset(x: 76)
                }
                .accessibilityHidden(true)
                VStack(spacing: 0) {
                    ForEach(spine) { node in spineRow(node) }
                }
            }
            .padding(.vertical, 14)
        }
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    private var spineBandTrailing: String {
        var bits: [String] = []
        if let d = onDutyAt { bits.append(clock712.string(from: d)) }
        if let sym = consist?.consistNumber { bits.append(sym) }
        return bits.isEmpty ? "—" : bits.joined(separator: " · ")
    }

    private func spineRow(_ node: SpineNode712) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // LEFT GUTTER — mono timestamp, outside the rule
            Text(node.at.map { clock712.string(from: $0) } ?? "--:--")
                .font(.system(size: 11, weight: .bold, design: .monospaced)).monospacedDigit()
                .foregroundStyle(node.state == .future ? palette.textTertiary : palette.textPrimary)
                .frame(width: 66, alignment: .trailing)

            // The node dot, centred on the rule
            nodeDot(node.state)
                .frame(width: 24)
                .accessibilityHidden(true)

            // The event
            VStack(alignment: .leading, spacing: 2) {
                Text(node.title)
                    .font(.system(size: 12.5, weight: .heavy))
                    .foregroundStyle(node.state == .future ? palette.textSecondary : palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(node.detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(node.state == .future ? palette.textTertiary : palette.textSecondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Text(node.chip)
                .font(.system(size: 8.5, weight: .heavy)).kerning(0.4)
                .foregroundStyle(chipColor(node.state))
                .padding(.trailing, 16)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spineRowA11y(node))
    }

    /// One spoken statement per spine node. A node with no recorded time says so
    /// rather than reading the placeholder dashes as a value.
    private func spineRowA11y(_ node: SpineNode712) -> String {
        let when = node.at.map { clock712.string(from: $0) } ?? "time not recorded"
        return "\(when). \(node.title). \(node.detail). \(node.chip)."
    }

    @ViewBuilder private func nodeDot(_ state: NodeState712) -> some View {
        switch state {
        case .committed:
            Circle().fill(palette.textPrimary).frame(width: 10, height: 10)
        case .current:
            ZStack {
                Circle().strokeBorder(LinearGradient.diagonal, lineWidth: 2.4).frame(width: 20, height: 20)
                Circle().fill(LinearGradient.diagonal).frame(width: 10, height: 10)
            }
        case .future:
            Circle().fill(palette.bgCard).frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(palette.textTertiary, lineWidth: 2))
        }
    }

    private func chipColor(_ state: NodeState712) -> Color {
        switch state {
        case .committed: return Brand.success
        case .current:   return Brand.info
        case .future:    return palette.textTertiary
        }
    }

    // MARK: SIGN-OFF block + the gate

    private var signOffCard: some View {
        VStack(spacing: 0) {
            // Briefing acknowledgement
            HStack(spacing: 12) {
                if let c = conductorRow {
                    ZStack {
                        Circle().fill(Brand.info).frame(width: 28, height: 28)
                        Text(c.discInitials).font(.system(size: 11, weight: .bold)).kerning(0.4)
                            .foregroundStyle(.white)
                    }
                    // Initials disc — the crew identity it stands for is spoken in
                    // the combined row label below, so the disc itself is silent.
                    .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Briefing acknowledged")
                        .font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    Text(ackByLine)
                        .font(.system(size: 9.5)).monospaced().foregroundStyle(palette.textSecondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                statePill(briefingCommitted ? "COMMITTED" : "OPEN",
                          briefingCommitted ? Brand.success : palette.textTertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Briefing acknowledged. \(ackByLine).")
            .accessibilityValue(briefingCommitted ? "Committed" : "Open")

            Divider().overlay(palette.borderFaint).padding(.horizontal, 16)
                .accessibilityHidden(true)

            // HOS recorded
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("HOS recorded")
                        .font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    Text(hosLine)
                        .font(.system(size: 9.5)).monospaced().foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 6)
                statePill(
                    hosEvidenceCurrent ? "CURRENT" : (hosRecorded ? "UNVERIFIED" : "MISSING"),
                    hosEvidenceCurrent ? Brand.success : Brand.warning
                )
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Hours of service recorded. \(hosLine).")
            .accessibilityValue(hosEvidenceCurrent ? "Current" : (hosRecorded ? "Unverified" : "Missing"))

            Divider().overlay(palette.borderFaint).padding(.horizontal, 16)
                .accessibilityHidden(true)

            // THE GATE — always visible, never hidden
            HStack(spacing: 10) {
                Image(systemName: gateOpen ? "lock.open" : "lock")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(gateOpen ? Brand.success : Brand.warning)
                    .accessibilityHidden(true)
                Text(gateOpen
                     ? "Tie-up submit open · 2 of 2 committed"
                     : "Tie-up submit gated · \(gateSatisfiedCount) of 2 committed")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(gateOpen ? Brand.success : Brand.warning)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                Text(gateOpen ? "READY" : (briefingCommitted ? "HOS MUST VERIFY" : "ACK MUST COMMIT"))
                    .font(.system(size: 9, weight: .heavy)).kerning(0.3)
                    .foregroundStyle(gateOpen ? Brand.success : Brand.warning)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background((gateOpen ? Brand.success : Brand.warning).opacity(0.12))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(gateOpen
                                ? "Tie-up submit open. 2 of 2 committed. Ready."
                                : "Tie-up submit gated. \(gateSatisfiedCount) of 2 committed. \(briefingCommitted ? "Hours of service must verify" : "Acknowledgement must commit").")
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var ackByLine: String {
        if let r = briefingRecord {
            let who = r.inspector ?? conductorRow?.displayLabel ?? "crew"
            let when = r.at.map { clock712.string(from: $0) } ?? "—"
            return "\(who) · \(when) · committed"
        }
        return "no §218.99 briefing record returned"
    }

    private var hosLine: String {
        guard hosEvidenceCurrent,
              let row = conductorHOSRow,
              let on = onDutyHours,
              let left = hoursRemaining else {
            return hosRecorded
                ? "recorded duty hours are not current, sourced evidence"
                : "current sourced duty evidence unavailable"
        }
        let source = row.source?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? "SOURCE UNAVAILABLE"
        let observed = row.freshness?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "time unavailable"
        return "\(hoursMinutes(on)) on duty · \(hoursMinutes(left)) to the §228 limit · \(source) · \(observed)"
    }

    private func validDutyHours(_ hours: Double?) -> Double? {
        guard let hours, hours.isFinite, hours >= 0 else { return nil }
        return hours
    }

    private func hoursMinutes(_ h: Double) -> String {
        let mins = Int((h * 60).rounded())
        return "\(mins / 60)h \(String(format: "%02d", mins % 60))m"
    }

    private func statePill(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).kerning(0.3).foregroundStyle(c)
            .padding(.horizontal, 10).frame(height: 20)
            .background(Capsule().fill(c.opacity(0.14)))
    }

    // MARK: Tri-country band + CTA

    private var triCountryBand: some View {
        HStack(spacing: Space.s2) {
            countryTile("US · FRA", "§218.99 · §228", active: true)
            countryTile("CA · TC", "CROR · Work/Rest", active: false)
            countryTile("MX · ARTF", "RSF · jornada", active: false)
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
        .accessibilityLabel("\(top). \(bottom).")
        .accessibilityValue(active ? "Active regime" : "Not the active regime")
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            // NAMED GAP RAIL-CDR-712-TIEUP-SUBMIT. The tie-up write is verified
            // absent server-side, so this is a REAL Button that is really disabled:
            // inert, visibly dimmed, and it states why to VoiceOver. A regulatory
            // sign-off is never queued here and never faked.
            Button {} label: {
                Text("Submit tie-up")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .disabled(true)
            .opacity(0.42)
            .saturation(0.35)
            .accessibilityLabel("Submit tie-up")
            .accessibilityValue(submitTieUpSpokenValue)
            .accessibilityAddTraits(.isButton)

            // NAMED GAP RAIL-CDR-712-BRIEFING-ACK. No briefing review destination
            // exists and getRailInspections — already read above — is the only
            // briefing evidence on the rail surface, so this stays truly disabled.
            Button {} label: {
                Text("Review briefing")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 148)
                    .frame(minHeight: 48)
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().strokeBorder(palette.borderSoft))
            }
            .buttonStyle(.plain)
            .disabled(true)
            .opacity(0.42)
            .saturation(0.35)
            .accessibilityLabel("Review briefing")
            .accessibilityValue(briefingCommitted
                                ? "Unavailable. No briefing review is wired; the acknowledged record is summarised in the sign-off block above."
                                : "Unavailable. No briefing review is wired and no 49 CFR section 218.99 briefing record was returned.")
            .accessibilityAddTraits(.isButton)
        }
    }

    private func notWiredCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "tray.and.arrow.up")
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
        .accessibilityLabel(text)
    }

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

    private struct ShipmentsInput712: Encodable { let limit: Int }
    // Two shapes rather than one optional field: zod `.optional()` accepts an
    // absent key, not an explicit null, so we never encode `status: null`.
    private struct ConsistsByStatusInput712: Encodable { let status: String; let limit: Int }
    private struct ConsistsAnyInput712: Encodable { let limit: Int }
    private struct CrewInput712: Encodable { let limit: Int }
    private struct DetailInput712: Encodable { let id: Int }
    private struct InspectionsInput712: Encodable { let limit: Int }

    private func load() async {
        loading = true; loadError = nil

        // 1 · Crew + duty window — the spine's on-duty and tie-up bookends.
        do {
            crew = try await EusoTripAPI.shared
                .query("railShipments.getRailCrew", input: CrewInput712(limit: 50))
        } catch {
            loadError = error.eusoUserCopy
        }

        // 2 · §228 duty hours for the gate's HOS condition.
        do {
            hosRows = try await EusoTripAPI.shared.queryNoInput("railShipments.getRailCrewHOS")
        } catch {
            hosRows = []
            if loadError == nil {
                loadError = "Rail HOS evidence could not refresh. The tie-up compliance gate remains closed."
            }
        }

        // 3 · The consist this shift is tied to.
        if let env: ConsistEnvelope712 = try? await EusoTripAPI.shared
            .query("railShipments.getTrainConsists", input: ConsistsByStatusInput712(status: "in_transit", limit: 1)),
           let first = env.consists?.first {
            consist = first
        } else if let env: ConsistEnvelope712 = try? await EusoTripAPI.shared
            .query("railShipments.getTrainConsists", input: ConsistsAnyInput712(limit: 1)) {
            consist = env.consists?.first
        }

        // 4 · The run anchor, then its events — the completed work-event nodes.
        if let rows: [RunAnchor712] = try? await EusoTripAPI.shared
            .query("railShipments.getRailShipments", input: ShipmentsInput712(limit: 1)) {
            anchor = rows.first
        }
        if let sid = anchor?.numericId {
            detail = try? await EusoTripAPI.shared
                .query("railShipments.getRailShipmentDetail", input: DetailInput712(id: sid))
        }

        // 5 · Inspection records — the §218.99 briefing node's only real basis.
        inspections = (try? await EusoTripAPI.shared
            .query("railShipments.getRailInspections", input: InspectionsInput712(limit: 50))) ?? []

        loading = false
    }
}

#Preview("712 · Rail Conductor Job Briefing and Tie-Up · Light") {
    RailConductorJobBriefingTieUpScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}

#Preview("712 · Rail Conductor Job Briefing and Tie-Up · Dark") {
    RailConductorJobBriefingTieUpScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
