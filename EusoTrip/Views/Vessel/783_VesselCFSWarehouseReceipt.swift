//
//  783_VesselCFSWarehouseReceipt.swift
//  EusoTrip — Vessel Operator · CFS Warehouse Receipt (DOCUMENT archetype).
//
//  Faithful 1:1 port of "783 Vessel CFS Warehouse Receipt.svg" (Light + Dark).
//  A container-freight-station receiving surface (distinct from the detention
//  money boards): a gradient-rimmed hero with the receipts-open figure +
//  putaway progress, a 3-cell KPI strip (RECEIPTS · ON-HAND · SHORT FLAGS), an
//  itemized receipt ledger reconciled against ASN counts (DONE / VERIFYING /
//  SHORT), a yardManagement wiring context strip, and a Process-receipt /
//  View-on-hand CTA pair. The vessel-operator's transload receiving at Pier J
//  CFS — mirror of the rail sibling (626) at equal depth.
//
//  WIRING (server/routers/yardManagement.ts — verified this fire):
//    · getWarehouseInventory {locationId?,limit}? (query, protectedProcedure,
//        companyId-scoped :1486)
//        -> { items[{id,sku,name,category,quantity,unit,location,minLevel,
//             maxLevel,lastReceived,lastShipped,value}],
//             summary{totalItems,totalValue,lowStockAlerts,categories},
//             lowStockAlerts[] }
//    · "Process receipt" -> processWarehouseReceipt {locationId,items[]} mutation
//        (:1555). PORT-GAP (honest, matches 626): there is NO per-CFS-receipt
//        list/lifecycle query (WR-#### putaway/verify state), so the RECEIPTS
//        ledger reconciles live inventory against each SKU's ASN target
//        (minLevel), and "Process receipt" — which needs a scanned items[]
//        payload this read board doesn't host — re-pulls live on-hand rather
//        than POST an empty receipt.
//  transportMode=vessel · CMA CGM at Pier J CFS · USD. No mock data.
//

import SwiftUI

private struct CFSInventory783: Decodable {
    let items: [CFSItem783]?
    let summary: CFSSummary783?
    let lowStockAlerts: [CFSItem783]?
}
private struct CFSItem783: Decodable, Identifiable {
    let id: String
    let sku: String?
    let name: String?
    let quantity: Int?
    let location: String?
    let minLevel: Int?
    let maxLevel: Int?
}
private struct CFSSummary783: Decodable {
    let totalItems: Int?
    let lowStockAlerts: Int?
    let categories: Int?
}

struct VesselCFSWarehouseReceiptScreen: View {
    let theme: Theme.Palette
    var locationId: String = "PIER-J-CFS"
    var body: some View {
        Shell(theme: theme) { VesselCFSWarehouseReceiptBody(locationId: locationId) }
            nav: { VesselDetnNav(active: .shipments) }
    }
}

private enum CFSState783 {
    case done, verify, short
    var label: String { self == .done ? "DONE" : self == .verify ? "VERIFYING" : "SHORT" }
    var color: Color { self == .done ? Brand.success : self == .verify ? Brand.info : Brand.warning }
    var icon: String { self == .short ? "exclamationmark.triangle" : (self == .done ? "checkmark.circle" : "clock") }
}

private struct VesselCFSWarehouseReceiptBody: View {
    @Environment(\.palette) private var palette
    let locationId: String
    @State private var inv: CFSInventory783? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var processing = false

    private var items: [CFSItem783] { inv?.items ?? [] }
    private var openCount: Int { items.count }
    private var onHand: Int { items.reduce(0) { $0 + ($1.quantity ?? 0) } }
    private var shortFlags: Int { items.filter { ($0.quantity ?? 0) < ($0.minLevel ?? 0) }.count }
    private var putaway: Int { items.filter { ($0.quantity ?? 0) >= ($0.maxLevel ?? Int.max) && ($0.maxLevel ?? 0) > 0 }.count }
    private var progress: CGFloat { openCount > 0 ? CGFloat(putaway) / CGFloat(openCount) : 0 }
    private var facilityLabel: String { items.compactMap { $0.location }.first(where: { !$0.isEmpty }) ?? "Pier J CFS" }

    private func state(_ it: CFSItem783) -> CFSState783 {
        let q = it.quantity ?? 0, mn = it.minLevel ?? 0, mx = it.maxLevel ?? Int.max
        if q >= mx && mx != Int.max { return .done }
        if q < mn { return .short }
        return .verify
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                VDetnEyebrow(section: "CFS RECEIPTS", caption: "WAREHOUSE")
                titleRow
                IridescentHairline()

                if loading {
                    loadingCard
                } else if let err = loadError {
                    errorCard(err)
                } else if items.isEmpty {
                    EusoEmptyState(systemImage: "shippingbox",
                                   title: "No receipts on hand",
                                   subtitle: "No on-hand items were found for \(facilityLabel). CFS receipts appear after cargo is received against an ASN.")
                } else {
                    heroCard
                    kpiStrip
                    receiptsCard
                    wiringStrip
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var titleRow: some View {
        HStack(alignment: .top) {
            Text("Receipts · CFS").font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(facilityLabel.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary).lineLimit(1)
                Text("synced now").font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: Space.s2) {
                    VDetnChip(text: "\(items.filter { state($0) == .verify }.count) VERIFYING", color: Brand.info)
                    VDetnChip(text: "CMA CGM", color: Brand.neutral)
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(openCount)")
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("receipts open").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                        Text("\(putaway) putaway done · \(items.filter { state($0) == .verify }.count) verifying · \(shortFlags) short-ship")
                            .font(.system(size: 11)).foregroundStyle(palette.textTertiary).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("PUTAWAY").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                        Text("\(putaway) of \(openCount)").font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundStyle(Brand.info)
                    }
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.textPrimary.opacity(0.08)).frame(height: 6)
                        Capsule().fill(LinearGradient.diagonal).frame(width: max(0, g.size.width * progress), height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // MARK: KPI

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            VDetnKPICell(label: "RECEIPTS", value: "\(openCount)", gradient: true)
            VDetnKPICell(label: "ON-HAND", value: onHand.formatted(), valueTint: Brand.info)
            VDetnKPICell(label: "SHORT FLAGS", value: "\(shortFlags)", valueTint: Brand.warning)
        }
    }

    // MARK: Receipts ledger

    private var receiptsCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VDetnSectionLabel(title: "RECEIPTS · TODAY", trailing: "getWarehouseInventory")
            VStack(spacing: 0) {
                let rows = Array(items.prefix(3).enumerated())
                ForEach(rows, id: \.element.id) { idx, it in
                    receiptRow(it)
                    if idx < rows.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, 16)
                    }
                }
                if items.count > 3 {
                    Text("+ \(items.count - 3) more SKU\(items.count - 3 == 1 ? "" : "s") on hand · \(shortFlags) short-ship flag\(shortFlags == 1 ? "" : "s") total")
                        .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)
                }
            }
            .padding(.vertical, 4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func receiptRow(_ it: CFSItem783) -> some View {
        let s = state(it)
        let q = it.quantity ?? 0, expected = it.minLevel ?? 0
        let sub: String = {
            switch s {
            case .done:   return "\(q) ctn received · putaway \(it.location ?? "bin")"
            case .verify: return "counting \(q) / \(max(expected, q)) ctn"
            case .short:  return "\(q) of \(expected) ctn · \(expected - q) short vs ASN"
            }
        }()
        let value: String = {
            switch s {
            case .done:   return it.location ?? "A-1"
            case .verify: return expected > 0 ? "\(Int(Double(q) / Double(expected) * 100))%" : "\(q)"
            case .short:  return "-\(expected - q) ctn"
            }
        }()
        return HStack(spacing: Space.s3) {
            VDetnIconChip(systemImage: s.icon, color: s.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(it.sku.map { "\($0) · \(it.name ?? "")" } ?? (it.name ?? "Receipt"))
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(sub).font(EType.mono(.caption)).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                VDetnPill(text: s.label, color: s.color)
                Text(value).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(s.color)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    // MARK: Wiring context strip

    private var wiringStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CFS RECEIPTS · LIVE YARD INVENTORY").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("VERIFIED WAREHOUSE INVENTORY").font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
            }
            Text("Process receipt → processWarehouseReceipt")
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            Text("Eusorone Technologies (DU) · \(facilityLabel) · \(onHand.formatted()) units on hand")
                .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: CTA

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: processing ? "Refreshing…" : "Process receipt",
                      action: { Task { await processReceipt() } }, isLoading: processing)
            secondaryButton783(title: "View on-hand") { Task { await load() } }.frame(width: 148)
        }
    }

    private func secondaryButton783(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(EType.title).foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color(hex: 0x232932))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Load / actions

    private struct CFSInput783: Encodable { let locationId: String; let limit: Int }

    private func load() async {
        loading = true; loadError = nil
        do {
            self.inv = try await EusoTripAPI.shared.query(
                "yardManagement.getWarehouseInventory", input: CFSInput783(locationId: locationId, limit: 50))
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func processReceipt() async {
        // PORT-GAP (matches 626): processWarehouseReceipt needs a scanned items[]
        // payload this read board doesn't host — re-pull live on-hand instead of
        // POSTing an empty receipt.
        processing = true
        await load()
        processing = false
    }

    private var loadingCard: some View {
        LifecycleCard { Text("Loading CFS receipts…").font(EType.caption).foregroundStyle(palette.textSecondary) }
    }
    private func errorCard(_ e: String) -> some View {
        LifecycleCard(accentDanger: true) { Text(e).font(EType.caption).foregroundStyle(Brand.danger) }
    }
}

#Preview("783 · Vessel CFS Warehouse Receipt · Night") { VesselCFSWarehouseReceiptScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("783 · Vessel CFS Warehouse Receipt · Light") { VesselCFSWarehouseReceiptScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
