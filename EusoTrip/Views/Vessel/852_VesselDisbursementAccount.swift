//
//  852_VesselDisbursementAccount.swift
//  EusoTrip — Vessel Operator · Port Disbursement Account (852).
//
//  Composition port of "852 Vessel Port Disbursement Account.svg" (Light +
//  Dark). This is the VESSEL band's only MONEY screen, so it is built against
//  the golden money anchor (02 Shipper · 227 Settlement Detail) rather than
//  against its vessel neighbours.
//
//  ARCHETYPE — MONEY · VARIANCE-AGAINST-AN-ESTIMATE.
//  A port disbursement account is not an invoice and not a settlement. It is
//  the ship agent's own account to the principal, rendered twice: a PRO-FORMA
//  (PDA) quoted before the call, and a FINAL (FDA) rendered after it. The
//  operator who opens this screen has already accepted the gross — they funded
//  it. The single question they open it to answer is: WHERE DID THE FINAL
//  DEPART FROM THE ESTIMATE, AND BY HOW MUCH. So the variance is the H1 and
//  the gross is context beneath it.
//
//  That ordering is the lesson 010 was failed for: it made the carrier's gross
//  the H1 and buried the disputed delta in a 13px secondary line, which is the
//  opposite of what the reader came for. It was also failed for drawing a
//  two-segment proportion bar against three dot colours; here the bar segments
//  and the ledger swatches are generated from ONE array of cost heads
//  (`DAHead852.all`), so the two counts cannot drift apart by construction.
//
//  SIBLING SEPARATION (this band, checked screen by screen):
//    836 Laytime & SOF — a one-payer money CLOCK: time on demurrage accruing
//        against a laytime allowance. One rate, one running total, no estimate.
//    842 Bunkering & BDN — deliberately NOT money: a spec axis against a
//        MARPOL ceiling plus a delivered-quantity reconciliation. No currency
//        appears on a bunker delivery note at all.
//    839 Marine Services — an hour GUTTER of booked service windows; it books
//        the tug and the pilot, it does not price them.
//    684 / 700 / 674 — settlement, freight-bill audit and cost breakdown for a
//        SHIPMENT between shipper and carrier. A different money event with a
//        different counter-party (see the createVesselSettlement note below).
//    852 owns none of those spines: one payer (the principal), one payee (the
//        agent), and a two-column ledger whose whole point is the third column.
//
//  WIRING (verified first-hand against frontend/server this fire — every line
//  number below was read off the live file, not inherited from the SVG):
//    REAL — vesselShipments.getVesselShipmentDetail EXISTS
//        routers/vesselShipments.ts:561 (vesselProcedure, input { id: Int }).
//        Returns a FLAT spread — `{ ...shipment, lifecycleStage, bols, customs,
//        events, demurrage, containers, originPort, destinationPort }`
//        (vesselShipments.ts:587) — there is NO `shipment` wrapper key. Names
//        the vessel, the voyage and the booking on the header and the hero.
//    REAL — vesselShipments.getPortDetails EXISTS
//        routers/vesselShipments.ts:2313 (vesselProcedure, input
//        { portId: Int }) -> `{ ...port, berths }`. Names the port of call and
//        its berths — the berth-hire head is charged against a berth in that
//        list, so this is the account's place identity.
//    REAL — vesselShipments.getPortConditions EXISTS
//        routers/vesselShipments.ts:3276 (vesselProcedure, input
//        { portId: String } — a STRING on this proc, unlike getPortDetails,
//        which takes an Int. They genuinely differ on the same router.
//        Returns `pilotageHold` derived by the local helper `pilotageHoldFrom`
//        (vesselShipments.ts:242, surfaced at :3299/:3345) —
//        { visibilityHold, pilotageMinimumNm, windGustKt }. This is a genuine
//        PDA signal, not decoration: a visibility hold is the single most
//        common cause of pilot standby and tug overtime, which is where the
//        pilotage and towage heads overrun their pro-forma. It is
//        enterprise-gated and fail-soft — `available:false` with a named
//        `reason` on the free tier — and this screen renders that refusal
//        verbatim rather than papering it with a green state.
//        (The SVG `<desc>` and the catalog sketch cited "pilotageHoldFrom:211"
//        and "getVesselShipmentDetail:523". Both were stale — the helper is at
//        242 and the procedure at 561 — and both are corrected here.)
//
//    STUB · named-gap — THE DISBURSEMENT LEDGER ITSELF DOES NOT EXIST.
//        Grepped repo-wide this fire: `disbursement|PDA` returns ONE hit and it
//        is "WHO/PDA recognized provider" in industryVerticals.ts:424, a
//        pharmaceutical training certification. There is no disbursement
//        account model, no cost-head table, no funds-on-account balance.
//        Proposed shape:
//          vesselShipments.getDisbursementAccount({ callId: string })
//            -> { callId, unlocode, agentName, currency: 'USD'|'CAD'|'MXN',
//                 status: 'PDA_ISSUED'|'FDA_DRAFT'|'FDA_APPROVED'|'DISPUTED',
//                 heads: [{ head: DAHead, proformaMinor: number,
//                           finalMinor: number|null, varianceMinor: number|null,
//                           supportingDocId: string|null }],
//                 totals: { proformaMinor, finalMinor, varianceMinor },
//                 funds: { onAccountMinor, clearedMinor, balanceMinor } }
//        Amounts in MINOR UNITS (integers) with an explicit currency — a
//        floating-point port account is a rounding lawsuit.
//
//    STUB · named-gap MONEY + IRREVERSIBLE — the two controls.
//          vesselShipments.approveFDA({ callId, expectedTotalMinor, currency,
//                                       idempotencyKey, confirm: true })
//          vesselShipments.disputeDisbursementHead({ callId, head, reason,
//                                       claimedMinor, idempotencyKey })
//        approveFDA releases the principal's funds to the agent. It must be
//        gated + confirm:true + audited + tested + evaluated, must carry an
//        idempotency key and an `expectedTotalMinor` the server re-checks
//        (approving a figure the operator never saw is the classic race), and
//        must write the disbursement_account row + a blockchainAuditTrail
//        `vessel.fda_approved` entry and broadcast WS_CHANNELS.VESSEL_OPS /
//        WS_EVENTS.FDA_APPROVED. RBAC vesselProcedure (operator / accounts).
//        NEITHER EXISTS TODAY, so BOTH CONTROLS ARE `.disabled(true)` and the
//        notice beneath them names the missing procedures. They are real
//        Buttons in a disabled state — not dimmed-but-tappable, and not a Text
//        dressed as a capsule.
//
//    EXPLICITLY NOT WIRED — vesselShipments.createVesselSettlement EXISTS
//        routers/vesselShipments.ts:2170, and it is the wrong money event.
//        That procedure settles a SHIPMENT between shipper and carrier. A port
//        disbursement account settles a PORT CALL between a principal and its
//        ship agent: different parties, different instrument, different ledger,
//        different audit trail. Binding this screen's Approve button to it
//        because it is the nearest available mutation would move real money on
//        the wrong contract. Left disconnected on purpose and recorded here.
//
//  NO FIGURE ON THIS SCREEN IS INVENTED. The SVG's literal amounts
//  ($182,050 FDA · $175,800 PDA · +$6,250 variance · $200,000 on account)
//  exist in this comment and nowhere else. A rendered variance that no agent
//  submitted, sitting above a button that releases funds, is a financial lie
//  with the operator's signature on it. Until getDisbursementAccount ships,
//  every amount is an em-dash, the variance H1 is neutral (never green, never
//  amber — either colour is a verdict), and the composition bar carries its
//  cost heads as an empty scale with no proportions plotted, exactly as 842
//  carries its MARPOL ceilings with no marker.
//
//  OFFLINE POLICY (doctrine §W):
//    READ  · ONLINE_ONLY(this read IS money). Every other read surface in this
//            band may be served stale, but a disbursement account is the
//            figure the operator is about to release funds against. A cached
//            balance is how you approve a superseded FDA or double-fund a call
//            the agent already drew down. There is no TTL at which that is
//            acceptable, so this screen declines a cache tier rather than
//            declaring one it would not honour. The refusal is stated in the
//            UI, not just here.
//    WRITE · ONLINE_ONLY(money movement is never queued). A queued approval
//            replays against whatever the account says at reconnect, which may
//            be a different total than the one the operator read. Money
//            mutations are also the one class EusoTripAPIError
//            .queuedForOfflineReplay is documented never to be thrown for
//            (Services/EusoTripAPI.swift:26-42) — so the policy and the
//            transport already agree.
//    The port-call and port context reads are themselves cheap and live; no
//    part of this screen retains a serve across a cold launch.
//
//  CHAIN CLOSURE: an approved FDA should emit WS_EVENTS.FDA_APPROVED on
//    WS_CHANNELS.VESSEL_OPS to the port-call surface (851) and to the operator
//    account/wallet surface (656). OPEN counter-party item (owning lane:
//    VESSEL · the-oath): RealtimeService.swift carries no vessel:* case and
//    Views/Vessel has zero realtime subscribers, so the emit would reach no
//    listener today. Recorded, not papered over.
//
//  COUNTRY (single-country content, never a file fork) — CURRENCY IS THE
//    CONTENT HERE: US USD · Port of Long Beach tariff + CBP (active) ·
//    CA CAD · Vancouver Fraser Port Authority · MX MXN · API Manzanillo. A
//    port account is rendered in the currency of the port, and the head names
//    themselves differ by regime (US wharfage vs CA berthage vs MX ANP).
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Cost heads (the fixed anatomy of a port disbursement account)

/// The heads a ship agent renders a port account under. These are the
/// ANATOMY of the instrument — every PDA in every port carries them — so they
/// are drawn whether or not an account has been returned, the way 842 draws
/// the MARPOL ceilings before any sample is tested.
///
/// This one array feeds BOTH the proportion bar's segments AND the ledger's
/// swatches. That is deliberate: 010 shipped a two-segment bar against three
/// dot colours and lost the axis for it. Here the counts are the same array's
/// count and cannot disagree.
private struct DAHead852: Identifiable {
    let id: String
    let name: String
    let note: String
    let ink: Color

    static let all: [DAHead852] = [
        .init(id: "pilotage", name: "Pilotage · inward + outward",
              note: "compulsory · standby billed by the hour", ink: Brand.blue),
        .init(id: "towage", name: "Towage · tugs",
              note: "per tug, per movement · overtime after hours", ink: Brand.magenta),
        .init(id: "berth", name: "Berth hire & wharfage",
              note: "per metre LOA per day alongside", ink: Brand.vessel),
        .init(id: "dues", name: "Port & tonnage dues",
              note: "on gross tonnage · set by tariff", ink: Brand.success),
        .init(id: "services", name: "Line handling · fresh water · garbage",
              note: "boatmen, potable water, MARPOL Annex V landing", ink: Brand.warning),
        .init(id: "agency", name: "Agency fee",
              note: "the agent's own remuneration", ink: Brand.neutral)
    ]
}

/// One rendered ledger line. `proforma`, `final` and `variance` are all
/// optional and all nil until getDisbursementAccount ships — an em-dash
/// amount, never an assumed one.
private struct DALine852: Identifiable {
    let id: String
    let head: DAHead852
    var proforma: String? = nil
    var finalAmount: String? = nil
    var variance: String? = nil
    /// Share of the TOTAL VARIANCE this head is responsible for, 0…1.
    /// nil while no account is linked, which is why the bar plots nothing.
    var varianceShare: Double? = nil
}

// MARK: - Variance composition bar (the screen's proportion instrument)

/// WHERE THE OVERRUN CAME FROM. The 227 anchor plots a gross composition
/// because a settlement's question is "what am I being paid for". A port
/// account's question is "what moved", so this plots the composition of the
/// VARIANCE, not of the gross — the same organ, pointed at the figure this
/// screen exists for.
///
/// Segment count is `heads.count` by construction. When no share has been
/// returned the bar renders as the empty scale it is: one hollow track per
/// head, each in that head's ink at low opacity, separated by hairlines, with
/// a caption saying plainly that nothing is plotted. A bar filled with equal
/// thirds would read as a finding.
private struct VarianceCompositionBar852: View {
    @Environment(\.palette) private var palette
    let lines: [DALine852]

    private var plotted: Bool { lines.contains { $0.varianceShare != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = max(geo.size.width, 1)
                HStack(spacing: plotted ? 0 : 2) {
                    ForEach(lines) { line in
                        if let share = line.varianceShare {
                            Rectangle()
                                .fill(line.head.ink)
                                .frame(width: max(w * CGFloat(share), 1))
                        } else {
                            // Empty scale: the head is present, its proportion is not.
                            Rectangle()
                                .fill(line.head.ink.opacity(0.16))
                                .overlay(
                                    Rectangle().strokeBorder(
                                        line.head.ink.opacity(0.40),
                                        style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5])
                                    )
                                )
                                .frame(width: max((w - CGFloat(2 * (lines.count - 1))) / CGFloat(lines.count), 1))
                        }
                    }
                }
                .frame(width: w, alignment: .leading)
            }
            .frame(height: 16)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(plotted
                 ? "Share of the total variance, by head."
                 : "\(lines.count) heads on the scale · no proportions plotted — the agent's account has not been returned.")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Screen

struct VesselDisbursementAccountScreen: View {
    let theme: Theme.Palette
    /// Port call context. Zero is an honest "nothing selected" — the screen
    /// says so rather than reading a fabricated call.
    var shipmentId: Int = 0
    var portId: Int = 0
    var callId: String = ""

    var body: some View {
        Shell(theme: theme) {
            VesselDisbursementAccountBody(shipmentId: shipmentId, portId: portId, callId: callId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Wire shapes

/// getVesselShipmentDetail returns a FLAT spread (vesselShipments.ts:587).
/// Decoding a `{ shipment: … }` wrapper against it does not throw — the
/// optional just yields nil — so the screen would "load" and then render its
/// awaiting state forever, invisibly. Decode off the ROOT; tolerate a wrapper
/// so a future server revision cannot silently break this again.
private struct DAShipment852: Decodable {
    let id: Int?
    let vesselName: String?
    let bookingNumber: String?
    let voyageNumber: String?
}

private struct DADetail852: Decodable {
    let shipment: DAShipment852?
    private enum CodingKeys: String, CodingKey { case shipment }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let wrapped = try? c.decodeIfPresent(DAShipment852.self, forKey: .shipment) {
            self.shipment = wrapped
        } else {
            self.shipment = try? DAShipment852(from: decoder)
        }
    }
}

/// getPortDetails -> `{ ...port, berths }` (vesselShipments.ts:2313).
private struct DAPort852: Decodable {
    let name: String?
    let unlocode: String?
    let city: String?
    let stateProvince: String?
    let country: String?
}

/// getPortConditions (vesselShipments.ts:3276). Enterprise-gated and
/// fail-soft: `available:false` + a named `reason` is the free-tier answer and
/// is rendered verbatim.
private struct DAPilotageHold852: Decodable {
    let visibilityHold: Bool?
    let pilotageMinimumNm: Double?
    let windGustKt: Double?
}
private struct DAPortConditions852: Decodable {
    let available: Bool?
    let reason: String?
    let pilotageHold: DAPilotageHold852?
}

// MARK: - Body

private struct VesselDisbursementAccountBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    let portId: Int
    let callId: String

    @State private var shipment: DAShipment852? = nil
    @State private var port: DAPort852? = nil
    @State private var conditions: DAPortConditions852? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionNote: String? = nil

    /// The ledger. Amounts stay nil until getDisbursementAccount ships.
    private var lines: [DALine852] {
        DAHead852.all.map { DALine852(id: $0.id, head: $0) }
    }

    private var portLabel: String {
        if let p = port {
            let code = p.unlocode ?? ""
            let name = p.name ?? p.city ?? "port"
            return code.isEmpty ? name : "\(name) \(code)"
        }
        return "no port of call resolved"
    }

    private var subtitleLine: String {
        if let s = shipment {
            let vessel = s.vesselName ?? "vessel"
            let voy = s.voyageNumber ?? s.bookingNumber ?? callId
            return voy.isEmpty ? "\(vessel) · \(portLabel)" : "\(vessel) · voy \(voy) · \(portLabel)"
        }
        return "No port call selected · pro-forma against final · agent not named"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · PORT DISBURSEMENT ACCOUNT",
                caption: "PDA → FDA",
                title: "Port disbursement",
                subtitle: subtitleLine
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    skeleton
                } else if let err = loadError, shipment == nil, port == nil {
                    VesselErrorCard(text: err)
                } else {
                    if let err = loadError {
                        VesselErrorCard(text: "Refresh failed — \(err) Nothing below is being updated. A port account is money: do not act on this view until it reloads.")
                    }
                    onlineOnlyRow
                    varianceHero
                    ledgerSection
                    fundsStrip
                    pilotageSection
                    VesselRegulatorBand(
                        title: "SETTLEMENT CURRENCY · SINGLE-COUNTRY",
                        reference: "port · currency",
                        rows: [
                            .init("US", "USD · Long Beach tariff + CBP", active: true),
                            .init("CA", "CAD · Vancouver Fraser Port Authority"),
                            .init("MX", "MXN · API Manzanillo")
                        ]
                    )
                    if let actionNote { VesselGapNote(text: actionNote) }
                    ctaPair
                    VesselGapNote(text: "Vessel, voyage, port call, and pilotage-hold context are available. The disbursement account has not been provided, so pro forma, final, variance, and funds-balance values remain unknown. Approval and dispute controls stay disabled until an account record is connected.")
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - Offline posture, stated in the UI

    private var onlineOnlyRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Brand.blue)
            Text("ONLINE ONLY · a port account is never served from cache and an approval is never queued")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Brand.blue.opacity(0.08)))
    }

    // MARK: - Hero (H1 is the variance — the figure the screen exists for)

    private var varianceHero: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    Text("Final account against the agent's pro-forma")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text("ACCOUNT NOT LINKED")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(palette.tintNeutral))
                }

                // THE H1. Not the gross. A variance is a signed number and a
                // signed number is a verdict, so while it is unknown it stays
                // NEUTRAL — an amber figure would read as an overrun that
                // nobody reported and a green one as a saving.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("— USD")
                        .font(.system(size: 32, weight: .bold, design: .monospaced)).tracking(-0.5)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("variance vs pro-forma")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("the figure this account is opened to answer")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 6)
                }

                // The two gross figures sit UNDER the variance, as context.
                HStack(spacing: Space.s3) {
                    grossBlock(label: "PRO-FORMA · PDA", value: "—", note: "quoted before the call")
                    grossBlock(label: "FINAL · FDA", value: "—", note: "rendered after the call")
                }

                VarianceCompositionBar852(lines: lines)
            }
        }
    }

    private func grossBlock(label: String, value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(value)
                .font(.system(size: 15, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
            Text(note)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
    }

    // MARK: - Ledger (per-head pro-forma → final → variance) + TOTAL band

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "COST HEADS · PRO-FORMA vs FINAL",
                                right: "\(DAHead852.all.count) HEADS · AWAITING ACCOUNT")
            VesselGroupCard {
                VStack(spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { idx, line in
                        if idx > 0 { Divider().overlay(palette.borderFaint) }
                        headRow(line)
                    }
                    // The TOTAL band — drawn apart from the heads by a solid
                    // rule so a total can never be mistaken for a line.
                    Rectangle().fill(palette.borderSoft)
                        .frame(height: 1)
                        .padding(.vertical, Space.s3)
                    totalRow("TOTAL · PRO-FORMA", "—", emphasis: false)
                    totalRow("TOTAL · FINAL", "—", emphasis: false)
                    totalRow("TOTAL · VARIANCE", "—", emphasis: true)
                }
            }
        }
    }

    private func headRow(_ line: DALine852) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            // The swatch IS the bar segment's ink. One array, one colour set.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(line.head.ink.opacity(line.varianceShare == nil ? 0.45 : 1.0))
                .frame(width: 4, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(line.head.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(line.head.note)
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text(line.finalAmount ?? "—")
                    .font(.system(size: 12.5, weight: .heavy, design: .monospaced))
                    .foregroundStyle(line.finalAmount == nil ? palette.textTertiary : palette.textPrimary)
                Text(line.variance.map { "Δ \($0)" } ?? "Δ —")
                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            .frame(minWidth: 74, alignment: .trailing)
        }
        .padding(.vertical, Space.s3)
    }

    private func totalRow(_ label: String, _ value: String, emphasis: Bool) -> some View {
        HStack {
            Text(label)
                .font(.system(size: emphasis ? 10 : 9.5, weight: .heavy)).tracking(0.5)
                .foregroundStyle(emphasis ? palette.textPrimary : palette.textTertiary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: emphasis ? 16 : 12, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.vertical, emphasis ? Space.s2 : 3)
    }

    // MARK: - Funds on account

    private var fundsStrip: some View {
        VesselSummaryStrip(
            label: "Funds on account · cleared — · balance —",
            value: "no balance returned",
            valueColor: palette.textTertiary
        )
    }

    // MARK: - Pilotage hold (REAL · getPortConditions → pilotageHoldFrom:242)

    private var pilotageSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "PILOTAGE CONDITIONS · VARIANCE DRIVER",
                                right: conditions?.available == true ? "LIVE MARINE" : "NO MARINE READING")
            VesselGroupCard {
                VStack(alignment: .leading, spacing: Space.s2) {
                    if conditions?.available == true, let hold = conditions?.pilotageHold {
                        HStack(spacing: Space.s3) {
                            Image(systemName: hold.visibilityHold == true ? "eye.trianglebadge.exclamationmark" : "eye")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(hold.visibilityHold == true ? Brand.warning : palette.textSecondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(hold.visibilityHold == nil
                                     ? "Visibility layer not observed"
                                     : (hold.visibilityHold == true
                                        ? "Pilotage hold — channel visibility at or under the minimum"
                                        : "No pilotage hold on visibility"))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(palette.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(pilotageDetail(hold))
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(palette.textTertiary)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            Spacer(minLength: 0)
                        }
                    } else {
                        HStack(spacing: Space.s3) {
                            Image(systemName: "eye.slash")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(palette.textTertiary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("No marine reading for this port")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(palette.textTertiary)
                                Text(conditions?.reason ?? "port conditions not requested")
                                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(palette.textTertiary)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    Text("A visibility hold is what turns a quoted pilotage and towage line into an overrun — pilots stand by and tugs run into overtime while the channel is shut. It is shown here as context for the two heads above it and is never used to compute an amount.")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func pilotageDetail(_ hold: DAPilotageHold852) -> String {
        var parts: [String] = []
        if let min = hold.pilotageMinimumNm { parts.append(String(format: "minimum %.1f nm", min)) }
        if let gust = hold.windGustKt { parts.append(String(format: "gust %.0f kt", gust)) } else { parts.append("gust not observed") }
        return parts.joined(separator: " · ")
    }

    // MARK: - CTA pair (both genuinely disabled · both ONLINE_ONLY when built)

    /// AXIS B. Neither procedure exists, so neither control is live. These are
    /// real Buttons carrying `.disabled(true)` — the system reports them
    /// disabled to VoiceOver and they cannot be tapped. They are not dimmed
    /// and left tappable, they do not mutate local @State to imitate a write,
    /// and they are not Text views dressed as capsules.
    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                CTAButton(title: "Approve FDA", trailingIcon: "lock.fill")
                    .disabled(true)
                    .opacity(0.5)
                    .accessibilityHint("Unavailable until a disbursement account is connected")
                VesselGhostButton(title: "Dispute a head", width: 150)
                    .disabled(true)
                    .opacity(0.5)
                    .accessibilityHint("Unavailable until a disbursement account is connected")
            }
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.lock")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Brand.warning)
                Text("Disbursement approval and line-item dispute are unavailable until an account record is connected.")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 210)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 260)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 96)
        }
    }

    // MARK: - Load (REAL: getVesselShipmentDetail · getPortDetails · getPortConditions)

    private func load() async {
        loading = true; loadError = nil

        if shipmentId > 0 {
            struct In: Encodable { let id: Int }
            do {
                let detail: DADetail852? = try await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselShipmentDetail", input: In(id: shipmentId))
                self.shipment = detail?.shipment
            } catch {
                loadError = error.eusoUserCopy
            }
        } else {
            shipment = nil
        }

        if portId > 0 {
            // getPortDetails takes an Int portId; getPortConditions takes a
            // String on the same router. Verified against
            // vesselShipments.ts:2313 and :3276 — they genuinely differ, and
            // sending the wrong scalar is an input-validation throw.
            struct PortIn: Encodable { let portId: Int }
            struct CondIn: Encodable { let portId: String }
            do {
                self.port = try await EusoTripAPI.shared.query(
                    "vesselShipments.getPortDetails", input: PortIn(portId: portId))
            } catch {
                if loadError == nil {
                    loadError = error.eusoUserCopy
                }
            }
            do {
                self.conditions = try await EusoTripAPI.shared.query(
                    "vesselShipments.getPortConditions", input: CondIn(portId: String(portId)))
            } catch {
                // Fail-soft by design on the server; a client-side failure is
                // recorded on the section, not promoted to a screen error.
                self.conditions = nil
            }
        } else {
            port = nil
            conditions = nil
        }

        loading = false
    }
}

#Preview("852 · Vessel Port Disbursement Account · Night") {
    VesselDisbursementAccountScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("852 · Vessel Port Disbursement Account · Light") {
    VesselDisbursementAccountScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
