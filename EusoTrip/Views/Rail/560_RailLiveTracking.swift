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

    private var originLabel: String {
        guard let y = detail?.originYard else { return "—" }
        return [y.code, y.city].compactMap { $0 }.joined(separator: " · ")
    }
    private var destLabel: String {
        guard let y = detail?.destinationYard else { return "—" }
        return [y.code, y.city].compactMap { $0 }.joined(separator: " · ")
    }
    private var currentPositionLabel: String {
        tracking?.currentLocation?.description
            ?? liveData?.currentLocation
            ?? "En route"
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
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
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

    // MARK: Route Arc Card (stylised canvas — real coords pending liveTrackShipment feed)

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
                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    ZStack(alignment: .topLeading) {
                        // Solid gradient arc: origin → live marker
                        Path { p in
                            p.move(to: CGPoint(x: 0.10*w, y: 0.78*h))
                            p.addCurve(to: CGPoint(x: 0.52*w, y: 0.40*h),
                                       control1: CGPoint(x: 0.26*w, y: 0.50*h),
                                       control2: CGPoint(x: 0.40*w, y: 0.41*h))
                        }
                        .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))

                        // Dashed arc: live marker → destination
                        Path { p in
                            p.move(to: CGPoint(x: 0.52*w, y: 0.40*h))
                            p.addCurve(to: CGPoint(x: 0.90*w, y: 0.58*h),
                                       control1: CGPoint(x: 0.67*w, y: 0.39*h),
                                       control2: CGPoint(x: 0.82*w, y: 0.44*h))
                        }
                        .stroke(palette.textTertiary.opacity(0.5),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 5]))

                        // Origin pin
                        Circle().fill(LinearGradient.diagonal)
                            .frame(width: 11, height: 11)
                            .position(x: 0.10*w, y: 0.78*h)

                        // Destination pin
                        Circle().strokeBorder(palette.textTertiary, lineWidth: 2)
                            .frame(width: 11, height: 11)
                            .position(x: 0.90*w, y: 0.58*h)

                        // Live position — halo + filled dot
                        Circle().fill(LinearGradient.diagonal).opacity(0.18)
                            .frame(width: 22, height: 22)
                            .position(x: 0.52*w, y: 0.40*h)
                        Circle().fill(LinearGradient.diagonal)
                            .frame(width: 12, height: 12)
                            .position(x: 0.52*w, y: 0.40*h)
                    }
                }
                // Overlay chips + labels
                VStack(alignment: .leading) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(Brand.success).frame(width: 7, height: 7)
                            Text("LIVE · \(currentPositionLabel)")
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

    // MARK: KPI Strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            let speedVal = liveData?.speed.map { "\(Int($0)) mph" } ?? "— mph"
            let etaVal   = liveData?.eta ?? "—"
            let dwellVal = liveData?.dwellRisk ?? "—"
            let dwellColor: Color = {
                switch dwellVal.lowercased() {
                case "low":  return Brand.success
                case "high": return Brand.danger
                default:     return Brand.warning
                }
            }()
            MetricTile(label: "SPEED", value: speedVal)
            MetricTile(label: "ETA DEST", value: etaVal, gradientNumeral: true)
            MetricTile(label: "DWELL RISK", value: dwellVal, accent: dwellVal == "—" ? nil : dwellColor)
        }
    }

    // MARK: Events

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("EVENTS · getRailTracking")
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
            CTAButton(title: "Share tracking", action: {}, leadingIcon: "square.and.arrow.up")
            CTAButton(title: "Waybill", leadingIcon: "doc.text")
        }
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
        var f = ISO8601DateFormatter()
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
