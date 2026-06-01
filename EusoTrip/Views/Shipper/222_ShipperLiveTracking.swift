//
//  222_ShipperLiveTracking.swift
//  EusoTrip 2027 UI — Shipper · Live Tracking (parity-reconciled 2026-04-29)
//
//  PARITY AUDIT 2026-04-29 — reconciled to wireframe canon at
//  /02 Shipper/Code/222_ShipperLiveTracking.swift. Persona: Diego
//  Usoro / Eusorone Technologies (companyId 1) per §11. Live
//  shipment rows pull §11.2 MATRIX-50 hex tails when present in
//  the active set (LD-260427-A38FB12C7E Houston→Dallas tanker, etc).
//
//  Layout (top → bottom):
//    1. TopBar           ✦ SHIPPER · LIVE TRACKING · TELEMETRY /
//                        "{N} PINGING · LAST {Xs} AGO" (Brand.success when healthy)
//    2. Title block      Live Tracking / "{X} in motion · {N} MATRIX loads · HERE basemap · 20s refresh"
//    3. IridescentHairline
//    4. Map hero (380pt) HereMapView basemap + mode-filter chip overlay
//                        (All / Healthy / Stale / Unassigned) + 3-cell KPI strip
//                        (AVG SPEED · SOONEST ETA · LAST PING)
//    5. ACTIVE SHIPMENTS section header + view-all link
//    6. Shipment rows    3pt left rim · load id mono · status pill · lane title ·
//                        spec line · ETA + position + last-ping triplet
//    7. Geofence ribbon  bottom · pin glyph + "GEOFENCE EVENTS · BACKEND PENDING"
//                        (EUSO-2132)
//
//  Real wiring preserved: `shippers.getActiveLoads(limit:25)` +
//  `telemetry.getLiveLocation(driverId:)` + `telemetry.getTrail(...)`
//  via `ShipperLiveTrackingStore`. 20s polling preserved. Detail
//  sheet preserved (current position + breadcrumb sparkline).
//
//  Backend gaps surfaced (logged in audit log, no fake data):
//    EUSO-2131 — Portfolio aggregates (avg speed across all in-
//                transit loads, soonest ETA in window) computed
//                client-side from positions / loads. Tighter
//                accuracy lands when `telemetry.getPortfolioStats`
//                ships.
//    EUSO-2132 — `telemetry.getGeofenceEvents(loadId, since)` not
//                yet on iOS API surface. Bottom geofence ribbon
//                paints placeholder until backend ships the event
//                stream.
//    EUSO-2133 — No per-load coord endpoint for the map hero.
//                `HereMapView` paints the basemap only; need a
//                per-load lat/lng + truck-puck endpoint so the
//                §11.2 anchor lanes can render breadcrumb trails.
//
//  Doctrine refs: §2 LOADS-tab nav (handled by ContentView); §3
//  numbers-first copy; §4.3 single iridescent hairline; §6 single
//  full-bleed map hero (HERE basemap canon); §11 / §11.2 / §11.4
//  Diego canon + UN1203/UN1005; §15.2 per-row 3pt tier rim; §17.2
//  status pill grammar; §19.2 file-scoped helpers; §20.4 no dead
//  buttons; §22.2 counter color (success when all-healthy).
//

import SwiftUI

// MARK: - Mode filter (wireframe canon: live coverage health buckets)

private enum LiveModeFilter: String, CaseIterable, Identifiable {
    case all
    case healthy
    case stale
    case unassigned

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:        return "All"
        case .healthy:    return "Healthy"
        case .stale:      return "Stale"
        case .unassigned: return "Unassigned"
        }
    }
}

// MARK: - Store (preserved verbatim)

@MainActor
final class ShipperLiveTrackingStore: ObservableObject {
    enum Phase {
        case idle
        case loading
        case loaded
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var loads: [ShipperAPI.ActiveLoad] = []
    @Published private(set) var positions: [Int: ShipperTelemetryAPI.LiveLocation] = [:]
    @Published private(set) var lastRefresh: Date? = nil

    private let api: EusoTripAPI
    private var pollTask: Task<Void, Never>? = nil

    init(api: EusoTripAPI = .shared) { self.api = api }

    deinit { pollTask?.cancel() }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(nanoseconds: 20 * 1_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        if case .loaded = phase {} else { phase = .loading }
        do {
            let active = try await api.shipper.getActiveLoads(limit: 25)
            let inTransit = active.filter { l in
                let s = l.status.lowercased()
                return s == "in_transit" || s == "loading" || s == "assigned"
            }
            self.loads = inTransit
            await fanFetchPositions(for: inTransit)
            self.lastRefresh = Date()
            self.phase = .loaded
        } catch {
            self.phase = .error("Couldn't reach tracking service.")
        }
    }

    private func fanFetchPositions(for loads: [ShipperAPI.ActiveLoad]) async {
        let driverIds: [Int] = loads.compactMap { $0.driverId }
        await withTaskGroup(of: (Int, ShipperTelemetryAPI.LiveLocation?).self) { group in
            for id in driverIds {
                group.addTask { [api] in
                    let loc = try? await api.shipperTelemetry.getLiveLocation(driverId: id)
                    return (id, loc)
                }
            }
            for await (id, loc) in group {
                if let loc { self.positions[id] = loc }
            }
        }
    }
}

// MARK: - Screen root

struct ShipperLiveTracking: View {
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    // Sheet→push (NAV remediation 2026-05-30): the per-load telemetry
    // detail renders in-stack via the surface's `\.rolePushDetail` layer
    // (slide-in + BespokeBackBar) instead of a slide-up sheet.
    @Environment(\.rolePushDetail) private var pushDetail
    @StateObject private var store = ShipperLiveTrackingStore()
    @State private var detail: ShipperAPI.ActiveLoad? = nil
    @State private var modeFilter: LiveModeFilter = .all

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, Space.s5)
                titleBlock
                    .padding(.top, Space.s2)
                IridescentHairline()
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s5)

                content
                    .padding(.top, Space.s3)

                Color.clear.frame(height: 96)
            }
        }
        .refreshable { await store.refresh() }
        .task { store.startPolling() }
        .onDisappear { store.stopPolling() }
        // RealtimeService → any inbound load assignment / reassignment
        // / surface-refresh event triggers an immediate store refresh
        // on top of the standard polling cadence so the board reflects
        // a fresh dispatch within sub-second instead of waiting for
        // the next polling tick.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await store.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task { await store.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadReassigned)) { _ in
            Task { await store.refresh() }
        }
    }

    // MARK: TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · LIVE TRACKING · TELEMETRY")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text(counterEyebrow)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(counterColor)
                .accessibilityLabel(counterAccessibility)
        }
        .padding(.horizontal, Space.s3)
    }

    private var counterEyebrow: String {
        let healthy = healthyCount
        if let lastSec = freshestPingSec {
            return "\(healthy) PINGING · LAST \(lastSec)s AGO"
        }
        if store.loads.isEmpty {
            return "—"
        }
        return "\(healthy) PINGING · WAITING"
    }

    private var counterColor: Color {
        if healthyCount > 0 && healthyCount == store.loads.filter({ $0.driverId != nil }).count {
            return Brand.success
        }
        return palette.textTertiary
    }

    private var counterAccessibility: String {
        "\(healthyCount) loads pinging healthy"
    }

    private var healthyCount: Int {
        store.positions.values.filter { !$0.stale }.count
    }

    private var freshestPingSec: Int? {
        let dates = store.positions.values.compactMap { $0.updatedAt.flatMap(parseISO) }
        guard let latest = dates.max() else { return nil }
        return max(0, Int(Date().timeIntervalSince(latest)))
    }

    private func parseISO(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    // MARK: Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Live Tracking")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text(titleSubtitle)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3)
    }

    private var titleSubtitle: String {
        let inMotion = store.loads.count
        // §11 MATRIX-50 batch size — the canonical Diego portfolio.
        let matrixSize = 50
        return "\(inMotion) in motion · \(matrixSize) MATRIX loads · HERE basemap · 20s refresh"
    }

    // MARK: Content state machine

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .loading:
            VStack(spacing: Space.s2) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.3))
                        .frame(height: 92)
                }
            }
            .padding(.horizontal, Space.s3)
        case .error(let m):
            errorCard(m)
                .padding(.horizontal, Space.s3)
        case .loaded:
            VStack(alignment: .leading, spacing: 0) {
                mapHero
                shipmentsSection
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s4)
                geofenceRibbon
                    .padding(.top, Space.s4)
            }
        }
    }

    // MARK: Map hero (HereMapView basemap + chip overlay + KPI strip)

    private var mapHero: some View {
        ZStack(alignment: .top) {
            // 2026-05-21: swapped the raster HereMapView (MKMapView + HERE
            // Maps Tile v3 — empty grid, plan doesn't serve raster) for the
            // OMV vector renderer that the web platform uses + that the
            // plan DOES serve.
            // 2026-06-01 (D-maps-basemap): the bespoke canvas now paints an
            // abstract land basemap, so it never reads blank. We also feed it
            // the REAL live driver positions (`store.positions`, sourced from
            // `telemetry.getLiveLocation`) as truck pucks, and frame the
            // camera on them. With no live fixes yet it falls back to CONUS so
            // the basemap is still visible. No fabricated coords.
            HereLiveMapView(
                center: liveMapCenter,
                zoom: liveMapZoom,
                baseLayers: liveMapLayers,
                addOns: .shipperTracking
            )
                .frame(height: 380)
                .clipped()
                .accessibilityLabel("Live load map, \(store.loads.count) active loads")

            VStack(alignment: .leading, spacing: Space.s3) {
                modeFilterChips
                kpiStrip
            }
            .padding(.horizontal, Space.s3)
            .padding(.top, 10)
        }
    }

    // MARK: Live map data (real driver positions → truck pucks)

    /// Loads with a live fix, honoring the active health filter. Each yields a
    /// real `(load, coord)` from `telemetry.getLiveLocation`. Loads without a
    /// driver / fix simply aren't pinned (no fabricated coords).
    private var pinnedLive: [(load: ShipperAPI.ActiveLoad, coord: HereLatLng)] {
        filteredLoads.compactMap { l in
            guard let id = l.driverId,
                  let p = store.positions[id],
                  let lat = p.lat, let lng = p.lng,
                  !(lat == 0 && lng == 0) else { return nil }
            return (l, HereLatLng(lat, lng))
        }
    }

    /// Truck-puck markers for every load with a real live fix. The marker id
    /// is the load id so a tap routes back to that load (HereLiveMapView marks
    /// id-carrying base pins actionable → `onSelectMarker`).
    private var liveMapLayers: [HereMapLayer] {
        let pins = pinnedLive.map { entry in
            HereMarker(
                at: entry.coord,
                kind: .truck,
                label: "\(entry.load.origin) → \(entry.load.destination)",
                id: entry.load.id
            )
        }
        return pins.isEmpty ? [] : [.markers(pins)]
    }

    /// Camera center = centroid of the live fixes; CONUS when none yet.
    private var liveMapCenter: HereLatLng {
        let coords = pinnedLive.map { $0.coord }
        guard !coords.isEmpty else { return .init(39.5, -98.35) }
        let lat = coords.map { $0.lat }.reduce(0, +) / Double(coords.count)
        let lng = coords.map { $0.lng }.reduce(0, +) / Double(coords.count)
        return .init(lat, lng)
    }

    /// Tighter zoom for a single fix, looser for a spread; CONUS framing (4)
    /// when there are no fixes so the abstract basemap reads as North America.
    private var liveMapZoom: Int {
        switch pinnedLive.count {
        case 0:  return 4
        case 1:  return 8
        default: return 5
        }
    }

    private var modeFilterChips: some View {
        let healthy = store.positions.values.filter { !$0.stale }.count
        let stale = store.positions.values.filter { $0.stale }.count
        let unassigned = store.loads.filter { $0.driverId == nil }.count
        let chips: [(LiveModeFilter, Int)] = [
            (.all,        store.loads.count),
            (.healthy,    healthy),
            (.stale,      stale),
            (.unassigned, unassigned)
        ]
        return HStack(spacing: 6) {
            ForEach(chips, id: \.0) { (mode, count) in
                modeChip(mode: mode, count: count)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func modeChip(mode: LiveModeFilter, count: Int) -> some View {
        let isActive = (mode == modeFilter)
        let label = "\(mode.label) · \(count)"
        Button(action: { tapModeChip(mode) }) {
            if isActive {
                Text(label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(LinearGradient.primary))
            } else {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
            }
        }
        .buttonStyle(.plain)
    }

    private func tapModeChip(_ mode: LiveModeFilter) {
        withAnimation(.easeOut(duration: 0.18)) { modeFilter = mode }
        NotificationCenter.default.post(
            name: .eusoShipperLiveModeFilter,
            object: nil,
            userInfo: [
                "source": "222_ShipperLiveTracking",
                "filter": mode.rawValue,
                "shipperCompanyId": 1
            ]
        )
    }

    private var kpiStrip: some View {
        HStack(spacing: 0) {
            kpiCell(label: "AVG SPEED",
                    value: avgSpeedValue,
                    valueStyle: .gradient,
                    trail: "mph",
                    trailColor: palette.textSecondary)
            kpiDivider
            kpiCell(label: "SOONEST ETA",
                    value: soonestEtaValue,
                    valueStyle: .neutral,
                    trail: soonestEtaLane,
                    trailColor: palette.textSecondary)
            kpiDivider
            kpiCell(label: "LAST PING",
                    value: lastPingValue,
                    valueStyle: .success,
                    trail: lastPingTrail,
                    trailColor: palette.textSecondary)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var avgSpeedValue: String {
        // EUSO-2131 — backend portfolio aggregate not shipped. Compute
        // client-side from current positions.
        let speeds = store.positions.values.compactMap { $0.speed }.filter { $0 > 0 }
        guard !speeds.isEmpty else { return "—" }
        let avg = speeds.reduce(0, +) / Double(speeds.count)
        return String(format: "%.0f", avg)
    }

    private var soonestEtaValue: String {
        // ETA on ActiveLoad is a String. Take the first non-empty as a
        // crude proxy until backend ships sortable ETAs (EUSO-2131).
        let firstEta = store.loads.first { !$0.eta.isEmpty }?.eta
        return firstEta ?? "—"
    }

    private var soonestEtaLane: String {
        guard let load = store.loads.first(where: { !$0.eta.isEmpty }) else { return "—" }
        let o = load.origin.split(separator: ",").first.map(String.init) ?? load.origin
        let d = load.destination.split(separator: ",").first.map(String.init) ?? load.destination
        return "\(o)→\(d)"
    }

    private var lastPingValue: String {
        if let s = freshestPingSec {
            return "\(s)s"
        }
        return "—"
    }

    private var lastPingTrail: String {
        let healthy = healthyCount
        let total = store.loads.filter { $0.driverId != nil }.count
        if total == 0 { return "no drivers" }
        if healthy == total { return "all healthy" }
        return "\(healthy)/\(total) healthy"
    }

    private enum ValueStyle { case gradient, success, neutral }

    private func kpiCell(label: String,
                         value: String,
                         valueStyle: ValueStyle,
                         trail: String?,
                         trailColor: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Group {
                    switch valueStyle {
                    case .gradient: Text(value).foregroundStyle(LinearGradient.diagonal)
                    case .success:  Text(value).foregroundStyle(Brand.success)
                    case .neutral:  Text(value).foregroundStyle(palette.textPrimary)
                    }
                }
                .font(.system(size: 22, weight: .bold).monospacedDigit())
                if let trail, let trailColor {
                    Text(trail)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(trailColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kpiDivider: some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(width: 1, height: 36)
            .padding(.horizontal, 4)
    }

    // MARK: Active shipments section

    private var shipmentsSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("ACTIVE SHIPMENTS")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Button(action: tapViewAll) {
                    Text("View all 50")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                .buttonStyle(.plain)
            }
            shipmentList
        }
    }

    @ViewBuilder
    private var shipmentList: some View {
        let rows = filteredLoads
        if rows.isEmpty {
            emptyCard
        } else {
            VStack(spacing: Space.s2) {
                ForEach(rows) { l in
                    Button(action: { openLoad(l) }) { shipmentRow(l) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private var filteredLoads: [ShipperAPI.ActiveLoad] {
        switch modeFilter {
        case .all:
            return store.loads
        case .healthy:
            return store.loads.filter { l in
                guard let id = l.driverId, let p = store.positions[id] else { return false }
                return !p.stale
            }
        case .stale:
            return store.loads.filter { l in
                guard let id = l.driverId, let p = store.positions[id] else { return false }
                return p.stale
            }
        case .unassigned:
            return store.loads.filter { $0.driverId == nil }
        }
    }

    private func shipmentRow(_ l: ShipperAPI.ActiveLoad) -> some View {
        let pos = l.driverId.flatMap { store.positions[$0] }
        let rim: RimKind = {
            if l.driverId == nil { return .neutral }
            if let p = pos, p.stale { return .warn }
            return .gradient
        }()
        return HStack(spacing: 0) {
            rimBar(for: rim)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(l.loadNumber)
                        .font(.system(size: 10, weight: .heavy).monospaced())
                        .tracking(0.5)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    statusPill(l.status, rim: rim)
                }
                Text("\(l.origin) → \(l.destination)")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(specLine(l))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                    Text(l.eta.isEmpty ? "ETA pending" : "ETA \(l.eta)")
                        .font(.system(size: 10, weight: .heavy).monospacedDigit())
                        .tracking(0.4)
                        .foregroundStyle(palette.textPrimary)
                    Text(positionLabel(pos))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Text(pingLabel(pos))
                        .font(.system(size: 10, weight: .heavy).monospacedDigit())
                        .tracking(0.4)
                        .foregroundStyle(pingColor(pos))
                }
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s3)
        }
        .frame(minHeight: 88)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(l.origin) to \(l.destination), \(l.status), load \(l.loadNumber)")
    }

    private enum RimKind { case gradient, warn, neutral }

    @ViewBuilder
    private func rimBar(for rim: RimKind) -> some View {
        switch rim {
        case .gradient: Rectangle().fill(LinearGradient.primary)
        case .warn:     Rectangle().fill(Brand.warning)
        case .neutral:  Rectangle().fill(palette.textTertiary)
        }
    }

    @ViewBuilder
    private func statusPill(_ status: String, rim: RimKind) -> some View {
        let label = status.replacingOccurrences(of: "_", with: " ").uppercased()
        switch rim {
        case .gradient:
            Text(label)
                .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                .foregroundStyle(LinearGradient.primary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(LinearGradient.primary.opacity(0.14)))
        case .warn:
            Text(label)
                .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                .foregroundStyle(Brand.warning)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Brand.warning.opacity(0.18)))
        case .neutral:
            Text(label)
                .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(palette.bgCardSoft))
        }
    }

    private func specLine(_ l: ShipperAPI.ActiveLoad) -> String {
        var parts: [String] = []
        if !l.catalyst.isEmpty {
            parts.append(l.catalyst)
        }
        if !l.driver.isEmpty {
            parts.append(l.driver)
        }
        return parts.isEmpty ? "Carrier pending" : parts.joined(separator: " · ")
    }

    private func positionLabel(_ pos: ShipperTelemetryAPI.LiveLocation?) -> String {
        guard let pos else { return "—" }
        if pos.stale { return "stale ping" }
        if let speed = pos.speed, speed > 0, let h = pos.heading {
            let dir = headingLabel(h)
            return String(format: "%.0f mph · %@", speed, dir)
        }
        if let lat = pos.lat, let lng = pos.lng {
            return String(format: "%.2f° · %.2f°", lat, lng)
        }
        return "—"
    }

    private func headingLabel(_ h: Double) -> String {
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let idx = Int(((h.truncatingRemainder(dividingBy: 360) + 360) / 45).rounded()) % 8
        return dirs[idx]
    }

    private func pingLabel(_ pos: ShipperTelemetryAPI.LiveLocation?) -> String {
        guard let pos, let updated = pos.updatedAt, let d = parseISO(updated) else {
            return "—"
        }
        let secs = max(0, Int(Date().timeIntervalSince(d)))
        if secs < 60 { return "\(secs)s" }
        if secs < 3600 { return "\(secs/60)m" }
        return "\(secs/3600)h"
    }

    private func pingColor(_ pos: ShipperTelemetryAPI.LiveLocation?) -> Color {
        guard let pos else { return palette.textTertiary }
        return pos.stale ? Brand.warning : Brand.success
    }

    // MARK: Geofence ribbon (placeholder · EUSO-2132)

    private var geofenceRibbon: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Space.s2) {
                pinGlyph
                Text("GEOFENCE EVENTS · BACKEND PENDING")
                    .font(EType.micro).tracking(0.5)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("EUSO-2132")
                    .font(EType.micro).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
            }
            Text("`telemetry.getGeofenceEvents` lands when backend ships the event stream.")
                .font(.system(size: 10))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                palette.bgCard
                LinearGradient(colors: [Brand.success.opacity(0.10),
                                        Brand.blue.opacity(0.10)],
                               startPoint: .leading, endPoint: .trailing)
            }
        )
        .overlay(alignment: .top) {
            Rectangle().fill(palette.borderFaint).frame(height: 1)
        }
    }

    private var pinGlyph: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 9, y: 0))
                p.addCurve(to: CGPoint(x: 18, y: 9),
                           control1: CGPoint(x: 14, y: 0),
                           control2: CGPoint(x: 18, y: 4))
                p.addCurve(to: CGPoint(x: 9, y: 24),
                           control1: CGPoint(x: 18, y: 15),
                           control2: CGPoint(x: 9, y: 24))
                p.addCurve(to: CGPoint(x: 0, y: 9),
                           control1: CGPoint(x: 9, y: 24),
                           control2: CGPoint(x: 0, y: 15))
                p.addCurve(to: CGPoint(x: 9, y: 0),
                           control1: CGPoint(x: 0, y: 4),
                           control2: CGPoint(x: 4, y: 0))
            }
            .stroke(Brand.success, lineWidth: 1.6)
            Circle().fill(Brand.success).frame(width: 6, height: 6).offset(y: -3)
        }
        .frame(width: 18, height: 24)
    }

    // MARK: Row open (sheet→push)

    /// Sheet→push: render the per-load telemetry detail in-stack via the
    /// surface `\.rolePushDetail` layer (BespokeBackBar provided by the
    /// layer). `detail` is retained for future reads. Re-provides
    /// `\.palette` since the pushed detail reads it.
    private func openLoad(_ l: ShipperAPI.ActiveLoad) {
        detail = l
        let p = palette
        pushDetail?(l.loadNumber) {
            AnyView(
                ShipperLiveTrackingDetail(load: l)
                    .environment(\.palette, p)
            )
        }
    }

    // MARK: View-all tap

    private func tapViewAll() {
        // Real action: jump to 201 ShipperLoads with "in_transit"
        // as the search query so the row list shows the full live
        // fleet. Replaces openURL stub. Telemetry post retained.
        NotificationCenter.default.post(
            name: .eusoShipperLiveViewAll,
            object: nil,
            userInfo: [
                "source": "222_ShipperLiveTracking",
                "shipperCompanyId": 1
            ]
        )
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap, object: nil,
            userInfo: ["screenId": "201", "query": "in_transit"]
        )
    }

    // MARK: Empty + error

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "location.slash")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text(modeFilter == .all ? "No in-transit loads" : "No matches for this filter")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text(modeFilter == .all
                 ? "Loads in `assigned`, `loading`, or `in_transit` status will appear here with live carrier coords."
                 : "Try a different filter chip on the map.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func errorCard(_ m: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
            Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
            Button("Retry") { Task { await store.refresh() } }
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Brand.info)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// Mode filter chip tap (All / Healthy / Stale / Unassigned).
    static let eusoShipperLiveModeFilter = Notification.Name("eusoShipperLiveModeFilter")
    /// "View all" link tap on the active-shipments header.
    static let eusoShipperLiveViewAll    = Notification.Name("eusoShipperLiveViewAll")
}

// MARK: - Detail sheet (preserved)

struct ShipperLiveTrackingDetail: View {
    let load: ShipperAPI.ActiveLoad
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var live: ShipperTelemetryAPI.LiveLocation? = nil
    @State private var trail: [ShipperTelemetryAPI.TrailPoint] = []
    @State private var phase: Phase = .loading

    enum Phase { case loading, loaded, error(String) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                hero
                if case .loading = phase {
                    loadingCard
                } else if case .error(let m) = phase {
                    errorCard(m)
                } else {
                    livePanel
                    trailCard
                }
                Color.clear.frame(height: 60)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
        }
        .background(palette.bgPage)
        .task { await fetch() }
        .refreshable { await fetch() }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LIVE LOAD")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            Text(load.loadNumber)
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("\(load.origin) → \(load.destination)")
                .font(EType.body).foregroundStyle(palette.textSecondary)
            HStack(spacing: 10) {
                if load.driverId != nil {
                    Label(load.driver, systemImage: "person.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                }
                Label(load.eta, systemImage: "clock.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, 4)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(
            colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.22)],
            startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var loadingCard: some View {
        HStack {
            ProgressView()
            Text("Pulling telemetry…").font(EType.caption).foregroundStyle(palette.textSecondary)
            Spacer()
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func errorCard(_ m: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
            Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
            Button("Retry") { Task { await fetch() } }
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.info)
        }
        .padding(Space.s3).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    @ViewBuilder
    private var livePanel: some View {
        if let p = live {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("CURRENT POSITION")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    if p.stale {
                        Label("Stale", systemImage: "wifi.exclamationmark")
                            .font(.system(size: 10, weight: .heavy)).foregroundStyle(Brand.warning)
                    } else {
                        Label("Live", systemImage: "dot.radiowaves.left.and.right")
                            .font(.system(size: 10, weight: .heavy)).foregroundStyle(Brand.success)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(coordsLabel(p))
                        .font(.system(size: 18, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textPrimary)
                }
                HStack(spacing: 8) {
                    metric("Speed", value: speedLabel(p.speed), tint: Brand.success)
                    metric("Heading", value: headingLabel(p.heading), tint: nil)
                    metric("Updated", value: updatedLabel(p.updatedAt), tint: nil)
                }
            }
            .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        } else {
            Text("Carrier hasn't pinged yet.").font(EType.caption).foregroundStyle(palette.textSecondary)
                .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private func metric(_ k: String, value: String, tint: Color?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(k.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(0.7).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(palette.textPrimary))
                .monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s2).padding(.vertical, Space.s2)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var trailCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("BREADCRUMB · LAST 4 H")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(trail.count) pts")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            if trail.isEmpty {
                Text("No trail recorded yet.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .padding(.vertical, 6)
            } else {
                BreadcrumbSparkline(points: trail).frame(height: 110)
                Text("Most recent ping: \(trail.last.map { relativeTrail($0.recordedAt) } ?? "—")")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func fetch() async {
        guard let id = load.driverId else {
            phase = .error("This load has no driver assigned yet.")
            return
        }
        phase = .loading
        do {
            async let l = EusoTripAPI.shared.shipperTelemetry.getLiveLocation(driverId: id)
            async let t = EusoTripAPI.shared.shipperTelemetry.getTrail(driverId: id, hoursBack: 4)
            self.live  = try await l
            self.trail = (try? await t) ?? []
            self.phase = .loaded
        } catch {
            self.phase = .error("Couldn't reach tracking service.")
        }
    }

    private func coordsLabel(_ p: ShipperTelemetryAPI.LiveLocation) -> String {
        guard let lat = p.lat, let lng = p.lng else { return "— · —" }
        return String(format: "%.4f° · %.4f°", lat, lng)
    }

    private func speedLabel(_ s: Double?) -> String {
        guard let s, s > 0 else { return "Idle" }
        return String(format: "%.0f mph", s)
    }

    private func headingLabel(_ h: Double?) -> String {
        guard let h else { return "—" }
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let idx = Int(((h.truncatingRemainder(dividingBy: 360) + 360) / 45).rounded()) % 8
        return dirs[idx]
    }

    private func updatedLabel(_ iso: String?) -> String {
        guard let iso else { return "—" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? Date()
        let s = Date().timeIntervalSince(d)
        if s < 60 { return "now" }
        if s < 3600 { return "\(Int(s/60))m" }
        return "\(Int(s/3600))h"
    }

    private func relativeTrail(_ iso: String) -> String { updatedLabel(iso) + " ago" }
}

// MARK: - Sparkline (preserved)

private struct BreadcrumbSparkline: View {
    let points: [ShipperTelemetryAPI.TrailPoint]
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            if points.count >= 2 {
                let lats = points.map { $0.lat }
                let lngs = points.map { $0.lng }
                let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 1
                let minLng = lngs.min() ?? 0, maxLng = lngs.max() ?? 1
                let dLat = max(maxLat - minLat, 0.0001)
                let dLng = max(maxLng - minLng, 0.0001)
                Path { p in
                    for (i, pt) in points.enumerated() {
                        let x = w * ((pt.lng - minLng) / dLng)
                        let y = h - h * ((pt.lat - minLat) / dLat)
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(LinearGradient.diagonal,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    let x = w * ((last.lng - minLng) / dLng)
                    let y = h - h * ((last.lat - minLat) / dLat)
                    Circle().fill(Brand.success).frame(width: 8, height: 8)
                        .overlay(Circle().fill(Brand.success.opacity(0.3)).scaleEffect(2.4))
                        .position(x: x, y: y)
                }
            } else {
                Text("Insufficient points")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }
}

// MARK: - Previews

#Preview("222 · Live Tracking · Dark") {
    ShipperLiveTracking()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("222 · Live Tracking · Light") {
    ShipperLiveTracking()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
