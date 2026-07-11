//
//  719_VesselEBL.swift
//  EusoTrip — Vessel Operator · DCSA Electronic Bill of Lading (eBL).
//
//  Verbatim SwiftUI port of "719 Vessel DCSA eBL.svg" (Dark + Light).
//  Archetype: TITLE-CUSTODY / interoperability-ledger — a hero eBL identity +
//  possession token, a DCSA cross-platform interoperability rail, a hash-chained
//  transfer-of-title block ledger, and an issuing-jurisdiction band. Nav:
//  SHIPMENTS current.
//
//  WIRING (line-confirmed on disk, server/routers/vesselShipments.ts):
//    getBOL   EXISTS vesselShipments.ts:944 (hero eBL identity + holder · REAL).
//    listBOLs EXISTS vesselShipments.ts:961 (document context · REAL). The
//    ledger blocks correspond to blockchainAuditTrail rows written by createBOL
//    (vessel.bol_issued) / surrenderBOL (vessel.bol_surrendered).
//  STUB · named-gap (surfaced to the-oath): DCSA cross-platform transfer-of-title
//    has no procedure/column today (no titleHolderId / possessionToken /
//    dcsaPlatform) → vesselShipments.transferTitle {bolId,toPartyId,platform,
//    confirm} (irreversible · human-gated · audited) and
//    vesselShipments.getTitleChain {bolId} → {blocks[]}. The interoperability
//    rail + jurisdiction band are regulatory reference facts, not fabricated
//    data. transportMode=vessel; tri-country US·CA·MX.
//

import SwiftUI

private struct BOL719: Decodable {
    let bolNumber: String?; let bolType: String?; let status: String?
    let originPort: String?; let destinationPort: String?; let vesselName: String?
}

struct VesselEBLScreen: View {
    let theme: Theme.Palette
    var bolNumber: String = "MSCUSH6840517"

    var body: some View {
        Shell(theme: theme) {
            VesselEBLBody(bolNumber: bolNumber)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",              isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselEBLBody: View {
    @Environment(\.palette) private var palette
    let bolNumber: String

    @State private var bol: BOL719? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    private struct TitleBlock { let n: Int; let title: String; let sub: String; let hash: String; let current: Bool }
    private let blocks: [TitleBlock] = [
        .init(n: 4, title: "Holder · Eusorone Technologies", sub: "issued to order · 2m ago", hash: "0xA7C4…41E7", current: true),
        .init(n: 3, title: "Endorsed · Issuing bank (LC)", sub: "negotiated · 3h ago", hash: "0x91DE…77B2", current: false),
        .init(n: 2, title: "Endorsed · Shipper (blank)", sub: "to order · 1d ago", hash: "0x4F2A…C0E9", current: false),
        .init(n: 1, title: "Genesis · eBL issued by MSC", sub: "carrier · 2d ago", hash: "0x0000…GENS", current: false),
    ]
    private let platforms: [(String, Bool)] = [("WaveBL", true), ("CargoX", false), ("GSBN", false), ("IQAX", false)]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if loading {
                    gapCard("Loading electronic B/L…", "getBOL · \(bolNumber)", warn: false)
                } else if let err = loadError {
                    gapCard("eBL unavailable", err, warn: true)
                } else {
                    heroCard
                    interopRail
                    titleLedger
                    jurisdictionBand
                    standardsBadges
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s2)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("✦ VESSEL OPERATOR · DCSA eBL").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("MSC · DCSA").font(EType.mono(.micro)).tracking(0.6).foregroundStyle(palette.textTertiary)
            }
            Text("Electronic B/L").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
        }
    }

    private var heroCard: some View {
        RimCard719 {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("eBL \(bol?.bolNumber ?? bolNumber) · DCSA 3.0").font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text("ISSUED · ON-CHAIN").font(.system(size: 8.5, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(palette.bgCardSoft))
                }.padding(.bottom, 14)
                Text("\(bol?.originPort ?? "Shanghai CNSHA") → \(bol?.destinationPort ?? "Long Beach USLGB")")
                    .font(.system(size: 16, weight: .heavy)).foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                Text("Negotiable original eBL · transfer of title").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary).padding(.top, 4)
                HStack(spacing: 8) {
                    Circle().fill(Brand.rail).frame(width: 22, height: 22).overlay(Text("MSC").font(.system(size: 7, weight: .heavy)).foregroundStyle(.white))
                    Text("Carrier MSC · SCAC MSCU · holder Eusorone (DU)").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
                }.padding(.top, 12)
                HStack {
                    Text("0xA7C4…41E7").font(.system(size: 17, weight: .heavy, design: .monospaced)).foregroundStyle(LinearGradient.primary)
                    Spacer()
                    Text("POSSESSION TOKEN").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(palette.textTertiary)
                }.padding(.top, 12)
            }
        }
    }

    private var interopRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("DCSA eBL INTEROPERABILITY")
                Spacer()
                Text("STUB · transferTitle").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("Title token portable across conformant platforms").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(palette.textPrimary)
                HStack(spacing: 0) {
                    ForEach(Array(platforms.enumerated()), id: \.offset) { idx, p in
                        VStack(spacing: 6) {
                            ZStack {
                                if p.1 {
                                    Circle().fill(LinearGradient.primary).frame(width: 24, height: 24)
                                    Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                                } else {
                                    Circle().fill(palette.bgCard).overlay(Circle().strokeBorder(palette.borderSoft, lineWidth: 1)).frame(width: 24, height: 24)
                                    Circle().fill(palette.textTertiary).frame(width: 6, height: 6)
                                }
                            }
                            Text(p.0).font(.system(size: 9.5, weight: p.1 ? .heavy : .semibold)).foregroundStyle(p.1 ? palette.textPrimary : palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        if idx < platforms.count - 1 {
                            Rectangle().fill(idx == 0 ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.borderSoft)).frame(height: 3).offset(y: -10)
                        }
                    }
                }
            }
            .padding(Space.s4).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private var titleLedger: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("TRANSFER-OF-TITLE LEDGER · blockchainAuditTrail")
                Spacer()
                Text("getTitleChain · STUB").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 0) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { idx, b in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(b.current ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCardSoft))
                                    .frame(width: 24, height: 24)
                                Text("\(b.n)").font(.system(size: 11, weight: .heavy)).foregroundStyle(b.current ? .white : palette.textTertiary)
                            }
                            if idx < blocks.count - 1 { Rectangle().fill(palette.borderSoft).frame(width: 2, height: 30) }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(b.title).font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                                Spacer()
                                Text(b.hash).font(EType.mono(.micro)).foregroundStyle(b.current ? Color(hex: 0x5AB0FF) : palette.textTertiary)
                            }
                            Text(b.sub).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(palette.textSecondary)
                        }
                        .padding(.bottom, idx < blocks.count - 1 ? 8 : 0)
                    }
                }
            }
            .padding(Space.s4).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private var jurisdictionBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("ISSUING-JURISDICTION · eBL legal recognition")
            VStack(spacing: 8) {
                jurisdictionRow("US", "US · UETA / E-SIGN 2000 · MLETR pending", "ACTIVE", Brand.success, active: true)
                divider
                jurisdictionRow("CA", "CA · UECA · PIPEDA Part 2", "STANDBY", palette.textTertiary, active: false)
                divider
                jurisdictionRow("MX", "MX · Cód. Comercio Art. 89 · NOM-151", "STANDBY", palette.textTertiary, active: false)
            }
            .padding(Space.s4).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }
    private func jurisdictionRow(_ cc: String, _ text: String, _ state: String, _ color: Color, active: Bool) -> some View {
        HStack(spacing: 10) {
            Text(cc).font(.system(size: 8.5, weight: .heavy)).foregroundStyle(active ? .white : palette.textSecondary)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.tintNeutral)))
            Text(text).font(.system(size: 10.5, weight: active ? .heavy : .semibold)).foregroundStyle(active ? palette.textPrimary : palette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Text(state).font(.system(size: 8, weight: .heavy)).foregroundStyle(color)
        }
        .padding(.vertical, 8)
    }

    private var standardsBadges: some View {
        HStack(spacing: 8) {
            ForEach(["DCSA eBL 3.0", "MLETR-aligned", "Group of Nine"], id: \.self) { s in
                Text(s).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.bgCard))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            }
        }
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Transfer title",
                      action: { /* STUB · vesselShipments.transferTitle — irreversible · human-gated · audited */ },
                      trailingIcon: "arrow.right")
            Button {
                // View eBL — opens the document (routed by the nav controller).
            } label: {
                Text("View eBL").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 140, minHeight: 48).background(palette.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
    }
    private var divider: some View { Rectangle().fill(palette.borderFaint).frame(height: 1) }
    private func gapCard(_ title: String, _ detail: String, warn: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: warn ? "exclamationmark.triangle.fill" : "link")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(warn ? Brand.danger : palette.textTertiary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(detail).font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(warn ? Brand.danger.opacity(0.4) : palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func load() async {
        loading = true; loadError = nil
        struct BOLIn: Encodable { let bolNumber: String }
        do {
            let b: BOL719? = try await EusoTripAPI.shared.query("vesselShipments.getBOL", input: BOLIn(bolNumber: bolNumber))
            self.bol = b
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

private struct RimCard719<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient(colors: [Brand.blue.opacity(0.95), Brand.magenta.opacity(0.95)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 18.5, style: .continuous).fill(palette.bgCard).padding(1.5)
            content().padding(Space.s5)
        }.frame(maxWidth: .infinity)
    }
}

#Preview("719 · Vessel DCSA eBL · Night") {
    VesselEBLScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("719 · Vessel DCSA eBL · Light") {
    VesselEBLScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
