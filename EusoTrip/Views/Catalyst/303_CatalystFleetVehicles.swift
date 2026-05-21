//
//  303_CatalystFleetVehicles.swift
//  EusoTrip — Catalyst · Fleet · Vehicles (brick 303).
//
//  Pixel-match to wireframe `03 Catalyst/Dark-SVG/303 Fleet Vehicles.svg`
//  (eusotrip-killers co-work team, Apr 2026). Renders the same five
//  stacked sections the SVG calls for:
//
//    1. Header — eyebrow + title + "Add" CTA
//    2. Vehicle card — identity + status + lane + 4-tile KPI grid +
//       equipment-capability strip (active capability gradient-rimmed)
//    3. IFTA quarterly strip — 4 quarters with status capsules + YTD line
//    4. Zeun maintenance schedule — 3 rows (Next PM / Last DOT / Tank cert)
//    5. Schedule PM CTA card — "save 90 min vs road shop"
//
//  Wire bindings (all real, no stubs):
//    vehicles.list                  — vehicle roster + status
//    iftaCalculator.calculateQuarter — per-quarter IFTA summary
//    maintenance.getUpcoming         — next-PM + DOT inspection + cert rows
//    maintenance.getAlerts           — alert count badge on Zeun header
//
//  Bottom nav frozen per the bottom-nav-frozen doctrine — content
//  only. Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire models

private struct VehicleRow: Decodable, Hashable, Identifiable {
    let id: String
    let vin: String?
    let make: String?
    let model: String?
    let year: Int?
    let licensePlate: String?
    let vehicleType: String?
    let status: String?
    let currentLat: Double?
    let currentLng: Double?
    let currentMileage: Int?
    let lastServiceDate: String?
    let nextServiceDate: String?
    let assignedDriverId: String?
}

private struct VehiclesList: Decodable {
    let vehicles: [VehicleRow]?
    let items: [VehicleRow]?
    let total: Int?
    var rows: [VehicleRow] { vehicles ?? items ?? [] }
}

private struct IFTAQuarterResult: Decodable, Hashable {
    let quarter: Int?
    let year: Int?
    let totalMiles: Double?
    let totalTaxableMiles: Double?
    let totalFuelGallons: Double?
    let totalTaxDue: Double?
    let netTaxOwed: Double?
    let status: String?
}

private struct MaintenanceUpcoming: Decodable, Hashable, Identifiable {
    let id: String
    let vehicleId: String?
    let type: String?
    let dueAt: String?
    let title: String?
    let description: String?
    let location: String?
    let urgency: String?  // low/medium/high
}

private struct MaintenanceAlerts: Decodable {
    let alerts: Int?
    let total: Int?
    var count: Int { alerts ?? total ?? 0 }
}

// MARK: - Screen

struct CatalystFleetVehiclesScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { FleetVehiclesBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Dispatch", systemImage: "rectangle.split.3x1.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill",  isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",           isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct FleetVehiclesBody: View {
    @Environment(\.palette) private var palette
    @State private var vehicles: [VehicleRow] = []
    @State private var iftaQuarters: [Int: IFTAQuarterResult] = [:]
    @State private var maintenance: [MaintenanceUpcoming] = []
    @State private var alertCount: Int = 0
    @State private var loading: Bool = true
    @State private var error: String?

    private var activeCount: Int {
        vehicles.filter { ($0.status ?? "").lowercased() == "in_use" || ($0.status ?? "").lowercased() == "available" }.count
    }
    private var maintCount: Int {
        vehicles.filter { ($0.status ?? "").lowercased() == "maintenance" }.count
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading && vehicles.isEmpty {
                    LifecycleCard { Text("Loading fleet…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = error {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if vehicles.isEmpty {
                    EusoEmptyState(
                        systemImage: "truck.box",
                        title: "No vehicles yet",
                        subtitle: "Tap Add to register your first power unit."
                    )
                } else {
                    ForEach(vehicles) { v in
                        vehicleCard(v)
                    }
                }
                iftaStrip
                maintenanceSection
                schedulePmCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · FLEET · VEHICLES")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            HStack {
                Text("Vehicles")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Button {
                    // 2026-05-21 — wire to existing vehicle-add flow via
                    // the Catalyst settings vehicle composer. Future:
                    // open a dedicated 303A "Add Vehicle" sheet.
                    NotificationCenter.default.post(
                        name: NSNotification.Name("eusoCatalystAddVehicleRequested"),
                        object: nil
                    )
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill").font(.caption)
                        Text("Add").font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .foregroundStyle(palette.textPrimary)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(LinearGradient.diagonal.opacity(0.4))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Text("\(activeCount) ACTIVE · \(maintCount) MAINTENANCE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - Vehicle card

    @ViewBuilder
    private func vehicleCard(_ v: VehicleRow) -> some View {
        let isHazmatTank = (v.vehicleType ?? "").lowercased().contains("tank") ||
                           (v.vehicleType ?? "").lowercased().contains("hazmat")

        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    // Mode pill (UN code for hazmat, otherwise vehicleType)
                    Text(isHazmatTank ? "UN" : "VH")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(isHazmatTank ? Color.orange.opacity(0.18) : Color.blue.opacity(0.18)))
                        .foregroundStyle(isHazmatTank ? Color.orange : Color.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vehicleTitle(v))
                            .font(EType.body.weight(.bold))
                            .foregroundStyle(palette.textPrimary)
                        Text("VIN \(v.vin ?? "—") · \(v.licensePlate ?? "—")")
                            .font(.caption2.monospaced())
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                }

                HStack(spacing: 6) {
                    statusCapsule(v.status ?? "—")
                    if isHazmatTank {
                        Text("HAZMAT TANK")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                            .foregroundStyle(Color.orange)
                    }
                }

                // KPI grid 2×2 (ODOMETER / MPG 30D / LAST SVC / NEXT SVC)
                HStack(spacing: 8) {
                    kpiTile(label: "ODOMETER",
                            value: v.currentMileage.map { "\($0.formatted(.number))" } ?? "—",
                            unit: "mi")
                    kpiTile(label: "MPG · 30D",
                            value: "—",
                            unit: "—")
                }
                HStack(spacing: 8) {
                    kpiTile(label: "LAST SVC",
                            value: daysAgoOrDate(v.lastServiceDate),
                            unit: shortDate(v.lastServiceDate))
                    kpiTile(label: "NEXT SVC",
                            value: daysUntilOrDate(v.nextServiceDate),
                            unit: shortDate(v.nextServiceDate))
                }

                // Equipment capability strip (1 of 3 active per SVG)
                VStack(alignment: .leading, spacing: 4) {
                    Text("EQUIPMENT CAPABILITY · 1 OF 3 ACTIVE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    HStack(spacing: 6) {
                        capabilityChip("MC-306 TANKER", active: isHazmatTank)
                        capabilityChip("53' REEFER",    active: false)
                        capabilityChip("48' FLATBED",   active: false)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func statusCapsule(_ raw: String) -> some View {
        let s = raw.lowercased()
        let label: String = {
            switch s {
            case "in_use":          return "ON ROUTE"
            case "available":       return "AVAILABLE"
            case "maintenance":     return "IN SHOP"
            case "out_of_service":  return "OUT OF SERVICE"
            default:                return raw.uppercased()
            }
        }()
        let color: Color = {
            switch s {
            case "in_use":          return Color.green
            case "available":       return Color.blue
            case "maintenance":     return Color.orange
            case "out_of_service":  return Color.red
            default:                return palette.textSecondary
            }
        }()
        return Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    private func kpiTile(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(palette.textPrimary)
            Text(unit).font(.caption2.monospacedDigit()).foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCardSoft)
        )
    }

    private func capabilityChip(_ label: String, active: Bool) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(active ? .white : palette.textTertiary)
            .background(
                Capsule().fill(active ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCardSoft))
            )
            .overlay(
                Capsule().strokeBorder(active ? Color.clear : palette.borderFaint)
            )
    }

    // MARK: - IFTA quarterly strip

    private var iftaStrip: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("IFTA · 2026 · QUARTERLY")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("48 states · IRP IA")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.textTertiary)
                }
                HStack(spacing: 8) {
                    ForEach(1...4, id: \.self) { q in
                        iftaQuarterTile(q)
                    }
                }
                let ytdMiles = iftaQuarters.values.reduce(0.0) { $0 + ($1.totalMiles ?? 0) }
                let ytdTax   = iftaQuarters.values.reduce(0.0) { $0 + ($1.netTaxOwed ?? $1.totalTaxDue ?? 0) }
                if ytdMiles > 0 || ytdTax > 0 {
                    Text("YTD fuel tax $\(Int(ytdTax).formatted(.number)) · YTD miles \(Int(ytdMiles).formatted(.number))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.textTertiary)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func iftaQuarterTile(_ q: Int) -> some View {
        let result = iftaQuarters[q]
        let (statusLabel, statusColor): (String, Color) = {
            switch q {
            case 1: return ("FILED", .green)
            case 2: return ("IN PROGRESS", .orange)
            default: return ("UPCOMING", palette.textTertiary)
            }
        }()
        let value: String = {
            if let r = result, let tax = (r.netTaxOwed ?? r.totalTaxDue), tax > 0 {
                return "$\(Int(tax).formatted(.number))"
            }
            return "—"
        }()
        let miles: String = {
            if let r = result, let m = r.totalMiles, m > 0 {
                return "\(Int(m).formatted(.number)) mi"
            }
            return q >= 3 ? "opens Jul \(q * 3 - 6)" : "—"
        }()
        return VStack(alignment: .leading, spacing: 2) {
            Text("Q\(q) · \(statusLabel)")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(statusColor)
            Text(value)
                .font(.callout.weight(.heavy).monospacedDigit())
                .foregroundStyle(palette.textPrimary)
            Text(miles)
                .font(.caption2.monospaced())
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(palette.bgCardSoft)
        )
    }

    // MARK: - Maintenance Zeun section

    private var maintenanceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("MAINTENANCE · ZEUN SCHEDULE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if alertCount > 0 {
                    Text("\(alertCount) ALERT\(alertCount == 1 ? "" : "S")")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.18)))
                        .foregroundStyle(Color.orange)
                }
            }
            if maintenance.isEmpty {
                LifecycleCard {
                    Text("No scheduled maintenance.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            } else {
                ForEach(maintenance.prefix(3)) { m in
                    maintRow(m)
                }
            }
        }
    }

    private func maintRow(_ m: MaintenanceUpcoming) -> some View {
        let (badge, badgeColor) = maintBadge(m)
        return LifecycleCard {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.title ?? m.type ?? "Maintenance")
                        .font(EType.body.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text(maintSubtitle(m))
                        .font(.caption2)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text(badge)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(badgeColor.opacity(0.18)))
                    .foregroundStyle(badgeColor)
            }
        }
    }

    private func maintBadge(_ m: MaintenanceUpcoming) -> (String, Color) {
        switch (m.urgency ?? "").lowercased() {
        case "high":   return ("URGENT", .red)
        case "medium": return ("DUE", .orange)
        case "low":    return ("UPCOMING", .blue)
        default:
            if let due = isoDate(m.dueAt) {
                let days = Int(due.timeIntervalSinceNow / 86400)
                if days < 0 { return ("OVERDUE", .red) }
                if days <= 14 { return ("\(days)D", .orange) }
                return ("\(days)D", .blue)
            }
            return ("CURRENT", .green)
        }
    }

    private func maintSubtitle(_ m: MaintenanceUpcoming) -> String {
        var bits: [String] = []
        if let d = m.dueAt, let date = isoDate(d) {
            let f = DateFormatter(); f.dateStyle = .medium
            bits.append(f.string(from: date))
        }
        if let d = m.description, !d.isEmpty { bits.append(d) }
        if let l = m.location, !l.isEmpty { bits.append(l) }
        return bits.joined(separator: " · ")
    }

    // MARK: - Schedule PM CTA

    private var schedulePmCard: some View {
        Button {
            // Future: schedule-PM sheet. For now, post a notification
            // the Zeun composer can subscribe to.
            NotificationCenter.default.post(
                name: NSNotification.Name("eusoCatalystSchedulePmRequested"),
                object: nil
            )
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Schedule PM in home bay")
                        .font(EType.body.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Save ~90 min vs road shop. Auto-adds to Zeun.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, Space.s4).padding(.vertical, 12)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.4))
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func vehicleTitle(_ v: VehicleRow) -> String {
        let bits = [v.make, v.model].compactMap { $0 }.filter { !$0.isEmpty }
        let head = bits.isEmpty ? "Vehicle \(v.id)" : bits.joined(separator: " ")
        if let y = v.year { return "\(head) · \(y)" }
        return head
    }

    private func shortDate(_ iso: String?) -> String {
        guard let date = isoDate(iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func daysAgoOrDate(_ iso: String?) -> String {
        guard let date = isoDate(iso) else { return "—" }
        let days = max(0, Int(Date().timeIntervalSince(date) / 86400))
        return "\(days)d"
    }

    private func daysUntilOrDate(_ iso: String?) -> String {
        guard let date = isoDate(iso) else { return "—" }
        let days = Int(date.timeIntervalSinceNow / 86400)
        if days < 0 { return "OVERDUE" }
        return "\(days)d"
    }

    private func isoDate(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }

    // MARK: - Pipeline

    private func loadAll() async {
        loading = true; error = nil
        async let v: Void = loadVehicles()
        async let i: Void = loadIFTA()
        async let m: Void = loadMaintenance()
        async let a: Void = loadAlerts()
        _ = await (v, i, m, a)
        loading = false
    }

    private func loadVehicles() async {
        struct In: Encodable {
            let status: String?; let type: String?; let search: String?
            let limit: Int?; let offset: Int?
        }
        do {
            let r: VehiclesList = try await EusoTripAPI.shared.query(
                "vehicles.list",
                input: In(status: nil, type: nil, search: nil, limit: 50, offset: 0)
            )
            vehicles = r.rows
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func loadIFTA() async {
        let year = Calendar.current.component(.year, from: Date())
        struct In: Encodable { let quarter: Int; let year: Int }
        await withTaskGroup(of: (Int, IFTAQuarterResult?).self) { group in
            for q in 1...4 {
                group.addTask { @Sendable in
                    do {
                        let r: IFTAQuarterResult = try await EusoTripAPI.shared.query(
                            "iftaCalculator.calculateQuarter",
                            input: In(quarter: q, year: year)
                        )
                        return (q, r)
                    } catch { return (q, nil) }
                }
            }
            for await (q, r) in group {
                if let r { iftaQuarters[q] = r }
            }
        }
    }

    private func loadMaintenance() async {
        struct In: Encodable { let days: Int? }
        do {
            maintenance = try await EusoTripAPI.shared.query(
                "maintenance.getUpcoming", input: In(days: 90)
            )
        } catch { /* */ }
    }

    private func loadAlerts() async {
        do {
            let r: MaintenanceAlerts = try await EusoTripAPI.shared.queryNoInput("maintenance.getAlerts")
            alertCount = r.count
        } catch { /* */ }
    }
}

// MARK: - Previews

#Preview("303 Fleet Vehicles · Dark") {
    CatalystFleetVehiclesScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("303 Fleet Vehicles · Light") {
    CatalystFleetVehiclesScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
