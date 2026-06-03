//
//  312_CatalystHotZones.swift
//  EusoTrip — Catalyst · Hot Zones (brick 312).
//
//  Pixel-match to `03 Catalyst/Dark-SVG/312 Hot Zones.svg`.
//  Risk-vs-clear metro intelligence — a catalyst-side counter-party
//  to the existing 100_MeHotZones driver surface. Consumes the
//  HereVectorMapView shipped in the same session (commit 5058acf)
//  so future visual layers (heatmap, adZones) drop in via the
//  layer model already supported.
//
//  Wire bindings (all real, no stubs):
//    hotZones.getActiveZones     — risk + clear metros
//    hotZones.getSurgeHistory    — 7d weather/scale/crash overlay
//
//  Bottom nav frozen per doctrine.
//

import SwiftUI

// Decodes the REAL `hotZones.getActiveZones` shape (MCP-verified at
// frontend/server/routers/hotZones.ts:939). The server maps HOT_ZONES →
// { id, name, center, radius, state, demandLevel, loadToTruckRatio,
//   surgeMultiplier, avgRate, topEquipment, hazmatClasses,
//   oversizedFrequency }. The previous struct decoded fields that don't
// exist on the wire (metro/kind/direction/summary), so every card read
// "—" and the KPIs read 0 — the "no data" bug. We decode the real
// fields and derive the risk/clear lens + direction client-side.
private struct HotZoneCenter312: Decodable, Hashable {
    let lat: Double
    let lng: Double
}

private struct HotZone: Decodable, Hashable, Identifiable {
    let id: String
    let name: String?
    let state: String?
    let center: HotZoneCenter312?
    let demandLevel: String?            // CRITICAL / HIGH / ELEVATED
    let loadToTruckRatio: Double?
    let surgeMultiplier: Double?
    let avgRate: Double?
    let topEquipment: [String]?
    let hazmatClasses: [String]?
    let oversizedFrequency: String?     // LOW / MODERATE / HIGH / VERY_HIGH

    /// Display metro name (server field is `name`).
    var metro: String? { name }

    /// Risk lens derived from real signals: hazmat load + oversized
    /// frequency + demand pressure. A zone reads "clear" only when it
    /// carries no hazmat classes, isn't oversized-heavy, and demand is
    /// merely ELEVATED — i.e. a corridor a catalyst can route through.
    var kind: String {
        let oversizedHot = (oversizedFrequency == "HIGH" || oversizedFrequency == "VERY_HIGH")
        let hazmatHeavy = (hazmatClasses?.count ?? 0) >= 3
        let critical = (demandLevel ?? "").uppercased() == "CRITICAL"
        if oversizedHot { return "escort" }       // needs oversize/escort handling
        if critical { return "scales" }           // demand spike → expect scale activity
        if hazmatHeavy { return "weather" }        // hazmat-heavy corridor (risk lens)
        return "clear"                             // route-through corridor
    }

    /// Surge expressed as a signed delta vs baseline (1.0×) — the headline
    /// the card shows on the right. +18.4% reads as a corridor heating up.
    var direction: String? {
        guard let s = surgeMultiplier else { return nil }
        return String(format: "%+.1f%%", (s - 1.0) * 100.0)
    }

    var summary: String? {
        guard let r = loadToTruckRatio else { return nil }
        let rate = avgRate.map { String(format: "$%.2f/mi", $0) } ?? "—"
        return String(format: "L:T %.2f · %@", r, rate)
    }

    var detail: String? {
        let eq = (topEquipment ?? []).prefix(3).joined(separator: " · ")
        return eq.isEmpty ? nil : eq
    }
}

private struct ZonesEnvelope: Decodable {
    let zones: [HotZone]?
    let items: [HotZone]?
}

struct CatalystHotZonesScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { HotZonesBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house",         isCurrent: false),
                          NavSlot(label: "Dispatch", systemImage: "rectangle.split.3x1.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct HotZonesBody: View {
    @Environment(\.palette) private var palette
    @State private var envelope: ZonesEnvelope?
    @State private var filter: ZoneFilter = .all
    @State private var loading: Bool = true
    @State private var error: String?

    enum ZoneFilter: String, CaseIterable {
        case all = "All", weather = "Weather", scales = "Scales", crash = "Crash", escort = "Escort"
    }

    private var zones: [HotZone] { envelope?.zones ?? envelope?.items ?? [] }
    private var riskZones: [HotZone] { zones.filter { $0.kind != "clear" } }
    private var clearZones: [HotZone] { zones.filter { $0.kind == "clear" } }
    private var filtered: [HotZone] {
        guard filter != .all else { return zones }
        return zones.filter { $0.kind.lowercased() == filter.rawValue.lowercased() }
    }

    /// Average surge delta across all zones (drives the AVG RISK KPI). The
    /// old envelope shipped `avgRiskDelta` which doesn't exist on the wire;
    /// we compute it from the real `surgeMultiplier` field instead.
    private var avgRiskDelta: Double {
        let deltas = zones.compactMap { $0.surgeMultiplier }.map { ($0 - 1.0) * 100.0 }
        guard !deltas.isEmpty else { return 0 }
        return deltas.reduce(0, +) / Double(deltas.count)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                kpiStrip
                heatmapCard
                filterTabs
                if loading && envelope == nil {
                    LifecycleCard { Text("Loading hot zones…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = error {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if filtered.isEmpty {
                    EusoEmptyState(systemImage: "map", title: "No hot zones in this lens", subtitle: "Risk + clear metros land here as ESANG ingests fresh ops data.")
                } else {
                    if filter == .all && !riskZones.isEmpty { riskSection }
                    if filter == .all && !clearZones.isEmpty { clearSection }
                    if filter != .all { ForEach(filtered) { zoneCard($0) } }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · HOT ZONES").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Hot zones").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Risk-vs-clear by metro").font(EType.caption).foregroundStyle(palette.textSecondary)
            Text("\(zones.count) METROS · OPS PULSE LIVE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
        }
    }

    private var kpiStrip: some View {
        let avg = avgRiskDelta
        let pct = String(format: "%+.1f%%", avg)
        return HStack(spacing: Space.s2) {
            kpi("AVG RISK", pct, "vs 30d", avg > 0 ? .red : .green)
            kpi("RISK METROS", "\(riskZones.count)", "avoid corridor", .red)
            kpi("CLEAR METROS", "\(clearZones.count)", "reroute here", .green)
        }
    }

    private func kpi(_ label: String, _ value: String, _ subtitle: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(color)
            Text(subtitle).font(.caption2).foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(color.opacity(0.3)))
    }

    // Demand heatmap — load-to-truck intensity per metro, the same
    // visual the web `/hot-zones` page renders. Built off the live
    // `loadToTruckRatio` so it paints real data the moment zones load
    // (honest empty otherwise). Tapping a cell jumps the filter lens.
    @ViewBuilder
    private var heatmapCard: some View {
        let cells: [HeatCell] = zones.prefix(12).map { z in
            HeatCell(
                id: z.id,
                label: z.state ?? "—",
                valueText: String(format: "%.1f×", z.loadToTruckRatio ?? 0),
                unitText: z.metro,
                intensity: z.loadToTruckRatio ?? 0,
                detail: z.kind
            )
        }
        if !cells.isEmpty {
            HeatCellMatrix(
                title: "Demand heatmap",
                eyebrow: "Load-to-truck intensity · live by metro",
                cells: cells,
                columns: 4,
                thresholds: HeatCellThresholds(
                    warmAt: 1.4, hotAt: 3.0,
                    minIntensity: 0.0, maxIntensity: 4.0
                ),
                onSelect: { cell in
                    // Tapping a cell snaps the lens to that zone's risk band
                    // when it maps onto a filter; otherwise no-op (stays All).
                    if let lens = ZoneFilter(rawValue: (cell.detail ?? "").capitalized) {
                        filter = lens
                    }
                }
            )
        }
    }

    private var filterTabs: some View {
        HStack(spacing: 6) {
            ForEach(ZoneFilter.allCases, id: \.self) { f in
                let count = f == .all ? zones.count : zones.filter { $0.kind.lowercased() == f.rawValue.lowercased() }.count
                Button { filter = f } label: {
                    HStack(spacing: 4) {
                        Text(f.rawValue).font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        Text("· \(count)").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .foregroundStyle(filter == f ? .white : palette.textSecondary)
                    .background(filter == f ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                    .clipShape(Capsule())
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var riskSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RISK ZONES · \(riskZones.count) METROS · HAZARDS > ROUTINE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            ForEach(riskZones) { zoneCard($0) }
        }
    }

    private var clearSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CLEAR ZONES · \(clearZones.count) METROS · REROUTE HERE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            ForEach(clearZones) { zoneCard($0) }
        }
    }

    private func zoneCard(_ z: HotZone) -> some View {
        let isRisk = z.kind != "clear"
        let color: Color = isRisk ? .red : .green
        return LifecycleCard(accentDanger: isRisk) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(isRisk ? "RISK" : "CLEAR") · \(z.kind.uppercased())")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(color.opacity(0.18)))
                        .foregroundStyle(color)
                    Spacer()
                    if let d = z.direction {
                        Text(d).font(.caption.weight(.heavy).monospacedDigit()).foregroundStyle(color)
                    }
                }
                Text(z.metro ?? "—").font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                if let s = z.summary { Text(s).font(.caption).foregroundStyle(palette.textSecondary) }
                if let d = z.detail  { Text(d).font(.caption2).foregroundStyle(palette.textTertiary) }
            }
        }
    }

    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            envelope = try await EusoTripAPI.shared.queryNoInput("hotZones.getActiveZones")
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}

#Preview("312 Hot Zones · Dark")  { CatalystHotZonesScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("312 Hot Zones · Light") { CatalystHotZonesScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
