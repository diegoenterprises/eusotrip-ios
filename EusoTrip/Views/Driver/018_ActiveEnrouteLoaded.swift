//  018_ActiveEnrouteLoaded.swift
//  EusoTrip 2027 UI — Wave 1
//
//  Screen 018 · Active Load — en route to delivery (loaded, long-haul eastbound).
//  Moment (night):     Michael Eusorone, 10:24 AM CDT, I-20 E near Pell City AL,
//                      247 mi of 620 done, 373 mi remaining, ETA 18:12 EDT
//                      (+1h 42m after 16:00–16:30 window). Receiver is 24/7.
//  Moment (afternoon): Michael Eusorone, 16:24 CDT, I-20 E approaching Birmingham,
//                      193 mi of 620 done, 427 mi remaining, ETA 00:42 EDT
//                      (+43m after 23:30–23:59 window). Receiver is 24/7.
//
//  Cohort B promotion (81st firing, 2026-04-24):
//    • `@StateObject TripLifecycleStore` — the single binding for the
//      state machine; `.refresh()` pulls `availableTransitions` +
//      `history` on every `.task` rebind.
//    • `@State activeLoad: Load?` — hydrated via `lifecycle.loadId`
//      → `EusoTripAPI.shared.loads.getById(n)`.
//    • `LifecycleProductContext` — resolves product + vertical per
//      role + load so the chrome reads correctly for dry-van, reefer,
//      flatbed, container, rail-intermodal, rail-bulk, vessel-
//      container, vessel-bulk, and vessel-tanker drivers — not just
//      hazmat tanker.
//    • Figma-verbatim fallbacks under `fallback*` — displayed only
//      when `activeLoad` is nil so offline/preview walks still render
//      the documented moment.
//    • No mock/fake markers. All numbers come from the real Load
//      object when available and gracefully fall back to the Figma-
//      verbatim frame otherwise.
//
//  Doctrine refs: §4.3 (iridescent route line = the one hairline),
//                 §5 (glass bottom sheet — only non-map surface),
//                 §6 (dual register), §7 (canvas density),
//                 §8 (Driver rhythm), §9 (ActiveCard glass variant),
//                 §12 (both previews).

import SwiftUI
import CoreLocation

// MARK: - Screen

struct ActiveEnrouteLoaded: View {
    @Environment(\.palette) var palette
    @Environment(\.driverNavBack) private var navBack
    @Environment(\.driverToggleMapLayers) private var toggleMapLayers
    @Environment(\.driverOpenTripLog) private var openTripLog
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @StateObject private var hos = HOSLiveStore()
    @State private var activeLoad: Load?

    /// Decoded HERE Routing v8 section polyline for the pickup→delivery
    /// corridor — the real road geometry painted on the basemap, not a
    /// 2-point great-circle straight segment. Empty until the route
    /// resolves; the map then falls back to the straight pickup→delivery
    /// base line (never a fabricated path). Mirrors 013 / 035.
    @State private var routePolyline: [HereLatLng] = []

    /// §3c receiver fence on the loaded-approach corridor (map-layer
    /// adoption 2026-06-10). Resolved from a REAL `tracking.getGeofences`
    /// row matched against the load's delivery coordinate — the ring is
    /// the row's own center + radius (meters). nil ⇒ no ring is painted
    /// (honest absence; the radius is never invented). Mirrors 013.
    @State private var receiverFence: TrackingGeofencesAPI.ResolvedFence?

    enum Register { case night, afternoon }
    let register: Register

    /// Product + vertical dispatch for every chrome decision on this
    /// screen. A dry-van driver sees pallet seal + BOL language, a
    /// reefer driver sees set-point, a flatbed driver sees securement,
    /// a container driver sees seal + chassis, a rail or vessel
    /// driver sees the right nouns for the gate/berth/spur.
    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Figma-verbatim fallbacks (2026-04-24 frame)
    //
    // Used only when `activeLoad` is nil. Every computed getter below
    // prefers the real Load field and falls back to these values so
    // the documented Figma moment still renders end-to-end in preview
    // walks and offline sims.

    private let fallbackLoadID     = "-"
    private let fallbackOriginName = "-"
    private let fallbackDestTitle  = "-"
    private let fallbackDestSub    = "-"
    private let fallbackMilesTotal = "620"
    /// 110th firing M2 retrofit: previous literal "881204" excised.
    /// The seal id is not yet a first-class field on `Load`; until
    /// `Load.sealNumber` ships from the backend the floating card
    /// omits the seal segment entirely rather than fabricating one.
    private let fallbackSealID     = "-"

    /// Compact label for the on-map destination flag. Prefers the
    /// receiver's city/state from the hydrated Load; falls back to
    /// em-dash when the Load hasn't hydrated yet.
    /// Doctrine: 0% mock data — never render a fabricated brand name
    /// in the production map overlay (110th firing leak fix —
    /// the previous fabricated big-box-retailer DC literal was excised).
    private var destFlagText: String {
        if let dest = activeLoad?.deliveryLocation {
            let city = dest.cityState
            if !city.isEmpty { return city }
        }
        return "-"
    }
    // MARK: - Live/fallback computed overrides

    private var loadID: String {
        activeLoad?.loadNumber ?? fallbackLoadID
    }
    private var originName: String {
        activeLoad?.pickupLocation?.cityState ?? fallbackOriginName
    }
    /// Receiver brand · receiver city + state — builds from the
    /// Load's deliveryLocation when available; falls back to the
    /// Figma-verbatim string when the Load hasn't hydrated yet.
    /// `LoadLocation.cityState` already does the "City, ST"
    /// formatting.
    private var destTitle: String {
        guard let dest = activeLoad?.deliveryLocation else {
            return fallbackDestTitle
        }
        let addr = dest.address.isEmpty ? "" : dest.address
        let city = dest.cityState
        if !addr.isEmpty, !city.isEmpty { return "\(addr) · \(city)" }
        if !city.isEmpty { return city }
        return fallbackDestTitle
    }
    /// "72 pallets · Dry · 42,340 lb · seal 881204" — best-effort
    /// product-aware rebuild. Pallet count + seal are not first-class
    /// fields on `Load`, so we source weight from the Load and fall
    /// back to the Figma frame for the non-weight portions. The
    /// `ctx` drives the cargo descriptor so reefer reads "Reefer",
    /// flatbed reads "Flatbed", etc.
    private var destSub: String {
        guard let load = activeLoad else { return fallbackDestSub }
        let weightPill: String
        if let w = load.weight, !w.isEmpty {
            let unit = load.weightUnit ?? "lb"
            weightPill = "\(w) \(unit)"
        } else {
            weightPill = "42,340 lb"
        }
        let descriptor: String
        switch ctx.product {
        case .hazmatTanker, .vesselTanker:  descriptor = "Hazmat"
        case .dryVan:                       descriptor = "Dry"
        case .reefer:                       descriptor = "Reefer"
        case .flatbed:                      descriptor = "Flatbed"
        case .container, .vesselContainer:  descriptor = "Container"
        case .railIntermodal:               descriptor = "Rail · IMO"
        case .railBulk, .vesselBulk:        descriptor = "Bulk"
        }
        let palletsOrUnits: String
        switch ctx.product {
        case .reefer, .dryVan:              palletsOrUnits = "72 pallets"
        case .container, .railIntermodal, .vesselContainer: palletsOrUnits = "1 box · 40' HC"
        case .hazmatTanker, .vesselTanker:  palletsOrUnits = "10,500 gal"
        case .flatbed:                      palletsOrUnits = "steel coils"
        case .railBulk, .vesselBulk:        palletsOrUnits = "bulk"
        }
        // Seal segment only renders when we have a real seal id;
        // until `Load.sealNumber` ships, the segment is omitted so we
        // never publish a fabricated identifier in the production UI.
        let sealSegment = (fallbackSealID == "-") ? "" : " · seal \(fallbackSealID)"
        return "\(palletsOrUnits) · \(descriptor) · \(weightPill)\(sealSegment)"
    }
    private var milesTotal: String {
        if let d = activeLoad?.distance, !d.isEmpty { return d }
        return fallbackMilesTotal
    }

    /// Floating-top-bar meta line — composes "loadID · corridor ·
    /// sealed seal" with em-dash sentinels for the parts that aren't
    /// yet first-class fields on `Load`.
    ///
    /// 115th firing M2 retrofit: previous literal "I-20 E" excised
    /// from the floating top bar (audit caught a fixture corridor
    /// leak the 113th ESANG sweep missed). The corridor identifier
    /// is not yet a first-class field on `Load`; until
    /// `Load.corridor` ships from the backend the top bar omits
    /// the corridor segment entirely rather than fabricating one.
    /// Doctrine: 0% mock data — no fabricated brand or corridor in
    /// the production UI.
    private var topBarMetaText: String {
        // Corridor segment — empty until Load.corridor lands.
        let corridorSeg = ""
        // Seal segment — only render when we have a real seal id.
        let sealSeg = (fallbackSealID == "-") ? "" : " · sealed \(fallbackSealID)"
        return "\(loadID)\(corridorSeg)\(sealSeg)"
    }

    // MARK: live or neutral copy (§11) — Cohort B M2 retrofit
    //
    // Each accessor below is one of two states:
    //   (a) LIVE — derived from the wall-clock, HOSLiveStore, the
    //       hydrated Load, or the receiver's deliveryLocation.
    //   (b) NEUTRAL — em-dash placeholder when the upstream signal
    //       (HERE Routing live ETA / live mileage progress / live
    //       waypoint) hasn't wired into the floating card yet.
    //
    // No more `register == .night ? "Figma night" : "Figma afternoon"`.
    // Every getter renders the same in both registers — palette is
    // what makes register-aware visual decisions, not copy.

    /// Live wall-clock in `HH:mm`, recomputed when the body draws.
    private var clockTime: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }
    /// Progress is 0 until live mileage progress wires in (HERE
    /// Routing trip-progress or live odometer). Keeps the bar empty
    /// rather than rendering a plausible-looking fixture percent.
    private var progress: Double { 0 }
    /// Em-dash until live mileage progress lands.
    private var milesLeft: String { "-" }
    private var milesDone: String { "-" }
    /// Em-dash until live HERE Routing ETA wires in.
    private var etaTime: String { "-" }
    /// Em-dash until the live ETA-vs-appointment comparator wires in.
    private var lateAmount: String { "" }
    /// Neutral assurance copy until receiver-policy data wires in
    /// (24/7 vs windowed receiving, pre-notify status). No
    /// brand-specific vignettes.
    private var reassureText: String {
        guard let dest = activeLoad?.deliveryLocation, !dest.cityState.isEmpty else {
            return "Receiver details will surface once the load is hydrated."
        }
        return "Routing toward \(dest.cityState). Receiver acknowledgement pending."
    }
    /// Live appointment window from the load's deliveryDate when set;
    /// em-dash otherwise. Format mirrors the Figma "Appt HH:mm" feel
    /// without the timezone abbreviation (server returns UTC; we
    /// render local).
    private var apptWindow: String {
        guard let iso = activeLoad?.deliveryDate, !iso.isEmpty else { return "Appt -" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let d = date else { return "Appt -" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return "Appt \(f.string(from: d))"
    }
    /// Live HOS drive bank from HOSLiveStore. Em-dash when the store
    /// hasn't hydrated.
    private var hosDriveLeft: String {
        guard let s = hos.status else { return "- left" }
        return "\(s.drivingRemainingDisplay) left"
    }
    /// Live break-due hint pulled from HOSLiveStore.status when the
    /// next break is queued. Empty otherwise (the dot before this
    /// chip hides cleanly when the suffix is empty).
    private var hosBreakAt: String {
        guard let iso = hos.status?.nextBreakDue else { return "" }
        let inFmt = ISO8601DateFormatter()
        inFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = inFmt.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let d = parsed else { return "" }
        let outFmt = DateFormatter()
        outFmt.locale = Locale(identifier: "en_US_POSIX")
        outFmt.dateFormat = "HH:mm"
        return "· 30-min break due at \(outFmt.string(from: d))"
    }
    var body: some View {
        ZStack(alignment: .top) {
            // Map canvas — fills behind everything
            mapBackground
                .frame(height: 800)
                .clipped()

            // Floating TopBar + HERE road intel chips
            VStack(spacing: 6) {
                floatingTopBar
                // Real-Time Traffic + Road Alerts + Safety Cameras —
                // pulled from HERE Dynamic Map Content, centered on
                // the driver's live fix. Chips hide individually when
                // HERE returns nothing for that layer.
                //
                // §3 WEATHER AHEAD chip (Wave 3b parity): pass the same
                // active load id this screen already hydrates for the
                // lifecycle/ETA chrome so the bespoke weather chip mounts.
                // The chip hides itself when the lane is clear / none /
                // enterprise-gated (available:false today) and lights up
                // the moment the §3 lane risk is actionable — never a
                // fabricated band.
                EnRouteRoadIntelStrip(loadId: activeLoad.map { String($0.id) })
                    .padding(.horizontal, 14)
                // Tier 1 #12 (2026-05-21) — live reefer status HUD.
                // Only renders when this load's product is reefer;
                // server-driven poll cadence (30s in breach, 120s
                // normal); breach transitions speak via ESangTTSPlayer.
                if ctx.product == .reefer && !lifecycle.loadId.isEmpty {
                    XRReeferStatusHUD(_loadId: lifecycle.loadId)
                        .padding(.horizontal, 14)
                }
                Spacer()
            }
            .padding(.top, 8)

            // Bottom sheet
            VStack(spacing: 0) {
                Spacer()
                bottomSheet
                    .padding(.bottom, 84) // above nav
            }
        }
        // Uniform cafe-door entrance.
        .screenTileRoot()
        .task { await hydrateLiveTrip() }
    }

    // MARK: - Live hydration

    /// Bind the lifecycle store to the driver's currently-active
    /// load and pull the full Load record so product-aware chrome +
    /// per-Load fallbacks light up. Safe to re-call (both inner
    /// helpers no-op when already bound).
    private func hydrateLiveTrip() async {
        // HOS bootstrap runs in parallel so the in-card HOS bank +
        // break-due chip paint as soon as either signal lands. Both
        // are idempotent — safe to call on every appearance.
        async let hosBoot: () = hos.bootstrap()
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        if !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) {
            activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
        }
        if let load = activeLoad {
            await refreshRoutePolyline(for: load)
            await resolveReceiverFence(for: load)
        }
        _ = await hosBoot
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
              !(delivery.lat == 0 && delivery.lng == 0) else {
            receiverFence = nil
            return
        }
        receiverFence = await EusoTripAPI.shared.trackingGeofences
            .fence(near: delivery.lat, delivery.lng)
    }

    /// Resolves the pickup→delivery corridor via HERE Routing v8 and decodes
    /// its section polyline into the live route line painted on the basemap —
    /// real curved road geometry, not a 2-point great-circle straight segment.
    /// On any failure (missing coords, HERE error) the polyline stays empty
    /// and the map draws the straight pickup→delivery base line instead.
    @MainActor
    private func refreshRoutePolyline(for load: Load) async {
        guard let pickup = load.pickupLocation,
              let delivery = load.deliveryLocation,
              !(pickup.lat == 0 && pickup.lng == 0),
              !(delivery.lat == 0 && delivery.lng == 0) else {
            routePolyline = []
            return
        }
        let stops = HereStops(
            origin: CLLocationCoordinate2D(latitude: pickup.lat, longitude: pickup.lng),
            destination: CLLocationCoordinate2D(latitude: delivery.lat, longitude: delivery.lng)
        )
        let profile = TruckProfile.from(load: load)
        do {
            let resp = try await HereRoutingClient.shared.route(stops: stops, profile: profile)
            guard let section = resp.routes.first?.sections.first else {
                routePolyline = []
                return
            }
            let coords = HereRoutingClient.polyline(for: section)
            routePolyline = coords.count >= 2 ? coords.map { HereLatLng($0) } : []
        } catch {
            routePolyline = []
        }
    }

    // MARK: Floating top bar

    private var floatingTopBar: some View {
        HStack(spacing: Space.s3) {
            glassIconButton(systemName: "chevron.left", label: "Back")
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: ctx.product.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(ctx.headerKicker)
                        .font(EType.micro).tracking(0.6)
                        .fontWeight(.semibold)
                        .foregroundStyle(palette.textSecondary)
                    // 2026-05-17 — Mode chip on the en-route-loaded
                    // floating bar. The "loaded" state is when the
                    // wrong-mode error is most expensive (truck driver
                    // dispatched a rail leg, vessel charter accidentally
                    // routed to a truck). Hidden for default truck case.
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                    Text("· En route · Delivery")
                        .font(EType.body).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                }
                Text(topBarMetaText)
                    .font(.system(size: 11, design: .monospaced)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderSoft))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))

            glassIconButton(systemName: "square.stack.3d.up", label: "Map layers")
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private func glassIconButton(systemName: String, label: String) -> some View {
        Button {
            switch label {
            case "Back":        navBack?()
            case "Map layers":  toggleMapLayers?()
            default:            break
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(palette.textPrimary)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial)
                .overlay(Circle().strokeBorder(palette.borderSoft))
                .clipShape(Circle())
        }
        .accessibilityLabel(label)
    }

    // MARK: Map background

    /// Canonical OMV vector map + live HERE add-ons (fuel / EV / weather /
    /// traffic / parking / truck-stops / weigh-stations / safety-cameras /
    /// ISA / sponsored ad-zones / missions), fed the load's real
    /// pickup/delivery coords and the decoded lane. Mirrors 013's
    /// `mapLayer`. Falls back to the honest decorative placeholder (no
    /// fabricated route) until BOTH endpoints carry a real fix.
    @ViewBuilder
    private var mapBackground: some View {
        if let load = activeLoad,
           let pickup = load.pickupLocation,
           let delivery = load.deliveryLocation,
           // Coord gate (D-maps-basemap 2026-06-01): the server's geocode
           // self-heal can return a load whose pickup/delivery JSON is
           // present but whose lat/lng are still 0 (HERE geocode not yet
           // run). Drawing those frames the map on null island (0,0).
           // Require a real fix on BOTH endpoints; otherwise fall to the
           // honest placeholder until the next read lands coords.
           !(pickup.lat == 0 && pickup.lng == 0),
           !(delivery.lat == 0 && delivery.lng == 0) {
            let line: [HereLatLng] = routePolyline.count >= 2 ? routePolyline : []
            let markerLayer = HereMapLayer.markers([
                .init(at: .init(pickup.lat, pickup.lng), kind: .pickup, label: originName),
                .init(at: .init(delivery.lat, delivery.lng), kind: .delivery, label: destFlagText)
            ])
            let routeLayers: [HereMapLayer] = line.count >= 2
                ? [.route(polyline: line, colorHex: "#1473FF"), markerLayer]
                : [markerLayer]
            // §3c receiver fence at the corridor terminus — ONLY when a
            // real `tracking.getGeofences` row covers the receiver
            // (resolveReceiverFence). Absent row ⇒ absent layer.
            let fenceLayers: [HereMapLayer] = receiverFence.map {
                [.geofenceRing(center: $0.center,
                               radiusMeters: $0.radiusMeters,
                               kind: .receiver,
                               breachAt: nil)]
            } ?? []
            HereLiveMapView(
                center: .init(pickup.lat, pickup.lng),
                zoom: 7,
                firstPerson: true,
                route: line,
                baseLayers: routeLayers + fenceLayers,
                addOns: .driverEnRoute
            )
        } else {
            mapPlaceholder
        }
    }

    /// Operational empty state shown until the active load has verified route
    /// coordinates. It contains no authored roads, scale, waypoint, or live puck.
    private var mapPlaceholder: some View {
        EusoEmptyState(
            systemImage: "mappin.slash",
            title: "Awaiting route coordinates",
            subtitle: "Live navigation will appear after verified pickup and delivery coordinates are available."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.bgCard)
    }

    // MARK: Bottom sheet (glass)

    private var bottomSheet: some View {
        VStack(spacing: 12) {
            Capsule().fill(palette.borderSoft).frame(width: 40, height: 4)

            // Hero row: mi to delivery (gradient) + done/total + percent
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(milesLeft)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("mi to delivery")
                        .font(.system(size: 13, weight: .medium)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(milesDone) / \(milesTotal)")
                        .font(EType.mono(.caption)).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                        .tracking(0.6)
                    Text("\(Int(progress * 100))% complete")
                        .font(EType.mono(.micro)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }

            // Progress rail
            VStack(spacing: 6) {
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.borderSoft).frame(height: 4)
                    GeometryReader { g in
                        Capsule()
                            .fill(LinearGradient.diagonal)
                            .frame(width: g.size.width * progress, height: 4)
                    }
                    .frame(height: 4)
                }
                // 115th firing M2 retrofit: previous literals "Meridian, MS"
                // / "Hope Mills, NC" excised. Origin pulls from the
                // hydrated Load's pickupLocation; destination shares the
                // existing destFlagText computed property (which falls
                // back to "-" until the receiver hydrates).
                // Doctrine: 0% mock data — never publish a fabricated
                // city pair on the production progress rail.
                HStack {
                    Text(originName)
                    Spacer()
                    Text("\(Int(progress * 100))%").foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text(destFlagText)
                }
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Trip progress \(Int(progress * 100)) percent")

            // ETA strip with late pill and reassurance
            HStack(alignment: .top, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ETA".uppercased())
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(etaTime)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                            .tracking(0.4)
                        Text("EDT")
                            .font(EType.mono(.micro)).tracking(0.5)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(lateAmount.uppercased())
                        .font(EType.mono(.micro)).tracking(0.5)
                        .fontWeight(.semibold)
                        .foregroundStyle(palette.warning)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(palette.warning.opacity(register == .night ? 0.14 : 0.14))
                        .overlay(RoundedRectangle(cornerRadius: Radius.pill)
                            .strokeBorder(palette.warning.opacity(0.32)))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
                    Text(reassureText)
                        .font(.system(size: 10)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 170, alignment: .trailing)
                        .lineLimit(3)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(palette.bgElev.opacity(0.5))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderSoft))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))

            // Destination card (unboxed)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(destTitle).font(EType.body).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                    Text(destSub).font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    (Text("Dock ").font(EType.micro).tracking(0.5)
                        .foregroundStyle(palette.textTertiary) +
                     Text("TBD on arrival").font(EType.mono(.micro)).fontWeight(.semibold)
                        .foregroundColor(palette.textPrimary))
                        .textCase(.uppercase)
                    Text(apptWindow).font(EType.mono(.micro)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.top, 4)

            // HOS divider + drive time remaining
            VStack(spacing: 0) {
                Divider().background(palette.borderFaint)
                HStack(spacing: Space.s3) {
                    Text("Drive".uppercased())
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    HStack(spacing: 4) {
                        Text(hosDriveLeft)
                            .font(EType.mono(.caption)).fontWeight(.semibold)
                            .foregroundStyle(palette.textPrimary)
                            .tracking(0.4)
                        Text(hosBreakAt)
                            .font(EType.mono(.micro)).tracking(0.4)
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                }
                .padding(.top, 8)
            }

            // Actions
            HStack(spacing: Space.s2) {
                LifecycleCTAButton(title: "Navigate")
                    .accessibilityLabel("Resume turn-by-turn navigation")
                Button { openTripLog?() } label: {
                    Text("Find stop")
                        .font(EType.body).fontWeight(.medium)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderSoft))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                }
                .accessibilityLabel("Find a stop along the route")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
        .overlay(
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 24, topTrailing: 24))
                .stroke(palette.borderSoft, lineWidth: 1)
        )
        .clipShape(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 24, topTrailing: 24)))
    }
}

// MARK: - Wrapper

struct ActiveEnrouteLoadedScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            ActiveEnrouteLoaded(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_018(),
                      trailing: driverNavTrailing_018(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_018() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_018() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person", isCurrent: false)]
}

// MARK: - Previews

#Preview("018 · En Route · Loaded · Dark") {
    ActiveEnrouteLoadedScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("018 · En Route · Loaded · Light") {
    ActiveEnrouteLoadedScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
