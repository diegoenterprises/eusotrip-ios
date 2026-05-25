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
    let reefer: Bool?
    let hazmat: Bool?
}

// MARK: - Filter

private enum VesselShipmentFilter: String, CaseIterable {
    case all       = "All"
    case atSea     = "At Sea"
    case delayed   = "Delayed"
    case atPort    = "At Port"
    case delivered = "Delivered"
}

// MARK: - Body

private struct VesselShipmentsBody: View {
    @Environment(\.palette) private var palette
    @State private var shipments: [VesselShipment] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var searchText: String = ""
    @State private var activeFilter: VesselShipmentFilter = .all

    private var filtered: [VesselShipment] {
        var list = shipments
        switch activeFilter {
        case .all:       break
        case .atSea:     list = list.filter { ["in_transit", "at_sea"].contains(($0.status ?? "").lowercased()) }
        case .delayed:   list = list.filter { ($0.status ?? "").lowercased() == "delayed" }
        case .atPort:    list = list.filter { ($0.status ?? "").lowercased() == "at_port" }
        case .delivered: list = list.filter { ($0.status ?? "").lowercased() == "delivered" }
        }
        guard !searchText.isEmpty else { return list }
        let q = searchText.lowercased()
        return list.filter {
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
                searchAndFilter
                if loading {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCardSoft).frame(height: 96)
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
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header

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
            HStack(alignment: .firstTextBaseline) {
                Text("Vessel shipments")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if !shipments.isEmpty {
                    Text("\(shipments.count)")
                        .font(.system(size: 22, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(palette.textTertiary)
                }
            }
            if !shipments.isEmpty {
                let atSea    = shipments.filter { ["in_transit","at_sea"].contains(($0.status ?? "").lowercased()) }.count
                let delayed  = shipments.filter { ($0.status ?? "").lowercased() == "delayed" }.count
                let reefer   = shipments.filter { $0.reefer == true }.count
                HStack(spacing: 8) {
                    if atSea > 0 {
                        Text("\(atSea) at sea").font(EType.caption).foregroundStyle(Brand.success)
                    }
                    if delayed > 0 {
                        Text("· \(delayed) delayed").font(EType.caption).foregroundStyle(Brand.warning)
                    }
                    if reefer > 0 {
                        Text("· \(reefer) reefer").font(EType.caption).foregroundStyle(Brand.info)
                    }
                }
            }
        }
    }

    // MARK: - Search + Filter

    private var searchAndFilter: some View {
        VStack(spacing: Space.s2) {
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(VesselShipmentFilter.allCases, id: \.self) { f in
                        let isActive = activeFilter == f
                        Button { withAnimation(.easeInOut(duration: 0.15)) { activeFilter = f } } label: {
                            Text(f.rawValue)
                                .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(isActive ? .white : palette.textSecondary)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(isActive ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCard))
                                .overlay(Capsule().strokeBorder(isActive ? Color.clear : palette.borderFaint))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Shipment row

    private func shipmentRow(_ s: VesselShipment) -> some View {
        let statusKind: StatusPill.Kind = {
            switch (s.status ?? "").lowercased() {
            case "in_transit", "at_sea": return .success
            case "at_port":              return .info
            case "delayed":              return .warning
            case "exception":            return .danger
            case "delivered":            return .neutral
            default:                     return .info
            }
        }()
        let isDanger = (s.status ?? "").lowercased() == "exception"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                modeBadge(for: s)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(s.origin ?? "—")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text(s.destination ?? "—")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                    }
                    if let vessel = s.vessel {
                        Text(vessel)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer()
                StatusPill(text: (s.status ?? "—").replacingOccurrences(of: "_", with: " ").uppercased(),
                           kind: statusKind)
            }
            // Lifecycle strip (7 stages: Booked → Gate In → Loaded → At Sea → Arrived → Discharged → Delivered)
            lifecycleStrip(status: s.status ?? "")
            // Meta + booking number
            HStack(spacing: Space.s3) {
                if let containers = s.containersCount {
                    Label("\(containers) ctrs", systemImage: "shippingbox")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                if let eta = s.eta {
                    Label("ETA \(eta)", systemImage: "clock")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                if let bkng = s.bookingNumber {
                    Spacer()
                    Text(bkng)
                        .font(EType.mono(.micro)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(Space.s3)
        .background(isDanger ? Brand.danger.opacity(0.04) : palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(isDanger ? Brand.danger.opacity(0.40) : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Mode badge

    private func modeBadge(for s: VesselShipment) -> some View {
        let (icon, color): (String, Color) = {
            if s.hazmat == true                    { return ("exclamationmark.triangle.fill", Brand.hazmat) }
            if s.reefer == true                    { return ("thermometer.snowflake", Brand.info) }
            let c = (s.commodity ?? "").lowercased()
            if c.contains("bulk") || c.contains("grain") { return ("cylinder.fill", Brand.neutral) }
            return ("shippingbox.fill", Brand.vessel)
        }()
        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.12))
                .frame(width: 38, height: 38)
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    // MARK: - Lifecycle strip

    private func lifecycleStrip(status: String) -> some View {
        let stages = 7
        let idx = stageIndex(status)
        return HStack(spacing: 0) {
            ForEach(0..<stages, id: \.self) { i in
                Circle()
                    .fill(i <= idx ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCardSoft))
                    .frame(width: i == idx ? 8 : 5, height: i == idx ? 8 : 5)
                if i < stages - 1 {
                    Rectangle()
                        .fill(i < idx ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCardSoft))
                        .frame(height: 1.5)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: 10)
    }

    private func stageIndex(_ status: String) -> Int {
        switch status.lowercased() {
        case "booked", "booking_confirmed":        return 0
        case "gate_in", "container_released":      return 1
        case "loaded", "loaded_on_vessel":         return 2
        case "in_transit", "at_sea", "departed":   return 3
        case "arrived", "at_port":                 return 4
        case "discharged", "customs_cleared":      return 5
        case "delivered", "gate_out", "settled":   return 6
        default:                                   return 3
        }
    }

    // MARK: - Load

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
