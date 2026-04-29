//
//  705_DispatchRouteOptimization.swift
//  EusoTrip — Dispatch · Route optimization (fleet positions + ETAs).
//

import SwiftUI

struct DispatchRouteOptimizationScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RouteBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .working
            )
        }
    }
}

private struct FleetPin: Decodable, Identifiable, Hashable {
    let id: String
    let driverName: String?
    let loadNumber: String?
    let latitude: Double?
    let longitude: Double?
    let speed: Double?
    let heading: Double?
    let lastPingISO: String?
    let etaISO: String?
}

private struct RouteBody: View {
    @Environment(\.palette) private var palette
    @State private var pins: [FleetPin] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                summary
                content
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
                Image(systemName: "map.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCH · ROUTING").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Fleet positions").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Live pings + ETAs. ESANG suggests reroutes when traffic shifts.").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    @ViewBuilder
    private var summary: some View {
        if !pins.isEmpty {
            HStack(spacing: Space.s2) {
                LifecycleStatTile(label: "TRACKED", value: "\(pins.count)", icon: "dot.radiowaves.up.forward")
                LifecycleStatTile(label: "AVG MPH", value: String(format: "%.0f", avgSpeed), icon: "speedometer")
                LifecycleStatTile(label: "STALE", value: "\(staleCount)", icon: "clock.arrow.circlepath", danger: staleCount > 0)
            }
        }
    }

    private var avgSpeed: Double {
        let xs = pins.compactMap { $0.speed }
        guard !xs.isEmpty else { return 0 }
        return xs.reduce(0, +) / Double(xs.count)
    }

    private var staleCount: Int {
        let now = Date()
        let fmt = ISO8601DateFormatter()
        return pins.filter { p in
            guard let iso = p.lastPingISO, let d = fmt.date(from: iso) else { return false }
            return now.timeIntervalSince(d) > 600
        }.count
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading fleet positions…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if pins.isEmpty {
            EusoEmptyState(systemImage: "map", title: "No live pings", subtitle: "Drivers without ELD telemetry won't appear here.")
        } else {
            ForEach(pins) { p in
                LifecycleCard {
                    LifecycleSection(label: (p.loadNumber ?? "—").uppercased(), icon: "shippingbox")
                    LifecycleRow(label: "Driver",   value: dashIfEmpty(p.driverName))
                    LifecycleRow(label: "Lat/Lng",  value: latlng(p))
                    LifecycleRow(label: "Speed",    value: p.speed.map { String(format: "%.0f mph", $0) } ?? "—")
                    LifecycleRow(label: "Last ping",value: humanISO(p.lastPingISO))
                    LifecycleRow(label: "ETA",      value: humanISO(p.etaISO))
                }
            }
        }
    }

    private func latlng(_ p: FleetPin) -> String {
        guard let lat = p.latitude, let lng = p.longitude else { return "—" }
        return String(format: "%.3f, %.3f", lat, lng)
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [FleetPin] = try await EusoTripAPI.shared.api.queryNoInput("dispatch.getFleetLocations")
            pins = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("705 · Routing · Night") { DispatchRouteOptimizationScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("705 · Routing · Afternoon") { DispatchRouteOptimizationScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
