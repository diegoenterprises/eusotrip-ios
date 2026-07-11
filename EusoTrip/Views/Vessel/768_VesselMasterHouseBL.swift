//
//  768_VesselMasterHouseBL.swift
//  EusoTrip — Vessel Operator · Master & House B/L (CONSOLIDATION-TREE).
//
//  Verbatim bespoke port of canonical wireframe "768 Vessel Master & House
//  B-L · Dark" (06 Vessel · Vessel Operator). Consolidation-hierarchy
//  archetype, purpose-built as a master node branching down a trunk to three
//  house-B/L leaf cards — each with consignee + a proportional
//  weight-allocation bar + its house B/L number — deliberately DISTINCT from
//  every single-document surface (005/715/719/765/767). The co-load split of
//  one master (carrier→NVOCC) over N houses (NVOCC→underlying shippers).
//
//  Docked under SHIPMENTS. transportMode=vessel · tri-country US·CA·MX.
//
//  REAL WIRING (tRPC):
//    · vesselShipments.listBOLs {limit} -> both levels are first-class B/L
//      types (bolType incl. MASTER + HOUSE) (server/routers/vesselShipments.ts
//      :961) — EXISTS at the row level. createBOL (:880) issues each level.
//  STUB (handed to the-oath): blConsolidation.getTree / linkHouse — listBOLs
//  returns a FLAT list; there is no masterBolId foreign key nor an
//  allocation-share field tying houses to a master. The tree + weight shares
//  render the certified reference model (a flat list of master/house rows,
//  where present, is surfaced live); the parent-child link + share-sum
//  invariant persist when the consolidation endpoint lands.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselMasterHouseBLScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            VesselMasterHouseBLBody()
        } nav: {
            BottomNav.vesselOperatorShipments()
        }
    }
}

// MARK: - Model

private struct HouseLeaf768: Identifiable {
    let id: String            // "HBL-7741-A"
    let consignee: String
    let weightKg: Int
    let sharePct: Int
    let barColor: Color
}

// MARK: - Body

private struct VesselMasterHouseBLBody: View {
    @Environment(\.palette) private var palette

    @State private var bols: [VesselDocBOL] = []
    @State private var loading = true

    private var masterBOL: VesselDocBOL? {
        bols.first(where: { ($0.bolType ?? "").lowercased() == "master" })
    }
    private var masterNumber: String { masterBOL?.bolNumber ?? "MSCUSH6840517" }
    private var totalWeight: Int { masterBOL?.weightKg ?? 28_400 }

    private let houses: [HouseLeaf768] = [
        .init(id: "HBL-7741-A", consignee: "Horizon Trading FZE", weightKg: 12_800, sharePct: 45, barColor: Color(hex: 0xA98BFF)),
        .init(id: "HBL-7741-B", consignee: "Cedar Mills Import Co", weightKg: 9_600,  sharePct: 34, barColor: Color(hex: 0x5AB0FF)),
        .init(id: "HBL-7741-C", consignee: "Allied Cold Foods",    weightKg: 6_000,  sharePct: 21, barColor: Color(hex: 0x34D8A6)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDocTopBar(eyebrow: "VESSEL OPERATOR · CONSOLIDATION",
                            idCaption: "MASTER + 3 HOUSE",
                            title: "Master & house")
            IridescentHairline().padding(.horizontal, Space.s5)

            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    VesselDocSkeleton(bodyHeight: 340)
                } else {
                    heroCard
                    treeSection
                    TriCountryAuthorityBand(title: "MANIFEST AUTHORITY · HOUSE DECLARATIONS",
                                            regimes: manifestRegimes)
                    VesselDocCTAPair(primaryTitle: "Issue house B/Ls",
                                     secondaryTitle: "Edit split",
                                     primaryIcon: "doc.on.doc.fill",
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
                Text("Master \(masterNumber) · co-load")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text("1 MASTER · 3 HOUSE")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Color(hex: 0xA98BFF))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color(hex: 0xA98BFF).opacity(0.16)))
            }
            Text("Consolidation B/L set")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s3)
            Text("Carrier → NVOCC master over 3 house B/Ls")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 3)
            Text("40' HC · \(totalWeight.formatted(.number.grouping(.automatic))) kg · 3 underlying shippers")
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

    // MARK: Consolidation tree

    private var treeSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            VesselSectionHeader(label: "CONSOLIDATION TREE",
                                right: masterBOL != nil ? "live master" : "reference")
            VStack(spacing: 0) {
                // Master node.
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MASTER · \(masterNumber)")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("MSC → Eusorone (NVOCC) · \(totalWeight.formatted(.number.grouping(.automatic))) kg")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 8)
                    Text("100%")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .padding(Space.s3)
                .background(LinearGradient(colors: [Color(hex: 0x7A4DFF), Brand.magenta],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // House leaves with a trunk line.
                HStack(alignment: .top, spacing: 0) {
                    // Trunk.
                    Rectangle().fill(palette.borderSoft)
                        .frame(width: 2.5)
                        .padding(.leading, 18)
                        .padding(.top, 0)
                    VStack(spacing: Space.s3) {
                        ForEach(houses) { h in houseLeaf(h) }
                    }
                    .padding(.leading, Space.s3)
                }
                .padding(.top, Space.s3)
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            VesselDocGapNote(text: "Reference co-load split. The parent-child link + share-sum invariant persist when the consolidation endpoint lands.")
        }
    }

    private func houseLeaf(_ h: HouseLeaf768) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(h.id)
                        .font(.system(size: 10.5, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text(h.consignee)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                Text("\(h.weightKg.formatted(.number.grouping(.automatic))) kg")
                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
            }
            // Allocation bar.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.textPrimary.opacity(0.06)).frame(height: 6)
                    Capsule().fill(h.barColor)
                        .frame(width: geo.size.width * CGFloat(h.sharePct) / 100.0, height: 6)
                }
            }
            .frame(height: 6)
            Text("\(h.sharePct)%")
                .font(.system(size: 7.5, weight: .heavy))
                .foregroundStyle(h.barColor)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var manifestRegimes: [CountryRegime] {
        [
            .init(code: "US", authority: "US · CBP", detail: "house bills on AMS/ACE", consequence: nil, state: .active),
            .init(code: "CA", authority: "CA · CBSA", detail: "supplementary cargo (ACI)", consequence: nil, state: .standby),
            .init(code: "MX", authority: "MX · Aduanas", detail: "consolidado VUCEM", consequence: nil, state: .standby),
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

#Preview("768 · Vessel Master & House B/L · Night") {
    VesselMasterHouseBLScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("768 · Vessel Master & House B/L · Light") {
    VesselMasterHouseBLScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
