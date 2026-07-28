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
    /// Feeds the AEI-fix route interpolation so the arc stops parking
    /// at a milestone bucket for a thousand miles.
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
    @State private var loading = true
    @State private var loadError: String? = nil

    // MARK: - Live AEI geometry (real coords only)

    /// The live car fix from the AEI tracking chain. nil unless the server
    /// returned a real, non-null-island coordinate — we never plot (0,0).
    private var liveCarPoint: HereLatLng? {
        guard let c = tracking?.currentLocation,
              let la = c.lat, let lo = c.lng,
              !(la == 0 && lo == 0) else { return nil }
        return HereLatLng(la, lo)
    }

    /// The scan trail: every tracking event that carries a real lat/lng,
    /// in chronological order (oldest→newest). Null-island scans dropped.
    private var liveTrailPoints: [HereLatLng] {
        (tracking?.events ?? [])
            .compactMap { e -> (String, HereLatLng)? in
                guard let la = e.location?.lat, let lo = e.location?.lng,
                      !(la == 0 && lo == 0) else { return nil }
                return (e.timestamp ?? "", HereLatLng(la, lo))
            }
            .sorted { $0.0 < $1.0 }
            .map { $0.1 }
    }

    /// True when the AEI chain has at least one real coordinate to plot.
    private var hasLiveGeo: Bool { liveCarPoint != nil || !liveTrailPoints.isEmpty }

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

    /// Real journey progress (0…1) — origin yard → destination yard.
    ///
    /// Strongest signal (Wave B, 2026-06-10) is REAL geometry: when the
    /// latest AEI fix carries coordinates AND both yards resolve real
    /// catalog anchors, the fraction is interpolated by route distance
    /// (origin→fix over origin→fix→destination) — the arc rides the
    /// actual scan position instead of parking at a 0.50 milestone
    /// bucket for a thousand miles. The event-chain milestone ladder is
    /// the fallback when geometry is incomplete; the status ladder is
    /// the floor when the event feed is empty. Never a hardcoded
    /// position.
    private var journeyProgress: Double {
        // 0) Route-distance interpolation off the latest real AEI fix.
        if let f = interpolatedRouteFraction { return f }
        // 1) Event-chain milestone — pick the furthest-along event type seen.
        if let events = tracking?.events, !events.isEmpty {
            var best = 0.04 // booked but tracked
            for e in events {
                let t = e.eventType.lowercased()
                let v: Double
                switch t {
                case "arrival", "arrived",
                     "spotted", "unloading", "delivered":      v = 1.0
                case "interchange", "at_interchange":          v = 0.62
                case "scan", "aei_scan":                       v = 0.50
                case "departure", "departed":                  v = 0.14
                case "hold", "on_hold", "derailment_hold",
                     "exception", "hazmat_exception":          v = max(best, 0.30) // holds don't rewind
                default:                                       v = best
                }
                best = max(best, v)
            }
            return min(max(best, 0), 1)
        }
        // 2) Status fallback when the event feed is empty — the full
        //    rail consist FSM (updateRailShipmentStatus transitions),
        //    each stage at its honest fraction.
        switch (detail?.status ?? "").lowercased() {
        case "delivered", "completed", "arrived", "unloaded",
             "empty_returned", "invoiced", "settled":          return 1.0
        case "unloading":                                      return 0.95
        case "spotted", "at_destination":                      return 0.9
        case "in_yard":                                        return 0.8
        case "in_transit", "in-transit", "enroute", "en_route": return 0.5
        case "interchange", "at_interchange", "interchange_delay": return 0.62
        case "departed", "released":                           return 0.14
        case "in_consist":                                     return 0.10
        case "pending", "scheduled", "booked", "requested",
             "car_ordered", "car_placed", "loading", "loaded": return 0.04
        case "on_hold", "derailment_hold", "hazmat_exception",
             "cancelled":                                      return 0.04
        default:
            // Zero-fallback doctrine: an unmapped consist status must
            // not fabricate a mid-route arc. DEBUG-loud, honest
            // origin-side floor in release (the 003 pattern).
            assertionFailure("RailLiveTracking.journeyProgress: unmapped consist status '\(detail?.status ?? "nil")' — add it to the ramp")
            return 0.04
        }
    }

    /// Latest position fix with real coordinates — the live AEI fix
    /// first, then the newest tracking event that carries a location.
    private var latestFix560: (lat: Double, lng: Double)? {
        if let c = tracking?.currentLocation,
           let la = c.lat, let ln = c.lng, !(la == 0 && ln == 0) {
            return (la, ln)
        }
        let dated = (tracking?.events ?? []).compactMap { e -> (String, Double, Double)? in
            guard let l = e.location, let la = l.lat, let ln = l.lng,
                  !(la == 0 && ln == 0) else { return nil }
            return (e.timestamp ?? "", la, ln)
        }
        // ISO-8601 strings sort lexicographically — newest fix wins.
        guard let newest = dated.max(by: { $0.0 < $1.0 }) else { return nil }
        return (newest.1, newest.2)
    }

    /// Route-distance fraction between the REAL yard anchors. nil when
    /// either yard lacks catalog coordinates or no fix exists — the
    /// milestone/status ladders then take over (honest degradation).
    private var interpolatedRouteFraction: Double? {
        guard let o = detail?.originYard?.coordinates,
              let d = detail?.destinationYard?.coordinates,
              let ola = o.lat, let oln = o.lng,
              let dla = d.lat, let dln = d.lng,
              !(ola == 0 && oln == 0), !(dla == 0 && dln == 0),
              let fix = latestFix560 else { return nil }
        let toFix  = Self.haversineMi(ola, oln, fix.lat, fix.lng)
        let toDest = Self.haversineMi(fix.lat, fix.lng, dla, dln)
        let total = toFix + toDest
        guard total > 0.5 else { return nil }   // co-located anchors — no geometry
        // Clamp inside the pins so the marker never overpaints a yard
        // node it hasn't actually reached/left.
        return min(max(toFix / total, 0.02), 0.98)
    }

    private static func haversineMi(_ lat1: Double, _ lng1: Double,
                                    _ lat2: Double, _ lng2: Double) -> Double {
        let r = 3958.8
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
            * sin(dLng / 2) * sin(dLng / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

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
        .refreshable { await load() }
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
                if hasLiveGeo {
                    railLiveMap
                } else {
                    railLocationPending
                }
                // Overlay chips + labels
                VStack(alignment: .leading) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(hasLiveGeo ? Brand.success : palette.textTertiary)
                                .frame(width: 7, height: 7)
                            Text(hasLiveGeo ? "LIVE · \(currentPositionLabel)" : "LOCATION PENDING")
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

    /// In-house HERE map of the live AEI position. The scan trail (events with
    /// real coords) draws as the route line; the live car fix is the truck
    /// puck. Built only when `hasLiveGeo` — every coordinate is server-real
    /// and null-island guarded upstream, so nothing is ever fabricated.
    private var railLiveMap: some View {
        let trail = liveTrailPoints
        let car = liveCarPoint
        // Route line = trail, with the live car appended as the leading edge.
        var line = trail
        if let car, line.last != car { line.append(car) }
        let center = car ?? trail.last ?? HereLatLng(39.5, -98.35)
        var markers: [HereMarker] = trail.map { HereMarker(at: $0, kind: .stop) }
        if let car { markers.append(HereMarker(at: car, kind: .truck, label: currentPositionLabel)) }
        var layers: [HereMapLayer] = []
        if line.count >= 2 { layers.append(.route(polyline: line, colorHex: "#1473FF")) }
        layers.append(.markers(markers))
        return HereVectorMapView(
            center: center,
            zoom: trail.count >= 2 || car != nil ? 6 : 9,
            interactive: true,
            tilt: 0,
            layers: layers
        )
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
            "Current \(currentPositionLabel) · progress \(Int((journeyProgress * 100).rounded()))%",
            "Live geo \(hasLiveGeo ? "available" : "pending") · events \(tracking?.events.count ?? 0)"
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
