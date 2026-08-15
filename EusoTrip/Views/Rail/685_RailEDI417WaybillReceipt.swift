//
//  685_RailEDI417WaybillReceipt.swift
//  EusoTrip — Rail · 685 EDI 417 Waybill Receipt.
//
//  TITLE: Waybill receipt.
//  PURPOSE: reconcile the waybill of record — the shipping paper the car
//  actually moves on — field by field against what the shipment was tendered
//  as, and re-issue it when the paper is wrong.
//
//  Verbatim port of 05 Rail/Light-SVG/685 Rail EDI 417 Waybill Receipt.svg
//  (Light + Dark twin, identical geometry, palette-driven): ✦ eyebrow + mono
//  right register, back/title/ellipsis row, carrier sub-line, three chips,
//  the full-bleed iridescent hairline, the gradient-rimmed verdict hero with
//  its washed header band and REVIEW pill, the
//  "FIELD RECONCILIATION · N / tendered → received" section register, the
//  reconciliation panel with wash-highlighted non-matching rows and per-row
//  verdict glyphs, the three-country authority band, and the primary /
//  secondary CTA pair.
//
//  ARCHETYPE — DOCUMENT-OF-RECORD RECONCILIATION LEDGER (not DETAIL, not a
//  card stack). The SVG's geometry is a diff, not a summary: every row is a
//  tendered → received pair with its own verdict, mismatches are wash-lifted
//  out of the register, and the hero is a match COUNT rather than a status.
//  A waybill is legal paper — the question this screen answers is not "what
//  does the shipment look like" (002/005 answer that) but "does the paper
//  agree with the tender, and where exactly does it not."
//
//  ── HOW THIS DIFFERS FROM 005 AND 590 (both read first, neither recreated) ──
//    · 005 RailWaybillScreen renders ONE side of the document as a stacked
//      card grammar — hero → PARTIES → COMMODITY/HAZMAT → advisory → shipping-
//      paper strip → Download/Re-issue. It never compares anything. 685 renders
//      TWO sides against each other in a single ruled register; it has no
//      parties card, no placard diamond, no advisory row, no ShareLink, and it
//      does not duplicate 005's STCC reference map.
//    · 590 RailDocumentIngestScreen is a PARSE-CONFIDENCE surface over
//      documentManagement.classifyDocument — a % confidence numeral, a progress
//      bar, and a flat label→value extract list with no second column and no
//      verdict. 685 touches no documentManagement procedure, draws no
//      confidence bar, and its rows carry a comparison rather than a value.
//    · No symbol, sheet, verb or helper is shared with either file.
//
//  ── WIRING MANIFEST (every line re-confirmed first-hand against the real
//     router this fire; the brief's line numbers had drifted — see report) ────
//    EXISTS railShipments.ts:2874 (query)    railShipments.getWaybill
//        in  { shipmentId: number }
//        out null | { shipmentId, shipmentNumber, carType, numberOfCars,
//                     status, commodity, hazmatClass, unNumber, weight,
//                     originRailroad, destinationRailroad, routeDescription,
//                     originYard{name,city,state}, destinationYard{…},
//                     shipperName, consigneeName,
//                     waybill{waybillNumber, commodity, hazmatInfo{class,un,name},
//                             originStation, destinationStation, freightCharges,
//                             weightPounds, railcarNumber, routingInstructions,
//                             createdAt} | null,
//                     issued: boolean }
//        → BOTH sides of every reconciliation row. The TENDERED column is the
//          rail_shipments row; the RECEIVED column is the rail_waybills row.
//          Nothing on this screen is parsed, guessed or seeded.
//    EXISTS railShipments.ts:412  (query)    railShipments.getRailShipmentDetail
//        in  { id: number }   out null | { …shipment, waybills[], events[],
//                                          demurrage[], originYard, destinationYard }
//        → waybills[] IS the revision history (re-issue INSERTS a superseding
//          row) and the car register (rail_waybills.railcarNumber). Its yard
//          rows are the FULL rail_yards rows, so splcCode + country (a real
//          "US"|"CA"|"MX" enum column) come from here — which is why the SVG's
//          SPLC values and its three-country band are real and not literals.
//    EXISTS railShipments.ts:3057 (mutation) railShipments.reissueWaybill
//        in  { shipmentId?: number, loadId?: number, railId?: string }
//            ALL THREE OPTIONAL — the zod object accepts {} and the handler
//            throws BAD_REQUEST at railShipments.ts:3075. Because they are
//            `.optional()` (not `.nullable()`), a synthesized Swift encoder
//            emitting `"loadId": null` would be REJECTED by zod, so the input
//            below hand-rolls encode(to:) with encodeIfPresent. `railId` is the
//            shipmentNumber alias, resolved at railShipments.ts:3070.
//        out { waybillId, waybillNumber, reissuedAt }
//        gates STATE  — pre-departure only, REISSUABLE_RAIL_STATES at
//                       railShipments.ts:3087 = requested · car_ordered ·
//                       car_placed · loading · loaded · in_consist. Mirrored
//                       client-side so the CTA states the reason instead of
//                       spending a round-trip on a PRECONDITION_FAILED.
//              TENANT — admin OR shipment.shipperId === caller
//                       (railShipments.ts:3102, FORBIDDEN otherwise). Stated on
//                       the confirm sheet; the server's message is surfaced
//                       verbatim if it refuses.
//    EXISTS railShipments.ts:1997 (mutation) railShipments.createRailWaybill
//        in  { shipmentId: coerce number, waybillNumber?: string,
//              commodity: string (REQUIRED), weight?: number, hazmatClass?: string }
//            Optional fields → encodeIfPresent, same reason as above.
//        out the inserted waybill identity. Drives the primary CTA only in the
//        issued:false state — there is nothing to reconcile and nothing to
//        supersede until shipping paper exists.
//    STUB · named-gap   acceptWaybill / disputeWaybill — the SVG's CTA pair
//        reads "Accept waybill" / "Dispute". NEITHER verb exists on any router.
//        The secondary slot is drawn in a truthful unavailable state with its
//        reason on screen and is not wired to a lookalike. Proposed TS in the
//        NAMED GAPS block below.
//    NOT WIRED (deliberate)  railShipments.ingestEdi322 (mutation,
//        railShipments.ts:2479) is EDI 322 — road-to-road INTERCHANGE custody,
//        owned by 694 — not EDI 417. This SVG draws no ingest tray, so it is
//        not called here. Confirmed first-hand: the string "417" does not occur
//        anywhere under server/, shared/ or services/; rail_edi_transactions is
//        written only by railTenderWorkflow.ts:165 (404 outbound) and :295
//        (990 inbound). There is NO inbound 417 parse to call, so the screen
//        reconciles the waybill OF RECORD instead of pretending to parse one.
//
//  ── DB ROW · AUDIT ROW · WEBSOCKET ────────────────────────────────────────
//    reissueWaybill  DB     INSERT rail_waybills (superseding, revision-tagged
//                           <stem>-R<n>) + UPDATE rail_shipments.waybillNumber
//                           + INSERT rail_shipment_events "waybill_reissued"
//                    AUDIT  blockchain_audit_trail eventType
//                           "rail.waybillReissued" (railShipments.ts:3166)
//                    WS     WS_EVENTS.RAIL_DOC_UPDATED broadcast to
//                           WS_CHANNELS.RAIL_SHIPMENT(<id>) and
//                           WS_CHANNELS.USER(<shipperId>)
//                           (railShipments.ts:3185-3191).
//                           Wire value 'rail:doc_updated'
//                           (shared/websocket-events.ts:413).
//                           iOS SUBSCRIBER CONFIRMED FIRST-HAND:
//                           Services/RealtimeService.swift:591 lists
//                           "rail:doc_updated" in the S2 rail case block →
//                           NotificationCenter .esangRefreshSurface. This
//                           screen observes that notification, so a re-issue
//                           committed anywhere now refreshes this document
//                           live. The emit is no longer broadcasting into a
//                           vacuum.
//    createRailWaybill  DB  INSERT rail_waybills.  AUDIT none.  WS NONE.
//    getWaybill / getRailShipmentDetail — reads. No row, no audit, no emit.
//
//  RBAC: railProcedure on every call (RAIL transport-mode gate). getWaybill and
//  getRailShipmentDetail additionally apply ownsRailShipmentRow and return
//  honest-null rather than throwing on a foreign shipment; createRailWaybill
//  throws FORBIDDEN through the same helper; reissueWaybill adds the strictly
//  narrower admin-OR-shipper assertion above.
//
//  transportMode = rail. COUNTRY IS CONTENT, one screen, never a file fork: the
//  authority band binds to rail_yards.country (a real "US"|"CA"|"MX" enum) on
//  the origin and destination yards, so the active cell is derived, not chosen —
//  US · AAR 417 waybill (STB/FRA), CA · TC CN waybill (Transport Canada), MX ·
//  ARTF carta porte (ARTF/SICT). When the two yards resolve to different
//  countries the move is cross-border and the customs authorities of record are
//  named (CBP · CBSA · Aduanas/VUCEM); when hazmat is on the paper the
//  dangerous-goods regime of each jurisdiction in play is named (49 CFR §172 ·
//  TDG · NOM-002-SCT). Nothing is shown for a jurisdiction the route never
//  touches, and an unresolved yard says so rather than defaulting to US.
//
//  OFFLINE POLICY (Offline Mode Encyclopedia v2): READ_CACHED(15m) for the
//  document read — a waybill read in a yard with no signal is a real scenario,
//  so the reconciled document is persisted per shipment and re-served on a cold
//  offline launch behind a permanently visible monospaced 10pt staleness line in
//  the header right register that flips to Brand.warning past TTL. A stale legal
//  document is ALWAYS visibly labelled stale. Every commit is ONLINE_ONLY
//  because a waybill revision is a write against legal paper that cannot be
//  undone from the phone, and no rail path is offline-eligible anyway (the six
//  eligible paths are enumerated at Services/EusoTripAPI.swift:1684 and none is
//  rail) — so the CTA disables at 45% with an explicit stated reason and the
//  commit refuses up front and says so, instead of queueing or silently
//  swallowing the failure the way 566:622 does.
//
//  NAMED GAPS (proposed TypeScript — nothing is stubbed or faked in this file):
//    1. acceptWaybill / disputeWaybill — the SVG's CTA pair. Proposed:
//         acceptWaybill: railProcedure
//           .input(z.object({ shipmentId: z.number(), waybillNumber: z.string(),
//                             confirm: z.literal(true) }))
//           .mutation(...)  // → { accepted: true, acceptedAt: string }
//           // rail_shipment_events "waybill_accepted" +
//           // blockchainAuditTrail "rail.waybillAccepted" +
//           // broadcast WS_EVENTS.RAIL_DOC_UPDATED to RAIL_SHIPMENT + USER.
//         disputeWaybill: railProcedure
//           .input(z.object({ shipmentId: z.number(), waybillNumber: z.string(),
//                             fields: z.array(z.string()).min(1).max(40),
//                             reason: z.string().max(500), confirm: z.literal(true) }))
//           .mutation(...)  // → { disputed: true, disputeId: number }
//           // same event/audit/broadcast triad with "rail.waybillDisputed".
//       Both need a rail_waybills status column (issued|accepted|disputed) or a
//       rail_waybill_dispositions side table; there is no such column today,
//       which is why no lookalike was borrowed.
//    2. ingestWaybill417 — no inbound EDI 417 parse exists anywhere. Proposed:
//         ingestWaybill417: railProcedure
//           .input(z.object({ shipmentId: z.number(), rawEdi417: z.string().min(1) }))
//           .mutation(...)  // parses → INSERT rail_edi_transactions
//                           // (transactionType "417", direction "inbound")
//                           // then upserts rail_waybills from the parsed segments.
//       Until it lands, the waybill of record IS the received document and this
//       screen says so rather than drawing a parse tray it cannot fill.
//    3. getWaybill returns yards as {name,city,state} only — no splcCode, no
//       country — which is why this screen must also call getRailShipmentDetail
//       for the SPLC codes and the jurisdiction. Proposed: widen getWaybill's
//       originYard/destinationYard projection to include splcCode and country
//       and this screen drops a whole round-trip.
//
//  WHY THIS MAKES THE RAIL USER'S JOB EASIER, IN ONE SENTENCE: it puts the
//  waybill's own numbers next to the tender's numbers on one screen, so the
//  wrong weight or the missing hazmat entry is caught while the paper can still
//  be re-issued, instead of at the gate or on a freight bill weeks later.
//
//  NAV (Rail Engineer operational band): HOME · SHIPMENTS(current) · [orb] ·
//  COMPLIANCE · ME. SHIPMENTS is current because this document is always
//  reached from, and scoped to, one rail shipment.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen root

struct RailWaybillReceipt417_685: View {
    let theme: Theme.Palette
    let shipmentId: Int

    init(theme: Theme.Palette = Theme.dark, shipmentId: Int = 0) {
        self.theme = theme
        self.shipmentId = shipmentId
    }

    var body: some View {
        Shell(theme: theme) {
            RailWaybillReceiptBody685(shipmentId: shipmentId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",         systemImage: "person",           isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Decoded shapes (field-for-field against the real router payloads)

private struct HazmatInfo685: Decodable {
    let `class`: String?
    let un: String?
    let name: String?
}

private struct YardBrief685: Decodable {
    let name: String?
    let city: String?
    let state: String?
}

/// The embedded rail_waybills row returned by getWaybill — the RECEIVED column.
/// Null in its entirety until shipping paper is issued.
private struct WaybillBody685: Decodable {
    let waybillNumber: String?
    let commodity: String?
    let hazmatInfo: HazmatInfo685?
    let originStation: String?
    let destinationStation: String?
    let freightCharges: String?
    let weightPounds: Int?
    let railcarNumber: String?
    let routingInstructions: String?
    let createdAt: String?
}

/// railShipments.getWaybill — carries BOTH columns of the reconciliation.
private struct WaybillDoc685: Decodable {
    let shipmentId: Int?
    let shipmentNumber: String?
    let carType: String?
    let numberOfCars: Int?
    let status: String?
    let commodity: String?
    let hazmatClass: String?
    let unNumber: String?
    let weight: String?
    let originRailroad: String?
    let destinationRailroad: String?
    let routeDescription: String?
    let originYard: YardBrief685?
    let destinationYard: YardBrief685?
    let shipperName: String?
    let consigneeName: String?
    let waybill: WaybillBody685?
    let issued: Bool?
}

/// One rail_waybills row out of getRailShipmentDetail.waybills[] — a revision.
private struct WaybillRevision685: Decodable, Identifiable {
    let id: Int
    let waybillNumber: String?
    let railcarNumber: String?
    let commodity: String?
    let originStation: String?
    let destinationStation: String?
    let weightPounds: Int?
    let freightCharges: String?
    let createdAt: String?
}

/// The FULL rail_yards row getRailShipmentDetail returns (splcCode + country).
private struct YardFull685: Decodable {
    let name: String?
    let city: String?
    let state: String?
    let country: String?
    let splcCode: String?
}

/// The subset of getRailShipmentDetail this screen consumes.
private struct ShipmentDetail685: Decodable {
    let id: Int?
    let waybillNumber: String?
    let numberOfCars: Int?
    let originYard: YardFull685?
    let destinationYard: YardFull685?
    let waybills: [WaybillRevision685]?
}

private struct ReissueOut685: Decodable {
    let waybillId: String?
    let waybillNumber: String?
    let reissuedAt: String?
}

private struct CreateWaybillOut685: Decodable {
    let id: Int?
    let waybillNumber: String?
    let success: Bool?
}

// MARK: - Encodable inputs
//
// Every optional field goes through encodeIfPresent. zod `.optional()` accepts
// an ABSENT key and rejects an explicit null, and Swift's synthesized encoder
// emits null — sending {"shipmentId":12,"railId":null} to reissueWaybill would
// 400 on the railId branch. Hand-rolled below so it cannot.

private struct ShipmentIn685: Encodable {
    let shipmentId: Int
}

private struct DetailIn685: Encodable {
    let id: Int
}

private struct ReissueIn685: Encodable {
    let shipmentId: Int?
    let railId: String?

    private enum CodingKeys: String, CodingKey { case shipmentId, railId }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(shipmentId, forKey: .shipmentId)
        try c.encodeIfPresent(railId, forKey: .railId)
    }
}

private struct CreateWaybillIn685: Encodable {
    let shipmentId: Int
    let commodity: String
    let weight: Double?
    let hazmatClass: String?

    private enum CodingKeys: String, CodingKey { case shipmentId, commodity, weight, hazmatClass }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(shipmentId, forKey: .shipmentId)
        try c.encode(commodity, forKey: .commodity)
        try c.encodeIfPresent(weight, forKey: .weight)
        try c.encodeIfPresent(hazmatClass, forKey: .hazmatClass)
    }
}

// MARK: - Reconciliation model

private enum ReconVerdict685 {
    /// Both columns present and equal.
    case match
    /// Both columns present and different — the paper contradicts the tender.
    case differ
    /// Tendered, but absent from the waybill of record. This is the verdict
    /// that stops a car at the gate, so it reads danger, not warning.
    case missing
    /// The field has no column on rail_shipments at all (consignee, railcar and
    /// freight charges live only on the waybill), so there is nothing to compare
    /// against. Never dressed up as a pass.
    case notTendered

    var isComparable: Bool { self != .notTendered }
}

/// One ruled row of the ledger. Computed from two decoded server records — it
/// is never decoded, seeded or defaulted.
private struct ReconRow685: Identifiable {
    let id: String
    let label: String
    let tendered: String?
    let received: String?
    let verdict: ReconVerdict685
    /// True when the two columns are free text (station names, routing prose)
    /// and the comparison is a normalized text match rather than an identity
    /// match. Tagged on screen so a "match" is never over-claimed.
    let textCompare: Bool
}

/// Normalizer for the free-text columns. Station and routing values are typed
/// by humans on both sides, so an exact compare would manufacture mismatches.
private enum ReconText685 {
    static func normalize(_ s: String?) -> String {
        guard let s else { return "" }
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let kept = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
        return String(String.UnicodeScalarView(kept))
            .split(separator: " ")
            .joined(separator: " ")
    }

    /// Identity compare for codes, numbers and enum values.
    static func exact(_ a: String?, _ b: String?) -> Bool {
        let x = normalize(a), y = normalize(b)
        return !x.isEmpty && x == y
    }

    /// Text compare for prose columns — equal after normalization, or one side
    /// clearly names the other (a yard "Barstow Yard" vs a station "BARSTOW").
    static func loose(_ a: String?, _ b: String?) -> Bool {
        let x = normalize(a), y = normalize(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        if x == y { return true }
        return x.contains(y) || y.contains(x)
    }
}

private enum ISO685 {
    static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static func date(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return withFraction.date(from: s) ?? plain.date(from: s)
    }
    static func stamp(_ s: String?) -> String? {
        guard let d = date(s) else { return nil }
        let f = DateFormatter()
        f.dateFormat = "MMM d · HH:mm"
        let zone = TimeZone.current.abbreviation() ?? ""
        return zone.isEmpty ? f.string(from: d) : "\(f.string(from: d)) \(zone)"
    }
}

// MARK: - Jurisdiction (country is content — bound to rail_yards.country)

private enum Jurisdiction685: String, CaseIterable, Identifiable {
    case us = "US"
    case ca = "CA"
    case mx = "MX"

    var id: String { rawValue }

    /// The SVG's band copy, preserved verbatim.
    var authority: String {
        switch self {
        case .us: return "US · AAR"
        case .ca: return "CA · TC"
        case .mx: return "MX · ARTF"
        }
    }
    var document: String {
        switch self {
        case .us: return "417 waybill"
        case .ca: return "CN waybill"
        case .mx: return "carta porte"
        }
    }
    var regulator: String {
        switch self {
        case .us: return "STB · FRA"
        case .ca: return "Transport Canada"
        case .mx: return "ARTF · SICT"
        }
    }
    var dangerousGoods: String {
        switch self {
        case .us: return "49 CFR §172"
        case .ca: return "TDG"
        case .mx: return "NOM-002-SCT"
        }
    }
    var customs: String {
        switch self {
        case .us: return "CBP"
        case .ca: return "CBSA"
        case .mx: return "Aduanas · VUCEM"
        }
    }

    static func from(_ raw: String?) -> Jurisdiction685? {
        guard let raw, !raw.isEmpty else { return nil }
        return Jurisdiction685(rawValue: raw.uppercased())
    }
}

// MARK: - READ_CACHED(15m)
//
// A waybill only changes on a re-issue — but a re-issue invalidates the copy in
// your hand, so fifteen minutes is the longest window in which "this is the
// current revision" is still a safe claim standing in a yard with no signal.

private struct WaybillReceiptCache685: Codable {
    let savedAt: Date
    let shipmentNumber: String?
    let waybillNumber: String?
    let carrier: String?
    let status: String?
    let issued: Bool?
    let matched: Int
    let comparable: Int
    let differing: Int
    let missing: Int
    let issuedAt: String?
    let revisionCount: Int
    let jurisdictions: [String]
}

private enum WaybillReceiptCacheStore685 {
    static let ttl: TimeInterval = 15 * 60

    private static func key(_ shipmentId: Int) -> String {
        "eusotrip.rail685.waybillReceipt.\(shipmentId)"
    }

    static func save(_ envelope: WaybillReceiptCache685, shipmentId: Int) {
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        UserDefaults.standard.set(data, forKey: key(shipmentId))
    }

    static func load(shipmentId: Int) -> WaybillReceiptCache685? {
        guard let data = UserDefaults.standard.data(forKey: key(shipmentId)) else { return nil }
        return try? JSONDecoder().decode(WaybillReceiptCache685.self, from: data)
    }
}

private enum CommitMode685 {
    case issue
    case reissue
}

// MARK: - Body

private struct RailWaybillReceiptBody685: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    /// ONLINE_ONLY enforcement for the commit, and the offline serve for the read.
    @ObservedObject private var reach = OfflineReachabilityHub.shared

    let shipmentId: Int

    @State private var idText: String = ""
    @State private var scopeId: Int = 0

    // Reads
    @State private var doc: WaybillDoc685? = nil
    @State private var detail: ShipmentDetail685? = nil
    @State private var cached: WaybillReceiptCache685? = nil
    @State private var lastSyncedAt: Date? = nil
    @State private var servedFromCache = false
    @State private var loading = true
    @State private var loadError: String? = nil

    // Commit (ONLINE_ONLY, confirm-gated)
    @State private var showConfirm = false
    @State private var committing = false
    @State private var refusal: String? = nil
    @State private var toast: String? = nil

    // MARK: Derived — document identity

    private var wb: WaybillBody685? { doc?.waybill }
    private var issued: Bool { doc?.issued ?? (wb != nil) }

    /// The waybill's OWN number — never falls back to the shipment number, so
    /// the header never implies paper that has not been issued.
    private var waybillNumber: String? {
        if let live = wb?.waybillNumber, !live.isEmpty { return live }
        if let c = cached?.waybillNumber, !c.isEmpty { return c }
        return nil
    }

    private var shipmentNumber: String? {
        if let n = doc?.shipmentNumber, !n.isEmpty { return n }
        return cached?.shipmentNumber
    }

    private var carrierLabel: String {
        if let rr = doc?.originRailroad, !rr.isEmpty { return rr }
        if let rr = doc?.destinationRailroad, !rr.isEmpty { return rr }
        if let c = cached?.carrier, !c.isEmpty { return c }
        return "Railroad"
    }

    private var statusWord: String {
        let raw = doc?.status ?? cached?.status
        guard let raw, !raw.isEmpty else { return "status pending" }
        return raw.replacingOccurrences(of: "_", with: " ")
    }

    private var revisions: [WaybillRevision685] {
        (detail?.waybills ?? []).sorted { $0.id > $1.id }
    }

    private var distinctRailcars: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for r in revisions {
            let n = (r.railcarNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !n.isEmpty, !seen.contains(n) else { continue }
            seen.insert(n)
            out.append(n)
        }
        return out
    }

    // MARK: Derived — the ledger

    private var rows: [ReconRow685] {
        guard let doc else { return [] }
        var out: [ReconRow685] = []

        func compare(_ id: String,
                     _ label: String,
                     tendered: String?,
                     received: String?,
                     textCompare: Bool = false) -> ReconRow685 {
            let t = (tendered ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let r = (received ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let verdict: ReconVerdict685
            if t.isEmpty {
                // Nothing was tendered for this field, so there is no verdict to
                // reach — never dressed up as a pass just because the paper is
                // silent too.
                verdict = .notTendered
            } else if r.isEmpty {
                verdict = .missing
            } else if textCompare ? ReconText685.loose(t, r) : ReconText685.exact(t, r) {
                verdict = .match
            } else {
                verdict = .differ
            }
            return ReconRow685(id: id,
                               label: label,
                               tendered: t.isEmpty ? nil : t,
                               received: r.isEmpty ? nil : r,
                               verdict: verdict,
                               textCompare: textCompare)
        }

        func waybillOnly(_ id: String, _ label: String, received: String?) -> ReconRow685 {
            let r = (received ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return ReconRow685(id: id,
                               label: label,
                               tendered: nil,
                               received: r.isEmpty ? nil : r,
                               verdict: .notTendered,
                               textCompare: false)
        }

        // The shipment's waybill pointer vs the latest waybill row. A drift here
        // means the shipment is still pointing at a superseded revision.
        out.append(compare("wbnum", "Waybill number",
                           tendered: detail?.waybillNumber,
                           received: wb?.waybillNumber))

        out.append(compare("origin", "Origin station",
                           tendered: tenderedOriginLabel,
                           received: wb?.originStation,
                           textCompare: true))

        out.append(compare("dest", "Destination station",
                           tendered: tenderedDestinationLabel,
                           received: wb?.destinationStation,
                           textCompare: true))

        out.append(compare("cars", "Car count",
                           tendered: doc.numberOfCars.map { String($0) },
                           received: distinctRailcars.isEmpty ? nil : String(distinctRailcars.count)))

        out.append(compare("commodity", "Commodity",
                           tendered: doc.commodity,
                           received: wb?.commodity,
                           textCompare: true))

        out.append(compare("weight", "Weight (lb)",
                           tendered: tenderedWeightText,
                           received: wb?.weightPounds.map { grouped($0) }))

        out.append(compare("hazclass", "Hazmat class",
                           tendered: doc.hazmatClass,
                           received: wb?.hazmatInfo?.`class`))

        out.append(compare("un", "UN number",
                           tendered: doc.unNumber,
                           received: wb?.hazmatInfo?.un))

        out.append(compare("routing", "Routing",
                           tendered: doc.routeDescription,
                           received: wb?.routingInstructions,
                           textCompare: true))

        // Waybill-only columns — rail_shipments has no consignee, railcar or
        // freight-charge column, so there is nothing tendered to reconcile.
        out.append(waybillOnly("consignee", "Consignee", received: doc.consigneeName))
        out.append(waybillOnly("railcar", "Railcar", received: wb?.railcarNumber))
        out.append(waybillOnly("freight", "Freight charges", received: freightText))

        return out
    }

    private var tenderedOriginLabel: String? {
        yardLabel(name: detail?.originYard?.name ?? doc?.originYard?.name,
                  city: detail?.originYard?.city ?? doc?.originYard?.city,
                  state: detail?.originYard?.state ?? doc?.originYard?.state,
                  splc: detail?.originYard?.splcCode)
    }

    private var tenderedDestinationLabel: String? {
        yardLabel(name: detail?.destinationYard?.name ?? doc?.destinationYard?.name,
                  city: detail?.destinationYard?.city ?? doc?.destinationYard?.city,
                  state: detail?.destinationYard?.state ?? doc?.destinationYard?.state,
                  splc: detail?.destinationYard?.splcCode)
    }

    private func yardLabel(name: String?, city: String?, state: String?, splc: String?) -> String? {
        var parts: [String] = []
        if let name, !name.isEmpty { parts.append(name) }
        else if let city, !city.isEmpty {
            parts.append(state?.isEmpty == false ? "\(city) \(state ?? "")" : city)
        }
        if let splc, !splc.isEmpty { parts.append("SPLC \(splc)") }
        let joined = parts.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }

    private var tenderedWeightText: String? {
        guard let raw = doc?.weight, let v = Double(raw), v > 0 else { return nil }
        return grouped(Int(v.rounded()))
    }

    /// railWaybills carries no currency column, so the settlement code is derived
    /// from the ORIGIN jurisdiction — the road of record that bills the move. If
    /// the origin yard has no country the code is UNRESOLVED and none is printed:
    /// this file resolves CA and MX, so stamping USD on a CN or ARTF waybill's
    /// charges would be a fabricated financial claim.
    private var settlementCurrency: String? {
        guard let j = Jurisdiction685.from(detail?.originYard?.country) ?? jurisdictions.first
        else { return nil }
        switch j {
        case .us: return "USD"
        case .ca: return "CAD"
        case .mx: return "MXN"
        }
    }

    private var freightText: String? {
        guard let raw = wb?.freightCharges, let v = Double(raw), v > 0 else { return nil }
        guard let code = settlementCurrency else {
            // The amount is real; the currency is not on file. Say both.
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.minimumFractionDigits = 2
            f.maximumFractionDigits = 2
            let n = f.string(from: NSNumber(value: v)) ?? "\(v)"
            return "\(n) · currency unresolved"
        }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v))
    }

    private func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    // MARK: Derived — verdict counts

    private var comparableRows: [ReconRow685] { rows.filter { $0.verdict.isComparable } }
    private var matchedCount: Int { rows.filter { $0.verdict == .match }.count }
    private var differCount: Int { rows.filter { $0.verdict == .differ }.count }
    private var missingCount: Int { rows.filter { $0.verdict == .missing }.count }
    private var reviewCount: Int { differCount + missingCount }

    private var comparableCount: Int {
        // Live when the document has loaded; the cached envelope carries the
        // last known counts so a cold offline launch still shows a verdict.
        doc == nil ? (cached?.comparable ?? 0) : comparableRows.count
    }

    private var matchedForHero: Int { doc == nil ? (cached?.matched ?? 0) : matchedCount }
    private var reviewForHero: Int {
        doc == nil ? ((cached?.differing ?? 0) + (cached?.missing ?? 0)) : reviewCount
    }
    private var missingForHero: Int { doc == nil ? (cached?.missing ?? 0) : missingCount }

    /// Hero pill — never claims a pass it has not computed.
    private var verdictPill: (String, Color) {
        if doc == nil && cached == nil { return ("PENDING", palette.textTertiary) }
        if !(doc?.issued ?? cached?.issued ?? false) { return ("NOT ISSUED", palette.textTertiary) }
        if missingForHero > 0 { return ("INCOMPLETE", Brand.danger) }
        if reviewForHero > 0 { return ("REVIEW", Brand.warning) }
        if comparableCount > 0 { return ("MATCHED", Brand.success) }
        return ("PENDING", palette.textTertiary)
    }

    private var heroWash: Color {
        let color = verdictPill.1
        return color == palette.textTertiary ? palette.tintNeutral : color.opacity(0.16)
    }

    private var heroHeadline: String {
        guard doc?.issued ?? cached?.issued ?? false else { return "No waybill issued yet" }
        return "\(matchedForHero) of \(comparableCount) fields matched"
    }

    private var heroSubline: String {
        var parts: [String] = []
        if reviewForHero > 0 {
            parts.append("\(reviewForHero) discrepanc\(reviewForHero == 1 ? "y" : "ies")")
        } else if (doc?.issued ?? cached?.issued ?? false) {
            parts.append("no discrepancies")
        } else {
            parts.append("nothing to reconcile")
        }
        if let n = waybillNumber, !n.isEmpty { parts.append(n) }
        if let at = ISO685.stamp(wb?.createdAt ?? cached?.issuedAt) { parts.append("issued \(at)") }
        return parts.joined(separator: " · ")
    }

    // MARK: Derived — jurisdiction

    private var jurisdictions: [Jurisdiction685] {
        var out: [Jurisdiction685] = []
        if let o = Jurisdiction685.from(detail?.originYard?.country) { out.append(o) }
        if let d = Jurisdiction685.from(detail?.destinationYard?.country), !out.contains(d) { out.append(d) }
        if out.isEmpty {
            out = (cached?.jurisdictions ?? []).compactMap { Jurisdiction685(rawValue: $0) }
        }
        return out
    }

    private var isCrossBorder: Bool { jurisdictions.count > 1 }

    private var hasHazmat: Bool {
        if let c = doc?.hazmatClass, !c.isEmpty { return true }
        if let c = wb?.hazmatInfo?.`class`, !c.isEmpty { return true }
        return false
    }

    // MARK: Derived — READ_CACHED(15m) staleness

    private var cacheAge: TimeInterval? {
        guard let stamp = lastSyncedAt ?? cached?.savedAt else { return nil }
        return Date().timeIntervalSince(stamp)
    }

    private var cacheIsStale: Bool {
        guard let age = cacheAge else { return true }
        return age > WaybillReceiptCacheStore685.ttl
    }

    private var stalenessLine: String {
        guard let age = cacheAge else { return "no cached copy" }
        let prefix = servedFromCache ? "cached" : "live"
        if age < 60 { return "\(prefix) · just now" }
        if age < 3600 { return "\(prefix) · \(Int(age / 60))m ago" }
        return "\(prefix) · \(Int(age / 3600))h ago"
    }

    // MARK: Derived — commit gating

    private var commitMode: CommitMode685 { issued ? .reissue : .issue }

    /// Mirrors REISSUABLE_RAIL_STATES at railShipments.ts:3087 so the CTA can
    /// state the reason instead of spending a round-trip on a 412.
    private static let reissuableStates: Set<String> = [
        "requested", "car_ordered", "car_placed", "loading", "loaded", "in_consist",
    ]

    private var commitTitle: String {
        commitMode == .issue ? "Issue waybill" : "Re-issue waybill"
    }

    /// The one place a disabled CTA gets its stated reason. nil = enabled.
    private var commitBlockedReason: String? {
        if scopeId <= 0 { return "No shipment in scope — load one first." }
        if !reach.isOnline {
            return "Offline · a waybill revision is legal paper, so it is never queued. Reconnect to commit."
        }
        if doc == nil { return "The document has not loaded — nothing to commit against." }
        if commitMode == .issue {
            let commodity = (doc?.commodity ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if commodity.isEmpty {
                return "A waybill cannot be issued without a commodity, and this shipment carries none — set the commodity on the shipment first."
            }
            return nil
        }
        let status = (doc?.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !status.isEmpty && !Self.reissuableStates.contains(status) {
            return "Re-issue is pre-departure only — this consist is '\(status.replacingOccurrences(of: "_", with: " "))'. The carried waybill is now the legal record of the move."
        }
        return nil
    }

    private var commitEnabled: Bool { commitBlockedReason == nil && !committing }

    // MARK: View

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header

                if scopeId <= 0 {
                    scopePrompt
                } else if loading && doc == nil && cached == nil {
                    LifecycleCard {
                        Text("Loading the waybill of record…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if doc == nil && cached == nil {
                    LifecycleCard(accentWarning: true) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No waybill in scope for shipment \(scopeId).")
                                .font(EType.caption).foregroundStyle(palette.textPrimary)
                            Text("A waybill shows as missing when the shipment does not exist or is not yours — nothing is assumed on your behalf.")
                                .font(EType.caption).foregroundStyle(palette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    verdictHero
                    ledgerSection
                    revisionSection
                    authorityBand
                    ctaPair
                    if let refusal { refusalBanner(refusal) }
                }

                if let loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(loadError).font(EType.caption).foregroundStyle(Brand.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task {
            if scopeId == 0 { scopeId = shipmentId }
            if idText.isEmpty && shipmentId > 0 { idText = String(shipmentId) }
            await load()
        }
        .eusoRefreshable { await load() }
        // rail:doc_updated → .esangRefreshSurface (RealtimeService.swift:591).
        // A re-issue committed anywhere now repaints this document live.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { note in
            let event = (note.object as? String) ?? ""
            guard event.isEmpty || event.hasPrefix("rail:") else { return }
            Task { await load() }
        }
        .overlay(alignment: .bottom) { toastView }
        .sheet(isPresented: $showConfirm) { confirmSheet }
    }

    // MARK: Header — SVG y=72 eyebrow · y=90 back · y=116 H1 · y=136 sub · y=150 chips · y=192 hairline

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                EusoTripEyebrow(verbatim: "RAIL · WAYBILL OF RECORD")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: Space.s2)
                Text(waybillNumber ?? shipmentNumber ?? "—")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }

            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Text("Waybill receipt")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: Space.s2)
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(subLine)
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: Space.s2)
                // READ_CACHED(15m) staleness — always drawn, warns past TTL.
                Text(stalenessLine)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(cacheIsStale ? Brand.warning : palette.textTertiary)
                    .fixedSize()
                    .accessibilityLabel("Waybill copy \(stalenessLine)")
            }

            chipRow
            IridescentHairline().padding(.top, 4)
        }
    }

    private var subLine: String {
        var parts: [String] = [carrierLabel]
        parts.append(issued ? "waybill of record" : "no waybill issued")
        if comparableCount > 0 { parts.append("\(comparableCount) fields reconciled") }
        if let n = shipmentNumber, !n.isEmpty { parts.append(n) }
        return parts.joined(separator: " · ")
    }

    /// SVG y=150 — three pills: matched (green) · review (amber) · document state.
    private var chipRow: some View {
        HStack(spacing: Space.s2) {
            chip("\(matchedForHero) match", Brand.success)
            chip("\(reviewForHero) review", reviewForHero > 0 ? Brand.warning : palette.textTertiary)
            chip(revisionChipText, palette.textSecondary)
            Spacer(minLength: 0)
        }
    }

    private var revisionChipText: String {
        let count = revisions.isEmpty ? (cached?.revisionCount ?? 0) : revisions.count
        if count > 1 { return "\(count) revisions" }
        if count == 1 { return "1 revision" }
        return issued ? "issued" : "not issued"
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy)).tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(palette.bgCard))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    // MARK: Scope prompt (the gallery entry and any deep link without an id)

    private var scopePrompt: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            LifecycleCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Enter a rail shipment ID to pull its waybill of record.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                    Text("The ledger reconciles the shipment as tendered against the shipping paper the car actually moves on.")
                        .font(EType.caption).foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: Space.s3) {
                Image(systemName: "number")
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textTertiary)
                TextField("Shipment ID", text: $idText)
                    .keyboardType(.numberPad)
                    .font(.system(size: 15, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                    .submitLabel(.go)
                    .onSubmit { Task { await applyScope() } }
                Button { Task { await applyScope() } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.text.magnifyingglass").font(.system(size: 12, weight: .heavy))
                        Text("Open waybill").font(.system(size: 12, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(LinearGradient.diagonal))
                }
                .buttonStyle(.plain)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    // MARK: Verdict hero — SVG y=206, 400×120, gradient rim + washed header band

    private var verdictHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s3) {
                Image(systemName: "doc.plaintext")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(verdictPill.1)
                Text(heroBandLabel)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(verdictPill.1)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: Space.s2)
                Text(verdictPill.0)
                    .font(.system(size: 10.5, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(verdictPill.1)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(verdictPill.1.opacity(0.16)))
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(heroWash)

            VStack(alignment: .leading, spacing: 6) {
                Text(heroHeadline)
                    .font(.system(size: 22, weight: .bold)).kerning(-0.2)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(heroSubline)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if missingForHero > 0 {
                    Text("\(missingForHero) tendered field\(missingForHero == 1 ? "" : "s") absent from the shipping paper — a car can be held at the gate for this.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var heroBandLabel: String {
        if let n = waybillNumber, !n.isEmpty { return "WAYBILL OF RECORD · \(n)" }
        return "WAYBILL OF RECORD · NONE ISSUED"
    }

    // MARK: Ledger — SVG y=344 register + y=354 panel (400×342)

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionRegister(left: "FIELD RECONCILIATION · \(rows.count)",
                            right: "tendered → received")

            if rows.isEmpty {
                LifecycleCard {
                    Text("Nothing to reconcile until the waybill is issued.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        reconRow(row)
                        if index < rows.count - 1 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func sectionRegister(left: String, right: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(left)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: Space.s2)
                Text(right)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            Rectangle().fill(palette.borderFaint).frame(height: 1)
        }
    }

    /// SVG rows: label, "tendered <value> → <value>", verdict glyph at the right,
    /// with a rounded wash lifted behind any row that is not a clean match.
    private func reconRow(_ row: ReconRow685) -> some View {
        HStack(alignment: .center, spacing: Space.s2) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.label)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    if row.textCompare && row.verdict.isComparable {
                        Text("text")
                            .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(palette.tintNeutral))
                    }
                }
                HStack(spacing: 6) {
                    Text(row.verdict == .notTendered ? "not tendered" : "tendered")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                    if let t = row.tendered {
                        Text(t)
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Text("→")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textTertiary)
                    Text(row.received ?? "not on the paper")
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(verdictColor(row.verdict))
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: Space.s2)
            verdictGlyph(row.verdict)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(verdictWash(row.verdict))
                .padding(.horizontal, Space.s2)
        )
    }

    private func verdictColor(_ v: ReconVerdict685) -> Color {
        switch v {
        case .match:       return Brand.success
        case .differ:      return Brand.warning
        case .missing:     return Brand.danger
        case .notTendered: return palette.textTertiary
        }
    }

    private func verdictWash(_ v: ReconVerdict685) -> Color {
        switch v {
        case .match, .notTendered: return .clear
        case .differ:              return Brand.warning.opacity(0.12)
        case .missing:             return Brand.danger.opacity(0.12)
        }
    }

    @ViewBuilder
    private func verdictGlyph(_ v: ReconVerdict685) -> some View {
        switch v {
        case .match:
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Brand.success)
        case .differ:
            Image(systemName: "exclamationmark")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Brand.warning)
        case .missing:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Brand.danger)
        case .notTendered:
            Image(systemName: "minus")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Revision register — the document's own history + the car list
    //
    // Not in the SVG's 440×956 crop, but a document of record without its
    // revision chain is not a document of record: re-issue INSERTS a superseding
    // rail_waybills row, so waybills[] is literally the chain of paper this car
    // has moved under. Drawn in the SVG's own register grammar (eyebrow + rule +
    // ruled rows), not a new visual language.

    private var revisionSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionRegister(left: "REVISION CHAIN · \(revisions.count)",
                            right: distinctRailcars.isEmpty
                                ? "no car on the paper"
                                : "\(distinctRailcars.count) car\(distinctRailcars.count == 1 ? "" : "s")")

            if revisions.isEmpty {
                LifecycleCard {
                    Text(issued
                         ? "The shipment detail read has not returned the waybill chain yet."
                         : "No shipping paper has been issued against this shipment.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(revisions.enumerated()), id: \.element.id) { index, rev in
                        revisionRow(rev, isCurrent: index == 0)
                        if index < revisions.count - 1 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func revisionRow(_ rev: WaybillRevision685, isCurrent: Bool) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 3) {
                Text(rev.waybillNumber ?? "—")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    if let car = rev.railcarNumber, !car.isEmpty {
                        Text(car)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(palette.textSecondary)
                    } else {
                        Text("no car named")
                            .font(.system(size: 10))
                            .foregroundStyle(Brand.warning)
                    }
                    if let at = ISO685.stamp(rev.createdAt) {
                        Text("· \(at)")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
            Spacer(minLength: Space.s2)
            Text(isCurrent ? "CURRENT" : "SUPERSEDED")
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(isCurrent ? Brand.success : palette.textTertiary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(isCurrent ? Brand.success.opacity(0.14) : palette.tintNeutral))
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 11)
    }

    // MARK: Authority band — SVG y=752, three 128×30 cells (country IS content)

    private var authorityBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                ForEach(Jurisdiction685.allCases) { j in
                    authorityCell(j, active: jurisdictions.contains(j))
                }
            }

            if jurisdictions.isEmpty {
                Text("Route jurisdiction unresolved — neither yard on this shipment carries a country, so no authority is claimed.")
                    .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if isCrossBorder {
                    Text("Cross-border move · customs of record \(jurisdictions.map { $0.customs }.joined(separator: " · "))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Brand.info)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if hasHazmat {
                    Text("Dangerous goods on the paper · \(jurisdictions.map { $0.dangerousGoods }.joined(separator: " · "))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Brand.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Regulator \(jurisdictions.map { $0.regulator }.joined(separator: " · "))")
                    .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func authorityCell(_ j: Jurisdiction685, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(j.authority)
                .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                .foregroundStyle(active ? Brand.blue : palette.textSecondary)
            Text(j.document)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(active ? Brand.blue : palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? Brand.blue.opacity(0.12) : palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .strokeBorder(active ? Brand.blue.opacity(0.35) : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    // MARK: CTA pair — SVG y=798 (primary 244 gradient + secondary 148 outline)

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                Button { showConfirm = true } label: {
                    ZStack {
                        if committing {
                            ProgressView().tint(.white)
                        } else {
                            Text(commitTitle)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(LinearGradient.primary))
                }
                .buttonStyle(.plain)
                .disabled(!commitEnabled)
                .opacity(commitEnabled ? 1 : 0.45)

                // STUB · named-gap. No acceptWaybill verb exists on any router,
                // so this slot is drawn unavailable with its reason on screen
                // rather than wired to a lookalike that would move the wrong row.
                Text("Accept as received")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.72)
                    .frame(width: 148, height: 48)
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(palette.bgCard))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(palette.borderFaint))
                    .opacity(0.45)
                    .accessibilityLabel("Accept as received — unavailable, not built yet")
            }

            if let reason = commitBlockedReason {
                Text(reason)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Accept / dispute is unavailable: railShipments exposes no acceptWaybill or disputeWaybill verb. Re-issuing a superseding revision is the only commit that exists against this document today.")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func refusalBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(Brand.danger)
            Text(text).font(EType.caption).foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(Brand.danger.opacity(0.12)))
    }

    // MARK: Confirm gate — a revision is a write against legal paper

    private var confirmSheet: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(commitMode == .issue ? "ISSUE SHIPPING PAPER" : "RE-ISSUE THE WAYBILL")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }

                Text(commitMode == .issue
                     ? "Issue the waybill"
                     : "Supersede \(waybillNumber ?? "this waybill")")
                    .font(.system(size: 22, weight: .heavy)).kerning(-0.3)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(commitMode == .issue
                     ? "This issues the shipment's first waybill from the tendered commodity, weight and hazmat class. It is the shipping paper the car will move on."
                     : "This issues a superseding, revision-tagged waybill, points the shipment at it, records the re-issue on the shipment's event history and on the immutable audit trail, and tells everyone watching this shipment — the shipper included — that the paper changed. A waybill revision is not undoable from the phone.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    confirmRow("Shipment", shipmentNumber ?? "#\(scopeId)")
                    confirmRow("Current paper", issued ? (waybillNumber ?? "issued") : "none issued")
                    confirmRow("New number", commitMode == .issue
                               ? "issued on commit"
                               : "next revision, issued on commit")
                    confirmRow("Consist state", statusWord)
                    confirmRow("Discrepancies", reviewForHero == 0 ? "none" : "\(reviewForHero) open")
                }
                .padding(Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                Text(commitMode == .issue
                     ? "Only a party to this shipment may attach shipping paper — anyone else is refused."
                     : "Only the shipment's shipper or an admin may re-issue, and only pre-departure. If it is declined, the refusal is shown here verbatim.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if !reach.isOnline {
                    Text("Offline · this commit is never queued. Reconnect first.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Brand.warning)
                }

                Button {
                    Task { await commit() }
                } label: {
                    HStack {
                        Spacer()
                        if committing {
                            ProgressView().tint(.white)
                        } else {
                            Text(commitMode == .issue ? "Confirm and issue" : "Confirm and re-issue")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(committing || !reach.isOnline)
                .opacity(reach.isOnline ? 1 : 0.45)

                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .background(palette.bgSheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private func confirmRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: Space.s2)
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: Toast

    private var toastView: some View {
        Group {
            if let t = toast {
                Text(t)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Brand.success))
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func showToast(_ msg: String) {
        withAnimation(.easeOut(duration: 0.18)) { toast = msg }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.easeOut(duration: 0.18)) { toast = nil }
        }
    }

    // MARK: Reads — READ_CACHED(15m), parallel fan-out, honest degradation

    private func applyScope() async {
        let trimmed = idText.trimmingCharacters(in: .whitespaces)
        scopeId = Int(trimmed) ?? 0
        doc = nil
        detail = nil
        cached = nil
        lastSyncedAt = nil
        servedFromCache = false
        await load()
    }

    private func load() async {
        loading = true
        loadError = nil

        guard scopeId > 0 else {
            loading = false
            return
        }

        // Cache-first so the document is on screen immediately and survives a
        // cold offline launch in a yard. The staleness line stays honest about
        // which of the two the reader is looking at.
        if cached == nil { cached = WaybillReceiptCacheStore685.load(shipmentId: scopeId) }
        if doc == nil && cached != nil { servedFromCache = true }

        // Parallel fan-out — one dead section degrades alone. getWaybill is the
        // document of record; getRailShipmentDetail supplies the revision chain,
        // the SPLC codes and the jurisdiction. Both return null on a foreign or
        // missing shipment, so both decode through Optional rather than throwing.
        async let docTask: WaybillDoc685? = EusoTripAPI.shared.query(
            "railShipments.getWaybill", input: ShipmentIn685(shipmentId: scopeId))
        async let detailTask: ShipmentDetail685? = EusoTripAPI.shared.query(
            "railShipments.getRailShipmentDetail", input: DetailIn685(id: scopeId))

        do {
            let fresh = try await docTask
            self.doc = fresh
            if fresh != nil {
                self.servedFromCache = false
                self.lastSyncedAt = Date()
            }
        } catch {
            // Degraded, and visibly so: the cached copy stays on screen with its
            // age in the header. We do not blank the document and we do not
            // pretend the read succeeded.
            if cached == nil {
                loadError = waybillErrorCopy(error, attempt: "load this waybill")
            }
            servedFromCache = cached != nil
        }

        self.detail = (try? await detailTask) ?? nil

        if doc != nil { persistCache() }
        loading = false
    }

    /// Operator-language copy for a failed waybill request.
    ///
    /// A raw `NSError` string ("EusoTripAPIError error 5") tells a rail clerk
    /// nothing they can act on, so every failure class is mapped to a sentence
    /// that names what did not happen and what to do next. Refusal reasons
    /// that already carry human copy — the tenant gate above all — are
    /// surfaced verbatim, because the reader needs to read them.
    private func waybillErrorCopy(_ error: Error, attempt: String) -> String {
        guard let api = error as? EusoTripAPIError else {
            if (error as NSError).domain == NSURLErrorDomain {
                return "No connection, so EusoTrip couldn't \(attempt). Check your signal, then try again."
            }
            return "Couldn't \(attempt). Try again in a moment."
        }
        switch api {
        case .unauthenticated:
            return "Your session expired before EusoTrip could \(attempt). Sign in again, then retry."
        case .forbidden(let reason):
            return reason
        case .trpcError(let reason):
            return reason
        case .httpStatus(let code, _):
            return "Shipping papers are unavailable right now (\(code)), so EusoTrip couldn't \(attempt). Try again in a moment."
        case .decodingFailed:
            return "The waybill came back in a form this app version can't read. Update the app, then retry."
        case .empty:
            return "Nothing came back, so EusoTrip couldn't \(attempt). Try again in a moment."
        case .notConfigured, .badURL:
            return "Shipping papers aren't reachable from this build. Restart the app, then try again."
        case .queuedForOfflineReplay:
            return "You're offline — a shipping paper is never held for later. Nothing was issued."
        }
    }

    private func persistCache() {
        let envelope = WaybillReceiptCache685(
            savedAt: Date(),
            shipmentNumber: doc?.shipmentNumber,
            waybillNumber: wb?.waybillNumber,
            carrier: doc?.originRailroad ?? doc?.destinationRailroad,
            status: doc?.status,
            issued: doc?.issued,
            matched: matchedCount,
            comparable: comparableRows.count,
            differing: differCount,
            missing: missingCount,
            issuedAt: wb?.createdAt,
            revisionCount: revisions.count,
            jurisdictions: jurisdictions.map { $0.rawValue }
        )
        WaybillReceiptCacheStore685.save(envelope, shipmentId: scopeId)
        cached = envelope
    }

    // MARK: Commit — ONLINE_ONLY · MUTATION, never query()

    private func commit() async {
        refusal = nil

        // ONLINE_ONLY, enforced rather than merely declared. No rail path is in
        // the six-path offline eligibility table (EusoTripAPI.swift:1684), and a
        // waybill revision is legal paper — so this refuses loudly instead of
        // queueing or being swallowed.
        guard reach.isOnline else {
            refusal = "Offline · the waybill was NOT re-issued and NOT queued. Reconnect and commit again."
            showConfirm = false
            return
        }
        guard scopeId > 0 else {
            refusal = "No shipment in scope — nothing to commit against."
            showConfirm = false
            return
        }
        if let reason = commitBlockedReason {
            refusal = reason
            showConfirm = false
            return
        }

        committing = true
        do {
            switch commitMode {
            case .reissue:
                // MUTATION → POST. reissueWaybill is `.mutation` at
                // railShipments.ts:3057; calling it through query() would issue a
                // GET and the server has no method override — the S4 class that
                // ships a permanently dead CTA.
                let out: ReissueOut685 = try await EusoTripAPI.shared.mutation(
                    "railShipments.reissueWaybill",
                    input: ReissueIn685(shipmentId: scopeId, railId: nil))
                showConfirm = false
                showToast("Waybill re-issued · \(out.waybillNumber ?? out.waybillId ?? "new revision")")

            case .issue:
                let commodity = (doc?.commodity ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let weight: Double? = {
                    guard let raw = doc?.weight, let v = Double(raw), v > 0 else { return nil }
                    return v
                }()
                let hazClass: String? = {
                    let c = (doc?.hazmatClass ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return c.isEmpty ? nil : c
                }()
                let out: CreateWaybillOut685 = try await EusoTripAPI.shared.mutation(
                    "railShipments.createRailWaybill",
                    input: CreateWaybillIn685(shipmentId: scopeId,
                                              commodity: commodity,
                                              weight: weight,
                                              hazmatClass: hazClass))
                showConfirm = false
                showToast("Waybill issued · \(out.waybillNumber ?? "new shipping paper")")
            }

            await load()
        } catch {
            // Surfaced verbatim, never silent — a FORBIDDEN here is the server's
            // tenant gate speaking and the reader needs to read it.
            refusal = waybillErrorCopy(error, attempt: "commit this waybill")
            showConfirm = false
        }
        committing = false
    }
}

// MARK: - Previews

#Preview("685 · EDI 417 Waybill Receipt · Night") {
    RailWaybillReceipt417_685(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("685 · EDI 417 Waybill Receipt · Light") {
    RailWaybillReceipt417_685(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
