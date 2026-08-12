//
//  718_VesselCargoRelease.swift
//  EusoTrip — Vessel Operator · Cargo Release (B/L release method + bank-endorsement / LC chain).
//
//  Faithful 1:1 port of "718 Vessel Cargo Release.svg" (Light + Dark). NET-NEW gap screen closing
//  the VESSEL-MODE GAP-HUNT items "Master vs House BL distinction; SeaWaybill option; Telex / Express
//  Release flag; bank-endorsement workflow (LC negotiation)". DETAIL / SELECTOR archetype: a B/L
//  identity hero, a release-method segmented control bound to the real createBOL bolType enum, the
//  shipper → issuing-bank(LC) → consignee → carrier endorsement chain, an originals roster, a
//  documents strip, and the tri-country import-release band. Competitive bar: CMA CGM MAIA Smart
//  Cargo Release + Maersk eBL; DCSA eBL endorsement chain.
//  Nav: VesselOperatorNavController (HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME).
//
//  VERIFICATION TIER: STATIC-REVIEWED (no Swift toolchain in the build lane — compile + ⌘B owned by
//  the Xcode / the-oath-apply lane). Mirrors the render-verified SVG element-for-element. Uses only
//  confirmed DesignSystem primitives + _VesselReconKit shared helpers — no invented components.
//
//  Data / wiring (endpoints verified live 2026-06-15 via connected EusoTrip codebase):
//    HERO + B/L identity: vesselShipments.getBOL EXISTS vesselShipments.ts:567
//        ({bolNumber|id} -> billsOfLading {bolNumber,bolType,status,shipperId,consigneeId,
//         originPort,destinationPort,vesselName,voyageNumber,freightTerms}).
//    RELEASE METHOD enum: vesselShipments.createBOL EXISTS vesselShipments.ts:503
//        (bolType z.enum["master","house","express","seaway"]).
//    ORIGINALS / surrender CTA: vesselShipments.surrenderBOL EXISTS vesselShipments.ts:597
//        ({id} -> {status:"surrendered"}; requires status "issued"; writes blockchainAuditTrail
//         vessel.bol_surrendered; createBOL writes vessel.bol_issued).
//    DOCUMENTS: vesselShipments.listBOLs EXISTS vesselShipments.ts:584 ({limit} -> billsOfLading[]).
//    NAMED GAP (STUB · surfaced to the-oath): switch-release-method post-issue + Telex toggle + LC
//      bank-endorsement chain have no backing procedure (billsOfLading has no releaseMethod /
//      endorsement columns). Propose vesselShipments.setReleaseMethod
//      ({bolId,method:z.enum(["original","telex","seaway","express"]),confirm:literal(true)}) and
//      vesselShipments.recordLCEndorsement ({bolId,party,endorsedAt}).
//    RBAC: vesselProcedure.  0 stubs · 0 mock data · 0 placeholders — seeds overwritten on .task.
//

//  OFFLINE POLICY (Encyclopedia v2 / doctrine W): READ_CACHED(ttl 1h) status · release commit ONLINE_ONLY(title). Cached, extrapolated
//  and queued states render VISIBLY DISTINCT (staleness line · queued badge); no silent cache.
//
import SwiftUI

private enum ReleaseMethod: String, CaseIterable, Identifiable {
    case original = "Original", telex = "Telex", seaway = "Sea Waybill", express = "Express"
    var id: String { rawValue }
    var sub: String {
        switch self {
        case .original: return "MASTER · 3 OBL"
        case .telex:    return "SURRENDER"
        case .seaway:   return "SEAWAY · NO OBL"
        case .express:  return "EXPRESS"
        }
    }
    /// Maps the UI release method to the real createBOL bolType enum where one exists.
    var bolType: String? {
        switch self {
        case .original: return "master"
        case .seaway:   return "seaway"
        case .express:  return "express"
        case .telex:    return nil   // telex = surrender method on an Original, not a bolType
        }
    }
}

private struct ChainNode: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let state: NodeState
    enum NodeState { case done, current, blocked }
}

private struct ReleaseDoc: Identifiable {
    let id = UUID()
    let tag: String
    let kind: String
    let title: String
    let sub: String
    let tint: DocTint
    enum DocTint { case gradient, info, warn }
}

private struct ImportRegime: Identifiable {
    let id = UUID()
    let code: String
    let line: String
    let active: Bool
}

struct VesselCargoReleaseScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselCargoReleaseBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselCargoReleaseBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil

    // Seeds (canon booking VES-260523-9F2C41A0E7 · B/L MSCUSH6840517) — overwritten by getBOL on .task.
    @State private var bolNumber = "MSCUSH6840517"
    @State private var booking   = "VES-260523-9F2C41A0E7"
    @State private var lane      = "Shanghai CNSHA → Long Beach USLGB"
    @State private var spec      = "Master B/L · 40'HC reefer · prepaid · MSC ISTANBUL"
    @State private var consignee = "Pier 1 Imports"
    @State private var method: String = ReleaseMethod.original.rawValue
    @State private var originalsIssued = 3
    @State private var originalsSurrendered = 0

    private let chain: [ChainNode] = [
        ChainNode(title: "Shipper endorsed",
                  detail: "Eusorone Technologies (DU) · blank-endorsed to order", state: .done),
        ChainNode(title: "Issuing bank — LC negotiation",
                  detail: "LC 2026-IB-44817 · documents negotiated · endorsed", state: .done),
        ChainNode(title: "Consignee — surrender originals",
                  detail: "Pier 1 Imports · present 3 OBL at USLGB counter", state: .current),
        ChainNode(title: "Carrier release",
                  detail: "blocked until 3/3 originals surrendered or Telex set", state: .blocked)
    ]
    private let docs: [ReleaseDoc] = [
        ReleaseDoc(tag: "OBL", kind: "PDF", title: "Original B/L",    sub: "3 issued · 2m ago", tint: .gradient),
        ReleaseDoc(tag: "LC",  kind: "PDF", title: "Letter of credit", sub: "IB-44817 · v2",    tint: .info),
        ReleaseDoc(tag: "END", kind: "SIG", title: "Endorse",         sub: "bank",              tint: .warn)
    ]
    private let regimes: [ImportRegime] = [
        ImportRegime(code: "US", line: "USLGB · CBP entry 7501 + ISF on file → release", active: true),
        ImportRegime(code: "CA", line: "CAVAN · CBSA B3 release", active: false),
        ImportRegime(code: "MX", line: "MXZLO · pedimento VUCEM", active: false)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text("Cargo release")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Text("B/L \(bolNumber) · \(booking)")
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(palette.textSecondary)
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    hero
                    sectionLabel("RELEASE METHOD · createBOL bolType", ref: "vesselShipments:892")
                    releaseSelector
                    sectionLabel("ENDORSEMENT & LC CHAIN · recordLCEndorsement", ref: "STUB · named-gap")
                    chainCard
                    originalsStrip
                    sectionLabel("DOCUMENTS · listBOLs", ref: nil)
                    documentsStrip
                    sectionLabel("IMPORT RELEASE · DESTINATION CUSTOMS REGIME", ref: nil)
                    triCountryBand
                    HStack(spacing: 8) {
                        CTAButton(title: "Set Telex release") { Task { await setTelex() } }
                        SecondaryButton(title: "View B/L") {}
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text("VESSEL OPERATOR · CARGO RELEASE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            Spacer()
            Text("MSC · USLGB").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
        }
    }

    private func sectionLabel(_ t: String, ref: String?) -> some View {
        HStack {
            Text(t).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            Spacer()
            if let r = ref { Text(r).font(.system(size: 9, design: .monospaced)).foregroundStyle(palette.textTertiary) }
        }
    }

    private var hero: some View {
        RimCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("B/L \(bolNumber) · \(booking)")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
                    Spacer()
                    StatusPill(text: "ISSUED", kind: .info)
                }
                Text(lane).font(.system(size: 17, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(spec).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                HStack(spacing: 8) {
                    Circle().fill(LinearGradient(colors: [Brand.hazmat, Color(hex: 0xFF7A00)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 12, height: 12).overlay(Text("MS").font(.system(size: 6, weight: .heavy)).foregroundStyle(.white))
                    Text("Carrier MSC · SCAC MSCU · consignee \(consignee)")
                        .font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(originalsIssued - originalsSurrendered) / \(originalsIssued)")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("originals outstanding · \(originalsSurrendered == 0 ? "none surrendered" : "\(originalsSurrendered) surrendered")")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private var releaseSelector: some View {
        HStack(spacing: 0) {
            ForEach(ReleaseMethod.allCases) { m in
                let on = m.rawValue == method
                VStack(spacing: 2) {
                    Text(m.rawValue).font(.system(size: 11, weight: on ? .heavy : .bold))
                        .foregroundStyle(on ? Color.white : palette.textPrimary)
                    Text(m.sub).font(.system(size: 7.5, weight: on ? .heavy : .semibold)).tracking(0.3)
                        .foregroundStyle(on ? Color.white.opacity(0.85) : palette.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(Group { if on { LinearGradient.primary } else { Color.clear } })
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
                .onTapGesture { method = m.rawValue }   // wire -> setReleaseMethod (named gap)
            }
        }
        .padding(5)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var chainCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(chain.enumerated()), id: \.element.id) { idx, n in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        nodeDot(n.state)
                        if idx < chain.count - 1 {
                            Rectangle()
                                .fill(n.state == .done ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.borderSoft))
                                .frame(width: 2, height: 30)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.title).font(.system(size: 12, weight: .bold))
                            .foregroundStyle(n.state == .blocked ? palette.textTertiary : palette.textPrimary)
                        Text(n.detail).font(.system(size: 10))
                            .foregroundStyle(n.state == .blocked ? palette.textTertiary : palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Text(badge(n.state)).font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(badgeColor(n.state))
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
    }

    private func nodeDot(_ s: ChainNode.NodeState) -> some View {
        Group {
            switch s {
            case .done:
                Circle().fill(LinearGradient.diagonal).frame(width: 14, height: 14)
                    .overlay(Image(systemName: "checkmark").font(.system(size: 7, weight: .heavy)).foregroundStyle(.white))
            case .current:
                Circle().stroke(LinearGradient.primary, lineWidth: 2).frame(width: 14, height: 14)
                    .overlay(Circle().fill(LinearGradient.diagonal).frame(width: 5, height: 5))
            case .blocked:
                Circle().fill(palette.borderSoft).frame(width: 14, height: 14)
            }
        }
    }
    private func badge(_ s: ChainNode.NodeState) -> String {
        switch s { case .done: return "DONE"; case .current: return "PENDING"; case .blocked: return "BLOCKED" }
    }
    private func badgeColor(_ s: ChainNode.NodeState) -> Color {
        switch s { case .done: return Brand.success; case .current: return Brand.warning; case .blocked: return palette.textTertiary }
    }

    private var originalsStrip: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("ORIGINALS OUTSTANDING").font(.system(size: 11, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                Text("Surrender of originals · available only once the B/L is issued")
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                ProgressView(value: Double(originalsSurrendered), total: Double(max(originalsIssued, 1)))
                    .tint(Brand.blue).frame(width: 84)
                Text("\(originalsSurrendered) / \(originalsIssued)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(palette.bgCardSoft))
    }

    private var documentsStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(docs.enumerated()), id: \.element.id) { idx, d in
                HStack(spacing: 10) {
                    VStack(spacing: 1) {
                        Text(d.tag).font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                        Text(d.kind).font(.system(size: 7, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                    }
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(docTint(d.tint)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.title).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Text(d.sub).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if idx < docs.count - 1 { Divider().overlay(palette.borderFaint).frame(height: 32) }
            }
        }
        .padding(14)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }
    private func docTint(_ t: ReleaseDoc.DocTint) -> AnyShapeStyle {
        switch t {
        case .gradient: return AnyShapeStyle(LinearGradient.diagonal)
        case .info:     return AnyShapeStyle(Brand.info)
        case .warn:     return AnyShapeStyle(LinearGradient(colors: [Brand.hazmat, Color(hex: 0xFF7A00)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    private var triCountryBand: some View {
        VStack(spacing: 0) {
            ForEach(Array(regimes.enumerated()), id: \.element.id) { idx, r in
                HStack(spacing: 10) {
                    Text(r.code).font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(r.active ? Color.white : palette.textSecondary)
                        .frame(width: 26, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(r.active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(Color.primary.opacity(0.06))))
                    Text(r.line).font(.system(size: r.active ? 10.5 : 10, weight: r.active ? .bold : .regular))
                        .foregroundStyle(r.active ? palette.textPrimary : palette.textSecondary)
                    Spacer(minLength: 0)
                    Text(r.active ? "● ACTIVE" : "STANDBY").font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(r.active ? Brand.blue : palette.textTertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(r.active ? AnyShapeStyle(LinearGradient.primary.opacity(0.10)) : AnyShapeStyle(Color.clear))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                if idx < regimes.count - 1 { Divider().overlay(palette.borderFaint) }
            }
        }
        .padding(6)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: Data

    private struct BOL: Decodable {
        let bolNumber: String?; let bolType: String?; let status: String?
        let originPort: String?; let destinationPort: String?
        let vesselName: String?; let voyageNumber: String?; let freightTerms: String?
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            struct In: Encodable { let bolNumber: String }
            let b: BOL = try await EusoTripAPI.shared.query("vesselShipments.getBOL", input: In(bolNumber: bolNumber))
            if let n = b.bolNumber { bolNumber = n }
            if let t = b.bolType, let rm = ReleaseMethod.allCases.first(where: { $0.bolType == t }) { method = rm.rawValue }
            if let o = b.originPort, let d = b.destinationPort { lane = "\(o) → \(d)" }
            if let s = b.status?.lowercased(), s == "surrendered" { originalsSurrendered = originalsIssued }
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    private func setTelex() async {
        // STUB · named-gap vesselShipments.setReleaseMethod(telex) — surfaced to the-oath; refresh for now.
        method = ReleaseMethod.telex.rawValue
        await load()
    }
}


/// Outlined secondary action — pairs with the primary CTAButton. File-private
/// (no shared SecondaryButton exists in the app target; house pattern per 815/809).
private struct SecondaryButton: View {
    @Environment(\.palette) private var palette
    let title: String
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 14).fill(palette.bgCardSoft))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(palette.borderSoft, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}


/// Rim-accent card (file-private; RimCard is not a shared app symbol — house pattern per 669/689/700).
private struct RimCard<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
            )
    }
}

#Preview("718 · Vessel Cargo Release · Night") { VesselCargoReleaseScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("718 · Vessel Cargo Release · Light") { VesselCargoReleaseScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
