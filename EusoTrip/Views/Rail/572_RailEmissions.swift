//
//  572_RailEmissions.swift
//  EusoTrip — Rail Engineer · Emissions (per-shipment intermodal-rail carbon footprint).
//
//  Verbatim port of "572 Rail Emissions.svg" (Light + Dark).
//  Per-shipment multimodal CO2 footprint vs all-truck baseline: modal breakdown legs,
//  intensity g/tmi, saved tonnes, offset cost. Generate CO2 report + buy offset CTA.
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME).
//
//  Data:
//    co2Calculator.calculateMultiModal    (EXISTS co2Calculator.ts:112)  → {legs,totalCo2Tonnes,carbonOffsetCostUsd}
//    co2Calculator.calculateTruckShipment (EXISTS co2Calculator.ts:31)   → all-truck baseline
//    co2Calculator.shipperSummary         (EXISTS co2Calculator.ts:167)  → intensity + savings rollup
//

import SwiftUI

struct RailEmissionsScreen: View {
    let theme: Theme.Palette
    let railId: String
    let shipmentId: Int

    var body: some View {
        Shell(theme: theme) { RailEmissionsBody(railId: railId, shipmentId: shipmentId) } nav: {
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

private struct EmissionsLeg572: Decodable {
    let leg: String?
    let mode: String?
    let co2Kg: Double?
    let co2Tonnes: Double?
    let miles: Double?
    let description: String?
}

private struct MultiModalResult572: Decodable {
    let legs: [EmissionsLeg572]?
    let totalCo2Tonnes: Double?
    let carbonOffsetCostUsd: Double?
    let routeSummary: String?
    let ladenTonnes: Double?
    let totalMiles: Double?
}

private struct TruckBaseline572: Decodable {
    let totalCo2Tonnes: Double?
    let co2Kg: Double?
}

private struct ShipperSummary572: Decodable {
    let totalCo2Tonnes: Double?
    let intensityGPerTonMile: Double?
    let co2SavedTonnes: Double?

    private enum CodingKeys: String, CodingKey {
        case totalCo2Tonnes
        case intensityKgPerMile
        case co2SavedTonnes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.totalCo2Tonnes = try c.decodeIfPresent(Double.self, forKey: .totalCo2Tonnes)
        self.co2SavedTonnes = try c.decodeIfPresent(Double.self, forKey: .co2SavedTonnes)
        // Server returns intensityKgPerMile (kg/mile); convert to intensityGPerTonMile (g/ton-mile).
        // Conversion: kg/mile * 1000 / 20 = g/ton-mile (assuming 20-ton canonical weight).
        if let kgPerMile = try c.decodeIfPresent(Double.self, forKey: .intensityKgPerMile) {
            self.intensityGPerTonMile = kgPerMile * 50
        } else {
            self.intensityGPerTonMile = nil
        }
    }
}

// MARK: - Display row

private struct LegRow572: Identifiable {
    let id: Int
    let title: String
    let sub: String
    let mode: String
    let co2Label: String
}

// MARK: - Body

private struct RailEmissionsBody: View {
    @Environment(\.palette) private var palette
    let railId: String
    let shipmentId: Int

    @State private var result: MultiModalResult572? = nil
    @State private var truckBaseline: TruckBaseline572? = nil
    @State private var summary: ShipperSummary572? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var isExporting = false

    // MARK: Derived

    private var totalLabel: String {
        guard let t = result?.totalCo2Tonnes else { return "—" }
        return String(format: "%.2ft", t)
    }
    private var truckLabel: String {
        if let t = truckBaseline?.totalCo2Tonnes { return String(format: "%.1ft", t) }
        if let kg = truckBaseline?.co2Kg         { return String(format: "%.1ft", kg / 1000) }
        return "—"
    }
    private var advantagePercent: Int {
        guard let actual = result?.totalCo2Tonnes,
              let truck  = truckBaseline?.totalCo2Tonnes,
              truck > 0 else { return 0 }
        return max(0, Int((1 - actual / truck) * 100))
    }
    private var advantageLabel: String {
        let pct = advantagePercent
        return pct > 0 ? "\(pct)% UNDER TRUCK" : "MULTIMODAL"
    }
    private var routeLabel: String  { result?.routeSummary ?? "Intermodal route" }
    private var ladenLabel: String {
        guard let l = result?.ladenTonnes, let m = result?.totalMiles else { return "—" }
        return "\(Int(l)) t lading · \(Int(m)) mi intermodal"
    }
    private var intensityLabel: String {
        if let i = summary?.intensityGPerTonMile { return String(format: "%.0f g/tmi", i) }
        return "—"
    }
    private var savedLabel: String {
        if let s = summary?.co2SavedTonnes { return String(format: "%.1ft", s) }
        guard let actual = result?.totalCo2Tonnes,
              let truck  = truckBaseline?.totalCo2Tonnes else { return "—" }
        return String(format: "%.1ft", max(0, truck - actual))
    }
    private var offsetLabel: String {
        guard let cost = result?.carbonOffsetCostUsd else { return "—" }
        return "$\(Int(cost))"
    }

    private func legCo2(_ leg: EmissionsLeg572) -> String {
        if let t = leg.co2Tonnes { return String(format: "%.2ft", t) }
        if let kg = leg.co2Kg   { return String(format: "%.2ft", kg / 1000) }
        return "—"
    }
    private func legSub(_ leg: EmissionsLeg572) -> String {
        var parts: [String] = [(leg.mode ?? "—").uppercased()]
        if let mi = leg.miles { parts.append("\(Int(mi)) mi") }
        if let desc = leg.description { parts.append(desc) }
        return parts.joined(separator: " · ")
    }

    private func modeInfo(_ mode: String) -> (label: String, color: Color, icon: String) {
        switch mode.lowercased() {
        case "dray", "truck": return ("DRAY",  Brand.warning, "shippingbox.fill")
        case "rail":          return ("RAIL",  Brand.success, "tram.fill")
        case "total":         return ("TOTAL", Brand.blue,    "leaf.fill")
        default:              return (mode.uppercased(), Brand.rail, "circle.fill")
        }
    }

    private var legRows: [LegRow572] {
        var rows: [LegRow572] = []
        for (i, leg) in (result?.legs ?? []).enumerated() {
            let title = leg.leg ?? leg.mode.map { $0.capitalized } ?? "—"
            rows.append(LegRow572(id: i, title: title, sub: legSub(leg),
                mode: leg.mode ?? "—", co2Label: legCo2(leg)))
        }
        if let total = result?.totalCo2Tonnes {
            var subParts = ["totalCo2Tonnes"]
            if let cost = result?.carbonOffsetCostUsd { subParts.append("offset $\(Int(cost))") }
            rows.append(LegRow572(id: rows.count, title: "Total footprint",
                sub: subParts.joined(separator: " · "),
                mode: "total", co2Label: String(format: "%.2ft", total)))
        }
        return rows
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading emissions…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    heroCard
                    kpiStrip
                    modalBreakdown
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
                    Text("RAIL ENGINEER · EMISSIONS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text(String(railId.prefix(22)))
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Carbon per shipment")
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
        let pct = advantagePercent
        let pillColor: Color = pct > 0 ? Brand.success : palette.textSecondary
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(advantageLabel)
                    .font(.system(size: 10, weight: .heavy)).kerning(0.6)
                    .foregroundStyle(pillColor)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(pillColor.opacity(0.14)))
                Text(routeLabel)
                    .font(.system(size: 10, weight: .heavy)).kerning(0.6)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(palette.textPrimary.opacity(0.06)))
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(totalLabel)
                        .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("CO2 this shipment")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Text(ladenLabel)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("ALL-TRUCK")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(truckLabel)
                        .font(.system(size: 22, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(Brand.danger)
                    Text("baseline")
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
            MetricTile(label: "INTENSITY", value: intensityLabel)
            MetricTile(label: "CO2 SAVED", value: savedLabel, gradientNumeral: true)
            MetricTile(label: "OFFSET",    value: offsetLabel)
        }
    }

    // MARK: - Modal breakdown

    private var modalBreakdown: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("MODAL BREAKDOWN")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("calculateMultiModal")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            if legRows.isEmpty {
                EusoEmptyState(
                    systemImage: "leaf",
                    title: "No leg data",
                    subtitle: "Modal breakdown will appear once tracking data loads."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(legRows.enumerated()), id: \.element.id) { idx, row in
                        legRow(row)
                        if idx < legRows.count - 1 {
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

    private func legRow(_ row: LegRow572) -> some View {
        let info = modeInfo(row.mode)
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(info.color.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: info.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(info.color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(row.sub)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(info.label)
                    .font(.system(size: 10, weight: .bold)).kerning(0.4)
                    .foregroundStyle(info.color)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(info.color.opacity(0.14)))
                Text(row.co2Label)
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(16)
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Export CO2 report", action: { Task { await exportReport() } }, leadingIcon: "doc.text", isLoading: isExporting)
            Button {} label: {
                Text("Buy offset · \(offsetLabel)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load / Actions

    private func load() async {
        loading = true; loadError = nil
        struct ShipmentIn: Encodable { let shipmentId: Int; let railId: String }
        do {
            async let multiResult: MultiModalResult572 = EusoTripAPI.shared.query(
                "co2Calculator.calculateMultiModal",
                input: ShipmentIn(shipmentId: shipmentId, railId: railId))
            async let truckResult: TruckBaseline572 = EusoTripAPI.shared.query(
                "co2Calculator.calculateTruckShipment",
                input: ShipmentIn(shipmentId: shipmentId, railId: railId))
            let (mr, tr) = try await (multiResult, truckResult)
            self.result        = mr
            self.truckBaseline = tr
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        do {
            struct EmptyIn: Encodable {}
            let s: ShipperSummary572 = try await EusoTripAPI.shared.query(
                "co2Calculator.shipperSummary", input: EmptyIn())
            self.summary = s
        } catch { /* best-effort intensity enrichment */ }
        loading = false
    }

    private func exportReport() async {
        isExporting = true
        struct ExportIn: Encodable { let railId: String }
        struct ExportOut: Decodable {}
        do {
            let _: ExportOut = try await EusoTripAPI.shared.query(
                "co2Calculator.exportReport", input: ExportIn(railId: railId))
        } catch { /* non-fatal */ }
        isExporting = false
    }
}

#Preview("572 · Rail Emissions · Night") { RailEmissionsScreen(theme: Theme.dark, railId: "RAIL-260523-7C3A0B12D4", shipmentId: 0).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("572 · Rail Emissions · Light") { RailEmissionsScreen(theme: Theme.light, railId: "RAIL-260523-7C3A0B12D4", shipmentId: 0).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
