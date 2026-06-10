//
//  402_CatalystCapacityPlanner.swift
//  EusoTrip 2027 UI — Catalyst track · carrier network-intelligence band
//
//  Moment: a carrier sells the empty truck-days it can SEE. This is a BOARD/grid
//          archetype — NOT the home/detail skeleton: a utilization hero with a
//          committed/open/maintenance stacked bar, a 7-day availability HEAT-GRID
//          (every unit × every day, committed=gradient / open=faint / maint=amber),
//          and an open-window list that turns each gap into a post or auto-match.
//          The grid is the bespoke element — it maps idle capacity at a glance so a
//          truck never sits unsold.
//
//  SwiftUI twin of 03 Catalyst/Dark-SVG/402 Catalyst Capacity Planner.svg.
//  Web peer: /catalyst/dispatch/capacity. transportMode=truck; country=US.
//  Persona: Eusotrans LLC · Michael Eusorone owner-op · 6 trucks.
//
//  LIVE WIRING (zero-fallback purge · 2026-06-09 · audit B13):
//    • utilization hero + stacked bar → capacityPlanning.getCapacityDashboard (capacityPlanning.ts:65)
//    • 7-day grid + open windows      → carrierCapacity.getCapacityCalendar   (carrierCapacity.ts:22)
//      (real per-day availableTrucks; grid cells fill proportionally, count
//       labels show the true available/fleet numbers)
//  Both decoded in-file against the exact server projections. Anything with
//  no live source (open miles) renders an honest em-dash; honest
//  EusoEmptyState when no calendar/fleet exists. The seeded 6-truck week
//  and invented best-match RPM rows are GONE.
//
//  Bottom nav (Catalyst variant): HOME · DISPATCH · [orb] · WALLET · ME (DISPATCH current).
//

import SwiftUI

// MARK: - Shell wrapper

struct CatalystCapacityPlannerScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette) {
        self.theme = theme
    }

    var body: some View {
        Shell(theme: theme) {
            CapacityBody_402()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_402(),
                trailing: catalystNavTrailing_402(),
                orbState: .idle
            )
        }
    }
}

// MARK: - Catalyst BottomNav (HOME · DISPATCH · [orb] · WALLET · ME — DISPATCH current)

private func catalystNavLeading_402() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house.fill", isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "tray.full",  isCurrent: true)]
}

private func catalystNavTrailing_402() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard",  isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person.fill", isCurrent: false)]
}

// MARK: - View model

private enum CapacityCell_402 { case committed, open, maintenance }

private struct CapacityDay_402: Identifiable {
    let id: String          // "Thu 30"
    let dow: String         // "Thu"
    let date: String        // "30"
    let cells: [CapacityCell_402]   // one per unit, top→bottom
    let countLabel: String  // "4/6"
    let countHot: Bool      // ink the count blue when there's open capacity
}

private struct OpenWindow_402: Identifiable {
    let id: String          // unit
    let unit: String        // "261"
    let title: String       // "Unit 261 · Dallas TX"
    let window: String      // mono "open Thu–Fri · dry van · 1,040 open mi"
    let match: String       // "best match: DFW → Memphis $2.18/mi"
}

private struct CapacityVM_402 {
    let utilization: String         // "78%"
    let openSlots: String           // "5 truck-days"
    let openMiles: String           // "2,140 mi"
    let committedFrac: Double       // 33/42
    let openFrac: Double            // 5/42
    let maintFrac: Double           // 1/42
    let barCaption: String
    let unitCount: String           // "6 units"
    let openWindowHeader: String    // "2 of 5"
    let days: [CapacityDay_402]
    let openWindows: [OpenWindow_402]
    let insightTitle: String
    let insightSub: String
}

// MARK: - Body

private struct CapacityBody_402: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @State private var vm: CapacityVM_402 = .empty
    @State private var loading: Bool = true
    @State private var loadError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
            VStack(alignment: .leading, spacing: Space.s4) {
                heroCard
                gridSection
                openWindowSection
                insightRow
                ctaPair
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s7)
        }
        .task { await loadAll_402() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await loadAll_402() }
        }
    }

    // MARK: TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ CATALYST · CAPACITY")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("NEXT 7 DAYS")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("Back to Dispatch")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Capacity")
                        .font(EType.display)
                        .foregroundStyle(palette.textPrimary)
                    Text("\(vm.unitCount) · committed vs open")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }
            .padding(.top, Space.s2)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    // MARK: Hero · fleet utilization

    private var heroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: Radius.xl - 1.5, style: .continuous)
                .fill(palette.bgCard)
                .padding(1.5)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FLEET UTILIZATION · 7-DAY")
                            .font(EType.micro).tracking(1.0)
                            .foregroundStyle(palette.textTertiary)
                        Text(vm.utilization)
                            .font(.system(size: 38, weight: .bold).monospacedDigit())
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("OPEN SLOTS")
                            .font(EType.micro).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(vm.openSlots)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Brand.blue)
                        Text("OPEN MILES")
                            .font(EType.micro).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                            .padding(.top, 2)
                        Text(vm.openMiles)
                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                stackedBar.padding(.top, Space.s4)
                Text(vm.barCaption)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, Space.s2)
            }
            .padding(Space.s4)
        }
        .frame(height: 136)
    }

    private var stackedBar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 4) {
                Capsule().fill(LinearGradient.primary)
                    .frame(width: w * vm.committedFrac)
                Capsule().fill(Brand.blue.opacity(0.20))
                    .frame(width: w * vm.openFrac)
                Capsule().fill(Brand.hazmat.opacity(0.7))
                    .frame(width: max(8, w * vm.maintFrac))
                Spacer(minLength: 0)
            }
        }
        .frame(height: 10)
        .accessibilityLabel("Utilization \(vm.utilization)")
    }

    // MARK: 7-day availability heat-grid

    private var gridSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("7-DAY AVAILABILITY GRID")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(vm.unitCount)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Group {
                if vm.days.isEmpty {
                    EusoEmptyState(
                        systemImage: "calendar",
                        title: loading ? "Loading availability…" : "No capacity calendar yet",
                        subtitle: loading ? "" : (loadError ?? "Your fleet's 7-day availability grid appears here once vehicles and loads are on file.")
                    )
                    .padding(.vertical, Space.s3)
                    .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 0) {
                        ForEach(vm.days) { day in
                            VStack(spacing: 4) {
                                Text(day.dow)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(palette.textSecondary)
                                Text(day.date)
                                    .font(.system(size: 8))
                                    .foregroundStyle(palette.textTertiary)
                                VStack(spacing: 4) {
                                    ForEach(Array(day.cells.enumerated()), id: \.offset) { _, cell in
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(cellStyle(cell))
                                            .frame(height: 12)
                                    }
                                }
                                .padding(.top, 2)
                                Text(day.countLabel)
                                    .font(.system(size: 9, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(day.countHot ? Brand.blue : palette.textPrimary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s3)
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private func cellStyle(_ c: CapacityCell_402) -> AnyShapeStyle {
        switch c {
        case .committed:   return AnyShapeStyle(Brand.blue)
        case .open:        return AnyShapeStyle(Brand.blue.opacity(0.14))
        case .maintenance: return AnyShapeStyle(Brand.hazmat.opacity(0.7))
        }
    }

    // MARK: Open-window list

    private var openWindowSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("OPEN WINDOWS · SELLABLE NOW")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(vm.openWindowHeader)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                if vm.openWindows.isEmpty {
                    EusoEmptyState(
                        systemImage: "truck.box",
                        title: loading ? "Loading open windows…" : "No open windows this week",
                        subtitle: loading ? "" : "Days with unsold truck capacity appear here so they can be posted or auto-matched."
                    )
                    .padding(.vertical, Space.s3)
                } else {
                    ForEach(Array(vm.openWindows.enumerated()), id: \.element.id) { idx, w in
                        openRow(w)
                        if idx < vm.openWindows.count - 1 {
                            Rectangle().fill(palette.borderFaint)
                                .frame(height: 1)
                                .padding(.leading, 52)
                        }
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private func openRow(_ w: OpenWindow_402) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm + 2)
                    .fill(Brand.blue.opacity(0.12))
                Text(w.unit)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Brand.blue)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(w.title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(w.window)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
                Text(w.match)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.blue)
            }
            Spacer(minLength: Space.s2)
            Text("OPEN")
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                .foregroundStyle(Brand.blue)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Capsule().fill(Brand.blue.opacity(0.14)))
        }
        .padding(Space.s4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(w.title), open, \(w.match)")
    }

    // MARK: ESang insight row

    private var insightRow: some View {
        Button {
            NotificationCenter.default.post(
                name: .eusoCatalystCapacityInsight_402, object: nil,
                userInfo: ["source": "402_CatalystCapacityPlanner"])
        } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                    Circle().fill(RadialGradient(
                        colors: [.white.opacity(0.75), .clear],
                        center: .init(x: 0.35, y: 0.30), startRadius: 0, endRadius: 16))
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.insightTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text(vm.insightSub)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button {
                NotificationCenter.default.post(
                    name: .eusoCatalystCapacityPost_402, object: nil,
                    userInfo: ["source": "402_CatalystCapacityPlanner"])
            } label: {
                Text("Post open trucks")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            Button {
                NotificationCenter.default.post(
                    name: .eusoCatalystCapacityAutoMatch_402, object: nil,
                    userInfo: ["source": "402_CatalystCapacityPlanner"])
            } label: {
                Text("Auto-match")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 144, height: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Network (LIVE — getCapacityDashboard + getCapacityCalendar)

    private struct CapacityDashWire_402: Decodable {
        let totalTrucks: Int
        let availableTrucks: Int
        let inUseTrucks: Int
        let maintenanceTrucks: Int
        let totalDrivers: Int
        let activeLoads: Int
        let pendingLoads: Int
        let utilizationPct: Int
        let demandTrend: String
        let capacityStatus: String
    }
    private struct CalendarSlotWire_402: Decodable {
        let date: String
        let dayOfWeek: String
        let availableTrucks: Int
        let status: String
    }
    private struct CalendarWeekWire_402: Decodable {
        let weekStart: String
        let weekEnd: String
        let totalAvailableTruckDays: Int
        let slots: [CalendarSlotWire_402]
    }
    private struct CalendarWire_402: Decodable {
        let carrierId: Int
        let companyName: String?
        let fleetSize: Int
        let weeks: [CalendarWeekWire_402]
    }
    private struct CalendarInput_402: Encodable { let carrierId: Int; let weeks: Int }
    private struct EmptyInput_402: Encodable {}

    private func loadAll_402() async {
        loading = true
        loadError = nil
        defer { loading = false }

        do {
            let dash: CapacityDashWire_402 = try await EusoTripAPI.shared.query(
                "capacityPlanning.getCapacityDashboard", input: EmptyInput_402())

            var calendar: CalendarWire_402? = nil
            if let cidString = session.user?.companyId, let cid = Int(cidString) {
                calendar = try? await EusoTripAPI.shared.query(
                    "carrierCapacity.getCapacityCalendar",
                    input: CalendarInput_402(carrierId: cid, weeks: 1))
            }

            vm = buildVM_402(dash: dash, calendar: calendar)
        } catch {
            vm = .empty
            loadError = "Couldn't reach the capacity service - retry."
        }
    }

    private func buildVM_402(dash: CapacityDashWire_402, calendar: CalendarWire_402?) -> CapacityVM_402 {
        let total = max(0, dash.totalTrucks)
        let frac: (Int) -> Double = { total > 0 ? Double($0) / Double(total) : 0 }

        // 7-day grid from the REAL capacity calendar (proportional cell fill).
        var days: [CapacityDay_402] = []
        var openWindows: [OpenWindow_402] = []
        let week = calendar?.weeks.first
        if let week, let fleet = calendar?.fleetSize, fleet > 0 {
            let displayCells = min(fleet, 6)
            for slot in week.slots.prefix(7) {
                let available = max(0, min(fleet, slot.availableTrucks))
                let committed = fleet - available
                let committedCells = Int((Double(committed) / Double(fleet) * Double(displayCells)).rounded())
                var cells: [CapacityCell_402] = []
                for i in 0..<displayCells {
                    cells.append(i < committedCells ? .committed : .open)
                }
                let dayNum = String(slot.date.suffix(2))
                days.append(CapacityDay_402(
                    id: slot.date,
                    dow: String(slot.dayOfWeek.prefix(3)),
                    date: dayNum,
                    cells: cells,
                    countLabel: "\(available)/\(fleet)",
                    countHot: available > 0 && slot.status != "unavailable"
                ))
                if available > 0 && slot.status != "unavailable" {
                    openWindows.append(OpenWindow_402(
                        id: slot.date,
                        unit: dayNum,
                        title: "\(slot.dayOfWeek) \(String(slot.date.prefix(10)))",
                        window: "\(available) truck\(available == 1 ? "" : "s") open · \(slot.status)",
                        match: "post to the load board to fill"
                    ))
                }
            }
        }
        let openTruckDays = week?.totalAvailableTruckDays

        let softest = days.max { a, b in
            (Int(a.countLabel.split(separator: "/").first ?? "0") ?? 0)
                < (Int(b.countLabel.split(separator: "/").first ?? "0") ?? 0)
        }

        return CapacityVM_402(
            utilization: "\(dash.utilizationPct)%",
            openSlots: openTruckDays.map { "\($0) truck-days" } ?? "—",
            openMiles: "—",   // no open-mile rollup on any wired proc
            committedFrac: frac(dash.inUseTrucks),
            openFrac: frac(dash.availableTrucks),
            maintFrac: frac(dash.maintenanceTrucks),
            barCaption: total > 0
                ? "\(dash.inUseTrucks) in use · \(dash.availableTrucks) available · \(dash.maintenanceTrucks) maintenance · of \(total) trucks"
                : "No vehicles on file",
            unitCount: total > 0 ? "\(total) unit\(total == 1 ? "" : "s")" : "— units",
            openWindowHeader: openWindows.isEmpty ? "—" : "\(openWindows.count) of 7 days",
            days: days,
            openWindows: Array(openWindows.prefix(3)),
            insightTitle: softest.map { "Most open capacity: \($0.dow) · \($0.countLabel)" }
                ?? "Capacity \(dash.capacityStatus) · demand \(dash.demandTrend)",
            insightSub: "\(dash.activeLoads) active load\(dash.activeLoads == 1 ? "" : "s") · \(dash.pendingLoads) pending on the board"
        )
    }
}

// MARK: - Notifications

private extension Notification.Name {
    static let eusoCatalystCapacityPost_402      = Notification.Name("eusoCatalystCapacityPost_402")
    static let eusoCatalystCapacityAutoMatch_402 = Notification.Name("eusoCatalystCapacityAutoMatch_402")
    static let eusoCatalystCapacityInsight_402   = Notification.Name("eusoCatalystCapacityInsight_402")
}

// MARK: - Honest empty envelope (em-dash until a real hydrate)

private extension CapacityVM_402 {
    static let empty = CapacityVM_402(
        utilization: "—", openSlots: "—", openMiles: "—",
        committedFrac: 0, openFrac: 0, maintFrac: 0,
        barCaption: "—",
        unitCount: "— units",
        openWindowHeader: "—",
        days: [],
        openWindows: [],
        insightTitle: "No capacity insight yet",
        insightSub: "Live fleet and load data populate this board."
    )
}

// MARK: - Previews

#Preview("402 · Catalyst · Capacity · Night") {
    CatalystCapacityPlannerScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("402 · Catalyst · Capacity · Afternoon") {
    CatalystCapacityPlannerScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
