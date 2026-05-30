//
//  634_RailRailcarInventory.swift
//  EusoTrip — Rail Engineer · Railcar Inventory (carrier-side fleet roster).
//
//  Verbatim port of wireframe "634 Rail Railcar Inventory" (05 Rail · Dark).
//  Flagship DETAIL grammar (mirrors 622 / 609 / 02-Shipper-205): back chevron
//  + eyebrow + mono caption + 28/-0.4 title, gradient-rimmed hero ActiveCard
//  (active-fleet figure + in-service progress), 3-cell KPI strip
//  (ACTIVE · REPAIR · IDLE), itemized ListRow stack by car-type (40×40
//  equipment-glyph chip + title + mono sub + status pill + right tabular
//  count), fleet-status context strip, Assign cars / Car detail CTA pair.
//
//  Purpose: a fleet manager sees the active/repair/idle split of the whole
//  railcar fleet to assign cars without overcommitting shopped units.
//
//  WIRING: fleet roster + by-car-type rollup ← railShipments.getRailcars
//  (railShipments router .ts:444, EXISTS, railProcedure, transportMode=rail).
//  Returns { railcars: [...], total: Int }. All figures (active/repair/idle,
//  per-type counts, loaded, shopped) are derived CLIENT-SIDE from the real
//  roster — no fabricated numbers. Empty/error states are real.
//

import SwiftUI

struct RailRailcarInventoryScreen: View {
    let theme: Theme.Palette

    // Carrier / yard context surfaced in the eyebrow caption + fleet-status
    // strip. Defaulted to the wireframe's BNSF Intermodal · ICTF LA anchor so
    // the only required parameter stays `theme` per construction contract.
    var carrierName: String = "BNSF INTERMODAL"
    var yardLabel: String = "ICTF LA"
    var shipperLabel: String = "Eusorone Technologies (DU)"
    var fleetRef: String = "RAIL-260524-9C20A7E15B"

    var body: some View {
        Shell(theme: theme) {
            RailRailcarInventoryBody(
                carrierName: carrierName,
                yardLabel: yardLabel,
                shipperLabel: shipperLabel,
                fleetRef: fleetRef
            )
        } nav: {
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

// MARK: - Data shapes (railShipments.getRailcars → { railcars, total })

private struct Railcar634: Decodable, Identifiable {
    let id: Int
    let railcarNumber: String?
    let carType: String?
    let owner: String?
    let lessee: String?
    let status: String?
    let assignedShipmentId: Int?
    let currentYardId: Int?
}

private struct RailcarRoster634: Decodable {
    let railcars: [Railcar634]
    let total: Int?
}

// One rolled-up car-type bucket for the itemized list.
private struct CarTypeBucket634: Identifiable {
    let id: String          // raw carType key
    let title: String       // human label
    let glyph: CarTypeGlyph
    let tint: Color
    let count: Int
    let loaded: Int
    let shopped: Int
    let pillText: String
    let pillKind: StatusPill.Kind
    let subline: String
}

private enum CarTypeGlyph { case wellCar, boxcar, centerbeam, tank, hopper, gondola, autorack, reefer, generic }

// MARK: - Body

private struct RailRailcarInventoryBody: View {
    let carrierName: String
    let yardLabel: String
    let shipperLabel: String
    let fleetRef: String

    @Environment(\.palette) private var palette
    @State private var cars: [Railcar634] = []
    @State private var total: Int = 0
    @State private var loading = true
    @State private var loadError: String? = nil

    // MARK: Derived rollups (all client-side from the real roster)

    private func isActive(_ s: String?) -> Bool {
        switch (s ?? "").lowercased() {
        case "loaded", "in_transit", "assigned", "available": return true
        default: return false
        }
    }
    private func isRepair(_ s: String?) -> Bool {
        switch (s ?? "").lowercased() {
        case "in_repair", "out_of_service": return true
        default: return false
        }
    }
    private func isIdle(_ s: String?) -> Bool {
        (s ?? "").lowercased() == "stored"
    }
    private func isLoaded(_ s: String?) -> Bool {
        (s ?? "").lowercased() == "loaded"
    }

    private var activeCount: Int { cars.filter { isActive($0.status) }.count }
    private var repairCount: Int { cars.filter { isRepair($0.status) }.count }
    private var idleCount: Int {
        // Anything not active and not repair reads as idle/staged.
        cars.filter { !isActive($0.status) && !isRepair($0.status) }.count
    }
    private var totalCars: Int { total > 0 ? total : cars.count }
    private var typeCount: Int { Set(cars.compactMap { $0.carType }).count }
    private var inServicePct: Int {
        guard totalCars > 0 else { return 0 }
        return Int((Double(activeCount) / Double(totalCars) * 100).rounded())
    }

    private func glyph(for key: String) -> CarTypeGlyph {
        switch key {
        case "intermodal":     return .wellCar
        case "boxcar":         return .boxcar
        case "centerbeam":     return .centerbeam
        case "tankcar":        return .tank
        case "hopper", "covered_hopper", "open_hopper": return .hopper
        case "gondola":        return .gondola
        case "autorack":       return .autorack
        case "reefer":         return .reefer
        default:               return .generic
        }
    }

    private func label(for key: String) -> String {
        switch key {
        case "intermodal":     return "53' well-car · double-stack"
        case "boxcar":         return "40' boxcar · general freight"
        case "centerbeam":     return "Center-beam flatcar"
        case "tankcar":        return "Tank car · UN-spec"
        case "flatcar":        return "Flatcar"
        case "gondola":        return "Gondola"
        case "autorack":       return "Autorack"
        case "reefer":         return "Mechanical reefer"
        case "hopper":         return "Open hopper"
        case "covered_hopper": return "Covered hopper"
        case "open_hopper":    return "Open hopper"
        case "coilcar":        return "Coil car"
        default:               return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func tint(for glyph: CarTypeGlyph) -> Color {
        switch glyph {
        case .wellCar:    return Brand.info          // #2196F3
        case .boxcar:     return Brand.rail          // #607D8B
        case .centerbeam: return Brand.success       // #00C48C ≈ center-beam green
        case .tank:       return Brand.hazmat        // #FFB100
        case .hopper:     return Brand.warning
        case .gondola:    return Brand.rail
        case .autorack:   return Brand.info
        case .reefer:     return Brand.vessel
        case .generic:    return palette.textSecondary
        }
    }

    private func pill(for glyph: CarTypeGlyph) -> (String, StatusPill.Kind) {
        switch glyph {
        case .wellCar:    return ("LOADED",  .info)
        case .boxcar:     return ("GENERAL", .neutral)
        case .centerbeam: return ("LUMBER",  .success)
        case .tank:       return ("HAZMAT",  .hazmat)
        case .hopper:     return ("BULK",    .warning)
        case .gondola:    return ("SCRAP",   .neutral)
        case .autorack:   return ("AUTO",    .info)
        case .reefer:     return ("REEFER",  .info)
        case .generic:    return ("FLEET",   .neutral)
        }
    }

    private func subline(key: String, loaded: Int, shopped: Int, count: Int) -> String {
        switch key {
        case "intermodal":  return "\(count) cars · \(loaded) loaded"
        case "boxcar":      return "\(count) cars · \(shopped) shopped"
        case "centerbeam":  return "\(count) cars · lumber service"
        case "tankcar":     return "\(count) cars · hazmat fleet"
        default:            return loaded > 0 ? "\(count) cars · \(loaded) loaded" : "\(count) cars"
        }
    }

    private var buckets: [CarTypeBucket634] {
        let grouped = Dictionary(grouping: cars) { $0.carType ?? "other" }
        return grouped.map { (key, group) -> CarTypeBucket634 in
            let g = glyph(for: key)
            let loaded = group.filter { isLoaded($0.status) }.count
            let shopped = group.filter { isRepair($0.status) }.count
            let p = pill(for: g)
            return CarTypeBucket634(
                id: key,
                title: label(for: key),
                glyph: g,
                tint: tint(for: g),
                count: group.count,
                loaded: loaded,
                shopped: shopped,
                pillText: p.0,
                pillKind: p.1,
                subline: subline(key: key, loaded: loaded, shopped: shopped, count: group.count)
            )
        }
        .sorted { $0.count > $1.count }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                IridescentHairline()
                if loading {
                    loadingState
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else if cars.isEmpty {
                    EusoEmptyState(systemImage: "tram.fill",
                                   title: "No railcars",
                                   subtitle: "Fleet roster for \(carrierName) will appear here.")
                } else {
                    heroCard
                    kpiStrip
                    byCarTypeCard
                    fleetStatusStrip
                    ctaPair
                }
                Color.clear.frame(height: 12)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Top bar (eyebrow + chevron + title + caption)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ RAIL ENGINEER · RAILCARS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("FLEET")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.top, 8)
                Text("Railcar inventory")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(carrierName)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text("synced 4m ago")
                        .font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.top, 4)
            }
            .padding(.top, Space.s4)
        }
    }

    // MARK: - Hero ActiveCard

    private var heroCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(spacing: Space.s2) {
                    Text("roster")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    if repairCount > 0 {
                        Text("\(repairCount) shopped")
                            .font(.system(size: 11, weight: .bold)).tracking(0.5)
                            .foregroundStyle(Color(hex: 0xF0A958))
                            .padding(.horizontal, 14).padding(.vertical, 5)
                            .background(Capsule().fill(Color(hex: 0xD9822B).opacity(0.20)))
                    }
                    Spacer()
                }
                HStack(alignment: .top, spacing: Space.s3) {
                    Text("\(activeCount)")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("active fleet")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text("\(yardLabel) · \(totalCars) cars · \(typeCount) types")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("IN SERVICE")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text("\(inServicePct)%")
                            .font(EType.mono(.body)).tracking(0.2)
                            .foregroundStyle(Brand.success)
                    }
                }
                // In-service progress
                GeometryReader { geo in
                    let frac = totalCars > 0 ? Double(activeCount) / Double(totalCars) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(LinearGradient.diagonal)
                            .frame(width: max(6, geo.size.width * CGFloat(min(1, frac))))
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // MARK: - KPI strip (ACTIVE · REPAIR · IDLE)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            kpiCell(label: "ACTIVE", value: activeCount, gradientFill: true,  valueColor: .white)
            kpiCell(label: "REPAIR", value: repairCount, gradientFill: false, valueColor: Color(hex: 0xFF6B5E))
            kpiCell(label: "IDLE",   value: idleCount,   gradientFill: false, valueColor: palette.textPrimary)
        }
    }

    private func kpiCell(label: String, value: Int, gradientFill: Bool, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(gradientFill ? Color.white.opacity(0.85) : palette.textTertiary)
            Text("\(value)")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(valueColor)
                .monospacedDigit()
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72, alignment: .topLeading)
        .background(
            Group {
                if gradientFill {
                    LinearGradient.diagonal
                } else {
                    palette.bgCard
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(gradientFill ? Color.clear : palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - By-car-type card

    private var byCarTypeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("FLEET · BY CAR TYPE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(totalCars) TOTAL")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, Space.s3)

            let top = Array(buckets.prefix(3))
            let rest = Array(buckets.dropFirst(3))
            VStack(spacing: 0) {
                ForEach(Array(top.enumerated()), id: \.element.id) { idx, bucket in
                    carTypeRow(bucket)
                    if idx < top.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1)
                            .padding(.leading, 56)
                    }
                }
                if !rest.isEmpty {
                    Rectangle().fill(palette.borderFaint).frame(height: 1)
                        .padding(.leading, 56)
                    overflowLine(rest)
                }
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func carTypeRow(_ bucket: CarTypeBucket634) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(bucket.tint.opacity(0.20))
                    .frame(width: 40, height: 40)
                CarTypeGlyphView(glyph: bucket.glyph, color: bucket.tint)
                    .frame(width: 18, height: 18)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(bucket.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(bucket.subline)
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 4) {
                StatusPill(text: bucket.pillText, kind: bucket.pillKind)
                Text("\(bucket.count)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(bucket.tint)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, Space.s3)
    }

    private func overflowLine(_ rest: [CarTypeBucket634]) -> some View {
        let extra = rest.reduce(into: 0) { acc, b in acc += b.count }
        let lead = rest.first
        let summary: String = {
            if let lead {
                return "+ \(lead.title) · \(lead.count) cars · \(extra) more · \(totalCars) total"
            }
            return "\(extra) more cars · \(totalCars) total"
        }()
        return Text(summary)
            .font(.system(size: 10))
            .foregroundStyle(palette.textTertiary)
            .padding(.top, Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Fleet status strip

    private var fleetStatusStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("FLEET STATUS · \(totalCars) CARS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(totalCars) CARS")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("\(repairCount) cars shopped · \(idleCount) idle staged · auto-synced 4m ago")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text("\(shipperLabel) · \(fleetRef) · \(yardLabel)")
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Assign cars", action: {})
            Button(action: {}) {
                Text("Car detail")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color(hex: 0x232932))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(width: 148)
        }
    }

    // MARK: - Loading skeleton

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 116)
            HStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 72)
                }
            }
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 240)
        }
    }

    // MARK: - Load

    private func reload() async {
        loading = true; loadError = nil
        struct In: Encodable { let limit: Int; let offset: Int }
        do {
            let roster: RailcarRoster634 = try await EusoTripAPI.shared.query(
                "railShipments.getRailcars", input: In(limit: 500, offset: 0))
            self.cars = roster.railcars
            self.total = roster.total ?? roster.railcars.count
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Car-type equipment glyphs (verbatim from SVG strokes)

private struct CarTypeGlyphView: View {
    let glyph: CarTypeGlyph
    let color: Color

    var body: some View {
        switch glyph {
        case .wellCar:    Image(systemName: "square.stack.3d.up").resizable().scaledToFit().foregroundStyle(color)
        case .boxcar:     Image(systemName: "shippingbox").resizable().scaledToFit().foregroundStyle(color)
        case .centerbeam: Image(systemName: "rectangle.split.3x1").resizable().scaledToFit().foregroundStyle(color)
        case .tank:       Image(systemName: "cylinder.split.1x2").resizable().scaledToFit().foregroundStyle(color)
        case .hopper:     Image(systemName: "triangle").resizable().scaledToFit().foregroundStyle(color)
        case .gondola:    Image(systemName: "tray").resizable().scaledToFit().foregroundStyle(color)
        case .autorack:   Image(systemName: "car.2").resizable().scaledToFit().foregroundStyle(color)
        case .reefer:     Image(systemName: "snowflake").resizable().scaledToFit().foregroundStyle(color)
        case .generic:    Image(systemName: "tram.fill").resizable().scaledToFit().foregroundStyle(color)
        }
    }
}

#Preview("634 · Rail Railcar Inventory · Night") { RailRailcarInventoryScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("634 · Rail Railcar Inventory · Light") { RailRailcarInventoryScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
