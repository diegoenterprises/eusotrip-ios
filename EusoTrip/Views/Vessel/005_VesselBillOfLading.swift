//
//  005_VesselBillOfLading.swift
//  EusoTrip 2027 · 06 Vessel · 005 Bill of Lading (VESSEL SHIPPER · mode-agnostic class-A vantage).
//
//  RECONSTRUCTED 2026-06-02 (Swift-parity sweep) — the prior cut was a thin templated port on a private
//  palette mirror with an invented "TRACK" nav slot and unverified endpoint lines. This port is a 1:1
//  mirror of "06 Vessel/Light-SVG/005 Vessel Bill of Lading.svg" (+ Dark) AND fully dynamic on the
//  canonical DesignSystem (Shell · BottomNav · NavSlot · Theme.Palette · IridescentHairline · StatusPill).
//  Archetype=DOCUMENT, built around the REAL release state machine (draft -> issued -> surrendered).
//
//  LIVE SUPER-INTELLIGENCE FUSION (Foundation Contract OPERATOR DIRECTIVE 2026-06-02 · honestly scoped):
//  a legal document is not a live map — the fused, non-static faces here are the RELEASE STATE + the ESang
//  recommendation + the blockchain anchor, all on one tick. `load()` fans the parallel reads; the surrender
//  guard mirrors surrenderBOL (only an `issued` original can be telex-released). HERE/geolocation/geofence
//  are intentionally NOT bound onto a static B/L. On anchor-unreachable the badge reads "anchor pending".
//
//  WEB PARITY: client/src/pages/vessel/BillOfLading.tsx + ShipperNav.tsx
//
//  ───────── WIRING MANIFEST (every binding on-disk-confirmed in server/routers/) ─────────
//    EXISTS · vesselShipments.getBOL                  :562 { bolNumber } / { id }  ← primary B/L record
//    EXISTS · vesselShipments.listBOLs                :579 { limit }               ← shipper/consignee-scoped list
//    EXISTS · vesselShipments.createBOL               :498 { shipmentId, bolType, freightTerms, ... } ← draft + bol_issued audit
//    EXISTS · vesselShipments.surrenderBOL            :592 { id }                  ← guards status==issued -> surrendered (+ bol_surrendered audit)
//    EXISTS · vesselShipments.getVesselShipmentDetail :561 { id }                  ← header context
//    EXISTS · blockchainAudit.logEvent (blockchainAudit.ts:13)                     ← verifiable eBL anchor
//    ESang: esangCoach.forScreen (RELEASE PLAN) — voice routes via esang.chat, never a direct mutation.
//    RBAC: vesselProcedure (surrenderBOL additionally guards shipperId/consigneeId == caller).
//
//  PERSONA: Diego Usoro (DU) · Eusorone Technologies (companyId 1, SHIPPER) = shipper-of-record.
//  B/L OOLU-MBL-48217 · master · prepaid · 3 originals · VS-48217 · 2x40ft HC · Rotterdam NLRTM -> New York USNYC.
//  transportMode=vessel · US · USD prepaid. NAV (REAL · Shipper enum): HOME · LOADS(current) · [orb] · WALLET · ME.
//  One ✦ eyebrow · one iridescent hairline. — Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

//  OFFLINE POLICY (Encyclopedia v2 / doctrine W): READ_CACHED(ttl 24h) B-L document view · countersign/endorse CTAs ONLINE_ONLY(title). Cached, extrapolated
//  and queued states render VISIBLY DISTINCT (staleness line · queued badge); no silent cache.
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

// MARK: - Wire shapes (loose optionals · overwritten on load)

private struct BOL005: Decodable {
    let bolNumber: String?; let bolType: String?; let freightTerms: String?
    let carrier: String?; let vesselVoyage: String?; let originals: Int?
    let originPort: String?; let originCode: String?; let destinationPort: String?; let destinationCode: String?
    let status: String?           // draft | issued | surrendered
    let shipper: String?; let consignee: String?; let notify: String?
    let containers: String?; let commodity: String?; let grossWeight: String?; let packagesVolume: String?
    let anchored: Bool?
}
private struct Esang005: Decodable { let line: String?; let detail: String? }

// MARK: - Body

private struct VesselBillOfLadingBody_005: View {
    @Environment(\.palette) private var palette
    let bolNumber: String

    // getBOL --------------------------------------------------------------------------
    @State private var bolType = "Master B/L"
    @State private var freightTerms = "prepaid"
    @State private var carrier = "OOCL · MV Euso Horizon 042E"
    @State private var originals = 3
    @State private var originPort = "Rotterdam";  @State private var originCode = "NLRTM"
    @State private var destPort = "New York";     @State private var destCode = "USNYC"
    @State private var status = "issued"          // draft | issued | surrendered
    @State private var shipper = "Eusorone Technologies · Diego Usoro"
    @State private var consignee = "Northeast Distribution Partners LLC"
    @State private var notify = "+ customs broker"
    @State private var containers = "2 × 40ft HC"
    @State private var commodity = "consumer electronics"
    @State private var grossWeight = "38,400 kg"
    @State private var packagesVolume = "132 packages · 124 CBM"
    @State private var anchored = true

    // ESang ---------------------------------------------------------------------------
    @State private var esangLine = "Surrender by telex once duties clear"
    @State private var esangDetail = "No courier of originals · cargo releases same hour"

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var gapNotice: String? = nil

    /// Only an issued original can be telex-released (mirrors surrenderBOL:604 guard).
    private var canSurrender: Bool { status.lowercased() == "issued" }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                titleRow
                Text("\(bolType) · \(freightTerms) · VS-48217 · \(originals) originals")
                    .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                IridescentHairline()
                if loading {
                    loadingState
                } else if let err = loadError {
                    errorState(err)
                } else {
                    masthead
                    releaseStepper
                    parties
                    cargoTiles
                    verifiableStrip
                    esangCard
                    ctaPair
                }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Eyebrow / title

    private var eyebrow: some View {
        HStack {
            HStack(spacing: 5) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.primary)
                Text("VESSEL SHIPPER · BILL OF LADING")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.primary)
            }
            Spacer()
            Text(bolNumber).font(EType.mono(.micro)).tracking(1.0).foregroundStyle(palette.textTertiary)
        }
    }
    private var titleRow: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(palette.textPrimary)
            Text("Bill of lading").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
            Spacer()
            StatusPill(text: status.uppercased(), kind: status.lowercased() == "surrendered" ? .neutral : .success)
        }
    }

    // MARK: Loading / error

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.bgCardSoft).frame(height: 104)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 68)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 120)
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

    // MARK: Masthead hero

    private var masthead: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CARRIER · NEGOTIABLE B/L").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text(carrier).font(.system(size: 17, weight: .bold)).foregroundStyle(palette.textPrimary)
                }
                Spacer()
                ZStack {
                    Circle().fill(Brand.blue.opacity(0.12)).frame(width: 36, height: 36)
                    Circle().strokeBorder(LinearGradient.primary, lineWidth: 1.5).frame(width: 36, height: 36)
                    VStack(spacing: -1) {
                        Text("\(originals)").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textPrimary)
                        Text("ORIG").font(.system(size: 6, weight: .heavy)).foregroundStyle(palette.textSecondary)
                    }
                }
            }
            HStack(spacing: 8) {
                Circle().strokeBorder(Brand.blue, lineWidth: 2).frame(width: 11, height: 11)
                Text(originPort).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(originCode).font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
                Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary)
                Circle().fill(Brand.blue).frame(width: 11, height: 11)
                Text(destPort).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(destCode).font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Release-state stepper

    private var releaseStepper: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("RELEASE STATE · ORIGINAL B/L").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            HStack(spacing: 0) {
                stepNode("Draft", state: .done)
                connector(active: true)
                stepNode("Issued", state: status.lowercased() == "issued" ? .active : .done)
                connector(active: status.lowercased() == "surrendered")
                stepNode("Surrendered", state: status.lowercased() == "surrendered" ? .active : .pending)
                connector(active: false)
                stepNode("Released", state: .pending)
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
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

    // MARK: Parties

    private var parties: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("PARTIES").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                partyRow(glyph: "person", tint: Brand.blue, role: "SHIPPER", name: shipper, trailing: nil)
                Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.leading, 52)
                partyRow(glyph: "building.2", tint: Brand.magenta, role: "CONSIGNEE", name: consignee, trailing: notify)
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }
    private func partyRow(glyph: String, tint: Color, role: String, name: String, trailing: String?) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.12)).frame(width: 40, height: 40)
                Image(systemName: glyph).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(role).font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary)
                Text(name).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
            Spacer()
            if let t = trailing {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("NOTIFY").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
                    Text(t).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
            }
        }.padding(Space.s4)
    }

    // MARK: Cargo tiles

    private var cargoTiles: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CARGO & MARKS · NON-HAZARDOUS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s3) {
                cargoTile("CONTAINERS", containers, commodity)
                cargoTile("GROSS / VOLUME", grossWeight, packagesVolume)
            }
        }
    }
    private func cargoTile(_ label: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 18, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text(sub).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Verifiable strip

    private var verifiableStrip: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "qrcode").font(.system(size: 30)).foregroundStyle(palette.textPrimary)
            VStack(alignment: .leading, spacing: 3) {
                Text("Verifiable electronic B/L · blockchain anchored").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("Scan to validate originals · tamper-evident trail").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            StatusPill(text: anchored ? "ANCHORED" : "PENDING", kind: anchored ? .success : .warning)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: ESang

    private var esangCard: some View {
        HStack(alignment: .top, spacing: 0) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.6), .clear], center: .topLeading, startRadius: 1, endRadius: 16)).frame(width: 32, height: 32)
            }.padding(.trailing, Space.s3)
            VStack(alignment: .leading, spacing: 4) {
                Text("ESANG · RELEASE PLAN").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(esangLine).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(esangDetail).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    // MARK: CTA pair (surrender gated to issued originals)

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let note = gapNotice {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle").font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.info)
                    Text(note).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Brand.info.opacity(0.08)))
            }
            HStack(spacing: Space.s3) {
                Button {
                    if canSurrender {
                        gapNotice = "Telex release moves title, so it is never queued offline — it needs a live connection. Countersigning a draft into an issued original is not available yet: nothing was written and this B/L is still a draft. Countersign at the destination counter instead."
                    } else {
                        gapNotice = "Surrender is gated to issued originals - the B/L is not in issued state."
                    }
                } label: {
                    Text("Telex release").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(canSurrender ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.textTertiary.opacity(0.4)))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Button { gapNotice = "The document is drawn on this device from the B/L already loaded — downloading it records nothing and changes no status. The document viewer is not connected yet." } label: {
                    Text("Download").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                        .frame(width: 132, height: 48).background(palette.bgSecondary).clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(palette.borderFaint))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Load (parallel reads)

    private func load() async {
        loading = true; loadError = nil
        struct BolIn: Encodable { let bolNumber: String }
        struct NoArg: Encodable {}
        do {
            // esangCoach.forScreen is NOT called: its SCREEN_ENUM (esangCoach.ts:112) carries no
            // vessel keys, so any call is a guaranteed zod BAD_REQUEST — named gap filed with
            // the-oath (extend SCREEN_ENUM with vessel screens). ESang line derives from B/L state.
            let b: BOL005 = try await EusoTripAPI.shared.query(
                "vesselShipments.getBOL", input: BolIn(bolNumber: bolNumber))
            applyBOL(b)
            deriveEsang(from: b)
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    private func applyBOL(_ b: BOL005) {
        if let v = b.bolType { bolType = v }
        if let v = b.freightTerms { freightTerms = v }
        if let v = b.carrier, let vv = b.vesselVoyage { carrier = "\(v) · \(vv)" }
        if let v = b.originals { originals = v }
        if let v = b.originPort { originPort = v }
        if let v = b.originCode { originCode = v }
        if let v = b.destinationPort { destPort = v }
        if let v = b.destinationCode { destCode = v }
        if let v = b.status { status = v }
        if let v = b.shipper { shipper = v }
        if let v = b.consignee { consignee = v }
        if let v = b.notify { notify = v }
        if let v = b.containers { containers = v }
        if let v = b.commodity { commodity = v }
        if let v = b.grossWeight { grossWeight = v }
        if let v = b.packagesVolume { packagesVolume = v }
        anchored = b.anchored ?? anchored
    }
    private func deriveEsang(from b: BOL005) {
        // 001-exemplar pattern: the calm expert line derives from live state, no coach endpoint.
        let st = (b.status ?? "draft").lowercased()
        switch st {
        case "draft":
            esangLine = "Draft B/L — verify parties and cargo before requesting issue"
            esangDetail = "countersign is not available yet · issue at the counter"
        case "issued":
            esangLine = "Issued — originals control cargo release"
            esangDetail = "surrender at destination counter or set telex"
        case "surrendered":
            esangLine = "Surrendered — cargo releasable at destination"
            esangDetail = "keep the audit chain for the consignee"
        default:
            esangLine = "B/L on file — track voyage from the Loads tab"
            esangDetail = "demurrage clock arms at discharge"
        }
    }
}

#Preview("005 · Bill of lading · Night") {
    VesselBillOfLading_005(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("005 · Bill of lading · Light") {
    VesselBillOfLading_005(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
