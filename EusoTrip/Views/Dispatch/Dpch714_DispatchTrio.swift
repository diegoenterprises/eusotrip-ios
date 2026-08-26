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
//  Map-layer adoption (2026-06-10): the Fleet Map adopts the §2
//  traffic-flow ribbon grammar (536 wireframe: jam `#FFA726` w6 ·
//  severe `#F44336` w6) fed by REAL HERE Real-Time Traffic v7 flow
//  links around the fleet's live anchor — jamFactor ≥8 ⇒ severe,
//  ≥4 ⇒ jam (HERE's documented 0–10 scale: 4-7 slow, 7-9 queued,
//  9-10 stopped), with the speed/freeFlow ratio fallback (≤0.25 ⇒
//  severe, ≤0.5 ⇒ jam) when jamFactor is absent. No flow data / no
//  real fleet fix ⇒ NO ribbons (honest empty).
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation

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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = Self.flexString(c, .id) ?? ""
        loadNumber = try? c.decode(String.self, forKey: .loadNumber)
        status = try? c.decode(String.self, forKey: .status)
        driverName = try? c.decode(String.self, forKey: .driverName)
        pickupCity = try? c.decode(String.self, forKey: .pickupCity)
        pickupState = try? c.decode(String.self, forKey: .pickupState)
        destCity = try? c.decode(String.self, forKey: .destCity)
        destState = try? c.decode(String.self, forKey: .destState)
        rate = Self.flexString(c, .rate)
    }

    private enum CodingKeys: String, CodingKey {
        case id, loadNumber, status, driverName, pickupCity, pickupState, destCity, destState, rate
    }

    private static func flexString(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        if let s = try? c.decode(String.self, forKey: key) { return s }
        if let i = try? c.decode(Int.self, forKey: key) { return String(i) }
        if let d = try? c.decode(Double.self, forKey: key) {
            return d == d.rounded() ? String(Int(d)) : String(d)
        }
        return nil
    }
}

private struct AvailableDriverRow: Decodable, Hashable, Identifiable {
    let id: String
    let name: String?
    let status: String?
    let currentCity: String?
    let currentState: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = Self.flexString(c, .id) ?? ""
        name = try? c.decode(String.self, forKey: .name)
        status = try? c.decode(String.self, forKey: .status)
        currentCity = try? c.decode(String.self, forKey: .currentCity)
        currentState = try? c.decode(String.self, forKey: .currentState)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, status, currentCity, currentState
    }

    private static func flexString(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        if let s = try? c.decode(String.self, forKey: key) { return s }
        if let i = try? c.decode(Int.self, forKey: key) { return String(i) }
        if let d = try? c.decode(Double.self, forKey: key) {
            return d == d.rounded() ? String(Int(d)) : String(d)
        }
        return nil
    }
}

private struct CommandCenterBody: View {
    @Environment(\.palette) private var palette
    @State private var autopilot: AutopilotStatus?
    @State private var loads: [UnifiedLoadRow] = []
    @State private var drivers: [AvailableDriverRow] = []
    @State private var hosEvidence: [HOSFleetDriver] = []
    @State private var hosWarning: String?
    @State private var loading: Bool = true
    @State private var error: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let a = autopilot { autopilotCard(a) }
                statsRow
                if !drivers.isEmpty { driverSection }
                if let hosWarning {
                    LifecycleCard(accentDanger: true) {
                        Text(hosWarning).font(EType.caption).foregroundStyle(Brand.warning)
                    }
                }
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
        .eusoRefreshable { await loadAll() }
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
            Text("ASSIGNABLE DRIVERS · CURRENT HOS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            ForEach(drivers.prefix(8)) { d in
                LifecycleCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.name ?? "Driver").font(EType.body.weight(.semibold))
                            Text("\(d.currentCity ?? "-"), \(d.currentState ?? "-")").font(.caption).foregroundStyle(palette.textSecondary)
                        }
                        Spacer()
                        if let hos = evidence(for: d.id),
                           let hours = hos.hoursAvailable?.drivingRemaining {
                            Text("\(HOSStatus.formatHours(hours)) · \(hos.source ?? "source unavailable")")
                                .font(.caption.monospacedDigit().weight(.semibold))
                        } else {
                            Text("HOS unavailable")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Brand.warning)
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
                        Text("\(l.pickupCity ?? "-"), \(l.pickupState ?? "-") → \(l.destCity ?? "-"), \(l.destState ?? "-")").font(.caption).foregroundStyle(palette.textSecondary)
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
            async let roster: [AvailableDriverRow] = EusoTripAPI.shared.query(
                "dispatch.getAvailableDrivers",
                input: In(limit: 25)
            )
            async let evidenceRows: [HOSFleetDriver] = EusoTripAPI.shared.queryNoInput("hos.getFleetHOS")
            let (driverRows, currentEvidence) = try await (roster, evidenceRows)
            hosEvidence = currentEvidence
            drivers = driverRows.filter { driver in
                evidence(in: currentEvidence, for: driver.id)?.assignmentEligibility() == .eligible
            }
            hosWarning = drivers.isEmpty && !driverRows.isEmpty
                ? "No driver has complete, current HOS evidence for assignment."
                : nil
        } catch {
            drivers = []
            hosEvidence = []
            hosWarning = "Current company HOS evidence could not refresh. Driver assignment is held."
        }
    }

    private func evidence(for driverId: String) -> HOSFleetDriver? {
        evidence(in: hosEvidence, for: driverId)
    }

    private func evidence(in rows: [HOSFleetDriver], for driverId: String) -> HOSFleetDriver? {
        rows.first { row in
            row.driverId == driverId || row.userId.map { String($0) } == driverId
        }
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

    /// §2 congestion ribbons over the fleet's corridor — REAL HERE
    /// Real-Time Traffic v7 flow links fetched around the first live
    /// fleet fix. Empty when HERE returns nothing, when no severity
    /// threshold trips, or when no fleet vehicle has a real fix yet
    /// (honest empty — the layer is simply absent).
    @State private var trafficSegments: [HereTrafficSegment] = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let s = stats { statsRow(s) }
                fleetMap
                if loading {
                    LifecycleCard { Text("Loading fleet…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if !positions.isEmpty {
                    fleetList
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadAll() }
        .eusoRefreshable { await loadAll() }
    }

    // MARK: Live fleet map (in-house HERE basemap · real driver GPS pucks)

    /// A fleet position's REAL live fix, coord-gated. Sourced from the
    /// `location.tracking.getFleetMap` proc, which joins the latest
    /// `gps_tracking` row per `vehicleId` and returns `positions[].{latitude,
    /// longitude}`. nil when either coord is absent or it resolves to null
    /// island — so a puck only ever draws on a real fix (no fabricated coords).
    private func fix(_ p: FleetPosition) -> HereLatLng? {
        guard let coordinate = LatLongParser.validatedCoordinate(
            latitude: p.latitude,
            longitude: p.longitude
        ) else { return nil }
        return HereLatLng(coordinate.latitude, coordinate.longitude)
    }

    /// Truck pucks for every real fix. id = the driver/position id so a tap on
    /// the canonical board routes back to that driver (HereLiveMapView marks
    /// id-carrying base pins actionable → `onSelectMarker`).
    private var truckMarkers: [HereMarker] {
        positions.compactMap { p in
            guard let f = fix(p) else { return nil }
            return HereMarker(
                at: f,
                kind: .truck,
                label: p.driverName ?? "Driver \(p.driverId ?? p.id)",
                id: p.driverId ?? p.id
            )
        }
    }

    /// Camera center = the first real fix; CONUS sentinel when the board is
    /// still awaiting its first gps_tracking heartbeat (never null island).
    private var mapCenter: HereLatLng {
        truckMarkers.first?.at ?? HereLatLng(39.5, -98.35)
    }

    @ViewBuilder
    private var fleetMap: some View {
        if !truckMarkers.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("LIVE FLEET MAP · live GPS")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                // §2 traffic ribbons ride UNDER the pucks — only when real
                // HERE flow links tripped a jam/severe threshold.
                let trafficLayers: [HereMapLayer] = trafficSegments.isEmpty
                    ? []
                    : [.trafficFlow(trafficSegments)]
                HereLiveMapView(
                    center: mapCenter,
                    zoom: 4,
                    baseLayers: trafficLayers + [.markers(truckMarkers)],
                    addOns: .shipperTracking,
                    mapModeContext: .primary(.truck),
                    liveOperationsStatus: .init(
                        availability: .degraded,
                        sourceLabel: "Fleet telemetry",
                        detail: "Road fleet positions available; freshness not supplied",
                        observationCount: truckMarkers.count
                    )
                )
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
                .accessibilityLabel("Live fleet map, \(truckMarkers.count) drivers reporting")
            }
        } else if !loading {
            // Coord gate — no parseable live fix on the board yet. Honest
            // placeholder so the map never frames on null island. Lights up the
            // instant a gps_tracking heartbeat lands for any fleet vehicle.
            HStack(spacing: 12) {
                Image(systemName: "map")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No fleet positions")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("Waiting for a live GPS signal from a fleet driver")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
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
        VStack(alignment: .leading, spacing: 6) {
            Text("FLEET ROSTER").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            ForEach(positions) { p in
                LifecycleCard {
                    HStack(spacing: 8) {
                        Image(systemName: statusIcon(p.status)).foregroundStyle(statusColor(p.status))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.driverName ?? "Driver \(p.driverId ?? p.id)").font(EType.body.weight(.semibold))
                            Text((p.status ?? "—").replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption2).foregroundStyle(palette.textTertiary)
                        }
                        Spacer()
                        if fix(p) == nil {
                            Text("NO FIX").font(.caption2.weight(.bold)).tracking(0.4).foregroundStyle(palette.textTertiary)
                        } else if let s = p.speedMph {
                            Text("\(Int(s)) mph").font(.caption.monospacedDigit())
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
        // Traffic depends on the fleet anchor, so it runs AFTER the
        // positions land (and silently no-ops without a real fix).
        await loadTraffic()
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

    // MARK: §2 traffic-flow ribbons (REAL HERE Real-Time Traffic v7)

    /// Fetches HERE flow links around the first REAL fleet fix and maps
    /// them onto the canon `.trafficFlow` layer. Every ribbon is a real
    /// HERE shape-link polyline whose live flow tripped a jam/severe
    /// threshold; anything below the jam floor is NOT painted (free
    /// flow is the basemap, not a ribbon). Any failure ⇒ empty array.
    private func loadTraffic() async {
        // Honest gate: no real fleet fix → no traffic query → no ribbons.
        guard let anchor = truckMarkers.first?.at else {
            trafficSegments = []
            return
        }
        do {
            let flows = try await HereTrafficClient.shared.flow(
                near: CLLocationCoordinate2D(latitude: anchor.lat, longitude: anchor.lng),
                radiusMeters: 30_000
            )
            var segs: [HereTrafficSegment] = []
            outer: for result in flows {
                guard let severity = Self.severity(for: result.currentFlow) else { continue }
                for link in result.location?.shape?.links ?? [] {
                    let pts: [HereLatLng] = (link.points ?? []).compactMap { point -> HereLatLng? in
                        guard let coordinate = LatLongParser.validatedCoordinate(
                            latitude: point.lat,
                            longitude: point.lng
                        ) else { return nil }
                        return HereLatLng(coordinate)
                    }
                    guard pts.count >= 2 else { continue }
                    segs.append(HereTrafficSegment(
                        polyline: pts,
                        severity: severity
                    ))
                    // Perf cap — the canvas culls, but there's no need to
                    // ship hundreds of ribbons for a zoom-4 board.
                    if segs.count >= 60 { break outer }
                }
            }
            trafficSegments = segs
        } catch {
            trafficSegments = []   // honest empty — never a fabricated ribbon
        }
    }

    /// HERE jamFactor scales 0 (free) → 10 (closed); per HERE's docs
    /// 4-7 is slow, 7-9 queued, 9-10 stopped. Canon mapping: ≥8 ⇒
    /// severe (`#F44336`), ≥4 ⇒ jam (`#FFA726`), else no ribbon. When
    /// jamFactor is absent, the speed/freeFlow ratio stands in:
    /// ≤0.25 ⇒ severe, ≤0.5 ⇒ jam.
    private static func severity(for flow: HereTrafficFlow?) -> HereTrafficSegment.Severity? {
        guard let f = flow else { return nil }
        if let jf = f.jamFactor, jf.isFinite {
            if jf >= 8 { return .severe }
            if jf >= 4 { return .jam }
            return nil
        }
        if let s = f.speed, let ff = f.freeFlow, s.isFinite, ff.isFinite, ff > 0 {
            let ratio = s / ff
            if ratio <= 0.25 { return .severe }
            if ratio <= 0.5 { return .jam }
        }
        return nil
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

private struct PerformanceDashboardFallback: Decodable, Hashable {
    let activeLoads: Int?
    let unassigned: Int?
    let inTransit: Int?
    let issues: Int?
    let completedToday: Int?
    let totalDrivers: Int?
    let availableDrivers: Int?
}

private struct PerformanceBody: View {
    @Environment(\.palette) private var palette
    @State private var stats: PerformanceStats?
    @State private var metrics: [PerformanceMetric] = []
    @State private var history: [PerformanceHistoryRow] = []
    @State private var fallback: PerformanceDashboardFallback?
    @State private var loadErrors: [String] = []
    @State private var loading: Bool = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let s = stats { statsCard(s) }
                if !metrics.isEmpty { metricsSection }
                if !history.isEmpty { historySection }
                if stats == nil && metrics.isEmpty && history.isEmpty, let fallback {
                    fallbackCard(fallback)
                }
                if !loading && stats == nil && metrics.isEmpty && history.isEmpty && fallback == nil {
                    LifecycleCard(accentDanger: !loadErrors.isEmpty) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Performance data unavailable")
                                .font(EType.bodyStrong)
                                .foregroundStyle(loadErrors.isEmpty ? palette.textPrimary : Brand.danger)
                            Text(loadErrors.first ?? "No dispatch performance rows are available for this company yet.")
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if loading {
                    LifecycleCard { Text("Loading performance…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                }
                Color.clear.frame(height: 150)
            }
            .padding(.horizontal, 14)
            .padding(.top, 58)
        }
        .task { await loadAll() }
        .eusoRefreshable { await loadAll() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCH · PERFORMANCE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("KPIs & history").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Dispatcher score, completed freight, on-time posture and company activity.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
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
                        Text(h.route ?? "-").font(.caption).foregroundStyle(palette.textSecondary)
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

    private func fallbackCard(_ f: PerformanceDashboardFallback) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 12) {
                LifecycleSection(label: "LIVE COMPANY PULSE", icon: "waveform.path.ecg")
                HStack(spacing: 8) {
                    LifecycleStatTile(label: "COMPLETE", value: "\(f.completedToday ?? 0)", icon: "checkmark.seal.fill")
                    LifecycleStatTile(label: "ACTIVE", value: "\(f.activeLoads ?? 0)", icon: "shippingbox.fill")
                    LifecycleStatTile(label: "ON ROAD", value: "\(f.inTransit ?? 0)", icon: "truck.box.fill")
                }
                HStack(spacing: 8) {
                    performanceMini(label: "Unassigned", value: f.unassigned ?? 0, danger: (f.unassigned ?? 0) > 0)
                    performanceMini(label: "Issues", value: f.issues ?? 0, danger: (f.issues ?? 0) > 0)
                    performanceMini(label: "Drivers", value: f.totalDrivers ?? 0, subvalue: "\(f.availableDrivers ?? 0) available")
                }
                Text("Detailed performance history appears after completed company freight is available. The live dispatch pulse stays visible so this screen never renders blank.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func performanceMini(label: String, value: Int, subvalue: String? = nil, danger: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text("\(value)")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(danger ? Brand.danger : palette.textPrimary)
                .monospacedDigit()
            if let subvalue {
                Text(subvalue)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func numFmt(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(value).formatted(.number))" }
        return String(format: "%.1f", value)
    }

    private func loadAll() async {
        loading = true
        loadErrors = []
        fallback = nil
        async let s: Void = loadStats()
        async let m: Void = loadMetrics()
        async let h: Void = loadHistory()
        _ = await (s, m, h)
        if stats == nil && metrics.isEmpty && history.isEmpty {
            await loadFallback()
        }
        loading = false
    }

    private func loadStats() async {
        do { stats = try await EusoTripAPI.shared.queryNoInput("dispatchRole.getPerformanceStats") }
        catch { loadErrors.append((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription) }
    }
    private func loadMetrics() async {
        struct In: Encodable { let period: String?; let limit: Int? }
        do {
            metrics = try await EusoTripAPI.shared.query("dispatchRole.getPerformanceMetrics", input: In(period: nil, limit: 10))
        } catch { loadErrors.append((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription) }
    }
    private func loadHistory() async {
        struct In: Encodable { let period: String?; let limit: Int? }
        do {
            history = try await EusoTripAPI.shared.query("dispatchRole.getPerformanceHistory", input: In(period: nil, limit: 30))
        } catch { loadErrors.append((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription) }
    }
    private func loadFallback() async {
        do { fallback = try await EusoTripAPI.shared.queryNoInput("dispatch.getDashboardStats") }
        catch { loadErrors.append((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription) }
    }
}

// MARK: - Previews

#Preview("714 Command · Dark") { DispatchCommandCenterScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("714 Command · Light") { DispatchCommandCenterScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("715 Fleet · Dark")    { DispatchFleetMapScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("715 Fleet · Light")   { DispatchFleetMapScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("716 Perf · Dark")     { DispatchPerformanceScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("716 Perf · Light")    { DispatchPerformanceScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
