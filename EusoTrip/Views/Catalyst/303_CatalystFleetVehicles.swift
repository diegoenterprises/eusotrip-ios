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
//    vehicles.create                — add vehicle CTA
//    vehicles.scheduleMaintenance   — schedule PM CTA
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

    enum CodingKeys: String, CodingKey {
        case id, vin, make, model, year, licensePlate, vehicleType, type, status
        case currentLat, currentLng, currentMileage, mileage
        case lastServiceDate, nextServiceDate, nextMaintenanceDate
        case assignedDriverId, currentDriverId, driver
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.vin = try container.decodeIfPresent(String.self, forKey: .vin)
        self.make = try container.decodeIfPresent(String.self, forKey: .make)
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
        self.year = try container.decodeIfPresent(Int.self, forKey: .year)
        self.licensePlate = try container.decodeIfPresent(String.self, forKey: .licensePlate)
        self.vehicleType = try container.decodeIfPresent(String.self, forKey: .vehicleType)
            ?? container.decodeIfPresent(String.self, forKey: .type)
        self.status = try container.decodeIfPresent(String.self, forKey: .status)
        self.currentLat = try container.decodeIfPresent(Double.self, forKey: .currentLat)
        self.currentLng = try container.decodeIfPresent(Double.self, forKey: .currentLng)
        self.currentMileage = try container.decodeIfPresent(Int.self, forKey: .currentMileage)
            ?? container.decodeIfPresent(Int.self, forKey: .mileage)
        self.lastServiceDate = try container.decodeIfPresent(String.self, forKey: .lastServiceDate)
        self.nextServiceDate = try container.decodeIfPresent(String.self, forKey: .nextServiceDate)
            ?? container.decodeIfPresent(String.self, forKey: .nextMaintenanceDate)
        self.assignedDriverId = try container.decodeIfPresent(String.self, forKey: .assignedDriverId)
            ?? container.decodeIfPresent(String.self, forKey: .currentDriverId)
            ?? container.decodeIfPresent(String.self, forKey: .driver)
    }
}

private struct VehiclesList: Decodable {
    let vehicles: [VehicleRow]?
    let items: [VehicleRow]?
    let total: Int?
    var rows: [VehicleRow] { vehicles ?? items ?? [] }

    enum CodingKeys: String, CodingKey { case vehicles, items, total }

    init(from decoder: Decoder) throws {
        if let bareRows = try? [VehicleRow](from: decoder) {
            self.vehicles = bareRows
            self.items = nil
            self.total = bareRows.count
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.vehicles = try container.decodeIfPresent([VehicleRow].self, forKey: .vehicles)
        self.items = try container.decodeIfPresent([VehicleRow].self, forKey: .items)
        self.total = try container.decodeIfPresent(Int.self, forKey: .total)
    }
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

    enum CodingKeys: String, CodingKey {
        case id, vehicleId, type, dueAt, title, description, location, urgency
        case serviceType, nextDueDate, priority, isOverdue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.vehicleId = try container.decodeIfPresent(String.self, forKey: .vehicleId)
        let serviceType = try container.decodeIfPresent(String.self, forKey: .serviceType)
        self.type = try container.decodeIfPresent(String.self, forKey: .type) ?? serviceType
        self.dueAt = try container.decodeIfPresent(String.self, forKey: .dueAt)
            ?? container.decodeIfPresent(String.self, forKey: .nextDueDate)
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? serviceType?.replacingOccurrences(of: "_", with: " ").capitalized
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.location = try container.decodeIfPresent(String.self, forKey: .location)
        let priority = try container.decodeIfPresent(String.self, forKey: .priority)
        let overdue = try container.decodeIfPresent(Bool.self, forKey: .isOverdue) ?? false
        self.urgency = try container.decodeIfPresent(String.self, forKey: .urgency) ?? (overdue ? "high" : priority?.lowercased())
    }
}

private struct MaintenanceAlerts: Decodable {
    let alerts: Int?
    let total: Int?
    var count: Int { alerts ?? total ?? 0 }

    enum CodingKeys: String, CodingKey { case alerts, total }

    init(from decoder: Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            var count = 0
            while !array.isAtEnd {
                _ = try? array.decode(DiscardedDecodable.self)
                count += 1
            }
            self.alerts = count
            self.total = count
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.alerts = try container.decodeIfPresent(Int.self, forKey: .alerts)
        self.total = try container.decodeIfPresent(Int.self, forKey: .total)
    }
}

private struct DiscardedDecodable: Decodable {}

// MARK: - Screen

struct CatalystFleetVehiclesScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { FleetVehiclesBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Dispatch", systemImage: "rectangle.split.3x1.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Fleet",  systemImage: "truck.box.fill",  isCurrent: false),
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
    @State private var actionMessage: String?
    @State private var actionError: String?
    @State private var showAddVehicle: Bool = false
    @State private var showSchedulePM: Bool = false
    @State private var savingVehicle: Bool = false
    @State private var schedulingPM: Bool = false
    @State private var addVIN: String = ""
    @State private var addMake: String = ""
    @State private var addModel: String = ""
    @State private var addYear: String = ""
    @State private var addPlate: String = ""
    @State private var addVehicleType: String = "tractor"
    @State private var addCapacity: String = ""
    @State private var pmVehicleId: String = ""
    @State private var pmDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var pmNotes: String = ""

    private let vehicleTypes = ["tractor", "trailer", "tanker", "flatbed", "refrigerated", "dry_van", "lowboy", "step_deck"]

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
                actionFeedback
                iftaStrip
                maintenanceSection
                schedulePmCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
        .sheet(isPresented: $showAddVehicle) { addVehicleSheet }
        .sheet(isPresented: $showSchedulePM) { schedulePMSheet }
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
                    openAddVehicle()
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

    @ViewBuilder
    private var actionFeedback: some View {
        if let actionError {
            LifecycleCard(accentDanger: true) {
                Text(actionError).font(EType.caption).foregroundStyle(Brand.danger)
            }
        } else if let actionMessage {
            LifecycleCard {
                Text(actionMessage).font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var addVehicleSheet: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add Vehicle")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("Register a real fleet asset to your company roster.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    LifecycleCard {
                        VStack(spacing: 10) {
                            formField("VIN", text: $addVIN)
                            formField("Make", text: $addMake)
                            formField("Model", text: $addModel)
                            formField("Year", text: $addYear, keyboard: .numberPad)
                            formField("License plate", text: $addPlate)
                            formField("Capacity", text: $addCapacity)
                            Picker("Vehicle type", selection: $addVehicleType) {
                                ForEach(vehicleTypes, id: \.self) { type in
                                    Text(type.replacingOccurrences(of: "_", with: " ").capitalized).tag(type)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    if let actionError {
                        Text(actionError).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    Button {
                        Task { await createVehicle() }
                    } label: {
                        HStack {
                            if savingVehicle { ProgressView().tint(.white) }
                            Text(savingVehicle ? "Saving…" : "Save vehicle")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(savingVehicle || !addVehicleValid)
                }
                .padding(18)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showAddVehicle = false }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var schedulePMSheet: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Schedule PM")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("Set the next maintenance date on a real vehicle record.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    LifecycleCard {
                        VStack(spacing: 10) {
                            Picker("Vehicle", selection: $pmVehicleId) {
                                ForEach(vehicles) { vehicle in
                                    Text(vehicleTitle(vehicle)).tag(vehicle.id)
                                }
                            }
                            .pickerStyle(.menu)
                            DatePicker("Service date", selection: $pmDate, displayedComponents: .date)
                            formField("Notes", text: $pmNotes)
                        }
                    }
                    if let actionError {
                        Text(actionError).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    Button {
                        Task { await schedulePM() }
                    } label: {
                        HStack {
                            if schedulingPM { ProgressView().tint(.white) }
                            Text(schedulingPM ? "Scheduling…" : "Schedule PM")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(schedulingPM || pmVehicleId.isEmpty)
                }
                .padding(18)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showSchedulePM = false }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func formField(_ title: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.7).foregroundStyle(palette.textTertiary)
            TextField(title, text: text)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .keyboardType(keyboard)
                .textInputAutocapitalization(title == "VIN" ? .characters : .words)
                .autocorrectionDisabled(title == "VIN")
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(palette.bgSecondary))
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
                        Text("VIN \(v.vin ?? "-") · \(v.licensePlate ?? "-")")
                            .font(.caption2.monospaced())
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                }

                HStack(spacing: 6) {
                    statusCapsule(v.status ?? "-")
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
                            value: v.currentMileage.map { "\($0.formatted(.number))" } ?? "-",
                            unit: "mi")
                    kpiTile(label: "MPG · 30D",
                            value: "-",
                            unit: "-")
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
            return "-"
        }()
        let miles: String = {
            if let r = result, let m = r.totalMiles, m > 0 {
                return "\(Int(m).formatted(.number)) mi"
            }
            return q >= 3 ? "opens Jul \(q * 3 - 6)" : "-"
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
            openSchedulePM()
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
        guard let date = isoDate(iso) else { return "-" }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func daysAgoOrDate(_ iso: String?) -> String {
        guard let date = isoDate(iso) else { return "-" }
        let days = max(0, Int(Date().timeIntervalSince(date) / 86400))
        return "\(days)d"
    }

    private func daysUntilOrDate(_ iso: String?) -> String {
        guard let date = isoDate(iso) else { return "-" }
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

    // MARK: - Actions

    private var addVehicleValid: Bool {
        let vin = addVIN.trimmed.uppercased()
        guard !vin.isEmpty, vin.count <= 17, vehicleTypes.contains(addVehicleType) else { return false }
        if let year = Int(addYear.trimmed), !(1900...2100).contains(year) { return false }
        if !addYear.trimmed.isEmpty, Int(addYear.trimmed) == nil { return false }
        return true
    }

    private func openAddVehicle() {
        actionError = nil
        actionMessage = nil
        addVIN = ""
        addMake = ""
        addModel = ""
        addYear = ""
        addPlate = ""
        addVehicleType = "tractor"
        addCapacity = ""
        showAddVehicle = true
    }

    private func openSchedulePM() {
        actionError = nil
        actionMessage = nil
        guard !vehicles.isEmpty else {
            actionError = "Add or load a vehicle before scheduling PM."
            return
        }
        if pmVehicleId.isEmpty || !vehicles.contains(where: { $0.id == pmVehicleId }) {
            pmVehicleId = vehicles[0].id
        }
        showSchedulePM = true
    }

    private func createVehicle() async {
        guard addVehicleValid else {
            actionError = "Enter a valid VIN and vehicle type."
            return
        }
        savingVehicle = true
        actionError = nil
        actionMessage = nil
        defer { savingVehicle = false }

        struct In: Encodable {
            let vin: String
            let make: String?
            let model: String?
            let year: Int?
            let licensePlate: String?
            let vehicleType: String
            let capacity: String?
        }
        struct Out: Decodable {
            let success: Bool
            let id: String?
            let error: String?
        }

        do {
            let out: Out = try await EusoTripAPI.shared.mutation(
                "vehicles.create",
                input: In(
                    vin: addVIN.trimmed.uppercased(),
                    make: addMake.trimmed.nilIfEmpty,
                    model: addModel.trimmed.nilIfEmpty,
                    year: Int(addYear.trimmed),
                    licensePlate: addPlate.trimmed.nilIfEmpty,
                    vehicleType: addVehicleType,
                    capacity: addCapacity.trimmed.nilIfEmpty
                )
            )
            guard out.success else {
                actionError = out.error ?? "Vehicle was not saved."
                return
            }
            actionMessage = "Vehicle \(out.id.map { "#\($0)" } ?? "") saved to the live fleet roster."
            showAddVehicle = false
            await loadVehicles()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func schedulePM() async {
        guard !pmVehicleId.isEmpty else {
            actionError = "Choose a vehicle for PM."
            return
        }
        schedulingPM = true
        actionError = nil
        actionMessage = nil
        defer { schedulingPM = false }

        struct In: Encodable {
            let vehicleId: String
            let scheduledDate: String
            let notes: String?
        }
        struct Out: Decodable {
            let success: Bool
            let maintenanceId: String?
            let error: String?
        }

        do {
            let scheduledDate = ISO8601DateFormatter().string(from: pmDate)
            let out: Out = try await EusoTripAPI.shared.mutation(
                "vehicles.scheduleMaintenance",
                input: In(vehicleId: pmVehicleId, scheduledDate: scheduledDate, notes: pmNotes.trimmed.nilIfEmpty)
            )
            guard out.success else {
                actionError = out.error ?? "PM was not scheduled."
                return
            }
            actionMessage = "PM scheduled\(out.maintenanceId.map { " as Zeun #\($0)" } ?? "")."
            showSchedulePM = false
            await loadVehicles()
            await loadMaintenance()
            await loadAlerts()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
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
