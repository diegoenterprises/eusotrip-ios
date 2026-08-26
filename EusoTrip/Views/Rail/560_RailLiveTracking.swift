//
//  560_RailLiveTracking.swift
//  EusoTrip — Rail Engineer · Live Tracking (Class I AEI carrier-side).
//
//  Drill-down from 551_RailShipments. Faithful port of
//  "05 Rail/Light-SVG/560 Rail Live Tracking.svg" (Light + Dark).
//  RECONSTRUCTED to flagship DETAIL+journey grammar per
//  FOUNDER CADENCE DIRECTIVE 2026-05-24.  Nav anchored to
//  RailEngineerNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME),
//  Shipments tab current.
//
//  Data:
//    railShipments.getRailShipmentDetail (EXISTS railShipments.ts:140) → header + yards
//    railShipments.getRailTracking       (EXISTS railShipments.ts:485) → events + currentLocation
//    railShipments.liveTrackShipment     (EXISTS railShipments.ts:734) → Class I AEI live position
//

import SwiftUI

struct RailLiveTrackingScreen: View {
    let theme: Theme.Palette
    let shipmentId: Int
    var body: some View {
        Shell(theme: theme) {
            RailLiveTrackingBody(shipmentId: shipmentId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror getRailShipmentDetail + getRailTracking)

private struct RailYard560: Decodable {
    let id: Int
    let name: String?
    let code: String?
    let city: String?
    let state: String?
    /// Real yard anchor from the rail_yards catalog (`coordinates`
    /// JSON {lat,lng}) — getRailShipmentDetail returns the FULL yard
    /// row; the decode just never asked for it (Wave B, 2026-06-10).
    /// Used only as a labeled reference pin. It never substitutes for the
    /// server-owned EusoRail graph or route geometry.
    let coordinates: Coord560?
}

private struct Coord560: Decodable {
    let lat: Double?
    let lng: Double?
}

private struct RailLocation560: Decodable {
    let lat: Double?
    let lng: Double?
    let description: String?
}

private struct RailEvent560: Decodable, Identifiable {
    let id: Int
    let eventType: String
    let description: String?
    let location: RailLocation560?
    let timestamp: String?
}

private struct RailTracking560: Decodable {
    let events: [RailEvent560]
    let currentLocation: RailLocation560?
}

private struct RailShipmentDetail560: Decodable {
    let id: Int
    let shipmentNumber: String?
    let status: String?
    let carType: String?
    let numberOfCars: Int?
    let commodity: String?
    let hazmatClass: String?
    let unNumber: String?
    let originRailroad: String?
    let destinationRailroad: String?
    let waybillNumber: String?
    let originYard: RailYard560?
    let destinationYard: RailYard560?
}

// liveTrackShipment returns external Class I data — shape is best-effort
private struct LiveTrack560: Decodable {
    let speed: Double?
    let eta: String?
    let dwellRisk: String?
    let currentLocation: String?
    
    enum CodingKeys: String, CodingKey {
        case eta
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eta = try container.decodeIfPresent(String.self, forKey: .eta)
        
        // Extract optional fields from the full ShipmentTrackingResult structure
        // The server returns 13 fields; we selectively map only the 4 we use
        let allKeys = try decoder.container(keyedBy: AnyCodingKey.self)
        
        // speed: not in server response, leave nil (best-effort fallback)
        speed = nil
        
        // currentLocation: from server's location.city + location.station
        if let loc = try allKeys.decodeIfPresent(LocationContainer.self, forKey: AnyCodingKey(stringValue: "location")) {
            let parts = [loc.station, loc.city].compactMap { $0 }.joined(separator: ", ")
            currentLocation = parts.isEmpty ? nil : parts
        } else {
            currentLocation = nil
        }
        
        // dwellRisk: not in server response; compute as nil (can be enhanced with facility data)
        dwellRisk = nil
    }
}

// Helper struct to decode the nested location object
private struct LocationContainer: Decodable {
    let latitude: Double?
    let longitude: Double?
    let station: String?
    let city: String?
    let state: String?
    let railroad: String?
    let reportedAt: String?
}

// Helper for dynamic coding key lookup
private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    
    init?(intValue: Int) {
        return nil
    }
}

// MARK: - Body

private struct RailLiveTrackingBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    @State private var detail: RailShipmentDetail560? = nil
    @State private var tracking: RailTracking560? = nil
    @State private var liveData: LiveTrack560? = nil
    @State private var canonicalRouteLines: [[HereLatLng]] = []
    @State private var canonicalRouteStatus: String? = nil
    @State private var canonicalRouteVersion: Int? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // MARK: - Live AEI geometry (real coords only)

    /// The live car fix from the AEI tracking chain. nil unless the server
    /// returned a real, non-null-island coordinate — we never plot (0,0).
    private var liveCarPoint: HereLatLng? {
        guard let c = tracking?.currentLocation,
              let coordinate = LatLongParser.validatedCoordinate(
                  latitude: c.lat,
                  longitude: c.lng
              ) else { return nil }
        return HereLatLng(coordinate.latitude, coordinate.longitude)
    }

    /// The scan trail: every tracking event that carries a real lat/lng,
    /// in chronological order (oldest→newest). Null-island scans dropped.
    private var liveTrailPoints: [HereLatLng] {
        (tracking?.events ?? [])
            .compactMap { e -> (String, HereLatLng)? in
                guard let coordinate = LatLongParser.validatedCoordinate(
                    latitude: e.location?.lat,
                    longitude: e.location?.lng
                ) else { return nil }
                return (
                    e.timestamp ?? "",
                    HereLatLng(coordinate.latitude, coordinate.longitude)
                )
            }
            .sorted { $0.0 < $1.0 }
            .map { $0.1 }
    }

    /// The map may render an exact route without a live fix, or authorized
    /// observation evidence without a released route. Neither implies the other.
    private var hasMapGeo: Bool {
        liveCarPoint != nil || !liveTrailPoints.isEmpty || !canonicalRouteLines.isEmpty
    }

    private var originLabel: String {
        guard let y = detail?.originYard else { return "-" }
        return [y.code, y.city].compactMap { $0 }.joined(separator: " · ")
    }
    private var destLabel: String {
        guard let y = detail?.destinationYard else { return "-" }
        return [y.code, y.city].compactMap { $0 }.joined(separator: " · ")
    }
    private var currentPositionLabel: String {
        tracking?.currentLocation?.description
            ?? liveData?.currentLocation
            ?? "En route"
    }

    // A shipment status, an AEI milestone, and a straight line between yard
    // anchors are not route progress. Progress stays absent until the server
    // projects an authorized observation onto the exact bound EusoRail plan.

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard {
                        Text("Loading tracking…").font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    routeArcCard
                    kpiStrip
                    eventsSection
                    actions
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "tram.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("RAIL ENGINEER · LIVE TRACKING")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            HStack {
                Text(detail?.shipmentNumber ?? "RAIL-…")
                    .font(.system(size: 26, weight: .heavy)).monospaced()
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                StatusPill(
                    text: (detail?.status ?? "in_transit").replacingOccurrences(of: "_", with: " ").uppercased(),
                    kind: .info
                )
            }
            if let d = detail {
                let car = (d.carType ?? "car").replacingOccurrences(of: "_", with: " ")
                let n   = d.numberOfCars ?? 1
                Text("\(originLabel) → \(destLabel) · \(n) \(car)\(n == 1 ? "" : "s")")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            IridescentHairline()
        }
    }

    // MARK: Route map

    private var routeArcCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ROUTE · CLASS I AEI LIVE POSITION")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint, lineWidth: 1)
                    )
                if hasMapGeo {
                    railLiveMap
                } else {
                    railLocationPending
                }
                // Overlay chips + labels
                VStack(alignment: .leading) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(liveCarPoint != nil ? Brand.success : palette.textTertiary)
                                .frame(width: 7, height: 7)
                            Text(liveCarPoint != nil ? "OBSERVED · \(currentPositionLabel)" : "LOCATION PENDING")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(palette.textPrimary)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(palette.bgCardSoft))
                        Spacer()
                        if let eta = liveData?.eta {
                            Text("ETA \(eta)")
                                .font(.system(size: 10, weight: .bold)).monospacedDigit()
                                .foregroundStyle(palette.textPrimary)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(palette.bgCardSoft))
                        }
                    }
                    Spacer()
                    HStack {
                        Text(originLabel).font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textSecondary)
                        Spacer()
                        Text(destLabel).font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textSecondary)
                    }
                }
                .padding(14)
            }
            .frame(height: 160)
        }
    }

    private var railLocationPending: some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "location.slash")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("Awaiting a verified rail location")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text("The live map will appear when the next location is reported.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// In-house HERE map of the exact EusoRail route plus separate AEI/CLM
    /// observation evidence. A scan chain never becomes track geometry.
    private var railLiveMap: some View {
        let trail = liveTrailPoints
        let car = liveCarPoint
        // Route line = trail, with the live car appended as the leading edge.
        var line = trail
        if let car, line.last != car { line.append(car) }
        let center = car ?? trail.last ?? canonicalRouteLines.lazy.compactMap(\.first).first
            ?? HereLatLng(39.5, -98.35)
        var markers: [HereMarker] = trail.map { HereMarker(at: $0, kind: .stop) }
        if let car {
            markers.append(HereMarker(
                at: car,
                kind: .rail,
                label: currentPositionLabel,
                observationState: .degraded,
                sourceLabel: "Rail event feed",
                accessibilityLabel: "Rail consist at \(currentPositionLabel); freshness not classified"
            ))
        }
        var layers: [HereMapLayer] = canonicalRouteLines.enumerated().map { index, routeLine in
            .eusoRoute(
                polyline: routeLine,
                state: .active,
                label: index == 0
                    ? "Eusorone rail route plan version \(canonicalRouteVersion ?? 0)"
                    : nil
            )
        }
        if line.count >= 2 {
            layers.append(.observationTrail(points: line, label: "AEI position history"))
        }
        layers.append(.markers(markers))
        return HereVectorMapView(
            center: center,
            zoom: trail.count >= 2 || car != nil ? 6 : 9,
            interactive: true,
            tilt: 0,
            layers: layers,
            activeJob: true,
            mapModeContext: .primary(.rail),
            liveOperationsStatus: .init(
                availability: car == nil ? .empty : .degraded,
                sourceLabel: "Rail event feed",
                detail: car == nil
                    ? "No authorized live feed"
                    : "Observation available; freshness not classified",
                observationCount: car == nil ? 0 : 1
            )
        )
        .overlay(alignment: .bottomLeading) {
            if let canonicalRouteStatus {
                Text(canonicalRouteStatus)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(palette.bgCard.opacity(0.92))
                    .overlay(Capsule().strokeBorder(Brand.warning.opacity(0.45)))
                    .clipShape(Capsule())
                    .padding(8)
                    .accessibilityLabel(canonicalRouteStatus)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: KPI Strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            let speedVal = liveData?.speed.map { "\(Int($0)) mph" } ?? "- mph"
            let etaVal   = liveData?.eta ?? "-"
            let dwellVal = liveData?.dwellRisk ?? "-"
            let dwellColor: Color = {
                switch dwellVal.lowercased() {
                case "low":  return Brand.success
                case "high": return Brand.danger
                default:     return Brand.warning
                }
            }()
            MetricTile(label: "SPEED", value: speedVal)
            MetricTile(label: "ETA DEST", value: etaVal, gradientNumeral: true)
            MetricTile(label: "DWELL RISK", value: dwellVal, accent: dwellVal == "-" ? nil : dwellColor)
        }
    }

    // MARK: Events

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("EVENTS · live tracking")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if let count = tracking?.events.count {
                    Text("\(count)").font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            }
            LifecycleCard {
                let events = tracking?.events ?? []
                if events.isEmpty {
                    Text("No tracking events recorded.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(events.enumerated()), id: \.element.id) { idx, e in
                            eventRow(e)
                            if idx < events.count - 1 {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                }
            }
        }
    }

    private func eventRow(_ e: RailEvent560) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Brand.info.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: iconFor(e.eventType))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(e.eventType.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                if let desc = e.description, !desc.isEmpty {
                    Text(desc).font(.system(size: 11)).foregroundStyle(palette.textSecondary).lineLimit(2)
                }
                if let loc = e.location?.description {
                    Text(loc)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer()
            if let ts = e.timestamp {
                Text(shortDate(ts))
                    .font(.system(size: 11, weight: .medium)).monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(14)
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: Space.s2) {
            RailSecondaryActionButton(
                title: "Share context",
                sheetTitle: "Live tracking share context",
                lines: trackingShareLines,
                fillWidth: true,
                systemImage: "square.and.arrow.up"
            )
            RailSecondaryActionButton(
                title: "Waybill",
                sheetTitle: "Waybill context",
                lines: waybillContextLines,
                fillWidth: true,
                systemImage: "doc.text"
            )
        }
    }

    private var trackingShareLines: [String] {
        [
            "\(detail?.shipmentNumber ?? "Shipment") · \(originLabel) → \(destLabel)",
            "Current \(currentPositionLabel) · canonical route progress pending server projection",
            "Live geo \(liveCarPoint != nil ? "available" : "pending") · events \(tracking?.events.count ?? 0)"
        ]
    }

    private var waybillContextLines: [String] {
        [
            "Waybill \(detail?.waybillNumber ?? "-") · status \(detail?.status ?? "pending")",
            "\(detail?.numberOfCars ?? 0) car\(detail?.numberOfCars == 1 ? "" : "s") · \(detail?.carType ?? "car type pending")",
            "\(detail?.commodity ?? "commodity pending") · \(detail?.hazmatClass ?? "non-hazmat")"
        ]
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        await refreshCanonicalRoute()
        struct DetailIn: Encodable { let id: Int }
        struct TrackIn: Encodable { let shipmentId: Int }
        do {
            let d: RailShipmentDetail560 = try await EusoTripAPI.shared.query(
                "railShipments.getRailShipmentDetail", input: DetailIn(id: shipmentId))
            self.detail = d

            let t: RailTracking560 = try await EusoTripAPI.shared.query(
                "railShipments.getRailTracking", input: TrackIn(shipmentId: shipmentId))
            self.tracking = t

            // Best-effort external Class I AEI feed — non-blocking
            if let railroad = d.originRailroad, let wbn = d.waybillNumber {
                struct LiveIn: Encodable { let railroad: String; let shipmentId: String }
                self.liveData = try? await EusoTripAPI.shared.query(
                    "railShipments.liveTrackShipment",
                    input: LiveIn(railroad: railroad, shipmentId: wbn))
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    @MainActor
    private func refreshCanonicalRoute() async {
        canonicalRouteLines = []
        canonicalRouteStatus = nil
        canonicalRouteVersion = nil
        do {
            let result = try await CanonicalRoutePlanClient.shared.planRailShipment(
                id: shipmentId,
                purpose: .activeJob
            )
            switch result {
            case .persisted(let persisted):
                applyCanonicalRoute(persisted.route)
            case .pending(let pending):
                canonicalRouteStatus = pending.blockers.first?.message
                    ?? "EusoRail route pending verified graph authority"
                await readExistingCanonicalRoute()
            }
        } catch {
            canonicalRouteStatus = error.eusoUserCopy
            await readExistingCanonicalRoute()
        }
    }

    @MainActor
    private func readExistingCanonicalRoute() async {
        do {
            applyCanonicalRoute(
                try await CanonicalRoutePlanClient.shared.getBoundRailShipment(id: shipmentId)
            )
        } catch {
            if canonicalRouteStatus == nil { canonicalRouteStatus = error.eusoUserCopy }
        }
    }

    @MainActor
    private func applyCanonicalRoute(_ route: CanonicalRoutePlanClient.BoundRoutePlan) {
        guard let payload = route.rendererPayload else {
            canonicalRouteLines = []
            canonicalRouteVersion = nil
            canonicalRouteStatus = "EusoRail route exists but is not released for rendering"
            return
        }
        canonicalRouteLines = payload.lines
        canonicalRouteVersion = payload.identity.version
        canonicalRouteStatus = nil
    }

    // MARK: Helpers

    private func iconFor(_ eventType: String) -> String {
        switch eventType.lowercased() {
        case "departure", "departed":         return "arrow.up.right.circle"
        case "arrival", "arrived":            return "flag.checkered"
        case "interchange", "at_interchange": return "arrow.triangle.2.circlepath"
        case "scan", "aei_scan":              return "barcode.viewfinder"
        case "hold", "on_hold",
             "derailment_hold":               return "pause.circle"
        case "exception", "hazmat_exception": return "exclamationmark.triangle"
        case "spotted":                       return "mappin.and.ellipse"
        case "unloading":                     return "arrow.down.to.line"
        default:                              return "circle"
        }
    }

    private func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var d = f.date(from: iso)
        if d == nil {
            f.formatOptions = [.withInternetDateTime]
            d = f.date(from: iso)
        }
        guard let date = d else { return String(iso.prefix(10)) }
        let out = DateFormatter()
        out.dateFormat = "MM/dd HH:mm"
        return out.string(from: date)
    }
}

#Preview("560 · Rail Live Tracking · Night") {
    RailLiveTrackingScreen(theme: Theme.dark, shipmentId: 1001)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("560 · Rail Live Tracking · Light") {
    RailLiveTrackingScreen(theme: Theme.light, shipmentId: 1001)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
