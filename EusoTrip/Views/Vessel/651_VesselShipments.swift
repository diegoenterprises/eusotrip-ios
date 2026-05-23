//
//  651_VesselShipments.swift
//  EusoTrip — Vessel Operator · Shipments list (container bookings).
//

import SwiftUI

struct VesselShipmentsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselShipmentsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct VesselShipment: Decodable, Identifiable {
    let id: String
    let bookingNumber: String?
    let origin: String?
    let destination: String?
    let status: String?
    let containersCount: Int?
    let commodity: String?
    let vessel: String?
    let eta: String?
    let etd: String?
}

// MARK: - Body

private struct VesselShipmentsBody: View {
    @Environment(\.palette) private var palette
    @State private var shipments: [VesselShipment] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var searchText: String = ""

    private var filtered: [VesselShipment] {
        guard !searchText.isEmpty else { return shipments }
        let q = searchText.lowercased()
        return shipments.filter {
            ($0.origin ?? "").lowercased().contains(q) ||
            ($0.destination ?? "").lowercased().contains(q) ||
            ($0.vessel ?? "").lowercased().contains(q) ||
            ($0.bookingNumber ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                searchBar
                if loading {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCardSoft).frame(height: 90)
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                        .strokeBorder(palette.borderFaint))
                    }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else if filtered.isEmpty {
                    EusoEmptyState(
                        systemImage: "shippingbox.fill",
                        title: searchText.isEmpty ? "No shipments" : "No results for \(searchText)",
                        subtitle: searchText.isEmpty
                            ? "Vessel shipments assigned to you will appear here."
                            : "Try a different origin, destination, or vessel name."
                    )
                } else {
                    VStack(spacing: Space.s2) {
                        ForEach(filtered) { s in shipmentRow(s) }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · SHIPMENTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            HStack {
                Text("Vessel shipments").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Spacer()
                if !shipments.isEmpty {
                    Text("\(shipments.count) total")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.textTertiary)
            TextField("Search origin, destination, vessel…", text: $searchText)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func shipmentRow(_ s: VesselShipment) -> some View {
        let statusColor: Color = {
            switch (s.status ?? "").lowercased() {
            case "in_transit", "at_sea":  return Brand.success
            case "at_port":               return Brand.info
            case "delayed":               return Brand.warning
            case "exception":             return Brand.danger
            case "delivered":             return palette.textTertiary
            default:                      return palette.textSecondary
            }
        }()
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(s.origin ?? "—").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        Image(systemName: "arrow.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.textTertiary)
                        Text(s.destination ?? "—").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    }
                    if let vessel = s.vessel {
                        Text(vessel).font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer()
                Text((s.status ?? "—").replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(statusColor.opacity(0.5), lineWidth: 1))
            }
            HStack(spacing: Space.s3) {
                if let containers = s.containersCount {
                    Label("\(containers) containers", systemImage: "shippingbox")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                if let eta = s.eta {
                    Label("ETA \(eta)", systemImage: "clock")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                if let bkng = s.bookingNumber {
                    Label(bkng, systemImage: "doc.text")
                        .font(EType.mono(.micro)).tracking(0.4).foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func load() async {
        loading = true; loadError = nil
        struct ListIn: Encodable { let limit: Int; let offset: Int }
        do {
            let result: [VesselShipment] = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipments",
                input: ListIn(limit: 50, offset: 0)
            )
            self.shipments = result
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("651 · Vessel Shipments · Night") { VesselShipmentsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("651 · Vessel Shipments · Light") { VesselShipmentsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
