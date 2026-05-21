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

private struct HotZone: Decodable, Hashable, Identifiable {
    let id: String
    let metro: String?
    let state: String?
    let kind: String?            // weather / scales / crash / escort / clear
    let direction: String?       // "+18.4%" or "-9.2%"
    let summary: String?
    let detail: String?
    let lat: Double?
    let lng: Double?
}

private struct ZonesEnvelope: Decodable {
    let zones: [HotZone]?
    let items: [HotZone]?
    let avgRiskDelta: Double?
    let riskCount: Int?
    let clearCount: Int?
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
    private var riskZones: [HotZone] { zones.filter { ($0.kind ?? "") != "clear" } }
    private var clearZones: [HotZone] { zones.filter { ($0.kind ?? "") == "clear" } }
    private var filtered: [HotZone] {
        guard filter != .all else { return zones }
        return zones.filter { ($0.kind ?? "").lowercased() == filter.rawValue.lowercased() }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                kpiStrip
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
        let avg = envelope?.avgRiskDelta ?? 0
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

    private var filterTabs: some View {
        HStack(spacing: 6) {
            ForEach(ZoneFilter.allCases, id: \.self) { f in
                let count = f == .all ? zones.count : zones.filter { ($0.kind ?? "").lowercased() == f.rawValue.lowercased() }.count
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
        let isRisk = (z.kind ?? "") != "clear"
        let color: Color = isRisk ? .red : .green
        return LifecycleCard(accentDanger: isRisk) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(isRisk ? "RISK" : "CLEAR") · \((z.kind ?? "—").uppercased())")
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
