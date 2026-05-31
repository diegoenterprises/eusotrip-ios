//
//  626_RailWarehouseReceipt.swift
//  EusoTrip — Rail Engineer · Warehouse Receipt (CARRIER-SIDE · transload receiving).
//
//  Verbatim port of "626 Rail Warehouse Receipt.svg" (Dark).
//  Carrier-vantage rail-engineer surface — transload warehouse receiving with
//  ASN reconciliation. Back chevron + eyebrow + title 28/-0.4, gradient-rimmed
//  hero ActiveCard (lead figure + progress), 3-cell KPI strip (OPEN · VERIFYING ·
//  PUTAWAY), itemized warehouse-receipt ListRow stack (40x40 icon chip + WR id +
//  mono sub + short status pill + right tabular value), ON-HAND · INVENTORY
//  context strip, Process receipt / Inventory CTA pair.
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME).
//
//  Data (grep-confirmed in-repo this fire):
//    yardManagement.getWarehouseInventory   (EXISTS yardManagement.ts:1314)  query
//        → { items[], summary{ totalItems, totalValue, lowStockAlerts, categories }, lowStockAlerts[] }
//    yardManagement.processWarehouseReceipt (EXISTS yardManagement.ts:1383)  mutation
//        → "Process receipt" CTA target
//
//  PORT-GAP: there is NO per-receipt list endpoint (warehouseReceipts.getById /
//    warehouseReceipts.list do not exist in EusoTripAPI.swift or the server router).
//    The named WR-#### receipts (with ASN-reconcile DONE/VERIFY/SHORT state) have
//    no backing query, so the RECEIPTS · TODAY rail derives from the live
//    getWarehouseInventory items and renders a real empty/error state when no
//    inventory is on hand. See `// PORT-GAP:` markers below.
//

import SwiftUI

struct RailWarehouseReceiptScreen: View {
    let theme: Theme.Palette
    var locationId: String = "JOLIET-CFS"

    var body: some View {
        Shell(theme: theme) { RailWarehouseReceiptBody(locationId: locationId) } nav: {
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

// MARK: - Data shapes (yardManagement.getWarehouseInventory)

private struct WarehouseInventory626: Decodable {
    let items: [InventoryItem626]?
    let summary: InventorySummary626?
    let lowStockAlerts: [InventoryItem626]?
}

private struct InventoryItem626: Decodable, Identifiable {
    let id: String
    let sku: String?
    let name: String?
    let category: String?
    let quantity: Int?
    let unit: String?
    let location: String?
    let minLevel: Int?
    let maxLevel: Int?
    let lastReceived: String?
    let lastShipped: String?
    let value: Double?
}

private struct InventorySummary626: Decodable {
    let totalItems: Int?
    let totalValue: Double?
    let lowStockAlerts: Int?
    let categories: Int?
}

// processWarehouseReceipt mutation response
private struct ProcessReceiptResult626: Decodable {
    let success: Bool?
    let receiptId: String?
    let itemsReceived: Int?
    let totalQuantity: Int?
    let processedAt: String?
}

// MARK: - Body

private struct RailWarehouseReceiptBody: View {
    @Environment(\.palette) private var palette
    let locationId: String

    @State private var inventory: WarehouseInventory626? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var isProcessing = false

    // MARK: Derived (from live inventory — receipt rails reconcile against on-hand)

    private var items: [InventoryItem626] { inventory?.items ?? [] }

    /// Open receipts ≈ distinct SKUs currently received but not yet putaway-complete.
    /// PORT-GAP: no receipt-status field on inventory; "open" is the live item count.
    private var openCount: Int { items.count }

    /// Verifying ≈ low-stock-alert items (the ones the count flags for re-check).
    private var verifyingCount: Int { inventory?.summary?.lowStockAlerts ?? (inventory?.lowStockAlerts?.count ?? 0) }

    /// Putaway-complete ≈ items at or above their max level (received + shelved).
    private var putawayCount: Int {
        items.filter { ($0.quantity ?? 0) >= ($0.maxLevel ?? Int.max) }.count
    }

    private var onHandUnits: Int { items.reduce(into: 0) { acc, it in acc += (it.quantity ?? 0) } }
    private var skuCount: Int { inventory?.summary?.categories ?? Set(items.compactMap { $0.sku }).count }

    private var progressFraction: CGFloat {
        let total = openCount + putawayCount
        guard total > 0 else { return 0 }
        return CGFloat(putawayCount) / CGFloat(total)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow
                titleBlock
                IridescentHairline()
                    .padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s5) {
                    heroCard
                    kpiStrip
                    receiptsCard
                    onHandStrip
                    ctaPair
                    Color.clear.frame(height: 96)
                }
                .padding(.top, Space.s5)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Eyebrow

    private var eyebrow: some View {
        HStack {
            Text("✦  RAIL ENGINEER · WAREHOUSE RECEIPT")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("TRANSLOAD")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Title block (back chevron + title + carrier badge)

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 6)
            Text("Warehouse")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("BNSF INTERMODAL")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text("synced 5m ago")
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(.top, Space.s4)
    }

    // MARK: - Hero ActiveCard (gradient-rimmed)

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pills row
            HStack(spacing: Space.s2) {
                Text("transload")
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                Text("\(verifyingCount) verifying")
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(Capsule().fill(Brand.warning.opacity(0.20)))
                Spacer()
            }

            // Lead figure + caption  ·  right JOLIET CFS / DONE
            HStack(alignment: .top, spacing: Space.s3) {
                Text("\(openCount)")
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("receipts open")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Text("\(locationLabel) · on-hand \(onHandUnits.formatted()) units")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(locationLabel.uppercased())
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text("\(putawayCount) DONE")
                        .font(.system(size: 16, weight: .bold, design: .monospaced)).tracking(0.2)
                        .foregroundStyle(Brand.success)
                }
            }
            .padding(.top, Space.s4)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                        .frame(height: 6)
                    Capsule().fill(LinearGradient.diagonal)
                        .frame(width: max(0, geo.size.width * progressFraction), height: 6)
                }
            }
            .frame(height: 6)
            .padding(.top, Space.s4)
        }
        .padding(Space.s5)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.85), lineWidth: 1.5)
        )
    }

    private var locationLabel: String {
        // Humanize the locationId token → "Joliet CFS" reading per the SVG.
        if let loc = items.compactMap({ $0.location }).first, !loc.isEmpty { return loc }
        return "Joliet CFS"
    }

    // MARK: - 3-cell KPI strip (OPEN · VERIFYING · PUTAWAY)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            kpiCell(label: "OPEN", value: "\(openCount)",
                    valueColor: .white, filled: true)
            kpiCell(label: "VERIFYING", value: "\(verifyingCount)",
                    valueColor: Brand.warning, filled: false)
            kpiCell(label: "PUTAWAY", value: "\(putawayCount)",
                    valueColor: Brand.success, filled: false)
        }
    }

    private func kpiCell(label: String, value: String, valueColor: Color, filled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(filled ? Color.white.opacity(0.85) : palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(valueColor)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 72)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(filled ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(filled ? Color.clear : palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - RECEIPTS · TODAY card

    private var receiptsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("RECEIPTS · TODAY")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("yardManagement.ts:1314")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, Space.s3)

            if loading {
                receiptsCardBox {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCardSoft).frame(height: 48)
                    }
                }
            } else if let err = loadError {
                receiptsCardBox {
                    HStack(spacing: Space.s2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Brand.danger)
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                            .lineLimit(3)
                    }
                }
            } else if items.isEmpty {
                receiptsCardBox {
                    EusoEmptyReceipts()
                }
            } else {
                receiptsCardBox {
                    VStack(spacing: 0) {
                        ForEach(Array(items.prefix(3).enumerated()), id: \.element.id) { idx, it in
                            receiptRow(it)
                            if idx < min(items.count, 3) - 1 {
                                Rectangle().fill(palette.borderFaint).frame(height: 1)
                                    .padding(.vertical, Space.s2)
                            }
                        }
                        if items.count > 3 {
                            let extraSkus = items.count - 3
                            let shortFlags = items.filter { ($0.quantity ?? 0) < ($0.minLevel ?? 0) }.count
                            Text("+ \(extraSkus) more SKU\(extraSkus == 1 ? "" : "s") on hand · \(shortFlags) short-ship flag\(shortFlags == 1 ? "" : "s") total")
                                .font(.system(size: 10))
                                .foregroundStyle(palette.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, Space.s3)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func receiptsCardBox<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    /// Reconcile each on-hand SKU against its ASN target (minLevel = expected count).
    /// DONE   = at/above expected · VERIFY = within expected · SHORT = under expected.
    private func receiptRow(_ it: InventoryItem626) -> some View {
        let qty = it.quantity ?? 0
        let expected = it.minLevel ?? 0
        let max = it.maxLevel ?? Int.max
        let state: ReceiptState626 = {
            if qty >= max && max != Int.max { return .done }
            if qty < expected { return .short }
            return .verify
        }()
        let delta = qty - expected
        return HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(state.color.opacity(state == .short ? 0.18 : 0.20))
                    .frame(width: 40, height: 40)
                Image(systemName: state.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(state.tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(it.sku.map { "\($0) · \(it.name ?? "")" } ?? (it.name ?? "Receipt"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(state.sub(qty: qty, expected: expected, delta: delta, location: it.location))
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 8) {
                Text(state.label)
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(state.tint)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(state.color.opacity(0.22)))
                Text(state == .short ? "\(delta)" : "\(qty)")
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(state.tint)
            }
        }
    }

    // MARK: - ON-HAND · INVENTORY context strip

    private var onHandStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("ON-HAND · INVENTORY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("yardManagement.ts:1383")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("\(onHandUnits.formatted()) units on hand · \(skuCount) SKUs · \(putawayCount) putaway complete today")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text("Eusorone Technologies (DU) · RAIL-260524-9C20A7E15B · \(locationLabel)")
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Process receipt",
                      action: { Task { await processReceipt() } },
                      isLoading: isProcessing)
            Button {
                // Inventory drill — wired through nav; on this surface re-pulls live on-hand.
                Task { await reload() }
            } label: {
                Text("Inventory")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 52)
                    .background(Color(hex: 0x232932))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.10)))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load / Actions

    private func reload() async {
        loading = true; loadError = nil
        struct InvIn: Encodable { let locationId: String; let limit: Int }
        do {
            let inv: WarehouseInventory626 = try await EusoTripAPI.shared.query(
                "yardManagement.getWarehouseInventory",
                input: InvIn(locationId: locationId, limit: 50))
            self.inventory = inv
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func processReceipt() async {
        isProcessing = true
        // PORT-GAP: processWarehouseReceipt requires an items[] payload captured
        // from an ASN-scan flow that this surface does not yet host; without a
        // scanned manifest there is nothing to commit, so we re-pull live on-hand
        // to reflect the latest receiving state rather than POST an empty receipt.
        await reload()
        isProcessing = false
    }
}

// MARK: - Receipt reconciliation state

private enum ReceiptState626 {
    case done, verify, short

    var label: String {
        switch self {
        case .done:   return "DONE"
        case .verify: return "VERIFY"
        case .short:  return "SHORT"
        }
    }
    var color: Color {
        switch self {
        case .done:   return Brand.success
        case .verify: return Brand.warning
        case .short:  return Brand.danger
        }
    }
    var tint: Color {
        switch self {
        case .done:   return Color(hex: 0x34D8A6)
        case .verify: return Color(hex: 0xF5B544)
        case .short:  return Color(hex: 0xFF6B5E)
        }
    }
    var icon: String {
        switch self {
        case .done, .verify: return "shippingbox"
        case .short:         return "exclamationmark.triangle"
        }
    }
    func sub(qty: Int, expected: Int, delta: Int, location: String?) -> String {
        let bin = (location?.isEmpty == false) ? location! : "—"
        switch self {
        case .done:   return "\(qty) ctn received · putaway \(bin)"
        case .verify: return "counting \(qty) / \(expected) ctn"
        case .short:  return "short vs ASN · \(abs(delta)) ctn \(delta < 0 ? "under" : "over")"
        }
    }
}

// MARK: - Empty state (no live inventory → no derivable receipts)

private struct EusoEmptyReceipts: View {
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "shippingbox")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(palette.textTertiary)
            Text("No receipts on hand")
                .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text("Transload warehouse receipts will appear here once inventory is received against an ASN.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s4)
    }
}

#Preview("626 · Rail Warehouse Receipt · Night") { RailWarehouseReceiptScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("626 · Rail Warehouse Receipt · Light") { RailWarehouseReceiptScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
