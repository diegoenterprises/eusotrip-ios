//
//  Dpch714_DispatchTrio.swift
//  EusoTrip — Dispatch · Command Center / Fleet Map / Performance.
//
//  iOS port of three flagship web dispatch screens:
//    • DispatchCommandCenter.tsx → DispatchCommandCenterScreen
//    • DispatchFleetMap.tsx      → DispatchFleetMapScreen
//    • DispatchPerformance.tsx   → DispatchPerformanceScreen
//
//  All reads off REAL server endpoints — no stubs:
//    dispatch.autopilotStatus       (Command Center)
//    dispatch.unifiedLoads          (Command Center board)
//    dispatch.getAvailableDrivers   (Command Center)
//    location.tracking.getFleetMap  (Fleet Map)
//    dispatchRole.getFleetStats     (Fleet Map)
//    dispatchRole.getPerformanceStats   (Performance)
//    dispatchRole.getPerformanceMetrics (Performance)
//    dispatchRole.getPerformanceHistory (Performance)
//
//  Bundled into a single Swift file so the pbxproj only takes one
//  registration for the trio — keeps the eusotrip-killers screen-
//  porting sweep tight.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: ─────────────────────────────────────────────────────────
// MARK: Dispatch Command Center (714)
// MARK: ─────────────────────────────────────────────────────────

struct DispatchCommandCenterScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { CommandCenterBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",    systemImage: "house",         isCurrent: true),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct AutopilotStatus: Decodable, Hashable {
    let enabled: Bool?
    let activeDecisions: Int?
    let pendingApprovals: Int?
    let model: String?
}

private struct UnifiedLoadRow: Decodable, Hashable, Identifiable {
    let id: String
    let loadNumber: String?
    let status: String?
    let driverName: String?
    let pickupCity: String?
    let pickupState: String?
    let destCity: String?
    let destState: String?
    let rate: String?
}

private struct AvailableDriverRow: Decodable, Hashable, Identifiable {
    let id: String
    let name: String?
    let status: String?
    let currentCity: String?
    let currentState: String?
    let hosRemainingMin: Int?
}

private struct CommandCenterBody: View {
    @Environment(\.palette) private var palette
    @State private var autopilot: AutopilotStatus?
    @State private var loads: [UnifiedLoadRow] = []
    @State private var drivers: [AvailableDriverRow] = []
    @State private var loading: Bool = true
    @State private var error: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let a = autopilot { autopilotCard(a) }
                statsRow
                if !drivers.isEmpty { driverSection }
                if !loads.isEmpty { loadSection }
                if let err = error {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCH · COMMAND CENTER")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Live ops board")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
        }
    }

    private func autopilotCard(_ a: AutopilotStatus) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 6) {
                LifecycleSection(label: "ESANG AUTOPILOT", icon: "sparkles")
                HStack {
                    Text(a.enabled == true ? "ON" : "OFF")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(a.enabled == true ? Color.green : Color.secondary)
                    Spacer()
                    if let m = a.model {
                        Text(m).font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    }
                }
                HStack(spacing: 14) {
                    LifecycleStatTile(label: "ACTIVE",  value: "\(a.activeDecisions ?? 0)", icon: "wand.and.stars")
                    LifecycleStatTile(label: "PENDING", value: "\(a.pendingApprovals ?? 0)", icon: "hourglass")
                }
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "LOADS",       value: "\(loads.count)",   icon: "shippingbox.fill")
            LifecycleStatTile(label: "DRIVERS",     value: "\(drivers.count)", icon: "person.3.fill")
        }
    }

    private var driverSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AVAILABLE DRIVERS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            ForEach(drivers.prefix(8)) { d in
                LifecycleCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.name ?? "Driver").font(EType.body.weight(.semibold))
                            Text("\(d.currentCity ?? "—"), \(d.currentState ?? "—")").font(.caption).foregroundStyle(palette.textSecondary)
                        }
                        Spacer()
                        if let h = d.hosRemainingMin {
                            Text("\(h)m HOS").font(.caption.monospacedDigit().weight(.semibold))
                        }
                    }
                }
            }
        }
    }

    private var loadSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("UNIFIED LOAD BOARD").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            ForEach(loads.prefix(15)) { l in
                LifecycleCard {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(l.loadNumber ?? "Load \(l.id)").font(EType.body.weight(.bold))
                            Spacer()
                            Text((l.status ?? "").uppercased()).font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(palette.textSecondary)
                        }
                        Text("\(l.pickupCity ?? "—"), \(l.pickupState ?? "—") → \(l.destCity ?? "—"), \(l.destState ?? "—")").font(.caption).foregroundStyle(palette.textSecondary)
                        if let r = l.rate { Text("$\(r)").font(.caption.monospacedDigit().weight(.semibold)) }
                    }
                }
            }
        }
    }

    private func loadAll() async {
        loading = true; error = nil
        async let ap: Void = loadAutopilot()
        async let ld: Void = loadLoads()
        async let dr: Void = loadDrivers()
        _ = await (ap, ld, dr)
        loading = false
    }

    private func loadAutopilot() async {
        do { autopilot = try await EusoTripAPI.shared.queryNoInput("dispatch.autopilotStatus") } catch { /* optional */ }
    }
    private func loadLoads() async {
        struct In: Encodable { let limit: Int }
        struct Out: Decodable { let loads: [UnifiedLoadRow]?; let items: [UnifiedLoadRow]? }
        do {
            let r: Out = try await EusoTripAPI.shared.query("dispatch.unifiedLoads", input: In(limit: 30))
            loads = r.loads ?? r.items ?? []
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
    private func loadDrivers() async {
        struct In: Encodable { let limit: Int }
        do {
            let r: [AvailableDriverRow] = try await EusoTripAPI.shared.query("dispatch.getAvailableDrivers", input: In(limit: 25))
            drivers = r
        } catch { /* optional */ }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: Dispatch Fleet Map (715)
// MARK: ─────────────────────────────────────────────────────────

struct DispatchFleetMapScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { FleetMapBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",    systemImage: "house",         isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct FleetPosition: Decodable, Hashable, Identifiable {
    let id: String
    let driverId: String?
    let driverName: String?
    let latitude: Double?
    let longitude: Double?
    let speedMph: Double?
    let heading: Double?
    let status: String?
    let lastUpdate: String?
}

private struct FleetStatsRow: Decodable, Hashable {
    let totalDrivers: Int?
    let driving: Int?
    let idle: Int?
    let offDuty: Int?
    let avgUtilization: Double?
}

private struct FleetMapBody: View {
    @Environment(\.palette) private var palette
    @State private var positions: [FleetPosition] = []
    @State private var stats: FleetStatsRow?
    @State private var loading: Bool = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let s = stats { statsRow(s) }
                if loading { LifecycleCard { Text("Loading fleet…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if positions.isEmpty {
                    EusoEmptyState(systemImage: "map", title: "No fleet positions", subtitle: "Drivers will appear here once their ELD reports.")
                } else {
                    fleetList
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "map.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCH · FLEET MAP").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Live fleet positions").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func statsRow(_ s: FleetStatsRow) -> some View {
        HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "TOTAL",   value: "\(s.totalDrivers ?? 0)", icon: "person.3.fill")
            LifecycleStatTile(label: "DRIVING", value: "\(s.driving ?? 0)",      icon: "car.fill")
            LifecycleStatTile(label: "IDLE",    value: "\(s.idle ?? 0)",         icon: "pause.fill")
            LifecycleStatTile(label: "UTIL",    value: "\(Int(s.avgUtilization ?? 0))%", icon: "gauge")
        }
    }

    private var fleetList: some View {
        VStack(spacing: 6) {
            ForEach(positions) { p in
                LifecycleCard {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: statusIcon(p.status)).foregroundStyle(statusColor(p.status))
                            Text(p.driverName ?? "Driver \(p.driverId ?? p.id)").font(EType.body.weight(.semibold))
                            Spacer()
                            if let s = p.speedMph { Text("\(Int(s)) mph").font(.caption.monospacedDigit()) }
                        }
                        if let lat = p.latitude, let lng = p.longitude {
                            Text(String(format: "%.4f, %.4f", lat, lng))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private func statusIcon(_ raw: String?) -> String {
        switch (raw ?? "").lowercased() {
        case "driving": return "car.fill"
        case "idle":    return "pause.circle.fill"
        case "off_duty": return "moon.fill"
        default:         return "circle.fill"
        }
    }
    private func statusColor(_ raw: String?) -> Color {
        switch (raw ?? "").lowercased() {
        case "driving": return .green
        case "idle":    return .yellow
        case "off_duty": return .secondary
        default:         return .blue
        }
    }

    private func loadAll() async {
        loading = true
        async let p: Void = loadPositions()
        async let s: Void = loadStats()
        _ = await (p, s)
        loading = false
    }

    private func loadPositions() async {
        struct In: Encodable { let limit: Int }
        struct Out: Decodable { let positions: [FleetPosition]?; let drivers: [FleetPosition]? }
        do {
            let r: Out = try await EusoTripAPI.shared.query("location.tracking.getFleetMap", input: In(limit: 50))
            positions = r.positions ?? r.drivers ?? []
        } catch { /* */ }
    }
    private func loadStats() async {
        do { stats = try await EusoTripAPI.shared.queryNoInput("dispatchRole.getFleetStats") } catch { /* */ }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: Dispatch Performance (716)
// MARK: ─────────────────────────────────────────────────────────

struct DispatchPerformanceScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { PerformanceBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",    systemImage: "house",         isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",          isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

private struct PerformanceStats: Decodable, Hashable {
    let loadsCompleted: Int?
    let successRate: Int?
    let rating: Double?
    let onTimeRate: Int?
    let totalEarnings: Double?
    let trend: String?
}

private struct PerformanceMetric: Decodable, Hashable, Identifiable {
    let id: String
    let name: String?
    let value: Double?
    let target: Double?
    let weightUnit: String?
}

private struct PerformanceHistoryRow: Decodable, Hashable, Identifiable {
    let id: String
    let loadNumber: String?
    let route: String?
    let date: String?
    let rating: Double?
    let earnings: Double?
    let distance: Double?
    let onTime: Bool?
}

private struct PerformanceBody: View {
    @Environment(\.palette) private var palette
    @State private var stats: PerformanceStats?
    @State private var metrics: [PerformanceMetric] = []
    @State private var history: [PerformanceHistoryRow] = []
    @State private var loading: Bool = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let s = stats { statsCard(s) }
                if !metrics.isEmpty { metricsSection }
                if !history.isEmpty { historySection }
                if loading {
                    LifecycleCard { Text("Loading performance…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCH · PERFORMANCE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("KPIs & history").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func statsCard(_ s: PerformanceStats) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 6) {
                LifecycleSection(label: "OVERVIEW", icon: "speedometer")
                HStack(spacing: 14) {
                    LifecycleStatTile(label: "DELIVERED", value: "\(s.loadsCompleted ?? 0)", icon: "checkmark.seal.fill")
                    LifecycleStatTile(label: "ON-TIME",   value: "\(s.onTimeRate ?? 0)%",    icon: "clock.badge.checkmark")
                    LifecycleStatTile(label: "RATING",    value: String(format: "%.1f", s.rating ?? 0), icon: "star.fill")
                }
                if let e = s.totalEarnings, e > 0 {
                    HStack {
                        Text("TOTAL EARNINGS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                        Spacer()
                        Text("$\(Int(e).formatted(.number))").font(.body.weight(.heavy).monospacedDigit())
                    }
                }
            }
        }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("METRICS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            ForEach(metrics) { m in
                LifecycleCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.name ?? m.id).font(EType.body.weight(.semibold))
                            if let t = m.target, t > 0 {
                                Text("Target: \(numFmt(t)) \(m.weightUnit ?? "")").font(.caption2).foregroundStyle(palette.textTertiary)
                            }
                        }
                        Spacer()
                        Text(numFmt(m.value ?? 0))
                            .font(.title3.weight(.heavy).monospacedDigit())
                            .foregroundStyle(palette.textPrimary)
                    }
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DELIVERY HISTORY").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            ForEach(history.prefix(15)) { h in
                LifecycleCard {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(h.loadNumber ?? h.id).font(EType.body.weight(.bold))
                            Spacer()
                            if h.onTime == true {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else if h.onTime == false {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            }
                        }
                        Text(h.route ?? "—").font(.caption).foregroundStyle(palette.textSecondary)
                        HStack {
                            if let r = h.rating { Label(String(format: "%.1f", r), systemImage: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                            Spacer()
                            if let e = h.earnings, e > 0 {
                                Text("$\(Int(e))").font(.caption.monospacedDigit().weight(.semibold))
                            }
                        }
                    }
                }
            }
        }
    }

    private func numFmt(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(value).formatted(.number))" }
        return String(format: "%.1f", value)
    }

    private func loadAll() async {
        loading = true
        async let s: Void = loadStats()
        async let m: Void = loadMetrics()
        async let h: Void = loadHistory()
        _ = await (s, m, h)
        loading = false
    }

    private func loadStats() async {
        do { stats = try await EusoTripAPI.shared.queryNoInput("dispatchRole.getPerformanceStats") } catch { }
    }
    private func loadMetrics() async {
        struct In: Encodable { let period: String?; let limit: Int? }
        do {
            metrics = try await EusoTripAPI.shared.query("dispatchRole.getPerformanceMetrics", input: In(period: nil, limit: 10))
        } catch { }
    }
    private func loadHistory() async {
        struct In: Encodable { let period: String?; let limit: Int? }
        do {
            history = try await EusoTripAPI.shared.query("dispatchRole.getPerformanceHistory", input: In(period: nil, limit: 30))
        } catch { }
    }
}

// MARK: - Previews

#Preview("714 Command · Dark") { DispatchCommandCenterScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("714 Command · Light") { DispatchCommandCenterScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("715 Fleet · Dark")    { DispatchFleetMapScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("715 Fleet · Light")   { DispatchFleetMapScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("716 Perf · Dark")     { DispatchPerformanceScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("716 Perf · Light")    { DispatchPerformanceScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
