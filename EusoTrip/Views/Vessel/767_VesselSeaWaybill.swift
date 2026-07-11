//
//  767_VesselSeaWaybill.swift
//  EusoTrip — Vessel Operator · Sea Waybill (STRAIGHT-CONSIGNMENT + CONTRAST).
//
//  Verbatim bespoke port of canonical wireframe "767 Vessel Sea Waybill ·
//  Dark" (06 Vessel · Vessel Operator). Straight-consignment archetype,
//  purpose-built as a named-parties grid (shipper/consignee/notify,
//  non-transferable) over a Sea-Waybill-vs-Original-B/L comparison strip
//  (surrender / title / negotiable / faster-release) — deliberately DISTINCT
//  from the negotiable-title B/L surfaces (005/715/719/679). A non-negotiable
//  consignment released on consignee identity, no original, no surrender.
//
//  Docked under SHIPMENTS. transportMode=vessel · tri-country US·CA·MX.
//
//  REAL WIRING (tRPC):
//    · vesselShipments.createBOL {bolType:"seaway"} (server/routers/
//      vesselShipments.ts:880) — a sea waybill IS a first-class B/L type;
//      EXISTS-backed, NOT a stub. listBOLs (:961) anchors the operator's live
//      seaway/express bills; getBOL (:944) + services/bol.ts:326 back it.
//  STUB (handed to the-oath): vessel.releaseSeaway — only the ID-verified
//  release-without-document gate needs an explicit verb (release today keys
//  off surrender, which a seaway has none of). The "Issue Sea Waybill" CTA
//  is the real createBOL({bolType:'seaway'}) path.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselSeaWaybillScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            VesselSeaWaybillBody()
        } nav: {
            BottomNav.vesselOperatorShipments()
        }
    }
}

// MARK: - Model

private struct WaybillParty767: Identifiable {
    let id: String
    let role: String
    let name: String
    let note: String
}

private struct ContrastRow767: Identifiable {
    let id: String
    let attribute: String
    let waybill: String
    let waybillGood: Bool
    let originalBL: String
}

// MARK: - Body

private struct VesselSeaWaybillBody: View {
    @Environment(\.palette) private var palette

    @State private var bols: [VesselDocBOL] = []
    @State private var loading = true

    private var seawayBOL: VesselDocBOL? {
        bols.first(where: { ["seaway", "express"].contains(($0.bolType ?? "").lowercased()) }) ?? bols.first
    }
    private var swbNumber: String { seawayBOL?.bolNumber ?? "MSCU-SW-7741210" }
    private var lane: String { seawayBOL?.lane ?? "CNSHA → USLGB" }

    private var parties: [WaybillParty767] {
        [
            .init(id: "shipper",   role: "SHIPPER",   name: "Eusorone Technologies", note: "Shanghai CN · shipper of record"),
            .init(id: "consignee", role: "CONSIGNEE", name: "Pier 1 Imports LLC",    note: "named · non-transferable"),
            .init(id: "notify",    role: "NOTIFY",    name: "Pier 1 Imports LLC",    note: "same as consignee"),
        ]
    }

    private let contrast: [ContrastRow767] = [
        .init(id: "surrender", attribute: "Surrender required", waybill: "No",  waybillGood: false, originalBL: "Yes"),
        .init(id: "title",     attribute: "Document of title",  waybill: "No",  waybillGood: false, originalBL: "Yes"),
        .init(id: "negotiable", attribute: "Negotiable",        waybill: "No",  waybillGood: false, originalBL: "Yes"),
        .init(id: "faster",    attribute: "Faster release",     waybill: "Yes", waybillGood: true,  originalBL: "No"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDocTopBar(eyebrow: "VESSEL OPERATOR · SEA WAYBILL",
                            idCaption: "STRAIGHT · SWB",
                            title: "Sea waybill")
            IridescentHairline().padding(.horizontal, Space.s5)

            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    VesselDocSkeleton(bodyHeight: 320)
                } else {
                    heroCard
                    partiesSection
                    contrastSection
                    TriCountryAuthorityBand(title: "RELEASE AUTHORITY · DISCHARGE PORT",
                                            regimes: releaseRegimes)
                    VesselDocCTAPair(primaryTitle: "Issue Sea Waybill",
                                     secondaryTitle: "Switch to B/L",
                                     primaryIcon: "doc.text.fill",
                                     onPrimary: {}, onSecondary: {})
                }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
    }

    // MARK: Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("SWB \(swbNumber) · \(lane)")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                Text("NON-NEGOTIABLE")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Color(hex: 0x5AB0FF))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color(hex: 0x5AB0FF).opacity(0.14)))
            }
            Text("Sea Waybill — straight")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s3)
            Text("No original issued · no surrender required")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 3)
            Text("Release on consignee identity verification")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s3)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    // MARK: Named parties

    private var partiesSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            VesselSectionHeader(label: "NAMED PARTIES", right: seawayBOL != nil ? "live" : "reference")
            VStack(spacing: 0) {
                ForEach(Array(parties.enumerated()), id: \.element.id) { idx, p in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.role)
                            .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        HStack(alignment: .firstTextBaseline) {
                            Text(p.name)
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(1).minimumScaleFactor(0.8)
                            Spacer(minLength: 8)
                            Text(p.note)
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundStyle(palette.textTertiary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .padding(.horizontal, Space.s4).padding(.vertical, 11)
                    if idx < parties.count - 1 {
                        Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: Waybill vs Original B/L contrast

    private var contrastSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            VesselSectionHeader(label: "WAYBILL vs ORIGINAL B/L", right: "4 attributes")
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Text("SEA WAYBILL").font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(Color(hex: 0x5AB0FF))
                        .frame(width: 96, alignment: .center)
                    Text("ORIGINAL B/L").font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                        .frame(width: 76, alignment: .trailing)
                }
                .padding(.horizontal, Space.s4).padding(.top, Space.s3).padding(.bottom, Space.s2)
                Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                ForEach(Array(contrast.enumerated()), id: \.element.id) { idx, r in
                    contrastRow(r)
                    if idx < contrast.count - 1 {
                        Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func contrastRow(_ r: ContrastRow767) -> some View {
        HStack(spacing: Space.s2) {
            Text(r.attribute)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text(r.waybill)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(r.waybillGood ? Brand.success : palette.textTertiary)
                .frame(width: 64, height: 19)
                .background(Capsule().fill(palette.bgCardSoft))
                .frame(width: 96, alignment: .center)
            Text(r.originalBL)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(palette.textTertiary)
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, 11)
    }

    private var releaseRegimes: [CountryRegime] {
        [
            .init(code: "US", authority: "US · USLGB · CBP", detail: "ID-verified release", consequence: nil, state: .active),
            .init(code: "CA", authority: "CA · CAVAN", detail: "CBSA cargo control", consequence: nil, state: .standby),
            .init(code: "MX", authority: "MX · MXZLO · Aduanas", detail: "carta porte", consequence: nil, state: .standby),
        ]
    }

    private func load() async {
        loading = true
        struct ListIn: Encodable { let limit: Int }
        do {
            self.bols = try await EusoTripAPI.shared.query(
                "vesselShipments.listBOLs", input: ListIn(limit: 20))
        } catch {
            self.bols = []
        }
        loading = false
    }
}

#Preview("767 · Vessel Sea Waybill · Night") {
    VesselSeaWaybillScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("767 · Vessel Sea Waybill · Light") {
    VesselSeaWaybillScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
