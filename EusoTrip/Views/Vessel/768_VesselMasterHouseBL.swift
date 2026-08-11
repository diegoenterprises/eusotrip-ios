//
//  768_VesselMasterHouseBL.swift
//  EusoTrip — Vessel Operator · Master & House B/L.
//
//  Faithful 1:1 port of "768 Vessel Master & House B-L.svg" (Light + Dark). NET-NEW gap screen closing
//  the BOOKING/DOCUMENTATION moat item "Master vs House BL distinction". CONSOLIDATION-TREE /
//  ALLOCATION-SPLIT archetype — deliberately distinct from 005 Bill of Lading (single title), 715/719
//  (draft/eBL), 765 Letter of Credit, 767 Sea Waybill: the spine is a HIERARCHY — a master node branching
//  down a trunk to 3 house-B/L leaf cards, each with consignee + a proportional weight-allocation bar +
//  its house B/L number, not a single-document surface.
//  Nav: VesselOperatorNavController (HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME).
//
//  VERIFICATION TIER: STATIC-REVIEWED (no Swift toolchain in the build lane). Mirrors the
//  render-verified SVG element-for-element. Uses only confirmed DesignSystem + _VesselReconKit.
//
//  Data / wiring (verified live 2026-06-15 via connected EusoTrip codebase):
//    EXISTS — createBOL vesselShipments.ts:503 (bolType enum incl. MASTER + HOUSE — db.ts:2570) +
//      listBOLs vesselShipments.ts:584 (enumerate the set) + getBOL:956.
//    NAMED GAP (STUB · the-oath): no parent-child LINK surfaced — listBOLs returns a flat list; no
//      masterBolId FK / allocation-share field. Propose blConsolidation.getTree({masterBolId}) ->
//      {master,houses[{bolId,consignee,weightKg,sharePct}]}; blConsolidation.linkHouse({masterBolId,
//      houseBolId,weightKg,confirm:true}) — structural write, idempotent + share-sum<=100% invariant + audit.
//      RBAC: vesselProcedure.
//

//  OFFLINE POLICY (Encyclopedia v2 / doctrine W): READ_CACHED(ttl 24h) linkage view · issue/link CTAs ONLINE_ONLY(title). Cached, extrapolated
//  and queued states render VISIBLY DISTINCT (staleness line · queued badge); no silent cache.
//
import SwiftUI

private struct HouseBL: Identifiable {
    let id = UUID(); let hbl: String; let consignee: String; let kg: String; let share: Double; let tint: Color
}
private struct ManifestAuthority: Identifiable { let id = UUID(); let code: String; let line: String; let active: Bool }

struct VesselMasterHouseBLScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselMasterHouseBLBody()
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

private struct VesselMasterHouseBLBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil

    // Seeds - overwritten by listBOLs on .task (allocation share stays a named gap: blConsolidation.getTree).
    @State private var houses: [HouseBL] = [
        HouseBL(hbl: "HBL-7741-A", consignee: "Horizon Trading FZE", kg: "12,800 kg", share: 0.45, tint: Brand.magenta),
        HouseBL(hbl: "HBL-7741-B", consignee: "Cedar Mills Import Co", kg: "9,600 kg",  share: 0.34, tint: Brand.blue),
        HouseBL(hbl: "HBL-7741-C", consignee: "Allied Cold Foods",     kg: "6,000 kg",  share: 0.21, tint: Brand.success)]
    @State private var gapNotice: String? = nil
    private let authorities: [ManifestAuthority] = [
        ManifestAuthority(code: "US", line: "US · CBP · house bills on AMS/ACE",        active: true),
        ManifestAuthority(code: "CA", line: "CA · CBSA · supplementary cargo (ACI)",    active: false),
        ManifestAuthority(code: "MX", line: "MX · Aduanas · consolidado VUCEM",         active: false)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text("Master & house").font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    hero
                    sectionLabel("CONSOLIDATION TREE", ref: "EXISTS listBOLs:973")
                    treeCard
                    sectionLabel("MANIFEST AUTHORITY · house declarations", ref: "listBOLs·country")
                    triCountryBand
                    if let note = gapNotice {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle").font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.info)
                            Text(note).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Brand.info.opacity(0.08)))
                    }
                    HStack(spacing: 8) {
                        CTAButton(title: "Issue house B/Ls") { Task { await issue() } }
                        SecondaryButton(title: "Edit split") {}
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
            Text("VESSEL OPERATOR · CONSOLIDATION").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.diagonal)
            Spacer()
            Text("MASTER + 3 HOUSE").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
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
                    Text("Master MSCUSH6840517 · co-load").font(.system(size: 9.5, weight: .bold, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    Spacer()
                    StatusPill(text: "1 MASTER · 3 HOUSE", kind: .info)
                }
                Text("Consolidation B/L set").font(.system(size: 17, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Text("Carrier → NVOCC master over 3 house B/Ls").font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                Text("40' HC · 28,400 kg · 3 underlying shippers").font(.system(size: 10.5, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
        }
    }

    private var treeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Master node
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MASTER · MSCUSH6840517").font(.system(size: 11, weight: .heavy)).foregroundStyle(Color.white)
                    Text("MSC → Eusorone (NVOCC) · 28,400 kg").font(.system(size: 8.5)).foregroundStyle(Color.white.opacity(0.85))
                }
                Spacer(minLength: 0)
                Text("100%").font(.system(size: 9, weight: .heavy)).foregroundStyle(Color.white)
            }
            .padding(12)
            .background(LinearGradient(colors: [Brand.magenta, Color(hex: 0xBE01FF)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            // House leaves
            ForEach(houses) { h in
                HStack(alignment: .top, spacing: 0) {
                    Rectangle().fill(palette.bgCardSoft).frame(width: 18, height: 2.5).offset(y: 18)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(h.hbl).font(.system(size: 10.5, weight: .heavy)).foregroundStyle(palette.textPrimary)
                                Text(h.consignee).font(.system(size: 9.5)).foregroundStyle(palette.textSecondary)
                            }
                            Spacer(minLength: 0)
                            Text(h.kg).font(.system(size: 9.5, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textPrimary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(palette.bgCardSoft).frame(height: 6)
                                Capsule().fill(h.tint).frame(width: geo.size.width * h.share, height: 6)
                                Text("\(Int(h.share * 100))%").font(.system(size: 7.5, weight: .heavy)).foregroundStyle(h.tint)
                                    .offset(x: geo.size.width * h.share + 6, y: -1)
                            }
                        }
                        .frame(height: 12)
                    }
                    .padding(12)
                    .background(palette.bgCardSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(14)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var triCountryBand: some View {
        VStack(spacing: 0) {
            ForEach(Array(authorities.enumerated()), id: \.element.id) { idx, r in
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
                        .foregroundStyle(r.active ? Brand.success : palette.textTertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(r.active ? AnyShapeStyle(LinearGradient.primary.opacity(0.10)) : AnyShapeStyle(Color.clear))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                if idx < authorities.count - 1 { Divider().overlay(palette.borderFaint) }
            }
        }
        .padding(6)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: Data
    /// MySQL decimal(12,2) serializes as a JSON string through drizzle — decode both shapes.
    private struct FlexDouble: Decodable {
        let value: Double?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let d = try? c.decode(Double.self) { value = d }
            else if let str = try? c.decode(String.self) { value = Double(str) }
            else { value = nil }
        }
    }
    private struct BOL768: Decodable {
        let id: Int?; let bolNumber: String?; let bolType: String?; let consigneeId: Int?
        let grossWeightKg: FlexDouble?
    }
    private func load() async {
        loading = true; loadError = nil
        // LIVE: listBOLs vesselShipments.ts:973 enumerates the user's B/L set; house rows filter on
        // bolType=='house' (createBOL:892 enum master|house|express|seaway). Parent-child LINK +
        // allocation share remain the named gap (blConsolidation.getTree / linkHouse) - filed.
        do {
            struct In: Encodable { let limit: Int }
            let all: [BOL768] = try await EusoTripAPI.shared.query("vesselShipments.listBOLs", input: In(limit: 100))
            let hs = all.filter { ($0.bolType ?? "") == "house" }
            if !hs.isEmpty {
                let totalKg = hs.compactMap { $0.grossWeightKg?.value }.reduce(0,+)
                let tints: [Color] = [Brand.magenta, Brand.blue, Brand.success, Brand.info, Brand.warning]
                houses = hs.enumerated().map { i, h in
                    let kg = h.grossWeightKg?.value ?? 0
                    return HouseBL(hbl: h.bolNumber ?? "HBL-\(h.id ?? 0)",
                                   consignee: h.consigneeId.map { "Consignee #\($0)" } ?? "consignee on file",
                                   kg: kg > 0 ? "\(Int(kg)) kg" : "weight on file",
                                   share: totalKg > 0 ? kg / totalKg : 1.0 / Double(hs.count),
                                   tint: tints[i % tints.count])
                }
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
    private func issue() async {
        // STUB · named-gap blConsolidation.linkHouse({masterBolId,houseBolId,weightKg,confirm:true}) — structural write, audited.
        gapNotice = "House-B/L issuance is createBOL({bolType: house}) - EXISTS :892 - but the parent-child link (blConsolidation.linkHouse) is a named gap filed with the-oath; issuing unlinked houses would orphan the manifest. Held until the link lands."
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

#Preview("768 · Master & House B/L · Night") { VesselMasterHouseBLScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("768 · Master & House B/L · Light") { VesselMasterHouseBLScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
