//
//  665_RailYardSlotInventory.swift
//  EusoTrip — Rail Engineer · Yard Slot Inventory (Dark + Light · verbatim
//  port of "05 Rail / 665 Rail Yard Slot Inventory.svg").
//
//  ARCHETYPE = SLOT SCHEMATIC (the one schematic in the band — not a capacity
//  meter, not the 628 geographic yard map, not the 639 yard directory): a
//  track×slot occupancy grid drawn from the real yard spots colored by state
//  (occupied / reserved / bad-order / open), an OPEN / RESERVED / TURN triad,
//  a BLOCKED-and-RESERVED queue of slots needing a decision, a spotting-plan
//  suggestion, a tri-country units band, and a Reserve / Yard-map CTA pair.
//
//  WIRING (grep-confirmed · frontend/server/routers/yardManagement.ts):
//    • occupancy + triad → getYardDashboard (query · :106)
//        { capacity{ total, occupied, available, utilizationPct },
//          trailerSummary{ reserved }, avgTurnTimeMinutes }.
//    • slot schematic    → getYardMap (query · :371)
//        input { locationId }; { rows, cols, spots[{ row, col, label, status,
//        trailerNumber, type }] }.
//    • location resolve  → getYardLocations (query · :273).
//    HONEST NOTE: the SVG's per-railcar slot occupancy (which reporting mark
//    sits in slot B2-8) is a proposed gap — railYard.slotOccupancy (handed to
//    the-oath). getYardMap returns TRAILER/CHASSIS spots, so the schematic is
//    drawn from real yard spots; the spotting plan is a client derivation over
//    the live open cells, not a server ESANG call. Reserve routes through the
//    proposed updateTrailerPosition reserve verb. Tri-country units band is a
//    presentation toggle.
//
//  RBAC: protectedProcedure. transportMode=rail · US (AAR classification yard).
//  NAV (RailEngineerNavController): current = SHIPMENTS.
//

import SwiftUI

struct RailYardSlotInventoryScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailYardSlotInventoryBody() } nav: {
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

// MARK: - Decodables

private struct YardDashboard665: Decodable {
    struct Capacity: Decodable { let total: Int?; let occupied: Int?; let available: Int?; let utilizationPct: Double? }
    struct TrailerSummary: Decodable { let reserved: Int? }
    let capacity: Capacity?
    let trailerSummary: TrailerSummary?
    let avgTurnTimeMinutes: Double?
}
private struct YardMap665: Decodable {
    struct Spot: Decodable, Identifiable {
        let id: String
        let row: Int?
        let col: Int?
        let label: String?
        let status: String?          // empty | occupied | reserved | maintenance
        let trailerNumber: String?
        let type: String?
    }
    let rows: Int?
    let cols: Int?
    let spots: [Spot]?
}
private struct YardLocations665: Decodable {
    struct Loc: Decodable { let id: String; let name: String? }
    let locations: [Loc]
}

private enum YardUnits665: String, CaseIterable, Identifiable {
    case us, ca, mx
    var id: String { rawValue }
    var title: String { self == .us ? "US · feet" : (self == .ca ? "CA · metres" : "MX · metros") }
    var sub: String { self == .us ? "Class I · UP·BNSF" : (self == .ca ? "CN·CPKC" : "FXE·CPKC-MX") }
}

// MARK: - Body

private struct RailYardSlotInventoryBody: View {
    @Environment(\.palette) private var palette

    @State private var dash: YardDashboard665? = nil
    @State private var map: YardMap665? = nil
    @State private var yardName: String = "Yard"
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var units: YardUnits665 = .us
    @State private var ack: String? = nil

    private var spots: [YardMap665.Spot] { map?.spots ?? [] }

    private var occupied: Int { dash?.capacity?.occupied ?? spots.filter { $0.status == "occupied" }.count }
    private var total: Int { dash?.capacity?.total ?? spots.count }
    private var available: Int { dash?.capacity?.available ?? spots.filter { $0.status == "empty" }.count }
    private var reserved: Int { dash?.trailerSummary?.reserved ?? spots.filter { $0.status == "reserved" }.count }
    private var badOrder: Int { spots.filter { $0.status == "maintenance" }.count }
    private var utilPct: Int {
        if let p = dash?.capacity?.utilizationPct { return Int(p.rounded()) }
        return total > 0 ? Int((Double(occupied) / Double(total) * 100).rounded()) : 0
    }
    private var turnMinutes: Int { Int((dash?.avgTurnTimeMinutes ?? 0).rounded()) }

    private struct TrackGroup665: Identifiable {
        let row: Int
        let cells: [YardMap665.Spot]
        var id: Int { row }
    }

    /// Spots grouped into rows for the schematic (real row/col layout).
    private var rowGroups: [TrackGroup665] {
        let grouped = Dictionary(grouping: spots) { $0.row ?? 0 }
        return grouped.keys.sorted().prefix(6).map { r in
            TrackGroup665(row: r, cells: (grouped[r] ?? []).sorted { ($0.col ?? 0) < ($1.col ?? 0) })
        }
    }

    /// Largest contiguous run of open cells in any row — the spotting target.
    private var contiguousOpen: (row: Int, count: Int)? {
        var bestRow = -1
        var bestRun = 0
        for group in rowGroups {
            var run = 0
            for cell in group.cells {
                if (cell.status ?? "") == "empty" { run += 1 } else { run = 0 }
                if run > bestRun { bestRun = run; bestRow = group.row }
            }
        }
        guard bestRun >= 2, bestRow >= 0 else { return nil }
        return (row: bestRow, count: bestRun)
    }

    private let blockedStates: Set<String> = ["reserved", "maintenance"]
    private var blockedSpots: [YardMap665.Spot] {
        spots.filter { blockedStates.contains($0.status ?? "") }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                titleBlock
                IridescentHairline()

                if loading {
                    loadingState
                } else if let err = loadError {
                    errorCard(err)
                } else {
                    schematicHero
                    triad
                    blockedQueue
                    spottingPlan
                    unitsBand
                    if let ack {
                        Text(ack).font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: Eyebrow + title

    private var eyebrow: some View {
        HStack {
            Text("✦ RAIL ENGINEER · YARD SLOTS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text(yardName.uppercased())
                .font(EType.mono(.micro)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Slot inventory")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            Text("\(utilPct)% FULL")
                .font(.system(size: 10, weight: .heavy)).tracking(0.3)
                .foregroundStyle(Brand.warning)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Brand.warning.opacity(0.16)).clipShape(Capsule())
        }
    }

    // MARK: Schematic hero

    private var schematicHero: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("CLASSIFICATION BOWL · \(rowGroups.count) LEAD TRACKS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(occupied)")
                    .font(.system(size: 30, weight: .bold)).monospacedDigit()
                    .foregroundStyle(LinearGradient.primary)
                Text("/\(total)")
                    .font(.system(size: 15)).monospacedDigit()
                    .foregroundStyle(palette.textTertiary)
                    .padding(.trailing, 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text("slots used").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("\(available) open · \(reserved) reserved")
                        .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }

            if rowGroups.isEmpty {
                EusoEmptyState(
                    icon: Image(systemName: "square.grid.3x3"),
                    title: "No slot layout",
                    subtitle: "The schematic draws from getYardMap spots. No spot rows resolved for this yard yet.",
                    comingSoon: false
                )
            } else {
                VStack(spacing: 6) {
                    ForEach(rowGroups) { group in
                        trackRow(group)
                    }
                }
                legend
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.3), Brand.magenta.opacity(0.3)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private func trackRow(_ group: TrackGroup665) -> some View {
        HStack(spacing: 5) {
            Text(trackLabel(group.row))
                .font(.system(size: 9, weight: .heavy)).monospaced()
                .foregroundStyle(palette.textSecondary)
                .frame(width: 22, alignment: .trailing)
            HStack(spacing: 3) {
                ForEach(group.cells) { cell in
                    slotCell(cell)
                }
            }
        }
    }

    private func trackLabel(_ row: Int) -> String {
        // A1, A2, B1, B2 … from the row index.
        let letter = Character(UnicodeScalar(65 + row / 2)!)
        return "\(letter)\(row % 2 + 1)"
    }

    private func slotCell(_ cell: YardMap665.Spot) -> some View {
        let (fill, border): (Color, Color) = {
            switch cell.status ?? "empty" {
            case "occupied":    return (Brand.info.opacity(0.85), .clear)
            case "reserved":    return (Brand.warning.opacity(0.9), .clear)
            case "maintenance": return (Brand.danger.opacity(0.9), .clear)
            default:            return (Color.white.opacity(0.05), palette.borderFaint)
            }
        }()
        return RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(fill)
            .overlay(RoundedRectangle(cornerRadius: 2.5, style: .continuous).strokeBorder(border, lineWidth: 1))
            .frame(height: 13)
            .frame(maxWidth: .infinity)
    }

    private var legend: some View {
        HStack(spacing: Space.s4) {
            legendItem(Brand.info.opacity(0.85), "OCCUPIED", occupied)
            legendItem(Brand.warning.opacity(0.9), "RESERVED", reserved)
            legendItem(Brand.danger.opacity(0.9), "B/O", badOrder)
            legendItem(Color.white.opacity(0.10), "OPEN", available)
            Spacer(minLength: 0)
        }
    }

    private func legendItem(_ color: Color, _ label: String, _ count: Int) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color).frame(width: 11, height: 9)
            Text(label).font(.system(size: 8.5, weight: .bold)).foregroundStyle(palette.textSecondary)
            Text("\(count)").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: Triad

    private var triad: some View {
        HStack(spacing: Space.s2) {
            triadCell("OPEN SLOTS", "\(available)",
                      sub: contiguousOpen.map { "\($0.count) ON \(trackLabel($0.row)) CONTIG" } ?? "scattered",
                      gradient: true)
            triadCell("RESERVED", "\(reserved)", sub: reserved > 0 ? "held" : "none", gradient: false, accent: Brand.warning)
            triadCell("TURN", turnMinutes > 0 ? "\(turnMinutes)m" : "—", sub: "avg dwell→out", gradient: false, accent: Brand.info)
        }
    }

    private func triadCell(_ label: String, _ value: String, sub: String, gradient: Bool, accent: Color = .clear) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.5)
                .foregroundStyle(gradient ? .white.opacity(0.85) : palette.textTertiary)
            Group {
                if gradient { Text(value).foregroundStyle(.white) }
                else { Text(value).foregroundStyle(accent == .clear ? palette.textPrimary : accent) }
            }
            .font(.system(size: 24, weight: .bold)).monospacedDigit()
            Text(sub)
                .font(.system(size: 8, weight: .heavy)).tracking(0.2)
                .foregroundStyle(gradient ? .white.opacity(0.9) : (accent == .clear ? palette.textTertiary : accent))
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background(gradient ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(gradient ? Color.clear : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Blocked & reserved queue

    private var blockedQueue: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("BLOCKED & RESERVED").font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("needs a call").font(.system(size: 9)).foregroundStyle(palette.textTertiary)
            }
            if blockedSpots.isEmpty {
                Text("No held or fouled slots — the bowl is clear.")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(blockedSpots.prefix(4).enumerated()), id: \.element.id) { idx, s in
                        blockedRow(s)
                        if idx < min(blockedSpots.count, 4) - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                                .padding(.vertical, Space.s3)
                        }
                    }
                }
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private func blockedRow(_ s: YardMap665.Spot) -> some View {
        let fouled = (s.status ?? "") == "maintenance"
        let color: Color = fouled ? Brand.danger : Brand.warning
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.16)).frame(width: 40, height: 40)
                Image(systemName: fouled ? "wrench.and.screwdriver" : "lock")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(s.label ?? "slot")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(fouled ? "\(s.trailerNumber ?? "car") · awaiting shop" : "\(s.trailerNumber ?? "hold") · reserved")
                    .font(EType.mono(.caption)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            Text(fouled ? "FOULED" : "RESERVED")
                .font(.system(size: 10, weight: .heavy)).tracking(0.3)
                .foregroundStyle(color)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(color.opacity(0.14)).clipShape(Capsule())
        }
    }

    // MARK: Spotting plan

    private var spottingPlan: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 30, height: 30)
                Text("E").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let c = contiguousOpen {
                    Text("Commit \(trackLabel(c.row)) — \(c.count) contiguous open — to the next inbound cut")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(c.count) contiguous open · spot before it holds on the lead")
                        .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                } else {
                    Text("No contiguous open block — build room before the next cut arrives")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(available) open scattered · pull to consolidate")
                        .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.3), Brand.magenta.opacity(0.3)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Units band

    private var unitsBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("YARD SLOTS · UNITS & NETWORK BY COUNTRY")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                ForEach(YardUnits665.allCases) { u in
                    let active = u == units
                    Button { units = u } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(u.title)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(active ? Color.white : palette.textPrimary)
                            Text(u.sub)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(active ? Color.white.opacity(0.9) : palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                        .frame(minHeight: 44)
                        .background(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCard))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(active ? Color.clear : palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button { reserveSlots() } label: {
                Text("Reserve slots")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)

            RailSecondaryActionButton(
                title: "Yard map",
                sheetTitle: "Yard summary",
                lines: [
                    "Yard: \(yardName)",
                    "Utilization: \(utilPct)%",
                    "Occupied: \(occupied) / \(total)",
                    "Open: \(available) · reserved: \(reserved) · fouled: \(badOrder)",
                    "Avg turn: \(turnMinutes > 0 ? "\(turnMinutes)m" : "—")",
                    contiguousOpen.map { "Best block: \($0.count) on \(trackLabel($0.row))" } ?? "No contiguous block"
                ],
                systemImage: "map"
            )
        }
    }

    private func reserveSlots() {
        if let c = contiguousOpen {
            ack = "Reserve \(c.count) on \(trackLabel(c.row)) — commit routes through the yard reserve verb (updateTrailerPosition), pending on the router (handed to the-oath)."
        } else {
            ack = "No contiguous open block to reserve. Pull to consolidate first."
        }
    }

    // MARK: States

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 216)
            HStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 70)
                }
            }
        }
    }

    private func errorCard(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.danger)
            Text(msg).font(EType.caption).foregroundStyle(Brand.danger)
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Data

    private func reload() async {
        loading = true; loadError = nil
        do {
            self.dash = try await EusoTripAPI.shared.queryNoInput("yardManagement.getYardDashboard")

            struct LocInput: Encodable { let status: String }
            let locs: YardLocations665 = try await EusoTripAPI.shared.query(
                "yardManagement.getYardLocations", input: LocInput(status: "active"))
            if let loc = locs.locations.first {
                self.yardName = loc.name ?? "Yard"
                struct MapInput: Encodable { let locationId: String }
                self.map = try await EusoTripAPI.shared.query(
                    "yardManagement.getYardMap", input: MapInput(locationId: loc.id))
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("665 · Rail Yard Slot Inventory · Night") {
    RailYardSlotInventoryScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("665 · Rail Yard Slot Inventory · Light") {
    RailYardSlotInventoryScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
