//
//  612_RailTransloadInventory.swift
//  EusoTrip — Rail Engineer · Transload Inventory (carrier-side load-out queue).
//
//  The transload-pad load-out queue: inbound containers/cars staged for
//  cross-dock to outbound trailers. A KPI strip (scheduled / in-progress /
//  completed / total) over a FIFO order list — each order shows the inbound →
//  outbound mode hop, commodity, pallets, and status. Floor-loaded orders carry
//  a heavier-labor marker.
//
//  Live wiring: multiModal.getTransloading (tenant-scoped, paginated). Honest:
//  no orders → an honest empty state, never a fabricated queue.
//

import SwiftUI

struct RailTransloadInventoryScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailTransloadInventoryBody() } nav: {
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

// MARK: - Decodable model (matches multiModal.getTransloading)

private struct TransloadOrder612: Decodable, Identifiable {
    let id: String
    let orderNumber: String?
    let status: String?      // scheduled | in_progress | completed | cancelled
    let inboundMode: String?
    let outboundMode: String?
    let inboundContainer: String?
    let outboundTrailers: [String]?
    let facility: String?
    let commodity: String?
    let weight: Int?
    let palletCount: Int?
    let scheduledDate: String?
    let floorLoaded: Bool?
}

private struct TransloadResponse612: Decodable {
    let orders: [TransloadOrder612]?
    let total: Int?
}

// MARK: - Body

private struct RailTransloadInventoryBody: View {
    @Environment(\.palette) private var palette
    @State private var orders: [TransloadOrder612] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    private func statusColor(_ s: String?) -> Color {
        switch s {
        case "in_progress": return Brand.info
        case "completed":   return Brand.success
        case "cancelled":   return palette.textTertiary
        default:             return Brand.warning   // scheduled
        }
    }

    private func count(_ s: String) -> Int { orders.filter { $0.status == s }.count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                headline
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading transload queue…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    kpiStrip
                    if orders.isEmpty {
                        LifecycleCard { Text("No transload orders queued.").font(EType.caption).foregroundStyle(palette.textSecondary) }
                    } else {
                        queue
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.swap").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text("RAIL ENGINEER · TRANSLOAD INVENTORY").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Transload inventory")
                .font(.system(size: 28, weight: .heavy)).kerning(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
    }

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "SCHEDULED", value: "\(count("scheduled"))", accent: Brand.warning)
            MetricTile(label: "IN PROG",   value: "\(count("in_progress"))", accent: Brand.info)
            MetricTile(label: "DONE",      value: "\(count("completed"))", accent: Brand.success)
            MetricTile(label: "TOTAL",     value: "\(orders.count)", gradientNumeral: true)
        }
    }

    private var queue: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("LOAD-OUT QUEUE · FIFO")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            VStack(spacing: Space.s2) {
                ForEach(orders) { o in orderRow(o) }
            }
        }
    }

    private func orderRow(_ o: TransloadOrder612) -> some View {
        let color = statusColor(o.status)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(o.orderNumber ?? o.id)
                            .font(.system(size: 13, weight: .bold)).monospaced().foregroundStyle(palette.textPrimary)
                        if o.floorLoaded == true {
                            Text("FLOOR")
                                .font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.warning)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Capsule().fill(Brand.warning.opacity(0.16)))
                        }
                    }
                    // Inbound → outbound mode hop
                    HStack(spacing: 5) {
                        Text((o.inboundMode ?? "rail").uppercased())
                            .font(.system(size: 10, weight: .heavy)).foregroundStyle(palette.textSecondary)
                        Image(systemName: "arrow.right").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
                        Text((o.outboundMode ?? "truck").uppercased())
                            .font(.system(size: 10, weight: .heavy)).foregroundStyle(palette.textSecondary)
                        Text("· \(o.commodity ?? "—")")
                            .font(EType.caption).foregroundStyle(palette.textTertiary).lineLimit(1)
                    }
                }
                Spacer()
                Text((o.status ?? "scheduled").replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(color.opacity(0.14)))
            }
            HStack(spacing: Space.s3) {
                Label(o.inboundContainer ?? "—", systemImage: "shippingbox.fill")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary).lineLimit(1)
                Spacer()
                Text("\(o.palletCount ?? 0) plt · \(o.outboundTrailers?.count ?? 0) trl")
                    .font(.system(size: 11, weight: .bold)).monospacedDigit().foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func load() async {
        loading = true; loadError = nil
        struct Input: Encodable { let page: Int; let limit: Int }
        do {
            let resp: TransloadResponse612 = try await EusoTripAPI.shared.query("multiModal.getTransloading", input: Input(page: 1, limit: 50))
            self.orders = resp.orders ?? []
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("612 · Rail Transload Inventory · Night") { RailTransloadInventoryScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("612 · Rail Transload Inventory · Light") { RailTransloadInventoryScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
