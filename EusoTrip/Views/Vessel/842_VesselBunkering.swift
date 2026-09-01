//
//  842_VesselBunkering.swift
//  EusoTrip — Vessel Operator · Bunkering Operation & BDN (842).
//
//  Verbatim-composition port of "842 Vessel Bunkering & BDN.svg" (Dark →
//  Light). SPEC-AGAINST-CEILING + DELIVERY RECONCILIATION archetype — a fuel
//  RECEIPT surface, not a fuel dashboard. The governing instrument here is the
//  Bunker Delivery Note, and a BDN answers exactly two questions: does the
//  delivered fuel meet the sulphur ceiling the law sets for these waters, and
//  does the quantity on the note agree with the quantity the ship actually
//  received. So the screen carries two instruments and nothing else pretending
//  to be one: a graduated sulphur SPEC AXIS with the MARPOL Annex VI ceilings
//  drawn on it as fixed rules (0.10 %m/m ECA · 0.50 %m/m global), and a
//  four-line QUANTITY RECONCILIATION that ends in a difference. Around them sit
//  the two things that make a bunker receipt legally answerable: the transfer
//  parties (barge → receiving vessel) and the retained MARPOL sample.
//
//  Sibling separation: 843 (Ballast Water) is a per-tank STATE register drawn
//  on a deck plan — a spatial instrument about where water sits and how it was
//  treated. 842 owns no tanks and no plan: it is a transaction between two
//  parties, reckoned on a graduated axis and a reconciliation. 836 (Laytime)
//  is a one-payer money CLOCK; 839 (Marine Services) is an hour GUTTER of
//  booked windows; 833 (Securing) is a per-tier force worksheet. None of the
//  four share a spine with this one, and 842 is deliberately NOT built as a
//  money ledger — no price, no currency, no invoice appears on a BDN screen.
//
//  WIRING (honest):
//    REAL — vesselShipments.getVesselShipmentDetail (vesselShipments.ts,
//        vesselProcedure, input { id: Int }) → { shipment: { id, vesselName,
//        bookingNumber, voyageNumber, … } }. The receiving vessel, its voyage
//        and its booking are live: they name the header, the hero context line
//        and the RECEIVING side of the transfer band.
//    REAL (fixed regulatory reference, not data) — MARPOL Annex VI Reg. 14
//        sets the sulphur ceilings the axis is graduated against: 0.50 %m/m
//        outside an emission control area and 0.10 %m/m inside the North
//        American ECA. Reg. 18 governs the bunker delivery note itself and the
//        representative sample retained aboard. These are the instrument, the
//        way 833 states the CSS Code — they are drawn as RULES on the axis and
//        are never confused with a measured result.
//    STUB · named-gap — vessel.getBunkerOp({callId}); there is no bunkering /
//        BDN / ROB model on disk (670 Bunker Prices and 685 Bunker FSC are
//        PRICING surfaces, not an operation; grep BDN / ROB / bunkering-op =
//        0). It would return { bdnNumber, grade, supplier, bargeName,
//        orderedTonnes, deliveredTonnes, shipFigureTonnes, sulphurPct,
//        flashPointC, sampleSealNumber, sampleSealed:Bool, stemStartedAt,
//        stemCompletedAt }. Until it ships NOTHING is drawn on the spec axis,
//        every reconciliation line reads an em-dash, the sample reads NOT
//        LOGGED and the supplier side of the transfer band stays empty.
//    STUB · named-gap REGULATORY — vessel.confirmBDN({callId,confirm:true})
//        and vessel.flagBunkerQuality({callId,confirm:true}) [gated +
//        confirm:true + audit + test]; each writes the bunker_op row +
//        blockchainAuditTrail vessel.bdn_confirmed and broadcasts
//        WS_CHANNELS.VESSEL_OPS / WS_EVENTS.BDN_CONFIRMED. RBAC vesselProcedure
//        (chief engineer). The CTAs are present and honest: they name the gap
//        rather than firing a hopeful no-op.
//    NOTHING on this screen fabricates a compliance result. The SVG's literal
//        figures (1,850 MT VLSFO · 0.42 %m/m S · ROB 3,420 MT · BDN
//        MSC-ANNA-2614 · sample #3 sealed) exist in this comment only. A
//        rendered sulphur percentage or a rendered MARPOL PASS that no
//        laboratory returned is an environmental-compliance lie with criminal
//        exposure attached to it, so the axis carries its rules and no marker.
//
//  OFFLINE POLICY (doctrine W):
//    READ  · READ_CACHED(15m) — the port-call and vessel context may be served
//            from the 15-minute cache; a stale bunker receipt is still a
//            readable receipt, and the awaiting-states are visibly distinct so
//            a cached payload can never masquerade as a fresh one.
//            HONEST SCOPE OF THAT TIER: what the code actually does today is
//            retain the last decoded serve IN MEMORY for the life of the
//            session and banner-flag a failed refresh above it instead of
//            blanking the screen. There is NO persistent cache layer behind
//            it — Services/EusoTripAPI.swift:415-416 sets
//            .reloadIgnoringLocalAndRemoteCacheData and urlCache = nil — so nothing survives
//            a cold launch and the 15m TTL is a policy declaration, not an
//            enforced one. OPEN item (owning lane: the-oath): a real on-disk
//            read cache with TTL enforcement.
//    WRITE · ONLINE_ONLY(a fuel-receipt attestation must not be queued) —
//            Confirm BDN is the chief engineer signing for delivered quantity
//            and a declared sulphur spec. A queued attestation could be
//            replayed after the barge has sailed, after the retained sample was
//            broken, or against a revised note — signing for fuel you can no
//            longer inspect is the exact failure mode Annex VI Reg. 18 exists
//            to prevent. Flag quality is ONLINE_ONLY for the same reason: a
//            quality protest has a clock on it and must land while the barge is
//            still alongside.
//
//  CHAIN CLOSURE:
//    Emit WS_EVENTS.BDN_CONFIRMED on WS_CHANNELS.VESSEL_OPS. Intended
//    counter-parties: the port-call surface (the stem closes the call) and the
//    compliance surface that holds the MARPOL record (727 Marpol Record Book),
//    which should receive the confirmed BDN as a record-book entry.
//    OPEN counter-party item (owning lane: VESSEL · the-oath): the receiving
//    half does NOT exist. RealtimeService.swift carries ~48 event cases and no
//    vessel:* case at all; Views/Vessel has zero realtime subscribers (the whole
//    app has one, in Views/Dispatch). A confirmed BDN would therefore reach no
//    listener — 727 would not learn of it until its own next read, and no
//    shore-side compliance surface would learn of it ever. Recorded here as an
//    open item rather than papered over with an emit nobody hears.
//
//  COUNTRY (single-country content, never a file fork): US EPA-USCG North
//    American ECA 0.10% ACTIVE · CA Transport Canada ECA 0.10% · MX SEMARNAT
//    ECA 0.10%; MARPOL Annex VI global cap 0.50% shared.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselBunkeringScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0
    var callId: String = ""

    var body: some View {
        Shell(theme: theme) {
            VesselBunkeringBody(shipmentId: shipmentId, callId: callId)
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

// MARK: - Shipment shape (getVesselShipmentDetail)

private struct BunkerShipment842: Decodable {
    let id: Int?
    let vesselName: String?
    let bookingNumber: String?
    let voyageNumber: String?
}
private struct BunkerDetail842: Decodable {
    // FLAT-SHAPE REPAIR (2026-08-17). `vesselShipments.getVesselShipmentDetail`
    // returns a FLAT spread — `return { ...shipment, lifecycleStage, bols,
    // customs, events, demurrage, containers, originPort, destinationPort }`
    // (vesselShipments.ts:587). There is NO `shipment` wrapper key. Decoding a
    // wrapper against the real payload does NOT throw — the optional simply
    // yields nil — so the screen loads "successfully" and then renders its
    // awaiting state forever, invisibly. Decode off the ROOT; a wrapper is
    // still tolerated so a future revision cannot silently break this again.
    let shipment: BunkerShipment842?

    private enum CodingKeys: String, CodingKey { case shipment }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let wrapped = try? c.decodeIfPresent(BunkerShipment842.self, forKey: .shipment) {
            self.shipment = wrapped
        } else {
            self.shipment = try? BunkerShipment842(from: decoder)   // real shape: fields sit on the root
        }
    }
}

// MARK: - Reconciliation line model

/// How a quantity line participates in the reckoning. `nominated` and
/// `measured` are inputs; `difference` is the OUTCOME line and is drawn apart
/// from the inputs so a reader can never mistake an input for a result.
private enum BunkerQtyRole842 {
    case nominated
    case measured
    case difference
}

/// One line of the delivered-quantity reconciliation. The line KINDS are the
/// fixed anatomy of a bunker delivery reckoning (what was ordered, what the
/// note says was delivered, what the ship measured, and the gap between the
/// last two). `tonnes` comes from getBunkerOp and stays nil until it ships —
/// an em-dash quantity, never an assumed one.
private struct BunkerQtyLine842: Identifiable {
    let id = UUID()
    let label: String
    let note: String
    let role: BunkerQtyRole842
    var tonnes: String? = nil
}

// MARK: - Sulphur spec axis (bespoke · ceilings are rules, not readings)

/// The screen's governing instrument. A graduated %m/m sulphur axis from 0.00
/// to 0.60 carrying the two MARPOL Annex VI Reg. 14 ceilings as fixed rules:
/// 0.10 (North American ECA) and 0.50 (global cap). The three regions are the
/// LAW — compliant everywhere, compliant only outside an ECA, and
/// non-compliant — and they are drawn whether or not a test result exists.
///
/// `testedPct` is the ONLY thing on this axis that is data. When it is nil no
/// marker is placed at all: an unmarked axis reads as "no result", whereas a
/// marker parked at zero or at a default would read as a laboratory finding
/// that nobody made.
private struct SulphurCeilingAxis842: View {
    @Environment(\.palette) private var palette
    let testedPct: Double?

    private let axisMax: Double = 0.60
    private let ecaCeiling: Double = 0.10
    private let globalCeiling: Double = 0.50

    private func x(_ value: Double, _ w: CGFloat) -> CGFloat {
        CGFloat(min(max(value / axisMax, 0), 1)) * w
    }

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let ecaX = x(ecaCeiling, w)
            let globalX = x(globalCeiling, w)
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .leading) {
                    // The regulatory regions.
                    HStack(spacing: 0) {
                        Rectangle().fill(palette.tintSuccess)
                            .frame(width: ecaX)
                        Rectangle().fill(Color(hex: 0xFFC246).opacity(0.15))
                            .frame(width: max(globalX - ecaX, 0))
                        Rectangle().fill(palette.tintDanger)
                    }
                    // The ceilings themselves — hard rules on the scale.
                    Rectangle().fill(Brand.success).frame(width: 2)
                        .offset(x: max(ecaX - 1, 0))
                    Rectangle().fill(Brand.danger).frame(width: 2)
                        .offset(x: max(globalX - 1, 0))
                    // The tested value. Absent until a BDN spec is returned.
                    if let tested = testedPct {
                        Capsule()
                            .fill(palette.textPrimary)
                            .frame(width: 3, height: 20)
                            .offset(x: max(x(tested, w) - 1.5, 0))
                    }
                }
                .frame(height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                ZStack(alignment: .topLeading) {
                    Text("0.00")
                        .font(.system(size: 7.5, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                    Text("ECA 0.10")
                        .font(.system(size: 7.5, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Brand.success)
                        .fixedSize()
                        .offset(x: min(max(ecaX - 20, 24), max(w - 100, 24)))
                    Text("GLOBAL 0.50")
                        .font(.system(size: 7.5, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Brand.danger)
                        .fixedSize()
                        .offset(x: min(max(globalX - 30, 0), max(w - 62, 0)))
                }
                .frame(height: 10)
            }
        }
        .frame(height: 44)
    }
}

// MARK: - Body

private struct VesselBunkeringBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    let callId: String

    @State private var shipment: BunkerShipment842? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var attestNote: String? = nil

    /// The anatomy of a bunker delivery reckoning. The lines are fixed — every
    /// BDN reconciliation has exactly these four — while the tonnages arrive
    /// with getBunkerOp and are nil until then.
    private let qtyLines: [BunkerQtyLine842] = [
        BunkerQtyLine842(label: "Ordered",     note: "stem nomination",        role: .nominated),
        BunkerQtyLine842(label: "Delivered",   note: "BDN figure · supplier",  role: .nominated),
        BunkerQtyLine842(label: "Ship's figure", note: "sounded ROB gain",     role: .measured),
        BunkerQtyLine842(label: "Difference",  note: "BDN less ship's figure", role: .difference)
    ]

    private var receivingVessel: String { shipment?.vesselName ?? "—" }

    private var callLine: String {
        if let s = shipment {
            let vessel = s.vesselName ?? "vessel"
            let voy = s.voyageNumber ?? s.bookingNumber ?? callId
            return voy.isEmpty ? "\(vessel) · bunker delivery note"
                               : "\(vessel) · voy \(voy) · bunker delivery note"
        }
        // No booking is resolved, so nothing about this call is known — least of
        // all the supplier. A barge identity is getBunkerOp (STUB) data and is
        // legally answerable on the BDN itself, so it is NOT invented here; the
        // fallback matches the transfer band, which reads supplier "—" ·
        // "not named on a note".
        return "No booking selected · bunker delivery note · supplier not named"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · BUNKERING & BDN",
                caption: "MARPOL VI · BDN",
                title: "Bunker delivery note",
                subtitle: callLine
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
                        VesselErrorCard(text: "Refresh failed — \(err) The reckoning below is the last serve this session returned and is not being updated.")
                    }
                    specHero
                    reconciliationSection
                    transferSection
                    sampleCard
                    VesselSummaryStrip(
                        label: "MARPOL Annex VI Reg. 18 · BDN retained 3 years aboard",
                        value: "attestation pending",
                        valueColor: palette.textTertiary
                    )
                    VesselRegulatorBand(
                        title: "SULPHUR REGIME · SINGLE-COUNTRY",
                        reference: "bunker · country",
                        rows: [
                            .init("US", "EPA-USCG N-Am ECA · 0.10%", active: true),
                            .init("CA", "Transport Canada ECA · 0.10%"),
                            .init("MX", "SEMARNAT ECA · 0.10%")
                        ]
                    )
                    // A refusal is NOT an acknowledgement. VesselToastRow is the
                    // post-mutation success affordance (green checkmark.seal on
                    // tintSuccess) — painting it here would read as a signed BDN
                    // on a MARPOL screen. The honest-gap note is the affordance.
                    if let attestNote { VesselGapNote(text: attestNote) }
                    ctaPair
                    VesselGapNote(text: "Vessel and voyage context are live, and the MARPOL Annex VI ceilings drawn on the axis are the governing ones for this call. No delivery note is linked yet — the tested sulphur content, every quantity on the reconciliation, the supplier and barge, and the retained sample arrive with the bunker operation record. Nothing on this screen is inferred on the device.")
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - Spec hero (the sulphur reading against the MARPOL ceiling)

    private var specHero: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    Text("Delivered grade · sulphur content vs Annex VI")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text("SPEC UNREPORTED")
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Color(hex: 0xFFC246))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color(hex: 0xFFC246).opacity(0.13)))
                }
                // A sulphur figure is a pass/fail against a criminal-liability
                // ceiling. It stays an em-dash and stays NEUTRAL — never green,
                // never red — so the screen cannot imply either verdict.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("—% S")
                        .font(.system(size: 32, weight: .bold, design: .monospaced)).tracking(-0.5)
                        .foregroundStyle(palette.textTertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("grade — · tested %m/m")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("no laboratory result on file")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 6)
                }
                SulphurCeilingAxis842(testedPct: nil)
                Text("Ceilings are MARPOL Annex VI Reg. 14 — 0.10 %m/m inside the North American ECA, 0.50 %m/m outside it. No result is plotted.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Quantity reconciliation (BDN figure vs ship's figure)

    private var reconciliationSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "DELIVERED QUANTITY · RECONCILIATION",
                                right: "AWAITING BDN")
            VesselGroupCard {
                VStack(spacing: 0) {
                    ForEach(Array(qtyLines.enumerated()), id: \.element.id) { idx, line in
                        if line.role == .difference {
                            Rectangle()
                                .fill(palette.borderSoft)
                                .frame(height: 1)
                                .padding(.vertical, Space.s2)
                        } else if idx > 0 {
                            Divider().overlay(palette.borderFaint)
                        }
                        qtyRow(line)
                    }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "scalemass")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("A quantity dispute is raised before the barge disconnects")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text("UNRECONCILED")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(palette.tintNeutral))
            }
        }
    }

    private func qtyRow(_ line: BunkerQtyLine842) -> some View {
        let isOutcome = line.role == .difference
        return HStack(alignment: .center, spacing: Space.s3) {
            // Measured lines carry a solid rule, nominated lines a hollow one:
            // what the ship sounded and what a counter-party asserted must
            // never read alike.
            Group {
                if line.role == .measured {
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Brand.blue)
                } else if isOutcome {
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color(hex: 0xFFC246))
                } else {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(palette.textTertiary,
                                      style: StrokeStyle(lineWidth: 1.4, dash: [2.5, 2.5]))
                }
            }
            .frame(width: 4, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(line.label)
                    .font(.system(size: isOutcome ? 13 : 12, weight: isOutcome ? .heavy : .bold))
                    .foregroundStyle(isOutcome ? palette.textPrimary : palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(line.note)
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 6)
            Text(line.tonnes ?? "— MT")
                .font(.system(size: isOutcome ? 14 : 12, weight: .heavy, design: .monospaced))
                .foregroundStyle(line.tonnes == nil ? palette.textTertiary : palette.textPrimary)
        }
        .padding(.vertical, Space.s3)
    }

    // MARK: - Transfer parties (barge → receiving vessel)

    private var transferSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            // Whether a barge is made fast is getBunkerOp state, not something
            // this screen can assert. The caption states what IS true — no
            // transfer record has been returned — matching the AWAITING BDN
            // caption on the reconciliation header above.
            VesselSectionHeader(label: "TRANSFER · SUPPLIER TO RECEIVING VESSEL",
                                right: "AWAITING TRANSFER RECORD")
            VesselGroupCard {
                HStack(alignment: .center, spacing: Space.s3) {
                    partyBlock(role: "SUPPLIER · BARGE",
                               name: "—",
                               detail: "not named on a note",
                               known: false)
                    VStack(spacing: 4) {
                        Text("— MT")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundStyle(palette.textTertiary)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.textTertiary)
                        Text("grade —")
                            .font(.system(size: 8.5, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .frame(width: 62)
                    partyBlock(role: "RECEIVING VESSEL",
                               name: receivingVessel,
                               detail: shipment == nil ? "no booking selected" : "live booking context",
                               known: shipment != nil)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("Transfer —:— to —:— LT · hoses connected —:—")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
        }
    }

    private func partyBlock(role: String, name: String, detail: String, known: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(role)
                .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(name)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(known ? palette.textPrimary : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(detail)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCardSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(known ? Brand.blue.opacity(0.45) : palette.borderFaint,
                              style: StrokeStyle(lineWidth: 1, dash: known ? [] : [3, 3]))
        )
    }

    // MARK: - Retained MARPOL sample (custody)

    private var sampleCard: some View {
        VesselGroupCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: 8) {
                    Image(systemName: "seal")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                    Text("RETAINED MARPOL SAMPLE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer(minLength: 6)
                    Text("NOT LOGGED")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(palette.tintNeutral))
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("seal —")
                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                    Text("drawn at the receiving manifold")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Text("Annex VI Reg. 18.8.1 requires the representative sample to be sealed, signed by the barge master and the chief engineer, and kept aboard under the vessel's control for twelve months. No seal number has been recorded against this delivery.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - CTA pair (both ONLINE_ONLY · both gap-honest)

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Confirm BDN", action: { flagAttestGap() }, trailingIcon: "checkmark.seal")
            VesselGhostButton(title: "Flag quality", width: 150) { flagQualityGap() }
        }
    }

    /// Signing for fuel is an attestation, and the endpoint that would record
    /// it does not exist. Say so plainly rather than flashing a success state.
    private func flagAttestGap() {
        attestNote = "A BDN cannot be confirmed from this device yet: no delivery note is linked, the tested sulphur content has not been returned, and an attestation of this kind is never queued offline."
    }

    private func flagQualityGap() {
        attestNote = "A quality protest cannot be filed from this device yet: the bunker operation record is not built, and a protest must reach the supplier while the barge is still alongside — it cannot be queued."
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 190)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 200)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 96)
        }
    }

    // MARK: - Load (REAL: getVesselShipmentDetail)

    private func load() async {
        loading = true; loadError = nil
        guard shipmentId > 0 else { shipment = nil; loading = false; return }
        struct In: Encodable { let id: Int }
        do {
            let detail: BunkerDetail842? = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipmentDetail", input: In(id: shipmentId))
            self.shipment = detail?.shipment
        } catch {
            // `shipment` is deliberately NOT cleared. A failed refresh keeps the
            // last decoded serve on screen, banner-labelled as not fresh, rather
            // than blanking a reckoning the engineer may still be reading.
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("842 · Vessel Bunkering & BDN · Night") {
    VesselBunkeringScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("842 · Vessel Bunkering & BDN · Light") {
    VesselBunkeringScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
