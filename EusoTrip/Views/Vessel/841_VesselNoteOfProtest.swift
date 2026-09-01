//
//  841_VesselNoteOfProtest.swift
//  EusoTrip — Vessel Operator · Note of Protest (841).
//
//  App-integrated composition of "841 Vessel Note of Protest.svg"
//  (Light + Dark). SWORN-INSTRUMENT DOCUMENT SURFACE archetype. This screen is
//  not a dashboard and carries no metric: the centrepiece is the INSTRUMENT
//  ITSELF — an unexecuted note of protest rendered as a document sheet, its
//  recital slots drawn as ruled blanks, its operative clause set in the fixed
//  legal form, and the master's subscription line left unsigned. Under it sit
//  the three things that make the instrument work: the TIME BAR for noting
//  (the urgency — a limitation ruler with an arrival datum and a bar datum,
//  its travel mark unplaced), the CAUSAL EVENT as a bridge-log extract with a
//  ruled logbook margin, and an ENDORSEMENT & SEAL REGISTER of empty stamp
//  frames (master's declaration · oath administered · register entry ·
//  extension reserved). Deliberately NOT 838's countdown-plus-roster and NOT
//  834's naval-architecture plots; and deliberately not a node pipeline, which
//  would turn a legal instrument into a progress bar.
//  Nav: HOME · SHIPMENTS · [orb] · COMPLIANCE(current) · ME.
//
//  WIRING (honest) — the SVG <desc> names these procedures verbatim:
//    REAL — vesselShipments.getVesselShipmentDetail (vesselShipments.ts:162,
//        vesselProcedure, input { id: Int }) → { shipment: { id, vesselName,
//        bookingNumber, originPort, destinationPort, voyageNumber, … } }. The
//        ONLY live read here. It fills exactly two recital slots — the vessel
//        and the voyage/lane — and the header framing. Every other slot on the
//        instrument stays a ruled blank.
//    FIXED REFERENCE (real, not fabricated) — noting protest is a settled
//        concept of maritime law: the master declares, before a notary public
//        or other authorised officer, that loss or damage arose from perils
//        outside the master's control, and reserves the right to extend the
//        protest after survey. The form of words and the practice of noting
//        promptly on arrival, before breaking bulk, are the governing standard
//        the way 833 states the CSS Code. They are stated; they are not data.
//    STUB · named-gap — there is no note-of-protest / sea-protest model on
//        disk. From the wireframe <desc>, verbatim:
//          "Protest register + notarization → vessel.getNoteOfProtest({voyageId})
//           [STUB · named-gap: no note-of-protest/sea-protest model on disk;
//           reads voyage + adverse-event timestamps off
//           vesselShipments.getVesselShipmentDetail:162; 710 Marine Casualty is
//           the incident report, not the legal protest]"
//          "Lodge protest → vessel.lodgeNoteOfProtest({voyageId,confirm:true})
//           and Reserve extension →
//           vessel.reserveExtendedProtest({voyageId,confirm:true})
//           [STUB · LEGAL: gated + confirm:true + audit + test] write
//           protest_register row + blockchainAuditTrail vessel.protest_lodged,
//           broadcast WS_CHANNELS.VESSEL_OPS / WS_EVENTS.PROTEST_LODGED.
//           RBAC vesselProcedure (master)."
//        Until those ship, the adverse event, the noting time, the register
//        reference, the notary/consul attestation and the reservation of the
//        extended protest render as honest awaiting-states: blank recital
//        rules, an unplaced time-bar mark, em-dash log slots, unstamped
//        endorsement frames. A fabricated attestation — a seal shown as
//        affixed, a protest shown as lodged — would be a legal-class lie and
//        is never drawn. The SVG's illustrative content (heavy-weather damage
//        in the NE Pacific, noted 0300 LT, a register ref, a met 24h bar) sits
//        in this comment as the shape the model must return.
//    COUNTRY: single-country lodging formality — US Notary Public · 46 USC
//        active · CA Commissioner of Oaths · MX Corredor Público / Consulate.
//
//  OFFLINE POLICY:
//    READ  · READ_CACHED(15m) — a protest is prepared on the bridge and in the
//            agent's office where signal drops; the last good serve of the
//            voyage context stays on screen labelled as awaiting and is never
//            presented as a fresh register read.
//            HONEST SCOPE OF THAT TIER: what the code does today is retain the
//            last decoded serve IN MEMORY for the life of the session and
//            banner-flag a failed refresh above it instead of blanking the
//            screen. There is NO persistent cache layer behind it —
//            Services/EusoTripAPI.swift:415-416 sets
//            .reloadIgnoringLocalAndRemoteCacheData and urlCache = nil — so
//            nothing survives a cold launch and the 15m TTL is a policy
//            declaration, not an enforced one. OPEN item (owning lane:
//            the-oath): a real on-disk read cache with TTL enforcement.
//    WRITE · ONLINE_ONLY(a legal instrument must not be queued) — lodging the
//            protest and reserving the extended protest are legal acts with a
//            time of record. A queued protest would carry a false hour and
//            could destroy the very time-bar it exists to protect, so the CTA
//            refuses with an on-screen reason rather than enqueueing.
//
//  CHAIN CLOSURE:
//    Emit — WS_EVENTS.PROTEST_LODGED on WS_CHANNELS.VESSEL_OPS, raised by the
//    (stub) lodgeNoteOfProtest / reserveExtendedProtest writes.
//    Intended counter-party — the claims and cargo-liability side: the P&I /
//    H&M claims console and the general-average surface that must know a
//    protest is on the register before liability is apportioned, plus the
//    compliance ledger that files the attested instrument.
//    Listener — NONE. RealtimeService carries ~48 event cases and no vessel:*
//    case; Views/Vessel holds ZERO realtime subscribers (its only
//    RealtimeService mentions are header comments like this one), and
//    Views/Dispatch holds a single one — thin for that lane, but the client as a
//    whole is not: Views/Shipper alone references RealtimeService across ~23
//    files, with further use in Driver, Catalyst, Escort, Rail and Carrier. The
//    gap is vessel-specific, not app-wide. Nothing on iOS would hear PROTEST_LODGED
//    today. OPEN counter-party item → the-oath: the vessel lane owns the emit,
//    the claims/compliance console lane owns the missing receiver. Until it
//    lands, a lodged protest is write-only and no counter-party is notified.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselNoteOfProtestScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0
    /// Keys the STUB register read once vessel.getNoteOfProtest({voyageId}) ships.
    var voyageId: String = ""

    var body: some View {
        Shell(theme: theme) {
            VesselNoteOfProtestBody(shipmentId: shipmentId, voyageId: voyageId)
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

// MARK: - Shipment shape (getVesselShipmentDetail · the one REAL read)

private struct ProtestShipment841: Decodable {
    let id: Int?
    let vesselName: String?
    let bookingNumber: String?
    let originPort: String?
    let destinationPort: String?
    let voyageNumber: String?
}
private struct ProtestDetail841: Decodable {
    // FLAT-SHAPE REPAIR (2026-08-17). `vesselShipments.getVesselShipmentDetail`
    // returns a FLAT spread — `return { ...shipment, lifecycleStage, bols,
    // customs, events, demurrage, containers, originPort, destinationPort }`
    // (vesselShipments.ts:587). There is NO `shipment` wrapper key. Decoding a
    // wrapper against the real payload does NOT throw — the optional simply
    // yields nil — so the screen loads "successfully" and then renders its
    // awaiting state forever, invisibly. Decode off the ROOT; a wrapper is
    // still tolerated so a future revision cannot silently break this again.
    let shipment: ProtestShipment841?

    private enum CodingKeys: String, CodingKey { case shipment }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let wrapped = try? c.decodeIfPresent(ProtestShipment841.self, forKey: .shipment) {
            self.shipment = wrapped
        } else {
            self.shipment = try? ProtestShipment841(from: decoder)   // real shape: fields sit on the root
        }
    }
}

// MARK: - Body

private struct VesselNoteOfProtestBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    let voyageId: String

    @State private var shipment: ProtestShipment841? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    /// Set when the master taps a legal action — states plainly why the write
    /// is refused. Never a fake lodgement, never a queued instrument.
    @State private var actionNotice: String? = nil

    private let pendingAmber = Color(hex: 0xFFC246)

    /// The endorsement register: the four marks an executed protest carries.
    /// Every one of them is drawn unstamped until the register responds.
    private let endorsements = ["MASTER'S DECLARATION",
                                "OATH ADMINISTERED",
                                "REGISTER ENTRY",
                                "EXTENSION RESERVED"]

    private var lane: String? {
        guard let o = shipment?.originPort, !o.isEmpty,
              let d = shipment?.destinationPort, !d.isEmpty else { return nil }
        return "\(o) → \(d)"
    }

    /// The vessel recital slot — REAL when a booking is loaded, a ruled blank
    /// otherwise. Never a stand-in name on a sworn document.
    private var vesselSlot: String? {
        guard let n = shipment?.vesselName, !n.isEmpty else { return nil }
        return n
    }

    /// The voyage recital slot — the real voyage number, else the real lane.
    private var voyageSlot: String? {
        if let v = shipment?.voyageNumber, !v.isEmpty { return "Voy \(v)" }
        if let l = lane { return l }
        if !voyageId.isEmpty { return "Voy \(voyageId)" }
        return nil
    }

    private var masterLine: String {
        // 2026-08-25 — the fallback was a fabricated ship name ("MSC ANNA"), which
        // on a master's protest register is the worst place to invent an identity:
        // the whole instrument is an attestation about ONE named vessel. An
        // operator would have read it as MSC ANNA's protest. Assert no vessel.
        guard let name = vesselSlot, !name.isEmpty else {
            return "— · no vessel selected · noting protest"
        }
        return "\(name) · master's declaration · noting protest"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · NOTE OF PROTEST",
                caption: "MASTER · NOTARY",
                title: "Note of Protest",
                idText: shipment?.bookingNumber,
                subtitle: masterLine
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    skeleton
                } else if let err = loadError, shipment == nil {
                    // Nothing retained to keep — the failure IS the screen.
                    VesselErrorCard(text: err)
                } else {
                    if let err = loadError {
                        // Non-destructive refresh banner. A failed re-read never
                        // blanks a serve that is already on screen; it is flagged
                        // as no-longer-fresh above the retained content.
                        VesselErrorCard(text: "Refresh failed — \(err) The instrument below is the last serve this session returned and is not being updated.")
                    }
                    instrumentSheet
                    timeBarSection
                    causalEventSection
                    endorsementRegister
                    VesselSummaryStrip(label: "Protest noted · extended protest",
                                       value: "— · NOT RESERVED",
                                       valueColor: pendingAmber)
                    VesselRegulatorBand(
                        title: "PROTEST FORMALITY · SINGLE-COUNTRY",
                        reference: "lodging-country",
                        rows: [
                            .init("US", "Notary Public · 46 USC", active: true),
                            .init("CA", "Commissioner of Oaths"),
                            .init("MX", "Corredor Público / Cónsul")
                        ]
                    )
                    ctaPair
                    if let notice = actionNotice {
                        VesselGapNote(text: notice)
                    }
                    VesselGapNote(text: "Vessel and voyage context are verified live and fill the two recital slots they belong in. No protest record is linked to this voyage, so the matter protested, the hour of noting, the register reference and every attestation stay blank on the instrument — an unexecuted document, not a lodged one.")
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - The instrument itself (an unexecuted document sheet)

    private var instrumentSheet: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s4) {
                sheetMasthead
                recitalGrid
                operativeClause
                subscriptionLine
            }
        }
    }

    private var sheetMasthead: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                Text("NOTE OF PROTEST")
                    .font(.system(size: 12, weight: .heavy)).tracking(1.6)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                pendingChip("NOT EXECUTED")
            }
            HStack(spacing: Space.s2) {
                Text("REGISTER REF")
                    .font(.system(size: 8.5, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text("—")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
            }
            Rectangle().fill(palette.borderSoft).frame(height: 1)
        }
    }

    /// The recital slots. A slot with a live value is typed in; a slot without
    /// one is drawn as the ruled blank it is on an unfilled legal form.
    private var recitalGrid: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s4) {
                recitalSlot("VESSEL", vesselSlot)
                recitalSlot("VOYAGE", voyageSlot)
            }
            HStack(alignment: .top, spacing: Space.s4) {
                recitalSlot("PORT OF NOTING", nil)
                recitalSlot("DATE & HOUR NOTED", nil)
            }
            recitalSlot("MATTER PROTESTED", nil)
        }
    }

    private func recitalSlot(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
            if let value, !value.isEmpty {
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            } else {
                ProtestRule841()
                    .stroke(palette.borderSoft, style: StrokeStyle(lineWidth: 1.3, dash: [4, 3]))
                    .frame(height: 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The operative words. This is the settled form of a noting of protest —
    /// a fixed legal recital, stated as the standard, carrying no data.
    private var operativeClause: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("…do hereby note protest against wind, weather, sea and all other causes of loss or damage beyond my control, and against all losses, damages and detriments sustained or hereafter to be discovered, reserving the right to extend this protest at time and place convenient.")
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("form of words · settled maritime practice")
                .font(.system(size: 8.5, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var subscriptionLine: some View {
        HStack(alignment: .bottom, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: 5) {
                ProtestRule841()
                    .stroke(palette.borderSoft, style: StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
                    .frame(height: 12)
                Text("MASTER · signature —")
                    .font(.system(size: 8.5, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            VStack(alignment: .leading, spacing: 5) {
                ProtestRule841()
                    .stroke(palette.borderSoft, style: StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
                    .frame(height: 12)
                Text("SWORN BEFORE ME · —")
                    .font(.system(size: 8.5, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
        }
    }

    // MARK: - Time bar · the period for noting (the urgency of this screen)

    private var timeBarSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "TIME BAR · PERIOD FOR NOTING",
                                right: "ARRIVAL NOT RETURNED")
            VesselGroupCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack {
                        Text("ARRIVAL / DISCOVERY")
                            .font(.system(size: 8.5, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(palette.textTertiary)
                        Spacer(minLength: 8)
                        Text("BAR")
                            .font(.system(size: 8.5, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(pendingAmber)
                    }
                    limitationRuler
                    HStack {
                        Text("— elapsed of the period for noting")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.65)
                        Spacer(minLength: 8)
                        Text("mark unplaced")
                            .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Divider().overlay(palette.borderFaint)
                    Text("Protest is noted as soon as possible after arrival and, where cargo is concerned, before breaking bulk — commonly within twenty-four hours. A late note is open to challenge, which is why the hour of arrival is the one figure this screen will never guess.")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// A limitation ruler: an arrival datum, a bar datum, and the travel mark
    /// that would run between them. With no arrival hour returned the track
    /// carries no fill and the mark is not placed anywhere on it.
    private var limitationRuler: some View {
        ZStack {
            Capsule()
                .fill(palette.tintNeutral)
                .frame(height: 9)
            HStack {
                Rectangle().fill(palette.textTertiary).frame(width: 2, height: 18)
                Spacer(minLength: 0)
                Rectangle().fill(pendingAmber).frame(width: 2.5, height: 18)
            }
        }
        .frame(height: 20)
    }

    // MARK: - Causal event · bridge-log extract (ruled logbook margin)

    private var causalEventSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "CAUSAL EVENT · BRIDGE LOG EXTRACT",
                                right: "NO EVENT LINKED")
            VesselGroupCard {
                HStack(alignment: .top, spacing: Space.s4) {
                    // The logbook margin rule — a page feature, not a reading.
                    Rectangle()
                        .fill(Brand.blue.opacity(0.35))
                        .frame(width: 1.5)
                    VStack(alignment: .leading, spacing: Space.s3) {
                        logSlot("EVENT")
                        logSlot("POSITION")
                        logSlot("LOG TIME (LT)")
                        logSlot("WIND / SEA STATE")
                        logSlot("WITNESSED BY")
                    }
                }
            }
        }
    }

    private func logSlot(_ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(label)
                .font(.system(size: 8.5, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 116, alignment: .leading)
            Text("—")
                .font(.system(size: 11.5, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Endorsement & seal register (empty stamp frames)

    private var endorsementRegister: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "ENDORSEMENT & SEAL REGISTER",
                                right: "NO SEAL AFFIXED")
            HStack(alignment: .top, spacing: Space.s3) {
                stampFrame(endorsements[0])
                stampFrame(endorsements[1])
            }
            HStack(alignment: .top, spacing: Space.s3) {
                stampFrame(endorsements[2])
                stampFrame(endorsements[3])
            }
            Text("An attestation is a physical act by an authorised officer. Nothing on this register is marked until the attesting record exists — no seal is drawn that no officer has impressed.")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stampFrame(_ role: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            VStack(alignment: .leading, spacing: 6) {
                Text(role)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(2).minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("UNSTAMPED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary.opacity(0.85))
            }
            Spacer(minLength: 0)
            Circle()
                .strokeBorder(palette.borderSoft,
                              style: StrokeStyle(lineWidth: 1.4, dash: [3, 3]))
                .frame(width: 26, height: 26)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(palette.bgCardSoft.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderSoft,
                          style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
    }

    // MARK: - Chrome

    private func pendingChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
            .foregroundStyle(pendingAmber)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(pendingAmber.opacity(0.13)))
    }

    // MARK: - CTA pair (both writes are ONLINE_ONLY and both are refused here)

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Lodge protest",
                      action: { blockLodgement() },
                      trailingIcon: "checkmark.seal")
            VesselGhostButton(title: "Reserve ext.", width: 150) { blockReservation() }
        }
    }

    private func blockLodgement() {
        actionNotice = "The protest is not lodged here: no adverse-event record is linked to this voyage, so the instrument has no matter to protest and no hour of noting. A protest is never queued offline — a queued lodgement carries a false hour and can forfeit the very time bar it exists to protect."
    }

    private func blockReservation() {
        actionNotice = "The extended protest cannot be reserved before the protest itself is noted. The reservation extends an instrument on the register; with nothing on the register there is nothing to extend, and this write is never queued offline."
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 250)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 150)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 170)
        }
    }

    // MARK: - Load (REAL: getVesselShipmentDetail)

    private func load() async {
        loading = true; loadError = nil
        guard shipmentId > 0 else { shipment = nil; loading = false; return }
        struct In: Encodable { let id: Int }
        do {
            let detail: ProtestDetail841? = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipmentDetail", input: In(id: shipmentId))
            self.shipment = detail?.shipment
        } catch {
            // `shipment` is deliberately NOT cleared. A failed refresh keeps the
            // last decoded serve on screen, banner-labelled as not fresh, rather
            // than blanking an instrument being prepared against a time bar.
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Private instrument: a blank rule on an unexecuted document

/// A horizontal rule across the middle of its frame — the blank a recital slot
/// or a subscription line is written on. Drawn dashed while unfilled.
private struct ProtestRule841: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return p
    }
}

#Preview("841 · Vessel Note of Protest · Night") {
    VesselNoteOfProtestScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("841 · Vessel Note of Protest · Light") {
    VesselNoteOfProtestScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
