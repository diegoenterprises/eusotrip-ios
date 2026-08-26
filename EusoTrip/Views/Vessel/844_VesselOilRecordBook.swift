//
//  844_VesselOilRecordBook.swift
//  EusoTrip — Vessel Operator · Oil Record Book Part I, machinery-space
//  operations (MARPOL Annex I) (844).
//
//  Composition port of "844 Vessel Oil Record Book.svg" (Light + Dark).
//  ARCHETYPE: CODED-LEDGER + SIGNATURE-CUSTODY CHAIN.
//
//  Why this shape and not any sibling's. The Oil Record Book is a
//  CHRONOLOGICAL instrument with a fixed one-dimensional index: MARPOL Annex I
//  Appendix III gives Part I nine operation letter-codes (A…I) and a numbered
//  item under each, and every entry the ship ever makes lands under exactly one
//  of them, in time order, and then WAITS. It is not a grid — no entry has two
//  independent axes. So this screen is built as the book's own index (a code
//  register, one row per regulated letter-code, each carrying how many entries
//  sit under it) plus the thing the code register cannot express: a three-stop
//  SIGNATURE CUSTODY CHAIN, because under Annex I reg. 17 an entry is written by
//  the officer in charge of the operation and is not a record until the MASTER
//  signs the page. Custody, not category, is what this book is anxious about.
//
//  Sibling separation, stated plainly:
//    · 845 (Garbage Record Book, Annex V) is the band's nearest neighbour and
//      is deliberately NOT this organ. Annex V has no chronological letter-code
//      spine — it has a CATEGORY × DISPOSITION MATRIX (eleven waste categories
//      against three dispositions), where the interesting cell is a PERMISSION
//      derived from distance-to-land and special-area status. 845 is a grid and
//      its unknown is a rule-gated cell; 844 is a time-ordered ledger and its
//      unknown is a signature. Neither screen's instrument would work on the
//      other's regulation.
//    · 843 (Ballast Water) draws a top-down hull plan with vertical fill
//      columns and a three-condition discharge gate — spatial, not custodial.
//    · 842 (Bunkering) is a two-party transaction with a graduated sulphur-spec
//      axis and a quantity reconciliation. 844 has no counter-party and no
//      reconciliation: the book is the ship's own statement about itself.
//    · 840 (ISPS) is a level escalator, 838 (AMS) a T-minus cutoff + filing
//      pipeline, 836 (Laytime) a one-payer money clock, 839 an hour gutter.
//      No spine is shared with any of them.
//
//  SOURCE-SVG DEFECTS DELIBERATELY NOT REPRODUCED (filed in the fire report):
//    1. In the rendered SVG the hero's 30px figure ("2 await sign") overruns
//       the two stat labels placed beside it at x=214 and x=404 — three
//       elements competing for one baseline. Here the figure owns its own full
//       -width row and the two facts sit on a SEPARATE row as two equal
//       columns, so the collision is structurally impossible rather than
//       avoided by luck.
//    2. In the SVG the SIGNED / AWAIT / DRAFT state pills are drawn on the same
//       baseline as the m³ figures and overlap them. Here state vocabulary
//       lives in the custody chain and the ledger's right-hand column is a
//       single fixed-width stack, so nothing can ever land on the numbers.
//    3. The SVG leaves ~120px of dead band between the authority card (ends
//       y=724) and the CTA pair (starts y=788). Here every section is spaced by
//       one token (Space.s5) in a single VStack — there is no fixed spacer to
//       go stale, and the content simply flows into the CTA pair.
//
//  WIRING (honest — three REAL reads, every domain read/write a named gap):
//    REAL · vesselShipments.getVesselShipmentDetail
//        (EXISTS vesselShipments.ts:561 · vesselProcedure · input { id: Int }).
//        Returns a FLAT spread of the vessel_shipments row plus lifecycleStage,
//        bols, customs, events, demurrage, containers, originPort,
//        destinationPort (:587). Drives the voyage/booking context line and
//        supplies the vesselId the compliance read is keyed on.
//        NOTE ON A FIELD THAT DOES NOT EXIST: vessel_shipments has NO
//        `vesselName` column (drizzle/schema.ts — the row carries `vesselId`, a
//        FK to `vessels`). Several landed siblings decode `vesselName` off this
//        payload and silently get nil forever. This screen does not: it decodes
//        `vesselId` and takes the ship's name from the particulars read, and
//        renders an em-dash when neither is available.
//    REAL · vesselShipments.getVesselCompliance
//        (EXISTS vesselShipments.ts:2457 · vesselProcedure · input
//        { vesselId?: Int }). Returns { inspections, ispsRecords, insurance,
//        status, totalInspections, failedCount }. The ORB is a port-state
//        control document — the officer who reads it is the same officer who
//        raises the deficiency — so the live inspection posture is shown beside
//        it. This is REAL data and is labelled as inspection posture, never as
//        an ORB verdict.
//    REAL · vesselShipments.getVesselParticulars
//        (EXISTS vesselShipments.ts:2980 · vesselProcedure · input
//        { imoNumber: String }) — a MarineTraffic passthrough behind
//        lsCacheThrough("WARM", 86400). Annex I reg. 17 requires the book to
//        carry the ship's name, distinctive number and gross tonnage on its
//        face, so the identity strip is fed from here. It is an ENRICHMENT
//        overlay: a null payload leaves the screen whole and the identity reads
//        em-dash. Resolved via vesselShipments.getVesselFleet
//        (EXISTS vesselShipments.ts:2525) when the caller did not thread an IMO.
//
//    STUB · named-gap — vessel.getOilRecordBook({ voyageId: string,
//        part: 'I' | 'II' }). There is NO oil-record / ORB / oil-residue model
//        anywhere on disk. Grepped first-hand this fire across
//        frontend/server/**/*.ts: /oilRecord|\bORB\b/i returns exactly ONE hit
//        and it is unrelated — services/passkit/walletThemes.ts:57, a wallet
//        background asset named "orb-hero". Zero tables, zero procedures, zero
//        router mounts. Proposed TS shape:
//          {
//            bookId: string,
//            part: 'I' | 'II',
//            sludgeRobM3: number | null,
//            sludgeTankCapacityM3: number | null,
//            owsAlarmOk: boolean | null,
//            owsLastTestAt: string | null,           // ISO
//            lastLandingAt: string | null,           // ISO
//            lastLandingReceiptNo: string | null,    // MARPOL waste receipt
//            codeCounts: Record<'A'|'B'|'C'|'D'|'E'|'F'|'G'|'H'|'I', number>,
//            custody: { draft: number, awaitingMaster: number, signed: number },
//            entries: Array<{
//              entryId: string,
//              code: 'A'|'B'|'C'|'D'|'E'|'F'|'G'|'H'|'I',
//              itemNo: string,                       // e.g. "11.3"
//              operation: string,
//              qtyM3: number | null,
//              occurredAt: string,                   // ISO, ship's local time
//              positionLat: number | null,
//              positionLng: number | null,
//              enteredByCrewId: number | null,
//              state: 'DRAFT' | 'AWAITING_MASTER' | 'SIGNED',
//              signedByCrewId: number | null,
//              signedAt: string | null
//            }>
//          }
//        Until it exists every code row reads "— entries", the custody chain
//        reads "—" at all three stops, the sludge ROB is an em-dash, and the
//        OWS line states the 15 ppm requirement without asserting a reading.
//    STUB · named-gap REGULATORY WRITE — vessel.addORBEntry({ voyageId, code,
//        itemNo, qtyM3, occurredAt, positionLat, positionLng, confirm: true })
//        [gated + confirm:true + audit + test]. Writes an orb_entry row in
//        state DRAFT + blockchainAuditTrail vessel.orb_entry_added, broadcast
//        WS_CHANNELS.VESSEL_OPS / WS_EVENTS.ORB_ENTRY_ADDED.
//    STUB · named-gap REGULATORY WRITE — vessel.signORBEntry({ entryId,
//        confirm: true }) [gated + confirm:true + audit + test]. Transitions
//        AWAITING_MASTER → SIGNED, writes the orb_entry signature columns +
//        blockchainAuditTrail vessel.orb_signed, broadcast
//        WS_CHANNELS.VESSEL_OPS / WS_EVENTS.ORB_SIGNED. RBAC vesselProcedure —
//        the chief engineer adds, only the MASTER signs; the role split is part
//        of the procedure's gate, not a UI convention.
//    Neither write is reachable from this device. Both CTAs are `.disabled(true)`
//        under a permanently visible notice naming the two missing procedures.
//        Nothing on this screen mutates local @State to imitate persistence.
//
//  OFFLINE POLICY (doctrine §W — derived, not stamped):
//    READ  · READ_CACHED(10m) for the entry list and the code register. An ORB
//            page an engineer is reading is still worth reading when the link
//            drops mid-ocean, and a stale index misleads nobody as long as it
//            says so. Staleness is made VISIBLY DISTINCT: a served-at line
//            under the ledger states the local time of the last successful
//            serve, and a failed refresh paints a banner above retained content
//            instead of blanking it.
//            HONEST SCOPE OF THAT TIER: what the code does today is retain the
//            last decoded serve IN MEMORY for the life of the session. There is
//            no persistent cache behind it — Services/EusoTripAPI.swift sets
//            .reloadIgnoringLocalAndRemoteCacheData and urlCache = nil — so
//            nothing survives a cold launch and the 10m TTL is a policy
//            declaration, not an enforced one. OPEN item (owning lane:
//            the-oath): a real on-disk read cache with TTL enforcement.
//    WRITE · ONLINE_ONLY. Stated reason, not a stamp: a master's signature on
//            an Oil Record Book is IRREVERSIBLE and REGULATOR-FACING. The
//            signed page is the evidentiary record a port state control officer
//            reads, and in the United States a false or omitted ORB entry is
//            prosecuted under 33 U.S.C. 1908 / 18 U.S.C. 1519 against the ship
//            AND the individual. A queued signature would be replayed later
//            against a page whose content may have changed since the master saw
//            it, and a queued entry would be written with a device clock rather
//            than the ship's logged time and position. Neither may be deferred.
//            No queue lane is offered for either — offering one and then
//            refusing at replay is worse than refusing here.
//
//  CHAIN CLOSURE:
//    Intended emit WS_EVENTS.ORB_SIGNED on WS_CHANNELS.VESSEL_OPS; the intended
//    counter-parties are the port-state-control surface (678) and the vessel
//    compliance surface (652), which is where an arrival inspection would read
//    the book's state.
//    OPEN counter-party item (owning lane: VESSEL · the-oath): the receiving
//    half does not exist. RealtimeService.swift carries no vessel:* case and
//    Views/Vessel has zero realtime subscribers, so a signature would land on
//    no listener. Named here rather than papered over with an emit nobody hears.
//
//  COUNTRY (single-country content inside one file, never a file fork):
//    US USCG 33 CFR 151 · CG-835 exam ACTIVE · CA Transport Canada TP 13585 ·
//    MX SEMAR DGMM inspection. MARPOL Annex I itself is shared by all three.
//
//  PERSONA: Vessel Operator — the operator IS the carrier. No merchant-side
//    verb appears on this screen.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselOilRecordBookScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0
    var voyageId: String = ""
    var imoNumber: String = ""

    var body: some View {
        Shell(theme: theme) {
            VesselOilRecordBookBody(shipmentId: shipmentId, voyageId: voyageId, imoNumber: imoNumber)
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

// MARK: - Decodables

/// The vessel_shipments row as it is actually spread by
/// getVesselShipmentDetail:587. `vesselName` is NOT a column on this table and
/// is deliberately absent here — the ship's name comes from the particulars
/// overlay or reads em-dash.
private struct ORBShipment844: Decodable {
    let id: Int?
    let vesselId: Int?
    let voyageNumber: String?
    let bookingNumber: String?
    let status: String?
}

/// getVesselShipmentDetail returns a FLAT spread — there is no `shipment`
/// wrapper key (vesselShipments.ts:587). Decoding a wrapper against the real
/// payload does not throw; the optional simply yields nil and the screen
/// renders its awaiting state forever, invisibly. Decode off the ROOT and keep
/// tolerating a wrapper so a future revision cannot silently break this.
private struct ORBDetail844: Decodable {
    let shipment: ORBShipment844?

    private enum CodingKeys: String, CodingKey { case shipment }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let wrapped = try? c.decodeIfPresent(ORBShipment844.self, forKey: .shipment) {
            self.shipment = wrapped
        } else {
            self.shipment = try? ORBShipment844(from: decoder)
        }
    }
}

/// getVesselCompliance:2457 — the port-state inspection posture the ORB is read
/// against. Only the summary fields are decoded; the row arrays are not
/// rendered on this screen and are not pretended to be.
private struct ORBCompliance844: Decodable {
    let status: String?
    let totalInspections: Int?
    let failedCount: Int?
}

/// getVesselFleet:2525 — used only to resolve this shipment's vessel row (and
/// therefore its IMO) when the caller did not thread one in.
private struct ORBVesselRow844: Decodable, Identifiable {
    let id: Int?
    let name: String?
    let imoNumber: String?
    let flag: String?
    let grossTonnage: Int?
}
private struct ORBFleet844: Decodable {
    let vessels: [ORBVesselRow844]?
}

/// getVesselParticulars:2980 — a MarineTraffic passthrough this repo does not
/// own. Every field optional so a partial or null payload decodes cleanly and
/// leaves the spine untouched.
private struct ORBParticulars844: Decodable {
    let name: String?
    let flag: String?
    let grossTonnage: Int?
    let yearBuilt: Int?
}

// MARK: - Custody vocabulary

/// The three states an Annex I entry can be in. `awaitingMaster` is a
/// first-class state, not a UI nicety: an entry written but unsigned has no
/// evidentiary standing, and collapsing it into either DRAFT or SIGNED would
/// misstate the ship's legal position.
private enum ORBCustody844: CaseIterable {
    case draft
    case awaitingMaster
    case signed

    var label: String {
        switch self {
        case .draft:          return "DRAFT"
        case .awaitingMaster: return "AWAITING MASTER"
        case .signed:         return "SIGNED"
        }
    }
    var detail: String {
        switch self {
        case .draft:          return "written by the officer in charge"
        case .awaitingMaster: return "complete · not yet a record"
        case .signed:         return "master signed · evidentiary"
        }
    }
    var glyph: String {
        switch self {
        case .draft:          return "pencil"
        case .awaitingMaster: return "hourglass"
        case .signed:         return "signature"
        }
    }
}

/// One regulated operation letter-code from MARPOL Annex I Appendix III,
/// Part I (machinery-space operations). These nine codes and their item numbers
/// are the REGULATION — fixed reference, not data — so they are printed. The
/// `entries` count under each is data nobody has returned, and stays nil.
private struct ORBCode844: Identifiable {
    let id = UUID()
    let code: String
    let title: String
    let items: String
    var entries: Int? = nil
}

// MARK: - The signature custody chain (private to 844)

/// Three stops, chained left to right, each carrying its own count. This is the
/// instrument the code register cannot express: an Oil Record Book's real
/// anxiety is not what happened, it is whether the master has signed for it.
/// Every count renders as an em-dash until the book exists — never as a zero,
/// because "no entries awaiting signature" and "no book linked" are different
/// statements and only one of them is true.
private struct ORBCustodyChain844: View {
    @Environment(\.palette) private var palette
    let counts: [ORBCustody844: Int]

    private func tone(_ stop: ORBCustody844) -> Color {
        switch stop {
        case .draft:          return palette.textTertiary
        case .awaitingMaster: return Brand.warning
        case .signed:         return Brand.success
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(ORBCustody844.allCases.enumerated()), id: \.offset) { idx, stop in
                if idx > 0 {
                    Rectangle()
                        .fill(palette.borderFaint)
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 17)
                }
                stopColumn(stop)
            }
        }
    }

    private func stopColumn(_ stop: ORBCustody844) -> some View {
        let known = counts[stop] != nil
        let color = tone(stop)
        return VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(known ? color.opacity(0.16) : palette.tintNeutral)
                    .frame(width: 34, height: 34)
                Circle()
                    .strokeBorder(color.opacity(known ? 0.0 : 0.45),
                                  style: StrokeStyle(lineWidth: 1, dash: known ? [] : [3, 3]))
                    .frame(width: 34, height: 34)
                Image(systemName: stop.glyph)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(known ? color : palette.textTertiary)
            }
            Text(counts[stop].map { String($0) } ?? "—")
                .font(.system(size: 15, weight: .heavy, design: .monospaced))
                .foregroundStyle(known ? palette.textPrimary : palette.textTertiary)
            Text(stop.label)
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(stop.detail)
                .font(.system(size: 8.5, weight: .regular))
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 104)
    }
}

// MARK: - Body

private struct VesselOilRecordBookBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    let voyageId: String
    let imoNumber: String

    @State private var shipment: ORBShipment844? = nil
    @State private var compliance: ORBCompliance844? = nil
    @State private var vesselRow: ORBVesselRow844? = nil
    @State private var particulars: ORBParticulars844? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var complianceError: String? = nil
    @State private var servedAt: Date? = nil

    /// The Annex I Appendix III Part I code index. Fixed regulation, printed as
    /// such; every entry count is nil because no oil record book is linked.
    private static let codes: [ORBCode844] = [
        ORBCode844(code: "A", title: "Ballasting / cleaning of oil fuel tanks", items: "items 1–8"),
        ORBCode844(code: "B", title: "Discharge of dirty ballast or cleaning water", items: "items 9–10"),
        ORBCode844(code: "C", title: "Collection, transfer and disposal of oil residues", items: "item 11 · sludge"),
        ORBCode844(code: "D", title: "Non-automatic discharge of bilge water", items: "item 12"),
        ORBCode844(code: "E", title: "Automatic discharge of bilge water", items: "item 13"),
        ORBCode844(code: "F", title: "Condition of the oil filtering equipment", items: "item 14 · 15 ppm"),
        ORBCode844(code: "G", title: "Accidental or exceptional discharge of oil", items: "item 15"),
        ORBCode844(code: "H", title: "Bunkering of fuel or bulk lubricating oil", items: "item 16"),
        ORBCode844(code: "I", title: "Additional operational procedures / remarks", items: "item 17")
    ]

    /// No custody counts exist. The dictionary is empty rather than zero-filled
    /// so the chain renders three em-dashes and asserts nothing.
    private let custodyCounts: [ORBCustody844: Int] = [:]

    private func codeTone(_ code: String) -> Color {
        switch code {
        case "C", "H": return Brand.magenta
        case "D", "E": return Brand.blue
        case "F", "G": return Brand.warning
        default:       return palette.textTertiary
        }
    }

    // MARK: Derived context lines (REAL data only)

    private var shipName: String {
        if let n = particulars?.name, !n.isEmpty { return n }
        if let n = vesselRow?.name, !n.isEmpty { return n }
        return "—"
    }

    private var imoLine: String {
        let imo = resolvedImo
        return imo.isEmpty ? "IMO —" : "IMO \(imo)"
    }

    private var resolvedImo: String {
        if !imoNumber.isEmpty { return imoNumber }
        if let i = vesselRow?.imoNumber, !i.isEmpty { return i }
        return ""
    }

    /// Gross tonnage from the overlay, else the hull row, else unknown. Written
    /// out longhand rather than chained with `??`: the operands here are
    /// double-optionals (`Int??`) and a chained coalesce would silently
    /// interpolate an `Optional(…)` into the book face.
    private var grossTonnageText: String {
        if let gt = particulars?.grossTonnage { return "\(gt) GT" }
        if let gt = vesselRow?.grossTonnage { return "\(gt) GT" }
        return "— GT"
    }

    private var flagText: String {
        if let f = particulars?.flag, !f.isEmpty { return f }
        if let f = vesselRow?.flag, !f.isEmpty { return f }
        return "—"
    }

    private var voyageRef: String {
        if let v = shipment?.voyageNumber, !v.isEmpty { return v }
        if let b = shipment?.bookingNumber, !b.isEmpty { return b }
        return voyageId
    }

    private var voyageLine: String {
        let voy = voyageRef
        if !voy.isEmpty { return "\(shipName) · voy \(voy) · Part I machinery" }
        return "\(shipName) · Part I machinery-space operations"
    }

    private var inspectionPosture: String {
        guard let c = compliance else { return "inspection posture not read" }
        let total = c.totalInspections ?? 0
        let failed = c.failedCount ?? 0
        let state = (c.status ?? "unknown").replacingOccurrences(of: "_", with: " ")
        return "\(total) inspection\(total == 1 ? "" : "s") on file · \(failed) adverse · \(state)"
    }

    private var inspectionOK: Bool { (compliance?.status ?? "") == "compliant" }

    private var servedLine: String {
        guard let servedAt else { return "no serve returned this session" }
        let f = DateFormatter()
        f.dateFormat = "dd MMM HH:mm"
        return "index served \(f.string(from: servedAt)) local"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · OIL RECORD BOOK",
                caption: "MARPOL I · ORB-I",
                title: "Oil record book",
                subtitle: voyageLine
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    skeleton
                } else if let err = loadError, shipment == nil {
                    VesselErrorCard(text: err)
                } else {
                    if let err = loadError {
                        VesselErrorCard(text: "Refresh failed — \(err) The book index below is the last serve this session returned and is not being updated.")
                    }
                    custodyHero
                    custodySection
                    codeRegisterSection
                    identityStrip
                    owsStrip
                    stalenessLine
                    complianceStrip
                    VesselRegulatorBand(
                        title: "AUTHORITY · SINGLE-COUNTRY",
                        reference: "flag / port-state",
                        rows: [
                            .init("US", "USCG 33 CFR 151 · CG-835 exam", active: true),
                            .init("CA", "Transport Canada TP 13585"),
                            .init("MX", "SEMAR DGMM inspection")
                        ]
                    )
                    gapNote
                    ctaPair
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - Hero · what the book is waiting for
    //
    // COLLISION-PROOF BY CONSTRUCTION (SVG defect 1). The figure gets its own
    // row with a trailing Spacer and nothing beside it; the two facts get a
    // separate row of two equal columns. No third element ever shares the
    // figure's baseline.

    private var custodyHero: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top, spacing: 8) {
                    Text("Part I entries · held for the master")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text("ORB-I")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Brand.blue)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Brand.blue.opacity(0.14)))
                }
                // Figure row — owns the full width. Nothing sits beside it.
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("—")
                        .font(.system(size: 32, weight: .bold, design: .monospaced)).tracking(-0.5)
                        .foregroundStyle(palette.textTertiary)
                    Text("entries await signature")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                // Facts row — two equal columns, each with its own bounds.
                HStack(alignment: .top, spacing: Space.s3) {
                    heroFact(label: "MACHINERY SPACE", value: "codes A – I", align: .leading)
                    heroFact(label: "SLUDGE ROB", value: "— m³", align: .trailing)
                }
                Text("No oil record book is linked to this voyage. Entry counts, sludge remaining on board and every signature state arrive with the book itself — nothing here is estimated on the device.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func heroFact(label: String, value: String, align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 3) {
            Text(label)
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: align == .leading ? .leading : .trailing)
    }

    // MARK: - Signature custody chain

    private var custodySection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "SIGNATURE CUSTODY · ENTRY → MASTER",
                                right: "0 OF 3 KNOWN")
            VesselGroupCard {
                VStack(spacing: Space.s4) {
                    ORBCustodyChain844(counts: custodyCounts)
                    Divider().overlay(palette.borderFaint)
                    HStack(alignment: .center, spacing: Space.s4) {
                        partyBlock(role: "ENTERS", duty: "chief engineer")
                        Rectangle().fill(palette.borderFaint).frame(width: 1, height: 30)
                        partyBlock(role: "SIGNS", duty: "master")
                        Spacer(minLength: 0)
                    }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "lock")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Brand.warning)
                Text("An unsigned entry is not yet a record — MARPOL Annex I reg. 17")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
        }
    }

    /// A party is an initials disc, never a glyph. Nobody has been identified,
    /// so the disc carries an em-dash rather than a borrowed name.
    private func partyBlock(role: String, duty: String) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle()
                    .fill(palette.tintNeutral)
                    .frame(width: 32, height: 32)
                Circle()
                    .strokeBorder(palette.textTertiary.opacity(0.45),
                                  style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: 32, height: 32)
                Text("—")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(role)
                    .font(.system(size: 7.5, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
                Text(duty)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("not identified")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    // MARK: - The coded ledger index

    private var codeRegisterSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "PART I · OPERATION CODE REGISTER · 9 CODES",
                                right: "AWAITING BOOK")
            VesselGroupCard(padded: false) {
                VStack(spacing: 0) {
                    registerHeaderRow
                    ForEach(Array(Self.codes.enumerated()), id: \.element.id) { idx, code in
                        if idx > 0 { Divider().overlay(palette.borderFaint) }
                        codeRow(code)
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s2)
            }
        }
    }

    private var registerHeaderRow: some View {
        HStack(spacing: Space.s3) {
            Text("CODE")
                .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 32, alignment: .leading)
            Text("REGULATED OPERATION")
                .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 8)
            Text("ENTRIES")
                .font(.system(size: 8.5, weight: .heavy)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 62, alignment: .trailing)
        }
        .padding(.vertical, Space.s2)
    }

    /// The right-hand column is ONE fixed-width stack (SVG defect 2). A quantity
    /// and a state can never share a baseline here, so nothing can overlap the
    /// numbers no matter how long the operation title runs.
    private func codeRow(_ code: ORBCode844) -> some View {
        let tone = codeTone(code.code)
        let known = code.entries != nil
        return HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(tone.opacity(0.16))
                    .frame(width: 30, height: 30)
                Text(code.code)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(tone)
            }
            .frame(width: 32, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(code.title)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.65)
                Text(code.items)
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(code.entries.map { String($0) } ?? "—")
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .foregroundStyle(known ? palette.textPrimary : palette.textTertiary)
                Text(known ? "logged" : "no book")
                    .font(.system(size: 7.5, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
            }
            .frame(width: 62, alignment: .trailing)
        }
        .padding(.vertical, Space.s3)
    }

    // MARK: - Identity strip (Annex I reg. 17 book face · REAL particulars)

    private var identityStrip: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "BOOK FACE · SHIP IDENTITY",
                                right: particulars == nil ? "OVERLAY UNAVAILABLE" : "LIVE")
            VesselGroupCard {
                HStack(alignment: .top, spacing: Space.s3) {
                    identityCell(label: "SHIP", value: shipName)
                    identityCell(label: "DISTINCTIVE NO.", value: imoLine)
                    identityCell(label: "GROSS TONNAGE", value: grossTonnageText)
                    identityCell(label: "FLAG", value: flagText)
                }
            }
        }
    }

    private func identityCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 7, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(value == "—" || value.hasPrefix("— ") || value.hasSuffix("—")
                                 ? palette.textTertiary : palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Chrome strips

    /// The 15 ppm figure is the REQUIREMENT (Annex I reg. 14 / 33 CFR 151.10),
    /// printed as the standard. No alarm state and no tank percentage is
    /// asserted, because none was reported.
    private var owsStrip: some View {
        VesselSummaryStrip(
            label: "Oil filtering equipment · 15 ppm required · sludge tank —%",
            value: "CG-835 not verified",
            valueColor: palette.textTertiary
        )
    }

    private var stalenessLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
            Text("READ_CACHED 10m · \(servedLine)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
    }

    /// REAL inspection posture off getVesselCompliance:2457 — labelled as what
    /// it is. It is never presented as a verdict on the record book.
    private var complianceStrip: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "PORT-STATE POSTURE · THE OFFICER WHO READS THIS BOOK",
                                right: complianceError == nil ? "LIVE" : "UNREAD")
            VesselSummaryStrip(
                label: complianceError.map { "Inspection posture unavailable — \($0)" } ?? inspectionPosture,
                value: complianceError == nil ? (inspectionOK ? "no adverse finding" : "review") : "—",
                valueColor: complianceError == nil ? (inspectionOK ? Brand.success : Brand.warning) : palette.textTertiary
            )
        }
    }

    private var gapNote: some View {
            VesselGapNote(text: "Voyage, vessel identity, and port-state inspection context are available. Oil Record Book entries have not been provided, so counts and custody figures remain unknown. MARPOL Annex I codes and the 15 ppm limit are reference requirements, not recorded vessel activity.")
    }

    // MARK: - CTA pair · both writes refused, both procedures named
    //
    // Neither control is tappable. `.disabled(true)` sits on the container so a
    // tap cannot reach either button; the notice above it is permanent, not a
    // toast fired after a tap that never lands.

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Brand.warning)
                Text("Entry creation and master signature are unavailable until a vessel Oil Record Book is connected. Regulator-facing signatures require an active connection and are never queued.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            HStack(spacing: Space.s3) {
                CTAButton(title: "Add ORB entry", trailingIcon: "plus")
                VesselGhostButton(title: "Master sign", width: 150)
            }
            .disabled(true)
            .opacity(0.55)
            .accessibilityHint("Unavailable until a vessel Oil Record Book is connected")
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 190)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 150)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 320)
        }
    }

    // MARK: - Load
    //
    // Three REAL reads, in dependency order. The shipment is the spine; the
    // compliance and particulars reads are best-effort enrichment and their
    // failure never blanks the book.

    private func load() async {
        loading = true; loadError = nil; complianceError = nil

        struct DetailIn: Encodable { let id: Int }
        struct ComplianceIn: Encodable { let vesselId: Int? }
        struct FleetIn: Encodable { let limit: Int }
        struct ImoIn: Encodable { let imoNumber: String }

        // 1 · REAL spine — getVesselShipmentDetail:561.
        if shipmentId > 0 {
            do {
                let detail: ORBDetail844? = try await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselShipmentDetail", input: DetailIn(id: shipmentId))
                if let s = detail?.shipment { self.shipment = s }
            } catch {
                // The last decoded serve is deliberately NOT cleared — a failed
                // refresh banners above retained content instead of blanking a
                // page the engineer may still be reading.
                loadError = error.eusoUserCopy
            }
        } else {
            shipment = nil
        }

        // 2 · REAL port-state posture — getVesselCompliance:2457. The input
        //     vesselId is optional on the server; passing the shipment's vessel
        //     narrows it to this hull, nil returns the fleet-wide posture.
        do {
            let c: ORBCompliance844 = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselCompliance", input: ComplianceIn(vesselId: shipment?.vesselId))
            self.compliance = c
        } catch {
            self.compliance = nil
            complianceError = error.eusoUserCopy
        }

        // 3 · Resolve the hull row so the book face can carry a real IMO.
        //     getVesselFleet:2525 is the only read on this router that returns
        //     the vessels table; it is best-effort and never a spine.
        if let vid = shipment?.vesselId, vesselRow?.id != vid {
            let fleet: ORBFleet844? = try? await EusoTripAPI.shared.query(
                "vesselShipments.getVesselFleet", input: FleetIn(limit: 50))
            vesselRow = fleet?.vessels?.first(where: { $0.id == vid })
        }

        // 4 · REAL enrichment overlay — getVesselParticulars:2980. Null-safe by
        //     construction: a null payload leaves the identity strip em-dashed.
        let imo = resolvedImo
        if !imo.isEmpty {
            particulars = try? await EusoTripAPI.shared.query(
                "vesselShipments.getVesselParticulars", input: ImoIn(imoNumber: imo))
        } else {
            particulars = nil
        }

        if loadError == nil { servedAt = Date() }
        loading = false
    }
}

#Preview("844 · Vessel Oil Record Book · Night") {
    VesselOilRecordBookScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("844 · Vessel Oil Record Book · Light") {
    VesselOilRecordBookScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
