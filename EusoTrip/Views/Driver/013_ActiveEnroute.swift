//
//  013_ActiveEnroute.swift
//  EusoTrip 2027 UI — Wave 7 (driver · lifecycle · en route to pickup)
//
//  Screen 013 · En Route to Pickup — the driver is rolling toward
//  the pickup dock with live turn-by-turn guidance, hazmat-safe
//  routing, and a bottom sheet that shows the facility + appt
//  clock + the three live tiles (distance left / drive time /
//  fuel burn).
//
//  Figma source of truth:
//    /Users/diegousoro/Desktop/EusoTrip 2027 UI Wireframes/
//      01 Driver/{Dark,Light}/013 En Route to Pickup.png
//
//  Cohort B — server-backed (97th firing, gap-analysis P0):
//
//    • `TripLifecycleStore` hydrates the driver's currently-
//      assigned load + enumerates legal next-state transitions.
//    • "Continue route" CTA fires `loadLifecycle.executeTransition`
//      on the closest matching forward hop + chains into the
//      local `lifecycleAdvance` closure so the trip walks to 014.
//    • `Call shipper` deeplinks to `tel:` using the shipper's
//      phone from the Load record; disables honestly ("No phone
//      on file") while the wire shape carries no contact phone.
//    • `route.plan` resolves and persists the exact mode-native route;
//      this client supplies only load identity + active-job purpose.
//    • ETA, remaining distance/time, current instruction, and progress
//      stay neutral until the server returns an exact route projection.
//    • `HereLiveMapView` renders independent canonical lines plus a
//      separately sourced, licensed Live Operations observation.
//
//  Role + vertical awareness:
//    • DRIVER / CATALYST / ESCORT → "En route · Pickup"
//    • RAIL_ENGINEER / RAIL_CONDUCTOR → "En route · Rail yard"
//    • SHIP_CAPTAIN / VESSEL_OPERATOR → "En route · Port"
//    • Chip row adapts to the product:
//        hazmat tanker → NH3 · UN1005 · TANK
//        dry van → BOL · CTE · DRY
//        reefer → REEFER · 36°F · CTE
//    • Low-clearance warning only renders when HERE returns a
//      vertical-clearance attribute on any segment in the next
//      ~5 mi.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on "Continue route" primary CTA
//         + progress bar fill. Brand.warning on LOW-CLEARANCE chip.
//         Brand.blue on HAZMAT ROUTE LOCKED. Brand.success on
//         NH3/UN/TANK commodity chip when hazmat is locked.
//    §4   Tokenized Space / Radius / EType throughout.
//    §5   Palette semantic throughout (no raw Color.white).
//

import SwiftUI
import UIKit

// MARK: - Screen

struct ActiveEnroute: View {
    @Environment(\.palette) var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    /// Canonical sheet→push detail closure (auto BespokeBackBar). Used to
    /// push the Reroute Optimizer in-stack — NEVER a slide-up modal.
    @Environment(\.rolePushDetail) private var pushDetail
    @EnvironmentObject var session: EusoTripSession

    enum Register { case night, morning }
    let register: Register

    @Environment(\.openURL) private var openURL

    // Live server-backed state
    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?

    // MARK: - Canonical route + licensed live evidence
    //
    // The client identifies only the load and purpose. Mode, endpoints,
    // equipment profile, graph, source evidence, geometry, and instructions
    // are resolved and committed by route.plan on the server.
    @State private var canonicalRouteLines: [[HereLatLng]] = []
    @State private var canonicalRouteStatus: String?
    @State private var canonicalRouteVersion: Int?
    @State private var liveTruckObservation: LiveOperationsClient.Observation?
    @State private var liveTruckStatus: HereLiveOperationsStatus?
    /// HOS-reachability isoline ring (how far the driver can legally drive on
    /// the remaining clock). Empty when unknown — no layer drawn.
    @State private var isolinePolygon: [HereLatLng] = []
    /// §3c receiver fence for the corridor terminus (map-layer adoption
    /// 2026-06-10). Resolved from a REAL `tracking.getGeofences` row
    /// matched against the load's delivery coordinate — the ring draws
    /// the row's own center + radius (meters). nil when no fence row
    /// covers the receiver → NO ring is painted (honest absence; the
    /// radius is never invented).
    @State private var receiverFence: TrackingGeofencesAPI.ResolvedFence?

    // L08-9 · Astra hazmat placard scan. Presented as a SHEET (never a nav
    // push) from a hazmat-gated CTA in the bottom sheet. `lastPlacardUN`
    // records the UN of the most recent successful scan so the CTA can
    // confirm it back to the driver — a real local effect off the verified
    // `PlacardScanResponse`, never fabricated.
    @State private var showPlacardScan = false
    @State private var lastPlacardUN: String? = nil

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topManeuverCard
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s2)
                weatherRerouteBanner
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s2)
                Spacer()
                bottomSheet
                    .padding(.horizontal, Space.s3)
                    .padding(.bottom, Space.s3)
            }
        }
        .screenTileRoot()
        .eusoRefreshTask { await hydrateLiveTrip() }
        .eusoRefreshTask { await refreshHosReachability() }
    }

    // MARK: - Product + vertical awareness
    //
    // Dispatched through the shared `LifecycleProductContext` so
    // this screen carries the same vertical + product-variant
    // awareness the 014-025 rewrites use. Retired the local
    // `TripVertical` enum that only knew about pickup-word and
    // didn't split by product — now every chip, icon, and ESANG
    // line can adapt to dry van / reefer / flatbed / container /
    // rail / vessel just like the rest of the lifecycle family.

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    /// Back-compat alias for the existing call sites inside this
    /// file that read `vertical.pickupWord`. Any new surface on
    /// 013 should read `ctx.vertical` / `ctx.product` directly.
    private var vertical: TripVertical { ctx.vertical }

    /// The symbiotic-weather reroute banner — truck loads only (rail/vessel
    /// advise), and only when the load carries real pickup/delivery coords.
    @ViewBuilder private var weatherRerouteBanner: some View {
        if ctx.vertical == .truck,
           let load = activeLoad,
           let p = load.pickupLocation, let d = load.deliveryLocation,
           let pickupCoordinate = p.coordinatePair,
           let deliveryCoordinate = d.coordinatePair {
            WeatherRerouteBanner(
                origin: HereMapsAPI.LatLng(lat: pickupCoordinate.lat,
                                           lng: pickupCoordinate.lng),
                destination: HereMapsAPI.LatLng(lat: deliveryCoordinate.lat,
                                                lng: deliveryCoordinate.lng)
            )
        }
    }

    // MARK: - Hydration

    /// Hydrate the lifecycle store from the driver's current
    /// assigned load and pull the full Load row for the map +
    /// destination card. Safe to run on every appear — cheap
    /// when `loadId` is already populated.
    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        let load = try? await EusoTripAPI.shared.loads.getById(n)
        activeLoad = load
        if let load {
            await refreshCanonicalRoute(for: load)
            await refreshLicensedTruckObservation(for: load)
            await resolveReceiverFence(for: load)
        }
    }

    /// Looks up the company's REAL geofence row covering the delivery
    /// coordinate (`tracking.getGeofences` → nearest active circle row
    /// whose center sits within max(its radius, 1.5 km) of the
    /// receiver). The §3c receiver ring renders only when such a row
    /// exists — its own center + radius — otherwise the map stays
    /// ring-free. No invented coordinates, no invented radius.
    @MainActor
    private func resolveReceiverFence(for load: Load) async {
        guard let delivery = load.deliveryLocation,
              let coordinate = LatLongParser.validatedCoordinate(
                  latitude: delivery.lat,
                  longitude: delivery.lng
              ) else {
            receiverFence = nil
            return
        }
        receiverFence = await EusoTripAPI.shared.trackingGeofences
            .fence(near: coordinate.latitude, coordinate.longitude)
    }

    /// Resolves the exact server-owned active-job route. This screen never
    /// submits endpoints, mode, profile facts, graph facts, or geometry.
    @MainActor
    private func refreshCanonicalRoute(for load: Load) async {
        canonicalRouteLines = []
        canonicalRouteStatus = nil
        canonicalRouteVersion = nil
        do {
            let result = try await CanonicalRoutePlanClient.shared.planLoad(
                id: load.id,
                purpose: .activeJob
            )
            switch result {
            case .persisted(let persisted):
                applyCanonicalRoute(persisted.route)
            case .pending(let pending):
                canonicalRouteStatus = pending.blockers.first?.message
                    ?? "Canonical mode-native route pending verified authority"
                await readExistingCanonicalRoute(loadId: load.id)
            }
        } catch {
            canonicalRouteStatus = error.eusoUserCopy
            await readExistingCanonicalRoute(loadId: load.id)
        }
    }

    @MainActor
    private func readExistingCanonicalRoute(loadId: Int) async {
        do {
            applyCanonicalRoute(
                try await CanonicalRoutePlanClient.shared.getBoundLoad(id: loadId)
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
            canonicalRouteStatus = "Canonical route exists but is not released for rendering"
            return
        }
        canonicalRouteLines = payload.lines
        canonicalRouteVersion = payload.identity.version
        canonicalRouteStatus = nil
    }

    /// Reads the driver's tenant-bound truck observation through the Live
    /// Operations authority. The marker is evidence only; it never becomes
    /// route geometry or progress without a server route projection.
    @MainActor
    private func refreshLicensedTruckObservation(for load: Load) async {
        liveTruckObservation = nil
        liveTruckStatus = nil
        guard EusoTripMapTransportMode(canonicalValue: load.transportMode) == .truck else {
            return
        }
        do {
            let assigned = try await EusoTripAPI.shared.vehicle.getAssigned()
            guard let vehicleId = Int(assigned.id) else {
                liveTruckStatus = .init(
                    availability: .empty,
                    sourceLabel: nil,
                    freshnessLabel: nil,
                    detail: "No assigned truck is available for authorized live evidence",
                    observationCount: 0
                )
                return
            }
            let result = try await LiveOperationsClient.shared.latestTruck(vehicleId: vehicleId)
            liveTruckObservation = result.observation
            liveTruckStatus = Self.liveOperationsStatus(from: result)
        } catch {
            liveTruckStatus = .init(
                availability: .degraded,
                sourceLabel: nil,
                freshnessLabel: nil,
                detail: "Authorized truck observation is unavailable",
                observationCount: 0
            )
        }
    }

    private static func liveOperationsStatus(
        from result: LiveOperationsClient.AssetResult
    ) -> HereLiveOperationsStatus {
        guard let observation = result.observation else {
            return .init(
                availability: .empty,
                sourceLabel: nil,
                freshnessLabel: nil,
                detail: result.coverage.statement,
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
            detail: observation.accessibleEvidenceLabel,
            observationCount: 1
        )
    }

    /// HOS-reachability isoline: how far the driver can legally drive on the
    /// remaining 11h clock, from the current position. Honest — empty when
    /// remaining HOS or a fix is unknown, or HERE returns no polygon.
    private func refreshHosReachability() async {
        guard let status = HOSClockService.shared.status,
              status.hasCurrentObservation(),
              status.canDrive == true,
              let drivingRemaining = status.drivingRemaining,
              drivingRemaining > 0,
              let fix = await DriverLocationResolver.shared.currentCoordinate() else {
            isolinePolygon = []
            return
        }
        let rangeSec = Int((drivingRemaining * 3600).rounded())
        let result = try? await EusoTripAPI.shared.hereMaps.isoline(
            origin: .init(lat: fix.latitude, lng: fix.longitude),
            rangeSec: rangeSec
        )
        guard result?.ok == true, let poly = result?.polygon else {
            isolinePolygon = []
            return
        }
        let rawPolygon: [HereMapsAPI.IsolinePoint] = poly
        let coordinates: [HereLatLng] = rawPolygon.compactMap { point -> HereLatLng? in
            guard let coordinate = LatLongParser.validatedCoordinate(
                latitude: point.lat,
                longitude: point.lng
            ) else { return nil }
            return HereLatLng(coordinate)
        }
        isolinePolygon = coordinates.count >= 3 ? coordinates : []
    }

    /// Fires the next forward state transition on the server
    /// then hops to 014 via the local `lifecycleAdvance` closure.
    /// Selection picks the first transition whose target state
    /// matches pickup-arrival semantics; falls through to local
    /// advance when no legal server transition exists (preview +
    /// no-active-load runtime).
    private func continueRoute() async {
        let candidates = lifecycle.availableTransitions
        let preferred = candidates.first { t in
            let to = t.to.lowercased()
            return to.contains("approach") || to.contains("at_pickup") || to.contains("pickup")
        } ?? candidates.first
        if let transition = preferred {
            _ = await lifecycle.execute(transition)
        }
        advance?()
    }

    // MARK: - Data bindings (server projection only)

    /// Remaining distance, duration, ETA, and percent require a committed
    /// server projection against this exact route version. A licensed position
    /// by itself is not route progress, so these stay neutral until that
    /// projection contract is present.
    private var remainingMilesText: String { "-" }
    private var remainingDriveText: String { "-" }
    private var etaClockText: String { "-" }
    private var etaLabelText: String { "ETA · PROJECTION PENDING" }
    private var milesLabelText: String { "POSITION EVIDENCE ONLY" }
    private var timeRemainingText: String { "ROUTE PROJECTION PENDING" }

    /// Pickup-window clock from the load's `pickupDate` (the APPT
    /// shown beside the pickup facility), else "-".
    private var appointmentText: String {
        guard let iso = activeLoad?.pickupDate,
              let date = Self.parseISO(iso) else { return "-" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let tz = TimeZone.current.abbreviation() ?? ""
        return tz.isEmpty ? f.string(from: date) : "\(f.string(from: date)) \(tz)"
    }

    /// Instantaneous FUEL BURN has NO live source — there is no
    /// truck-telemetry feed anywhere in the platform — so it renders
    /// an honest em-dash, never a fabricated gallons figure.
    private var fuelBurnText: String { "-" }

    private var titleHeading: String {
        canonicalRouteLines.isEmpty ? "Awaiting route authority" : "Canonical route ready"
    }

    private var titleDetail: String {
        if let canonicalRouteStatus, !canonicalRouteStatus.isEmpty {
            return canonicalRouteStatus
        }
        if let canonicalRouteVersion {
            return "Plan v\(canonicalRouteVersion) · current instruction requires verified projection"
        }
        if let load = activeLoad, let loc = load.pickupLocation, !loc.cityState.isEmpty {
            return "Destination evidence · \(loc.cityState)"
        }
        return "-"
    }

    /// Lenient ISO-8601 parse (with and without fractional seconds).
    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    private var destinationFacility: String {
        if let load = activeLoad,
           let loc = load.pickupLocation,
           !loc.city.isEmpty {
            let stateSuffix = loc.state.isEmpty ? "" : ", \(loc.state)"
            return "\(loc.city)\(stateSuffix)"
        }
        return "-"
    }

    private var destinationAddress: String {
        if let load = activeLoad,
           let loc = load.pickupLocation,
           !loc.address.isEmpty {
            var parts = [loc.address]
            if !loc.city.isEmpty    { parts.append(loc.city) }
            if !loc.state.isEmpty   { parts.append(loc.state) }
            if !loc.zipCode.isEmpty { parts.append(loc.zipCode) }
            return parts.joined(separator: " · ")
        }
        return "-"
    }

    // MARK: - Commodity chip row
    //
    // Reads the load's hazmat + product + HERE clearance fields
    // to compose the three chips visible in the Figma frame. Each
    // chip comes from a real data source — we never fabricate an
    // NH3 UN number or a low-clearance distance.

    private struct EnrouteChip: Identifiable {
        let id = UUID()
        let label: String
        let tint: Color
        let icon: String?
    }

    /// True when the live load actually carries a hazmat class. Gates the
    /// HAZMAT ROUTE LOCKED chip AND the placard-scan CTA (L08-9). No load /
    /// non-hazmat load ⇒ no hazmat affordances (never fabricated).
    private var isHazmatLoad: Bool {
        (activeLoad?.hazmatClass ?? "").isEmpty == false
    }

    private var chips: [EnrouteChip] {
        var out: [EnrouteChip] = []
        // HAZMAT chip — rendered only when the live load actually
        // carries a hazmat class. No load = no fabricated chip.
        let isHazmat = isHazmatLoad
        if isHazmat {
            out.append(EnrouteChip(label: "HAZMAT ROUTE LOCKED", tint: Brand.info, icon: "lock.shield"))
        }
        // 2026-05-17 — Mode chip on the driver en-route header. Hidden
        // for default truck-single-vehicle. Renders MODE × Nx so a rail
        // engineer hauling a 100-tank-car unit train sees the count
        // up-front during transit, distinguishable from a single-truck
        // load even though they look identical in plain text.
        if let load = activeLoad {
            let mode = (load.transportMode ?? "truck").lowercased()
            let count = load.multiVehicleCount ?? 1
            if mode != "truck" || count > 1 {
                let label: String = {
                    let m = mode.uppercased()
                    return count > 1 ? "\(count)× \(m)" : m
                }()
                let tint: Color = {
                    switch mode {
                    case "rail":   return Brand.rail
                    case "vessel": return Brand.vessel
                    case "barge":  return Brand.info
                    default:       return Brand.blue
                    }
                }()
                out.append(EnrouteChip(label: label, tint: tint, icon: nil))
            }
        }
        // Commodity chip — UN + class + cargoType.
        if let load = activeLoad {
            var pieces: [String] = []
            if let name = load.commodityName, !name.isEmpty { pieces.append(name.uppercased()) }
            if let un = load.unNumber, !un.isEmpty { pieces.append(un) }
            if let cargo = load.cargoType, !cargo.isEmpty { pieces.append(cargo.uppercased()) }
            if !pieces.isEmpty {
                out.append(EnrouteChip(
                    label: pieces.joined(separator: " · "),
                    tint: Brand.success,
                    icon: nil
                ))
            }
        }
        // Low-clearance chip — sourced from HERE route span
        // truck-attributes. The route models don't currently decode
        // per-span clearance limits, so there is no live source for a
        // clearance warning and we never fabricate one.
        return out
    }

    // MARK: - Map layer

    @ViewBuilder
    private var mapLayer: some View {
        if let load = activeLoad,
           let pickup = load.pickupLocation,
           let delivery = load.deliveryLocation,
           let pickupCoordinate = pickup.coordinatePair,
           let deliveryCoordinate = delivery.coordinatePair {
            // Canonical OMV vector map + exact committed route lines + licensed
            // Live Operations evidence. Route geometry and position evidence
            // stay separate; discontinuities are never bridged.
            let mapTransportMode = EusoTripMapTransportMode(
                canonicalValue: load.transportMode
            )
            let markers = operationalMarkers(
                pickup: .init(pickupCoordinate.lat, pickupCoordinate.lng),
                delivery: .init(deliveryCoordinate.lat, deliveryCoordinate.lng)
            )
            let markerLayer = HereMapLayer.markers(markers)
            let routeLayers: [HereMapLayer] = canonicalRouteLines.enumerated().map { index, line in
                .eusoRoute(
                    polyline: line,
                    state: .active,
                    label: index == 0
                        ? "Eusorone \(mapTransportMode.rawValue) route plan version \(canonicalRouteVersion ?? 0)"
                        : nil
                )
            } + [markerLayer]
            // §3c receiver fence at the corridor terminus — ONLY when a
            // real `tracking.getGeofences` row covers the receiver
            // (resolveReceiverFence). Absent row ⇒ absent layer.
            let fenceLayers: [HereMapLayer] = receiverFence.map {
                [.geofenceRing(center: $0.center,
                               radiusMeters: $0.radiusMeters,
                               kind: .receiver,
                               breachAt: nil)]
            } ?? []
            // HOS-reachability isoline — a translucent ring of how far the
            // driver can legally drive on the remaining clock. Drawn only when
            // HERE returned a real polygon (≥3 pts).
            let isolineLayers: [HereMapLayer] = isolinePolygon.count >= 3
                ? [.adZones([HerePolygon(ring: isolinePolygon, fillHex: "#00C48C", opacity: 0.12, label: "HOS reach")])]
                : []
            HereLiveMapView(
                center: .init(pickupCoordinate.lat, pickupCoordinate.lng),
                zoom: 7,
                firstPerson: true,
                route: [],
                baseLayers: routeLayers + fenceLayers + isolineLayers,
                addOns: mapTransportMode == .truck ? .driverEnRoute : [],
                activeJob: true,
                mapModeContext: .unconfirmed(mapTransportMode),
                liveOperationsStatus: liveTruckStatus
            )
            .overlay(alignment: .bottomLeading) {
                if let canonicalRouteStatus {
                    Text(canonicalRouteStatus)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(palette.bgCard.opacity(0.92))
                        .overlay(Capsule().strokeBorder(Brand.warning.opacity(0.45)))
                        .clipShape(Capsule())
                        .padding(10)
                        .accessibilityLabel(canonicalRouteStatus)
                }
            }
        } else {
            mapPlaceholder
        }
    }

    /// Builds the marker array outside the ViewBuilder so optional licensed
    /// position evidence can be appended without becoming an expression in
    /// the SwiftUI result builder. The observation remains independent from
    /// canonical route geometry.
    private func operationalMarkers(
        pickup: HereLatLng,
        delivery: HereLatLng
    ) -> [HereMarker] {
        var markers: [HereMarker] = [
            .init(at: pickup, kind: .pickup, label: destinationFacility),
            .init(at: delivery, kind: .delivery, label: nil)
        ]
        if let observation = liveTruckObservation,
           let coordinate = observation.position.coordinate {
            markers.append(.init(
                at: coordinate,
                kind: .truck,
                label: "Assigned truck",
                observationState: observation.markerState,
                sourceLabel: observation.provider.id,
                accessibilityLabel: observation.accessibleEvidenceLabel
            ))
        }
        return markers
    }

    /// Operational empty state shown until the active load has verified route
    /// coordinates. It deliberately contains no authored roads or route line.
    private var mapPlaceholder: some View {
        EusoEmptyState(
            systemImage: "mappin.slash",
            title: "Awaiting route coordinates",
            subtitle: "Live navigation will appear after verified pickup and delivery coordinates are available."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.bgCard)
    }

    // MARK: - Top maneuver card

    private var topManeuverCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            maneuverIcon
            VStack(alignment: .leading, spacing: Space.s2) {
                maneuverHeader
                maneuverSubhead
                progressRail
                milesRow
                chipsRow
                // HERE Dynamic Map Content — live road intel chips.
                // Pulls Real-Time Traffic flow, Road Alerts
                // (incidents), and Safety Cameras in parallel, using
                // an authorized current observation or a fallback
                // waypoint from the active load. Chips silently hide
                // when HERE returns nothing, so the card stays clean
                // between events.
                //
                // §3 WEATHER AHEAD chip (Wave 3b parity): pass the same
                // active load id this screen already hydrates for the HUD
                // leg/ETA so the bespoke weather chip mounts. The chip
                // hides itself when the lane is clear / none / enterprise-
                // gated (available:false today) and lights up the moment
                // the §3 lane risk is actionable — never a fabricated band.
                EnRouteRoadIntelStrip(loadId: activeLoad.map { String($0.id) })
            }
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderSoft, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        )
    }

    private var maneuverIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(LinearGradient.diagonal)
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(.white)
        }
        .frame(width: 54, height: 54)
    }

    private var maneuverHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(titleHeading)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(etaClockText)
                    .font(EType.bodyStrong.monospaced())
                    .foregroundStyle(palette.textPrimary)
                Text(etaLabelText)
                    .font(EType.micro)
                    .tracking(1.1)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private var maneuverSubhead: some View {
        Text(titleDetail)
            .font(EType.body)
            .foregroundStyle(palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var progressRail: some View {
        Capsule().fill(palette.tintNeutral.opacity(0.4))
        .frame(height: 4)
        .accessibilityLabel("Route progress pending verified server projection")
    }

    private var milesRow: some View {
        HStack {
            Text(milesLabelText)
                .font(EType.caption.monospaced())
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(timeRemainingText)
                .font(EType.caption.monospaced())
                .foregroundStyle(palette.textTertiary)
        }
    }

    @ViewBuilder
    private var chipsRow: some View {
        let all = chips
        FlowRow(spacing: 6) {
            ForEach(all) { chip in
                enrouteChip(chip)
            }
        }
    }

    private func enrouteChip(_ chip: EnrouteChip) -> some View {
        HStack(spacing: 4) {
            Circle().fill(chip.tint).frame(width: 6, height: 6)
            if let icon = chip.icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(chip.tint)
            }
            Text(chip.label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(chip.tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(
            Capsule().stroke(chip.tint.opacity(0.55), lineWidth: 1)
        )
    }

    // MARK: - Bottom sheet

    private var bottomSheet: some View {
        VStack(spacing: Space.s3) {
            Capsule().fill(palette.borderSoft).frame(width: 40, height: 4)

            // Facility row
            HStack(alignment: .top, spacing: Space.s3) {
                facilityPin
                VStack(alignment: .leading, spacing: 2) {
                    Text(destinationFacility)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(destinationAddress)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("APPT")
                        .font(EType.micro)
                        .tracking(1.3)
                        .foregroundStyle(palette.textTertiary)
                    Text(appointmentText)
                        .font(EType.bodyStrong.monospaced())
                        .foregroundStyle(palette.textPrimary)
                }
            }

            // Tiles
            HStack(spacing: Space.s2) {
                tile(label: "DISTANCE", value: remainingMilesText)
                tile(label: "DRIVE TIME", value: remainingDriveText)
                tile(label: "FUEL BURN", value: fuelBurnText)
            }

            // Reroute affordance — pushes the Reroute Optimizer in-stack
            // (canonical sheet→push, NOT a slide-up). Compares the active
            // route against ranked alternates (routing.compareAlternatives)
            // and applies a chosen route (routing.applyReroute). Always
            // tappable; the optimizer self-hydrates the active load and
            // shows an honest "no saved route" state when none is persisted.
            rerouteAffordance

            // CTAs
            HStack(spacing: Space.s2) {
                Button {
                    callShipper()
                } label: {
                    Text(shipperPhone == nil ? "No phone on file" : "Call shipper")
                        .font(EType.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(shipperPhone == nil ? palette.textTertiary : palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderSoft, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(shipperPhone == nil)

                Button {
                    Task { await continueRoute() }
                } label: {
                    HStack(spacing: 6) {
                        if lifecycle.inflightTransitionId != nil {
                            ProgressView().progressViewStyle(.circular).tint(.white)
                        }
                        Text("Continue route")
                            .font(EType.body)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(LinearGradient.diagonal)
                    )
                }
                .buttonStyle(.plain)
                .disabled(lifecycle.inflightTransitionId != nil)
                .accessibilityLabel("Continue route to pickup")
            }

            // L08-9 · Hazmat placard scan — hazmat loads only. Canonical
            // CTAButton (NO NavigationLink) that presents the already-built
            // Astra `HazmatPlacardScanView` as a SHEET. Gated on the same
            // `isHazmatLoad` as the HAZMAT ROUTE LOCKED chip, so a dry-van /
            // reefer load never sees it. `onScanComplete` records the verified
            // UN back into the CTA subtitle — a real local effect, not a stub.
            if isHazmatLoad {
                CTAButton(
                    title: "Scan hazmat placard",
                    action: { showPlacardScan = true },
                    leadingIcon: "camera.viewfinder",
                    subtitle: lastPlacardUN.map { "LAST SCAN · UN \($0)" }
                )
                .accessibilityLabel("Scan hazmat placard with camera")
                .sheet(isPresented: $showPlacardScan) {
                    NavigationStack {
                        HazmatPlacardScanView(
                            loadId: activeLoad.map { String($0.id) },
                            onScanComplete: { resp in
                                if let un = resp.ocr.unNumber ?? resp.unNumber, !un.isEmpty {
                                    lastPlacardUN = un
                                }
                            }
                        )
                    }
                }
            }
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderSoft, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
        )
    }

    /// "Reroute" affordance on the en-route sheet — slim, full-width row
    /// that pushes the Reroute Optimizer via the canonical sheet→push
    /// detail layer (auto BespokeBackBar; never a slide-up modal). Passes
    /// the active load id + mode so the optimizer resolves the right route.
    private var rerouteAffordance: some View {
        Button {
            let lid = activeLoad?.id
            let mode = activeLoad?.transportMode
            pushDetail?("Reroute Optimizer") {
                AnyView(RerouteOptimizerSheet(loadId: lid, transportMode: mode))
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Reroute · compare alternates")
                    .font(EType.body).fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.vertical, Space.s3)
            .padding(.horizontal, Space.s3)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open reroute optimizer")
    }

    private var facilityPin: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(LinearGradient.diagonal.opacity(0.18))
                .frame(width: 40, height: 40)
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
        }
    }

    private func tile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(1.2)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.bodyStrong.monospaced())
                .foregroundStyle(palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.tintNeutral.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Helpers

    /// The shipper's dialable phone, when the live `Load` carries
    /// one. The current `Load` Codable shape does NOT surface a
    /// shipper/contact phone (no field on the wire), so this stays
    /// nil and the Call button disables itself honestly — we never
    /// fabricate a number. Mirrors the receiver-call pattern on 038.
    private var shipperPhone: String? {
        // Wired to a real value once `loads.getById` surfaces
        // `shipper.phone`. Until then there is no live source.
        nil
    }

    /// Deeplink to `tel:` using the shipper's phone on the active
    /// load. No-op when no phone is on file — never fabricate a
    /// contact, never dial a placeholder number.
    private func callShipper() {
        guard let raw = shipperPhone, !raw.isEmpty else { return }
        let digits = raw.filter { "+0123456789".contains($0) }
        guard !digits.isEmpty, let url = URL(string: "tel:\(digits)") else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        openURL(url)
    }
}

// MARK: - FlowRow (wraps chips across lines)

private struct FlowRow<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        _FlowLayout(spacing: spacing) { content() }
    }
}

private struct _FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        var total = CGSize(width: 0, height: 0)
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxWidth, x > 0 {
                y += rowH + spacing
                x = 0
                rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            total.width = max(total.width, x)
            total.height = y + rowH
        }
        return total
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX {
                y += rowH + spacing
                x = bounds.minX
                rowH = 0
            }
            s.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(sz)
            )
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

// MARK: - Wrapper (registry entry)

struct ActiveEnrouteScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            // Figma shows a single register — the Dark/Light
            // variants are palette-driven, not register-driven.
            // We pick `.morning` as the default; a future cue from
            // session time-of-day can flip to `.night`.
            ActiveEnroute(register: .morning)
        } nav: {
            BottomNav(
                leading: [
                    NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
                    NavSlot(label: "Trips", systemImage: "truck.box", isCurrent: true),
                ],
                trailing: [
                    NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
                    NavSlot(label: "Me",     systemImage: "person",      isCurrent: false),
                ],
                orbState: .idle
            )
        }
    }
}

// MARK: - Previews

#Preview("013 · En Route to Pickup · Dark") {
    ActiveEnrouteScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("013 · En Route to Pickup · Light") {
    ActiveEnrouteScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}

// MARK: - Weather hazard reroute banner (the symbiotic-weather loop)
//
// Closes the loop the weather program opened: calls hereMaps.weatherReroute
// (live HERE Destination Weather alerts sampled along the corridor → HERE
// avoid[areas] → a truck route AROUND them, with REAL baseline-vs-avoided
// miles when HERE can produce a detour). Honest rendering shows ONLY real signal:
//   • a reroute card when a detour actually avoids an ON-ROAD hazard,
//   • an advisory when hazards are near the corridor but NOT on the road,
//   • nothing at all when the road is clear.
// No fabricated detour miles — every number comes from the HERE route diff.
struct WeatherRerouteBanner: View {
    let origin: HereMapsAPI.LatLng
    let destination: HereMapsAPI.LatLng

    @Environment(\.palette) private var palette
    @State private var result: HereMapsAPI.WeatherRerouteResult?
    @State private var errorText: String?
    @State private var loaded = false

    var body: some View {
        Group {
            if let r = result {
                if r.rerouted, r.milesAdded > 0 {
                    card(icon: "cloud.bolt.rain.fill", tint: Brand.warning,
                         title: "Severe weather ahead",
                         detail: hazardLine(r),
                         footer: "Detour avoids it · +\(r.milesAdded) mi")
                } else if r.hazardCount > 0 {
                    card(icon: "exclamationmark.triangle.fill", tint: Brand.info,
                         title: "\(r.hazardCount) weather alert\(r.hazardCount == 1 ? "" : "s") near your route",
                         detail: hazardLine(r),
                         footer: "None on your road — monitoring live")
                }
                // r.hazardCount == 0 → clear road → render nothing.
            } else if let errorText {
                card(icon: "wifi.exclamationmark", tint: Brand.warning,
                     title: "Route weather unavailable",
                     detail: errorText,
                     footer: "Live monitor paused")
            }
        }
        .task {
            guard !loaded else { return }
            loaded = true
            do {
                result = try await EusoTripAPI.shared.hereMaps.weatherReroute(origin: origin, destination: destination)
                errorText = nil
            } catch {
                result = nil
                errorText = weatherError(error)
            }
        }
    }

    private func hazardLine(_ r: HereMapsAPI.WeatherRerouteResult) -> String {
        if let h = r.hazards.first {
            if let head = h.headline, !head.isEmpty { return head }
            return [h.event, h.severity].compactMap { $0 }.joined(separator: " · ")
        }
        return "Active hazard near the corridor"
    }

    private func weatherError(_ error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Couldn’t reach the live route-weather monitor." : message
    }

    private func card(icon: String, tint: Color, title: String, detail: String, footer: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(detail).font(EType.caption).foregroundStyle(palette.textSecondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(footer).font(.system(size: 11, weight: .heavy)).foregroundStyle(tint).padding(.top, 1)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(tint.opacity(0.4), lineWidth: 1))
        )
    }
}
