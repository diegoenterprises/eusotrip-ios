//
//  601_RailChassisPool.swift
//  EusoTrip — Rail Engineer · Chassis Pool (carrier-side BOARD/INVENTORY).
//
//  Verbatim port of "601 Rail Chassis Pool.svg" (Dark = exact Theme.dark
//  palette swap of the Light source). CARRIER-SIDE BOARD/INVENTORY archetype
//  — a pool-availability board: an availability hero (units ready now over a
//  deployment bar with per-diem-MTD / on-road / in-shop right metrics) above a
//  by-equipment-TYPE board (each row carries its own utilization gauge + a
//  right-aligned available count), then a return-status tile shelf
//  (due back / overdue / per-diem rate) and a Schedule-shop / Renewals CTA pair.
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS[current] · [orb]
//  · COMPLIANCE · ME).
//
//  Data:
//    yardManagement.getChassisInventory  (EXISTS yardManagement.ts:1133)
//        input{locationId?,status?} → {chassis[], summary{total,available,inUse,maintenance,outOfService}}
//    railLeaseMgmt.perDiemAccrual        (EXISTS railLeaseMgmt.ts:60)
//        → {carId,daysOnRoad,ratePerDay,perDiemTotal,status}  (per-diem MTD + rate)
//    railLeaseMgmt.dashboard             (EXISTS railLeaseMgmt.ts:15)  → per-diem MTD aggregate
//    railLeaseMgmt.scheduleShop          (EXISTS railLeaseMgmt.ts:87)  → "Schedule shop" CTA (mutation · audit row)
//    railLeaseMgmt.renewalCalendar       (EXISTS railLeaseMgmt.ts:50)  → "Renewals" CTA
//
//  PORT-GAP (named-gap surfaced to the-oath):
//    • yardManagement.getChassisPoolByType — no single procedure returns the
//      per-equipment-TYPE available/total split; the by-type board is composed
//      client-side from getChassisInventory.chassis grouped by chassisType.
//    • WS chassis-pool channel — getChassisInventory is read-only; no
//      WS_CHANNELS broadcast wired for live pool changes yet.
//    • return-status (due back today / overdue past per-diem) — derived
//      client-side from per-diem accrual where present; no dedicated procedure.
//

import SwiftUI

struct RailChassisPoolScreen: View {
    let theme: Theme.Palette
    var locationId: String? = nil

    var body: some View {
        Shell(theme: theme) { RailChassisPoolBody(locationId: locationId) } nav: {
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

// MARK: - Data shapes

private struct ChassisUnit601: Decodable, Identifiable {
    let id: String
    let chassisType: String?     // "40_marine" | "53_domestic" | "well_car" | "genset" …
    let chassisNumber: String?
    let status: String?          // "available" | "in_use" | "maintenance" | "out_of_service"
    let pool: String?            // "DCLI" | "TRAC" | "FlexiVan" | "DTTX"
    let daysOnRoad: Int?
}

private struct ChassisSummary601: Decodable {
    let total: Int?
    let available: Int?
    let inUse: Int?
    let maintenance: Int?
    let outOfService: Int?
}

private struct ChassisInventory601: Decodable {
    let chassis: [ChassisUnit601]?
    let summary: ChassisSummary601?
}

private struct PerDiemAccrual601: Decodable {
    let carId: String?
    let daysOnRoad: Int?
    let ratePerDay: Double?
    let perDiemTotal: Double?
    let status: String?           // "accruing" | "closed"
}

private struct LeaseDashboard601: Decodable {
    let perDiemMtdUsd: Double?
    let perDiemRatePerDay: Double?
    let totalPerDiemPerDay: Double?
    let totalAccruedCostUsd: Double?
}

// One composed by-type pool bucket (client-side from inventory.chassis).
private struct PoolType601: Identifiable {
    let id: String
    let type: String            // raw chassisType key
    let total: Int
    let available: Int
    let inUse: Int
}

// MARK: - Body

private struct RailChassisPoolBody: View {
    @Environment(\.palette) private var palette
    let locationId: String?

    @State private var inventory: ChassisInventory601? = nil
    @State private var dashboard: LeaseDashboard601? = nil
    @State private var accruals: [PerDiemAccrual601] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    // Filter chips (All / Available / On-road / Shop)
    private enum StatusFilter: String { case all, available, onRoad, shop }
    @State private var activeFilter: StatusFilter = .all

    @State private var isSchedulingShop = false
    @State private var shopAck: String? = nil
    @State private var renewalAck: String? = nil

    // MARK: Derived — pool counts

    private var summary: ChassisSummary601? { inventory?.summary }
    private var chassis: [ChassisUnit601] { inventory?.chassis ?? [] }

    private var totalCount:     Int { summary?.total        ?? chassis.count }
    private var availableCount: Int { summary?.available    ?? chassis.filter { ($0.status ?? "").lowercased() == "available" }.count }
    private var inUseCount:     Int { summary?.inUse        ?? chassis.filter { isOnRoad($0.status) }.count }
    private var shopCount:      Int { (summary?.maintenance ?? 0) + (summary?.outOfService ?? 0) }

    private var deployedPct: Int {
        guard totalCount > 0 else { return 0 }
        return Int((Double(totalCount - availableCount) / Double(totalCount) * 100).rounded())
    }

    private func isOnRoad(_ status: String?) -> Bool {
        switch (status ?? "").lowercased() {
        case "in_use", "on_road", "onroad", "deployed", "out": return true
        default: return false
        }
    }

    // per-diem MTD ($ accrued month-to-date)
    private var perDiemMtdLabel: String {
        if let m = dashboard?.perDiemMtdUsd ?? dashboard?.totalAccruedCostUsd {
            return "$\(moneyGroup(m))"
        }
        let summed = accruals.reduce(into: 0.0) { acc, a in acc += (a.perDiemTotal ?? 0) }
        if summed > 0 { return "$\(moneyGroup(summed))" }
        return "—"
    }

    // per-diem daily rate (DCLI tariff)
    private var perDiemRateLabel: String {
        if let r = dashboard?.perDiemRatePerDay ?? dashboard?.totalPerDiemPerDay {
            return "$\(Int(r))/day"
        }
        if let r = accruals.compactMap({ $0.ratePerDay }).first {
            return "$\(Int(r))/day"
        }
        return "—"
    }

    // return-status — derived client-side from accruals (PORT-GAP: no procedure)
    private var dueBackCount: Int {
        accruals.filter { ($0.status ?? "").lowercased() == "accruing" && ($0.daysOnRoad ?? 0) <= 5 }.count
    }
    private var overdueCount: Int {
        accruals.filter { ($0.daysOnRoad ?? 0) > 5 }.count
    }

    private func moneyGroup(_ v: Double) -> String {
        let n = NSNumber(value: Int(v.rounded()))
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","
        return f.string(from: n) ?? "\(Int(v.rounded()))"
    }

    // MARK: Derived — by-type board (composed client-side · PORT-GAP)

    private var poolByType: [PoolType601] {
        let grouped = Dictionary(grouping: chassis) { ($0.chassisType ?? "other").lowercased() }
        let buckets: [PoolType601] = grouped.map { key, units in
            let total = units.count
            let avail = units.filter { ($0.status ?? "").lowercased() == "available" }.count
            let inUse = units.filter { isOnRoad($0.status) }.count
            return PoolType601(id: key, type: key, total: total, available: avail, inUse: inUse)
        }
        // Largest pools first; last bucket renders as the summary line.
        return buckets.sorted { $0.total > $1.total }
    }

    // MARK: Type vocabulary helpers (RAIL · chassis/well-car/genset/intermodal)

    private func typeTitle(_ t: PoolType601) -> String {
        switch t.type {
        case "40_marine", "40", "40ft", "40_chassis": return "40' Chassis · DCLI"
        case "53_domestic", "53", "53ft", "53_chassis": return "53' Chassis · TRAC"
        case "well_car", "wellcar", "dttx": return "Well-car · DTTX"
        case "genset", "genset_reefer", "reefer": return "Genset reefer · FlexiVan"
        default: return t.type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func typeSub(_ t: PoolType601) -> String {
        let unitWord: String
        switch t.type {
        case "well_car", "wellcar", "dttx": unitWord = "cars"
        default: unitWord = "units"
        }
        switch t.type {
        case "40_marine", "40", "40ft", "40_chassis":   return "DCLI · 40' marine · \(t.total) \(unitWord)"
        case "53_domestic", "53", "53ft", "53_chassis": return "TRAC · 53' domestic · \(t.total) \(unitWord)"
        case "well_car", "wellcar", "dttx":             return "DTTX · double-stack · \(t.total) \(unitWord)"
        case "genset", "genset_reefer", "reefer":       return "FlexiVan · \(t.total) \(unitWord)"
        default:                                        return "\(t.total) \(unitWord)"
        }
    }

    private func typeColor(_ t: PoolType601) -> Color {
        switch t.type {
        case "40_marine", "40", "40ft", "40_chassis":   return Brand.blue
        case "53_domestic", "53", "53ft", "53_chassis": return Brand.success
        case "well_car", "wellcar", "dttx":             return Color(red: 0.376, green: 0.490, blue: 0.545) // #607D8B
        default:                                        return Color(red: 0.376, green: 0.490, blue: 0.545)
        }
    }

    private func typeIcon(_ t: PoolType601) -> String {
        switch t.type {
        case "well_car", "wellcar", "dttx": return "tram.fill"
        case "genset", "genset_reefer", "reefer": return "snowflake"
        default: return "rectangle.split.3x1.fill"
        }
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                filterChips
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading chassis pool…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    availabilityHero
                    byTypeBoard
                    returnStatusShelf
                    ctaPair
                    if let ack = shopAck {
                        Text(ack).font(EType.caption).foregroundStyle(Brand.success)
                    }
                    if let ack = renewalAck {
                        Text(ack).font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header (eyebrow + title + subtitle)

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("RAIL ENGINEER · CHASSIS POOL")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("DCLI · LPC POOL")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Chassis pool")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            Text("Logistics Park · DCLI pool · per-diem live")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - Filter chips (All / Available / On-road / Shop)

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                filterChip(.all,       "All · \(totalCount)",          fill: true,  color: .white)
                filterChip(.available, "Available · \(availableCount)", fill: false, color: Brand.success)
                filterChip(.onRoad,    "On-road · \(inUseCount)",       fill: false, color: Brand.blue)
                filterChip(.shop,      "Shop · \(shopCount)",           fill: false, color: Brand.warning)
            }
        }
    }

    @ViewBuilder
    private func filterChip(_ filter: StatusFilter, _ label: String, fill: Bool, color: Color) -> some View {
        let isActive = activeFilter == filter
        Button {
            withAnimation(.easeInOut(duration: 0.16)) { activeFilter = filter }
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(fill ? Color.white : color)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(
                    Group {
                        if fill {
                            Capsule().fill(LinearGradient.primary)
                        } else {
                            Capsule().fill(palette.bgCard)
                        }
                    }
                )
                .overlay(
                    Capsule().strokeBorder(isActive && !fill ? color.opacity(0.55) : palette.borderFaint, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pool availability hero (gradient-rim card)

    private var availabilityHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("POOL AVAILABLE NOW")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Text("\(availableCount)")
                        .font(.system(size: 40, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                        .padding(.top, 8)
                    Text("of \(totalCount) units · \(deployedPct)% deployed")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.top, 4)
                    deploymentBar
                        .padding(.top, 10)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    heroMetric(value: perDiemMtdLabel, label: "per-diem MTD")
                    heroMetric(value: "\(inUseCount)",  label: "on the road").padding(.top, 8)
                    heroMetric(value: "\(shopCount)",   label: "in shop").padding(.top, 8)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    private func heroMetric(value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .bold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var deploymentBar: some View {
        GeometryReader { geo in
            let frac = totalCount > 0 ? CGFloat(totalCount - availableCount) / CGFloat(totalCount) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(palette.textPrimary.opacity(0.12)).frame(height: 6)
                Capsule().fill(LinearGradient.primary)
                    .frame(width: max(0, geo.size.width * frac), height: 6)
            }
        }
        .frame(width: 160, height: 6)
    }

    // MARK: - Pool by equipment type board

    private var byTypeBoard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("POOL BY EQUIPMENT TYPE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.blue)
                Spacer()
                Text("see all ›")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            Rectangle().fill(palette.borderFaint).frame(height: 1)

            if poolByType.isEmpty {
                EusoEmptyState(
                    systemImage: "rectangle.split.3x1.fill",
                    title: "No chassis in pool",
                    subtitle: "Pool inventory by equipment type will appear here."
                )
            } else {
                VStack(spacing: 0) {
                    let detailed = Array(poolByType.prefix(3))
                    let summaryRows = Array(poolByType.dropFirst(3))
                    ForEach(Array(detailed.enumerated()), id: \.element.id) { idx, t in
                        typeRow(t)
                        if idx < detailed.count - 1 || !summaryRows.isEmpty {
                            Divider().padding(.leading, 68).overlay(palette.borderFaint)
                        }
                    }
                    ForEach(Array(summaryRows.enumerated()), id: \.element.id) { idx, t in
                        summaryRow(t)
                        if idx < summaryRows.count - 1 {
                            Divider().padding(.leading, 16).overlay(palette.borderFaint)
                        }
                    }
                }
                .padding(.vertical, 2)
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
            }
        }
    }

    private func typeRow(_ t: PoolType601) -> some View {
        let color = typeColor(t)
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: typeIcon(t))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(typeTitle(t))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(typeSub(t))
                    .font(.system(size: 11, weight: .regular, design: .monospaced)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                utilizationGauge(t, color: color)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(t.available)")
                    .font(.system(size: 16, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("avail")
                    .font(.system(size: 9))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(16)
    }

    private func utilizationGauge(_ t: PoolType601, color: Color) -> some View {
        GeometryReader { geo in
            // Gauge tracks deployment (in-use / total) so a fuller bar = tighter pool.
            let frac = t.total > 0 ? CGFloat(t.inUse) / CGFloat(t.total) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(palette.textPrimary.opacity(0.12)).frame(height: 6)
                Capsule().fill(color)
                    .frame(width: max(0, geo.size.width * frac), height: 6)
            }
        }
        .frame(height: 6)
        .frame(maxWidth: 240)
    }

    private func summaryRow(_ t: PoolType601) -> some View {
        HStack {
            Text(typeSub(t))
                .font(.system(size: 11))
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text("\(t.available) avail")
                .font(.system(size: 11, weight: .bold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: - Return status tile shelf

    private var returnStatusShelf: some View {
        HStack(spacing: Space.s2) {
            returnTile(dot: Brand.blue,    title: "\(dueBackCount) due back", line1: "return today",   line2: "by 18:00 CT")
            returnTile(dot: Brand.danger,  title: "\(overdueCount) overdue",  line1: "past per-diem",  line2: "> 5 days out")
            returnTile(dot: Brand.success, title: perDiemRateLabel,           line1: "per-diem rate",  line2: "DCLI tariff")
        }
    }

    private func returnTile(dot: Color, title: String, line1: String, line2: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(dot).frame(width: 7, height: 7)
                Text(title)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(line1)
                .font(.system(size: 9.5))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 12)
            Text(line2)
                .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 4)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - CTA pair (Schedule shop · Renewals)

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(
                title: "Schedule shop",
                action: { Task { await scheduleShop() } },
                leadingIcon: "wrench.and.screwdriver.fill",
                isLoading: isSchedulingShop
            )
            Button {
                Task { await openRenewals() }
            } label: {
                Text("Renewals")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 124, height: 48)
                    .background(palette.bgSecondary)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load / Actions

    private func load() async {
        loading = true; loadError = nil
        struct InventoryIn: Encodable { let locationId: String?; let status: String? }
        struct EmptyIn: Encodable {}
        do {
            async let inv: ChassisInventory601 = EusoTripAPI.shared.query(
                "yardManagement.getChassisInventory",
                input: InventoryIn(locationId: locationId, status: nil))
            // per-diem MTD + rate aggregate (best-effort; non-fatal on failure)
            let invResult = try await inv
            self.inventory = invResult

            // Lease dashboard for per-diem MTD + tariff rate.
            if let dash: LeaseDashboard601 = try? await EusoTripAPI.shared.query(
                "railLeaseMgmt.dashboard", input: EmptyIn()) {
                self.dashboard = dash
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func scheduleShop() async {
        isSchedulingShop = true; shopAck = nil
        struct ScheduleIn: Encodable { let locationId: String? }
        struct ScheduleOut: Decodable { let id: String? }
        do {
            // scheduleShop persists an audit row (mutation · POST).
            let _: ScheduleOut = try await EusoTripAPI.shared.mutation(
                "railLeaseMgmt.scheduleShop",
                input: ScheduleIn(locationId: locationId))
            shopAck = "Shop slot scheduled · audit row persisted."
        } catch {
            shopAck = "Couldn't schedule shop: \((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)"
        }
        isSchedulingShop = false
    }

    private func openRenewals() async {
        renewalAck = nil
        struct CalendarIn: Encodable { let window: Int? }
        struct RenewalOut: Decodable { let renewalsInNext30Days: Int? }
        do {
            let out: RenewalOut = try await EusoTripAPI.shared.query(
                "railLeaseMgmt.renewalCalendar", input: CalendarIn(window: 30))
            if let n = out.renewalsInNext30Days {
                renewalAck = "\(n) renewal\(n == 1 ? "" : "s") in next 30 days."
            } else {
                renewalAck = "Renewal calendar opened."
            }
        } catch {
            renewalAck = "Couldn't load renewals: \((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)"
        }
    }
}

#Preview("601 · Rail Chassis Pool · Night") { RailChassisPoolScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("601 · Rail Chassis Pool · Light") { RailChassisPoolScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
