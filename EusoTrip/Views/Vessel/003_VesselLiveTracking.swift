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
//  Live position comes only from liveOperations.latestForAsset, whose server
//  boundary enforces tenant grants, provider licence/consent, evidence hashes,
//  freshness, and quality. Provider identity and limitations remain visible.
//  AIS observations never become voyage geometry or remaining distance.
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
    let etaUtc: String?
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
        // Origin / destination port coordinates when the aggregator joins the
        // `ports` row (decodeIfPresent — older payloads omit them and the map
        // falls back to the PortDirectory catalog, then the live AIS fix).
        let originLat: Double?
        let originLng: Double?
        let destinationLat: Double?
        let destinationLng: Double?
    }
    struct Vessel: Decodable {
        let name: String?
        let imoNumber: String?
        let status: String?
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
    /// The booking being tracked. An empty value means no route context was
    /// supplied and renders an honest error without issuing a request.
    var bookingNumber: String

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
    @State private var liveAsset: LiveOperationsClient.AssetResult? = nil
    @State private var liveAssetError: String? = nil
    @State private var pulse = false
    @StateObject private var nearbyVessels = LiveOperationsNearbyStore(mode: .vessel)

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
        .task(id: "fallback-nearby-\(vesselImo ?? "none")-\(fallbackMapCenter.lat)-\(fallbackMapCenter.lng)") {
            guard vesselImo == nil, !fallbackMapPoints.isEmpty else { return }
            await nearbyVessels.poll(
                around: fallbackMapCenter,
                radiusMeters: 200_000,
                limit: 150
            )
        }
        .eusoRefreshable { await load() }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    // MARK: Top bar (SVG y=72 eyebrow · y=116 mono display · y=138 subline · AIS dot)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Space.s3) {
                EusoTripEyebrow(verbatim: "VESSEL SHIPPER · LIVE TRACKING")
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

    /// Pulsing green only for current, operationally usable evidence. Delayed,
    /// stale, offline, conflicted, and unavailable states remain distinct.
    private var aisBadge: some View {
        let observation = liveAsset?.observation
        let live = observation?.markerState == .current && observation?.operationalUseAllowed == true
        let color: Color
        switch observation?.markerState {
        case .current: color = live ? Brand.success : Brand.warning
        case .degraded, .stale: color = Brand.warning
        case .offline: color = palette.textTertiary
        case nil: color = liveAssetError == nil ? palette.textTertiary : Brand.warning
        }
        let label: String
        if live { label = "AIS LIVE" }
        else if let observation { label = "AIS \(observation.freshnessState.rawValue.uppercased())" }
        else if liveAssetError != nil { label = "AIS DEGRADED" }
        else { label = "NO AUTHORIZED FIX" }
        return HStack(spacing: 6) {
            ZStack {
                Circle().fill(color).frame(width: 10, height: 10)
                if live {
                    Circle().fill(color.opacity(0.4)).frame(width: 10, height: 10)
                        .scaleEffect(pulse ? 2.2 : 1).opacity(pulse ? 0 : 0.4)
                }
            }
            Text(label)
                .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(observation?.accessibleEvidenceLabel ?? liveAsset?.coverage.statement ?? "No authorized vessel observation")
    }

    private var subline: String {
        var parts: [String] = []
        if let v = board?.vessel?.name { parts.append(v) }
        let n = board?.containerCount ?? 0
        if n > 0 { parts.append("\(n) cntr") }
        if let fix = lastFixLabel { parts.append("reported \(fix) UTC") }
        if parts.isEmpty { return "Eusorone Marine · awaiting first AIS fix" }
        return parts.joined(separator: " · ")
    }

    private var lastFixLabel: String? {
        guard let ts = liveAsset?.observation?.observedAt, let d = Self.parseDate(ts) else { return nil }
        return Self.hhmm.string(from: d)
    }

    // MARK: Live ocean map

    private var mapCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(Color(red: 0.039, green: 0.078, blue: 0.133)) // #0A1422 ocean
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(Brand.blue.opacity(0.06))

            if let o = originCoord, let d = destinationCoord, let imo = vesselImo {
                VesselOceanTrackMap(
                    imoNumber: imo,
                    vesselShipmentId: board?.booking?.id,
                    origin: o,
                    destination: d,
                    originLabel: originLabel,
                    destinationLabel: destinationLabel
                )
            } else if !fallbackMapPoints.isEmpty {
                HereVectorMapView(
                    center: fallbackMapCenter,
                    zoom: fallbackMapPoints.count >= 2 ? 4 : 7,
                    interactive: true,
                    tilt: 0,
                    layers: [.markers(fallbackMapMarkers + nearbyVessels.markers)],
                    styleHint: .ocean,
                    mapModeContext: .primary(.vessel),
                    liveOperationsStatus: liveOperationsStatus
                )
            } else {
                mapLocationUnavailable
            }
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(palette.borderFaint))
    }

    private var mapLocationUnavailable: some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "location.slash")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("Vessel location unavailable")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text("The live map will appear when verified port coordinates are available.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 48)
    }

    // MARK: Origin / destination / IMO resolution for the live ocean map

    /// Vessel IMO that keys the live AIS feed inside `VesselOceanTrackMap`.
    private var vesselImo: String? {
        guard let imo = board?.vessel?.imoNumber, !imo.isEmpty else { return nil }
        return imo
    }

    /// Origin coordinate: aggregator port join → PortDirectory catalog. A live
    /// vessel fix never replaces a missing origin.
    private var originCoord: HereLatLng? {
        if let coordinate = LatLongParser.validatedCoordinate(
            latitude: board?.booking?.originLat,
            longitude: board?.booking?.originLng
        ) {
            return HereLatLng(coordinate.latitude, coordinate.longitude)
        }
        if let code = board?.booking?.originUnlocode,
           let p = PortDirectory.find(unlocode: code),
           let coordinate = LatLongParser.validatedCoordinate(
               latitude: p.lat,
               longitude: p.lng
           ) {
            return HereLatLng(coordinate)
        }
        return nil
    }

    /// Destination coordinate: aggregator port join → PortDirectory catalog.
    /// (No AIS fallback here — that anchors origin; the dest must be authored.)
    private var destinationCoord: HereLatLng? {
        if let coordinate = LatLongParser.validatedCoordinate(
            latitude: board?.booking?.destinationLat,
            longitude: board?.booking?.destinationLng
        ) {
            return HereLatLng(coordinate.latitude, coordinate.longitude)
        }
        if let code = board?.booking?.destinationUnlocode,
           let p = PortDirectory.find(unlocode: code),
           let coordinate = LatLongParser.validatedCoordinate(
               latitude: p.lat,
               longitude: p.lng
           ) {
            return HereLatLng(coordinate)
        }
        return nil
    }

    /// Exact licensed Live Operations position, when currently renderable.
    private var livePositionCoord: HereLatLng? {
        liveAsset?.observation?.position.coordinate
    }

    private var fallbackMapPoints: [HereLatLng] {
        [originCoord, livePositionCoord, destinationCoord].compactMap { $0 }
    }

    private var fallbackMapCenter: HereLatLng {
        let points = fallbackMapPoints
        guard !points.isEmpty else { return HereLatLng(33.7, -118.2) }
        return HereLatLng(
            points.map(\.lat).reduce(0, +) / Double(points.count),
            points.map(\.lng).reduce(0, +) / Double(points.count)
        )
    }

    private var fallbackMapMarkers: [HereMarker] {
        var markers: [HereMarker] = []
        if let originCoord {
            markers.append(HereMarker(at: originCoord, kind: .pickup, label: originLabel))
        }
        if let destinationCoord {
            markers.append(HereMarker(at: destinationCoord, kind: .delivery, label: destinationLabel))
        }
        if let observation = liveAsset?.observation,
           let coordinate = observation.position.coordinate {
            markers.append(HereMarker(
                at: coordinate,
                kind: .vessel,
                label: board?.vessel?.name ?? "Vessel",
                observationState: observation.markerState,
                sourceLabel: observation.provider.id,
                accessibilityLabel: observation.accessibleEvidenceLabel
            ))
        }
        return markers
    }

    private var liveOperationsStatus: HereLiveOperationsStatus {
        if nearbyVessels.result != nil || nearbyVessels.errorMessage != nil {
            return nearbyVessels.status
        }
        guard let observation = liveAsset?.observation else {
            return .init(
                availability: liveAssetError == nil ? .empty : .degraded,
                sourceLabel: nil,
                freshnessLabel: nil,
                detail: liveAssetError ?? liveAsset?.coverage.statement ?? "No authorized vessel observation",
                observationCount: 0
            )
        }
        let availability: HereLiveOperationsStatus.Availability
        switch observation.markerState {
        case .current: availability = observation.operationalUseAllowed ? .live : .degraded
        case .stale: availability = .stale
        case .degraded: availability = .degraded
        case .offline: availability = .unavailable
        }
        return .init(
            availability: availability,
            sourceLabel: observation.provider.id,
            freshnessLabel: observation.freshnessState.rawValue,
            detail: observation.provider.limitationsStatement,
            observationCount: 1
        )
    }

    // MARK: ETA + evidence strip

    private var etaStrip: some View {
        HStack(spacing: Space.s3) {
            metricBox("ETA · \(destinationShort)", etaLabel, accent: true)
            metricBox("LIVE EVIDENCE", liveEvidenceLabel, accent: false)
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
        guard let ts = board?.etaUtc, let d = Self.iso.date(from: ts) else { return "-" }
        return Self.etaFmt.string(from: d)
    }

    private var liveEvidenceLabel: String {
        guard let observation = liveAsset?.observation else {
            return liveAssetError == nil ? "NO AUTHORIZED FIX" : "DEGRADED"
        }
        return "\(observation.freshnessState.rawValue.uppercased()) · \(observation.quality.state.rawValue.replacingOccurrences(of: "_", with: " ").uppercased())"
    }

    private func eventLabel(_ e: OceanTrackBoard.TrackEvent) -> String {
        if let d = e.description, !d.isEmpty { return d }
        if let loc = e.location, !loc.isEmpty { return loc }
        return (e.eventType ?? "event").replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func eventTime(_ e: OceanTrackBoard.TrackEvent) -> String {
        guard let ts = e.timestamp, let d = Self.iso.date(from: ts) else { return "-" }
        // today → HH:mm, else MM-dd
        if Calendar.current.isDateInToday(d) { return Self.hhmm.string(from: d) }
        return Self.mmdd.string(from: d)
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
        loading = true; loadError = nil; liveAssetError = nil
        let cleaned = bookingNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            board = nil
            loading = false
            NotificationCenter.default.post(
                name: .eusoVesselShipperNavSwap,
                object: nil,
                userInfo: ["screenId": "Vesl012"]
            )
            return
        }
        struct BoardIn: Encodable { let bookingNumber: String }
        do {
            let b: OceanTrackBoard = try await EusoTripAPI.shared.query(
                "vesselShipments.getOceanTrackingBoard",
                input: BoardIn(bookingNumber: cleaned))
            guard b.found else {
                self.board = nil
                loading = false
                NotificationCenter.default.post(
                    name: .eusoVesselShipperNavSwap,
                    object: nil,
                    userInfo: ["screenId": "Vesl012"]
                )
                return
            }
            self.board = b
            if let imo = b.vessel?.imoNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
               !imo.isEmpty {
                do {
                    liveAsset = try await LiveOperationsClient.shared.latestVessel(imoNumber: imo)
                } catch {
                    liveAsset = nil
                    liveAssetError = error.eusoUserCopy
                }
            } else {
                liveAsset = nil
            }
        } catch {
            loadError = error.eusoUserCopy
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
            actionError = "Per-container positions unavailable. "
                + (error.eusoUserCopy)
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
    private static func parseDate(_ raw: String) -> Date? {
        if let date = iso.date(from: raw) { return date }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: raw)
    }
}

#Preview("003 · Vessel Live Tracking · Night") {
    VesselLiveTrackingScreen(theme: Theme.dark, bookingNumber: "PREVIEW").preferredColorScheme(.dark)
}
#Preview("003 · Vessel Live Tracking · Light") {
    VesselLiveTrackingScreen(theme: Theme.light, bookingNumber: "PREVIEW").preferredColorScheme(.light)
}
