//
//  849_VesselGeneralDeclaration.swift
//  EusoTrip — Vessel Operator · General Declaration, IMO FAL Form 1 (849).
//
//  Live-wired port of "849 Vessel General Declaration.svg" (Light + Dark).
//  DOCUMENT FACE + VALIDATION GUTTER archetype — ONE form's CONTENTS.
//
//  FAL Form 1 is the basic document of arrival and departure: the ship, the
//  voyage, the call, the complement, the cargo in brief, and the master's
//  attestation. It is a numbered instrument — the officer reading it asks for
//  "box 9" and "box 12", not for a row in a table. So this screen is drawn as
//  the form itself: numbered boxes in form order, each carrying its value and,
//  in a gutter down the right edge, whether that box is complete, or missing
//  and therefore blocking lodgement. Every box also states WHERE its value came
//  from, because on a legal declaration the provenance of a figure matters as
//  much as the figure.
//
//  Sibling separation (the band's #1 axis — 849 is one of the forms 848 lodges):
//    · 848 Maritime Single Window is the ENVELOPE — a column-headed
//      transmission ledger of eight declarations with sent times, authority
//      acknowledgements and re-sent counts, closed by an all-forms-lodged gate.
//      It never shows a field of any form. 849 is nothing BUT fields: no
//      timestamps of transmission, no acknowledgement, no resubmission counter,
//      no second party, no ledger columns.
//    · 699 Vessel Particulars is the ship's permanent specification sheet;
//      849 borrows four of its facts and is otherwise a per-call document that
//      expires the moment the ship sails.
//    · 738 VGM Declaration is a per-container mass attestation; 668 IMDG is a
//      hazmat manifest. Neither is a numbered statutory form face.
//    · 843 Ballast Water is a hull plan and a permission gate — spatial, not
//      documentary.
//
//  WIRING (read first-hand off the live router this fire, not inherited).
//  The ship, the port and the call genuinely exist, so this document face draws
//  real particulars rather than literals — and leaves a box EMPTY rather than
//  fill it from something adjacent:
//    REAL · vesselShipments.getVesselShipmentDetail (vesselShipments.ts:561,
//        input { id: number }) → FLAT spread `{ ...shipment, lifecycleStage,
//        bols, customs, events, demurrage, containers, originPort,
//        destinationPort }` (:587). Supplies box 4 (voyage number), box 6
//        (date/time of arrival, from ata ?? eta), box 15 (brief particulars of
//        voyage, from origin → destination + serviceRoute) and box 16 (brief
//        description of cargo, from commodity / cargoType / container count /
//        total weight).
//    REAL · vesselShipments.getPortDetails (:2313, input { portId: number })
//        → `{ ...port, berths }` off the `ports` table. Supplies box 5, the
//        port of arrival, as name + UN/LOCODE from the port record.
//    REAL · vesselShipments.getVesselFleet (:2525, input { limit, offset, … })
//        → `{ vessels, total }`, a straight select off the `vessels` table.
//        Supplies boxes 1, 2, 3, 7 and 12 — name, type, IMO number, call sign,
//        flag and gross tonnage. NOTE the deliberate resolution rule below.
//    REAL · vesselShipments.getVesselParticulars (:2980, input { imoNumber })
//        → MarineTraffic particulars `{ imoNumber, mmsi, name, type, flag,
//        grossTonnage, deadweight, length, beam, yearBuilt, owner, operator,
//        callSign, classification }`, cached 24h. Used ONLY as an overlay where
//        the registry column is null — never to overwrite a registry value, and
//        never as the sole source of a box (it returns null with no API key).
//    REAL · vesselShipments.getVesselPortCalls (:2994, input { imoNumber,
//        days }) → bare PortCall[] `{ portName, portId, unlocode, arrivalTime,
//        departureTime, inPort, draught, country }`. Supplies the LAST PORT OF
//        CALL half of box 9, taken as the most recent call that has actually
//        departed. The NEXT PORT half has no source — port calls are history,
//        not schedule — so box 9 stays incomplete and says exactly why.
//
//    SHIP RESOLUTION, stated because it is a compromise: there is no
//        getVesselById on disk. `vessel_shipments.vesselId` is the real link
//        (drizzle/schema.ts:11813) and getVesselFleet is a plain paged select,
//        so the ship is resolved by matching that id inside the fetched page.
//        If the ship is not in the page, boxes 1/2/3/7/12 stay EM-DASH rather
//        than falling back to "the first vessel in the fleet" — putting another
//        ship's IMO number on a General Declaration is a forgery, not a
//        fallback. OPEN item (owning lane: the-oath):
//        vessel.getVesselById({vesselId}).
//
//    NOT WIRED, and why:
//      · vesselShipments.getVesselCrew (:2417) exists, but it returns COMPANY
//        USERS holding vessel roles (VESSEL_SHIPPER, VESSEL_OPERATOR,
//        PORT_MASTER, SHIP_CAPTAIN, VESSEL_BROKER, CUSTOMS_BROKER) filtered by
//        companyId — an office roster, not this hull's signed-on complement for
//        this voyage. Counting it into box 17 would print a crew number on a
//        statutory form that no muster supports, and picking its SHIP_CAPTAIN
//        row for box 8 would name a master who may never have sailed on her.
//        Boxes 8 and 17 stay empty and say so.
//      · vesselShipments.createCustomsEntry (:1349) and updateCustomsStatus
//        (:1401) are real, but neither fits FAL 1. createCustomsEntry inserts a
//        DUTY entry keyed on declarationType/HTS/declared value/duty rate;
//        updateCustomsStatus moves a duty entry through draft→filed→cleared. A
//        General Declaration has no HTS code, no declared value and no duty,
//        and its lodgement state is not the customs enum. Forcing either would
//        write a commercial entry in place of a master's declaration. Named,
//        not forced. (848 wires updateCustomsStatus where it genuinely belongs
//        — on the customs entries themselves.)
//      · Net tonnage (box 13) is NOT deadweight and NOT gross tonnage. The
//        `vessels` table carries grossTonnage and deadweightTonnage and no net
//        tonnage column, so box 13 is empty. Substituting DWT would be a false
//        entry on a form a port state control officer reads.
//
//    STUB · named-gap — there is no FAL Form 1 model on disk (`generalDeclaration
//        |FAL|falForm` greps to zero repo-wide this fire). Proposed shapes:
//
//        vessel.getGeneralDeclaration({ callId: string }) -> {
//          callId: string,
//          direction: "arrival" | "departure",
//          master: { name: string, licenceNo: string | null } | null,
//          agent: { name: string, contact: string } | null,
//          certificateOfRegistry: { port: string, date: string,
//                                   number: string } | null,
//          netTonnage: number | null,
//          berthOrStation: string | null,
//          nextPort: { name: string, unlocode: string } | null,
//          crewCount: number | null,
//          passengerCount: number | null,
//          remarks: string | null,
//          attachedCopies: Record<"cargo"|"stores"|"crewList"|"passengerList"
//                                 |"crewEffects"|"health", number>,
//          lodgement: { state: "draft"|"ready"|"lodged"|"amended",
//                       lodgedAt: string | null,
//                       reference: string | null } | null
//        }
//
//        vessel.signGeneralDeclaration({ callId: string, confirm: true })
//          [REGULATORY · IRREVERSIBLE — the master's attestation]
//          gated + confirm:true + audit + test + eval; pin .sortedKeys.
//          Writes the fal1_declaration row + blockchainAuditTrail
//          vessel.fal1_signed, broadcasts WS_CHANNELS.VESSEL_OPS /
//          WS_EVENTS.FAL1_LODGED. RBAC vesselProcedure (master).
//
//        vessel.amendGeneralDeclaration({ callId, boxes, confirm: true })
//          — an amendment to a lodged declaration is itself a filing and
//          carries the same gate.
//
//        Until those exist, Sign & lodge and Amend are `.disabled(true)` with
//        the missing procedure named on screen. No local @State is mutated to
//        imitate a signature.
//
//  COUNTRY (content inside the screen, never a file fork):
//    US CBP / USCG — the FAL 1 accepted in place of CBP Form 1300 —
//    FOREGROUNDED. CA CBSA A6 General Declaration under ACI, and MX SEMAR /
//    API Declaración General through VUCEM, sit on the standby band.
//
//  OFFLINE POLICY (doctrine W — derived, not stamped):
//    READ  · READ_CACHED(15m) with a visible staleness line. The ship's
//            particulars and the call's ports change slowly, so a slightly old
//            document face is still a usable one — and every unresolved box is
//            visibly distinct, so a cached serve can never masquerade as a
//            complete form. The read time is printed on the attestation block.
//            HONEST SCOPE OF THAT TIER: the code retains the last decoded serve
//            IN MEMORY for the session and banner-flags a failed refresh above
//            it instead of blanking the form. There is NO persistent cache —
//            Services/EusoTripAPI.swift:415-416 sets
//            .reloadIgnoringLocalAndRemoteCacheData and urlCache = nil — so
//            nothing survives a cold launch and the 15m TTL is a policy
//            declaration, not an enforced one. OPEN item (the-oath): a real
//            on-disk read cache with TTL enforcement.
//    WRITE · ONLINE_ONLY(the master's attestation is a legal filing and is
//            irreversible). Signing FAL 1 binds the master personally to every
//            box on it. Queued offline and replayed later it would attest to a
//            state of the ship that had already changed, and it could not be
//            withdrawn once replayed. No connection, no signature.
//
//  CHAIN CLOSURE:
//    Intended emit WS_EVENTS.FAL1_LODGED on WS_CHANNELS.VESSEL_OPS, so 848's
//    transmission board and the compliance console (652) learn the form left
//    the ship.
//    OPEN counter-party item (owning lane: VESSEL · the-oath): no receiver
//    exists. RealtimeService carries no vessel:* case and Views/Vessel holds
//    zero realtime subscribers, so a lodgement would land on no listener and
//    848 would not learn of it until its own next read.
//
//  Nav: HOME · SHIPMENTS · [orb] · COMPLIANCE(current) · ME — the eyebrow, the
//  nav and this note agree.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselGeneralDeclarationScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0

    var body: some View {
        Shell(theme: theme) {
            VesselGeneralDeclarationBody(shipmentId: shipmentId)
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

// MARK: - Live shapes

private struct Port849: Decodable {
    let id: Int?
    let name: String?
    let unlocode: String?
    let country: String?
}

/// `vesselShipments.getVesselShipmentDetail` :561 — the call itself.
private struct Detail849: Decodable {
    let id: Int?
    let bookingNumber: String?
    let voyageNumber: String?
    let serviceRoute: String?
    let vesselId: Int?
    let commodity: String?
    let cargoType: String?
    let numberOfContainers: Int?
    let totalWeightKg: String?      // decimal(14,2) → JSON string
    let eta: String?
    let ata: String?
    let originPortId: Int?
    let destinationPortId: Int?
    let originPort: Port849?
    let destinationPort: Port849?

    /// FLAT-SHAPE GUARD — the payload has no `shipment` wrapper (:587). Decode
    /// off the root; a wrapper would silently yield nil and strand the form in
    /// its awaiting state forever.
    private enum CodingKeys: String, CodingKey {
        case id, bookingNumber, voyageNumber, serviceRoute, vesselId, commodity
        case cargoType, numberOfContainers, totalWeightKg, eta, ata
        case originPortId, destinationPortId, originPort, destinationPort
    }
}

/// `vesselShipments.getVesselFleet` :2525 — a straight select off `vessels`.
private struct VesselRow849: Decodable {
    let id: Int?
    let name: String?
    let imoNumber: String?
    let callSign: String?
    let vesselType: String?
    let flag: String?
    let grossTonnage: Int?
    let deadweightTonnage: Int?
}
private struct Fleet849: Decodable { let vessels: [VesselRow849] }

/// `vesselShipments.getVesselParticulars` :2980 — MarineTraffic overlay.
private struct Particulars849: Decodable {
    let imoNumber: String?
    let name: String?
    let type: String?
    let flag: String?
    let callSign: String?
    let grossTonnage: Int?
}

/// `vesselShipments.getVesselPortCalls` :2994 — bare PortCall[].
private struct PortCall849: Decodable {
    let portName: String?
    let unlocode: String?
    let arrivalTime: String?
    let departureTime: String?
    let inPort: Bool?
    let country: String?
}

// MARK: - The box model (the document's unit)

/// One numbered box of FAL Form 1. `value == nil` means NOT AVAILABLE — never
/// zero, never a placeholder, never a value borrowed from an adjacent field.
/// `required` is the Convention's, not ours: box 19 remarks and box 20 attached
/// copies do not block lodgement; the rest do.
private struct FALBox849: Identifiable {
    let id: String        // the box number as printed on the form
    let label: String
    let value: String?
    let source: String    // where the value came from, or what is missing
    let required: Bool

    var complete: Bool { value != nil }
    var blocking: Bool { value == nil && required }
}

/// A titled band of the form — the document's own grouping, used as printed
/// rules between box runs rather than as separate cards.
private struct FALBand849: Identifiable {
    let id: String
    let caption: String
    let boxes: [FALBox849]
}

// MARK: - Body

private struct VesselGeneralDeclarationBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int

    @State private var detail: Detail849? = nil
    @State private var arrivalPort: Port849? = nil
    @State private var ship: VesselRow849? = nil
    @State private var particulars: Particulars849? = nil
    @State private var lastCall: PortCall849? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var readAt: Date? = nil

    // MARK: Resolved identity (live or absent)

    private var shipName: String? {
        let n = ship?.name ?? particulars?.name
        return (n?.isEmpty == false) ? n : nil
    }

    private var imoNumber: String? {
        let raw = ship?.imoNumber ?? particulars?.imoNumber
        guard let raw, !raw.isEmpty else { return nil }
        return raw.uppercased().hasPrefix("IMO")
            ? raw.uppercased()
            : "IMO \(raw)"
    }

    /// The bare digits MarineTraffic and the port-call feed expect.
    private var bareImo: String? {
        guard let raw = ship?.imoNumber, !raw.isEmpty else { return nil }
        return raw.uppercased().hasPrefix("IMO")
            ? String(raw.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            : raw
    }

    private var arrivalPlace: String? {
        guard let p = arrivalPort ?? detail?.destinationPort else { return nil }
        return Self.place(p.name, p.unlocode)
    }

    private var headerTitle: String { shipName ?? "General Declaration" }

    private var headerSubtitle: String {
        var parts: [String] = ["FAL 1 · arrival"]
        if let a = arrivalPlace { parts.append(a) }
        if let v = detail?.voyageNumber, !v.isEmpty { parts.append("voy \(v)") }
        return parts.joined(separator: " · ")
    }

    private var stalenessLine: String {
        guard let readAt else { return "not yet read" }
        let mins = Int(Date().timeIntervalSince(readAt) / 60)
        return mins <= 0 ? "read just now" : "read \(mins)m ago"
    }

    // MARK: The form face — built from live data, box by box

    private var bands: [FALBand849] {
        [
            FALBand849(id: "ship", caption: "THE SHIP", boxes: shipBoxes),
            FALBand849(id: "call", caption: "THE CALL", boxes: callBoxes),
            FALBand849(id: "load", caption: "COMPLEMENT & CARGO", boxes: loadBoxes),
            FALBand849(id: "part", caption: "PARTIES, REMARKS & ATTACHMENTS", boxes: partyBoxes)
        ]
    }

    private var shipBoxes: [FALBox849] {
        let typeText = (ship?.vesselType ?? particulars?.type)?
            .replacingOccurrences(of: "_", with: " ")
        let nameAndType: String? = {
            guard let n = shipName else { return nil }
            guard let t = typeText, !t.isEmpty else { return n }
            return "\(n) · \(t)"
        }()
        let gt: String? = {
            if let g = ship?.grossTonnage, g > 0 { return Self.grouped(g) }
            if let g = particulars?.grossTonnage, g > 0 { return Self.grouped(g) }
            return nil
        }()
        let flag = Self.nonEmpty(ship?.flag ?? particulars?.flag)
        let call = Self.nonEmpty(ship?.callSign ?? particulars?.callSign)

        return [
            FALBox849(id: "1", label: "Name and type of ship", value: nameAndType,
                      source: nameAndType == nil ? "vessel not resolved on this booking" : "vessel registry",
                      required: true),
            FALBox849(id: "2", label: "IMO number", value: imoNumber,
                      source: imoNumber == nil ? "vessel not resolved on this booking" : "vessel registry",
                      required: true),
            FALBox849(id: "3", label: "Call sign", value: call,
                      source: call == nil ? "no call sign on the vessel record" : "vessel registry",
                      required: true),
            FALBox849(id: "7", label: "Flag State of ship", value: flag,
                      source: flag == nil ? "no flag on the vessel record" : "vessel registry",
                      required: true),
            FALBox849(id: "12", label: "Gross tonnage", value: gt,
                      source: gt == nil ? "no gross tonnage on the vessel record" : "vessel registry",
                      required: true),
            FALBox849(id: "13", label: "Net tonnage", value: nil,
                      source: "no net tonnage held — deadweight is not net tonnage and is not substituted",
                      required: true)
        ]
    }

    private var callBoxes: [FALBox849] {
        let arrivalStamp = Self.stampText(detail?.ata ?? detail?.eta)
        let lastPort = Self.nonEmpty(lastCall.flatMap { Self.place($0.portName, $0.unlocode) })
        let box9: String? = lastPort.map { "\($0) → —" }
        let voyageParticulars: String? = {
            let from = detail?.originPort.flatMap { Self.place($0.name, $0.unlocode) }
            let to = arrivalPlace
            guard let from, let to else { return nil }
            if let route = Self.nonEmpty(detail?.serviceRoute) {
                return "\(from) → \(to) · \(route)"
            }
            return "\(from) → \(to)"
        }()

        return [
            FALBox849(id: "4", label: "Voyage number", value: Self.nonEmpty(detail?.voyageNumber),
                      source: Self.nonEmpty(detail?.voyageNumber) == nil ? "no voyage number on the booking" : "booking",
                      required: true),
            FALBox849(id: "5", label: "Port of arrival", value: arrivalPlace,
                      source: arrivalPlace == nil ? "no destination port on the booking" : "port record",
                      required: true),
            FALBox849(id: "6", label: "Date and time of arrival", value: arrivalStamp,
                      source: arrivalStamp == nil ? "neither actual nor estimated arrival is on the booking"
                                                  : (detail?.ata != nil ? "booking · actual arrival" : "booking · estimated arrival"),
                      required: true),
            FALBox849(id: "9", label: "Last port of call / next port of call", value: box9,
                      source: box9 == nil ? "no departed port call in the vessel's history"
                                          : "last port from port-call history · next port not recorded",
                      required: true),
            FALBox849(id: "14", label: "Position of the ship in the port", value: nil,
                      source: "no berth or station assignment is held for this call",
                      required: true),
            FALBox849(id: "15", label: "Brief particulars of voyage", value: voyageParticulars,
                      source: voyageParticulars == nil ? "origin or destination port missing on the booking" : "booking · port records",
                      required: true)
        ]
    }

    private var loadBoxes: [FALBox849] {
        let cargo: String? = {
            var parts: [String] = []
            if let c = Self.nonEmpty(detail?.commodity) { parts.append(c) }
            if let t = Self.nonEmpty(detail?.cargoType) {
                parts.append(t.replacingOccurrences(of: "_", with: " "))
            }
            if let n = detail?.numberOfContainers, n > 0 { parts.append("\(n) containers") }
            if let w = Self.nonEmpty(detail?.totalWeightKg), let d = Double(w), d > 0 {
                parts.append("\(Self.grouped(Int(d.rounded()))) kg")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }()

        return [
            FALBox849(id: "16", label: "Brief description of the cargo", value: cargo,
                      source: cargo == nil ? "no commodity, cargo type, container count or weight on the booking" : "booking",
                      required: true),
            FALBox849(id: "17", label: "Number of crew", value: nil,
                      source: "no signed-on complement for this voyage · available roster is company-wide",
                      required: true),
            FALBox849(id: "18", label: "Number of passengers", value: nil,
                      source: "no passenger record connected · blank does not mean zero",
                      required: true)
        ]
    }

    private var partyBoxes: [FALBox849] {
        [
            FALBox849(id: "8", label: "Name of master", value: nil,
                      source: "no master of record for this voyage",
                      required: true),
            FALBox849(id: "10", label: "Certificate of registry (port, date, number)", value: nil,
                      source: "no certificate of registry held",
                      required: true),
            FALBox849(id: "11", label: "Name and contact details of ship's agent", value: nil,
                      source: "no port agent appointment held for this call",
                      required: true),
            FALBox849(id: "19", label: "Remarks", value: nil,
                      source: "optional — does not block lodgement",
                      required: false),
            FALBox849(id: "20", label: "Attached declarations (copies)", value: nil,
                      source: "optional here — the attached set is tracked on the single window",
                      required: false)
        ]
    }

    private var allBoxes: [FALBox849] { bands.flatMap(\.boxes) }
    private var requiredBoxes: [FALBox849] { allBoxes.filter(\.required) }
    private var completeRequired: Int { requiredBoxes.filter(\.complete).count }
    private var blockingBoxes: [FALBox849] { allBoxes.filter(\.blocking) }

    // MARK: Layout

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · GENERAL DECLARATION",
                caption: "IMO FAL · FORM 1",
                title: headerTitle,
                idText: imoNumber,
                subtitle: headerSubtitle
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading && detail == nil && ship == nil {
                    skeleton
                } else if let err = loadError, detail == nil {
                    VesselErrorCard(text: err)
                } else {
                    if let err = loadError {
                        VesselErrorCard(text: "Refresh failed — \(err) The declaration below is the last serve this session returned and is not being updated.")
                    }
                    masthead
                    documentFace
                    blockingStrip
                    attestationBlock
                    VesselRegulatorBand(
                        title: "ARRIVAL AUTHORITY · SINGLE-COUNTRY",
                        reference: "one authority per call",
                        rows: [
                            .init("US", "CBP / USCG · FAL 1 in lieu of CBP 1300", active: true),
                            .init("CA", "CBSA A6 General Declaration · ACI"),
                            .init("MX", "SEMAR / API · Declaración General · VUCEM")
                        ]
                    )
                    ctaPair
                    gapNotes
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - Masthead (the form's own head: boxes 1-3 and the completeness count)

    private var masthead: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    Text("IMO FAL Form 1 · arrival declaration")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text("NOT LODGED")
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Brand.warning)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Brand.warning.opacity(0.13)))
                        .overlay(Capsule().strokeBorder(Brand.warning.opacity(0.4),
                                                        style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5])))
                }
                // The form's head, as printed: three labelled cells across.
                HStack(alignment: .top, spacing: Space.s3) {
                    mastheadCell(caption: "1 · SHIP", value: shipName)
                    mastheadCell(caption: "2 · IMO No.", value: imoNumber, mono: true)
                    mastheadCell(caption: "3 · CALL SIGN",
                                 value: Self.nonEmpty(ship?.callSign ?? particulars?.callSign), mono: true)
                }
                Divider().overlay(palette.borderFaint)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(completeRequired) / \(requiredBoxes.count)")
                        .font(.system(size: 30, weight: .bold, design: .monospaced)).tracking(-0.5)
                        .foregroundStyle(completeRequired == requiredBoxes.count ? Brand.success : palette.textPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("required boxes complete")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(blockingBoxes.isEmpty
                             ? "no box is blocking lodgement"
                             : "\(blockingBoxes.count) blocking lodgement")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(blockingBoxes.isEmpty ? Brand.success : Brand.warning)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                }
                Text("Counted from the boxes below: a box is complete only when a real value resolved for it. Nothing is filled from an adjacent field.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func mastheadCell(caption: String, value: String?, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(caption)
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            Text(value ?? "—")
                .font(mono
                      ? .system(size: 12, weight: .bold, design: .monospaced)
                      : .system(size: 13, weight: .bold))
                .foregroundStyle(value == nil ? palette.textTertiary : palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The document face (numbered boxes + validation gutter)

    private var documentFace: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "DECLARATION · IMO FAL FORM 1",
                                right: "\(blockingBoxes.count) BLOCKING")
            VesselGroupCard(padded: false) {
                VStack(spacing: 0) {
                    ForEach(Array(bands.enumerated()), id: \.element.id) { bandIdx, band in
                        bandCaption(band.caption)
                        ForEach(Array(band.boxes.enumerated()), id: \.element.id) { idx, box in
                            if idx > 0 { Divider().overlay(palette.borderFaint) }
                            boxRow(box)
                        }
                        if bandIdx < bands.count - 1 {
                            Divider().overlay(palette.borderSoft)
                        }
                    }
                }
            }
            gutterLegend
        }
    }

    private func bandCaption(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s3)
        .padding(.bottom, 4)
    }

    /// One box of the form. The number sits in its own left column exactly as
    /// it is printed on FAL 1; the validation mark sits in a gutter down the
    /// right edge. A missing required box is drawn as an EMPTY dashed square —
    /// never as a red cross, because the box is not wrong, it is unfilled.
    private func boxRow(_ box: FALBox849) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Text(box.id)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
                .frame(width: 20, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                Text(box.label)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.65)
                Text(box.value ?? "—")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(box.complete ? palette.textPrimary : palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(box.source)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            gutterMark(box)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    @ViewBuilder
    private func gutterMark(_ box: FALBox849) -> some View {
        if box.complete {
            Image(systemName: "checkmark.square.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Brand.success)
                .frame(width: 22)
                .accessibilityLabel("Box \(box.id) complete")
        } else if box.required {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Brand.warning.opacity(0.75),
                              style: StrokeStyle(lineWidth: 1.4, dash: [3, 2.5]))
                .frame(width: 15, height: 15)
                .frame(width: 22)
                .accessibilityLabel("Box \(box.id) required and empty — blocks lodgement")
        } else {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(palette.textTertiary.opacity(0.45),
                              style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
                .frame(width: 15, height: 15)
                .frame(width: 22)
                .accessibilityLabel("Box \(box.id) optional and empty")
        }
    }

    private var gutterLegend: some View {
        HStack(spacing: Space.s4) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.square.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Brand.success)
                Text("Complete")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
            }
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(Brand.warning.opacity(0.75),
                                  style: StrokeStyle(lineWidth: 1.2, dash: [2.5, 2]))
                    .frame(width: 10, height: 10)
                Text("Blocks lodgement")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
            }
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(palette.textTertiary.opacity(0.45),
                                  style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .frame(width: 10, height: 10)
                Text("Optional")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - What is blocking

    private var blockingStrip: some View {
        VesselSummaryStrip(
            label: blockingBoxes.isEmpty
                ? "Every required box is filled"
                : "Blocking boxes · " + blockingBoxes.map(\.id).joined(separator: ", "),
            value: blockingBoxes.isEmpty ? "clear" : "\(blockingBoxes.count) of \(requiredBoxes.count)",
            valueColor: blockingBoxes.isEmpty ? Brand.success : Brand.warning
        )
    }

    // MARK: - Master's attestation (the foot of the form)

    private var attestationBlock: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "MASTER'S ATTESTATION · BOX 21",
                                right: "NOT ATTESTED")
            VesselGroupCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Text("I declare that the particulars entered above are true and correct.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // The signature rule, drawn as it is printed — an empty line.
                    VStack(alignment: .leading, spacing: 4) {
                        Rectangle()
                            .fill(palette.borderSoft)
                            .frame(height: 1)
                            .padding(.top, Space.s4)
                        HStack {
                            Text("Signature of master, authorised agent or officer")
                                .font(.system(size: 9, weight: .regular))
                                .foregroundStyle(palette.textTertiary)
                            Spacer(minLength: 8)
                            Text("—")
                                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                    Divider().overlay(palette.borderFaint)
                    attestationRow("Master of record", "—")
                    attestationRow("Attested at", "—")
                    attestationRow("Declaration read", stalenessLine)
                    HStack(spacing: 6) {
                        Image(systemName: "lock")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Brand.warning)
                        Text("Signing binds the master personally and cannot be withdrawn")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.65)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func attestationRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - CTA pair (both gap-blocked, both ONLINE_ONLY by policy)

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                CTAButton(title: "Sign & lodge", trailingIcon: "signature")
                    .disabled(true)
                    .accessibilityHint("Unavailable until a general-declaration record is connected")
                VesselGhostButton(title: "Amend", width: 130)
                    .disabled(true)
                    .accessibilityHint("Unavailable until a general-declaration record is connected")
            }
            VesselGapNote(text: "Sign and lodge is unavailable until a general-declaration record is connected. The master's attestation and any amendment require an active connection and are never queued.")
        }
    }

    // MARK: - Honest-gap notes

    private var gapNotes: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            VesselGapNote(text: "Vessel identity, port, booking, and port-call history supply the populated declaration boxes. Every other box remains blank because its required record has not been provided; no nearby value is substituted.")
            VesselGapNote(text: "Box 13 remains blank because net tonnage has not been provided; gross tonnage and deadweight are not substitutes. Box 17 remains blank because no vessel-specific signed-on complement has been confirmed. A statutory declaration must not infer either value.")
            VesselGapNote(text: "Previously loaded declaration facts remain visible with their read time. A master's signature or amendment requires an active connection and is never queued.")
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 220)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 380)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 160)
        }
    }

    // MARK: - Load (five real reads, in dependency order)

    private func load() async {
        loading = true; loadError = nil
        guard shipmentId > 0 else {
            detail = nil; ship = nil; arrivalPort = nil
            particulars = nil; lastCall = nil; loading = false
            return
        }
        struct DetailIn: Encodable { let id: Int }
        struct PortIn: Encodable { let portId: Int }
        struct FleetIn: Encodable { let limit: Int; let offset: Int }
        struct ImoIn: Encodable { let imoNumber: String }
        struct CallsIn: Encodable { let imoNumber: String; let days: Int }

        do {
            // 1 · the call
            let d: Detail849? = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipmentDetail", input: DetailIn(id: shipmentId))
            self.detail = d
            self.readAt = Date()

            // 2 · the port of arrival (box 5). Degrades to the joined row, never
            //     to a literal.
            if let portId = d?.destinationPortId ?? d?.destinationPort?.id {
                let resolved: Port849? = try? await EusoTripAPI.shared.query(
                    "vesselShipments.getPortDetails", input: PortIn(portId: portId))
                self.arrivalPort = resolved ?? d?.destinationPort
            } else {
                self.arrivalPort = d?.destinationPort
            }

            // 3 · the ship (boxes 1/2/3/7/12). Resolved by matching the booking's
            //     vesselId inside the fleet page — NOT by taking the first vessel.
            //     No match ⇒ those boxes stay empty. See the header note.
            if let vesselId = d?.vesselId {
                let fleet: Fleet849? = try? await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselFleet", input: FleetIn(limit: 100, offset: 0))
                self.ship = fleet?.vessels.first { $0.id == vesselId }
            } else {
                self.ship = nil
            }

            // 4 · the MarineTraffic overlay — fills only what the registry left
            //     null, and returns null with no API key, which is honest.
            if let imo = bareImo, !imo.isEmpty {
                self.particulars = try? await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselParticulars", input: ImoIn(imoNumber: imo))
            } else {
                self.particulars = nil
            }

            // 5 · last port of call (half of box 9) — the most recent call that
            //     has genuinely departed, and not this same arrival port.
            if let imo = bareImo, !imo.isEmpty {
                let calls: [PortCall849]? = try? await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselPortCalls", input: CallsIn(imoNumber: imo, days: 60))
                let arrivalCode = (arrivalPort?.unlocode ?? "").uppercased()
                self.lastCall = (calls ?? [])
                    .filter { ($0.departureTime?.isEmpty == false) && ($0.inPort != true) }
                    .filter { arrivalCode.isEmpty || ($0.unlocode ?? "").uppercased() != arrivalCode }
                    .max { lhs, rhs in
                        (Self.parseISO(lhs.departureTime) ?? .distantPast)
                            < (Self.parseISO(rhs.departureTime) ?? .distantPast)
                    }
            } else {
                self.lastCall = nil
            }
        } catch {
            // The retained serve stays on screen, banner-labelled as not fresh.
            // A half-blanked declaration is harder to read than a stale one that
            // says it is stale.
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    // MARK: - Formatting helpers

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    private static func place(_ name: String?, _ code: String?) -> String? {
        let n = nonEmpty(name)
        let c = nonEmpty(code)
        switch (n, c) {
        case let (n?, c?): return "\(n) \(c)"
        case let (n?, nil): return n
        case let (nil, c?): return c
        default: return nil
        }
    }

    private static func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    private static func parseISO(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let d = f.date(from: s) { return d }
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    private static func stampText(_ s: String?) -> String? {
        guard let d = parseISO(s) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM HH:mm"
        return f.string(from: d)
    }
}

#Preview("849 · Vessel General Declaration · Night") {
    VesselGeneralDeclarationScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("849 · Vessel General Declaration · Light") {
    VesselGeneralDeclarationScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
