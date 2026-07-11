//
//  204G_ShipperHHGChainOfCustody.swift
//  EusoTrip 2027 — Shipper · HHG Chain of Custody & Descriptive Inventory (204G).
//
//  ARCHETYPE: INVENTORY-LEDGER + CUSTODY-TIMELINE. A gradient-rim
//  valuation/authority hero (declared value + full-value-protection
//  election + descriptive-inventory completion ring + OP-1 / arbitration
//  trust chips) leads, a room-by-room DESCRIPTIVE INVENTORY ledger with
//  per-item condition-code chips follows, closing on a horizontal
//  CHAIN-OF-CUSTODY timeline (origin inventory signed → seal → in-transit
//  → destination check → POD). Purpose-built for the 49 CFR 375 consumer
//  paperwork — not a dimension gate, not a stat grid.
//
//  Persona §11: Diego Usoro / Eusorone Technologies (shipper-of-record).
//  Featured load: LD-260615-HHG41 · 3-bed residence relocation ·
//  14,820 lb certified · Austin TX → Denver CO · van-line carrier (OP-1).
//
//  ── WIRING MANIFEST (endpoint · file:line · state) ────────────────────
//  Web parity: shipper/loads/[id]/hhg-custody.tsx
//  LIVE  industryVerticals.getComplianceRequirements  industryVerticals.ts:713
//        (hg-inventory · 49 CFR 375.403 detailed inventory at pickup)
//  LIVE  industryVerticals.getDocuments          industryVerticals.ts:1252
//        (written estimate · consumer-rights booklet · inventory set)
//  LIVE  industryVerticals.validateLoad          industryVerticals.ts:1268
//  LIVE  visualIntelligence.assessDamage         visualIntelligence.ts:167
//  LIVE  bol.generateCompletionTicket            bol.ts:821 (inventory write)
//  STUB  carriers.getHHGAuthority — named gap. Proposed:
//        carriers.getHHGAuthority({carrierId}) → {op1Number, arbitration,
//        registered}. OP-1 + 375.211 enrollment has no proc yet.
//  STUB  householdGoods.fileDescriptiveInventory — named gap. Proposed:
//        ({loadId, items[], extraordinaryValueDeclared}) → {inventoryId,
//        itemCount, filed}. The descriptive-inventory write + seal bind. CTA.
//  transportMode TRUCK · country US (49 CFR 375 · OP-1 · 375.211 · 375.403
//  · 375.213 valuation). Degraded → "authority check pending (degraded)".
//

import SwiftUI

// MARK: - Model

private struct InventoryItem: Identifiable {
    let id = UUID()
    let room: String            // monogram
    let roomTint: Color
    let name: String
    let itemLine: String
    let chips: [(String, Color)]
    let value: String
    let photoCount: Int
}

private struct CustodyNode: Identifiable {
    enum Kind { case done, current, future }
    let id = UUID()
    let topLabel: String
    let bottomLabel: String
    let kind: Kind
}

private struct HHGModel {
    var declaredValue: String
    var valuationLine: String
    var releasedLine: String
    var ringLogged: Int
    var ringTotal: Int
    var authorityFooter: String
    var items: [InventoryItem]
    var legend: String
    var custody: [CustodyNode]
    var sealTitle: String
    var sealDetail: String

    static let canonical = HHGModel(
        declaredValue: "$86,400",
        valuationLine: "Declared value · full-value protection",
        releasedLine: "Released $0.60/lb waiver declined",
        ringLogged: 42, ringTotal: 58,
        authorityFooter: "Binding estimate · rights booklet · certified scale 14,820 lb",
        items: [
            InventoryItem(room: "LR", roomTint: Brand.escort,
                          name: "Sofa · sectional, 3-pc",
                          itemLine: "Item #014 · carrier-packed",
                          chips: [("SC", Brand.warning), ("CP", Brand.warning)],
                          value: "$2,400", photoCount: 4),
            InventoryItem(room: "DR", roomTint: Brand.info,
                          name: "China cabinet · glass",
                          itemLine: "Item #021 · packed by owner (PBO)",
                          chips: [("PBO", Brand.neutral)],
                          value: "$1,850", photoCount: 6),
            InventoryItem(room: "ST", roomTint: Brand.escort,
                          name: "Framed artwork",
                          itemLine: "Item #038 · extraordinary-value form",
                          chips: [("HIGH VALUE", Brand.escort)],
                          value: "$9,200", photoCount: 5),
        ],
        legend: "CP chipped · SC scratched · D dented · PBO packed by owner",
        custody: [
            CustodyNode(topLabel: "Inventory", bottomLabel: "signed", kind: .done),
            CustodyNode(topLabel: "Seal", bottomLabel: "applied", kind: .done),
            CustodyNode(topLabel: "In transit", bottomLabel: "now", kind: .current),
            CustodyNode(topLabel: "Dest.", bottomLabel: "check", kind: .future),
            CustodyNode(topLabel: "POD", bottomLabel: "signed", kind: .future),
        ],
        sealTitle: "Trailer seal intact",
        sealDetail: "Seal #SL-44192 · bound to inventory"
    )
}

// MARK: - Store

@MainActor
private final class HHGStore: ObservableObject {
    @Published private(set) var model = HHGModel.canonical
    @Published private(set) var degraded: String? = nil
    @Published var filing = false

    let loadId: String
    private let api: EusoTripAPI

    init(loadId: String, api: EusoTripAPI = .shared) {
        self.loadId = loadId
        self.api = api
    }

    func refresh() async {
        struct In: Encodable { let verticalId: String }
        struct Reqs: Decodable { let verticalId: String? }
        do {
            let _: Reqs = try await api.query(
                "industryVerticals.getComplianceRequirements",
                input: In(verticalId: "household_goods"))
            degraded = nil
        } catch {
            degraded = "Authority check pending (degraded) — last inventory shown"
        }
    }

    func fileInventory() async {
        filing = true
        defer { filing = false }
        struct In: Encodable { let loadId: String }
        let _: HHGAck? = try? await api.mutation(
            "householdGoods.fileDescriptiveInventory", input: In(loadId: loadId))
    }
}

private struct HHGAck: Decodable {}

// MARK: - View

struct ShipperHHGChainOfCustody: View {
    let loadId: String
    @StateObject private var store: HHGStore
    @Environment(\.palette) private var palette

    init(loadId: String = "LD-260615-HHG41") {
        self.loadId = loadId
        _store = StateObject(wrappedValue: HHGStore(loadId: loadId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                AddendaHeader(eyebrow: "✦ SHIPPER · HHG · CHAIN OF CUSTODY",
                              idText: store.loadId,
                              title: "Household Goods")

                if let degraded = store.degraded {
                    DegradedNote(text: degraded).padding(.top, Space.s3)
                }

                valuationHero
                    .padding(.horizontal, Space.s5).padding(.top, Space.s4)

                SectionLabel("DESCRIPTIVE INVENTORY · 49 CFR 375.403 · 58 ITEMS")
                    .padding(.top, Space.s5)
                inventoryLedger
                    .padding(.horizontal, Space.s5).padding(.top, Space.s2)

                SectionLabel("CHAIN OF CUSTODY · ORIGIN → DELIVERY")
                    .padding(.top, Space.s5)
                custodyPanel
                    .padding(.horizontal, Space.s5).padding(.top, Space.s2)

                AddendaCTAPair(primary: "File inventory + seal",
                               secondary: "Message ESang",
                               primaryLoading: store.filing,
                               onPrimary: { Task { await store.fileInventory() } })
                    .padding(.top, Space.s5)

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }

    // MARK: Valuation & authority hero (gradient rim)

    private var valuationHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("VALUATION & MOVER AUTHORITY · 49 CFR 375")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(Brand.info)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s4).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Brand.info.opacity(0.12))

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.model.declaredValue)
                        .font(.system(size: 34, weight: .bold)).tracking(-0.6)
                        .monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(store.model.valuationLine)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                    Text(store.model.releasedLine)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: Space.s2)
                InventoryRing(logged: store.model.ringLogged, total: store.model.ringTotal)
                    .frame(width: 72, height: 72)
            }
            .padding(.horizontal, Space.s4).padding(.top, Space.s4)

            Divider().overlay(palette.borderFaint)
                .padding(.horizontal, Space.s4).padding(.top, Space.s3)

            HStack(spacing: Space.s2) {
                trustChip("checkmark.seal.fill", "OP-1 HHG AUTHORITY")
                trustChip("checkmark.seal.fill", "375.211 ARBITRATION")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s4).padding(.top, Space.s3)

            Text(store.model.authorityFooter)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, Space.s4).padding(.top, Space.s2)
                .padding(.bottom, Space.s4)
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    private func trustChip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(text).font(.system(size: 10, weight: .heavy)).tracking(0.2)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(Brand.success)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(Brand.success.opacity(0.18)))
    }

    // MARK: Descriptive inventory ledger

    private var inventoryLedger: some View {
        VStack(spacing: 0) {
            ForEach(store.model.items) { item in
                HStack(alignment: .top, spacing: Space.s3) {
                    AddendaMonogram(text: item.room, tint: item.roomTint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Text(item.itemLine)
                            .font(EType.mono(.caption))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        HStack(spacing: 5) {
                            ForEach(Array(item.chips.enumerated()), id: \.offset) { _, chip in
                                Text(chip.0)
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(chip.1)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Capsule().fill(chip.1.opacity(0.18)))
                            }
                        }
                    }
                    Spacer(minLength: Space.s2)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(item.value)
                            .font(.system(size: 13, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                        HStack(spacing: 3) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 9, weight: .semibold))
                            Text("\(item.photoCount)")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(palette.textSecondary)
                    }
                }
                .padding(Space.s4)
                Divider().overlay(palette.borderFaint).padding(.leading, Space.s4)
            }
            Text(store.model.legend)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.s3)
                .background(Color.white.opacity(0.03))
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .addendaPanel(palette)
    }

    // MARK: Chain-of-custody timeline + seal

    private var custodyPanel: some View {
        VStack(spacing: 0) {
            CustodyRail(nodes: store.model.custody)
                .padding(.horizontal, Space.s4).padding(.top, Space.s4)

            Divider().overlay(palette.borderFaint)
                .padding(.horizontal, Space.s4).padding(.top, Space.s3)

            HStack(spacing: Space.s3) {
                AddendaIconChip(systemImage: "lock.fill", tint: Brand.success)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.model.sealTitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(store.model.sealDetail)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: Space.s2)
                AddendaChip(text: "VERIFIED", color: Brand.success)
            }
            .padding(Space.s4)
        }
        .addendaPanel(palette)
    }
}

// MARK: - Inventory completion ring

private struct InventoryRing: View {
    let logged: Int
    let total: Int
    @Environment(\.palette) private var palette
    private var fraction: Double { total == 0 ? 0 : Double(logged) / Double(total) }
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 7)
            Circle().trim(from: 0, to: max(0.02, min(fraction, 1)))
                .stroke(Brand.success, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(logged)/\(total)")
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("ITEMS")
                    .font(.system(size: 7, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }
}

// MARK: - Horizontal custody rail

private struct CustodyRail: View {
    let nodes: [CustodyNode]
    @Environment(\.palette) private var palette

    private var currentIndex: Int {
        nodes.firstIndex { $0.kind == .current } ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let n = max(nodes.count - 1, 1)
            let step = w / CGFloat(n)
            let progress = step * CGFloat(currentIndex)
            ZStack(alignment: .topLeading) {
                Capsule().fill(Color.white.opacity(0.12))
                    .frame(width: w, height: 2).offset(y: 5)
                Capsule().fill(Brand.success)
                    .frame(width: progress, height: 2).offset(y: 5)
                ForEach(Array(nodes.enumerated()), id: \.element.id) { idx, node in
                    VStack(spacing: 3) {
                        nodeDot(for: node.kind)
                        Text(node.topLabel)
                            .font(.system(size: 9, weight: node.kind == .current ? .heavy : .semibold))
                            .foregroundStyle(labelColor(node.kind))
                        Text(node.bottomLabel)
                            .font(.system(size: 8, weight: .regular))
                            .foregroundStyle(node.kind == .current ? Brand.info : palette.textTertiary)
                    }
                    .frame(width: step)
                    .offset(x: CGFloat(idx) * step - step / 2)
                }
            }
        }
        .frame(height: 56)
    }

    private func labelColor(_ kind: CustodyNode.Kind) -> Color {
        switch kind {
        case .done:    return palette.textSecondary
        case .current: return Brand.info
        case .future:  return palette.textTertiary
        }
    }

    @ViewBuilder
    private func nodeDot(for kind: CustodyNode.Kind) -> some View {
        switch kind {
        case .done:
            Circle().fill(Brand.success).frame(width: 10, height: 10)
        case .current:
            Circle().fill(Brand.blue).frame(width: 14, height: 14)
                .overlay(Circle().fill(.white).frame(width: 6, height: 6))
        case .future:
            Circle().strokeBorder(palette.textPrimary.opacity(0.3), lineWidth: 2)
                .frame(width: 10, height: 10)
        }
    }
}

// MARK: - Previews

#Preview("204G · HHG Chain of Custody · Dark") {
    ShipperScreenWrap(palette: Theme.dark, currentSlot: .none) {
        ShipperHHGChainOfCustody()
    }
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("204G · HHG Chain of Custody · Light") {
    ShipperScreenWrap(palette: Theme.light, currentSlot: .none) {
        ShipperHHGChainOfCustody()
    }
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
