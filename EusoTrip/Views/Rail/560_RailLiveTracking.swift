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

    /// Real journey progress (0…1) — origin yard → destination yard.
    ///
    /// Strongest signal is the tracking event chain: a departure scan marks the
    /// shipment off-origin, intermediate AEI scans / interchanges advance it, and
    /// an arrival/spotting marks it on-destination. We map the most-advanced
    /// milestone seen to a fraction. When no events are present yet we fall back
    /// to the shipment status. This is what the completed gradient arc and the
    /// dashed-remaining continuation are bound to — never a hardcoded position.
    private var journeyProgress: Double {
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
        // 2) Status fallback when the event feed is empty.
        switch (detail?.status ?? "").lowercased() {
        case "delivered", "completed", "arrived", "unloaded": return 1.0
        case "in_transit", "in-transit", "enroute", "en_route": return 0.5
        case "spotted", "at_destination":                     return 0.9
        case "interchange":                                   return 0.62
        case "departed", "released":                          return 0.14
        case "pending", "scheduled", "booked":                return 0.04
        default:                                              return 0.45
        }
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

    // MARK: Route Arc Card — completed gradient arc + dashed continuation,
    // bound to real journeyProgress (origin → live position → destination).

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
                RouteArc560(progress: journeyProgress, palette: palette)
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

// MARK: - Route Arc (completed gradient + dashed continuation), AAA

/// The route canvas: one continuous bezier from the origin pin to the
/// destination pin. The completed portion (origin → live position) is drawn as a
/// solid brand-gradient stroke trimmed to the **real** `progress` fraction; the
/// remaining portion (live position → destination) is a dashed continuation.
/// The live marker sits exactly on the path at the progress boundary.
///
/// Motion:
///   • Completed arc draws on with a decelerating spring on appear / on data
///     change (transform-free, GPU-friendly trim animation).
///   • Dashed remainder marches continuously and LINEARLY (a true loop — the
///     correct case for linear), seamless via a phase that wraps the dash period.
///   • The live marker's halo breathes gently (ambient ease-in-out loop).
///   • Reduce-motion: final static state — arc fully drawn to `progress`, no
///     march, no breathing.
private struct RouteArc560: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Real origin→destination fraction (0…1) from the data model.
    let progress: Double
    let palette: Theme.Palette

    /// The fraction the completed arc currently animates toward; starts at 0 so
    /// the route draws on from the origin into its true live position.
    @State private var shown: Double = 0
    /// Continuous marching-ants phase for the dashed remainder.
    @State private var march = false
    /// Ambient halo breathing.
    @State private var breathing = false

    // Dash geometry — pattern period drives the seamless march distance.
    private let dash: [CGFloat] = [4, 5]
    private var dashPeriod: CGFloat { dash.reduce(0, +) } // 9pt — one full cycle

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            // Anchor points in canvas space.
            let origin = CGPoint(x: 0.10 * w, y: 0.78 * h)
            let dest   = CGPoint(x: 0.90 * w, y: 0.58 * h)
            // Single continuous route path origin → destination.
            let route = Path { p in
                p.move(to: origin)
                p.addCurve(to: dest,
                           control1: CGPoint(x: 0.34 * w, y: 0.34 * h),
                           control2: CGPoint(x: 0.66 * w, y: 0.36 * h))
            }
            // Exact live-marker point on the path at the current shown fraction.
            let livePoint = pointOnPath(route, at: shown) ?? origin

            ZStack(alignment: .topLeading) {
                // Dashed remainder: live position → destination (the "to go").
                route
                    .trim(from: shown, to: 1)
                    .stroke(palette.textTertiary.opacity(0.5),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round,
                                               dash: dash,
                                               dashPhase: march ? -dashPeriod : 0))

                // Completed segment: origin → live position, real progress.
                route
                    .trim(from: 0, to: shown)
                    .stroke(LinearGradient.primary,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))

                // Origin pin (filled — departed).
                Circle().fill(LinearGradient.diagonal)
                    .frame(width: 11, height: 11)
                    .position(origin)

                // Destination pin (hollow — pending arrival).
                Circle().strokeBorder(palette.textTertiary, lineWidth: 2)
                    .frame(width: 11, height: 11)
                    .position(dest)

                // Live position — breathing halo + filled dot, on the real point.
                Circle().fill(LinearGradient.diagonal)
                    .opacity(breathing ? 0.30 : 0.16)
                    .frame(width: breathing ? 26 : 20, height: breathing ? 26 : 20)
                    .position(livePoint)
                Circle().fill(LinearGradient.diagonal)
                    .frame(width: 12, height: 12)
                    .position(livePoint)
            }
        }
        .onAppear { settle(); startLoops() }
        .onChange(of: progress) { _, _ in settle() }
        .onChange(of: reduceMotion) { _, _ in settle(); startLoops() }
    }

    /// Settle the completed arc to its real fraction.
    private func settle() {
        if reduceMotion {
            shown = progress
            return
        }
        // Decelerating spring — the route draws on into its true live position.
        withAnimation(.spring(response: 0.70, dampingFraction: 0.85)) {
            shown = progress
        }
    }

    /// Start (or stop) the continuous ambient loops.
    private func startLoops() {
        guard !reduceMotion else {
            march = false
            breathing = false
            return
        }
        // Marching ants — continuous, linear, seamless (wraps one dash period).
        march = false
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
            march = true
        }
        // Ambient halo breathing — gentle ease-in-out, autoreverses.
        breathing = false
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            breathing = true
        }
    }

    /// Exact point on `path` at fraction `t` (0…1) using a trimmed sub-path.
    private func pointOnPath(_ path: Path, at t: Double) -> CGPoint? {
        let clamped = min(max(t, 0.0001), 1)
        return path.trimmedPath(from: 0, to: CGFloat(clamped)).currentPoint
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
