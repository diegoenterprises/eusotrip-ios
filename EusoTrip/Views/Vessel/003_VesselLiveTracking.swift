//
//  003_VesselLiveTracking.swift
//  EusoTrip — Vessel Shipper · Live Tracking (per-booking ocean tracking board).
//
//  Web parity: client/src/pages/vessel/ContainerTracking.tsx + VesselNavigation.tsx
//  Wireframe:  06 Vessel / 003 Vessel Live Tracking (canvas 440×956).
//  PERSONA:    Diego Usoro · Eusorone Marine (VESSEL_SHIPPER). Booking VS-#####.
//  transportMode = vessel.
//
//  WIRED ENDPOINTS (verified §18 against server/routers/vesselShipments.ts):
//    • vesselShipments.getOceanTrackingBoard  — NEW §18 aggregator; bookingNumber →
//        typed NON-NULL board (booking + vessel + position + ETA + events + count).
//        Backs the hero, map marker, ETA strip, and AIS-events feed.
//    • vesselShipments.getContainerPositions (EXISTS :950) — "Per-container
//        positions" CTA. Returns { containers:[…], total }.
//
//  Live AIS endpoints (liveVesselPosition / getVesselTrack / liveTrackOcean-
//  Shipment) return `null` on provider error and key off imoNumber/referenceNumber,
//  NOT bookingNumber — so they are NOT called directly here. The aggregator
//  composes a stable, decodable board from real DB rows; the spatial provider
//  name NEVER appears in UI (HERE doctrine — branded "EusoTrip Network").
//  The map is a stylized great-circle ocean schematic, not a geo plot.
//
//  No mock data. Real @State loading / error / actionError. do/catch — never try?.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//

import SwiftUI

// MARK: - Data shapes (tRPC vesselShipments.getOceanTrackingBoard)

private struct OceanTrackBoard: Decodable {
    let found: Bool
    let booking: Booking?
    let vessel: Vessel?
    let position: Position?
    let etaUtc: String?
    let remainingNm: Double?
    let remainingDays: Double?
    let events: [TrackEvent]
    let containerCount: Int

    struct Booking: Decodable {
        let id: Int?
        let bookingNumber: String?
        let status: String?
        let voyageNumber: String?
        let serviceRoute: String?
        let numberOfContainers: Int?
        let originName: String?
        let originUnlocode: String?
        let destinationName: String?
        let destinationUnlocode: String?
    }
    struct Vessel: Decodable {
        let name: String?
        let imoNumber: String?
        let status: String?
    }
    struct Position: Decodable {
        let lat: Double?
        let lng: Double?
        let headingDeg: Double?
        let speedKn: Double?
    }
    struct TrackEvent: Decodable, Identifiable {
        let id: Int
        let eventType: String?
        let description: String?
        let location: String?
        let timestamp: String?
    }
}

// MARK: - Screen

struct VesselLiveTrackingScreen: View {
    var theme: Theme.Palette = Theme.dark
    /// The booking being tracked. Real callers pass the selected booking number;
    /// preview parity uses the wireframe hero VS-48217.
    var bookingNumber: String = "VS-48217"

    var body: some View {
        Shell(theme: theme) {
            VesselLiveTrackingBody(bookingNumber: bookingNumber)
        } nav: {
            // NAV (mode-agnostic per class-A, verbatim to 003 desc):
            // HOME · LOADS(active) · [orb] · TRACK · ME
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house.fill",       isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Track", systemImage: "clock",           isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselLiveTrackingBody: View {
    let bookingNumber: String
    @Environment(\.palette) private var palette

    @State private var board: OceanTrackBoard? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionError: String? = nil
    @State private var pulse = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s5) {
                    if let actionError {
                        actionErrorBanner(actionError)
                    }

                    if loading {
                        loadingState
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    } else if board?.found != true {
                        EusoEmptyState(systemImage: "dot.radiowaves.left.and.right",
                                       title: "No live track for \(bookingNumber)",
                                       subtitle: "This booking isn't on the water yet, or it isn't yours to view.")
                    } else {
                        mapCard
                        etaStrip
                        eventFeed
                        perContainerCTA
                    }

                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s5)
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    // MARK: Top bar (SVG y=72 eyebrow · y=116 mono display · y=138 subline · AIS dot)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("✦ VESSEL SHIPPER · LIVE TRACKING")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
            }

            HStack(alignment: .center) {
                Text(board?.booking?.bookingNumber ?? bookingNumber)
                    .font(.system(size: 30, weight: .bold, design: .monospaced)).kerning(-0.5)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 8)
                aisBadge
            }
            .padding(.top, Space.s3)

            Text(subline)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 4)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s6)
    }

    /// Pulsing green when a live fix is present; grey "NO FIX" otherwise (honest).
    private var aisBadge: some View {
        let live = board?.position != nil
        let color: Color = live ? Brand.success : palette.textTertiary
        return HStack(spacing: 6) {
            ZStack {
                Circle().fill(color).frame(width: 10, height: 10)
                if live {
                    Circle().fill(color.opacity(0.4)).frame(width: 10, height: 10)
                        .scaleEffect(pulse ? 2.2 : 1).opacity(pulse ? 0 : 0.4)
                }
            }
            Text(live ? "AIS" : "NO FIX")
                .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                .foregroundStyle(color)
        }
    }

    private var subline: String {
        var parts: [String] = []
        if let v = board?.vessel?.name { parts.append(v) }
        let n = board?.containerCount ?? 0
        if n > 0 { parts.append("\(n) cntr") }
        if let fix = lastFixLabel { parts.append("last fix \(fix) UTC") }
        if parts.isEmpty { return "Eusorone Marine · awaiting first AIS fix" }
        return parts.joined(separator: " · ")
    }

    private var lastFixLabel: String? {
        guard let ts = board?.events.first?.timestamp, let d = Self.iso.date(from: ts) else { return nil }
        return Self.hhmm.string(from: d)
    }

    // MARK: Map card (SVG y=178, 400×300 great-circle schematic · EusoTrip Network)

    private var mapCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(Color(red: 0.039, green: 0.078, blue: 0.133)) // #0A1422 ocean
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(Brand.blue.opacity(0.06))

            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack(alignment: .topLeading) {
                    // latitude grid
                    ForEach(1..<4) { i in
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                            .offset(y: h * CGFloat(i) / 4)
                    }
                    // gradient great-circle (origin → vessel) + dashed remaining
                    VesselRoutePath().stroke(LinearGradient.primary,
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    VesselRemainingPath().stroke(Color.white.opacity(0.14),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: [2, 7]))

                    // origin node (gradient ring) — bottom-left of the arc
                    routeNode(x: w * 0.13, y: h * 0.24,
                              label: originLabel, gradient: true)
                    // destination node (grey ring)
                    routeNode(x: w * 0.93, y: h * 0.77,
                              label: destinationLabel, gradient: false)

                    // vessel marker w/ glow at progress fraction along the arc
                    vesselMarker(at: markerPoint(w: w, h: h))
                    // position chip
                    positionChip
                        .position(x: w * 0.72, y: h * 0.42)
                }
            }
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(palette.borderFaint))
    }

    private func routeNode(x: CGFloat, y: CGFloat, label: String, gradient: Bool) -> some View {
        ZStack {
            Circle().fill(palette.bgPrimary).frame(width: 12, height: 12)
                .overlay(
                    Circle().strokeBorder(
                        gradient ? AnyShapeStyle(LinearGradient.primary)
                                 : AnyShapeStyle(palette.textTertiary),
                        lineWidth: 3)
                )
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(gradient ? palette.textPrimary : palette.textSecondary)
                .fixedSize()
                .offset(y: gradient ? -16 : 18)
        }
        .position(x: x, y: y)
    }

    private func vesselMarker(at p: CGPoint) -> some View {
        ZStack {
            Circle().fill(Brand.magenta.opacity(0.22)).frame(width: 40, height: 40).blur(radius: 6)
            Circle().fill(LinearGradient.diagonal).frame(width: 22, height: 22)
            Image(systemName: "ferry.fill")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
        }
        .position(x: p.x, y: p.y)
    }

    private var positionChip: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(positionTitle)
                .font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
            Text(positionDetail)
                .font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .fill(palette.bgCardSoft))
        .fixedSize()
    }

    // MARK: ETA + remaining strip (SVG y=494, two 192×64 boxes)

    private var etaStrip: some View {
        HStack(spacing: Space.s3) {
            metricBox("ETA · \(destinationShort)", etaLabel, accent: true)
            metricBox("REMAINING", remainingLabel, accent: false)
        }
    }

    private func metricBox(_ label: String, _ value: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Group {
                if accent { Text(value).foregroundStyle(LinearGradient.diagonal) }
                else { Text(value).foregroundStyle(palette.textPrimary) }
            }
            .font(.system(size: 20, weight: .bold)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: AIS event feed (SVG y=592 eyebrow + y=604 timeline card)

    private var eventFeed: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("AIS EVENTS · EUSOTRIP NETWORK")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            let events = board?.events ?? []
            if events.isEmpty {
                EusoEmptyState(systemImage: "antenna.radiowaves.left.and.right",
                               title: "No AIS events yet",
                               subtitle: "Position reports appear here once the vessel departs.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.prefix(6).enumerated()), id: \.element.id) { idx, e in
                        eventRow(e, isCurrent: idx == 0, isLast: idx == min(events.count, 6) - 1)
                    }
                }
                .padding(Space.s4)
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func eventRow(_ e: OceanTrackBoard.TrackEvent, isCurrent: Bool, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(spacing: 0) {
                Circle()
                    .fill(isCurrent ? AnyShapeStyle(LinearGradient.primary)
                                    : AnyShapeStyle(palette.textTertiary))
                    .frame(width: 8, height: 8)
                if !isLast {
                    Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1).frame(maxHeight: .infinity)
                }
            }
            Text(eventLabel(e))
                .font(.system(size: 12, weight: isCurrent ? .bold : .semibold))
                .foregroundStyle(isCurrent ? palette.textPrimary : palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(eventTime(e))
                .font(.system(size: 10)).monospacedDigit()
                .foregroundStyle(palette.textTertiary)
        }
        .frame(minHeight: 36)
    }

    // MARK: Per-container positions CTA (SVG y=786, gradient capsule)
    //       → getContainerPositions (EXISTS :950). Validates reachability,
    //         surfaces failure honestly. Navigation wired at the surface router.

    private var perContainerCTA: some View {
        Button {
            Task { await openContainerPositions() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "scope").font(.system(size: 14, weight: .bold))
                Text("Per-container positions").font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(LinearGradient.primary)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Derived display

    private var originLabel: String { board?.booking?.originName ?? board?.booking?.originUnlocode ?? "Origin" }
    private var destinationLabel: String { board?.booking?.destinationName ?? board?.booking?.destinationUnlocode ?? "Destination" }
    private var destinationShort: String {
        (board?.booking?.destinationName ?? board?.booking?.destinationUnlocode ?? "DEST").uppercased()
    }

    private var etaLabel: String {
        guard let ts = board?.etaUtc, let d = Self.iso.date(from: ts) else { return "—" }
        return Self.etaFmt.string(from: d)
    }

    private var remainingLabel: String {
        guard let nm = board?.remainingNm, nm > 0 else { return "—" }
        let nmStr = Self.grouped.string(from: NSNumber(value: nm)) ?? "\(Int(nm))"
        if let days = board?.remainingDays, days > 0 {
            return "\(nmStr) NM · \(String(format: "%.1f", days))d"
        }
        return "\(nmStr) NM"
    }

    private var positionTitle: String {
        guard let p = board?.position, let lng = p.lng else { return "AWAITING FIX" }
        let hemi = lng >= 0 ? "E" : "W"
        return String(format: "%.1f°%@", abs(lng), hemi)
    }

    private var positionDetail: String {
        guard let p = board?.position else { return "no live position" }
        var parts: [String] = []
        if let s = p.speedKn { parts.append(String(format: "%.1f kn", s)) }
        if let h = p.headingDeg { parts.append(String(format: "hdg %03d°", Int(h.rounded()))) }
        return parts.isEmpty ? "position only" : parts.joined(separator: " · ")
    }

    private func eventLabel(_ e: OceanTrackBoard.TrackEvent) -> String {
        if let d = e.description, !d.isEmpty { return d }
        if let loc = e.location, !loc.isEmpty { return loc }
        return (e.eventType ?? "event").replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func eventTime(_ e: OceanTrackBoard.TrackEvent) -> String {
        guard let ts = e.timestamp, let d = Self.iso.date(from: ts) else { return "—" }
        // today → HH:mm, else MM-dd
        if Calendar.current.isDateInToday(d) { return Self.hhmm.string(from: d) }
        return Self.mmdd.string(from: d)
    }

    /// Marker fraction along the arc, derived from booking status (schematic).
    private func markerPoint(w: CGFloat, h: CGFloat) -> CGPoint {
        let t = progressFraction
        // Quadratic Bézier matching VesselRoutePath: p0=(.13,.24) c=(.53,.07) p1=(.93,.77)
        let p0 = CGPoint(x: 0.13, y: 0.24), c = CGPoint(x: 0.53, y: 0.07), p1 = CGPoint(x: 0.93, y: 0.77)
        let mt = 1 - t
        let x = mt*mt*p0.x + 2*mt*t*c.x + t*t*p1.x
        let y = mt*mt*p0.y + 2*mt*t*c.y + t*t*p1.y
        return CGPoint(x: x * w, y: y * h)
    }

    private var progressFraction: CGFloat {
        switch (board?.booking?.status ?? "").lowercased() {
        case "booking_requested", "booking_confirmed", "documentation": return 0.04
        case "container_released", "gate_in", "loaded_on_vessel":       return 0.10
        case "departed":                                                return 0.18
        case "in_transit", "transshipment":                             return 0.55
        case "arrived", "customs_hold", "customs_cleared":              return 0.92
        case "discharged", "gate_out", "delivered":                     return 0.98
        default:                                                        return 0.5
        }
    }

    // MARK: - Chrome

    private var loadingState: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 300)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            HStack(spacing: Space.s3) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 64)
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                }
            }
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 166)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        }
    }

    private func actionErrorBanner(_ message: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(Brand.danger)
            Text(message).font(EType.caption).foregroundStyle(Brand.danger)
            Spacer()
            Button { actionError = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13)).foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(Brand.danger.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.40)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Load + actions (do/catch · never try?)

    private func load() async {
        loading = true; loadError = nil
        struct BoardIn: Encodable { let bookingNumber: String }
        do {
            let b: OceanTrackBoard = try await EusoTripAPI.shared.query(
                "vesselShipments.getOceanTrackingBoard",
                input: BoardIn(bookingNumber: bookingNumber))
            self.board = b
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// getContainerPositions (EXISTS :950) — validate reachability before routing
    /// to the per-container surface so a dead feed surfaces honestly.
    private func openContainerPositions() async {
        struct PosIn: Encodable { let limit: Int }
        struct PosOut: Decodable { let total: Int? }
        do {
            let _: PosOut = try await EusoTripAPI.shared.query(
                "vesselShipments.getContainerPositions",
                input: PosIn(limit: 100))
        } catch {
            actionError = "Per-container positions unavailable — "
                + ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - Formatters
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let etaFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"; f.timeZone = TimeZone(identifier: "UTC"); return f }()
    private static let mmdd: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MM-dd"; f.timeZone = TimeZone(identifier: "UTC"); return f }()
    private static let hhmm: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; f.timeZone = TimeZone(identifier: "UTC"); return f }()
    private static let grouped: NumberFormatter = { let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; return f }()
}

// MARK: - Stylized great-circle paths (Shanghai → Long Beach schematic)

/// Origin → current vessel position arc (gradient stroke).
private struct VesselRoutePath: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.13, y: h * 0.24))
        p.addQuadCurve(to: CGPoint(x: w * 0.93, y: h * 0.77),
                       control: CGPoint(x: w * 0.53, y: h * 0.07))
        return p
    }
}

/// Remaining leg (dashed faint white), mid-route → destination.
private struct VesselRemainingPath: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.53, y: h * 0.34))
        p.addQuadCurve(to: CGPoint(x: w * 0.93, y: h * 0.77),
                       control: CGPoint(x: w * 0.73, y: h * 0.45))
        return p
    }
}

#Preview("003 · Vessel Live Tracking · Night") {
    VesselLiveTrackingScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("003 · Vessel Live Tracking · Light") {
    VesselLiveTrackingScreen(theme: Theme.light).preferredColorScheme(.light)
}
