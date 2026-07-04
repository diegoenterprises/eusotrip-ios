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
                orbState: .thinking
            )
        }
    }
}

private struct FleetPin: Decodable, Identifiable, Hashable {
    let id: String
    let driverName: String?
    let status: String?
    let loadNumber: String?
    let loadStatus: String?
    let latitude: Double?
    let longitude: Double?
    let speed: Double?
    let heading: Double?
    let lastPingISO: String?
    let etaISO: String?
    let origin: String?
    let destination: String?
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .driverId)
        self.driverName = try c.decodeIfPresent(String.self, forKey: .name)
        self.status = try c.decodeIfPresent(String.self, forKey: .status)
        self.loadNumber = try c.decodeIfPresent(String.self, forKey: .loadNumber)
        self.loadStatus = try c.decodeIfPresent(String.self, forKey: .loadStatus)
        self.etaISO = try c.decodeIfPresent(String.self, forKey: .etaISO)
        self.origin = try c.decodeIfPresent(String.self, forKey: .origin)
        self.destination = try c.decodeIfPresent(String.self, forKey: .destination)
        
        let loc = try c.decodeIfPresent(FleetLocationEnvelope.self, forKey: .lastKnownLocation)
        if let loc {
            self.latitude = loc.lat
            self.longitude = loc.lng
            self.speed = Self.double(c, .speed) ?? loc.speed
            self.heading = Self.double(c, .heading) ?? loc.heading
            self.lastPingISO = loc.updatedAt
        } else {
            self.latitude = nil
            self.longitude = nil
            self.speed = Self.double(c, .speed)
            self.heading = Self.double(c, .heading)
            self.lastPingISO = nil
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case driverId, name, status, loadNumber, loadStatus, lastKnownLocation, speed, heading, etaISO, origin, destination
    }

    private static func double(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return v }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }
}

private struct FleetLocationEnvelope: Decodable, Hashable {
    let lat: Double?
    let lng: Double?
    let speed: Double?
    let heading: Double?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey { case lat, lng, speed, heading, updatedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lat = Self.double(c, .lat)
        lng = Self.double(c, .lng)
        speed = Self.double(c, .speed)
        heading = Self.double(c, .heading)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    private static func double(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return v }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }
}

private struct RouteBody: View {
    @Environment(\.palette) private var palette
    @State private var pins: [FleetPin] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    private var livePins: [FleetPin] { pins.filter { $0.latitude != nil && $0.longitude != nil } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                summary
                content
                Color.clear.frame(height: 150)
            }
            .padding(.horizontal, 14)
            .padding(.top, 58)
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
            Text("Company-scoped load movement, live pings and ETA posture.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var summary: some View {
        if !pins.isEmpty {
            HStack(spacing: Space.s2) {
                LifecycleStatTile(label: "LIVE", value: "\(livePins.count)", icon: "dot.radiowaves.up.forward")
                LifecycleStatTile(label: "AVG MPH", value: String(format: "%.0f", avgSpeed), icon: "speedometer")
                LifecycleStatTile(label: "STALE", value: "\(staleCount)", icon: "clock.arrow.circlepath", danger: staleCount > 0)
            }
        }
    }

    private var avgSpeed: Double {
        let xs = livePins.compactMap { $0.speed }
        guard !xs.isEmpty else { return 0 }
        return xs.reduce(0, +) / Double(xs.count)
    }

    private var staleCount: Int {
        let now = Date()
        let fmt = ISO8601DateFormatter()
        return pins.filter { p in
            guard let iso = p.lastPingISO, let d = fmt.date(from: iso) else { return p.latitude == nil || p.longitude == nil }
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
                fleetCard(p)
            }
        }
    }

    private func fleetCard(_ p: FleetPin) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: p.latitude == nil ? "antenna.radiowaves.left.and.right.slash" : "location.north.line.fill")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text((p.loadNumber ?? "Unassigned").uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                    Spacer(minLength: 8)
                    Text(statusLabel(p))
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.5)
                        .foregroundStyle(palette.textTertiary)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(dashIfEmpty(p.driverName))
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(laneLabel(p))
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                HStack(spacing: 8) {
                    telemetryTile("Position", latlng(p), p.latitude == nil)
                    telemetryTile("Speed", speedLabel(p), p.speed == nil)
                    telemetryTile("ETA", etaLabel(p), p.etaISO == nil)
                }
                Text(p.lastPingISO == nil ? "No telemetry ping received for this driver yet." : "Last ping \(humanISO(p.lastPingISO)).")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func telemetryTile(_ label: String, _ value: String, _ muted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(muted ? palette.textSecondary : palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func latlng(_ p: FleetPin) -> String {
        guard let lat = p.latitude, let lng = p.longitude else { return "No ping" }
        return String(format: "%.3f, %.3f", lat, lng)
    }

    private func speedLabel(_ p: FleetPin) -> String {
        guard let speed = p.speed else { return "Pending" }
        return String(format: "%.0f mph", speed)
    }

    private func etaLabel(_ p: FleetPin) -> String {
        guard let eta = p.etaISO else { return "Pending" }
        return humanISO(eta)
    }

    private func statusLabel(_ p: FleetPin) -> String {
        (p.loadStatus ?? p.status ?? "pending")
            .replacingOccurrences(of: "_", with: " ")
            .uppercased()
    }

    private func laneLabel(_ p: FleetPin) -> String {
        if let origin = p.origin, let destination = p.destination { return "\(origin) -> \(destination)" }
        if let origin = p.origin { return "From \(origin)" }
        if let destination = p.destination { return "To \(destination)" }
        return "Lane pending"
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [FleetPin] = try await EusoTripAPI.shared.queryNoInput("dispatch.getFleetLocations")
            pins = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("705 · Routing · Night") { DispatchRouteOptimizationScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("705 · Routing · Afternoon") { DispatchRouteOptimizationScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
