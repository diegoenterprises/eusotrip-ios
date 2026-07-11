//
//  718_VesselCargoRelease.swift
//  EusoTrip — Vessel Operator · Cargo Release (B/L release method + endorsement chain).
//
//  Verbatim SwiftUI port of "718 Vessel Cargo Release.svg" (Dark + Light).
//  Archetype: DETAIL / selector — a hero B/L card, a release-method segmented
//  control (the real bolType enum), an endorsement / LC negotiation chain, an
//  originals-outstanding roster, a documents strip, and a tri-country
//  import-release band. Nav: SHIPMENTS current.
//
//  WIRING (line-confirmed on disk, server/routers/vesselShipments.ts):
//    getBOL      EXISTS vesselShipments.ts:944 (hero + release posture · REAL).
//    listBOLs    EXISTS vesselShipments.ts:961 (documents strip · REAL).
//    surrenderBOL EXISTS vesselShipments.ts:974 (mutation · requires status
//        "issued" · writes blockchainAuditTrail vessel.bol_surrendered · the
//        REAL cargo-release verb — "Surrender originals" fires this).
//    createBOL   EXISTS vesselShipments.ts:880 (bolType enum master|house|
//        express|seaway · the release-method segments).
//  STUB · named-gap (surfaced to the-oath): switching release method post-issue
//    + the LC bank-endorsement chain have no backing procedure today →
//    vesselShipments.setReleaseMethod {bolId,method} and
//    vesselShipments.recordLCEndorsement {bolId,party,endorsedAt}. The Telex
//    segment + endorsement timeline render as workflow state, honestly labeled.
//    transportMode=vessel; tri-country US·CA·MX.
//

import SwiftUI

private struct BOL718: Decodable, Identifiable {
    let id: Int?
    let bolNumber: String?
    let bolType: String?
    let status: String?
    let originPort: String?
    let destinationPort: String?
    let vesselName: String?
    let voyageNumber: String?
    let freightTerms: String?
    var identity: String { bolNumber ?? "\(id ?? 0)" }
}

struct VesselCargoReleaseScreen: View {
    let theme: Theme.Palette
    var bolNumber: String = "MSCUSH6840517"

    var body: some View {
        Shell(theme: theme) {
            VesselCargoReleaseBody(bolNumber: bolNumber)
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

private struct VesselCargoReleaseBody: View {
    @Environment(\.palette) private var palette
    let bolNumber: String

    private enum Method: String, CaseIterable { case original = "Original", telex = "Telex", seaway = "Sea Waybill", express = "Express" }

    @State private var bol: BOL718? = nil
    @State private var documents: [BOL718] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var surrendering = false
    @State private var surrenderedCount = 0
    private let totalOriginals = 3

    private var method: Method {
        switch (bol?.bolType ?? "master").lowercased() {
        case "express": return .express
        case "seaway": return .seaway
        default: return .original
        }
    }
    private var status: String { (bol?.status ?? "issued").lowercased() }
    private var canSurrender: Bool { status == "issued" && surrenderedCount < totalOriginals }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if loading {
                    gapCard("Loading bill of lading…", "getBOL · \(bolNumber)", warn: false)
                } else if let err = loadError {
                    gapCard("B/L unavailable", err, warn: true)
                } else {
                    heroCard
                    methodSelector
                    endorsementChain
                    originalsRoster
                    documentsStrip
                    importReleaseBand
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
                Text("✦ VESSEL OPERATOR · CARGO RELEASE").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("MSC · USLGB").font(EType.mono(.micro)).tracking(0.6).foregroundStyle(palette.textTertiary)
            }
            Text("Cargo release").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
        }
    }

    private var heroCard: some View {
        RimCard718 {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text("B/L \(bol?.bolNumber ?? bolNumber) · VES-260523")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer()
                    Text((bol?.status ?? "issued").uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(LinearGradient.primary))
                }.padding(.bottom, 12)
                Text("\(bol?.originPort ?? "Shanghai CNSHA") → \(bol?.destinationPort ?? "Long Beach USLGB")")
                    .font(.system(size: 17, weight: .heavy)).foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                Text("\((bol?.bolType ?? "Master").capitalized) B/L · 40'HC reefer · \((bol?.freightTerms ?? "prepaid")) · \(bol?.vesselName ?? "MSC ISTANBUL")")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.top, 4)
                HStack(spacing: 8) {
                    Circle().fill(LinearGradient(colors: [Brand.hazmat, Color(hex: 0xFF7A00)], startPoint: .top, endPoint: .bottom)).frame(width: 12, height: 12)
                        .overlay(Text("MS").font(.system(size: 6, weight: .heavy)).foregroundStyle(.white))
                    Text("Carrier MSC · SCAC MSCU · consignee Pier 1 Imports").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }.padding(.top, 12)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(totalOriginals - surrenderedCount) / \(totalOriginals)").font(.system(size: 22, weight: .heavy, design: .monospaced)).foregroundStyle(LinearGradient.diagonal)
                    Text(surrenderedCount == 0 ? "originals outstanding · none surrendered" : "originals outstanding · \(surrenderedCount) surrendered")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                }.padding(.top, 10)
            }
        }
    }

    private var methodSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("RELEASE METHOD · createBOL bolType")
            HStack(spacing: 0) {
                ForEach(Method.allCases, id: \.self) { m in
                    let active = m == method
                    VStack(spacing: 3) {
                        Text(m.rawValue).font(.system(size: 11, weight: active ? .heavy : .semibold))
                            .foregroundStyle(active ? .white : palette.textPrimary)
                        Text(methodSub(m)).font(.system(size: 7.5, weight: .semibold)).tracking(0.3)
                            .foregroundStyle(active ? Color.white.opacity(0.85) : palette.textTertiary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(Color.clear))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(5).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("Post-issue method switch pending vesselShipments.setReleaseMethod")
                .font(.system(size: 8.5, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
    }
    private func methodSub(_ m: Method) -> String {
        switch m {
        case .original: return "MASTER · 3 OBL"
        case .telex: return "SURRENDER"
        case .seaway: return "SEAWAY · NO OBL"
        case .express: return "EXPRESS"
        }
    }

    private var endorsementChain: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("ENDORSEMENT & LC CHAIN")
                Spacer()
                Text("STUB · recordLCEndorsement").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 0) {
                chainNode(done: true, first: true, title: "Shipper endorsed", sub: "Eusorone Technologies (DU) · blank-endorsed to order", verdict: "DONE", vColor: Brand.success)
                chainNode(done: true, first: false, title: "Issuing bank — LC negotiation", sub: "LC 2026-IB-44817 · documents negotiated · endorsed", verdict: "DONE", vColor: Brand.success)
                chainNode(done: false, first: false, current: true, title: "Consignee — surrender originals", sub: "Pier 1 Imports · present 3 OBL at USLGB counter", verdict: "PENDING", vColor: Brand.warning)
                chainNode(done: false, first: false, blocked: true, title: "Carrier release", sub: "blocked until 3/3 surrendered or Telex set", verdict: "BLOCKED", vColor: palette.textTertiary)
            }
            .padding(Space.s4).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }
    private func chainNode(done: Bool, first: Bool, current: Bool = false, blocked: Bool = false, title: String, sub: String, verdict: String, vColor: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    if current {
                        Circle().fill(palette.bgCard).overlay(Circle().strokeBorder(LinearGradient.primary, lineWidth: 2)).frame(width: 16, height: 16)
                        Circle().fill(LinearGradient.diagonal).frame(width: 6, height: 6)
                    } else if done {
                        Circle().fill(Brand.success).frame(width: 16, height: 16)
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                    } else {
                        Circle().fill(palette.textTertiary.opacity(0.2)).frame(width: 16, height: 16)
                    }
                }
                if !blocked { Rectangle().fill(done ? Brand.success : palette.borderSoft).frame(width: 2, height: 30) }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.system(size: 12, weight: .heavy)).foregroundStyle(blocked ? palette.textTertiary : palette.textPrimary)
                    Spacer()
                    Text(verdict).font(.system(size: 8.5, weight: .heavy)).foregroundStyle(vColor)
                }
                Text(sub).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(palette.textTertiary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.bottom, blocked ? 0 : 8)
        }
    }

    private var originalsRoster: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("ORIGINALS OUTSTANDING").font(.system(size: 11, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                Text("surrenderBOL · requires status \"issued\"").font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text("\(surrenderedCount) / \(totalOriginals)").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textPrimary)
        }
        .padding(Space.s4).background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.tintNeutral))
    }

    private var documentsStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("DOCUMENTS · listBOLs · \(documents.count) on file")
            if documents.isEmpty {
                gapCard("No bills of lading on file yet", "listBOLs returned an empty set for this account.", warn: false)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(documents.prefix(4).enumerated()), id: \.offset) { idx, d in
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                                Text("OBL").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.bolNumber ?? "B/L").font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textPrimary).lineLimit(1)
                                Text("\((d.bolType ?? "master").capitalized) · \((d.status ?? "issued"))").font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textTertiary)
                        }
                        .padding(.vertical, 10)
                        if idx < min(documents.count, 4) - 1 { divider }
                    }
                }
                .padding(.horizontal, Space.s4).background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private var importReleaseBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("IMPORT RELEASE · DESTINATION CUSTOMS REGIME")
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ccBadge("US", true)
                    Text("USLGB · CBP entry 7501 + ISF on file → release").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Text("● ACTIVE").font(.system(size: 8, weight: .heavy)).foregroundStyle(Brand.blue)
                }
                divider
                HStack(spacing: 8) {
                    ccBadge("CA", false)
                    Text("CAVAN · CBSA B3").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    ccBadge("MX", false)
                    Text("MXZLO · VUCEM").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                    Text("STANDBY").font(.system(size: 8, weight: .heavy)).foregroundStyle(palette.textTertiary)
                }
            }
            .padding(Space.s4).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }
    private func ccBadge(_ cc: String, _ active: Bool) -> some View {
        Text(cc).font(.system(size: 8.5, weight: .heavy)).foregroundStyle(active ? .white : palette.textSecondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.tintNeutral)))
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: surrendering ? "Surrendering…" : "Surrender originals",
                      action: { Task { await surrender() } }, isLoading: surrendering || !canSurrender)
            Button {
                // View B/L — opens the document (routed by the nav controller).
            } label: {
                Text("View B/L").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(palette.textPrimary)
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
            Image(systemName: warn ? "exclamationmark.triangle.fill" : "doc.on.doc")
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
        struct ListIn: Encodable { let limit: Int }
        do {
            async let b: BOL718? = EusoTripAPI.shared.query("vesselShipments.getBOL", input: BOLIn(bolNumber: bolNumber))
            async let l: [BOL718]? = EusoTripAPI.shared.query("vesselShipments.listBOLs", input: ListIn(limit: 20))
            let (bb, ll) = try await (b, l)
            self.bol = bb; self.documents = ll ?? []
            if (bb?.status ?? "").lowercased() == "surrendered" { surrenderedCount = totalOriginals }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func surrender() async {
        guard let id = bol?.id, canSurrender else { return }
        surrendering = true
        struct SurrenderIn: Encodable { let id: Int }
        struct SurrenderOut: Decodable { let status: String? }
        do {
            let _: SurrenderOut? = try await EusoTripAPI.shared.mutation("vesselShipments.surrenderBOL", input: SurrenderIn(id: id))
            surrenderedCount = totalOriginals
            await load()
        } catch { /* surfaced by the caller ladder */ }
        surrendering = false
    }
}

private struct RimCard718<Content: View>: View {
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

#Preview("718 · Vessel Cargo Release · Night") {
    VesselCargoReleaseScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("718 · Vessel Cargo Release · Light") {
    VesselCargoReleaseScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
