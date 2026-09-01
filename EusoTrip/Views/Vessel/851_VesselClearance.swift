//
//  851_VesselClearance.swift
//  EusoTrip — Vessel Operator · Inward / Outward Port Clearance (851).
//
//  Port of "851 Vessel Inward Outward Clearance.svg" (Light + Dark).
//
//  ARCHETYPE — TWO-DIRECTIONAL GATE BOARD.
//  Clearance is not a status a ship reports and not a timeline she walks: it is
//  a PERMISSION she either holds or does not hold, and she needs two of them at
//  every call. INWARD clearance — free pratique, immigration, vessel entry,
//  the cargo declaration, the agent's appointment — must all be released before
//  she may break bulk and work cargo. OUTWARD clearance — dues paid, the final
//  crew list lodged, stores sealed under bond, the export declaration, the
//  clearance certificate itself — must all be released before she may sail. So
//  the screen is drawn as it is decided: two PARALLEL COLUMNS of conditions,
//  side by side, each cell HELD or RELEASED, with the sailing decision closing
//  the board at the bottom. A master reads down one column to know what stops
//  her working and down the other to know what stops her leaving.
//
//  ON THE INFLUENCE, NOT THE DESIGN: 843 (Ballast) also ends in a permission —
//  a three-condition discharge gate. The influence is acknowledged and the
//  composition is not reused: 843 is a TOP-DOWN HULL PLAN of fill columns with
//  a small gate beneath it, one direction, three conditions, drawn spatially
//  because a ballast tank is a place. 851 has no geometry at all and no hero
//  instrument above the gate — the gate IS the screen, it runs in two
//  directions at once, and its axis is the pair INWARD | OUTWARD rather than a
//  list. Neither column is a lifecycle: the conditions inside one are
//  concurrent, not sequential, which is exactly why a rail or a stepper would
//  misdescribe them.
//
//  Sibling separation:
//    · 672 (USCG eNOA/NOAD) files a NOTICE ahead of arrival — a submission, not
//      a permission, and it grants nothing.
//    · 678 (Port State Control) is an INSPECTION outcome with deficiencies.
//    · 663 (CBP Entry Detail) is one cargo entry's own lifecycle.
//    · 850 (Ship's Stores) is a quantity manifest; it is the SOURCE of exactly
//      one cell on this board and is named as such rather than duplicated.
//
//  WIRING (honest — every line number read off the live router this fire):
//    REAL — vesselShipments.getVesselShipmentDetail (vesselShipments.ts:561 ·
//        vesselProcedure · input { id: Int }). Returns a FLAT spread of the
//        vessel_shipments row plus { lifecycleStage, bols, customs, events,
//        demurrage, containers, originPort, destinationPort } — no `shipment`
//        wrapper, so this screen decodes off the ROOT. Two things on that
//        payload are load-bearing here: `vesselId`, which resolves the ship,
//        and `customs`, the customsDeclarations rows for this booking.
//    REAL — vesselShipments.getPortDetails (vesselShipments.ts:2313 ·
//        vesselProcedure · input { portId: Int }) → the ports row + berths. A
//        clearance is granted BY a port's authorities, so the port row (name,
//        UN/LOCODE, country, customsOffice) drives the header, and the country
//        regime below is selected from it rather than stamped.
//    REAL — vesselShipments.getVesselFleet (vesselShipments.ts:2525 ·
//        vesselProcedure) → full vessels rows. Used ONLY to resolve the ship
//        this call is actually on: the fleet page is matched on
//        `vessels.id == shipment.vesselId`. It is never used to pick "a"
//        vessel — a clearance is granted to ONE named hull, and attributing
//        this board to an arbitrary fleet row would be a false statement about
//        which ship is cleared. If the match fails, the ship stays unidentified
//        and the two MarineTraffic reads below are skipped rather than guessed.
//        NAMED GAP: no procedure resolves a vessels row by id — getVesselFleet
//        filters on vesselType / status / search only — so this client-side
//        match is the only honest path today. Proposed:
//        vessel.getVesselById({ vesselId: number }) → the vessels row.
//    REAL — vesselShipments.getVesselParticulars (vesselShipments.ts:2980 ·
//        vesselProcedure · input { imoNumber: String }) → MarineTraffic
//        particulars { imoNumber, mmsi, name, type, flag, grossTonnage,
//        deadweight, length, beam, yearBuilt, owner, operator, callSign,
//        classification } or null. Clearance is granted to a SHIP, identified
//        by IMO number and flag, so her particulars are the board's identity
//        strip. The procedure returns null when the integration is unconfigured
//        or errors (it is wrapped in try/catch at :2987) — that renders as
//        em-dashes, never as a filled-in identity.
//    REAL — vesselShipments.getVesselPortCalls (vesselShipments.ts:2994 ·
//        vesselProcedure · input { imoNumber: String, days: Number }) → a bare
//        PortCall[] { portName, portId, unlocode, arrivalTime, departureTime,
//        inPort, draught, country } or null. This is the arrival the clearance
//        belongs to: the board is matched to the call at THIS port, so the
//        screen states which arrival it is deciding rather than floating free.
//    REAL — vesselShipments.getVesselCrew (vesselShipments.ts:2417 ·
//        vesselProcedure · input { companyId?, search? }) → { crew[],
//        certifications[], expiringCount }. The outward gate holds a FINAL CREW
//        LIST condition, and this is its honest source: the headcount is real.
//        HONESTY CONSTRAINT: the procedure scopes by COMPANY, not by ship —
//        there is no shipmentId / voyageId input — and there is no sign-on /
//        sign-off record anywhere (crewChange|signOn|signOff grep to 0), so the
//        count is stated as a company roster count and the LODGEMENT of the
//        list stays unverified. A headcount is not a lodged crew list.
//    STUB · named-gap — vessel.getPortClearance({ shipmentId, portId }).
//        Grepped repo-wide this fire: `inwardClearance|outwardClearance|
//        portClearance` = 0 occurrences. There is no clearance model on disk.
//        Proposed TS shape:
//            getPortClearance: vesselProcedure
//              .input(z.object({ shipmentId: z.number(), portId: z.number() }))
//              .query(): {
//                inward:  { condition: "freePratique"|"immigration"
//                                     |"vesselEntry"|"agentAppointed",
//                           state: "held"|"released"|"waived",
//                           authority: string,
//                           releasedAt: string | null,
//                           reference: string | null,
//                           holdReason: string | null }[],
//                outward: { condition: "portDues"|"crewListFinal"
//                                     |"storesSealed"|"clearanceCertificate",
//                           state: "held"|"released"|"waived",
//                           authority: string,
//                           releasedAt: string | null,
//                           reference: string | null,
//                           holdReason: string | null }[],
//                inwardGrantedAt:  string | null,
//                outwardGrantedAt: string | null,
//                clearanceCertificateNo: string | null,
//                mayBreakBulk: boolean,
//                maySail: boolean
//              }
//        Until it ships, every condition except the two cargo-declaration cells
//        reads NO RECORD, and the sailing decision has NO CODE PATH TO
//        "CLEARED TO SAIL" — see the decision bar below.
//    STUB · named-gap REGULATORY + IRREVERSIBLE —
//        vessel.requestPortClearance({ shipmentId, portId, direction,
//        confirm:true }) and vessel.grantOutwardClearance({ shipmentId, portId,
//        confirm:true }) [gated + confirm:true + audit + test + eval]; the
//        grant writes the port_clearance row + blockchainAuditTrail
//        vessel.outward_cleared and broadcasts WS_CHANNELS.VESSEL_OPS /
//        WS_EVENTS.CLEARANCE_GRANTED. RBAC vesselProcedure (master / ship's
//        agent). A vessel may not lawfully sail without the grant, which is why
//        it is irreversible and why it is not imitated here.
//    PARTLY WIRED, and exactly how far — vesselShipments.createCustomsEntry:1349
//        and vesselShipments.updateCustomsStatus:1401 were read first-hand.
//        createCustomsEntry inserts a customsDeclarations row from
//        { shipmentId, declarationType: import|export|transit|temporary_import,
//        htsCode?, countryOfOrigin?, declaredValue?, currency, dutyRate?,
//        brokerId? }; updateCustomsStatus moves one through
//        draft|filed|under_review|cleared|held|rejected and stamps filedDate /
//        clearedDate. Their READ side is genuinely useful here and is used: the
//        customsDeclarations rows ride in on getVesselShipmentDetail, so the
//        CARGO IMPORT DECLARATION cell on the inward column and the CARGO
//        EXPORT DECLARATION cell on the outward column are live — they read
//        RELEASED only when a matching declaration carries status "cleared".
//        Their WRITE side does NOT fit and is NOT called: neither procedure can
//        express a clearance. A port clearance is a permission granted to a
//        HULL by customs, immigration, port health and the port authority
//        together; a customsDeclarations row is one consignment of merchandise
//        with an HTS code and a duty rate. Calling updateCustomsStatus from a
//        "Request clearance" button would move a cargo entry's status and then
//        paint a ship as cleared to sail, which is the precise lie this board
//        exists to prevent. Stated plainly rather than forced.
//    PRECISION NOTE — the live cells are labelled CARGO declarations, not the
//        vessel's own entry. Under US practice the ship reports and enters
//        herself on CBP Form 1300; her cargo is entered separately. The board
//        keeps VESSEL ENTRY and CARGO IMPORT DECLARATION as two different cells
//        because they are two different permissions, and only the second one
//        has a row on the wire.
//
//  OFFLINE POLICY (doctrine W):
//    READ  · READ_CACHED(10m) — the condition board may be served from the last
//            decoded payload, because a held condition read ten minutes late is
//            still a held condition and reading it is not a decision. The
//            staleness is made UNMISTAKABLE rather than implied, and this is
//            the one place on the band where that matters most: a stale
//            "CLEARED TO SAIL" is exactly the lie the honesty law exists to
//            prevent. So a retained serve (a) paints the whole board with a
//            dashed amber rim, (b) prints an explicit NOT LIVE · AS OF hh:mm
//            banner above it, and (c) forces the sailing decision bar into its
//            stale rendering, in which it cannot read as a permission at all.
//            HONEST SCOPE OF THAT TIER: what this file does is retain the last
//            decoded serve IN MEMORY for the session and flag a failed refresh
//            above it. Services/EusoTripAPI.swift sets
//            .reloadIgnoringLocalAndRemoteCacheData with urlCache = nil, so
//            nothing survives a cold launch and the 10m TTL is a policy
//            declaration, not an enforced one. OPEN item (owning lane:
//            the-oath): a real on-disk read cache with TTL enforcement.
//    WRITE · ONLINE_ONLY(a clearance decision is a legal act) — requesting or
//            granting clearance asserts to a port state that a ship may work
//            cargo or leave. Queued and replayed later it could release a ship
//            against conditions that have since changed, or record a grant that
//            never happened. Never queued, under any connectivity.
//
//  CHAIN CLOSURE:
//    Intended emit WS_EVENTS.CLEARANCE_GRANTED on WS_CHANNELS.VESSEL_OPS, read
//    by 652 Compliance, by the departure surfaces (853 tidal window) and by the
//    berth board. OPEN counter-party item (owning lane: VESSEL · the-oath): the
//    receiving half does not exist — RealtimeService.swift carries no vessel:*
//    case and Views/Vessel has zero realtime subscribers, so a granted
//    clearance would land on no listener. Named rather than papered over.
//
//  COUNTRY (single-country content, never a file fork) — selected from the live
//    port row's country: US CBP Form 1300 vessel entry, USCG and USPHS free
//    pratique, and no breaking bulk before a permit to unlade under 19 CFR 4.30 ·
//    CA CBSA reporting with Transport Canada · MX Aduanas and SEMAR / Capitanía
//    de Puerto despacho.
//
//  Nav: HOME · SHIPMENTS · [orb] · COMPLIANCE(current) · ME — matches the SVG
//  NAV field, which marks COMPLIANCE.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselClearanceScreen: View {
    let theme: Theme.Palette
    /// vessel_shipments.id — the call being cleared. 0 = nothing threaded; the
    /// screen says so rather than inventing an arrival.
    var shipmentId: Int = 0
    /// ports.id of the clearing port. 0 = resolve from the call's destination
    /// (arrival) port, then its origin port.
    var portId: Int = 0
    /// Optional IMO override. Empty = resolve the hull from the call's vesselId
    /// against getVesselFleet; never guessed.
    var imoNumber: String = ""
    /// Optional tenant scope for the crew roster. Omitted by default so the
    /// server scopes from ctx.user.companyId.
    var companyId: Int = 0

    var body: some View {
        Shell(theme: theme) {
            VesselClearanceBody(shipmentId: shipmentId,
                                portId: portId,
                                threadedImo: imoNumber,
                                companyId: companyId)
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

// MARK: - Wire shapes

/// The ports row (drizzle `ports`), as returned by getPortDetails:2313 and
/// nested on getVesselShipmentDetail:561.
private struct ClearancePort851: Decodable {
    let id: Int?
    let name: String?
    let unlocode: String?
    let country: String?
    let customsOffice: String?
}

/// One customsDeclarations row as it rides in on getVesselShipmentDetail.
/// `declarationType` is the createCustomsEntry:1349 enum; `status` is the
/// updateCustomsStatus:1401 enum.
private struct ClearanceCustoms851: Decodable, Identifiable {
    let id: Int
    let declarationType: String?
    let status: String?
    let filedDate: String?
    let clearedDate: String?
}

private struct ClearanceDetail851: Decodable {
    let id: Int?
    let bookingNumber: String?
    let voyageNumber: String?
    let vesselId: Int?
    let originPortId: Int?
    let destinationPortId: Int?
    let status: String?
    let originPort: ClearancePort851?
    let destinationPort: ClearancePort851?
    let customs: [ClearanceCustoms851]?
}

/// A vessels row from getVesselFleet:2525 — the fleet select is `db.select()`,
/// so the FULL row arrives. Only the identity fields are read.
private struct ClearanceVessel851: Decodable, Identifiable {
    let id: Int
    let name: String?
    let imoNumber: String?
    let callSign: String?
    let flag: String?
    let grossTonnage: Int?
}

private struct ClearanceFleet851: Decodable {
    let vessels: [ClearanceVessel851]
}

/// MarineTraffic particulars from getVesselParticulars:2980 — null when the
/// integration is unconfigured or the upstream errors.
private struct ClearanceParticulars851: Decodable {
    let imoNumber: String?
    let name: String?
    let flag: String?
    let type: String?
    let grossTonnage: Int?
    let callSign: String?
    let classification: String?
}

/// One PortCall from getVesselPortCalls:2994 (bare array, or null).
private struct ClearanceCall851: Decodable {
    let portName: String?
    let unlocode: String?
    let arrivalTime: String?
    let departureTime: String?
    let inPort: Bool?
    let country: String?
}

private struct ClearanceCrew851: Decodable, Identifiable {
    let id: Int
    let name: String?
    let role: String?
    let isActive: Bool?
}

private struct ClearanceCrewPayload851: Decodable {
    let crew: [ClearanceCrew851]
}

// MARK: - Gate model

/// The state of one condition on the board. `unverified` is a first-class
/// member, not a fallback: "nobody has released this" and "an authority has
/// actively held it" are different facts with different next actions, and a
/// condition with no record must never render as either a release or a hold.
private enum GateState851 {
    case released(String)     // detail line — when and by what reference
    case held(String)         // detail line — the stated hold reason
    case unverified           // no record exists

    var isReleased: Bool {
        if case .released = self { return true }
        return false
    }
}

private enum GateDirection851: String {
    case inward = "INWARD"
    case outward = "OUTWARD"
}

/// One condition on one column of the board. The condition and its authority
/// are the REGULATION, printed the way 843 prints the D-2 standard; the state
/// is data.
private struct GateCondition851: Identifiable {
    let id: String
    let title: String
    let authority: String
    let form: String
    var state: GateState851 = .unverified
    /// True when this cell's state came off the wire rather than from the
    /// absence of a record. Drives the LIVE marker so a reader can tell the two
    /// evidenced cells from the eight unevidenced ones at a glance.
    var isLive: Bool = false
}

// MARK: - Body

private struct VesselClearanceBody: View {
    @Environment(\.palette) private var palette

    let shipmentId: Int
    let portId: Int
    let threadedImo: String
    let companyId: Int

    @State private var detail: ClearanceDetail851? = nil
    @State private var port: ClearancePort851? = nil
    @State private var vessel: ClearanceVessel851? = nil
    @State private var particulars: ClearanceParticulars851? = nil
    @State private var call: ClearanceCall851? = nil
    @State private var crew: [ClearanceCrew851] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var servedAt: Date? = nil

    // MARK: Derived context

    private var clearingPort: ClearancePort851? {
        port ?? detail?.destinationPort ?? detail?.originPort
    }

    private var portName: String { clearingPort?.name ?? "—" }
    private var portCode: String? { clearingPort?.unlocode?.uppercased() }
    private var countryCode: String { (clearingPort?.country ?? "US").uppercased() }

    private var shipLine: String {
        let name = particulars?.name ?? vessel?.name
        let imo = particulars?.imoNumber ?? vessel?.imoNumber
        switch (name, imo) {
        case let (n?, i?): return "\(n) · IMO \(i)"
        case let (n?, nil): return "\(n) · IMO —"
        case let (nil, i?): return "Ship unnamed · IMO \(i)"
        default:            return shipmentId > 0 ? "Ship not identified" : "No call threaded"
        }
    }

    private var subtitleLine: String {
        guard let d = detail else {
            return shipmentId > 0 ? "Call not loaded · inward & outward clearance"
                                  : "No call threaded · inward & outward clearance"
        }
        let booking = d.bookingNumber ?? "booking —"
        if let voy = d.voyageNumber, !voy.isEmpty {
            return "\(booking) · voy \(voy) · \(portName)"
        }
        return "\(booking) · \(portName)"
    }

    private var servingStale: Bool { loadError != nil && detail != nil }

    // MARK: The board

    /// The cargo declaration cell for one direction, derived from the
    /// customsDeclarations rows that ride in on getVesselShipmentDetail. This
    /// is the only place on the board where a state is evidenced today.
    private func cargoDeclarationState(_ type: String) -> (GateState851, Bool) {
        guard let rows = detail?.customs else { return (.unverified, false) }
        let matching = rows.filter { ($0.declarationType ?? "").lowercased() == type }
        guard !matching.isEmpty else { return (.unverified, false) }
        if let cleared = matching.first(where: { ($0.status ?? "").lowercased() == "cleared" }) {
            return (.released("cleared \(Self.day(cleared.clearedDate))"), true)
        }
        if let held = matching.first(where: { ["held", "rejected"].contains(($0.status ?? "").lowercased()) }) {
            return (.held("declaration \((held.status ?? "held").lowercased())"), true)
        }
        let statuses = Set(matching.compactMap { $0.status?.lowercased() })
        let label = statuses.sorted().joined(separator: " · ")
        return (.held(label.isEmpty ? "declaration open" : label), true)
    }

    private var inwardConditions: [GateCondition851] {
        let (cargo, live) = cargoDeclarationState("import")
        return [
            GateCondition851(id: "pratique",   title: "Free pratique",
                             authority: "Port health", form: pratiqueForm),
            GateCondition851(id: "immigration", title: "Immigration · crew inspection",
                             authority: "Border officers", form: immigrationForm),
            GateCondition851(id: "vesselEntry", title: "Vessel entry",
                             authority: "Customs · ship's report", form: vesselEntryForm),
            GateCondition851(id: "cargoImport", title: "Cargo import declaration",
                             authority: "Customs · entry", form: "customsDeclarations",
                             state: cargo, isLive: live),
            GateCondition851(id: "agent",       title: "Agent appointed · arrival lodged",
                             authority: "Ship's agent", form: "notice of arrival")
        ]
    }

    private var outwardConditions: [GateCondition851] {
        let (cargo, live) = cargoDeclarationState("export")
        return [
            GateCondition851(id: "dues",        title: "Port dues & disbursements",
                             authority: "Port authority", form: "disbursement account"),
            // The headcount is REAL (getVesselCrew:2417) and is printed as
            // what it actually is — a COMPANY roster count, not a ship's
            // complement and not a lodged list. The condition itself stays
            // unverified: there is no sign-on / sign-off record anywhere
            // (crewChange|signOn|signOff = 0 repo-wide), so nothing on the wire
            // can say this list was lodged with immigration.
            GateCondition851(id: "crewList",    title: "Final crew list lodged",
                             authority: "Immigration",
                             form: "\(crewListForm) · \(crewRosterLabel)"),
            GateCondition851(id: "stores",      title: "Stores sealed under bond",
                             authority: "Customs · FAL 3", form: "seal register · 850"),
            GateCondition851(id: "cargoExport", title: "Cargo export declaration",
                             authority: "Customs · entry", form: "customsDeclarations",
                             state: cargo, isLive: live),
            GateCondition851(id: "certificate", title: "Port clearance certificate",
                             authority: "Customs · master's clearance", form: clearanceForm)
        ]
    }

    /// The live roster count, stated honestly. `getVesselCrew` has no
    /// shipmentId / voyageId input — it scopes by company — so this is never
    /// described as "aboard" or as a complement.
    private var crewRosterLabel: String {
        if loading && crew.isEmpty { return "roster loading" }
        if crew.isEmpty { return "no roster returned" }
        let active = crew.filter { $0.isActive != false }.count
        return "\(active) on the company roster"
    }

    private var releasedCount: Int {
        (inwardConditions + outwardConditions).filter { $0.state.isReleased }.count
    }

    private var totalCount: Int { inwardConditions.count + outwardConditions.count }

    private var outwardAllReleased: Bool {
        outwardConditions.allSatisfy { $0.state.isReleased }
    }

    // MARK: Country content (never a fork)

    private var pratiqueForm: String {
        switch countryCode {
        case "CA": return "maritime declaration of health"
        case "MX": return "sanidad internacional"
        default:   return "USPHS · maritime declaration of health"
        }
    }
    private var immigrationForm: String {
        switch countryCode {
        case "CA": return "CBSA crew reporting"
        case "MX": return "INM · lista de tripulación"
        default:   return "CBP Form I-418"
        }
    }
    private var vesselEntryForm: String {
        switch countryCode {
        case "CA": return "CBSA vessel report · A6"
        case "MX": return "Aduanas · declaración de entrada"
        default:   return "CBP Form 1300"
        }
    }
    private var crewListForm: String {
        switch countryCode {
        case "CA": return "CBSA crew list"
        case "MX": return "INM · lista final"
        default:   return "CBP Form I-418 final"
        }
    }
    private var clearanceForm: String {
        switch countryCode {
        case "CA": return "CBSA clearance · Transport Canada"
        case "MX": return "Aduanas · despacho de salida"
        default:   return "CBP Form 1300 clearance"
        }
    }
    private var breakBulkRule: String {
        switch countryCode {
        case "CA": return "She may not work cargo until CBSA reports the vessel and releases her"
        case "MX": return "No puede iniciar descarga hasta el despacho de entrada · Aduanas"
        default:   return "She may not break bulk before a permit to unlade · 19 CFR 4.30"
        }
    }
    private var sailRule: String {
        switch countryCode {
        case "CA": return "She may not sail until CBSA and Transport Canada clear her outward"
        case "MX": return "No puede zarpar sin el despacho de salida · Aduanas / Capitanía"
        default:   return "She may not sail until customs issues her outward clearance"
        }
    }

    private var regulatorRows: [VesselRegulatorRow] {
        [
            .init("US", "CBP 1300 + USCG + USPHS pratique", active: countryCode == "US"),
            .init("CA", "CBSA + Transport Canada",           active: countryCode == "CA"),
            .init("MX", "Aduanas + SEMAR · Capitanía",       active: countryCode == "MX")
        ]
    }

    // MARK: - Composition

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · PORT CLEARANCE",
                caption: "INWARD · OUTWARD",
                title: "\(releasedCount) of \(totalCount) released",
                idText: portCode,
                subtitle: subtitleLine
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading && detail == nil {
                    skeleton
                } else if let err = loadError, detail == nil {
                    VesselErrorCard(text: err)
                    VesselGapNote(text: "No call is threaded into this screen, so there is no arrival to clear. A clearance belongs to one ship at one port on one call; the screen refuses to render a generic one.")
                } else {
                    if servingStale { staleBanner }
                    shipIdentityStrip
                    boardSection
                    decisionBar
                    VesselSummaryStrip(
                        label: "Inward — · outward — · certificate —",
                        value: "no clearance record",
                        valueColor: palette.textTertiary
                    )
                    VesselRegulatorBand(
                        title: "CLEARANCE AUTHORITY · SINGLE-COUNTRY",
                        reference: "port · \(countryCode)",
                        rows: regulatorRows
                    )
                    lockedActions
                    VesselGapNote(text: "Vessel particulars, port call, port, company roster, and two cargo-declaration records are available. Eight clearance conditions have no vessel-clearance evidence, so they remain No record and no sailing release is shown. No value is estimated.")
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - Staleness (the one that matters most on this band)

    private var staleBanner: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("NOT LIVE · AS OF \(Self.clock(servedAt))")
                    .font(.system(size: 9.5, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(Brand.warning)
                Text("Refresh failed — \(loadError ?? "no reason returned") The board below is the last serve this session returned. A clearance can be withdrawn between one read and the next, so nothing here may be relied on as a permission.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.tintWarning)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.warning.opacity(0.55),
                              style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Ship identity (a clearance is granted to a hull)

    private var shipIdentityStrip: some View {
        VesselGroupCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(shipLine)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(clearingPort?.customsOffice.map { "Clearing office \($0)" } ?? "Customs office not on the port row")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 8)
                    Text(callStatePill)
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(palette.tintNeutral))
                }
                HStack(spacing: Space.s3) {
                    identityChip(label: "FLAG", value: particulars?.flag ?? vessel?.flag ?? "—")
                    identityChip(label: "CALL SIGN", value: particulars?.callSign ?? vessel?.callSign ?? "—")
                    identityChip(label: "GT", value: (particulars?.grossTonnage ?? vessel?.grossTonnage).map { "\($0)" } ?? "—")
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                    Text("Arrived \(Self.stamp(call?.arrivalTime)) · departed \(Self.stamp(call?.departureTime))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var callStatePill: String {
        guard let call else { return "CALL NOT MATCHED" }
        if call.departureTime?.isEmpty == false { return "DEPARTED" }
        if call.inPort == true { return "ALONGSIDE" }
        return "EXPECTED"
    }

    private func identityChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(value == "—" ? palette.textTertiary : palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(palette.bgCardSoft))
    }

    // MARK: - The two-directional gate board

    private var boardSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "CLEARANCE GATE · 2 DIRECTIONS · \(totalCount) CONDITIONS",
                                right: "Clearance record not connected")
            HStack(alignment: .top, spacing: Space.s3) {
                gateColumn(.inward, conditions: inwardConditions, rule: breakBulkRule)
                gateColumn(.outward, conditions: outwardConditions, rule: sailRule)
            }
            HStack(spacing: Space.s4) {
                legendChip("Released", Brand.success, dashed: false)
                legendChip("Held", Brand.warning, dashed: false)
                legendChip("No record", palette.textTertiary, dashed: true)
                Spacer(minLength: 0)
            }
        }
    }

    private func gateColumn(_ direction: GateDirection851,
                            conditions: [GateCondition851],
                            rule: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: direction == .inward ? "arrow.down.right" : "arrow.up.right")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                Text(direction.rawValue)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("\(conditions.filter { $0.state.isReleased }.count)/\(conditions.count)")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, Space.s2)
            VStack(spacing: 0) {
                ForEach(Array(conditions.enumerated()), id: \.element.id) { idx, condition in
                    if idx > 0 { Divider().overlay(palette.borderFaint) }
                    gateCell(condition)
                }
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(servingStale ? Brand.warning.opacity(0.55) : palette.borderFaint,
                                  style: StrokeStyle(lineWidth: servingStale ? 1.2 : 1,
                                                     dash: servingStale ? [5, 4] : []))
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            Text(rule)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func gateCell(_ condition: GateCondition851) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: gateGlyph(condition.state))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(gateTone(condition.state))
                Text(condition.title)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2).minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            Text("\(condition.authority) · \(condition.form)")
                .font(.system(size: 8.5, weight: .regular))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(2).minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 5) {
                stateChip(condition.state)
                if condition.isLive {
                    Text("LIVE")
                        .font(.system(size: 7, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Brand.blue)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Brand.blue.opacity(0.14)))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.s3)
    }

    private func gateGlyph(_ state: GateState851) -> String {
        switch state {
        case .released: return "checkmark.seal.fill"
        case .held:     return "hand.raised.fill"
        case .unverified: return "lock"
        }
    }

    private func gateTone(_ state: GateState851) -> Color {
        switch state {
        case .released: return Brand.success
        case .held:     return Brand.warning
        case .unverified: return palette.textTertiary
        }
    }

    /// A state chip has three renderings and no fourth. `unverified` is drawn
    /// dashed and neutral so it can never be mistaken for either verdict.
    private func stateChip(_ state: GateState851) -> some View {
        let text: String
        let detail: String?
        switch state {
        case .released(let note): text = "RELEASED"; detail = note
        case .held(let note):     text = "HELD";     detail = note
        case .unverified:         text = "NO RECORD"; detail = nil
        }
        let tone = gateTone(state)
        var dashed = false
        if case .unverified = state { dashed = true }
        return VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                .foregroundStyle(tone)
                .padding(.horizontal, 8).padding(.vertical, 2.5)
                .background(Capsule().fill(tone.opacity(dashed ? 0.0 : 0.14)))
                .overlay(
                    Capsule().strokeBorder(tone.opacity(dashed ? 0.45 : 0.0),
                                           style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
                )
            if let detail {
                Text(detail)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    private func legendChip(_ label: String, _ color: Color, dashed: Bool) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(dashed ? Color.clear : color)
                .frame(width: 9, height: 9)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(color.opacity(dashed ? 0.6 : 0.0),
                                      style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                )
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: - The sailing decision

    /// THE DECISION BAR HAS NO CODE PATH TO "CLEARED TO SAIL", and that is
    /// deliberate rather than an oversight. A ship is cleared when customs
    /// issues the clearance certificate; nothing on the wire can evidence that
    /// certificate today, so no combination of live reads may produce a
    /// release. When vessel.getPortClearance ships, the released case is added
    /// HERE and nowhere else, gated on `outwardGrantedAt != nil` — never on a
    /// count of cells, and never on cached data.
    private var decisionBar: some View {
        let stale = servingStale
        let tone: Color = stale ? Brand.warning : palette.textTertiary
        let headline: String = stale
            ? "SAILING DECISION NOT LIVE"
            : (outwardAllReleased ? "SAILING DECISION UNAVAILABLE" : "NOT CLEARED TO SAIL")
        let reason: String = {
            if stale {
                return "This board is a retained serve from \(Self.clock(servedAt)). A clearance may have been granted or withdrawn since; it may not be read as a permission."
            }
            if outwardAllReleased {
                return "Every outward condition reads released, but no clearance certificate is on record. The certificate is the act, not the tally, so the decision stays unavailable."
            }
            let held = outwardConditions.filter { !$0.state.isReleased }.count
            return "\(held) of \(outwardConditions.count) outward conditions are unreleased. \(sailRule)."
        }()
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: stale ? "exclamationmark.triangle.fill" : "hand.raised.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tone)
                Text(headline)
                    .font(.system(size: 14, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(tone)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text("CLR —")
                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            Text(reason)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(stale ? palette.tintWarning : palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(tone.opacity(0.55),
                              style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Actions (both ONLINE_ONLY · both disabled behind a named gap)

    private var lockedActions: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Brand.warning)
                Text("Clearance request and certificate issuance are unavailable until a vessel-clearance record is connected.")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            HStack(spacing: Space.s3) {
                CTAButton(title: "Request clearance", action: {}, trailingIcon: "checkmark.seal")
                    .opacity(0.55)
                    .disabled(true)
                    .accessibilityHint("Unavailable until a vessel-clearance record is connected")
                VesselGhostButton(title: "Certificate", width: 140) {}
                    .opacity(0.55)
                    .disabled(true)
                    .accessibilityHint("Unavailable — no clearance certificate is on record")
            }
            VesselGapNote(text: "Clearance request and outward-clearance grant are unavailable because no vessel-clearance record is connected. Both are legal acts that require an online confirmation and are never queued. A cargo-declaration status cannot substitute for permission granted to the vessel.")
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 130)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 380)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 90)
        }
    }

    // MARK: - Load
    //  Six real reads, in dependency order. The call resolves the port and the
    //  hull; the hull resolves the IMO; the IMO resolves the particulars and
    //  the port call. Nothing downstream of a failed resolution is guessed.

    private func load() async {
        loading = true
        loadError = nil

        struct DetailIn: Encodable { let id: Int }
        struct PortIn: Encodable { let portId: Int }
        struct FleetIn: Encodable { let limit: Int; let offset: Int }
        struct ImoIn: Encodable { let imoNumber: String }
        struct CallsIn: Encodable { let imoNumber: String; let days: Int }
        struct CrewIn: Encodable { let companyId: Int?; let search: String? }

        var failures: [String] = []

        // 1. The call.
        if shipmentId > 0 {
            do {
                let d: ClearanceDetail851? = try await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselShipmentDetail", input: DetailIn(id: shipmentId))
                if let d { self.detail = d }
            } catch {
                // The prior serve is deliberately NOT cleared — a failed
                // refresh keeps the board under an explicit NOT LIVE banner
                // rather than blanking it.
                failures.append(error.eusoUserCopy)
            }
        }

        // 2. The clearing port.
        let resolvedPortId = portId > 0
            ? portId
            : (detail?.destinationPortId ?? detail?.originPortId ?? 0)
        if resolvedPortId > 0 {
            do {
                let p: ClearancePort851? = try await EusoTripAPI.shared.query(
                    "vesselShipments.getPortDetails", input: PortIn(portId: resolvedPortId))
                if let p { self.port = p }
            } catch {
                failures.append(error.eusoUserCopy)
            }
        }

        // 3. The hull. Matched on vessels.id == shipment.vesselId — never
        //    "the first vessel in the fleet". A clearance names one ship.
        if let vesselId = detail?.vesselId, vesselId > 0 {
            do {
                let fleet: ClearanceFleet851 = try await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselFleet", input: FleetIn(limit: 50, offset: 0))
                self.vessel = fleet.vessels.first { $0.id == vesselId }
            } catch {
                failures.append(error.eusoUserCopy)
            }
        }

        // 4 + 5. Particulars and port calls, keyed on the resolved IMO. Both
        //        are wrapped in try/catch server-side and return null when the
        //        MarineTraffic integration is unconfigured, which renders as
        //        em-dashes rather than as a filled-in identity.
        let imo: String = {
            if !threadedImo.isEmpty { return threadedImo }
            return vessel?.imoNumber ?? ""
        }()
        if !imo.isEmpty {
            do {
                let p: ClearanceParticulars851? = try await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselParticulars", input: ImoIn(imoNumber: imo))
                self.particulars = p
            } catch {
                failures.append(error.eusoUserCopy)
            }
            do {
                let calls: [ClearanceCall851]? = try await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselPortCalls", input: CallsIn(imoNumber: imo, days: 14))
                self.call = Self.matchCall(calls, to: clearingPort?.unlocode)
            } catch {
                failures.append(error.eusoUserCopy)
            }
        }

        // 6. The people aboard — the outward gate's crew-list condition.
        do {
            let payload: ClearanceCrewPayload851 = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselCrew",
                input: CrewIn(companyId: companyId > 0 ? companyId : nil, search: nil))
            self.crew = payload.crew
        } catch {
            failures.append(error.eusoUserCopy)
        }

        if failures.isEmpty {
            servedAt = Date()
        } else {
            loadError = failures.joined(separator: " · ")
        }
        loading = false
    }

    /// The call at THIS port, not merely the latest call. When the port cannot
    /// be matched the screen says CALL NOT MATCHED rather than attaching the
    /// board to an arrival somewhere else.
    private static func matchCall(_ calls: [ClearanceCall851]?, to unlocode: String?) -> ClearanceCall851? {
        guard let calls, !calls.isEmpty else { return nil }
        if let code = unlocode?.uppercased(), !code.isEmpty {
            if let hit = calls.first(where: { ($0.unlocode ?? "").uppercased() == code }) { return hit }
            return nil
        }
        return calls.first(where: { $0.inPort == true })
    }

    // MARK: - Formatting helpers

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static func clock(_ date: Date?) -> String {
        guard let date else { return "—:—" }
        return clockFormatter.string(from: date)
    }

    /// MarineTraffic timestamps arrive as strings in assorted shapes. Rendered
    /// trimmed to the minute when they look like one, verbatim otherwise, and
    /// as an em-dash when absent. Never re-derived into a relative phrase the
    /// upstream did not state.
    private static func stamp(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        let normalised = raw.replacingOccurrences(of: "T", with: " ")
        if normalised.count >= 16 {
            return String(normalised.prefix(16))
        }
        return normalised
    }

    /// A date-only rendering for a customs declaration's cleared/filed stamp.
    private static func day(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        let normalised = raw.replacingOccurrences(of: "T", with: " ")
        if normalised.count >= 10 { return String(normalised.prefix(10)) }
        return normalised
    }
}

#Preview("851 · Vessel Inward / Outward Clearance · Night") {
    VesselClearanceScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("851 · Vessel Inward / Outward Clearance · Light") {
    VesselClearanceScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
