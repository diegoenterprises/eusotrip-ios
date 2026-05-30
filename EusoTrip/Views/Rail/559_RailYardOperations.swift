//
//  559_RailYardOperations.swift
//  EusoTrip — Rail Engineer · Yard Operations (BOARD archetype).
//
//  Verbatim port of "559 Rail Yard Operations · Dark" (05 Rail).
//  Status swim-lanes (ON ROUTE · STAGING/USMCA · RAMP) of full-width yard
//  rows, each carrying a relative-capacity bar (slot capacity scaled to the
//  largest yard on the route) + track counts + status pill + railroad disc.
//  Route RAIL-260523-7C3A0B12D4 · BNSF transcon · Corwith → Argentine → LPC.
//
//  Web parity: app/(rail)/yards/page.tsx.
//  tRPC (server/routers/railShipments.ts):
//    ON ROUTE + STAGING lanes ← railShipments.getRailYards (yards; country
//      filter; capacity=carSlots, totalTracks). RBAC: railProcedure.
//    "Yard directory" CTA → railShipments.getRailYards (full list).
//    "Map" CTA → railShipments.getRailTracking (yard pins on the map).
//  PORT-GAP: RAMP shelf / per-facility staging detail wants
//    railShipments.getFacilityStatus(railroad, facilityCode) — a per-facility
//    call with no batch wrapper and no Swift API shim; the ramp shelf is
//    derived from the intermodal yards returned by getRailYards instead.
//

import SwiftUI

struct RailYardOperationsScreen: View {
    let theme: Theme.Palette
    var id: String = ""
    var body: some View {
        Shell(theme: theme) { RailYardOperationsBody() } nav: {
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

// MARK: - Data shapes (railShipments.getRailYards → rail_yards rows)

private struct RailYard559: Decodable, Identifiable {
    let id: Int
    let name: String?
    let splcCode: String?
    let railroadId: Int?
    let city: String?
    let state: String?
    let country: String?
    let yardType: String?
    let totalTracks: Int?
    let capacity: Int?
    let hasIntermodal: Bool?
    let hasHazmat: Bool?
    let status: String?
}

// MARK: - Lane model

private enum YardPill {
    case active, hazmat, ramp, staging

    var label: String {
        switch self {
        case .active:  return "ACTIVE"
        case .hazmat:  return "HAZMAT"
        case .ramp:    return "RAMP"
        case .staging: return "STAGING"
        }
    }
    var color: Color {
        switch self {
        case .active:  return Brand.success
        case .hazmat:  return Brand.warning
        case .ramp:    return Brand.blue
        case .staging: return Color(hex: 0x90A4AE)
        }
    }
    var disc: Color {
        switch self {
        case .active:  return Color(hex: 0x2BD9A4)
        case .hazmat:  return Brand.warning
        case .ramp:    return Color(hex: 0x4FB0FF)
        case .staging: return Color(hex: 0x90A4AE)
        }
    }
}

// MARK: - Body

private struct RailYardOperationsBody: View {
    @Environment(\.palette) private var palette
    @State private var yards: [RailYard559] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    private let routeId = "RAIL-260523-7C3A0B12D4"

    // Lane partitions ---------------------------------------------------------

    private var stagingYards: [RailYard559] {
        yards.filter { ($0.yardType ?? "").lowercased() == "staging" }
    }
    private var onRouteYards: [RailYard559] {
        yards.filter { ($0.yardType ?? "").lowercased() != "staging" }
    }
    private var rampYards: [RailYard559] {
        yards.filter { ($0.hasIntermodal ?? false) || ($0.yardType ?? "").lowercased() == "intermodal_ramp" }
    }

    /// Largest car-slot capacity on the board — the relative-capacity bars
    /// scale every row against this so saturation reads at a glance.
    private var maxCapacity: Double {
        let cap = yards.compactMap { $0.capacity }.map(Double.init).max() ?? 0
        return cap > 0 ? cap : 1
    }

    private func pill(for y: RailYard559) -> YardPill {
        if (y.hasHazmat ?? false) && ((y.yardType ?? "").lowercased() == "classification") { return .hazmat }
        switch (y.yardType ?? "").lowercased() {
        case "staging":         return .staging
        case "intermodal_ramp": return .ramp
        default:                return .active
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                if loading {
                    loadingBlock
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    .padding(.horizontal, 20).padding(.top, 16)
                } else if yards.isEmpty {
                    EusoEmptyState(systemImage: "square.stack.3d.up",
                                   title: "No yards on this route",
                                   subtitle: "Yards the consist will touch will appear here.")
                        .padding(.horizontal, 20).padding(.top, 24)
                } else {
                    filterChips
                        .padding(.horizontal, 20).padding(.top, 14)

                    // Lane 1 · ON ROUTE
                    laneHeader(title: "ON ROUTE · \(onRouteYards.count)", color: Color(hex: 0x2BD9A4))
                    onRouteCard
                        .padding(.horizontal, 20).padding(.top, 8)

                    // Lane 2 · STAGING · USMCA
                    if !stagingYards.isEmpty {
                        laneHeader(title: "STAGING · USMCA · \(stagingYards.count)", color: Color(hex: 0x90A4AE))
                        stagingCard
                            .padding(.horizontal, 20).padding(.top, 8)
                    }

                    // Lane 3 · RAMP · intermodal shelf
                    if !rampYards.isEmpty {
                        laneHeader(title: "RAMP · \(rampYards.count) INTERMODAL", color: palette.textTertiary)
                        rampShelf
                            .padding(.horizontal, 20).padding(.top, 8)
                    }

                    ctaPair
                        .padding(.horizontal, 20).padding(.top, 20)
                }

                Color.clear.frame(height: 96)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Top bar (route-scoped)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("RAIL ENGINEER · YARD OPS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text(routeId)
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Yard operations")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 8)
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .rotationEffect(.degrees(90))
            }
            .padding(.top, Space.s4)
            Text(routeSubtitle)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.leading, 24)
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, Space.s5)
    }

    private var routeSubtitle: String {
        // "BNSF transcon · Corwith → Argentine → LPC" — derived from the
        // on-route yards in railroad order; falls back to the route name.
        let names = onRouteYards.compactMap { $0.name }
        if names.count >= 2 {
            return names.prefix(3).joined(separator: " → ")
        }
        return "Yards on route \(routeId)"
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        let hazmatCount = onRouteYards.filter { pill(for: $0) == .hazmat }.count
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(text: "All · \(yards.count)", fg: .white, active: true)
                chip(text: "On route · \(onRouteYards.count)", fg: Color(hex: 0x2BD9A4), active: false)
                chip(text: "Hazmat · \(hazmatCount)", fg: Brand.warning, active: false)
                chip(text: "Staging · \(stagingYards.count)", fg: Color(hex: 0x90A4AE), active: false)
            }
        }
    }

    private func chip(text: String, fg: Color, active: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy)).tracking(0.4)
            .foregroundStyle(active ? .white : fg)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .frame(height: 26)
            .background(
                Group {
                    if active { AnyView(LinearGradient.primary) }
                    else      { AnyView(palette.bgCardSoft) }
                }
            )
            .overlay(
                Capsule().strokeBorder(active ? Color.clear : palette.borderSoft, lineWidth: 1)
            )
            .clipShape(Capsule())
    }

    // MARK: - Lane header

    private func laneHeader(title: String, color: Color) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(color)
                Spacer()
                Text("see all ›")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    // MARK: - Lane 1 · ON ROUTE card (yard rows w/ relative-capacity bars)

    private var onRouteCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(onRouteYards.enumerated()), id: \.element.id) { idx, y in
                yardRow(y)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                if idx < onRouteYards.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                        .padding(.horizontal, 16)
                }
            }
        }
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Lane 2 · STAGING card

    private var stagingCard: some View {
        VStack(spacing: 0) {
            ForEach(stagingYards) { y in
                yardRow(y)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
            }
        }
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Yard row (icon disc · name · meta · capacity bar · pill · count)

    private func yardRow(_ y: RailYard559) -> some View {
        let kind = pill(for: y)
        let cap = Double(y.capacity ?? 0)
        let frac = max(0.04, min(1.0, cap / maxCapacity))
        let metaParts: [String] = [
            [y.city, y.state].compactMap { $0 }.joined(separator: " "),
            railroadName(y.railroadId),
            stagingMeta(y) ?? "\(y.totalTracks ?? 0) tracks"
        ].filter { !$0.isEmpty }
        let meta = metaParts.joined(separator: " · ")

        return HStack(alignment: .top, spacing: 0) {
            // Icon disc
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(kind.color.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "rectangle.split.1x2")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(kind.disc)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    Text(y.name ?? "Yard")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 8)
                    // Status pill
                    Text(kind.label)
                        .font(.system(size: 10.5, weight: .bold)).tracking(0.4)
                        .foregroundStyle(kind.disc)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(kind.color.opacity(0.16)))
                }
                Text(meta)
                    .font(EType.mono(.caption)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, 4)
                    .lineLimit(1).minimumScaleFactor(0.7)

                // Capacity bar + slot count row
                HStack(alignment: .bottom, spacing: 12) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.14))
                                .frame(height: 6)
                            Capsule().fill(kind.disc)
                                .frame(width: max(6, geo.size.width * frac), height: 6)
                        }
                    }
                    .frame(height: 6)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(capacityString(y.capacity))
                            .font(.system(size: 14, weight: .bold)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                        Text(kind == .staging ? "\(y.totalTracks ?? 0) tracks" : "car slots")
                            .font(.system(size: 9, weight: .regular))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .fixedSize()
                }
                .padding(.top, 12)
            }
            .padding(.leading, 12)
        }
    }

    private func capacityString(_ cap: Int?) -> String {
        guard let cap = cap else { return "—" }
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        return fmt.string(from: NSNumber(value: cap)) ?? "\(cap)"
    }

    /// Staging rows surface the SPLC + interchange instead of a city.
    private func stagingMeta(_ y: RailYard559) -> String? {
        guard (y.yardType ?? "").lowercased() == "staging" else { return nil }
        var parts: [String] = []
        if let splc = y.splcCode, !splc.isEmpty { parts.append("SPLC \(splc)") }
        parts.append(railroadName(y.railroadId))
        parts.append("USMCA interchange")
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Map railroadId → reporting mark. We don't have a railroad-name join in
    /// this query, so render the AAR mark from the id where known and fall
    /// back to the raw id. // PORT-GAP: railShipments.getRailYards does not
    /// join rail_carriers — no reporting mark is returned with the yard row.
    private func railroadName(_ id: Int?) -> String {
        guard let id = id else { return "" }
        return "RR-\(id)"
    }

    // MARK: - Lane 3 · RAMP intermodal shelf (facility cards)

    private var rampShelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(rampYards.prefix(3)) { y in
                    rampCard(y)
                }
            }
        }
    }

    private func rampCard(_ y: RailYard559) -> some View {
        let dot: Color = {
            switch pill(for: y) {
            case .hazmat:  return Brand.warning
            case .ramp:    return Brand.blue
            case .staging: return Color(hex: 0x90A4AE)
            case .active:  return Color(hex: 0x00C48C)
            }
        }()
        let line2: String = (y.status ?? "open").lowercased() == "active" ? "open · accepting" : (y.status ?? "open · accepting")
        let line3 = [railroadName(y.railroadId), y.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Circle().fill(dot).frame(width: 7, height: 7)
                Text("\(shortName(y.name)) ramp")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.leading, 8)
                    .lineLimit(1)
            }
            Text(line2)
                .font(.system(size: 9.5, weight: .regular))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 16)
                .lineLimit(1)
            Text(line3)
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 4)
                .lineLimit(1)
        }
        .padding(14)
        .frame(width: 124, height: 64, alignment: .topLeading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func shortName(_ name: String?) -> String {
        guard let name = name else { return "Yard" }
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: 8) {
            Button(action: { Task { await loadDirectory() } }) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.split.1x2")
                        .font(.system(size: 14, weight: .bold))
                    Text("Yard directory")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient.primary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button(action: { NotificationCenter.default.post(name: .eusoRailNavSwap, object: nil, userInfo: ["screenId": "Rail560"]) }) {
                Text("Map")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(palette.bgCard)
                    .overlay(Capsule().strokeBorder(palette.borderSoft, lineWidth: 1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading skeleton

    private var loadingBlock: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 88)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
        }
        .padding(.horizontal, 20).padding(.top, 16)
    }

    // MARK: - Load

    private struct YardsIn: Encodable {
        let country: String?
        let limit: Int
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let rows: [RailYard559] = try await EusoTripAPI.shared.query(
                "railShipments.getRailYards", input: YardsIn(country: nil, limit: 50))
            self.yards = rows
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// "Yard directory" CTA — full list, no route filter (getRailYards).
    private func loadDirectory() async {
        do {
            let rows: [RailYard559] = try await EusoTripAPI.shared.query(
                "railShipments.getRailYards", input: YardsIn(country: nil, limit: 50))
            self.yards = rows
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("559 · Rail Yard Operations · Night") { RailYardOperationsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("559 · Rail Yard Operations · Light") { RailYardOperationsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
