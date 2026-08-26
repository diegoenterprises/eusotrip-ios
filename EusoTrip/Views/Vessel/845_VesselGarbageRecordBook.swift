//
//  845_VesselGarbageRecordBook.swift
//  EusoTrip — Vessel Operator · Garbage Record Book (MARPOL Annex V) (845).
//
//  Composition port of "845 Vessel Garbage Record Book.svg" (Light + Dark).
//  ARCHETYPE: CATEGORY × DISPOSITION PERMISSION MATRIX.
//
//  Why this shape, and why it is emphatically NOT 844's. The two screens are
//  the band's clone risk — both are MARPOL record books held for a signature —
//  so the separation is structural, not cosmetic:
//
//    · MARPOL Annex I (844) indexes its book ONE-DIMENSIONALLY: nine operation
//      letter-codes, entries in time order, and the only open question is
//      whether the master has signed. 844 is therefore a coded ledger plus a
//      signature custody chain.
//    · MARPOL Annex V (this screen) indexes its book TWO-DIMENSIONALLY: eleven
//      waste CATEGORIES (A…K, as amended 2016) against three DISPOSITIONS
//      (discharged at sea · landed to a port reception facility · incinerated
//      on board). The interesting object is the CELL, and a cell is not a
//      number — it is a PERMISSION. Reg. 3, 4 and 6 make most at-sea cells
//      unlawful outright, make three of them conditional on distance to the
//      nearest land, special-area status and the ship being en route, and leave
//      the rest permitted. A chronological ledger cannot express that; a grid
//      is the only honest instrument for it.
//
//    So: 844 asks "has this been signed?". 845 asks "may this go there at
//    all?". Different question, different organ, no shared spine.
//
//  Separation from the rest of the band, checked before drawing:
//    · 843 (Ballast Water) is a top-down HULL PLAN with vertical fill columns
//      and a three-condition gate — spatial geometry, one axis of tanks.
//    · 842 (Bunkering) carries a graduated sulphur-spec AXIS — a continuous
//      1-D value scale. This screen deliberately does NOT draw a distance axis
//      for exactly that reason; the distance thresholds are stated as
//      CONDITIONS attached to their cells instead.
//    · 838 (AMS) is a T-minus cutoff plus a filing pipeline; 840 (ISPS) a level
//      escalator; 836 (Laytime) a money clock. Nothing here repeats them.
//
//  TWO LAYERS IN ONE CELL — the honesty device this screen turns on:
//    LAYER 1 · PERMISSION is REGULATION. MARPOL Annex V is a published treaty
//      instrument; whether Category A plastics may be discharged at sea is not
//      data anyone has to return. It is printed, and it is printed as a rule.
//    LAYER 2 · QUANTITY is DATA, and there is none. Every quantity is an
//      em-dash and will stay one until a garbage-record model exists.
//    A cell therefore reads "this is permitted / conditional / forbidden, and
//    nothing has been recorded in it" — never "zero was discharged", which is
//    an assertion the ship would be held to.
//
//  SOURCE-SVG DEFECTS DELIBERATELY NOT REPRODUCED (filed in the fire report —
//  they were observed on 844's render and the same geometry is used here):
//    1. Hero figure colliding with the stat labels beside it. Here the "— nm"
//       figure owns its own full-width row; the two facts sit on a separate row
//       as two equal columns. Structurally impossible, not narrowly avoided.
//    2. State pills overlapping the m³ figures. Here every disposition cell is
//       a fixed-width tinted cell with exactly one piece of content, so a mark
//       and a number never share a baseline.
//    3. ~120px of dead band above the CTA pair. Here every section is spaced by
//       one token in a single VStack; there is no fixed spacer to go stale.
//    4. NEW, filed against BOTH SVGs in this pair: neither 844 nor 845 carries
//       the ESang advisory block with a figure attached that §4 requires of
//       every screen in this catalog. That is an SVG-side axis miss and is not
//       something the Swift port can invent — an advisory with no number on it
//       is exactly what sank 005.
//
//  WIRING (honest — three REAL reads, every domain read/write a named gap):
//    REAL · vesselShipments.getVesselShipmentDetail
//        (EXISTS vesselShipments.ts:561 · vesselProcedure · input { id: Int }).
//        Returns a FLAT spread of the vessel_shipments row plus lifecycleStage,
//        bols, customs, events, demurrage, containers, originPort,
//        destinationPort (:587) — there is NO `shipment` wrapper key. Drives the
//        voyage context line and supplies the vesselId the compliance read uses.
//        FIELD THAT DOES NOT EXIST: vessel_shipments has no `vesselName` column
//        (the row carries `vesselId`, a FK to `vessels`). This screen does not
//        decode one; the ship's name comes from the particulars overlay.
//    REAL · vesselShipments.getVesselCompliance
//        (EXISTS vesselShipments.ts:2457 · vesselProcedure · input
//        { vesselId?: Int }) → { inspections, ispsRecords, insurance, status,
//        totalInspections, failedCount }. A Garbage Record Book is examined at
//        the same port-state inspection that raises deficiencies, so the live
//        posture is shown beside it — labelled as inspection posture, never as
//        a verdict on the book.
//    REAL · vesselShipments.getVesselParticulars
//        (EXISTS vesselShipments.ts:2980 · vesselProcedure · input
//        { imoNumber: String }) — MarineTraffic passthrough behind
//        lsCacheThrough("WARM", 86400). Annex V reg. 10 requires the placard and
//        the book to carry the ship's identity, so the identity line is fed
//        from here as an ENRICHMENT overlay; a null payload leaves the screen
//        whole. IMO resolved via vesselShipments.getVesselFleet
//        (EXISTS vesselShipments.ts:2525) when the caller threaded none.
//
//    STUB · named-gap — vessel.getGarbageRecordBook({ voyageId: string }).
//        There is NO garbage-record model anywhere on disk. Grepped first-hand
//        this fire across frontend/server/**/*.ts: /garbageRecord/i returns
//        ZERO, and /garbage/i returns 13 hits of which every single one is
//        unrelated — eleven are the word "garbage" meaning malformed input in
//        validation comments, one is the truck commodity "Garbage/Refuse"
//        (hotZones.ts:920 / instantVerification.ts:116), and one is a single
//        descriptive string in an autopilot knowledge map
//        (services/autopilot/core/industryKnowledge.ts:189 · annexV: "Garbage
//        from ships"). No table, no procedure, no router mount, nothing this
//        screen could read. Proposed TS shape:
//          {
//            bookId: string,
//            nmFromNearestLand: number | null,
//            positionFixAt: string | null,          // ISO — gates the at-sea column
//            speedOverGroundKn: number | null,      // "en route" test
//            specialArea: string | null,            // e.g. "Caribbean Sea", null = none
//            placardPosted: boolean | null,         // reg. 10.1
//            managementPlanOnBoard: boolean | null, // reg. 10.2
//            totals: Array<{
//              category: 'A'|'B'|'C'|'D'|'E'|'F'|'G'|'H'|'I'|'J'|'K',
//              atSeaM3: number | null,
//              toReceptionM3: number | null,
//              incineratedM3: number | null
//            }>,
//            lastLanding: {
//              portUnlocode: string,
//              atUtc: string,
//              qtyM3: number,
//              receiptNo: string,
//              receiptUrl: string | null
//            } | null,
//            entries: Array<{
//              entryId: string,
//              category: string,
//              disposition: 'AT_SEA' | 'TO_RECEPTION' | 'INCINERATED',
//              qtyM3: number,
//              occurredAt: string,
//              positionLat: number | null,
//              positionLng: number | null,
//              enteredByCrewId: number | null,
//              masterSignedAt: string | null
//            }>
//          }
//        Until it exists every cell quantity is an em-dash, the distance figure
//        is an em-dash, the special-area and placard facts read unreported, and
//        the at-sea column's conditional cells stay CONDITIONAL rather than
//        resolving to permitted — a conditional cell that resolves itself on no
//        position fix is the exact failure this screen must not have.
//    STUB · named-gap REGULATORY WRITE — vessel.recordGarbageDisposal({
//        voyageId, category, disposition, qtyM3, occurredAt, positionLat,
//        positionLng, confirm: true }) [gated + confirm:true + audit + test].
//        Writes a garbage_entry row + blockchainAuditTrail
//        vessel.garbage_recorded, broadcast WS_CHANNELS.VESSEL_OPS /
//        WS_EVENTS.GARBAGE_RECORDED. The server MUST re-check the permission
//        layer — a client-side grid is a reading aid, never the gate.
//    STUB · named-gap REGULATORY WRITE — vessel.attachReceptionReceipt({
//        entryId, receiptNo, receiptUrl, confirm: true }) [gated + audit +
//        test]. Writes the reception-receipt columns + blockchainAuditTrail
//        vessel.garbage_receipt_attached. RBAC vesselProcedure (environmental
//        officer records; the master signs each completed page under reg. 10.3).
//    Neither write is reachable from this device. Both CTAs are `.disabled(true)`
//        under a permanently visible notice naming the two missing procedures.
//        Nothing on this screen mutates local @State to imitate persistence.
//
//  OFFLINE POLICY (doctrine §W — derived, not stamped):
//    READ  · READ_CACHED(10m) for the category totals and the landing history.
//            A garbage log an officer is reading is still worth reading on a
//            dropped link, and a stale total misleads nobody as long as it says
//            so. Staleness is made VISIBLY DISTINCT: a served-at line under the
//            matrix carries the local time of the last successful serve, and a
//            failed refresh banners above retained content instead of blanking
//            it. The PERMISSION layer is treaty text and is never stale.
//            HONEST SCOPE: what the code does today is retain the last decoded
//            serve IN MEMORY for the session. There is no persistent cache —
//            Services/EusoTripAPI.swift sets
//            .reloadIgnoringLocalAndRemoteCacheData and urlCache = nil — so
//            nothing survives a cold launch and the 10m TTL is a policy
//            declaration, not an enforced one. OPEN item (owning lane:
//            the-oath): a real on-disk read cache with TTL enforcement.
//    WRITE · ONLINE_ONLY, for a reason specific to Annex V. A disposal record
//            fixes a POSITION and a TIME, and the lawfulness of an at-sea
//            disposal is decided by that position — distance to nearest land,
//            whether the ship was inside a special area, whether she was en
//            route. Queued and replayed later, the entry would be written from
//            a device clock and a position the ship has already left, which is
//            how a lawful discharge becomes a falsified record. In the United
//            States that record is the document 33 CFR 151.55 requires to be
//            produced on demand and the one prosecuted when it is wrong. The
//            master's signature on a completed page is irreversible on the same
//            footing as the ORB's. No queue lane is offered for either write.
//
//  CHAIN CLOSURE:
//    Intended emit WS_EVENTS.GARBAGE_RECORDED on WS_CHANNELS.VESSEL_OPS; the
//    intended counter-parties are the port-state-control surface (678) and the
//    vessel compliance surface (652).
//    OPEN counter-party item (owning lane: VESSEL · the-oath): the receiving
//    half does not exist. RealtimeService.swift carries no vessel:* case and
//    Views/Vessel has zero realtime subscribers, so a recorded disposal would
//    land on no listener. Named rather than papered over.
//
//  COUNTRY (single-country content inside one file, never a file fork):
//    US USCG 33 CFR 151.55/151.57 + USDA-APHIS regulated garbage from foreign
//    ports ACTIVE · CA Transport Canada + CFIA · MX SEMAR + SENASICA. The
//    Annex V categories themselves are shared by all three.
//
//  PERSONA: Vessel Operator — the operator IS the carrier. No merchant-side
//    verb appears on this screen.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselGarbageRecordBookScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0
    var voyageId: String = ""
    var imoNumber: String = ""

    var body: some View {
        Shell(theme: theme) {
            VesselGarbageRecordBookBody(shipmentId: shipmentId, voyageId: voyageId, imoNumber: imoNumber)
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

/// The vessel_shipments row as getVesselShipmentDetail:587 actually spreads it.
/// No `vesselName` — that column does not exist on this table.
private struct GRBShipment845: Decodable {
    let id: Int?
    let vesselId: Int?
    let voyageNumber: String?
    let bookingNumber: String?
}

/// FLAT-SHAPE decode. A `shipment` wrapper is tolerated but the real payload
/// sits on the root; decoding only the wrapper would yield nil forever without
/// throwing, and the screen would render its awaiting state invisibly.
private struct GRBDetail845: Decodable {
    let shipment: GRBShipment845?

    private enum CodingKeys: String, CodingKey { case shipment }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let wrapped = try? c.decodeIfPresent(GRBShipment845.self, forKey: .shipment) {
            self.shipment = wrapped
        } else {
            self.shipment = try? GRBShipment845(from: decoder)
        }
    }
}

private struct GRBCompliance845: Decodable {
    let status: String?
    let totalInspections: Int?
    let failedCount: Int?
}

private struct GRBVesselRow845: Decodable, Identifiable {
    let id: Int?
    let name: String?
    let imoNumber: String?
}
private struct GRBFleet845: Decodable {
    let vessels: [GRBVesselRow845]?
}

private struct GRBParticulars845: Decodable {
    let name: String?
    let flag: String?
}

// MARK: - The permission layer (MARPOL Annex V · treaty text, not data)

/// What Annex V permits for one category in one disposition. `conditional` is a
/// distinct member on purpose: collapsing it into `permitted` is precisely how a
/// crew ends up discharging food waste eleven miles from land, and collapsing it
/// into `prohibited` would make the screen refuse a lawful operation. The
/// condition is named on the cell and spelled out in the key beneath the matrix.
private enum GRBPermission845 {
    case prohibited
    case conditional
    case permitted
    case notApplicable
}

/// One disposition column. Three, and only three, exist in the Annex V record:
/// over the side, ashore to a reception facility, or into the incinerator.
private enum GRBDisposition845: CaseIterable {
    case atSea
    case toReception
    case incinerated

    var header: String {
        switch self {
        case .atSea:       return "AT SEA"
        case .toReception: return "ASHORE"
        case .incinerated: return "INCIN"
        }
    }
}

/// One Annex V waste category. The letter, the name and the three permissions
/// are the regulation as amended in 2016 (resolution MEPC.277(70) record-book
/// categories A–K). `atSeaM3` / `ashoreM3` / `incinM3` are the DATA layer and
/// are nil until a garbage record book exists.
private struct GRBCategory845: Identifiable {
    let id = UUID()
    let letter: String
    let name: String
    let atSea: GRBPermission845
    let toReception: GRBPermission845
    let incinerated: GRBPermission845
    /// Short marker printed inside a conditional at-sea cell; the full text
    /// lives in the condition key so the cell stays readable at 56pt wide.
    let atSeaCondition: String?

    var atSeaM3: Double? { nil }
    var ashoreM3: Double? { nil }
    var incinM3: Double? { nil }

    func permission(_ d: GRBDisposition845) -> GRBPermission845 {
        switch d {
        case .atSea:       return atSea
        case .toReception: return toReception
        case .incinerated: return incinerated
        }
    }

    func quantity(_ d: GRBDisposition845) -> Double? {
        switch d {
        case .atSea:       return atSeaM3
        case .toReception: return ashoreM3
        case .incinerated: return incinM3
        }
    }
}

// MARK: - The matrix (private to 845)

/// The screen's instrument: eleven category rows against three disposition
/// columns. Every cell paints its PERMISSION as its own surface and its
/// QUANTITY as its content, so the two layers can never be mistaken for each
/// other. Column widths are fixed, so a long category name can never push a
/// number under a mark — the collision class the source render shows.
private struct GRBMatrix845: View {
    @Environment(\.palette) private var palette
    let rows: [GRBCategory845]

    private let cellWidth: CGFloat = 56
    private let cellHeight: CGFloat = 26

    private func tone(_ p: GRBPermission845) -> Color {
        switch p {
        case .prohibited:    return Brand.danger
        case .conditional:   return Brand.warning
        case .permitted:     return Brand.success
        case .notApplicable: return palette.textTertiary
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider().overlay(palette.borderFaint)
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                if idx > 0 { Divider().overlay(palette.borderFaint.opacity(0.6)) }
                categoryRow(row)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 4) {
            Text("CATEGORY")
                .font(.system(size: 8.5, weight: .heavy)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(GRBDisposition845.allCases.enumerated()), id: \.offset) { _, d in
                Text(d.header)
                    .font(.system(size: 8.5, weight: .heavy)).tracking(0.2)
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: cellWidth)
            }
        }
        .padding(.bottom, 6)
    }

    private func categoryRow(_ row: GRBCategory845) -> some View {
        HStack(spacing: 4) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(tone(row.atSea).opacity(0.16))
                        .frame(width: 20, height: 20)
                    Text(row.letter)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(tone(row.atSea))
                }
                Text(row.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.62)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(GRBDisposition845.allCases.enumerated()), id: \.offset) { _, d in
                cell(row, d)
            }
        }
        .padding(.vertical, 6)
    }

    /// One cell. Exactly one piece of content, centred, on a permission-tinted
    /// surface — a mark for a rule that forecloses the cell, a quantity where
    /// something could have been recorded and nothing was.
    private func cell(_ row: GRBCategory845, _ d: GRBDisposition845) -> some View {
        let p = row.permission(d)
        let color = tone(p)
        return ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(p == .notApplicable ? palette.tintNeutral.opacity(0.5) : color.opacity(0.12))
            if p == .conditional {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(color.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
            }
            switch p {
            case .prohibited:
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(color)
            case .notApplicable:
                Text("n/a")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            case .conditional:
                VStack(spacing: 0) {
                    Text(row.quantity(d).map { String(format: "%.1f", $0) } ?? "—")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(row.quantity(d) == nil ? palette.textTertiary : palette.textPrimary)
                    if let c = row.atSeaCondition, d == .atSea {
                        Text(c)
                            .font(.system(size: 6.5, weight: .heavy)).tracking(0.2)
                            .foregroundStyle(color)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            case .permitted:
                Text(row.quantity(d).map { String(format: "%.1f", $0) } ?? "—")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(row.quantity(d) == nil ? palette.textTertiary : palette.textPrimary)
            }
        }
        .frame(width: cellWidth, height: cellHeight)
    }
}

// MARK: - Body

private struct VesselGarbageRecordBookBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    let voyageId: String
    let imoNumber: String

    @State private var shipment: GRBShipment845? = nil
    @State private var compliance: GRBCompliance845? = nil
    @State private var vesselRow: GRBVesselRow845? = nil
    @State private var particulars: GRBParticulars845? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var complianceError: String? = nil
    @State private var servedAt: Date? = nil

    /// The Annex V record-book categories A–K as amended 2016, with the
    /// permission each disposition carries. This table is TREATY TEXT: it is
    /// correct without any server, and it is the only thing on this screen that
    /// is allowed to be certain.
    private static let categories: [GRBCategory845] = [
        GRBCategory845(letter: "A", name: "Plastics",
                       atSea: .prohibited, toReception: .permitted, incinerated: .permitted,
                       atSeaCondition: nil),
        GRBCategory845(letter: "B", name: "Food wastes",
                       atSea: .conditional, toReception: .permitted, incinerated: .permitted,
                       atSeaCondition: "≥3 nm"),
        GRBCategory845(letter: "C", name: "Domestic wastes",
                       atSea: .prohibited, toReception: .permitted, incinerated: .permitted,
                       atSeaCondition: nil),
        GRBCategory845(letter: "D", name: "Cooking oil",
                       atSea: .prohibited, toReception: .permitted, incinerated: .permitted,
                       atSeaCondition: nil),
        GRBCategory845(letter: "E", name: "Incinerator ashes",
                       atSea: .prohibited, toReception: .permitted, incinerated: .notApplicable,
                       atSeaCondition: nil),
        GRBCategory845(letter: "F", name: "Operational wastes",
                       atSea: .prohibited, toReception: .permitted, incinerated: .permitted,
                       atSeaCondition: nil),
        GRBCategory845(letter: "G", name: "Animal carcasses",
                       atSea: .conditional, toReception: .permitted, incinerated: .permitted,
                       atSeaCondition: "en route"),
        GRBCategory845(letter: "H", name: "Fishing gear",
                       atSea: .prohibited, toReception: .permitted, incinerated: .permitted,
                       atSeaCondition: nil),
        GRBCategory845(letter: "I", name: "E-waste",
                       atSea: .prohibited, toReception: .permitted, incinerated: .prohibited,
                       atSeaCondition: nil),
        GRBCategory845(letter: "J", name: "Cargo residues · non-HME",
                       atSea: .conditional, toReception: .permitted, incinerated: .notApplicable,
                       atSeaCondition: "≥12 nm"),
        GRBCategory845(letter: "K", name: "Cargo residues · HME",
                       atSea: .prohibited, toReception: .permitted, incinerated: .notApplicable,
                       atSeaCondition: nil)
    ]

    /// The conditions the three conditional at-sea cells hang on. Each is the
    /// regulation verbatim in substance; none of them is evaluated here,
    /// because evaluating them needs a position fix nobody has returned.
    private static let conditions: [(String, String)] = [
        ("B · food wastes",
         "≥ 3 nm comminuted to ≤ 25 mm, ≥ 12 nm otherwise · ≥ 12 nm comminuted inside a special area · reg. 4 & 6"),
        ("G · animal carcasses",
         "en route, as far from the nearest land as possible · prohibited in special areas · reg. 4 & 6"),
        ("J · cargo residues (non-HME)",
         "≥ 12 nm, outside special areas, en route, cargo not classified harmful to the marine environment · reg. 4 & 6")
    ]

    // MARK: Derived context (REAL data only)

    private var shipName: String {
        if let n = particulars?.name, !n.isEmpty { return n }
        if let n = vesselRow?.name, !n.isEmpty { return n }
        return "—"
    }

    private var resolvedImo: String {
        if !imoNumber.isEmpty { return imoNumber }
        if let i = vesselRow?.imoNumber, !i.isEmpty { return i }
        return ""
    }

    /// Longhand rather than a chained `??`: `particulars?.flag` is `String??`
    /// and a coalesce chain over a double-optional is how an `Optional(…)`
    /// reaches the screen.
    private var flagText: String {
        if let f = particulars?.flag, !f.isEmpty { return f }
        return "—"
    }

    private var voyageRef: String {
        if let v = shipment?.voyageNumber, !v.isEmpty { return v }
        if let b = shipment?.bookingNumber, !b.isEmpty { return b }
        return voyageId
    }

    private var voyageLine: String {
        let voy = voyageRef
        if !voy.isEmpty { return "\(shipName) · voy \(voy) · Annex V cat A–K" }
        return "\(shipName) · Annex V categories A–K"
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
        return "totals served \(f.string(from: servedAt)) local"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · GARBAGE RECORD",
                caption: "MARPOL V · GRB",
                title: "Garbage log",
                subtitle: voyageLine
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    skeleton
                } else if let err = loadError, shipment == nil {
                    VesselErrorCard(text: err)
                } else {
                    if let err = loadError {
                        VesselErrorCard(text: "Refresh failed — \(err) The category totals below are the last serve this session returned and are not being updated.")
                    }
                    eligibilityHero
                    matrixSection
                    conditionKey
                    landingStrip
                    stalenessLine
                    identityStrip
                    complianceStrip
                    VesselRegulatorBand(
                        title: "AUTHORITY · SINGLE-COUNTRY",
                        reference: "port-state",
                        rows: [
                            .init("US", "USCG 33 CFR 151.55/151.57 · APHIS", active: true),
                            .init("CA", "Transport Canada · CFIA"),
                            .init("MX", "SEMAR · SENASICA")
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

    // MARK: - Hero · where the ship is, and what that forecloses
    //
    // COLLISION-PROOF BY CONSTRUCTION. The distance figure owns a full-width
    // row; the two facts sit on a separate row of two equal columns. Nothing
    // shares the figure's baseline.

    private var eligibilityHero: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top, spacing: 8) {
                    Text("Discharge eligibility · distance to nearest land")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.65)
                    Spacer(minLength: 8)
                    Text("PLASTICS PROHIBITED")
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Brand.danger)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Capsule().fill(Brand.danger.opacity(0.13)))
                        .fixedSize()
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("— nm")
                        .font(.system(size: 32, weight: .bold, design: .monospaced)).tracking(-0.5)
                        .foregroundStyle(palette.textTertiary)
                    Text("no position fix received")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .top, spacing: Space.s3) {
                    heroFact(label: "SPECIAL AREA", value: "— unreported", align: .leading)
                    heroFact(label: "RECEPTION FACILITY", value: "— unreported", align: .trailing)
                }
                Text("Category A plastics may never be discharged at sea — no distance, no condition, nowhere. Every other at-sea cell is gated on distance to the nearest land, special-area status and the ship being en route, none of which has been reported here, so no conditional cell resolves itself.")
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
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: align == .leading ? .leading : .trailing)
    }

    // MARK: - The matrix

    private var matrixSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "ANNEX V · CATEGORY × DISPOSITION · 11 × 3",
                                right: "QUANTITIES AWAITING BOOK")
            VesselGroupCard {
                GRBMatrix845(rows: Self.categories)
            }
            legendRow
        }
    }

    private var legendRow: some View {
        HStack(spacing: Space.s4) {
            legendChip("Permitted", Brand.success, dashed: false)
            legendChip("Conditional", Brand.warning, dashed: true)
            legendChip("Prohibited", Brand.danger, dashed: false)
            legendChip("n/a", palette.textTertiary, dashed: false)
            Spacer(minLength: 0)
        }
    }

    private func legendChip(_ label: String, _ color: Color, dashed: Bool) -> some View {
        HStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color.opacity(0.16))
                if dashed {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(color.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
            }
            .frame(width: 11, height: 11)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: - Condition key (the treaty text behind the three dashed cells)

    private var conditionKey: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "AT-SEA CONDITIONS · 3 GATED CATEGORIES",
                                right: "NONE EVALUATED")
            VesselGroupCard {
                VStack(spacing: 0) {
                    ForEach(Array(Self.conditions.enumerated()), id: \.offset) { idx, c in
                        if idx > 0 { Divider().overlay(palette.borderFaint) }
                        conditionRow(title: c.0, detail: c.1)
                    }
                }
            }
        }
    }

    private func conditionRow(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.warning)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(detail)
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Text("UNEVALUATED")
                .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(palette.tintNeutral))
                .overlay(
                    Capsule().strokeBorder(palette.textTertiary.opacity(0.45),
                                           style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
                )
                .fixedSize()
        }
        .padding(.vertical, Space.s3)
    }

    // MARK: - Chrome strips

    /// The proof half of Annex V: a landing to a reception facility is only
    /// worth anything with the facility's receipt attached to it.
    private var landingStrip: some View {
        VesselSummaryStrip(
            label: "Last landing to reception — · — m³ · receipt —",
            value: "placard unreported",
            valueColor: palette.textTertiary
        )
    }

    private var stalenessLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
            Text("READ_CACHED 10m · \(servedLine) · permission layer is treaty text and never stale")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
    }

    private var identityStrip: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "BOOK FACE · SHIP IDENTITY",
                                right: particulars == nil ? "OVERLAY UNAVAILABLE" : "LIVE")
            VesselGroupCard {
                HStack(alignment: .top, spacing: Space.s3) {
                    identityCell(label: "SHIP", value: shipName)
                    identityCell(label: "DISTINCTIVE NO.",
                                 value: resolvedImo.isEmpty ? "IMO —" : "IMO \(resolvedImo)")
                    identityCell(label: "FLAG", value: flagText)
                }
            }
        }
    }

    private func identityCell(label: String, value: String) -> some View {
        let unknown = value == "—" || value.hasSuffix("—")
        return VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 7, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(unknown ? palette.textTertiary : palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// REAL inspection posture off getVesselCompliance:2457, labelled as what it
    /// is. Never presented as a verdict on the record book.
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
            VesselGapNote(text: "Voyage, vessel identity, and port-state inspection context are available. Garbage Record Book entries and position-based disposal facts have not been provided, so quantities, distance, special-area status, and last landing remain unknown. MARPOL Annex V permissions are reference requirements, not disposal approval.")
    }

    // MARK: - CTA pair · both writes refused, both procedures named

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Brand.warning)
                Text("Disposal recording and reception-receipt attachment are unavailable until a vessel Garbage Record Book is connected. These compliance records require an online confirmation and are never queued.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            HStack(spacing: Space.s3) {
                CTAButton(title: "Record disposal", trailingIcon: "plus")
                VesselGhostButton(title: "Attach receipt", width: 150)
            }
            .disabled(true)
            .opacity(0.55)
            .accessibilityHint("Unavailable until a vessel Garbage Record Book is connected")
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 200)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 360)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 140)
        }
    }

    // MARK: - Load (three REAL reads, in dependency order)

    private func load() async {
        loading = true; loadError = nil; complianceError = nil

        struct DetailIn: Encodable { let id: Int }
        struct ComplianceIn: Encodable { let vesselId: Int? }
        struct FleetIn: Encodable { let limit: Int }
        struct ImoIn: Encodable { let imoNumber: String }

        // 1 · REAL spine — getVesselShipmentDetail:561.
        if shipmentId > 0 {
            do {
                let detail: GRBDetail845? = try await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselShipmentDetail", input: DetailIn(id: shipmentId))
                if let s = detail?.shipment { self.shipment = s }
            } catch {
                // Retained content is deliberately NOT cleared on a failed
                // refresh; it is banner-labelled as no longer fresh instead.
                loadError = error.eusoUserCopy
            }
        } else {
            shipment = nil
        }

        // 2 · REAL port-state posture — getVesselCompliance:2457.
        do {
            let c: GRBCompliance845 = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselCompliance", input: ComplianceIn(vesselId: shipment?.vesselId))
            self.compliance = c
        } catch {
            self.compliance = nil
            complianceError = error.eusoUserCopy
        }

        // 3 · Resolve the hull row so the book face can carry a real IMO.
        if let vid = shipment?.vesselId, vesselRow?.id != vid {
            let fleet: GRBFleet845? = try? await EusoTripAPI.shared.query(
                "vesselShipments.getVesselFleet", input: FleetIn(limit: 50))
            vesselRow = fleet?.vessels?.first(where: { $0.id == vid })
        }

        // 4 · REAL enrichment overlay — getVesselParticulars:2980. Null-safe:
        //     a null payload leaves the identity strip em-dashed.
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

#Preview("845 · Vessel Garbage Record Book · Night") {
    VesselGarbageRecordBookScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("845 · Vessel Garbage Record Book · Light") {
    VesselGarbageRecordBookScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
