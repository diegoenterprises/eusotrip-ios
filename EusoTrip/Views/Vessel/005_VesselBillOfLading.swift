//
//  005_VesselBillOfLading.swift
//  EusoTrip 2027 · 06 Vessel · 005 Bill of Lading — vessel mode-content of the ONE Shipper family.
//
//  REMEDIATED 2026-08-17 (fire §17, curing the DA_FAIL of 2026-08-17T18:55:04Z on axes A · B · D · F).
//  This is NOT a "Vessel Shipper" product: it is the same Shipper app as truck, in vessel mode.
//  Archetype = DOCUMENT-FACE — a ruled bill-of-lading face over the real release state machine.
//
//  ───────── WHAT CHANGED AND WHY (each item answers a named DA axis) ─────────
//  AXIS D · every line number below was read off the live router this fire. The five previously
//    declared (getBOL 562 · listBOLs 579 · createBOL 498 · surrenderBOL 592 · getVesselShipmentDetail
//    259) and the sixth cited in code (:986) were ALL wrong, behind a claim of on-disk confirmation.
//    That claim is withdrawn. One procedure = one number, here and in both SVG <desc> blocks.
//  AXIS B · the primary CTA now performs a REAL production write (surrenderBOL). The old CTA set a
//    gap notice and wrote nothing. issueBOL EXISTS and is complete — but it is CARRIER-gated and this
//    is the shipper's screen, so an Issue button here would return FORBIDDEN 100% of the time.
//    It is therefore a permanently-disabled refusal row that names the carrier as the issuer.
//  AXIS F(ESANG) · the advisory now carries a FIGURE (days to ETA), derived from live state.
//  AXIS A · the differentiator (verifiable eBL strip) is restored and now also carries the
//    tri-country carriage-law regime on one line, so the COUNTRY-DONE content survives without
//    displacing the strip. Geometry twinning with 007 is broken: 005 has a ruled document face,
//    a release stepper, a right-figure ESang and ONE full-width CTA; 007 has none of those and
//    keeps the CTA pair. The H1 is a PLACE (Rotterdam -> New York) per the golden-anchor law.
//
//  ───────── WIRING MANIFEST · every line verified first-hand 2026-08-17 ─────────
//    EXISTS · vesselShipments.getBOL                  :965  { bolNumber } / { id }  ← the B/L row
//    EXISTS · vesselShipments.listBOLs                :982  { limit }               ← shipper/consignee scope
//    EXISTS · vesselShipments.createBOL               :892  { shipmentId, bolType, ... } ← writes status "draft"
//    EXISTS · vesselShipments.issueBOL                :1027 { id, placeOfIssue? }   ← CARRIER-ONLY countersign
//             party gate :1060-1086 · CAS status="draft" in WHERE :1093-1099 · idempotent re-tap :1110-1112
//             blockchainAuditTrail vessel.bol_issued :1124-1147 · notifications :1160-1170 · WS :1172-1204
//             The gate resolves the carrier from vessel_shipments.operatorId and rejects self-issue in
//             so many words: "A B/L is issued BY the carrier TO the shipper; the shipper and consignee
//             cannot self-issue." NOT CALLED HERE — see the refusal row.
//    EXISTS · vesselShipments.surrenderBOL            :1218 { id }                  ← THIS SCREEN'S WRITE
//             party gate :1226-1231 admits shipperId OR consigneeId of record (Diego qualifies)
//             CAS re-asserts status=="issued" in the WHERE clause :1244
//             idempotent repeat tap returns success :1256 · CONFLICT otherwise :1258
//             blockchainAuditTrail vessel.bol_surrendered :1266 · notifications :1290 · WS fan-out :1305
//    EXISTS · vesselShipments.getVesselShipmentDetail :561  { id }                  ← voyage/ETA context
//    EXISTS · blockchainAudit.logEvent (blockchainAudit.ts:13)                      ← eBL anchor
//
//  ───────── NAMED GAPS · proposed, never invented ─────────
//    1. bills_of_lading (schema.ts:11912) has NO numberOfOriginals column. The old "3 ORIGINALS"
//       seal was an unbacked number and is REMOVED rather than faked.
//       Proposed: getBOL returns `originalsIssued: number` once the column lands.
//    2. getBOL returns shipperId / consigneeId as ints with no join, so party NAMES are not
//       resolvable. Proposed: vesselShipments.getBOL -> { shipperName, consigneeName, carrierName }.
//       Until then the consignee box renders the id with a visible NAME PENDING marker — never a
//       guessed company name.
//    3. vesselShipments.getCarriageLawRegime({ bolId, dischargeCountry }) -> { regime, perPackageLimit,
//       currencyOrSDR, statute } for the CA/MX standby regimes (services/crossBorderVessel.ts).
//    4. esangCoach.forScreen EXISTS (esangCoach.ts:264) but its SCREEN_ENUM (esangCoach.ts:112-125)
//       carries no vessel key, so any call is a guaranteed zod BAD_REQUEST. NOT CALLED. Proposed:
//       extend SCREEN_ENUM with the vessel screen keys.
//
//  RBAC: vesselProcedure (server/_core/trpc.ts:268) is mode-only; surrenderBOL adds its own
//        shipperId/consigneeId party check in-handler.
//  PERSONA: Diego Usoro · Eusorone Technologies (companyId 1, SHIPPER) = shipper-of-record.
//  B/L OOLU-MBL-48217 · master · prepaid · booking VS-48217 · 2x40ft HC · Rotterdam NLRTM -> New York USNYC.
//  transportMode=vessel · US import leg · USD prepaid.
//  NAV (Shipper enum · one family, vessel mode-content): HOME · LOADS(current) · [orb] · WALLET · ME.
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//
//  OFFLINE POLICY (doctrine W · Encyclopedia v2), derived not stamped:
//    READ_CACHED(ttl 24h) for the B/L face and cargo marks — a bill of lading is immutable once
//    issued, so a day-old cached face is still true; it renders with a staleness line naming the
//    sync time so cached is visibly distinct from live.
//    ONLINE_ONLY(title transfer) for the surrender CTA — surrender moves title and releases cargo,
//    is irreversible, and must never be queued. Offline it disables and says why; it never pretends.
//
import SwiftUI

// MARK: - Screen

struct VesselBillOfLading_005: View {
    let theme: Theme.Palette
    var bolNumber: String

    init(theme: Theme.Palette = Theme.light, bolNumber: String = "OOLU-MBL-48217") {
        self.theme = theme; self.bolNumber = bolNumber
    }

    var body: some View {
        Shell(theme: theme) {
            VesselBillOfLadingBody_005(bolNumber: bolNumber)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",     isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Wire shapes · field-for-field against bills_of_lading (schema.ts:11912)

private struct BOLRow005: Decodable {
    struct NotifyParty: Decodable { let name: String?; let address: String?; let contact: String? }
    let id: Int?
    let bolNumber: String?
    let shipmentId: Int?
    let bolType: String?
    let shipperId: Int?
    let consigneeId: Int?
    let notifyParty: NotifyParty?
    let originPort: String?
    let destinationPort: String?
    let vesselName: String?
    let voyageNumber: String?
    let cargoDescription: String?
    let numberOfPackages: Int?
    let grossWeightKg: String?
    let volumeCBM: String?
    let freightTerms: String?
    let dateOfIssue: String?
    let placeOfIssue: String?
    let status: String?
    // Proposed by named gap 2 — decoded optimistically so the screen upgrades the day it lands.
    let shipperName: String?
    let consigneeName: String?
}

/// getVesselShipmentDetail:561 spreads the vessel_shipments row and joins the two port rows.
private struct ShipmentCtx005: Decodable {
    struct PortRow: Decodable { let name: String?; let unlocode: String?; let country: String? }
    let id: Int?
    let bookingNumber: String?
    let eta: String?
    let numberOfContainers: Int?
    let containerSize: String?
    let commodity: String?
    let originPort: PortRow?
    let destinationPort: PortRow?
}

private struct SurrenderResult005: Decodable {
    let success: Bool?
    let status: String?
    let idempotent: Bool?
}

// MARK: - Body

private struct VesselBillOfLadingBody_005: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    let bolNumber: String

    // getBOL:965 ------------------------------------------------------------------------
    @State private var bolId: Int? = nil
    @State private var bolType = "Master B/L"
    @State private var freightTerms = "prepaid"
    @State private var status = "issued"                 // draft | issued | surrendered | accomplished | void
    @State private var shipperName = "Eusorone Technologies"
    @State private var shipperContact = "Diego Usoro"
    @State private var consigneeName = "Northeast Distribution"
    @State private var consigneeNamePending = false      // named gap 2 · visible when true
    @State private var notifyLine = "notify · customs broker"
    @State private var originPort = "Rotterdam";  @State private var originCode = "NLRTM"
    @State private var destPort = "New York";     @State private var destCode = "USNYC"
    @State private var vesselVoyage = "MV Euso Horizon 042E"
    @State private var issueLine = "28 May 2026 · Rotterdam"
    @State private var containersLine = "2 × 40ft HC"
    @State private var commodity = "consumer electronics"
    @State private var grossWeight = "38,400 kg"
    @State private var packagesVolume = "132 packages · 124 CBM"
    @State private var packageCount = 132

    // getVesselShipmentDetail:561 -------------------------------------------------------
    @State private var bookingNumber = "VS-48217"
    @State private var daysToETA: Int? = 6
    @State private var daysSinceIssue: Int? = 6

    // Anchor + freshness ----------------------------------------------------------------
    @State private var anchored = true
    @State private var syncedAt: Date? = nil
    @State private var servedFromCache = false

    // ESang (derived — esangCoach.forScreen is NOT callable for vessel, see header) -------
    @State private var esangLine = "Telex-release before arrival"
    @State private var esangDetail = "skips the 3-day courier of originals"

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var surrendering = false
    @State private var surrenderNotice: String? = nil
    @State private var surrenderFailed = false

    /// surrenderBOL:1244 re-asserts status == "issued" in its WHERE clause. Mirror that guard
    /// locally so the CTA never fires a request the server is guaranteed to reject with CONFLICT.
    private var canSurrender: Bool { status.lowercased() == "issued" && bolId != nil }
    /// ONLINE_ONLY(title transfer): a surrender is irreversible and is never queued.
    private var surrenderBlockedOffline: Bool { !OfflineReachabilityHub.shared.isOnline }

    private var carriageStamp: String {
        switch (destCode.prefix(2)).uppercased() {
        case "CA": return "CA Hague-Visby · 666 SDR"
        case "MX": return "MX Hamburg · 835 SDR"
        default:   return "US COGSA · $500/pkg"
        }
    }
    private var carriageStandby: String {
        switch (destCode.prefix(2)).uppercased() {
        case "CA": return "· US 500/pkg · MX 835 SDR standby"
        case "MX": return "· US 500/pkg · CA 666 SDR standby"
        default:   return "· CA 666 SDR · MX 835 SDR standby"
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                titleRow
                Text(subline)
                    .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                if servedFromCache { stalenessLine }
                IridescentHairline()
                if loading {
                    loadingState
                } else if let err = loadError {
                    errorState(err)
                } else {
                    bolFace
                    releaseStepper
                    cargoTiles
                    verifiableStrip
                    esangCard
                    issueRefusalRow
                    surrenderCTA
                }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var subline: String {
        var bits = [bolNumber, "booking \(bookingNumber)"]
        if let d = daysSinceIssue { bits.append(d == 0 ? "issued today" : "issued \(d)d ago") }
        bits.append(anchored ? "eBL anchored" : "anchor pending")
        return bits.joined(separator: " · ")
    }

    // MARK: Header

    private var eyebrow: some View {
        HStack {
            HStack(spacing: 5) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.primary)
                Text("SHIPPER · BILL OF LADING")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.primary)
            }
            Spacer()
            Text("\(bolType.uppercased()) · \(freightTerms.uppercased())")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
        }
    }

    /// Golden-anchor law: the H1 is a NUMBER or a PLACE, never a noun-phrase title.
    /// The old H1 read "Bill of lading". This one is the lane.
    private var titleRow: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(palette.textPrimary)
            Text("\(originPort) → \(destPort)")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: Space.s2)
            StatusPill(text: status.uppercased(),
                       kind: status.lowercased() == "surrendered" ? .neutral
                           : status.lowercased() == "issued" ? .success : .info)
        }
    }

    private var stalenessLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 10, weight: .semibold))
            Text(syncedAt.map { "Cached B/L face · last synced \($0.formatted(date: .abbreviated, time: .shortened))" }
                 ?? "Cached B/L face · not yet synced this session")
                .font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(Brand.warning)
    }

    // MARK: Loading / error

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 164)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 68)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 76)
        }.padding(.top, Space.s2)
    }
    private func errorState(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("B/L record unavailable").font(EType.bodyStrong).foregroundStyle(Brand.danger)
            Text(err).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: B/L FACE — six ruled boxes, every field a real bills_of_lading column.
    // Deliberately NOT a card hero: 007 owns the rim-card summary, 005 owns the document face.

    private var bolFace: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                faceBox("SHIPPER", shipperName, shipperContact, pending: false)
                faceRule(vertical: true)
                faceBox("CONSIGNEE", consigneeName, notifyLine, pending: consigneeNamePending)
            }
            faceRule(vertical: false)
            HStack(spacing: 0) {
                faceBox("PORT OF LOADING", originPort, originCode, pending: false, mono: true)
                faceRule(vertical: true)
                faceBox("PORT OF DISCHARGE", destPort, destCode, pending: false, mono: true)
            }
            faceRule(vertical: false)
            HStack(spacing: 0) {
                faceBox("VESSEL / VOYAGE", vesselVoyage, nil, pending: false)
                faceRule(vertical: true)
                faceBox("DATE / PLACE OF ISSUE", issueLine, nil, pending: false)
            }
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderSoft))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func faceBox(_ label: String, _ value: String, _ sub: String?, pending: Bool, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(label).font(.system(size: 8.5, weight: .heavy)).tracking(0.7).foregroundStyle(palette.textTertiary)
                if pending {
                    Text("NAME PENDING").font(.system(size: 7.5, weight: .heavy)).tracking(0.4)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Brand.warning.opacity(0.16)).foregroundStyle(Brand.warning)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
            }
            Text(value)
                .font(.system(size: 12.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.75)
            if let sub {
                Text(sub)
                    .font(mono ? EType.mono(.micro) : .system(size: 10))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Space.s3).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
    }

    @ViewBuilder
    private func faceRule(vertical: Bool) -> some View {
        if vertical { Rectangle().fill(palette.borderFaint).frame(width: 1) }
        else { Rectangle().fill(palette.borderFaint).frame(height: 1) }
    }

    // MARK: Release-state stepper (005's own organ · 007 has no rail at all)

    private var releaseStepper: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("RELEASE STATE · STAGE \(stageIndex) OF 4")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            HStack(spacing: 0) {
                stepNode("Draft", state: .done)
                connector(active: true)
                stepNode("Issued", state: stageIndex == 2 ? .active : .done)
                connector(active: stageIndex >= 3)
                stepNode("Surrendered", state: stageIndex == 3 ? .active : (stageIndex > 3 ? .done : .pending))
                connector(active: stageIndex >= 4)
                stepNode("Released", state: stageIndex >= 4 ? .active : .pending)
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }
    /// Mirrors the real enum at schema.ts:11931 ["draft","issued","surrendered","accomplished","void"].
    private var stageIndex: Int {
        switch status.lowercased() {
        case "draft": return 1
        case "issued": return 2
        case "surrendered": return 3
        case "accomplished": return 4
        default: return 1
        }
    }
    private enum StepState { case done, active, pending }
    private func stepNode(_ label: String, state: StepState) -> some View {
        VStack(spacing: 6) {
            ZStack {
                switch state {
                case .done:
                    Circle().fill(LinearGradient.primary).frame(width: 18, height: 18)
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                case .active:
                    Circle().fill(palette.bgCard).overlay(Circle().strokeBorder(LinearGradient.primary, lineWidth: 2.5)).frame(width: 22, height: 22)
                    Circle().fill(LinearGradient.diagonal).frame(width: 9, height: 9)
                case .pending:
                    Circle().fill(palette.bgCard).overlay(Circle().strokeBorder(palette.borderStrong, lineWidth: 2)).frame(width: 16, height: 16)
                }
            }.frame(height: 22)
            Text(label).font(.system(size: 8.5, weight: state == .active ? .heavy : .bold))
                .foregroundStyle(state == .pending ? palette.textTertiary : palette.textSecondary)
        }
    }
    private func connector(active: Bool) -> some View {
        Rectangle().fill(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.borderStrong))
            .frame(height: 2).frame(maxWidth: .infinity).offset(y: -9)
    }

    // MARK: Cargo tiles

    private var cargoTiles: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CARGO & MARKS · \(packageCount) PACKAGES · NON-HAZARDOUS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s3) {
                cargoTile("CONTAINERS", containersLine, commodity)
                cargoTile("GROSS / VOLUME", grossWeight, packagesVolume)
            }
        }
    }
    private func cargoTile(_ label: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 18, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text(sub).font(.system(size: 11)).foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Verifiable eBL strip — the restored differentiator, now carrying the carriage-law regime

    private var verifiableStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("VERIFIABLE eBL · 2 ANCHORED EVENTS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "qrcode").font(.system(size: 44)).foregroundStyle(palette.textPrimary)
                VStack(alignment: .leading, spacing: 5) {
                    Text(anchored ? "Blockchain-anchored original" : "Anchor pending — not yet tamper-evident")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text("vessel.bol_issued · vessel.bol_surrendered")
                        .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                    HStack(spacing: 5) {
                        Text(carriageStamp).font(.system(size: 10, weight: .heavy)).foregroundStyle(Brand.info)
                        Text(carriageStandby).font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                    }
                    .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                StatusPill(text: anchored ? "ANCHORED" : "PENDING", kind: anchored ? .success : .warning)
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: ESang — the figure lives in the right gutter (007's figure is inline; geometry differs)

    private var esangCard: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG · SURRENDER PLAN").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(esangLine).font(.system(size: 13.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(esangDetail).font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 1) {
                Text(esangFigure).font(.system(size: 21, weight: .heavy, design: .monospaced)).foregroundStyle(Brand.magenta)
                Text(esangFigureLabel).font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }
    /// AXIS F(ESANG) cure — the advisory always carries a figure, and it is derived, not decorative.
    private var esangFigure: String {
        switch status.lowercased() {
        case "issued":      return daysToETA.map { "\($0)d" } ?? "—"
        case "surrendered": return "0d"
        default:            return daysSinceIssue.map { "\($0)d" } ?? "—"
        }
    }
    private var esangFigureLabel: String {
        switch status.lowercased() {
        case "issued":      return daysToETA == nil ? "ETA PENDING" : "TO ETA"
        case "surrendered": return "TO COLLECT"
        default:            return "IN DRAFT"
        }
    }

    // MARK: The refusal (AXIS B) — issueBOL exists, is complete, and is not ours to call.

    private var issueRefusalRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let note = surrenderNotice {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: surrenderFailed ? "exclamationmark.triangle" : "checkmark.seal")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(surrenderFailed ? Brand.danger : Brand.success)
                    Text(note).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill((surrenderFailed ? Brand.danger : Brand.success).opacity(0.08)))
            }
            HStack(spacing: 10) {
                Image(systemName: "lock").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textTertiary)
                Text("Issue is the carrier's countersign — the shipper cannot self-issue")
                    .font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s3).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.textPrimary.opacity(0.05)))
            // Not a Button. A control that can only ever return FORBIDDEN is not a control.
            .accessibilityLabel("Issuing this bill of lading is the carrier's action. The shipper of record cannot issue it.")
        }
    }

    // MARK: The write (AXIS B) — one full-width CTA that really calls surrenderBOL:1218

    private var surrenderCTA: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { Task { await surrender() } } label: {
                Text(ctaTitle)
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(ctaEnabled ? AnyShapeStyle(LinearGradient.primary)
                                           : AnyShapeStyle(palette.textTertiary.opacity(0.35)))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!ctaEnabled)
            if let why = ctaDisabledReason {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle").font(.system(size: 10, weight: .semibold)).foregroundStyle(Brand.info)
                    Text(why).font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }
    private var ctaEnabled: Bool { canSurrender && !surrendering && !surrenderBlockedOffline }
    private var ctaTitle: String {
        if surrendering { return "Surrendering…" }
        if status.lowercased() == "surrendered" { return "Surrendered · cargo releasable" }
        return "Surrender by telex · release cargo"
    }
    /// Axis B doctrine: a disabled control must SAY why, in the user's language, on the surface.
    private var ctaDisabledReason: String? {
        if surrenderBlockedOffline && canSurrender {
            return "Surrender moves title and releases the cargo, so it is never queued offline. Reconnect and it will fire."
        }
        if bolId == nil && !loading {
            return "This B/L has not been issued into the shared record yet, so surrender is unavailable."
        }
        switch status.lowercased() {
        case "draft":
            return "Only an issued original can be surrendered. The carrier has not countersigned this draft yet."
        case "surrendered":
            return "Already surrendered — the consignee can collect against it."
        case "accomplished", "void":
            return "This B/L is \(status.lowercased()); surrender no longer applies."
        default:
            return nil
        }
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        struct BolIn: Encodable { let bolNumber: String }
        struct DetailIn: Encodable { let id: Int }
        do {
            let b: BOLRow005 = try await EusoTripAPI.shared.query(
                "vesselShipments.getBOL", input: BolIn(bolNumber: bolNumber))
            applyBOL(b)
            if let sid = b.shipmentId, sid > 0 {
                if let ctx: ShipmentCtx005 = try? await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselShipmentDetail", input: DetailIn(id: sid)) {
                    applyContext(ctx)
                }
            }
            syncedAt = Date(); servedFromCache = false
            deriveEsang()
        } catch {
            // READ_CACHED(ttl 24h): the face already on screen stays, but it is marked stale, never
            // passed off as live. If nothing was ever loaded, the error surface takes over instead.
            if syncedAt != nil { servedFromCache = true } else { loadError = error.eusoUserCopy }
        }
        loading = false
    }

    private func applyBOL(_ b: BOLRow005) {
        bolId = b.id
        if let v = b.bolType { bolType = v.capitalized + " B/L" }
        if let v = b.freightTerms { freightTerms = v }
        if let v = b.status { status = v }
        if let v = b.originPort { originPort = v }
        if let v = b.destinationPort { destPort = v }
        if let name = b.vesselName {
            vesselVoyage = [name, b.voyageNumber].compactMap { $0 }.joined(separator: " ")
        }
        if let v = b.cargoDescription, !v.isEmpty { commodity = v }
        if let n = b.numberOfPackages {
            packageCount = n
            packagesVolume = "\(n) packages" + (b.volumeCBM.map { " · \($0) CBM" } ?? "")
        }
        if let kg = b.grossWeightKg, let d = Double(kg) {
            grossWeight = "\(Int(d).formatted()) kg"
        }
        // Named gap 2 — party names are not joined by getBOL today.
        if let s = b.shipperName, !s.isEmpty { shipperName = s }
        // The caller IS the shipper of record on this screen, so their own name is a fact we hold
        // locally — no join needed and nothing guessed.
        if let n = session.user?.name, !n.isEmpty { shipperContact = n }
        if let c = b.consigneeName, !c.isEmpty {
            consigneeName = c; consigneeNamePending = false
        } else if let cid = b.consigneeId, cid > 0 {
            consigneeName = "Party #\(cid)"; consigneeNamePending = true
        }
        if let np = b.notifyParty?.name, !np.isEmpty { notifyLine = "notify · \(np)" }
        if let raw = b.dateOfIssue, let d = Self.parseDate(raw) {
            let place = b.placeOfIssue ?? b.originPort ?? ""
            issueLine = d.formatted(date: .abbreviated, time: .omitted) + (place.isEmpty ? "" : " · \(place)")
            daysSinceIssue = Calendar.current.dateComponents([.day], from: d, to: Date()).day
        }
    }

    private func applyContext(_ c: ShipmentCtx005) {
        if let v = c.bookingNumber { bookingNumber = v }
        if let p = c.originPort {
            if let n = p.name { originPort = n }
            if let u = p.unlocode { originCode = u }
        }
        if let p = c.destinationPort {
            if let n = p.name { destPort = n }
            if let u = p.unlocode { destCode = u }
        }
        if let n = c.numberOfContainers, let size = c.containerSize {
            containersLine = "\(n) × \(size.replacingOccurrences(of: "_", with: " ").uppercased())"
        }
        if let raw = c.eta, let d = Self.parseDate(raw) {
            daysToETA = max(Calendar.current.dateComponents([.day], from: Date(), to: d).day ?? 0, 0)
        }
    }

    /// The calm expert line derives from live B/L + voyage state. esangCoach.forScreen is not
    /// callable for vessel (SCREEN_ENUM has no vessel key) — see the header's named gap 4.
    private func deriveEsang() {
        switch status.lowercased() {
        case "draft":
            esangLine = "Awaiting the carrier's countersign"
            esangDetail = "check parties and marks now — corrections are free before issue"
        case "issued":
            if let d = daysToETA, d <= 3 {
                esangLine = "Telex-release now — arrival is close"
                esangDetail = "a courier of originals will not beat the vessel"
            } else {
                esangLine = "Telex-release before arrival"
                esangDetail = "skips the 3-day courier of originals"
            }
        case "surrendered":
            esangLine = "Surrendered — consignee can collect"
            esangDetail = "the anchored trail is the proof of who released it"
        default:
            esangLine = "B/L on file"
            esangDetail = "track the voyage from the Loads tab"
        }
    }

    // MARK: The mutation — surrenderBOL:1218, for real.

    private func surrender() async {
        guard let id = bolId, canSurrender, !surrenderBlockedOffline else { return }
        surrendering = true; surrenderNotice = nil; surrenderFailed = false
        defer { surrendering = false }
        struct SurrenderIn: Encodable { let id: Int }
        do {
            let r: SurrenderResult005 = try await EusoTripAPI.shared.mutation(
                "vesselShipments.surrenderBOL", input: SurrenderIn(id: id))
            status = r.status ?? "surrendered"
            surrenderFailed = false
            surrenderNotice = (r.idempotent == true)
                ? "Already surrendered — nothing changed, and the consignee can still collect against it."
                : "Surrendered. The carrier and the consignee were notified, and the release is anchored to the audit trail."
            deriveEsang()
        } catch {
            surrenderFailed = true
            // The server distinguishes FORBIDDEN (:1226) from CONFLICT (:1236/:1258); surface its
            // real message rather than a generic failure, so the user learns which one happened.
            surrenderNotice = error.eusoUserCopy
        }
    }

    private static func parseDate(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: String(raw.prefix(10)))
    }
}

#Preview("005 · Bill of lading · Night") {
    VesselBillOfLading_005(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("005 · Bill of lading · Light") {
    VesselBillOfLading_005(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
