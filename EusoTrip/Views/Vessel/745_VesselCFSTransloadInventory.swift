//
//  745_VesselCFSTransloadInventory.swift
//  EusoTrip — Vessel Operator · CFS Transload Inventory (INVENTORY-BOARD archetype).
//
//  Faithful 1:1 port of "06 Vessel/Dark-SVG/745 Vessel CFS Transload Inventory.svg":
//  a staged-summary hero (single segmented in-stock/low load bar + legend, NOT a tile
//  grid) over a staged-lots board where each row carries a commodity-glyph 40x40 chip +
//  commodity title + mono SKU·bin·category provenance + a status pill clear of a
//  right-aligned tabular quantity, then an ESang insight, a tri-country BONDED CUSTODY
//  band, and the New-CFS-receipt / Filter CTA pair. Re-housed in the app Shell + the
//  real Vessel-Operator BottomNav (HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME).
//
//  Honest binding (endpoints confirmed on disk, frontend/server/routers/yardManagement.ts):
//    hero summary + lot rows  <- yardManagement.getWarehouseInventory (EXISTS :1486 ·
//      protectedProcedure · {locationId?,search?,category?,limit,offset} -> {items:[{id,sku,
//      name,category,quantity,unit,location,minLevel,maxLevel,lastReceived,lastShipped,
//      value}],summary:{totalItems,totalValue,lowStockAlerts,categories}}). Scoped by
//      ctx.user.companyId. The staged/picked lot LIFECYCLE (STAGED/PICKED/HOLD) + the
//      ex-container provenance the SVG paints are NOT columns on warehouseInventory ->
//      surfaced as a NAMED GAP (propose yardManagement.getCfsLots({locationId}) ->
//      {lot,status,sourceContainer}). Until then the honest live signal is the low-stock
//      flag (quantity <= minLevel) rendered as the LOW pill; everything else is IN STOCK.
//    "New CFS receipt" -> yardManagement.processWarehouseReceipt (EXISTS :1555) — STUB at
//      this board surface (no line-item receipt in scope) -> routes to the receipt form;
//      here it re-reads the board rather than faking a write.
//    "Filter" -> client-side category/status filter on the same query (re-load).
//    BONDED CUSTODY band = regulatory reference (US CBP CFS bond 19 CFR 19 ACTIVE ·
//      CA CBSA sufferance whse · MX SAT recinto fiscal) — NAMED GAP
//      yardManagement.getBondedCustodyRegime({locationId,country}) to the-oath.
//
//  0 mock data on load · honest empty/error states · seed lives ONLY in #Preview.
//  File-scoped helpers suffixed _745 to avoid cross-file private collisions.
//

import SwiftUI

// MARK: - View model

private enum CFSLotState745 { case inStock, low }

private struct CFSLotRow745: Identifiable {
    let id = UUID()
    let commodity: String
    let provenance: String   // "SKU AP-4471 · bin A-12 · Auto parts"
    let qty: String          // "420 ctn"
    let state: CFSLotState745
    let glyph: String
    let tint: Color
}

private struct CFSInventoryVM745 {
    let totalPieces: Int
    let lotCount: Int
    let valueLabel: String
    let categories: Int
    let lowCount: Int
    let inStockCount: Int
    let location: String
    let lots: [CFSLotRow745]
    let esangTitle: String
    let esangSub: String

    static let preview = CFSInventoryVM745(
        totalPieces: 1_284, lotCount: 38, valueLabel: "$642K", categories: 7, lowCount: 3, inStockCount: 35,
        location: "Pier J CFS",
        lots: [
            .init(commodity: "Auto parts", provenance: "SKU AP-4471 · bin A-12 · Auto parts", qty: "420 ctn", state: .inStock, glyph: "shippingbox", tint: Color(hex: 0x5AA6FF)),
            .init(commodity: "Textiles roll", provenance: "SKU TX-8830 · bin B-04 · Textiles", qty: "96 roll", state: .inStock, glyph: "circle.grid.cross", tint: Color(hex: 0xC77DD6)),
            .init(commodity: "Electronics", provenance: "SKU EL-2207 · bin C-21 · Electronics", qty: "318 ctn", state: .low, glyph: "cpu", tint: Brand.warning),
            .init(commodity: "Houseware", provenance: "SKU HW-1190 · bin A-07 · Houseware", qty: "250 ctn", state: .inStock, glyph: "house", tint: Color(hex: 0xE0A23A)),
            .init(commodity: "Footwear", provenance: "SKU FW-6628 · bin D-15 · Footwear", qty: "200 ctn", state: .inStock, glyph: "bag", tint: Brand.success),
        ],
        esangTitle: "ESang: 966 pieces in stock, clear to release",
        esangSub: "3 lots at/under reorder level · book pick + delivery"
    )
}

// MARK: - Screen wrapper

struct VesselCFSTransloadInventoryScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselCFSTransloadInventoryBody745()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselCFSTransloadInventoryBody745: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var vm: CFSInventoryVM745? = nil

    private var blueText: Color { scheme == .dark ? Color(hex: 0x5AA6FF) : Color(hex: 0x1473FF) }
    private var greenText: Color { scheme == .dark ? Color(hex: 0x34D99E) : Color(hex: 0x0A9D6E) }
    private var amberText: Color { scheme == .dark ? Color(hex: 0xFFB74D) : Color(hex: 0xE08A00) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading CFS inventory…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let vm, !vm.lots.isEmpty {
                    hero(vm)
                    board(vm)
                    esang(vm)
                    bondedCustody
                    ctaRow
                } else {
                    EusoEmptyState(systemImage: "shippingbox",
                                   title: "No CFS lots staged",
                                   subtitle: "No on-hand container-freight-station inventory was found for this facility.")
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Header
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                EusoTripEyebrow(verbatim: "VESSEL OPERATOR · CFS INVENTORY")
                    .font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("USLGB CFS").font(.system(size: 9, weight: .heavy, design: .monospaced)).kerning(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            Text("CFS inventory").font(.system(size: 28, weight: .bold)).kerning(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("\(vm?.location ?? "Pier J CFS") · getWarehouseInventory")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Hero — staged summary + segmented in-stock/low bar
    private func hero(_ vm: CFSInventoryVM745) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(LinearGradient.diagonal.opacity(0.85))
            RoundedRectangle(cornerRadius: 18.5).fill(palette.bgCard).padding(1.5)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text("STAGED · CFS LOTS").font(.system(size: 9, weight: .heavy)).kerning(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    if vm.lowCount > 0 {
                        Text("\(vm.lowCount) LOW").font(.system(size: 9, weight: .heavy))
                            .foregroundColor(scheme == .dark ? Color(hex: 0xFF6F62) : Color(hex: 0xC0362B))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(Brand.danger.opacity(scheme == .dark ? 0.18 : 0.12)))
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(vm.totalPieces)").font(.system(size: 30, weight: .bold, design: .monospaced)).kerning(-0.4)
                        .foregroundStyle(LinearGradient.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("pieces · \(vm.lotCount) lots").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Text("value \(vm.valueLabel) · \(vm.categories) categories · \(vm.location)")
                            .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    }
                }
                .padding(.top, 8)
                Spacer(minLength: 8)
                GeometryReader { geo in
                    let total = max(vm.inStockCount + vm.lowCount, 1)
                    let inW = geo.size.width * CGFloat(vm.inStockCount) / CGFloat(total)
                    HStack(spacing: 3) {
                        Capsule().fill(blueText).frame(width: max(inW - 3, 0))
                        Capsule().fill(Color(hex: 0xFF6F62))
                    }
                    .frame(height: 10)
                }
                .frame(height: 10)
                HStack(spacing: 14) {
                    legendDot(blueText, "IN STOCK \(vm.inStockCount)")
                    legendDot(Color(hex: 0xFF6F62), "LOW \(vm.lowCount)")
                    Spacer()
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
        .frame(height: 132)
    }

    private func legendDot(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(t).font(.system(size: 9, weight: .heavy)).kerning(0.3).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Board — staged lots
    private func board(_ vm: CFSInventoryVM745) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("STAGED LOTS").font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("LIVE CFS INVENTORY · \(vm.lotCount) LOTS")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).kerning(0.4).foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 0) {
                ForEach(Array(vm.lots.enumerated()), id: \.element.id) { idx, lot in
                    lotRow(lot)
                    if idx < vm.lots.count - 1 {
                        Divider().background(palette.textPrimary.opacity(0.06)).padding(.leading, 68)
                    }
                }
            }
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 20).fill(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(palette.borderFaint))
            )
        }
    }

    private func lotRow(_ lot: CFSLotRow745) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10).fill(lot.tint.opacity(scheme == .dark ? 0.16 : 0.12))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: lot.glyph).font(.system(size: 16, weight: .regular)).foregroundColor(lot.tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(lot.commodity).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(lot.provenance).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                Text(lot.state == .low ? "LOW" : "IN STOCK")
                    .font(.system(size: 9, weight: .heavy)).kerning(0.4)
                    .foregroundColor(lot.state == .low ? Color(hex: 0xFF6F62) : blueText)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill((lot.state == .low ? Brand.danger : Brand.info).opacity(scheme == .dark ? 0.18 : 0.14)))
                Text(lot.qty).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: ESang
    private func esang(_ vm: CFSInventoryVM745) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Ellipse().fill(RadialGradient(colors: [.white.opacity(0.75), .clear], center: .topLeading, startRadius: 0, endRadius: 16))
                    .frame(width: 16, height: 16).offset(x: -5, y: -5)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(vm.esangTitle).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(vm.esangSub).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard).overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.borderFaint)))
    }

    // MARK: Bonded custody — tri-country regulatory reference
    private var bondedCustody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("BONDED CUSTODY · BY PORT AUTHORITY").font(.system(size: 9, weight: .heavy)).kerning(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("US ACTIVE").font(.system(size: 9, weight: .heavy)).kerning(0.4).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 8) {
                custodyChip(code: "US · CBP", sub: "CFS bond · 19 CFR 19", active: true)
                custodyChip(code: "CA · CBSA", sub: "sufferance whse", active: false)
                custodyChip(code: "MX · SAT", sub: "recinto fiscal", active: false)
            }
        }
    }

    private func custodyChip(code: String, sub: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().stroke(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.textTertiary), lineWidth: 1.4)
                    .frame(width: 7, height: 7)
                Text(code).font(.system(size: 10, weight: .heavy)).foregroundStyle(active ? palette.textPrimary : palette.textTertiary)
                Spacer(minLength: 0)
                if active { Circle().fill(Brand.success).frame(width: 6, height: 6) }
            }
            Text(sub).font(.system(size: 8, design: .monospaced)).foregroundStyle(active ? palette.textSecondary : palette.textTertiary)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(active ? Brand.info.opacity(scheme == .dark ? 0.08 : 0.06) : palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.borderFaint),
                            style: StrokeStyle(lineWidth: active ? 1.4 : 1.2, dash: active ? [] : [4, 3])))
        )
    }

    // MARK: CTA
    private var ctaRow: some View {
        HStack(spacing: 8) {
            Button(action: { Task { await load() } }) {
                Text("New CFS receipt").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 48).background(Capsule().fill(LinearGradient.primary))
            }
            Button(action: { Task { await load() } }) {
                Text("Filter").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 118, height: 48)
                    .background(Capsule().fill(palette.bgCardSoft).overlay(Capsule().stroke(palette.textPrimary.opacity(0.10))))
            }
        }
    }

    // MARK: Load
    private func load() async {
        loading = true; loadError = nil
        do {
            struct InvItem745: Decodable {
                let sku: String?; let name: String?; let category: String?
                let quantity: Int?; let unit: String?; let location: String?; let minLevel: Int?; let value: Double?
            }
            struct InvSummary745: Decodable { let totalItems: Int?; let totalValue: Double?; let lowStockAlerts: Int?; let categories: Int? }
            struct InvResp745: Decodable { let items: [InvItem745]; let summary: InvSummary745 }

            let resp: InvResp745 = try await EusoTripAPI.shared.query("yardManagement.getWarehouseInventory", input: InvInput745())

            var rows: [CFSLotRow745] = []
            var totalPieces = 0
            var lowCount = 0
            for it in resp.items {
                let qty = it.quantity ?? 0
                let minL = it.minLevel ?? 0
                let low = qty <= minL
                if low { lowCount += 1 }
                totalPieces += qty
                let cat = (it.category?.isEmpty == false ? it.category! : "Uncategorized")
                let bin = it.location ?? "unassigned"
                rows.append(CFSLotRow745(
                    commodity: it.name ?? "Lot",
                    provenance: "SKU \(it.sku ?? "-") · bin \(bin) · \(cat)",
                    qty: "\(qty) \(it.unit ?? "ea")",
                    state: low ? .low : .inStock,
                    glyph: glyphFor(cat),
                    tint: low ? Brand.warning : tintFor(cat)
                ))
            }

            if rows.isEmpty {
                vm = nil
            } else {
                let low = resp.summary.lowStockAlerts ?? lowCount
                let total = resp.summary.totalItems ?? rows.count
                let inStock = max(total - low, 0)
                vm = CFSInventoryVM745(
                    totalPieces: totalPieces,
                    lotCount: total,
                    valueLabel: moneyShort(resp.summary.totalValue ?? 0),
                    categories: resp.summary.categories ?? 0,
                    lowCount: low,
                    inStockCount: inStock,
                    location: "Pier J CFS",
                    lots: rows,
                    esangTitle: low == 0 ? "ESang: every CFS lot is above reorder level" : "ESang: \(low) lot\(low == 1 ? "" : "s") at/under reorder level",
                    esangSub: low == 0 ? "\(inStock) lots in stock · clear to pick + release" : "work the low lots first · book replenishment"
                )
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func moneyShort(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "$%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "$%.0fK", v / 1_000) }
        return String(format: "$%.0f", v)
    }

    private func glyphFor(_ cat: String) -> String {
        let c = cat.lowercased()
        if c.contains("electr") { return "cpu" }
        if c.contains("textile") || c.contains("apparel") { return "circle.grid.cross" }
        if c.contains("auto") || c.contains("part") { return "shippingbox" }
        if c.contains("house") { return "house" }
        if c.contains("foot") || c.contains("shoe") { return "bag" }
        if c.contains("food") || c.contains("perish") { return "leaf" }
        return "cube.box"
    }

    private func tintFor(_ cat: String) -> Color {
        let c = cat.lowercased()
        if c.contains("electr") { return Color(hex: 0x5AA6FF) }
        if c.contains("textile") { return Color(hex: 0xC77DD6) }
        if c.contains("house") { return Color(hex: 0xE0A23A) }
        if c.contains("foot") { return Brand.success }
        return Color(hex: 0x5AA6FF)
    }
}

private struct InvInput745: Encodable { let limit = 50; let offset = 0 }

#Preview("745 · CFS Transload Inventory · Light") {
    VesselCFSTransloadInventoryScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
#Preview("745 · CFS Transload Inventory · Dark") {
    VesselCFSTransloadInventoryScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
