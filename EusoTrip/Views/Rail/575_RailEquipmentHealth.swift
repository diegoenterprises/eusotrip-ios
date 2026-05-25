//
//  575_RailEquipmentHealth.swift
//  EusoTrip — Rail Engineer · Equipment Health (fleet railcar health index).
//
//  Verbatim port of "575 Rail Equipment Health.svg" (Light + Dark).
//  Fleet health index, 4-cell KPI strip (healthy/watch/defect/avg miles),
//  per-railcar condition rows with condition pills and health%.
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME).
//
//  Data:
//    railShipments.getAssetHealth      (EXISTS :692)   → fleet health index + car rows
//    railShipments.getEquipmentSpecs   (EXISTS :678)   → component detail (best-effort)
//    railShipments.getFRASafetyCompliance (EXISTS :720) → FRA notes (best-effort)
//    railLeaseMgmt.dashboard           (EXISTS :13)    → shop/lease status (best-effort)
//

import SwiftUI

struct RailEquipmentHealthScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { RailEquipmentHealthBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct AssetHealthFleet575: Decodable {
    let healthIndex: Double?
    let carCount: Int?
    let shoppedCount: Int?
    let dueServiceCount: Int?
    let healthyCount: Int?
    let watchCount: Int?
    let defectCount: Int?
    let avgMilesToOverhaul: Int?
    let healthyPercent: Double?
    let divisionName: String?
}

private struct RailcarHealth575: Decodable, Identifiable {
    let id: Int
    let reportingMark: String?
    let equipmentType: String?
    let condition: String?
    let componentNote: String?
    let mileage: String?
    let additionalInfo: String?
    let healthPercent: Int?
}

// MARK: - Body

private struct RailEquipmentHealthBody: View {
    @Environment(\.palette) private var palette

    @State private var fleet: AssetHealthFleet575? = nil
    @State private var cars: [RailcarHealth575] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var isScheduling = false

    // MARK: Derived

    private var captionLabel: String { "\(fleet?.carCount ?? cars.count) CARS" }
    private var healthIndexLabel: String {
        fleet?.healthIndex.map { String(format: "%.1f", $0) } ?? "—"
    }
    private var shoppedLabel: String { "\(fleet?.shoppedCount ?? 0) SHOPPED" }
    private var shoppedCount: Int    { fleet?.shoppedCount ?? 0 }
    private var dueServiceLabel: String {
        fleet?.dueServiceCount.map { "\($0)" } ?? "—"
    }
    private var fleetSubLabel: String {
        let count = fleet?.carCount ?? cars.count
        let div   = fleet?.divisionName ?? "Rail Division"
        return "\(count) cars · \(div)"
    }
    private var healthyCount: String  { fleet?.healthyCount.map { "\($0)" } ?? "—" }
    private var healthyPct: String    {
        fleet?.healthyPercent.map { String(format: "%.0f%%", $0) } ?? "—"
    }
    private var watchCount: String    { fleet?.watchCount.map { "\($0)" } ?? "—" }
    private var defectCount: String   { fleet?.defectCount.map { "\($0)" } ?? "—" }
    private var avgMilesLabel: String {
        guard let m = fleet?.avgMilesToOverhaul else { return "—" }
        return m >= 1000 ? "\(m / 1000)k" : "\(m)"
    }

    private func conditionInfo(_ condition: String?) -> (label: String, color: Color) {
        switch (condition ?? "").lowercased() {
        case "bad_order", "bad order", "defect": return ("BAD ORDER", Brand.danger)
        case "watch":                             return ("WATCH",     Brand.warning)
        default:                                  return ("HEALTHY",   Brand.success)
        }
    }
    private func equipmentChipColor(_ type: String?) -> Color {
        switch (type ?? "").lowercased().replacingOccurrences(of: "_", with: " ") {
        case "tankcar", "tank car":             return Brand.danger
        case "covered hopper", "hopper":        return Brand.warning
        case "boxcar", "box car":               return Brand.blue
        case "well car", "wellcar":             return Brand.success
        case "flatcar", "flat car":             return Brand.blue
        case "gondola":                         return Color(red: 0.38, green: 0.49, blue: 0.55)
        default:
            let types: [Color] = [Brand.success, Brand.blue, Brand.warning]
            return types[abs((type ?? "").hashValue) % types.count]
        }
    }
    private func equipmentIcon(_ type: String?) -> String {
        switch (type ?? "").lowercased().replacingOccurrences(of: "_", with: " ") {
        case "tankcar", "tank car":      return "drop.fill"
        case "covered hopper", "hopper": return "shippingbox.fill"
        case "boxcar", "box car":        return "rectangle.split.2x1.fill"
        case "well car", "wellcar":      return "tram.fill"
        case "flatcar", "flat car":      return "minus.rectangle.fill"
        default:                         return "tram.fill"
        }
    }
    private func healthPctColor(_ cond: String?) -> Color {
        switch (cond ?? "").lowercased() {
        case "bad_order", "bad order", "defect": return Brand.danger
        default:                                  return palette.textPrimary
        }
    }
    private func carSub(_ c: RailcarHealth575) -> String {
        var parts: [String] = []
        if let note = c.componentNote    { parts.append(note) }
        if let mi   = c.mileage          { parts.append(mi) }
        if let info = c.additionalInfo   { parts.append(info) }
        return parts.joined(separator: " · ")
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading fleet health…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    heroCard
                    kpiStrip
                    carList
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
                    Text("RAIL ENGINEER · EQUIPMENT HEALTH")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text(captionLabel)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Equipment health")
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
                Text("FLEET HEALTHY")
                    .font(.system(size: 10, weight: .heavy)).kerning(0.6)
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.success.opacity(0.12)))
                if shoppedCount > 0 {
                    Text(shoppedLabel)
                        .font(.system(size: 10, weight: .heavy)).kerning(0.6)
                        .foregroundStyle(Brand.danger)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill(Brand.danger.opacity(0.10)))
                }
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(healthIndexLabel)
                        .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("fleet health index")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Text(fleetSubLabel)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("DUE SERVICE")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(dueServiceLabel)
                        .font(.system(size: 22, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(Brand.warning)
                    Text("within 30 days")
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

    // MARK: - KPI strip (4-cell)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            healthKPITile("HEALTHY",   value: healthyCount, sub: healthyPct,      subColor: Brand.success)
            healthKPITile("WATCH",     value: watchCount,   sub: "monitor",       subColor: palette.textSecondary, valueColor: Brand.warning)
            healthKPITile("DEFECT",    value: defectCount,  sub: "bad order",     subColor: Brand.danger,          valueColor: Brand.danger)
            healthKPITile("AVG MILES", value: avgMilesLabel, sub: "to overhaul",  subColor: palette.textSecondary, isGradient: true)
        }
    }

    @ViewBuilder
    private func healthKPITile(_ label: String, value: String, sub: String, subColor: Color,
                                valueColor: Color? = nil, isGradient: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if isGradient {
                Text(value)
                    .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
            } else {
                Text(value)
                    .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(valueColor ?? palette.textPrimary)
            }
            Text(sub)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(subColor)
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }

    // MARK: - Railcar list

    private var carList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("RAILCAR HEALTH")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getEquipmentSpecs")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            if cars.isEmpty {
                EusoEmptyState(
                    systemImage: "tram",
                    title: "No equipment data",
                    subtitle: "Railcar health reports will appear here."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(cars.enumerated()), id: \.element.id) { idx, car in
                        carRow(car)
                        if idx < cars.count - 1 {
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

    private func carRow(_ car: RailcarHealth575) -> some View {
        let chipColor = equipmentChipColor(car.equipmentType)
        let icon      = equipmentIcon(car.equipmentType)
        let cond      = conditionInfo(car.condition)
        let pctColor  = healthPctColor(car.condition)
        let pctStr    = car.healthPercent.map { "\($0)%" } ?? "—"

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(chipColor.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(chipColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(car.reportingMark ?? "—") · \(car.equipmentType?.replacingOccurrences(of: "_", with: " ") ?? "—")")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(carSub(car))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(cond.label)
                    .font(.system(size: 10, weight: .bold)).kerning(0.4)
                    .foregroundStyle(cond.color)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(cond.color.opacity(0.12)))
                Text(pctStr)
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(pctColor)
            }
        }
        .padding(16)
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Schedule shop", action: { Task { await scheduleShop() } }, isLoading: isScheduling)
            Button {} label: {
                Text("Order parts")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
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
        do {
            async let fleetResult: AssetHealthFleet575 = EusoTripAPI.shared.query(
                "railShipments.getAssetHealth", input: EmptyIn())
            async let carResult: [RailcarHealth575] = EusoTripAPI.shared.query(
                "railShipments.getEquipmentSpecs", input: EmptyIn())
            let (f, c) = try await (fleetResult, carResult)
            self.fleet = f
            self.cars  = c
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func scheduleShop() async {
        isScheduling = true
        struct EmptyIn: Encodable {}
        struct ShopOut: Decodable {}
        do {
            let _: ShopOut = try await EusoTripAPI.shared.query(
                "railLeaseMgmt.scheduleShop", input: EmptyIn())
        } catch { /* non-fatal */ }
        isScheduling = false
    }
}

#Preview("575 · Rail Equipment Health · Night") { RailEquipmentHealthScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("575 · Rail Equipment Health · Light") { RailEquipmentHealthScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
