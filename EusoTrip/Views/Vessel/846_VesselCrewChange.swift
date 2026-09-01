//
//  846_VesselCrewChange.swift
//  EusoTrip — Vessel Operator · Crew Change & Sign-Off (846).
//
//  Port of "846 Vessel Crew Change & Sign-Off.svg" (Light + Dark).
//  RELIEF-PAIRING LADDER + PER-PAIR PERMISSION GATE archetype.
//
//  WHY THIS SHAPE AND NOT A ROSTER LIST. A crew change is not a list of
//  people. It is a set of PAIRS — one seafarer leaves only because a named
//  reliever arrives to stand their watch — and each pair is either permitted
//  or not permitted at a named port on a named date. The permission is not a
//  status somebody types; it is the conjunction of five separate conditions
//  held by five separate authorities (the flag administration, the port state,
//  the shipowner, the manning agent, the outgoing officer). So the screen is
//  built as a LADDER OF PAIRS, each rung carrying its own five-square gate
//  strip and its own verdict, above a gate key that tallies each condition
//  across the whole change. There is no summary hero and no metric grid: the
//  number that matters is how many pairs may lawfully change hands, and that
//  is a gate reading, not a statistic.
//
//  SIBLING SEPARATION (this band shares a crew roster, which is the clone trap):
//    · 847 Hours of Rest is a TIME sheet — one seafarer's 7×24 h record of rest
//      against two hard ceilings. It has no pairs, no port, no permission.
//    · 691 Crew Call Board is a departmental PEG BOARD for mustering a watch —
//      no relief, no border, no counter-party.
//    · 654 Crew Certifications is a certificate EXPIRY ledger — it answers
//      "is this document in date", which is ONE of the five conditions here,
//      not the organ.
//    · 711 Crew Rest Hours is a fleet-wide 24 h bar roster.
//  Nothing here shares a spine with any of them: the pair is the unit, and the
//  pair exists nowhere else on the platform.
//
//  WIRING (honest — every line below was read off the live router this fire):
//    REAL · vesselShipments.getVesselCrew — vesselShipments.ts:2417 —
//        vesselProcedure, input { companyId?: number, search?: string }.
//        Returns { crew: [{ id, name, email, phone, role, profilePicture,
//        isActive }], certifications: [ full certifications row ],
//        expiringCount }. The ladder's off-signing half is drawn from this and
//        from nothing else. An empty roster renders a real empty state.
//    REAL · vesselShipments.getVesselShipmentDetail — vesselShipments.ts:561 —
//        vesselProcedure, input { id: number }. Returns the vessel_shipments
//        row spread FLAT (no wrapper key) plus originPort / destinationPort
//        joined off `ports`. The RELIEF PORT in the H1 — its name, its
//        UNLOCODE, its country — is this payload. So is the voyage number and
//        the arrival. Note vessel_shipments carries NO vesselName column
//        (drizzle/schema.ts:11813-11850); it carries vesselId. This screen
//        therefore never prints a ship's name it cannot prove.
//    REAL · the five gate conditions are the regulation, printed as the
//        regulation: MLC 2006 Reg 2.1 (seafarers' employment agreement),
//        Reg 2.5 (repatriation is the shipowner's obligation), STCW A-VIII/2
//        (handover of the watch), and the relief port's own crew-entry regime.
//        Printing the requirement is not the same as asserting it is met.
//    LIVE GATE CONDITION (one of five) · CERTIFICATES IN DATE is computed on
//        device from the real `certifications` rows returned above — a row
//        whose status is "expired", or whose expiryDate is in the past, fails
//        the condition; a seafarer with no certificate row at all is
//        UNVERIFIED, never PASS, because an absent document and a valid one
//        are not the same fact.
//    STUB · named-gap — there is no crew-change model on disk. Grepped
//        repo-wide this fire: crewChange / signOn / signOff = 0. The read the
//        ladder wants is
//            vessel.getCrewChange({ shipmentId: number, portCallId?: string })
//              -> { portCall: { unlocode, portName, windowOpensAt,
//                               windowClosesAt, agent },
//                   pairs: [{ pairId, offSignerUserId, joinerUserId | null,
//                             joinerName | null, rank, tourStartedAt,
//                             tourMaxMonths, seaInForce: Bool,
//                             visaState: "granted"|"pending"|"refused"|null,
//                             repatriationFlight: { pnr, departsAt } | null,
//                             handoverSignedAt: string | null }] }
//        Until that exists, the joining half of EVERY rung renders as an
//        unnominated dashed slot and four of the five gate squares read
//        UNVERIFIED. No pair can read CLEARED, because nothing on the wire can
//        clear one.
//    STUB · named-gap REGULATORY WRITES — the two CTAs. Proposed:
//            vessel.recordCrewSignOff({ userId: number, shipmentId: number,
//                                       pairId: string, confirm: true })
//            vessel.recordCrewSignOn ({ userId: number, shipmentId: number,
//                                       pairId: string, confirm: true })
//        [gated + confirm:true + audit + test]. Each writes the crew_change
//        row + a blockchainAuditTrail vessel.crew_signed entry and broadcasts
//        WS_CHANNELS.VESSEL_OPS / WS_EVENTS.CREW_CHANGED. RBAC vesselProcedure
//        (master / DPA). Both controls on this screen are `.disabled(true)`
//        today with the missing procedure named in-line — they are not dimmed
//        and left tappable, and they do not mutate local state to imitate a
//        signature.
//
//  OFFLINE POLICY (doctrine §W — derived, not stamped):
//    READ  · READ_CACHED(10m). The roster and the relief port are reference
//            context an officer may legitimately read at a berth with no
//            signal. A stale roster is still a readable roster. It is made
//            VISIBLY distinct: a staleness line under the header states the
//            age of the serve in relative time, and a failed refresh banners
//            above retained content rather than blanking it.
//            HONEST SCOPE: what the code does today is retain the last decoded
//            serve IN MEMORY for the life of the session. There is no
//            persistent on-disk read cache behind it
//            (Services/EusoTripAPI.swift sets urlCache = nil), so nothing
//            survives a cold launch and the 10m TTL is a declared policy, not
//            an enforced one. OPEN item, owning lane: the-oath.
//    WRITE · ONLINE_ONLY. A crew-change clearance is a BORDER DECISION. A
//            sign-off queued at sea and replayed at the berth could assert
//            that a seafarer was relieved under a visa that had since lapsed,
//            or land a sign-on for a reliever who never cleared immigration.
//            Neither control is ever queued, and no local state is mutated to
//            look as though a signature was taken.
//
//  CHAIN CLOSURE: WS_EVENTS.CREW_CHANGED on WS_CHANNELS.VESSEL_OPS, intended
//    for 654 (certificate ledger) and 847 (the incoming watch's rest record).
//    OPEN counter-party item, owning lane VESSEL · the-oath: the receiving
//    half does not exist — RealtimeService.swift carries no vessel:* case and
//    Views/Vessel has zero realtime subscribers, so a recorded change would
//    land on no listener.
//
//  COUNTRY (single-country content, never a file fork): the regime that
//    governs is the RELIEF PORT's. US CBP C1/D crew visa + USCG · CA CBSA crew
//    + Transport Canada · MX INM tripulación + SEMAR. STCW and MLC 2006 are
//    shared across all three.
//
//  Persona: Lena Bjornstad · Aurora Ocean Division. The vessel operator IS the
//  carrier — no merchant-side verb appears on this surface.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselCrewChangeScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0
    var companyId: Int = 0

    var body: some View {
        Shell(theme: theme) {
            VesselCrewChangeBody(shipmentId: shipmentId, companyId: companyId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Wire shapes (mirror the live payloads exactly)

/// `getVesselCrew().crew[]` — the select list at vesselShipments.ts:2424-2432.
/// `users.id` is an Int on the server.
private struct CrewRow846: Decodable, Identifiable {
    let id: Int
    let name: String?
    let email: String?
    let phone: String?
    let role: String?
    let isActive: Bool?
}

/// `getVesselCrew().certifications[]` — `db.select().from(certifications)` at
/// :2438, so the FULL row (drizzle/schema.ts:1945): id, userId, type, name,
/// expiryDate, status, documentUrl, createdAt.
private struct CrewCert846: Decodable, Identifiable {
    let id: Int
    let userId: Int?
    let type: String?
    let name: String?
    let expiryDate: String?
    let status: String?
}

private struct CrewPayload846: Decodable {
    let crew: [CrewRow846]
    let certifications: [CrewCert846]?
    /// Absent on the no-database early return at :2422, hence optional.
    let expiringCount: Int?
}

/// A joined `ports` row (drizzle/schema.ts:11756).
private struct ReliefPort846: Decodable {
    let id: Int?
    let name: String?
    let unlocode: String?
    let city: String?
    let state: String?
    let country: String?
}

/// The FLAT root of `getVesselShipmentDetail` (vesselShipments.ts:588 returns
/// `{ ...shipment, lifecycleStage, bols, customs, events, demurrage,
/// containers, originPort, destinationPort }` — there is no `shipment`
/// wrapper). Decoding a wrapper against the real payload does not throw, it
/// silently yields nil, so this decodes off the ROOT and merely tolerates a
/// wrapper in case a future revision adds one.
private struct VoyageContext846: Decodable {
    let id: Int?
    let bookingNumber: String?
    let voyageNumber: String?
    let eta: String?
    let status: String?
    let destinationPort: ReliefPort846?
    let originPort: ReliefPort846?
}

private struct VoyageEnvelope846: Decodable {
    let context: VoyageContext846?
    private enum CodingKeys: String, CodingKey { case shipment }

    init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: CodingKeys.self),
           let wrapped = try? c.decodeIfPresent(VoyageContext846.self, forKey: .shipment) {
            self.context = wrapped
        } else {
            self.context = try? VoyageContext846(from: decoder)
        }
    }
}

// MARK: - The gate

/// One square on a pair's gate strip. `unverified` is a first-class member and
/// never a synonym for `fail`: "we do not hold this document" and "this
/// document is expired" carry different consequences at a border, and
/// collapsing them would be a lie in the direction that gets a ship detained.
private enum GateState846: Equatable {
    case pass
    case fail
    case unverified
}

/// The five conditions a relief pair must satisfy before a change of hands is
/// lawful. Each carries the instrument that requires it. `live` marks the one
/// condition this device can actually evaluate today.
private struct GateCondition846: Identifiable {
    let id = UUID()
    let short: String       // gate-square caption
    let title: String
    let instrument: String  // the regulation that requires it
    let live: Bool
}

private let gateConditions846: [GateCondition846] = [
    .init(short: "CERT",  title: "Certificates in date",
          instrument: "STCW II/1 · certificates of competency",           live: true),
    .init(short: "SEA",   title: "Employment agreement in force",
          instrument: "MLC 2006 Reg 2.1 · signed SEA",                    live: false),
    .init(short: "VISA",  title: "Relief-port crew entry granted",
          instrument: "port-state crew regime · joiner and leaver",       live: false),
    .init(short: "FLT",   title: "Repatriation flight booked",
          instrument: "MLC 2006 Reg 2.5 · shipowner obligation",          live: false),
    .init(short: "HAND",  title: "Handover completed and signed",
          instrument: "STCW A-VIII/2 · handover of the watch",            live: false)
]

/// One rung of the ladder. `offSigner` is real. `joiner` is nil for every rung
/// today because no relief record exists — the rung renders that absence
/// rather than inventing a reliever.
private struct ReliefPair846: Identifiable {
    let id: Int
    let offSigner: CrewRow846
    let joinerName: String?
    let states: [GateState846]

    var verdict: (String, Color) {
        if states.contains(where: { if case .fail = $0 { return true }; return false }) {
            return ("BLOCKED", Brand.danger)
        }
        if states.contains(where: { if case .unverified = $0 { return true }; return false }) {
            return ("NOT CLEARED", Brand.warning)
        }
        return ("CLEARED", Brand.success)
    }
}

// MARK: - Body

private struct VesselCrewChangeBody: View {
    @Environment(\.palette) private var palette

    let shipmentId: Int
    let companyId: Int

    @State private var crew: [CrewRow846] = []
    @State private var certs: [CrewCert846] = []
    @State private var voyage: VoyageContext846? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var syncedAt: Date? = nil

    // MARK: Derived — the relief port is the screen's subject

    /// The H1 is a PLACE and it is live. When the voyage has no destination
    /// port joined, the screen says so rather than naming a port.
    private var reliefPortTitle: String {
        guard let p = voyage?.destinationPort else { return "Relief port not set" }
        if let code = p.unlocode, !code.isEmpty { return code }
        if let name = p.name, !name.isEmpty { return name }
        return "Relief port not set"
    }

    private var reliefPortLine: String {
        var parts: [String] = []
        if let p = voyage?.destinationPort {
            if let name = p.name, !name.isEmpty { parts.append(name) }
            else if let city = p.city, !city.isEmpty { parts.append(city) }
        }
        if let voy = voyage?.voyageNumber, !voy.isEmpty { parts.append("voy \(voy)") }
        else if let bk = voyage?.bookingNumber, !bk.isEmpty { parts.append(bk) }
        parts.append(crew.isEmpty ? "no roster returned" : "\(crew.count) on the roster")
        return parts.joined(separator: " · ")
    }

    private var reliefCountry: String {
        (voyage?.destinationPort?.country ?? "US").uppercased()
    }

    private var stalenessLine: String {
        guard let syncedAt else { return "not yet read this session" }
        let secs = Int(Date().timeIntervalSince(syncedAt))
        let age: String
        if secs < 60 { age = "\(max(secs, 1))s ago" }
        else if secs < 3600 { age = "\(secs / 60)m ago" }
        else { age = "\(secs / 3600)h ago" }
        return "roster + relief port read \(age) · cached read, 10m policy"
    }

    // MARK: Derived — the gate

    /// Certificates in date, computed on device from real certification rows.
    /// No rows for this seafarer -> UNVERIFIED, never PASS.
    private func certState(for userId: Int) -> GateState846 {
        let mine = certs.filter { $0.userId == userId }
        guard !mine.isEmpty else { return .unverified }
        let now = Date()
        for c in mine {
            if (c.status ?? "").lowercased() == "expired" { return .fail }
            if let raw = c.expiryDate, let d = Self.parse(raw), d < now { return .fail }
        }
        // Every row we hold is current — but a row with no expiry and no
        // status tells us nothing, so it cannot upgrade the verdict.
        let informative = mine.contains { $0.expiryDate != nil || $0.status != nil }
        return informative ? .pass : .unverified
    }

    private static func parse(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let d = df.date(from: s) { return d }
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: s)
    }

    /// One rung per real seafarer on the roster. The four conditions that
    /// depend on the missing crew-change record are UNVERIFIED for everyone.
    private var pairs: [ReliefPair846] {
        crew.map { member in
            ReliefPair846(
                id: member.id,
                offSigner: member,
                joinerName: nil,                 // no relief record exists — see STUB above
                states: [certState(for: member.id), .unverified, .unverified, .unverified, .unverified]
            )
        }
    }

    /// Per-condition tally across the whole change — the gate key's numbers.
    private func tally(_ idx: Int) -> (pass: Int, fail: Int, unverified: Int) {
        var p = 0, f = 0, u = 0
        for pair in pairs where idx < pair.states.count {
            switch pair.states[idx] {
            case .pass: p += 1
            case .fail: f += 1
            case .unverified: u += 1
            }
        }
        return (p, f, u)
    }

    private var clearedCount: Int {
        pairs.filter { $0.verdict.0 == "CLEARED" }.count
    }

    // MARK: View

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · CREW CHANGE",
                caption: "STCW · MLC 2006",
                title: reliefPortTitle,
                subtitle: reliefPortLine
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                stalenessRow
                if loading {
                    skeleton
                } else if let err = loadError, crew.isEmpty, voyage == nil {
                    VesselErrorCard(text: err)
                } else {
                    if let err = loadError {
                        VesselErrorCard(text: "Refresh failed — \(err) The change below is the last serve this session returned and is not being updated.")
                    }
                    gateKey
                    ladderSection
                    VesselSummaryStrip(
                        label: "\(clearedCount) of \(pairs.count) pairs clear to change hands at \(reliefPortTitle)",
                        value: pairs.isEmpty ? "no roster" : "relief record required",
                        valueColor: pairs.isEmpty ? palette.textTertiary : Brand.warning
                    )
                    VesselRegulatorBand(
                        title: "AUTHORITY · SINGLE-COUNTRY",
                        reference: "relief-port regime",
                        rows: regulatorRows
                    )
                    ctaPair
            VesselGapNote(text: "Crew sign-off and relief briefing are unavailable because no voyage crew-change record is connected. Add the signed-on complement and relief details before recording either action. Border-clearance actions require an online confirmation.")
            VesselGapNote(text: "The company roster, certificate dates, voyage, and relief port are available. A vessel-specific signed-on complement and crew-change record have not been provided, so relief slots and clearance gates remain unverified.")
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var stalenessRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
            Text(stalenessLine)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
    }

    private var regulatorRows: [VesselRegulatorRow] {
        [
            .init("US", "CBP C1/D crew visa · USCG",     active: reliefCountry == "US"),
            .init("CA", "CBSA crew · Transport Canada",  active: reliefCountry == "CA"),
            .init("MX", "INM tripulación · SEMAR",       active: reliefCountry == "MX")
        ]
    }

    // MARK: - Gate key (the five conditions, tallied across the change)

    /// Not a metric grid: five rows, one per CONDITION, each stating the
    /// instrument that requires it and how many pairs currently satisfy it.
    /// The whole screen is one instrument seen at two zooms — this is the
    /// gate summarised, the ladder below is the gate per pair.
    private var gateKey: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    Text("Change of hands · five conditions per pair")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text(pairs.isEmpty ? "NO PAIRS" : "NONE CLEARED")
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(pairs.isEmpty ? palette.textTertiary : Brand.warning)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(pairs.isEmpty ? palette.tintNeutral : palette.tintWarning))
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(clearedCount) / \(pairs.count)")
                        .font(.system(size: 32, weight: .bold, design: .monospaced)).tracking(-0.5)
                        .foregroundStyle(pairs.isEmpty ? palette.textTertiary : palette.textPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("pairs permitted to change")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(reliefPortTitle == "Relief port not set" ? "no relief port on the voyage" : "at \(reliefPortTitle)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                }
                Divider().overlay(palette.borderFaint)
                ForEach(Array(gateConditions846.enumerated()), id: \.element.id) { idx, cond in
                    conditionRow(idx: idx, cond: cond)
                }
            }
        }
    }

    private func conditionRow(idx: Int, cond: GateCondition846) -> some View {
        let t = tally(idx)
        return HStack(alignment: .center, spacing: Space.s3) {
            Text(cond.short)
                .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                .foregroundStyle(cond.live ? Brand.blue : palette.textTertiary)
                .frame(width: 40, height: 18)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(cond.live ? palette.tintInfo : palette.tintNeutral))
            VStack(alignment: .leading, spacing: 1) {
                Text(cond.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(cond.instrument)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 6)
            if cond.live {
                Text(t.fail > 0 ? "\(t.pass) pass · \(t.fail) fail" : "\(t.pass) of \(pairs.count) pass")
                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                    .foregroundStyle(t.fail > 0 ? Brand.danger : (t.pass > 0 ? Brand.success : palette.textTertiary))
            } else {
                Text("unverified")
                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - The ladder

    private var ladderSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(
                label: pairs.isEmpty ? "RELIEF PAIRS · NONE" : "RELIEF PAIRS · \(pairs.count) OFF-SIGNERS",
                right: "EXISTS · getVesselCrew:2417"
            )
            if pairs.isEmpty {
                VesselGroupCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No crew returned for this company")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                Text("No eligible seafarers are available in the company roster, so a relief pair cannot be formed.")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                VesselGroupCard(padded: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(pairs.enumerated()), id: \.element.id) { idx, pair in
                            if idx > 0 { Divider().overlay(palette.borderFaint) }
                            ReliefRung846(pair: pair)
                        }
                    }
                    .padding(.vertical, Space.s2)
                    .padding(.horizontal, Space.s4)
                }
            }
        }
    }

    // MARK: - CTA pair (both ONLINE_ONLY · both switched off, not dimmed)

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                CTAButton(title: "Confirm sign-off", trailingIcon: "checkmark.seal")
                    .opacity(0.5)
                    .allowsHitTesting(false)
                    .disabled(true)
                    .accessibilityLabel("Confirm sign-off, unavailable")
                    .accessibilityHint("Unavailable until a voyage crew-change record is connected")
                VesselGhostButton(title: "Brief joiners", width: 150)
                    .opacity(0.5)
                    .allowsHitTesting(false)
                    .disabled(true)
                    .accessibilityLabel("Brief joiners, unavailable")
                    .accessibilityHint("Unavailable until a voyage crew-change record is connected")
            }
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Brand.warning)
                Text("Crew-change record required")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.2)
                    .foregroundStyle(Brand.warning)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.tintWarning)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 250)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 300)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 130)
        }
    }

    // MARK: - Load (both reads REAL)

    private func load() async {
        loading = true; loadError = nil
        var failures: [String] = []

        // companyId is omitted unless the host threaded one, so the server
        // scopes from ctx.user.companyId rather than a caller-chosen tenant.
        struct CrewIn846: Encodable { let companyId: Int?; let search: String? }
        do {
            let payload: CrewPayload846 = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselCrew",
                input: CrewIn846(companyId: companyId > 0 ? companyId : nil, search: nil))
            crew = payload.crew                          // unconditional — an honest empty roster clears the ladder
            certs = payload.certifications ?? []
        } catch {
            failures.append(copy(error))
        }

        if shipmentId > 0 {
            struct DetailIn846: Encodable { let id: Int }
            do {
                let env: VoyageEnvelope846 = try await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselShipmentDetail", input: DetailIn846(id: shipmentId))
                voyage = env.context
            } catch {
                // The voyage is deliberately NOT cleared: a failed refresh keeps
                // the relief port the officer may still be reading, banner-flagged.
                failures.append(copy(error))
            }
        }

        if failures.isEmpty { syncedAt = Date() } else { loadError = failures.joined(separator: " · ") }
        loading = false
    }

    private func copy(_ error: Error) -> String {
        error.eusoUserCopy
    }
}

// MARK: - One rung of the ladder

/// A rung is a PAIR, drawn as a pair: the off-signing half on the left, the
/// joining half on the right, a relief connector between them, and the
/// five-square gate strip underneath carrying the verdict. The joining half
/// is a dashed, unnamed slot for every rung today — that is the crew-change
/// record's absence rendered honestly, not a styling choice.
private struct ReliefRung846: View {
    @Environment(\.palette) private var palette
    let pair: ReliefPair846

    private var initials: String {
        let name = (pair.offSigner.name ?? "").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return "—" }
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "—" : letters.joined().uppercased()
    }

    /// users.role is a PLATFORM role, not an STCW rank. The screen says so
    /// rather than dressing a role enum up as a certificate of competency.
    private var roleCode: String {
        switch (pair.offSigner.role ?? "").uppercased() {
        case "SHIP_CAPTAIN":    return "MASTER"
        case "PORT_MASTER":     return "PORT M"
        case "VESSEL_OPERATOR": return "OPER"
        case "VESSEL_SHIPPER":  return "SHIPPER"
        case "VESSEL_BROKER":   return "BROKER"
        case "CUSTOMS_BROKER":  return "CUSTOMS"
        default:                return "NO ROLE"
        }
    }

    private var tone: Color {
        pair.verdict.1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                // OFF-SIGNING HALF — real
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(tone.opacity(0.16)).frame(width: 30, height: 30)
                        Text(initials)
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(tone)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(pair.offSigner.name ?? "Name not set")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("\(roleCode) · \(pair.offSigner.isActive == false ? "off roster" : "signing off")")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // RELIEF CONNECTOR
                VStack(spacing: 1) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                    Text("RELIEF")
                        .font(.system(size: 6.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                }
                .frame(width: 42)

                // JOINING HALF — unnominated until the crew-change record exists
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .strokeBorder(palette.textTertiary.opacity(0.5),
                                          style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5]))
                            .frame(width: 30, height: 30)
                        Image(systemName: "person")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(palette.textTertiary)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(pair.joinerName ?? "No reliever nominated")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("relief record required")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // GATE STRIP — five squares, one per condition, plus the verdict
            HStack(spacing: 5) {
                ForEach(Array(gateConditions846.enumerated()), id: \.element.id) { idx, cond in
                    GateSquare846(
                        caption: cond.short,
                        state: idx < pair.states.count ? pair.states[idx] : .unverified
                    )
                }
                Spacer(minLength: 6)
                Text(pair.verdict.0)
                    .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(pair.verdict.1)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(pair.verdict.1.opacity(0.13)))
            }
        }
        .padding(.vertical, Space.s3)
    }
}

/// One square on a gate strip. A passed condition is filled; a failed one is
/// filled in danger with a bar; an unverified one is a DASHED outline with no
/// fill at all — visibly a hole in the evidence, never a quiet neutral that
/// could be mistaken for "fine".
private struct GateSquare846: View {
    @Environment(\.palette) private var palette
    let caption: String
    let state: GateState846

    private var tone: Color {
        switch state {
        case .pass:       return Brand.success
        case .fail:       return Brand.danger
        case .unverified: return palette.textTertiary
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(state == .unverified ? Color.clear : tone.opacity(0.16))
                    .frame(width: 22, height: 18)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(tone.opacity(state == .unverified ? 0.55 : 0.85),
                                  style: state == .unverified
                                    ? StrokeStyle(lineWidth: 1, dash: [2.5, 2])
                                    : StrokeStyle(lineWidth: 1))
                    .frame(width: 22, height: 18)
                switch state {
                case .pass:
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .heavy)).foregroundStyle(tone)
                case .fail:
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .heavy)).foregroundStyle(tone)
                case .unverified:
                    Text("?")
                        .font(.system(size: 8, weight: .heavy)).foregroundStyle(tone)
                }
            }
            Text(caption)
                .font(.system(size: 6.5, weight: .heavy)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption), \(state == .pass ? "pass" : state == .fail ? "fail" : "unverified")")
    }
}

#Preview("846 · Vessel Crew Change & Sign-Off · Night") {
    VesselCrewChangeScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("846 · Vessel Crew Change & Sign-Off · Light") {
    VesselCrewChangeScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
