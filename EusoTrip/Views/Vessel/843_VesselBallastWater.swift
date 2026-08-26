//
//  843_VesselBallastWater.swift
//  EusoTrip — Vessel Operator · Ballast Water Management & D-2 record (843).
//
//  Verbatim-composition port of "843 Vessel Ballast Water Management.svg"
//  (Dark → Light). DECK-PLAN TANK REGISTER + DISCHARGE-AUTHORISATION GATE
//  archetype. Ballast is the one thing aboard that is simultaneously a
//  STABILITY question and an ENVIRONMENTAL one, so this screen carries two
//  instruments and no summary: a top-down HULL PLAN on which every wing tank is
//  drawn in its true position — port and starboard of the centreline, forward
//  to aft — each tank a bottom-anchored FILL COLUMN carrying its own treatment
//  state; and beneath it a three-condition DISCHARGE GATE, because under the
//  IMO BWM Convention discharge is not a status you report, it is a permission
//  you either hold or do not hold.
//
//  On the fill columns: a vertical fill register against a limit line is a
//  deliberately rare device (used once elsewhere platform-wide, Shipper 299).
//  It is native here — a ballast tank IS a column of water — so it is built
//  properly rather than degraded into rows. It is drawn WITHOUT a limit rule:
//  the D-2 standard is a concentration ceiling on what is discharged, not a
//  fill ceiling on what is held, and painting a horizontal rule across the
//  tanks would assert a relationship the regulation does not define. The
//  ceiling lives where it belongs, on the gate.
//
//  Sibling separation: 842 (Bunkering & BDN) is a two-party TRANSACTION —
//  a graduated sulphur spec axis and a quantity reconciliation, no tanks and no
//  plan. 843 owns no counter-party at all: it is the ship's own state, drawn
//  spatially. 839 (Marine Services) is an hour gutter of booked windows, 836
//  (Laytime) a one-payer money clock, 833 (Securing) a per-tier force
//  worksheet. No spine is shared.
//
//  WIRING (honest):
//    REAL — vesselShipments.getVesselShipmentDetail (vesselShipments.ts,
//        vesselProcedure, input { id: Int }) → { shipment: { id, vesselName,
//        voyageNumber, bookingNumber, … } }. The vessel and its inbound voyage
//        are live and drive the header and the hero context line.
//    REAL (fixed regulatory reference, not data) — the IMO BWM Convention
//        regulation D-2 discharge standard: less than 10 viable organisms per
//        cubic metre at or above 50 µm in minimum dimension. US enforcement is
//        USCG 33 CFR 151.2025. These are the governing standard and are stated
//        as such, the way 833 states the CSS Code — the ceiling is printed, the
//        reading against it is not invented.
//    STUB · named-gap — vessel.getBallastOps({voyageId}); there is no ballast /
//        BWM / BWMS model on disk (grep ballast / BWM / BWMS = 0 on disk and 0
//        in the live router tree). It would return { organismsPerM3,
//        organismsReadingAt, troMgL, robM3, salinityPsu, bwmsMode,
//        bwmsOperational:Bool, exchangeCompletedAt, lastUptakeAt,
//        lastUptakeM3, tanks:[{ bay, side, fillFrac, state }] }. Until it ships
//        every tank column renders EMPTY with a dashed rim and an em-dash
//        level, every treatment state reads NO STATE, the organism figure and
//        the TRO figure are em-dashes, and all three gate conditions read
//        UNVERIFIED.
//    DEGRADED READ (per the source spec) — when BWMS telemetry is silent the
//        organism count must read as a stale or absent sensor, never as a
//        fabricated count. That rule is honoured structurally here: the count
//        has exactly two renderings, a returned value or an em-dash.
//    STUB · named-gap REGULATORY — vessel.recordBallastDischarge({voyageId,
//        confirm:true}) and vessel.logBallastUptake({voyageId,confirm:true})
//        [gated + confirm:true + audit + test]; each writes the ballast_op row
//        + blockchainAuditTrail vessel.ballast_recorded and broadcasts
//        WS_CHANNELS.VESSEL_OPS / WS_EVENTS.BALLAST_RECORDED. RBAC
//        vesselProcedure (chief officer).
//    NOTHING on this screen fabricates an environmental result. The SVG's
//        literal figures (< 10 /m³ · TRO 0.18 mg/L · ROB 8,400 m³ · uptake
//        06:10 of 4,200 m³ · salinity 33 PSU · per-tank treated/exchanging/
//        untreated states) exist in this comment only. A rendered D-2 COMPLIANT
//        chip that no BWMS reported is an environmental-compliance lie a port
//        state control officer would act on, so the gate stays closed and the
//        plan stays unpainted.
//
//  OFFLINE POLICY (doctrine W):
//    READ  · READ_CACHED(15m) — voyage and arrival context may be served from
//            the 15-minute cache; a stale ballast picture is still a readable
//            picture, and every awaiting-state is visibly distinct so a cached
//            payload can never masquerade as a fresh one.
//            HONEST SCOPE OF THAT TIER: what the code actually does today is
//            retain the last decoded serve IN MEMORY for the life of the
//            session and banner-flag a failed refresh above it instead of
//            blanking the screen. There is NO persistent cache layer behind
//            it — Services/EusoTripAPI.swift:415-416 sets
//            .reloadIgnoringLocalAndRemoteCacheData and urlCache = nil — so
//            nothing survives a cold launch and the 15m TTL is a policy
//            declaration, not an enforced one. OPEN item (owning lane:
//            the-oath): a real on-disk read cache with TTL enforcement.
//    WRITE · ONLINE_ONLY(a discharge authorisation must reflect live treatment
//            state) — Record discharge asserts that treated water met D-2 at
//            the moment it left the ship. Queued and replayed later it could
//            authorise a discharge against a treatment state that has since
//            changed, or record one that never lawfully occurred. Log uptake is
//            ONLINE_ONLY on the same reasoning: an uptake entry fixes the
//            source water and the position that the later discharge is judged
//            against.
//
//  CHAIN CLOSURE:
//    Emit WS_EVENTS.BALLAST_RECORDED on WS_CHANNELS.VESSEL_OPS. Intended
//    counter-parties: the compliance surface holding the MARPOL / environmental
//    record (727 Marpol Record Book), which should receive the ballast record
//    book entry, and the port-state-control surface (678), which is where an
//    arrival inspection would read it.
//    OPEN counter-party item (owning lane: VESSEL · the-oath): the receiving
//    half does NOT exist. RealtimeService.swift carries ~48 event cases and no
//    vessel:* case; Views/Vessel has zero realtime subscribers (the entire app
//    has one, in Views/Dispatch). A recorded discharge would land on no
//    listener — 727 and 678 would not learn of it until their own next read.
//    Named here as an open item rather than papered over with an emit that
//    nobody hears.
//
//  COUNTRY (single-country content, never a file fork): US USCG BWM 33 CFR
//    151.2025 ACTIVE · CA Transport Canada Ballast Water Regs 2021 · MX SEMAR /
//    CONAPESCA inspection; IMO BWM Convention D-2 shared.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselBallastWaterScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0
    var voyageId: String = ""

    var body: some View {
        Shell(theme: theme) {
            VesselBallastWaterBody(shipmentId: shipmentId, voyageId: voyageId)
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

// MARK: - Shipment shape (getVesselShipmentDetail)

private struct BallastShipment843: Decodable {
    let id: Int?
    let vesselName: String?
    let voyageNumber: String?
    let bookingNumber: String?
}
private struct BallastDetail843: Decodable {
    // FLAT-SHAPE REPAIR (2026-08-17). `vesselShipments.getVesselShipmentDetail`
    // returns a FLAT spread — `return { ...shipment, lifecycleStage, bols,
    // customs, events, demurrage, containers, originPort, destinationPort }`
    // (vesselShipments.ts:587). There is NO `shipment` wrapper key. Decoding a
    // wrapper against the real payload does NOT throw — the optional simply
    // yields nil — so the screen loads "successfully" and then renders its
    // awaiting state forever, invisibly. Decode off the ROOT; a wrapper is
    // still tolerated so a future revision cannot silently break this again.
    let shipment: BallastShipment843?

    private enum CodingKeys: String, CodingKey { case shipment }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let wrapped = try? c.decodeIfPresent(BallastShipment843.self, forKey: .shipment) {
            self.shipment = wrapped
        } else {
            self.shipment = try? BallastShipment843(from: decoder)   // real shape: fields sit on the root
        }
    }
}

// MARK: - Tank state model

/// The treatment state of one ballast tank. `unknown` is a first-class member,
/// not a fallback: a tank whose state has not been reported must be legible as
/// unreported, because "untreated" and "unreported" carry different legal
/// consequences and must never collapse into each other.
private enum BallastState843 {
    case treated
    case exchanged
    case untreated
    case unknown
}

/// One wing tank on the deck plan. Bay number and side are the ship's fixed
/// geometry. `fillFrac` and `state` come from getBallastOps and stay nil /
/// unknown until that record exists.
private struct BallastTank843: Identifiable {
    let id = UUID()
    let bay: Int
    let side: String          // "P" | "S"
    var fillFrac: Double? = nil
    var state: BallastState843 = .unknown

    var code: String { "\(bay)\(side)" }
}

/// A port/starboard pair sharing one bay number — the row unit of the plan.
private struct BallastBayPair843: Identifiable {
    let id = UUID()
    let bay: Int
    let port: BallastTank843
    let stbd: BallastTank843

    init(bay: Int) {
        self.bay = bay
        self.port = BallastTank843(bay: bay, side: "P")
        self.stbd = BallastTank843(bay: bay, side: "S")
    }
}

// MARK: - Hull outline (private to 843)

/// A top-down hull: a raked bow at the top, parallel body, tucked stern. It is
/// the frame the tank register is drawn inside, so a reader sees ballast where
/// it physically sits rather than as a list of names.
private struct HullPlan843: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let shoulder = rect.minY + 34
        let quarter = rect.maxY - 14
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: shoulder),
                       control: CGPoint(x: rect.maxX, y: rect.minY + 6))
        p.addLine(to: CGPoint(x: rect.maxX, y: quarter))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - 12, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + 12, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: quarter),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: shoulder))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                       control: CGPoint(x: rect.minX, y: rect.minY + 6))
        p.closeSubpath()
        return p
    }
}

// MARK: - The deck-plan tank register (private to 843)

/// The rare device, built properly: each tank is a real bottom-anchored fill
/// column, positioned port or starboard of a drawn centreline, bays running
/// forward to aft down the plan. An unreported tank renders as an EMPTY column
/// with a dashed rim and an em-dash level — never as a full tank, never as an
/// assumed zero presented as a sounding.
private struct BallastDeckRegister843: View {
    @Environment(\.palette) private var palette
    let pairs: [BallastBayPair843]

    private let cellHeight: CGFloat = 46
    private let spineWidth: CGFloat = 28

    private func tone(_ state: BallastState843) -> Color {
        switch state {
        case .treated:   return Brand.success
        case .exchanged: return Brand.blue
        case .untreated: return Color(hex: 0xFFC246)
        case .unknown:   return palette.textTertiary
        }
    }

    var body: some View {
        ZStack {
            HullPlan843()
                .stroke(palette.borderSoft, lineWidth: 1.5)
            VStack(spacing: 0) {
                Text("FWD")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                    .frame(height: 26)
                sideHeader
                ForEach(Array(pairs.enumerated()), id: \.element.id) { idx, pair in
                    if idx > 0 { Color.clear.frame(height: 5) }
                    bayRow(pair)
                }
                Text("AFT")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                    .frame(height: 24)
            }
            .padding(.horizontal, 16)
        }
    }

    private var sideHeader: some View {
        HStack(spacing: 0) {
            Text("PORT")
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("BAY")
                .font(.system(size: 7, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
                .frame(width: spineWidth)
            Text("STBD")
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.bottom, 6)
    }

    private func bayRow(_ pair: BallastBayPair843) -> some View {
        HStack(spacing: 0) {
            tankColumn(pair.port)
            // The centreline — the plan's spine, drawn through every bay.
            ZStack {
                Rectangle()
                    .fill(palette.borderFaint)
                    .frame(width: 1, height: cellHeight + 5)
                Text("\(pair.bay)")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
                    .padding(.horizontal, 4)
                    .background(palette.bgCard)
            }
            .frame(width: spineWidth)
            tankColumn(pair.stbd)
        }
    }

    private func tankColumn(_ tank: BallastTank843) -> some View {
        let color = tone(tank.state)
        let reported = tank.fillFrac != nil
        let levelText: String = {
            guard let f = tank.fillFrac else { return "—%" }
            return "\(Int((min(max(f, 0), 1) * 100).rounded()))%"
        }()
        return GeometryReader { geo in
            let h = max(geo.size.height, 1)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(palette.tintNeutral)
                if let f = tank.fillFrac, f > 0 {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(color.opacity(0.85))
                        .frame(height: max(h * CGFloat(min(f, 1)), 5))
                }
                VStack(spacing: 2) {
                    Text(tank.code)
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(reported ? palette.textPrimary : palette.textTertiary)
                    Text(levelText)
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(reported ? palette.textPrimary : palette.textTertiary)
                }
                .frame(maxHeight: .infinity)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(color.opacity(reported ? 0.0 : 0.55),
                                  style: StrokeStyle(lineWidth: 1, dash: reported ? [] : [3, 3]))
            )
        }
        .frame(height: cellHeight)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Body

private struct VesselBallastWaterBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    let voyageId: String

    @State private var shipment: BallastShipment843? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionNote: String? = nil

    /// The ship's ballast bays. The geometry is fixed — five wing pairs,
    /// forward to aft — while fill level and treatment state arrive with
    /// getBallastOps and are unreported until then.
    /// STATIC deliberately: the elements carry `let id = UUID()`, so an instance
    /// array literal re-mints every id on each Body re-init and the ForEach
    /// identity changes every render, defeating view diffing. The content is
    /// fixed geometry, so one evaluation for the process is correct.
    private static let pairs: [BallastBayPair843] = [
        BallastBayPair843(bay: 1),
        BallastBayPair843(bay: 2),
        BallastBayPair843(bay: 3),
        BallastBayPair843(bay: 4),
        BallastBayPair843(bay: 5)
    ]

    /// The three things that must all hold before a discharge is lawful. The
    /// conditions are the regulation; whether each is met is data nobody has
    /// returned yet, so all three read UNVERIFIED.
    /// Each detail line states the REQUIREMENT, never this ship's plant. The
    /// treatment train fitted to this hull (`bwmsMode`) is a returned field of
    /// getBallastOps (STUB) — naming a technology here would assert equipment
    /// nobody has reported.
    private let gateConditions: [(String, String)] = [
        ("BWMS treatment completed", "approved system run to completion · BWM Convention"),
        ("Viable organisms below D-2", "< 10 org/m³ ≥ 50 µm · BWM Convention"),
        ("Uptake & exchange in the record book", "position, volume and time logged")
    ]

    private var voyageLine: String {
        if let s = shipment {
            let vessel = s.vesselName ?? "vessel"
            let voy = s.voyageNumber ?? s.bookingNumber ?? voyageId
            return voy.isEmpty ? "\(vessel) · ballast water management"
                               : "\(vessel) · voy \(voy) · ballast water management"
        }
        // 2026-08-25 — was "MSC ANNA · inbound USLGB": a fabricated ship and
        // arrival port on a statutory environmental record.
        return "— · no voyage selected · ballast water management"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · BALLAST WATER",
                caption: "BWM D-2 · USCG",
                title: "Ballast ops",
                subtitle: voyageLine
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
                        VesselErrorCard(text: "Refresh failed — \(err) The ballast picture below is the last serve this session returned and is not being updated.")
                    }
                    dischargeHero
                    deckPlanSection
                    gateSection
                    VesselSummaryStrip(
                        label: "Last uptake —:— · — m³ via BWMS · salinity — PSU",
                        value: "no uptake logged",
                        valueColor: palette.textTertiary
                    )
                    VesselRegulatorBand(
                        title: "AUTHORITY · SINGLE-COUNTRY",
                        reference: "arrival · country",
                        rows: [
                            .init("US", "USCG BWM · 33 CFR 151.2025", active: true),
                            .init("CA", "Transport Canada BWM Regs 2021"),
                            .init("MX", "SEMAR · CONAPESCA inspection")
                        ]
                    )
                    // A refusal is NOT an acknowledgement. VesselToastRow is the
                    // post-mutation success affordance (green checkmark.seal on
                    // tintSuccess) — painting it here would read as a recorded
                    // discharge. The honest-gap note is the affordance.
                    if let actionNote { VesselGapNote(text: actionNote) }
                    ctaPair
                    VesselGapNote(text: "Vessel and voyage context are live, and the D-2 standard printed on the gate is the governing one for this arrival. No ballast record is linked — every tank level, every treatment state, the organism count, the TRO reading and the uptake log arrive with the ballast operations record. Nothing on this screen is estimated on the device.")
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - Hero (organism reading against the D-2 ceiling)

    private var dischargeHero: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    Text("Treated ballast · viable organisms vs D-2")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text("DISCHARGE NOT AUTHORISED")
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Color(hex: 0xFFC246))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color(hex: 0xFFC246).opacity(0.13)))
                }
                // An organism count is the finding a port state control officer
                // acts on. It stays an em-dash and stays NEUTRAL — never green,
                // never red — so no verdict is implied in either direction.
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("— /m³")
                        .font(.system(size: 32, weight: .bold, design: .monospaced)).tracking(-0.5)
                        .foregroundStyle(palette.textTertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("viable organisms ≥ 50 µm")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("BWMS reading not received")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("ROB ballast")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text("— m³")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                HStack(spacing: Space.s3) {
                    ceilingChip(label: "D-2 STANDARD", value: "< 10 org/m³", tone: Brand.success)
                    ceilingChip(label: "TRO RESIDUAL", value: "— mg/L", tone: palette.textTertiary)
                    Spacer(minLength: 0)
                }
                Text("The ceiling is the IMO BWM Convention regulation D-2 discharge standard, enforced at this arrival under 33 CFR 151.2025. No measurement is plotted against it.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func ceilingChip(label: String, value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(tone)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(palette.bgCardSoft))
    }

    // MARK: - Deck-plan tank register

    private var deckPlanSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "BALLAST TANKS · DECK PLAN · TREATMENT STATE",
                                right: "AWAITING TANK STATE")
            VesselGroupCard {
                BallastDeckRegister843(pairs: Self.pairs)
            }
            legendRow
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("Mid-ocean exchange —:— · BWMS mode — · 33 CFR 151.2025")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
        }
    }

    private var legendRow: some View {
        HStack(spacing: Space.s4) {
            legendChip("Treated", Brand.success)
            legendChip("Exchanged", Brand.blue)
            legendChip("Untreated", Color(hex: 0xFFC246))
            legendChip("No state", palette.textTertiary)
            Spacer(minLength: 0)
        }
    }

    private func legendChip(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: - Discharge-authorisation gate

    private var gateSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "DISCHARGE AUTHORISATION · D-2 GATE",
                                right: "0 OF 3 VERIFIED")
            VesselGroupCard {
                VStack(spacing: 0) {
                    ForEach(Array(gateConditions.enumerated()), id: \.offset) { idx, condition in
                        if idx > 0 { Divider().overlay(palette.borderFaint) }
                        gateRow(title: condition.0, detail: condition.1)
                    }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "lock")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xFFC246))
                Text("Discharge stays unlawful until all three conditions read verified")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
        }
    }

    private func gateRow(title: String, detail: String) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Image(systemName: "lock")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(detail)
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 6)
            Text("UNVERIFIED")
                .font(.system(size: 8.5, weight: .heavy)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(palette.tintNeutral))
                .overlay(
                    Capsule().strokeBorder(palette.textTertiary.opacity(0.45),
                                           style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
                )
        }
        .padding(.vertical, Space.s3)
    }

    // MARK: - CTA pair (both ONLINE_ONLY · both gap-honest)

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Record discharge", action: { flagDischargeGap() }, trailingIcon: "checkmark.seal")
            VesselGhostButton(title: "Log uptake", width: 150) { flagUptakeGap() }
        }
    }

    private func flagDischargeGap() {
        actionNote = "A discharge cannot be recorded from this device yet: the ballast operations record is not built, no treatment state has been reported, and a discharge authorisation is never queued offline — it must reflect live treatment state."
    }

    private func flagUptakeGap() {
        actionNote = "An uptake cannot be logged from this device yet: the ballast operations record is not built, and an uptake entry fixes the source water and position the later discharge is judged against, so it is never queued offline."
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 200)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 320)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 140)
        }
    }

    // MARK: - Load (REAL: getVesselShipmentDetail)

    private func load() async {
        loading = true; loadError = nil
        guard shipmentId > 0 else { shipment = nil; loading = false; return }
        struct In: Encodable { let id: Int }
        do {
            let detail: BallastDetail843? = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipmentDetail", input: In(id: shipmentId))
            self.shipment = detail?.shipment
        } catch {
            // `shipment` is deliberately NOT cleared. A failed refresh keeps the
            // last decoded serve on screen, banner-labelled as not fresh, rather
            // than blanking the ballast picture the officer may still be reading.
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("843 · Vessel Ballast Water Management · Night") {
    VesselBallastWaterScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("843 · Vessel Ballast Water Management · Light") {
    VesselBallastWaterScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
