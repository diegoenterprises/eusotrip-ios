//
//  847_VesselHoursOfRest.swift
//  EusoTrip — Vessel Operator · Hours of Rest (847).
//  MLC 2006 Standard A2.3 / STCW Code A-VIII/1.
//
//  Port of "847 Vessel Hours of Rest.svg" (Light + Dark).
//  RECORD-OF-REST SHEET archetype — one seafarer, seven days, forty-eight
//  half-hour columns per day, read against two hard ceilings and two
//  structural rules.
//
//  WHY THIS SHAPE. The hours-of-rest record is not a dashboard reading. It is
//  a DOCUMENT: the ILO/IMO record of hours of rest, one signed sheet per
//  seafarer per month, ruled into days down the page and half-hours across it,
//  which a port state control officer asks for by name and reads line by line.
//  Building it as anything else would put the officer in front of a summary
//  when what they must produce is the sheet. So the screen selects ONE
//  seafarer and draws their sheet, then states the four tests MLC Standard
//  A2.3 applies to it. The four tests are the point: two of them are ceilings
//  on TOTALS (10 h in any 24 h, 77 h in any 7 days) and two are structural
//  rules about the SHAPE of the rest (no more than two periods, one of them at
//  least six hours). A screen that showed only totals would pass a seafarer
//  who was woken every ninety minutes all night, which is exactly the fatigue
//  the rule exists to prevent.
//
//  SIBLING SEPARATION (this band shares a crew roster, which is the clone trap):
//    · 846 Crew Change is a LADDER OF PAIRS with a five-condition permission
//      gate at a named port. It has no time axis at all; its subject is
//      whether a change of hands is permitted, not how long anyone slept.
//    · 711 Crew Rest Hours is a FLEET SCAN — every crew member at once, one
//      24 h bar each, one status pill each. It answers "who looks wrong today".
//      847 answers a different question with a different organ: it takes one
//      named seafarer, spreads their week across the regulation's own ruled
//      form, and adjudicates the four tests individually. No fleet row, no
//      pill, no single-day framing.
//    · 691 Crew Call Board is a departmental peg board for mustering a watch.
//    · 654 Crew Certifications is a certificate expiry ledger.
//
//  WIRING (honest — every line below was read off the live router this fire):
//    REAL · vesselShipments.getVesselCrew — vesselShipments.ts:2417 —
//        vesselProcedure, input { companyId?: number, search?: string }.
//        Returns { crew: [{ id, name, email, phone, role, profilePicture,
//        isActive }], certifications, expiringCount }. The seafarer selector
//        at the top of this screen is that roster and nothing else; choosing a
//        seafarer is a local selection of real data, not a mutation. An empty
//        roster renders a real empty state and no sheet is drawn, because a
//        record of rest with no seafarer's name on it is not a record.
//    REAL · vesselShipments.getVesselShipmentDetail — vesselShipments.ts:561 —
//        vesselProcedure, input { id: number }. Supplies the voyage number and
//        the next port of call (joined `ports` row), which is where the sheet
//        would be inspected. vessel_shipments carries NO vesselName column
//        (drizzle/schema.ts:11813-11850), so no ship's name is printed here.
//    REAL (fixed regulatory reference, not data) · the ceilings and the
//        structural rules themselves. MLC 2006 Std A2.3(5)(a)(i): minimum 10
//        hours of rest in any 24-hour period. Std A2.3(5)(b): minimum 77 hours
//        in any 7-day period. Std A2.3(6): rest may be divided into no more
//        than two periods, one of which shall be at least 6 hours, and the
//        interval between consecutive rest periods shall not exceed 14 hours.
//        These are the governing minima and are printed as such. Printing the
//        ceiling is not the same as plotting a reading against it.
//    STUB · named-gap — there is NO rest-hours model on disk. Grepped
//        repo-wide this fire: hoursOfRest / restHours / MLC = 0 in the vessel
//        tree. (The only `restHours` matches anywhere in the repo belong to a
//        truck hours-of-service surface under 49 CFR 395 and a livestock
//        welfare surface — a different regulation, a different transport mode,
//        and a different legal subject. They are named here only to record
//        that they were checked and rejected; nothing on this screen reads
//        from them.) The read this sheet wants is
//            vessel.getRestHours({ userId: number, shipmentId?: number,
//                                  windowEndDay: string /* yyyy-MM-dd */,
//                                  days: number /* default 7 */ })
//              -> { seafarer: { userId, rank, watchStation },
//                   days: [{ day: string,
//                            halfHours: Array<"rest"|"work"|null> /* 48 */,
//                            restHours24h: number,
//                            periods: number,
//                            longestPeriodHours: number,
//                            maxIntervalHours: number,
//                            source: "watchbill"|"manual"|"incomplete" }],
//                   rolling7dRestHours: number,
//                   nonConformities: [{ day, rule, measured, minimum }] }
//        Until that exists every one of the 336 half-hour cells on this sheet
//        renders UNRECORDED, every daily total is an em-dash, and all four
//        conformity tests read UNVERIFIED. Not one cell is inferred from a
//        watch bill this device does not hold.
//    STUB · named-gap REGULATORY WRITES — the two CTAs. Proposed:
//            vessel.ackRestNonConformity({ userId, shipmentId, day,
//                                          rule, confirm: true })
//            vessel.exportRestRecord({ userId, fromDay, toDay, confirm: true })
//        [gated + confirm:true + audit + test]. Each writes the rest_ack row +
//        a blockchainAuditTrail vessel.rest_ack entry and broadcasts
//        WS_CHANNELS.VESSEL_OPS / WS_EVENTS.REST_FLAGGED. RBAC vesselProcedure
//        (master). Both controls are `.disabled(true)` today with the missing
//        procedure named in-line. Neither is dimmed-but-tappable and neither
//        mutates local state to imitate a signature.
//
//  OFFLINE POLICY (doctrine §W — derived, not stamped):
//    READ  · READ_CACHED(10m). The roster and the voyage are reference context
//            an officer may legitimately read at sea or alongside with no
//            signal, and a stale sheet is still a readable sheet. Made VISIBLY
//            distinct: a staleness line under the header states the age of the
//            serve in relative time, and a failed refresh banners above
//            retained content instead of blanking it.
//            HONEST SCOPE: the retention is IN MEMORY for the life of the
//            session only. There is no persistent on-disk read cache behind it
//            (Services/EusoTripAPI.swift sets urlCache = nil), so nothing
//            survives a cold launch and the 10m TTL is a declared policy, not
//            an enforced one. OPEN item, owning lane: the-oath.
//    WRITE · ONLINE_ONLY. A record of hours of rest is the EVIDENCE in a port
//            state control inspection and, once acknowledged by the master, an
//            irreversible regulatory signature. An acknowledgement queued at
//            sea and replayed later would carry a timestamp that does not
//            correspond to when the master saw the non-conformity — which is
//            precisely the fact an inspection turns on. An export is the same
//            document leaving the ship. Neither is ever queued.
//
//  CHAIN CLOSURE: WS_EVENTS.REST_FLAGGED on WS_CHANNELS.VESSEL_OPS, intended
//    for 678 (Port State Control) where an arrival inspection would read it
//    and 846 (Crew Change) where an incoming watch's rest state matters.
//    OPEN counter-party item, owning lane VESSEL · the-oath: the receiving
//    half does not exist — RealtimeService.swift carries no vessel:* case and
//    Views/Vessel has zero realtime subscribers, so a flagged non-conformity
//    would land on no listener.
//
//  COUNTRY (single-country content, never a file fork): the port-state regime
//    that governs is the next port of call's. US USCG 46 CFR 15.1111 · CA
//    Transport Canada Marine Personnel Regulations · MX SEMAR. STCW Code
//    A-VIII/1 and MLC 2006 Std A2.3 minima are shared across all three.
//
//  Persona: Lena Bjornstad · Aurora Ocean Division. The vessel operator IS the
//  carrier — no merchant-side verb appears on this surface.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselHoursOfRestScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0
    var companyId: Int = 0

    var body: some View {
        Shell(theme: theme) {
            VesselHoursOfRestBody(shipmentId: shipmentId, companyId: companyId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Wire shapes (mirror the live payloads exactly)

/// `getVesselCrew().crew[]` — the select list at vesselShipments.ts:2424-2432.
private struct Seafarer847: Decodable, Identifiable {
    let id: Int
    let name: String?
    let role: String?
    let isActive: Bool?
}

private struct CrewPayload847: Decodable {
    let crew: [Seafarer847]
    /// Absent on the no-database early return at :2422, hence optional.
    let expiringCount: Int?
}

/// A joined `ports` row (drizzle/schema.ts:11756) — where the sheet is read.
private struct InspectionPort847: Decodable {
    let name: String?
    let unlocode: String?
    let country: String?
}

/// The FLAT root of `getVesselShipmentDetail` (vesselShipments.ts:588 spreads
/// the shipment; there is no `shipment` wrapper key). Decoded off the ROOT,
/// with a wrapper merely tolerated in case a future revision adds one.
private struct VoyageContext847: Decodable {
    let id: Int?
    let bookingNumber: String?
    let voyageNumber: String?
    let eta: String?
    let destinationPort: InspectionPort847?
}

private struct VoyageEnvelope847: Decodable {
    let context: VoyageContext847?
    private enum CodingKeys: String, CodingKey { case shipment }

    init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: CodingKeys.self),
           let wrapped = try? c.decodeIfPresent(VoyageContext847.self, forKey: .shipment) {
            self.context = wrapped
        } else {
            self.context = try? VoyageContext847(from: decoder)
        }
    }
}

// MARK: - Sheet model

/// The state of one half-hour column. `unrecorded` is a first-class member and
/// is what every column carries today: an unlogged half hour is NOT rest, and
/// rendering it as rest would manufacture the exact evidence an inspection is
/// looking for.
private enum HalfHour847: Equatable {
    case rest
    case work
    case unrecorded
}

/// One ruled day line on the sheet: 48 half-hour columns plus the day's rest
/// total. `total` is nil until the rest-hours record exists.
private struct SheetDay847: Identifiable {
    let id = UUID()
    let label: String        // "Mon 11" — the ruled day
    let isToday: Bool
    let cells: [HalfHour847] // exactly 48
    let total: Double?       // rest hours in that 24 h, nil = unrecorded
}

/// One of the four tests MLC Standard A2.3 applies to the sheet. Two are
/// ceilings on totals, two are structural rules about the shape of the rest.
private struct RestTest847: Identifiable {
    let id = UUID()
    let rule: String
    let instrument: String
    let requirement: String
}

private let restTests847: [RestTest847] = [
    .init(rule: "Minimum rest in any 24 hours",
          instrument: "MLC 2006 Std A2.3(5)(a)(i) · STCW A-VIII/1",
          requirement: "10 h"),
    .init(rule: "Minimum rest in any 7 days",
          instrument: "MLC 2006 Std A2.3(5)(b) · STCW A-VIII/1",
          requirement: "77 h"),
    .init(rule: "Rest divided into at most two periods",
          instrument: "MLC 2006 Std A2.3(6)",
          requirement: "≤ 2"),
    .init(rule: "One rest period of at least six hours",
          instrument: "MLC 2006 Std A2.3(6)",
          requirement: "≥ 6 h")
]

// MARK: - Body

private struct VesselHoursOfRestBody: View {
    @Environment(\.palette) private var palette

    let shipmentId: Int
    let companyId: Int

    @State private var crew: [Seafarer847] = []
    @State private var voyage: VoyageContext847? = nil
    @State private var selectedId: Int? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var syncedAt: Date? = nil

    private var selected: Seafarer847? {
        guard let selectedId else { return crew.first }
        return crew.first { $0.id == selectedId } ?? crew.first
    }

    // MARK: Derived context

    /// The sheet's seven ruled day lines, most recent last. Labels are real
    /// calendar days off the device clock — the RULING is real, the CONTENT is
    /// not, and the two are visually separable on the sheet.
    private var days: [SheetDay847] {
        let cal = Calendar.current
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEE d"
        let today = Date()
        return (0..<7).reversed().map { back in
            let d = cal.date(byAdding: .day, value: -back, to: today) ?? today
            return SheetDay847(
                label: df.string(from: d),
                isToday: back == 0,
                cells: Array(repeating: HalfHour847.unrecorded, count: 48),
                total: nil
            )
        }
    }

    private var inspectionPortLine: String {
        guard let p = voyage?.destinationPort else { return "next port of call not set" }
        if let code = p.unlocode, !code.isEmpty { return "PSC \(code)" }
        if let name = p.name, !name.isEmpty { return "PSC \(name)" }
        return "next port of call not set"
    }

    private var portCountry: String {
        (voyage?.destinationPort?.country ?? "US").uppercased()
    }

    private var subtitleLine: String {
        var parts: [String] = []
        if let s = selected {
            parts.append(s.name ?? "Name not set")
        } else {
            parts.append(crew.isEmpty ? "no seafarer on the roster" : "select a seafarer")
        }
        parts.append("7-day record")
        if let voy = voyage?.voyageNumber, !voy.isEmpty { parts.append("voy \(voy)") }
        else if let bk = voyage?.bookingNumber, !bk.isEmpty { parts.append(bk) }
        return parts.joined(separator: " · ")
    }

    private var stalenessLine: String {
        guard let syncedAt else { return "not yet read this session" }
        let secs = Int(Date().timeIntervalSince(syncedAt))
        let age: String
        if secs < 60 { age = "\(max(secs, 1))s ago" }
        else if secs < 3600 { age = "\(secs / 60)m ago" }
        else { age = "\(secs / 3600)h ago" }
        return "roster + voyage read \(age) · cached read, 10m policy"
    }

    // MARK: View

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The H1 is the NUMBER the whole sheet is adjudicated against —
            // the MLC daily minimum. It is the requirement, printed as the
            // requirement; the measured reading lives in the hero and is an
            // em-dash until a record exists.
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · HOURS OF REST",
                caption: "MLC 2006 · STCW",
                title: "10 h / 24 h",
                subtitle: subtitleLine
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                stalenessRow
                if loading {
                    skeleton
                } else if let err = loadError, crew.isEmpty, voyage == nil {
                    VesselErrorCard(text: err)
                } else {
                    if let err = loadError {
                        VesselErrorCard(text: "Refresh failed — \(err) The sheet below is the last serve this session returned and is not being updated.")
                    }
                    seafarerSelector
                    ceilingHero
                    if crew.isEmpty {
                        emptyRoster
                    } else {
                        sheetSection
                        conformitySection
                    }
                    VesselSummaryStrip(
                        label: crew.isEmpty
                            ? "No seafarer selected · no sheet to adjudicate"
                            : "336 half-hour columns · 0 recorded · 4 tests unverified",
                        value: "watch bill not linked",
                        valueColor: palette.textTertiary
                    )
                    VesselRegulatorBand(
                        title: "AUTHORITY · SINGLE-COUNTRY",
                        reference: "port-state · \(inspectionPortLine)",
                        rows: regulatorRows
                    )
                    ctaPair
            VesselGapNote(text: "Non-conformity acknowledgement and record export are unavailable because no vessel hours-of-rest record is connected. Add the signed-on complement and recorded work/rest periods before using these controls.")
            VesselGapNote(text: "The company roster, certificate dates, voyage, and next port are available. Recorded work/rest periods are not, so every half-hour remains unrecorded rather than being inferred from a watch bill.")
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
            .init("US", "USCG 46 CFR 15.1111 · STCW",         active: portCountry == "US"),
            .init("CA", "TC Marine Personnel Regs",           active: portCountry == "CA"),
            .init("MX", "SEMAR · STCW A-VIII/1",              active: portCountry == "MX")
        ]
    }

    // MARK: - Seafarer selector (a real local selection over real roster data)

    /// The sheet belongs to ONE named seafarer, so choosing whose sheet is on
    /// screen is the first act. This is a local selection over live roster
    /// rows — it writes nothing and claims nothing.
    private var seafarerSelector: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            VesselSectionHeader(
                label: crew.isEmpty ? "SEAFARER · NONE ON ROSTER" : "SEAFARER · \(crew.count) ON ROSTER",
                right: "EXISTS · getVesselCrew:2417"
            )
            if !crew.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.s2) {
                        ForEach(crew) { member in
                            SeafarerChip847(
                                member: member,
                                isSelected: (selected?.id == member.id),
                                action: { selectedId = member.id }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var emptyRoster: some View {
        VesselGroupCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("No crew returned for this company")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("No eligible seafarers are available in the company roster, so no hours-of-rest sheet can be issued.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Hero (the two ceilings, each with an absent reading)

    private var ceilingHero: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    Text("Rest recorded against the MLC minima")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text("NO RECORD ON FILE")
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(palette.tintNeutral))
                }
                // A rest total is the finding a port state control officer
                // acts on. It stays an em-dash and stays NEUTRAL — never
                // green, never red — so no verdict is implied either way.
                HStack(alignment: .top, spacing: Space.s4) {
                    ceilingColumn(reading: "— h", ceiling: "min 10 h", window: "in any 24 hours")
                    Rectangle().fill(palette.borderFaint).frame(width: 1, height: 46)
                    ceilingColumn(reading: "— h", ceiling: "min 77 h", window: "in any 7 days")
                }
                Divider().overlay(palette.borderFaint)
                HStack {
                    Text("Read at")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.textTertiary)
                    Text(inspectionPortLine)
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 6)
                    Text(selected.map { $0.isActive == false ? "off roster" : "on the roster" } ?? "—")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.textTertiary)
                }
                Text("The figures above are the MLC 2006 Standard A2.3 minimums. No recorded work/rest periods are available for comparison.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func ceilingColumn(reading: String, ceiling: String, window: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(reading)
                .font(.system(size: 30, weight: .bold, design: .monospaced)).tracking(-0.5)
                .foregroundStyle(palette.textTertiary)
            Text(ceiling)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(palette.textSecondary)
            Text(window)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The sheet

    private var sheetSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(
                label: "RECORD OF REST · 7 DAYS × 48 HALF-HOURS",
                right: "Record not connected"
            )
            VesselGroupCard {
                VStack(alignment: .leading, spacing: 0) {
                    hourRuler
                    ForEach(days) { day in
                        SheetLine847(day: day)
                    }
                    Divider().overlay(palette.borderFaint).padding(.top, 6)
                    sheetLegend
                }
            }
        }
    }

    private var hourRuler: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 34)
            ForEach([0, 6, 12, 18], id: \.self) { hour in
                Text(String(format: "%02d", hour))
                    .font(.system(size: 7.5, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("24")
                .font(.system(size: 7.5, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
                .frame(width: 12, alignment: .trailing)
            Color.clear.frame(width: 34)
        }
        .padding(.bottom, 4)
    }

    private var sheetLegend: some View {
        HStack(spacing: Space.s3) {
            legendSwatch(label: "REST", tone: Brand.success, dashed: false)
            legendSwatch(label: "WORK", tone: Brand.warning, dashed: false)
            legendSwatch(label: "UNRECORDED", tone: palette.textTertiary, dashed: true)
            Spacer(minLength: 0)
            Text("rest h / 24")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.top, 8)
    }

    private func legendSwatch(label: String, tone: Color, dashed: Bool) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(dashed ? Color.clear : tone.opacity(0.85))
                .frame(width: 9, height: 9)
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(tone.opacity(dashed ? 0.55 : 0),
                                      style: StrokeStyle(lineWidth: 0.9, dash: [1.8, 1.5]))
                )
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Conformity ledger (four tests, adjudicated one by one)

    private var conformitySection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(
                label: "CONFORMITY · 4 TESTS · MLC STD A2.3",
                right: "ceiling printed · reading absent"
            )
            VesselGroupCard(padded: false) {
                VStack(spacing: 0) {
                    ForEach(Array(restTests847.enumerated()), id: \.element.id) { idx, test in
                        if idx > 0 { Divider().overlay(palette.borderFaint) }
                        testRow(test)
                    }
                }
                .padding(.vertical, Space.s2)
                .padding(.horizontal, Space.s4)
            }
            Text("Two of these tests are ceilings on a total and two are rules about the SHAPE of the rest. A sheet can satisfy both totals and still fail the structure — ten hours taken in six fragments is ten hours and is also a non-conformity — which is why each test is adjudicated on its own line rather than rolled into one verdict.")
                .font(.system(size: 9.5, weight: .regular))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func testRow(_ test: RestTest847) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 1) {
                Text(test.rule)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.65)
                Text(test.instrument)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.65)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: 5) {
                    Text("—")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                    Text("/")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(palette.textTertiary)
                    Text(test.requirement)
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                }
                Text("UNVERIFIED")
                    .font(.system(size: 7.5, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.vertical, Space.s3)
    }

    // MARK: - CTA pair (both ONLINE_ONLY · both switched off, not dimmed)

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                CTAButton(title: "Acknowledge", trailingIcon: "checkmark.seal")
                    .opacity(0.5)
                    .allowsHitTesting(false)
                    .disabled(true)
                    .accessibilityLabel("Acknowledge non-conformity, unavailable")
                    .accessibilityHint("Unavailable until a vessel hours-of-rest record is connected")
                VesselGhostButton(title: "Export record", width: 150)
                    .opacity(0.5)
                    .allowsHitTesting(false)
                    .disabled(true)
                    .accessibilityLabel("Export record, unavailable")
                    .accessibilityHint("Unavailable until a vessel hours-of-rest record is connected")
            }
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Brand.warning)
                Text("Hours-of-rest record required")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.2)
                    .foregroundStyle(Brand.warning)
                    .lineLimit(1).minimumScaleFactor(0.55)
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
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 60)
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 210)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 260)
        }
    }

    // MARK: - Load (both reads REAL)

    private func load() async {
        loading = true; loadError = nil
        var failures: [String] = []

        // companyId is omitted unless the host threaded one, so the server
        // scopes from ctx.user.companyId rather than a caller-chosen tenant.
        struct CrewIn847: Encodable { let companyId: Int?; let search: String? }
        do {
            let payload: CrewPayload847 = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselCrew",
                input: CrewIn847(companyId: companyId > 0 ? companyId : nil, search: nil))
            crew = payload.crew                          // unconditional — an honest empty roster clears the sheet
            // Keep the selection only if the seafarer is still on the roster.
            if let sel = selectedId, !payload.crew.contains(where: { $0.id == sel }) {
                selectedId = payload.crew.first?.id
            } else if selectedId == nil {
                selectedId = payload.crew.first?.id
            }
        } catch {
            failures.append(copy(error))
        }

        if shipmentId > 0 {
            struct DetailIn847: Encodable { let id: Int }
            do {
                let env: VoyageEnvelope847 = try await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselShipmentDetail", input: DetailIn847(id: shipmentId))
                voyage = env.context
            } catch {
                // The voyage is deliberately NOT cleared: a failed refresh keeps
                // the inspection context on screen, banner-flagged as not fresh.
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

// MARK: - Seafarer chip (whose sheet is on screen)

private struct SeafarerChip847: View {
    @Environment(\.palette) private var palette
    let member: Seafarer847
    let isSelected: Bool
    let action: () -> Void

    private var initials: String {
        let name = (member.name ?? "").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return "—" }
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "—" : letters.joined().uppercased()
    }

    /// users.role is a PLATFORM role, not an STCW rank or a watch station.
    /// The chip prints the role it actually has rather than dressing it up as
    /// a certificate of competency the roster never returned.
    private var roleCode: String {
        switch (member.role ?? "").uppercased() {
        case "SHIP_CAPTAIN":    return "MASTER"
        case "PORT_MASTER":     return "PORT M"
        case "VESSEL_OPERATOR": return "OPER"
        case "VESSEL_SHIPPER":  return "SHIPPER"
        case "VESSEL_BROKER":   return "BROKER"
        case "CUSTOMS_BROKER":  return "CUSTOMS"
        default:                return "NO ROLE"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(isSelected ? AnyShapeStyle(LinearGradient.primary)
                                         : AnyShapeStyle(palette.tintNeutral))
                        .frame(width: 26, height: 26)
                    Text(initials)
                        .font(.system(size: 9.5, weight: .heavy))
                        .foregroundStyle(isSelected ? .white : palette.textSecondary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(member.name ?? "Name not set")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(isSelected ? palette.textPrimary : palette.textSecondary)
                        .lineLimit(1)
                    Text(roleCode)
                        .font(.system(size: 7.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
            .background(isSelected ? palette.bgCard : palette.bgCardSoft)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? Brand.blue.opacity(0.55) : palette.borderFaint,
                                  lineWidth: isSelected ? 1.4 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(member.name ?? "Unnamed seafarer"), \(roleCode)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - One ruled day line on the sheet

/// The ruled form: a day label, forty-eight half-hour columns, a day total.
/// Every column today is UNRECORDED and is drawn as an empty dashed cell —
/// the ruling is real, the content is absent, and the two must never be
/// confusable. A quarter-day rule is stroked at 06 / 12 / 18 so a reader can
/// place a period on the sheet the way they would on the paper form.
private struct SheetLine847: View {
    @Environment(\.palette) private var palette
    let day: SheetDay847

    private func tone(_ cell: HalfHour847) -> Color {
        switch cell {
        case .rest:       return Brand.success
        case .work:       return Brand.warning
        case .unrecorded: return palette.textTertiary
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(day.label)
                .font(.system(size: 8.5, weight: day.isToday ? .heavy : .semibold))
                .foregroundStyle(day.isToday ? palette.textSecondary : palette.textTertiary)
                .frame(width: 34, alignment: .leading)
                .lineLimit(1).minimumScaleFactor(0.7)

            HStack(spacing: 0.6) {
                ForEach(0..<48, id: \.self) { idx in
                    let cell: HalfHour847 = idx < day.cells.count ? day.cells[idx] : .unrecorded
                    ZStack {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(cell == .unrecorded ? Color.clear : tone(cell).opacity(0.85))
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .strokeBorder(palette.textTertiary.opacity(cell == .unrecorded ? 0.38 : 0),
                                          style: StrokeStyle(lineWidth: 0.7, dash: [1.4, 1.2]))
                        // Quarter-day rules at 06 / 12 / 18.
                        if idx == 12 || idx == 24 || idx == 36 {
                            HStack(spacing: 0) {
                                Rectangle().fill(palette.borderSoft).frame(width: 0.7)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 14)
                }
            }

            Text(day.total.map { String(format: "%.1fh", $0) } ?? "— h")
                .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.vertical, 2.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.label), rest hours unrecorded")
    }
}

#Preview("847 · Vessel Hours of Rest · Night") {
    VesselHoursOfRestScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("847 · Vessel Hours of Rest · Light") {
    VesselHoursOfRestScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
