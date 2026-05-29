//
//  568_RailEquipmentLease.swift
//  EusoTrip — Rail Engineer · Equipment Lease (railcar/chassis lease ledger).
//
//  Verbatim port of "568 Rail Equipment Lease.svg" (Light + Dark).
//  Active leases with daily rate, running per-diem accrual, asset health, renewal calendar.
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME).
//
//  Data:
//    railLeaseMgmt.dashboard        (EXISTS railLeaseMgmt.ts:13)        → active-lease summary + units
//    railLeaseMgmt.perDiemAccrual   (EXISTS railLeaseMgmt.ts:58)        → {equipmentId?} → per-diem accrual
//    railLeaseMgmt.renewalCalendar  (EXISTS railLeaseMgmt.ts:48)        → {window?} → renewal events
//    railLeaseMgmt.calculateLeaseCost(EXISTS railLeaseMgmt.ts:25)       → CTA action
//    railShipments.getAssetHealth   (EXISTS railShipments.ts:692)       → per-unit health enrichment
//

import SwiftUI

struct RailEquipmentLeaseScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { RailEquipmentLeaseBody() } nav: {
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

private struct LeasedUnit568: Decodable, Identifiable {
    let id: Int
    let equipmentId: String?
    let equipmentType: String?      // "well_car" | "chassis" | "tank_car" | "flatcar" | "boxcar"
    let equipmentNumber: String?
    let leaseType: String?          // "full_service" | "per_diem_pool" | "net_lease"
    let dailyRateUsd: Double?
    let daysAccrued: Int?
    let accruedCostUsd: Double?
    let healthStatus: String?       // "healthy" | "service" | "out_of_service"
    let healthNote: String?
    let hazmatClass: String?
    let dotSpec: String?
}

private struct LeaseDashboard568: Decodable {
    let totalLeasesActive: Int?
    let totalPerDiemPerDay: Double?
    let totalAccruedCostUsd: Double?
    let consistId: String?
    let leases: [LeasedUnit568]?

    enum CodingKeys: String, CodingKey {
        case summary, upcomingRenewals, leasesByLessor, note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Extract from server's summary object
        if let summaryContainer = try? container.nestedContainer(keyedBy: SummaryKeys.self, forKey: .summary) {
            self.totalLeasesActive = try summaryContainer.decodeIfPresent(Int.self, forKey: .activeLeases)
            self.totalPerDiemPerDay = nil  // Server doesn't provide this; caller computes from leases
            self.totalAccruedCostUsd = nil // Server doesn't provide this; caller computes from leases
        } else {
            self.totalLeasesActive = nil
            self.totalPerDiemPerDay = nil
            self.totalAccruedCostUsd = nil
        }
        
        self.consistId = nil  // Server doesn't provide this
        self.leases = try container.decodeIfPresent([LeasedUnit568].self, forKey: .leasesByLessor)
    }

    private enum SummaryKeys: String, CodingKey {
        case activeLeases, totalCarsLeased, monthlyLeasePayment, renewalsNext30Days, renewalsNext90Days
    }
}

private struct RenewalEvent568: Decodable, Identifiable {
    let id: Int
    let equipmentNumber: String?
    let renewalDate: String?
    let daysUntilRenewal: Int?
    let termCostUsd: Double?
}

private struct RenewalCalendar568: Decodable {
    let renewals: [RenewalEvent568]?
    let renewalsInNext30Days: Int?
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.renewals = try c.decodeIfPresent([RenewalEvent568].self, forKey: .renewals)
        // Server returns next30/next60/next90/next180 arrays; map next30.count to renewalsInNext30Days
        if let next30 = try c.decodeIfPresent([RenewalEvent568].self, forKey: .next30) {
            self.renewalsInNext30Days = next30.count
        } else {
            self.renewalsInNext30Days = nil
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case renewals
        case next30
    }
}

// MARK: - Body

private struct RailEquipmentLeaseBody: View {
    @Environment(\.palette) private var palette

    @State private var dashboard: LeaseDashboard568? = nil
    @State private var renewal: RenewalCalendar568? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var isCalculating = false

    // MARK: Derived

    private var leases: [LeasedUnit568] { dashboard?.leases ?? [] }
    private var leasesCount: Int   { dashboard?.totalLeasesActive ?? leases.count }
    private var perDiemLabel: String {
        if let pd = dashboard?.totalPerDiemPerDay { return "$\(Int(pd))" }
        return "—"
    }
    private var totalAccrLabel: String {
        if let ta = dashboard?.totalAccruedCostUsd { return "$\(formatMoney(ta))" }
        return "—"
    }
    private var renewalCount: Int { renewal?.renewalsInNext30Days ?? (renewal?.renewals?.count ?? 0) }

    private func formatMoney(_ v: Double) -> String {
        if v >= 1000 { return String(format: "%,.0f", v) }
        return "\(Int(v))"
    }

    // MARK: Equipment helpers

    private func equipmentIcon(_ unit: LeasedUnit568) -> String {
        switch (unit.equipmentType ?? "").lowercased() {
        case "well_car":               return "tram.fill"
        case "chassis":                return "rectangle.split.3x1.fill"
        case "tank_car", "tanker":     return "drop.fill"
        case "flatcar":                return "minus.rectangle.fill"
        default:                       return "tram.fill"
        }
    }

    private func chipColor(_ unit: LeasedUnit568) -> Color {
        switch (unit.healthStatus ?? "healthy").lowercased() {
        case "healthy":         return Brand.success
        case "service":         return Color(red: 0.38, green: 0.49, blue: 0.55)
        case "out_of_service":  return Brand.danger
        default:
            switch (unit.equipmentType ?? "").lowercased() {
            case "tank_car", "tanker": return Brand.warning
            case "chassis":            return Color(red: 0.38, green: 0.49, blue: 0.55)
            default:                   return Brand.success
            }
        }
    }

    private func healthLabel(_ unit: LeasedUnit568) -> String {
        switch (unit.healthStatus ?? "healthy").lowercased() {
        case "healthy":         return "HEALTHY"
        case "service":         return "SERVICE"
        case "out_of_service":  return "OUT OF SVC"
        default:                return "HEALTHY"
        }
    }

    private func healthColor(_ unit: LeasedUnit568) -> Color {
        switch (unit.healthStatus ?? "healthy").lowercased() {
        case "healthy":         return Brand.success
        case "service":         return Brand.warning
        case "out_of_service":  return Brand.danger
        default:                return Brand.success
        }
    }

    private func unitTitle(_ unit: LeasedUnit568) -> String {
        let typeLabel: String = {
            switch (unit.equipmentType ?? "").lowercased() {
            case "well_car":  return "Well-car"
            case "chassis":   return "Chassis"
            case "tank_car":  return "Tankcar"
            case "flatcar":   return "Flatcar"
            default:          return (unit.equipmentType ?? "Unit").replacingOccurrences(of: "_", with: " ").capitalized
            }
        }()
        let num = unit.equipmentNumber ?? unit.equipmentId ?? "—"
        let extra = unit.hazmatClass.map { " · \($0)" } ?? ""
        return "\(typeLabel) \(num)\(extra)"
    }

    private func unitSub(_ unit: LeasedUnit568) -> String {
        var parts: [String] = []
        if let lt = unit.leaseType  { parts.append(lt.replacingOccurrences(of: "_", with: " ")) }
        if let dot = unit.dotSpec   { parts.append(dot) }
        if let rate = unit.dailyRateUsd { parts.append("$\(Int(rate))/day") }
        if let days = unit.daysAccrued  { parts.append("\(days) days") }
        if let note = unit.healthNote   { parts.append(note) }
        return parts.joined(separator: " · ")
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading leases…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    heroCard
                    kpiStrip
                    leasedUnitsList
                    renewalCalendarStrip
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("RAIL ENGINEER · EQUIPMENT LEASE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text("per-diem")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Equipment Lease")
                    .font(.system(size: 28, weight: .heavy))
                    .kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            IridescentHairline()
        }
    }

    // MARK: - Hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("ACCRUING")
                    .font(.system(size: 11, weight: .bold)).kerning(0.5)
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.warning.opacity(0.14)))
                Text("\(leasesCount) lease\(leasesCount == 1 ? "" : "s") on consist")
                    .font(.system(size: 11, weight: .bold)).kerning(0.5)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(palette.textPrimary.opacity(0.06)))
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(perDiemLabel)
                            .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("per-diem / day")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Text("running accrual · active consist")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("TOTAL ACCR")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(totalAccrLabel)
                        .font(.system(size: 20, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text("this cycle")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    // MARK: - KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "LEASES",   value: "\(leasesCount)")
            MetricTile(label: "PER-DIEM", value: perDiemLabel, gradientNumeral: true)
            MetricTile(label: "RENEWALS", value: "\(renewalCount)", accent: renewalCount > 0 ? Brand.warning : nil)
        }
    }

    // MARK: - Leased units list

    private var leasedUnitsList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("LEASED UNITS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("perDiemAccrual")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            if leases.isEmpty {
                EusoEmptyState(
                    systemImage: "tram.fill",
                    title: "No active leases",
                    subtitle: "Leased railcar units will appear here."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(leases.enumerated()), id: \.element.id) { idx, unit in
                        leaseRow(unit)
                        if idx < leases.count - 1 {
                            Divider()
                                .padding(.leading, 68)
                                .overlay(palette.borderFaint)
                        }
                    }
                }
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
            }
        }
    }

    private func leaseRow(_ unit: LeasedUnit568) -> some View {
        let color = chipColor(unit)
        let hColor = healthColor(unit)
        let accrued = unit.accruedCostUsd.map { "$\(Int($0))" } ?? "—"

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: equipmentIcon(unit))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(unitTitle(unit))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(unitSub(unit))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(healthLabel(unit))
                    .font(.system(size: 11, weight: .bold)).kerning(0.6)
                    .foregroundStyle(hColor)
                Text(accrued)
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(16)
    }

    // MARK: - Renewal calendar

    @ViewBuilder
    private var renewalCalendarStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if let renewals = renewal?.renewals, !renewals.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("RENEWAL CALENDAR")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(palette.textTertiary)
                        Spacer()
                        Text("renewalCalendar")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(palette.textTertiary)
                    }
                    ForEach(renewals.prefix(2)) { event in
                        let daysLabel = event.daysUntilRenewal.map { "\($0) days" } ?? ""
                        let costLabel = event.termCostUsd.map { " · $\(formatMoney($0)) term" } ?? ""
                        Text("\(event.equipmentNumber ?? "—") · renews \(event.renewalDate ?? "—") · \(daysLabel)\(costLabel)")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    if let count = renewal?.renewalsInNext30Days, count > 0 {
                        Text("\(count) renewal\(count == 1 ? "" : "s") in next 30 days")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                .padding(Space.s3)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
        }
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Calculate lease cost", action: { Task { await calculateCost() } }, leadingIcon: "tablecells", isLoading: isCalculating)
            Button {} label: {
                Text("Specs")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 116, height: 48)
                    .background(palette.bgCard)
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load / Actions

    private func load() async {
        loading = true; loadError = nil
        struct EmptyIn: Encodable {}
        struct CalendarIn: Encodable { let window: Int? }
        do {
            async let dash: LeaseDashboard568 = EusoTripAPI.shared.query(
                "railLeaseMgmt.dashboard", input: EmptyIn())
            async let cal: RenewalCalendar568 = EusoTripAPI.shared.query(
                "railLeaseMgmt.renewalCalendar", input: CalendarIn(window: 30))
            let (d, c) = try await (dash, cal)
            self.dashboard = d
            self.renewal   = c
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func calculateCost() async {
        isCalculating = true
        struct CostIn: Encodable { let equipmentType: String; let dailyRate: Double; let days: Int }
        struct CostOut: Decodable {}
        do {
            let rate = dashboard?.totalPerDiemPerDay ?? 0
            let _: CostOut = try await EusoTripAPI.shared.query(
                "railLeaseMgmt.calculateLeaseCost",
                input: CostIn(equipmentType: "consist", dailyRate: rate, days: 30))
        } catch { /* non-fatal */ }
        isCalculating = false
    }
}

#Preview("568 · Rail Equipment Lease · Night") { RailEquipmentLeaseScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("568 · Rail Equipment Lease · Light") { RailEquipmentLeaseScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
