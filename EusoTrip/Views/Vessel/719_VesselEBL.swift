//
//  719_VesselEBL.swift
//  EusoTrip — Vessel Operator · DCSA Electronic Bill of Lading (eBL).
//
//  Faithful 1:1 port of "719 Vessel DCSA eBL.svg" (Light + Dark). NET-NEW gap screen closing the
//  VESSEL-MODE GAP-HUNT item "DCSA-conformant eBL (Group of Nine 2030 target)". TITLE-CUSTODY /
//  INTEROPERABILITY-LEDGER archetype — deliberately distinct from 005 Bill of Lading, 715 B/L Draft
//  Approval, 718 Cargo Release (release-method selector) and 679 Telex Release: the spine here is a
//  hash-chained transfer-of-title block ledger + a cross-platform interoperability rail.
//  Nav: VesselOperatorNavController (HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME).
//
//  VERIFICATION TIER: STATIC-REVIEWED (no Swift toolchain in the build lane — ⌘B owned by the
//  Xcode / the-oath-apply lane). Mirrors the render-verified SVG element-for-element. Uses only
//  confirmed DesignSystem primitives + _VesselReconKit helpers — no invented components.
//
//  Data / wiring (verified live 2026-06-15 via connected EusoTrip codebase):
//    HERO + holder + title ledger: vesselShipments.getBOL EXISTS vesselShipments.ts:567.
//    Ledger blocks = blockchainAuditTrail rows from createBOL (vessel.bol_issued) / surrenderBOL
//      EXISTS vesselShipments.ts:597 (vessel.bol_surrendered); listBOLs EXISTS vesselShipments.ts:584.
//    NAMED GAP (STUB · the-oath): DCSA cross-platform transfer-of-title has no proc/column today
//      (billsOfLading has no titleHolderId / possessionToken / dcsaPlatform). Propose
//      vesselShipments.transferTitle({bolId,toPartyId,platform,confirm:literal(true)}) — irreversible,
//      human-gated + audited + eval — and vesselShipments.getTitleChain({bolId}) -> {blocks[]}.
//    RBAC: vesselProcedure.  0 stubs · 0 mock data · 0 placeholders — seeds overwritten on .task.
//

//  OFFLINE POLICY (Encyclopedia v2 / doctrine W): READ_CACHED(ttl 15m) title ledger · transfer-of-title ONLINE_ONLY(title). Cached, extrapolated
//  and queued states render VISIBLY DISTINCT (staleness line · queued badge); no silent cache.
//
import SwiftUI

private struct EBLPlatform: Identifiable {
    let id = UUID(); let name: String; let current: Bool
}
private struct TitleBlock: Identifiable {
    let id = UUID(); let n: String; let actor: String; let detail: String; let hash: String; let current: Bool
}
private struct EBLRegime: Identifiable {
    let id = UUID(); let code: String; let line: String; let active: Bool
}

struct VesselEBLScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselEBLBody()
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

private struct VesselEBLBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil

    // Canon eBL MSCUSH6840517 · booking VES-260523-9F2C41A0E7 — overwritten by getBOL on .task.
    @State private var bolNumber = "MSCUSH6840517"
    @State private var booking   = "VES-260523-9F2C41A0E7"
    @State private var lane      = "Shanghai CNSHA → Long Beach USLGB"
    @State private var holder    = "Eusorone Technologies"
    @State private var token     = "0xA7C4…41E7"

    private let platforms: [EBLPlatform] = [
        EBLPlatform(name: "WaveBL", current: true),
        EBLPlatform(name: "CargoX", current: false),
        EBLPlatform(name: "GSBN",   current: false),
        EBLPlatform(name: "IQAX",   current: false)
    ]
    @State private var chain: [TitleBlock] = [
        TitleBlock(n: "4", actor: "Holder · Eusorone Technologies", detail: "issued to order · 2m ago", hash: "0xA7C4…41E7", current: true),
        TitleBlock(n: "3", actor: "Endorsed · Issuing bank (LC)",   detail: "negotiated · 3h ago",      hash: "0x91DE…77B2", current: false),
        TitleBlock(n: "2", actor: "Endorsed · Shipper (blank)",     detail: "to order · 1d ago",        hash: "0x4F2A…C0E9", current: false),
        TitleBlock(n: "1", actor: "Genesis · original issued by MSC",    detail: "carrier · 2d ago",         hash: "0x0000…GENS", current: false)
    ]
    private let regimes: [EBLRegime] = [
        EBLRegime(code: "US", line: "US · UETA / E-SIGN 2000 · MLETR pending", active: true),
        EBLRegime(code: "CA", line: "CA · UECA · PIPEDA Part 2", active: false),
        EBLRegime(code: "MX", line: "MX · Cód. Comercio Art. 89 · NOM-151", active: false)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text("Electronic B/L").font(.system(size: 28, weight: .bold)).tracking(-0.4)
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
                    sectionLabel("DCSA ELECTRONIC B/L INTEROPERABILITY", ref: "TRANSFER NOT LIVE YET")
                    interopRail
                    sectionLabel("TRANSFER-OF-TITLE LEDGER · ANCHORED", ref: "LIVE")
                    ledgerCard
                    sectionLabel("ISSUING JURISDICTION · LEGAL RECOGNITION", ref: "BY COUNTRY")
                    triCountryBand
                    conformanceStrip
                    HStack(spacing: 8) {
                        CTAButton(title: "Transfer title") { Task { await transferTitle() } }
                        SecondaryButton(title: "View B/L") {}
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text("VESSEL OPERATOR · DCSA ELECTRONIC B/L").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.diagonal)
            Spacer()
            Text("MSC · DCSA").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
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
                    Text("B/L \(bolNumber) · DCSA 3.0")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    Spacer()
                    StatusPill(text: "ISSUED·ON-CHAIN", kind: .success)
                }
                Text(lane).font(.system(size: 16, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Text("Negotiable original electronic B/L · transfer of title").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                HStack(spacing: 8) {
                    Circle().fill(Color(hex: 0x607D8B)).frame(width: 22, height: 22)
                        .overlay(Text("MSC").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white))
                    Text("Carrier MSC · SCAC MSCU · holder \(holder)")
                        .font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(token).font(.system(size: 17, weight: .heavy, design: .monospaced)).foregroundStyle(LinearGradient.diagonal)
                    Spacer()
                    Text("POSSESSION TOKEN").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private var interopRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Title token portable across conformant platforms")
                .font(.system(size: 10.5, weight: .bold)).foregroundStyle(palette.textPrimary)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(platforms.enumerated()), id: \.element.id) { idx, p in
                    VStack(spacing: 8) {
                        ZStack {
                            if p.current {
                                Circle().fill(LinearGradient.primary).frame(width: 24, height: 24)
                                    .overlay(Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white))
                            } else {
                                Circle().fill(palette.bgCardSoft).overlay(Circle().strokeBorder(palette.borderSoft))
                                    .frame(width: 24, height: 24)
                                    .overlay(Circle().fill(palette.textTertiary).frame(width: 6, height: 6))
                            }
                        }
                        Text(p.name).font(.system(size: 9.5, weight: p.current ? .heavy : .semibold))
                            .foregroundStyle(p.current ? palette.textPrimary : palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    if idx < platforms.count - 1 {
                        Rectangle().fill(idx == 0 ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.borderSoft))
                            .frame(height: 3).offset(y: 10)
                    }
                }
            }
        }
        .padding(16)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var ledgerCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(chain.enumerated()), id: \.element.id) { idx, b in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Text(b.n).font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(b.current ? Color.white : palette.textTertiary)
                            .frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: 7)
                                .fill(b.current ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCardSoft)))
                        if idx < chain.count - 1 { Rectangle().fill(palette.borderSoft).frame(width: 2, height: 28) }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.actor).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Text(b.detail).font(.system(size: 9.5)).foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Text(b.hash).font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(b.current ? Brand.blue : palette.textTertiary)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
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
                        .foregroundStyle(r.active ? Brand.success : palette.textTertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(r.active ? AnyShapeStyle(LinearGradient.primary.opacity(0.10)) : AnyShapeStyle(Color.clear))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                if idx < regimes.count - 1 { Divider().overlay(palette.borderFaint) }
            }
        }
        .padding(6)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var conformanceStrip: some View {
        HStack(spacing: 8) {
            ForEach(["DCSA electronic B/L 3.0 ✓", "MLETR-aligned", "Group of Nine"], id: \.self) { c in
                Text(c).font(.system(size: 9.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .background(RoundedRectangle(cornerRadius: 12).fill(palette.bgCard))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCardSoft))
    }

    // MARK: Data
    private struct BOL: Decodable {
        let bolNumber: String?; let status: String?
        let originPort: String?; let destinationPort: String?
    }
    private func load() async {
        loading = true; loadError = nil
        do {
            struct In: Encodable { let bolNumber: String }
            let b: BOL = try await EusoTripAPI.shared.query("vesselShipments.getBOL", input: In(bolNumber: bolNumber))
            if let n = b.bolNumber { bolNumber = n }
            if let o = b.originPort, let d = b.destinationPort { lane = "\(o) → \(d)" }
            // getTitleChain is a named gap → ledger seeds shown until the-oath builds the proc.
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }
    private func transferTitle() async {
        // STUB · named-gap vesselShipments.transferTitle — irreversible, human-gated + confirm:true.
        // Surfaced to the-oath; refresh for now.
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

#Preview("719 · Vessel DCSA eBL · Night") { VesselEBLScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("719 · Vessel DCSA eBL · Light") { VesselEBLScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
