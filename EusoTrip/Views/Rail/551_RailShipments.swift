//
//  551_RailShipments.swift
//  EusoTrip — Rail Engineer · Shipments list.
//

import SwiftUI

struct RailShipmentsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailShipmentsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct RailShipment: Decodable, Identifiable {
    let id: String
    let loadId: String?
    let origin: String?
    let destination: String?
    let status: String?
    let carsCount: Int?
    let commodity: String?
    let estimatedArrival: String?
    let carrierName: String?
    let hazmat: Bool?
}

// MARK: - Filter

private enum RailShipmentFilter: String, CaseIterable {
    case all       = "All"
    case inTransit = "In Transit"
    case delayed   = "Delayed"
    case delivered = "Delivered"
}

// MARK: - Body

private struct RailShipmentsBody: View {
    @Environment(\.palette) private var palette
    @State private var shipments: [RailShipment] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var searchText: String = ""
    @State private var activeFilter: RailShipmentFilter = .all

    private var filtered: [RailShipment] {
        var list = shipments
        switch activeFilter {
        case .all:       break
        case .inTransit: list = list.filter { ["in_transit", "active"].contains(($0.status ?? "").lowercased()) }
        case .delayed:   list = list.filter { ($0.status ?? "").lowercased() == "delayed" }
        case .delivered: list = list.filter { ($0.status ?? "").lowercased() == "delivered" }
        }
        guard !searchText.isEmpty else { return list }
        let q = searchText.lowercased()
        return list.filter {
            ($0.origin ?? "").lowercased().contains(q) ||
            ($0.destination ?? "").lowercased().contains(q) ||
            ($0.commodity ?? "").lowercased().contains(q) ||
            ($0.loadId ?? "").lowercased().contains(q)
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
                        systemImage: "tram.fill",
                        title: searchText.isEmpty ? "No shipments" : "No results for \(searchText)",
                        subtitle: searchText.isEmpty
                            ? "Rail shipments assigned to you will appear here."
                            : "Try a different origin, destination, or commodity."
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
                Image(systemName: "shippingbox")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("RAIL ENGINEER · SHIPMENTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Rail shipments")
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
                let inTransit = shipments.filter { ["in_transit","active"].contains(($0.status ?? "").lowercased()) }.count
                let delayed   = shipments.filter { ($0.status ?? "").lowercased() == "delayed" }.count
                HStack(spacing: 8) {
                    if inTransit > 0 {
                        Text("\(inTransit) in transit").font(EType.caption).foregroundStyle(Brand.success)
                    }
                    if delayed > 0 {
                        Text("· \(delayed) delayed").font(EType.caption).foregroundStyle(Brand.warning)
                    }
                }
            }
        }
    }

    // MARK: - Search + Filter

    private var searchAndFilter: some View {
        VStack(spacing: Space.s2) {
            // Search field
            HStack(spacing: Space.s2) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.textTertiary)
                TextField("Search origin, destination, commodity…", text: $searchText)
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

            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(RailShipmentFilter.allCases, id: \.self) { f in
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

    private func shipmentRow(_ s: RailShipment) -> some View {
        let statusKind: StatusPill.Kind = {
            switch (s.status ?? "").lowercased() {
            case "in_transit", "active": return .success
            case "delayed":              return .warning
            case "exception":            return .danger
            case "delivered":            return .neutral
            default:                     return .info
            }
        }()
        let isDanger = (s.status ?? "").lowercased() == "exception"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Mode glyph
                modeBadge(for: s)
                // Route + commodity
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
                    if let commodity = s.commodity {
                        Text(commodity)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer()
                StatusPill(text: (s.status ?? "—").replacingOccurrences(of: "_", with: " ").uppercased(),
                           kind: statusKind)
            }
            // Lifecycle progress strip — animates its filled segment into
            // the real lifecycle stage resolved from `status`.
            RailLifecycleStrip(stageIndex: stageIndex(s.status ?? ""), stages: 7)
            // Meta row
            HStack(spacing: Space.s3) {
                if let cars = s.carsCount {
                    Label("\(cars) cars", systemImage: "tram.fill")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                if let eta = s.estimatedArrival {
                    Label("ETA \(eta)", systemImage: "clock")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                if let carrier = s.carrierName {
                    Label(carrier, systemImage: "building.2")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
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

    private func modeBadge(for s: RailShipment) -> some View {
        let (icon, color): (String, Color) = {
            if s.hazmat == true { return ("exclamationmark.triangle.fill", Brand.hazmat) }
            let c = (s.commodity ?? "").lowercased()
            if c.contains("grain") || c.contains("bulk") || c.contains("hopper") { return ("cylinder.fill", Brand.neutral) }
            if c.contains("tank") || c.contains("liquid") { return ("drop.fill", Brand.info) }
            return ("tram.fill", Brand.rail)
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

    private func stageIndex(_ status: String) -> Int {
        switch status.lowercased() {
        case "posted":                      return 0
        case "assigned":                    return 1
        case "in_yard":                     return 2
        case "in_transit", "active":        return 3
        case "delayed":                     return 4
        case "arrived":                     return 5
        case "delivered", "settled":        return 6
        default:                            return 3
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct ListIn: Encodable { let limit: Int; let offset: Int }
        do {
            let result: [RailShipment] = try await EusoTripAPI.shared.query(
                "railShipments.getRailShipments",
                input: ListIn(limit: 50, offset: 0)
            )
            self.shipments = result
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Lifecycle strip

/// Compact 7-dot lifecycle progress strip for a rail shipment row.
///
/// The filled segment is bound to the REAL lifecycle stage: `stageIndex`
/// is resolved upstream from the server `status` enum (posted → assigned →
/// in_yard → in_transit → delayed → arrived → delivered). Nothing here is
/// decorative — the gradient fill always terminates at the dot for the
/// shipment's actual stage.
///
/// Motion: on first appear (and on any status flip) the fill animates from
/// stage 0 into the real `stageIndex` with a single decel spring, and the
/// active dot pops with a soft spring + glow. Under Reduce Motion the strip
/// renders straight into its final filled state with no spring or pulse.
private struct RailLifecycleStrip: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Real lifecycle stage index resolved from the server status.
    let stageIndex: Int
    let stages: Int

    /// The index the fill currently animates toward. Starts at 0 so the
    /// gradient sweeps into the real stage on appear; reduce-motion snaps
    /// straight to `stageIndex`.
    @State private var shownIndex: Int = 0

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<stages, id: \.self) { i in
                let reached = i <= shownIndex
                let isActive = i == shownIndex
                Circle()
                    .fill(reached ? AnyShapeStyle(LinearGradient.primary)
                                  : AnyShapeStyle(palette.bgCardSoft))
                    .frame(width: isActive ? 8 : 5, height: isActive ? 8 : 5)
                    .shadow(color: isActive ? Brand.magenta.opacity(reduceMotion ? 0 : 0.45) : .clear,
                            radius: isActive ? 4 : 0)
                    .scaleEffect(isActive ? 1.0 : 0.92)
                    .animation(reduceMotion ? nil
                                            : .spring(response: 0.34, dampingFraction: 0.78),
                               value: isActive)
                if i < stages - 1 {
                    GeometryReader { geo in
                        // Backdrop hairline.
                        Rectangle()
                            .fill(palette.bgCardSoft)
                            .frame(height: 1.5)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        // Filled hairline — width tracks whether this segment
                        // is behind the reached stage. Animates in with the
                        // settle spring so the fill sweeps left→right.
                        Rectangle()
                            .fill(LinearGradient.primary)
                            .frame(width: i < shownIndex ? geo.size.width : 0, height: 1.5)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 1.5)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: 10)
        .onAppear {
            if reduceMotion {
                shownIndex = stageIndex
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                    shownIndex = stageIndex
                }
            }
        }
        .onChange(of: stageIndex) { _, newValue in
            if reduceMotion {
                shownIndex = newValue
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                    shownIndex = newValue
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Lifecycle stage \(stageIndex + 1) of \(stages)")
    }
}

#Preview("551 · Rail Shipments · Night") { RailShipmentsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("551 · Rail Shipments · Light") { RailShipmentsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
