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
//  tRPC wiring manifest (line-confirmed on the wireframe spec this fire) — NONE of
//  these procedures are surfaced on the iOS EusoTripAPI client yet, so the
//  representative seed figures from the Code/ spec are kept (house 0%-mock: seeds
//  are overwritten the moment the procedure lands and loadAll() hydrates). One
//  WIRE breadcrumb per missing call is left in loadAll_402() below.
//    • utilization hero + grid → capacityPlanning.getCapacityDashboard      (capacityPlanning.ts:65)
//    • open-window list         → capacityPlanning.getFleetRightSizing       (capacityPlanning.ts:477)
//                                 + carrierCapacity.getCapacityCalendar       (carrierCapacity.ts:22)
//    • driver-day feasibility   → capacityPlanning.getDriverScheduleOptimizer (capacityPlanning.ts:415)
//    • "Post open trucks" CTA   → catalystProcedure write on truckPosting/loadBoard (_core/trpc.ts:150)
//    • "Auto-match" CTA         → matcher against open demand (loadBoard / laneAgent)
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

    @State private var vm: CapacityVM_402 = .seed
    @State private var loading: Bool = false

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
                    Text("Eusotrans LLC · 6 trucks · committed vs open")
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
                ForEach(Array(vm.openWindows.enumerated()), id: \.element.id) { idx, w in
                    openRow(w)
                    if idx < vm.openWindows.count - 1 {
                        Rectangle().fill(palette.borderFaint)
                            .frame(height: 1)
                            .padding(.leading, 52)
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
                    .background(Capsule().fill(LinearGradient.primary))
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
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Network

    private func loadAll_402() async {
        loading = true
        loading = false
        // No capacity-planning procedure is surfaced on the iOS EusoTripAPI
        // client yet — the seed figures from the Code/ spec stand in until
        // each call lands, at which point this hydrate overwrites vm.
        // WIRE: capacityPlanning.getCapacityDashboard (capacityPlanning.ts:65)
        // WIRE: capacityPlanning.getFleetRightSizing (capacityPlanning.ts:477)
        // WIRE: carrierCapacity.getCapacityCalendar (carrierCapacity.ts:22)
        // WIRE: capacityPlanning.getDriverScheduleOptimizer (capacityPlanning.ts:415)
    }
}

// MARK: - Notifications

private extension Notification.Name {
    static let eusoCatalystCapacityPost_402      = Notification.Name("eusoCatalystCapacityPost_402")
    static let eusoCatalystCapacityAutoMatch_402 = Notification.Name("eusoCatalystCapacityAutoMatch_402")
    static let eusoCatalystCapacityInsight_402   = Notification.Name("eusoCatalystCapacityInsight_402")
}

// MARK: - Seed fixture (mirrors the SVG verbatim)

private func dayCells_402(_ committed: Int, maint: Bool = false) -> [CapacityCell_402] {
    var cells = [CapacityCell_402]()
    let total = 6
    for i in 0..<total {
        if i < committed { cells.append(.committed) }
        else if maint && i == total - 1 { cells.append(.maintenance) }
        else { cells.append(.open) }
    }
    return cells
}

private extension CapacityVM_402 {
    static let seed = CapacityVM_402(
        utilization: "78%", openSlots: "5 truck-days", openMiles: "2,140 mi",
        committedFrac: 33.0 / 42, openFrac: 5.0 / 42, maintFrac: 1.0 / 42,
        barCaption: "33 committed · 5 open · 1 in maintenance · of 42 truck-days",
        unitCount: "6 units",
        openWindowHeader: "2 of 5",
        days: [
            CapacityDay_402(id: "Mon 27", dow: "Mon", date: "27", cells: dayCells_402(5), countLabel: "5/6", countHot: false),
            CapacityDay_402(id: "Tue 28", dow: "Tue", date: "28", cells: dayCells_402(6), countLabel: "6/6", countHot: false),
            CapacityDay_402(id: "Wed 29", dow: "Wed", date: "29", cells: dayCells_402(5, maint: true), countLabel: "5/6", countHot: false),
            CapacityDay_402(id: "Thu 30", dow: "Thu", date: "30", cells: dayCells_402(4), countLabel: "4/6", countHot: true),
            CapacityDay_402(id: "Fri 31", dow: "Fri", date: "31", cells: dayCells_402(3), countLabel: "3/6", countHot: true),
            CapacityDay_402(id: "Sat 01", dow: "Sat", date: "01", cells: dayCells_402(2), countLabel: "2/6", countHot: false),
            CapacityDay_402(id: "Sun 02", dow: "Sun", date: "02", cells: dayCells_402(0), countLabel: "0/6", countHot: false),
        ],
        openWindows: [
            OpenWindow_402(id: "261", unit: "261", title: "Unit 261 · Dallas TX",
                           window: "open Thu–Fri · dry van · 1,040 open mi",
                           match: "best match: DFW → Memphis $2.18/mi"),
            OpenWindow_402(id: "318", unit: "318", title: "Unit 318 · Chicago IL",
                           window: "open Fri–Sat · flatbed · 1,100 open mi",
                           match: "best match: CHI → Columbus $2.41/mi"),
        ],
        insightTitle: "ESang: Fri–Sat is your soft spot · 5 open days",
        insightSub: "Posting both units now clears $4.6k of idle capacity"
    )
}

// MARK: - Previews

#Preview("402 · Catalyst · Capacity · Night") {
    CatalystCapacityPlannerScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("402 · Catalyst · Capacity · Afternoon") {
    CatalystCapacityPlannerScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
