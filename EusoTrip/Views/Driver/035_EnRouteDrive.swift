//
//  035_EnRouteDrive.swift
//  EusoTrip 2027 UI — Wave 2 (main haul · turn-by-turn)
//
//  Screen 035 · En Route Drive — the driver has departed the pickup (034)
//  and is now on the main haul. Turn-by-turn is live, the route polyline
//  is painted as the iridescent brand gradient, ESANG is quiet but ready,
//  the EusoShield in-transit binder is live and surfaced as a status chip,
//  and a hazmat reroute note confirms the tunnel/viaduct that was skipped
//  when the binder was written. The screen is map-first: the nav banner,
//  map controls, speed limit card, and bottom summary card all float on
//  the map canvas and the driver's only primary actions are:
//      • Exit (red) — stop nav + open exception flow
//      • Mute/voice — toggle ESANG voice coaching
//
//  Moment (Dark):  22:42 local, I-83 N after Curtis Bay. 1.4 mi to exit 4
//                  for Forrest Ave → Shrewsbury PA, then merge right onto
//                  I-83 N. Current speed 58 mph, limit 65. ETA 21:14, 52
//                  mi remaining, 1h 32m drive. HOS 6h 12m drive left.
//                  EusoShield $5M NH₃ binder live. Fort McHenry Tunnel
//                  skipped by routing.
//  Moment (Light): 10:14 local, US-30 W after Lancaster PA. 0.6 mi to
//                  exit 286 for Old Rt 30 → Gap PA, then continue US-30
//                  W. Current speed 53 mph, limit 55. ETA 10:42, 16 mi
//                  remaining, 28m drive. HOS 8h 48m drive left.
//                  EusoShield $2M gasoline binder live. Lincoln Hwy
//                  Viaduct skipped by routing.
//
//  93rd-firing visible-copy retrofit (Cohort A → Cohort B under M2):
//
//      Mirrors the 92nd-firing pass on 036 ESANG Smart Stop. All
//      register-keyed Figma fixtures (turn distances, exit chips,
//      lane shields, hard-coded speeds, ETA strings, hazmat reroute
//      vignettes, binder value vignettes) become live-or-neutral:
//
//        clockTime         — live wall-clock HH:mm
//        hosDriveLeft      — live HOSLiveStore.status.drivingRemaining
//        hazmatReroute     — already ctx-driven (hides on non-hazmat)
//        shieldValue       — already ctx-driven (per-product binder)
//        turnDistance/exit/headline/subhead/waypointShield
//                          — em-dash placeholders until HERE Routing
//                            turn-by-turn data lands in the screen
//        speedLimit/currentSpeed
//                          — em-dash placeholders until ELD/CoreLocation
//                            speed wires in
//        etaBig/etaSub     — em-dash placeholders until HERE Routing
//                            ETA lands
//        crossStreetLabels — em-dash placeholders (97th-firing finish).
//                            Was the last register-keyed text fixture
//                            on this screen ("West Aire Rd"/"Old
//                            Lincoln Hwy" etc.); awaiting HERE Routing
//                            cross-street annotations.
//
//      Result: in production with a live load + active HOS, the
//      screen renders live wall-clock, live HOS bank, ctx-driven
//      hazmat band, ctx-driven binder coverage, plus the live HERE
//      EnRouteRoadIntelStrip / HereCurrentLocationChip /
//      HereTypicalSpeedChip already attached. Without those signals,
//      the floating cards render em-dash placeholders — never
//      fixture data, never Figma vignettes.
//
//  Doctrine refs:
//    §2  nav invariants — no secondary chrome; BottomNav with Trips current.
//    §4.3 iridescent hairline → the route polyline IS the hairline on this
//         screen; gradient stroke, diagonal topLeading→bottomTrailing.
//    §6   dual register; both Dark + Light previews at the bottom.
//    §7   breathe density; map is the canvas, discs and cards float.
//    §8   Driver rhythm — turn banner → map → speed + summary card.
//    §11  visible copy is store-driven, not Figma-keyed. Cohort B under M2.
//
//  93rd firing (initial M2 retrofit).
//  97th firing (cross-street label finish — closes the last borderline
//               register-keyed text fixture; M2 strict 0 / borderline 0).
//

import SwiftUI
import CoreLocation
import Foundation

// MARK: - Screen

struct EnRouteDrive: View {
    @Environment(\.palette) var palette
    @Environment(\.lifecycleExit) private var lifecycleExit
    @Environment(\.driverToggleVoiceMute) private var toggleVoiceMute
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @StateObject private var hos = HOSLiveStore()
    @State private var activeLoad: Load?
    @State private var presentsOfflineRoadDesk = false
    @State private var appRadioSilenceLease: AppRadioSilenceLease?

    /// §3 per-load weather for the ACTIVE haul — the canonical
    /// `weather.forLoad` store (origin/dest realtime + LaneImpact peakLeg/
    /// riskTier/drivers). Drives the bespoke route-cell hazard band over the
    /// active route + the severe-cell ETA annotation. Honesty doctrine: the
    /// store keeps last-good + `isStale` on failure and the card is
    /// enterprise-gated server-side (expect `available:false` / nil today),
    /// so every weather affordance HIDES until a real actionable risk lands.
    @StateObject private var wx = WeatherCardStore()

    /// Decoded HERE Routing v8 section polyline for the main-haul leg
    /// (pickup → delivery, truck-aware). Drives the live route line on
    /// the HERE basemap. Empty until the route resolves — when empty
    /// the map falls back to the straight pickup→delivery base line so
    /// the corridor still renders honestly, never a fabricated path.
    @State private var routePolyline: [HereLatLng] = []

    /// §3c receiver fence on the main-haul corridor terminus (map-layer
    /// adoption 2026-06-10). Resolved from a REAL `tracking.getGeofences`
    /// row matched against the load's delivery coordinate — the ring is
    /// the row's own center + radius (meters). nil ⇒ no ring is painted
    /// (honest absence; the radius is never invented). Mirrors 013/018.
    @State private var receiverFence: TrackingGeofencesAPI.ResolvedFence?

    enum Register { case dark, light }
    let register: Register

    // Invariants (shared across both registers)
    private let loadBinderId = "ESO-89xxxxxxx"

    /// Vertical + product dispatcher. Hazmat reroute, binder coverage,
    /// and any product-aware copy on this screen reads from `ctx` so
    /// a dry-van load never paints a tunnel-skip banner and a reefer
    /// load surfaces cold-chain trace instead of an NH3 binder figure.
    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: live or neutral copy (§11) — 93rd firing M2 retrofit
    //
    // Each accessor below is one of two states:
    //   (a) LIVE — derived from the wall-clock, HOSLiveStore, ctx, or
    //       a HERE strip already attached to the screen.
    //   (b) NEUTRAL — em-dash placeholder when the upstream signal
    //       (HERE Routing turn-by-turn / ELD speed / live ETA) hasn't
    //       wired into the floating card yet.
    //
    // No more `register == .dark ? "Figma dark" : "Figma light"`. The
    // screen looks identical in both registers — the palette is what
    // makes register-aware visual decisions, not copy.

    /// Live wall-clock in `HH:mm`, recomputed when the body draws.
    private var clockTime: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }

    /// Em-dash until HERE Routing turn-by-turn lands in the card.
    private var turnDistance: String         { "-" }
    private var turnDistanceUnit: String     { "mi" }
    /// Em-dash until HERE Routing returns the next exit / waypoint.
    private var exitChip: String             { "-" }
    private var turnHeadline: String         { "Awaiting live route" }
    private var turnSubhead: String          { "TURN-BY-TURN PENDING" }
    private var thenPillText: String         { "THEN" }
    private var waypointShield: String       { "-" }

    /// Hazmat reroute callout — ctx-driven. Returns empty for
    /// non-hazmat loads so the band hides. Empty when no live load
    /// either (the band is meaningless without a hazmat context).
    private var hazmatReroute: String { ctx.enRouteHazmatBand }

    /// Em-dash until ELD speed signal wires in.
    private var speedLimit: String   { "-" }
    private var currentSpeed: String { "-" }
    /// Em-dash until HERE Routing ETA wires into the bottom card.
    private var etaBig: String       { "-" }
    private var etaSub: String       { "AWAITING LIVE ETA" }

    /// Live HOS drive bank from HOSLiveStore. `drivingRemaining` is
    /// hours-remaining-in-the-11h drive window (Double). Uses the
    /// model's own `drivingRemainingDisplay` formatter so the same
    /// "Xh YYm" string the HOS dashboard renders shows up here.
    /// Em-dash until the store hydrates a status snapshot.
    private var hosDriveLeft: String {
        hos.status?.drivingRemainingDisplay ?? "-"
    }

    /// In-transit binder summary — product-aware at runtime, neutral
    /// "binder" placeholder when no live load is hydrated.
    private var shieldValue: String {
        guard activeLoad != nil else { return "BINDER -" }
        return ctx.enRouteBinderValue
    }

    // Ping position, normalized to the map frame
    private var pingX: CGFloat { register == .dark ? 0.50 : 0.48 }
    private var pingY: CGFloat { register == .dark ? 0.68 : 0.66 }

    // MARK: §3 weather — live or honest-empty (Waves 1-3b-server)
    //
    // Every weather affordance below reads from `wx.card` (weather.forLoad).
    // Weather is enterprise-gated server-side, so the card arrives with
    // `available:false` / a `LaneImpact` whose `riskTier == .none` until the
    // key lands — and EVERY accessor returns nil/false in that state so the
    // band + chip + ETA pill stay hidden. No fabricated risk, ever.

    /// The §3 LaneImpact for the active load — only when the server marked
    /// the per-load card AND the lane impact `available` and the tier is
    /// actionable (watch+). nil ⇒ no band, no pill (honest absence).
    private var activeLaneImpact: WeatherForLoad.LaneImpact? {
        guard let card = wx.card, card.available, card.hasLaneRisk else { return nil }
        return card.laneImpact
    }

    /// The §3 risk tier driving the band intensity + ETA pill — nil when
    /// no actionable lane risk is live.
    private var weatherRiskTier: LaneRiskTier? {
        activeLaneImpact.map { $0.riskTier }
    }

    /// The peak leg the route reduction surfaced ("I-83 N · 4 PM") — the
    /// band labels itself from this, never a fabricated segment.
    private var weatherPeakLeg: WeatherForLoad.LaneImpact.PeakLeg? {
        activeLaneImpact?.peakLeg
    }

    /// True when a §3 driver indicates a freezing / wet-pavement hazard
    /// (ICE PELLETS / FREEZING / SLEET / wet PRECIP) — drives the
    /// ice/wet-pavement-ahead warning chip. Reads the server-formatted
    /// driver fields/values verbatim; absent ⇒ chip hidden.
    private var pavementHazard: PavementHazard? {
        guard let drivers = activeLaneImpact?.drivers else { return nil }
        for d in drivers {
            let f = d.field.lowercased()
            let v = d.value.lowercased()
            // Em-dash / empty values never trip the chip (honest).
            let hasValue = !v.isEmpty && v != "—" && v != "-"
            if (f.contains("ice") || f.contains("freez") || f.contains("sleet")
                || v.contains("ice") || v.contains("freez") || v.contains("sleet")), hasValue {
                return .ice
            }
            if (f.contains("precip") || f.contains("rain")), hasValue,
               weatherRiskTier?.isActionable == true {
                return .wet
            }
        }
        return nil
    }

    /// Hazard kind for the pavement-ahead warning chip.
    private enum PavementHazard {
        case ice, wet
        var label: String { self == .ice ? "ICE AHEAD" : "WET PAVEMENT AHEAD" }
        var glyph: WeatherIcons.Glyph { self == .ice ? .sleet : .rain }
        var tone: Color { self == .ice ? Brand.info : WeatherV3.drop }
    }

    /// A SEVERE / ELEVATED cell crossing the NEXT leg → the ETA card gets a
    /// bespoke weather-risk pill. nil ⇒ no annotation (watch tier stays on
    /// the band only; the ETA pill is reserved for the loudest tiers).
    private var etaWeatherFlag: (label: String, tone: Color)? {
        guard let li = activeLaneImpact else { return nil }
        switch li.riskTier {
        case .severe, .elevated:
            let head = (li.headline ?? "").trimmingCharacters(in: .whitespaces)
            return (head.isEmpty ? "WEATHER ON NEXT LEG" : head.uppercased(),
                    li.riskTier.color)
        case .watch, .none:
            return nil
        }
    }

    var body: some View {
        Group {
            if presentsOfflineRoadDesk {
                palette.bgPage
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            } else {
                ZStack(alignment: .top) {
                    // Map canvas — fills the whole screen behind every overlay
                    mapBackground
                        .frame(height: 760)
                        .clipped()

                    // Floating top: turn banner + THEN preview pill + hazmat band + road intel
                    VStack(spacing: 10) {
                        turnBanner
                            .padding(.horizontal, 14)
                        thenPreviewPill
                            .padding(.leading, 22)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !hazmatReroute.isEmpty {
                            hazmatBand
                                .padding(.horizontal, 14)
                        }
                        // §3 route-cell weather band — a translucent hazard band over
                        // the active load's peak leg + an ice/wet-pavement warning
                        // chip when the §3 drivers indicate it. Renders ONLY on a real
                        // actionable lane risk (weatherRiskTier != nil); hidden when
                        // the card is enterprise-gated / clear (honest absence).
                        if let tier = weatherRiskTier {
                            weatherRouteBand(tier: tier)
                                .padding(.horizontal, 14)
                        }
                        // HERE Dynamic Map Content — live Real-Time Traffic,
                        // Road Alerts (incidents), and Safety Cameras. Chips
                        // hide per-layer when HERE returns nothing. The active
                        // load id also feeds the §3 "WEATHER AHEAD" 4th chip
                        // (hidden when the lane is clear / enterprise-gated).
                        EnRouteRoadIntelStrip(loadId: activeLoad.map { String($0.id) })
                            .padding(.horizontal, 14)
                        Spacer()
                    }
                    .padding(.top, 8)

                    // Right rail of map control discs
                    VStack {
                        Spacer().frame(height: 260)
                        HStack {
                            Spacer()
                            mapControlRail
                                .padding(.trailing, 14)
                        }
                        Spacer()
                    }

                    // Speed limit + speedometer (bottom-left over the map)
                    VStack {
                        Spacer()
                        HStack(alignment: .bottom) {
                            speedCluster
                                .padding(.leading, 14)
                                .padding(.bottom, 6)
                            Spacer()
                        }
                        .padding(.bottom, 160)
                    }

                    // Bottom summary card (ETA + mute + Exit + HOS/Shield chips)
                    VStack(spacing: 6) {
                        Spacer()
                        // HERE reverse-geocode chip — surfaces the live cross-
                        // street + city under the summary so the driver sees
                        // where ESANG actually thinks they are. Hides cleanly
                        // when location is denied or HERE returns empty.
                        HereCurrentLocationChip()
                            .padding(.horizontal, 14)
                        // HERE Traffic Analytics — typical speed for the live
                        // viewport, anchoring the driver's self-pacing against
                        // the corridor's historical pattern.
                        HereTypicalSpeedChip()
                            .padding(.horizontal, 14)
                        bottomSummaryCard
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8) // nav clearance handled by Shell
                    }
                }
                .eusoRefreshTask { await hydrateLiveTrip() }
                // The online subtree owns this poll. Replacing the subtree with
                // the radio-silent desk cancels its refresh task, unmounts every
                // online HERE child, and unregisters foreground refreshes.
                .onDisappear { wx.stop() }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("En route drive")
        // Uniform cafe-door entrance.
        .screenTileRoot()
        .fullScreenCover(
            isPresented: $presentsOfflineRoadDesk,
            onDismiss: releaseAppRadioSilenceLease
        ) {
            NavigationStack {
                Group {
                    if let composition = OfflineMapProductionComposition.shared {
                        OfflineRoadJourneyView(composition: composition)
                    } else {
                        EusoEmptyState(
                            systemImage: "map.fill",
                            title: "Offline navigation unavailable",
                            subtitle: "This app version could not install the approved native offline composition. No online substitute was opened."
                        )
                        .padding(24)
                        .navigationTitle("Offline journey")
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Return to live map") {
                            Task { @MainActor in
                                await OfflineMapProductionComposition.shared?
                                    .stopNavigation()
                                releaseAppRadioSilenceLease()
                                presentsOfflineRoadDesk = false
                            }
                        }
                    }
                }
            }
            .interactiveDismissDisabled()
        }
    }

    private func presentOfflineRoadDesk() {
        if appRadioSilenceLease == nil {
            appRadioSilenceLease = AppRadioSilenceCoordinator.shared.acquire(
                reason: .offlineRoadJourney
            )
        }
        presentsOfflineRoadDesk = true
    }

    private func releaseAppRadioSilenceLease() {
        guard let lease = appRadioSilenceLease else { return }
        AppRadioSilenceCoordinator.shared.release(lease)
        appRadioSilenceLease = nil
    }

    private func hydrateLiveTrip() async {
        // HOS bootstrap runs in parallel with the lifecycle/load hydrate
        // so the bottom-card HOS pill paints as soon as either signal
        // lands. Both are idempotent — safe to call on every appearance.
        async let hosBoot: () = hos.bootstrap()
        await lifecycle.hydrateActiveLoad()
        guard !Task.isCancelled else { return }
        await lifecycle.refresh()
        guard !Task.isCancelled else { return }
        if !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) {
            activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
            guard !Task.isCancelled else { return }
        }
        if let load = activeLoad {
            await refreshRoutePolyline(for: load)
            guard !Task.isCancelled else { return }
            await resolveReceiverFence(for: load)
            guard !Task.isCancelled else { return }
            // §3 weather for the active haul — in-progress refresh (~30s).
            // Idempotent: startAutoRefresh stops any prior poll first.
            wx.startAutoRefresh(loadId: String(load.id), inProgress: true)
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

    /// Resolves the truck-aware main-haul corridor (pickup → delivery)
    /// via HERE Routing v8 and decodes its section polyline into the
    /// live route line painted on the basemap. Mirrors 013's live-leg
    /// pattern. On any failure (missing coords, HERE error) the polyline
    /// stays empty and the map renders the straight pickup→delivery base
    /// line instead — never a fabricated path.
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
            // Honest failure: leave the polyline empty so the map draws
            // the straight pickup→delivery base line, not a stale path.
            routePolyline = []
        }
    }

    // MARK: Turn-by-turn banner

    @ViewBuilder
    private var turnBanner: some View {
        if let composition = OfflineMapProductionComposition.shared {
            OfflineDriverTurnBanner(composition: composition) {
                legacyTurnBanner
            }
        } else {
            legacyTurnBanner
        }
    }

    private var legacyTurnBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            // Big right-turn arrow
            Image(systemName: "arrow.turn.up.right")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

            // Distance + exit chip + headline + subhead
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(turnDistance)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.white)
                        Text(turnDistanceUnit)
                            .font(EType.mono(.caption)).tracking(0.5)
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    Text(exitChip)
                        .font(EType.mono(.micro)).tracking(0.6)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.white.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                Text(turnHeadline)
                    .font(EType.body).fontWeight(.semibold)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(turnSubhead)
                    .font(EType.mono(.micro)).tracking(0.6)
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Trailing ESANG orb — small, gradient
            Circle()
                .fill(LinearGradient.diagonal)
                .frame(width: 36, height: 36)
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: Brand.magenta.opacity(0.45), radius: 10, y: 4)
                .accessibilityLabel("ESANG AI")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(LinearGradient.diagonal)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        // Doctrine §2.1 — dual-shadow brand glow. The turn-card surface
        // uses LinearGradient.diagonal (blue→magenta) for the fill, so the
        // drop shadow is split into blue (-x) + magenta (+x) halves to
        // carry the same gradient feel through the shadow as through
        // the fill. Mirrors the pattern at DriverTabPanes:733/895 and
        // activeTripMap:426-429.
        .shadow(color: Brand.blue.opacity(0.32), radius: 16, x: -2, y: 6)
        .shadow(color: Brand.magenta.opacity(0.32), radius: 16, x: 2, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("In \(turnDistance) miles, \(turnHeadline), \(turnSubhead)")
    }

    // MARK: THEN preview pill

    private var thenPreviewPill: some View {
        HStack(spacing: 6) {
            Text(thenPillText)
                .font(EType.mono(.micro)).tracking(0.8)
                .foregroundStyle(palette.textSecondary)
            Image(systemName: "arrow.turn.up.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.pill)
                .strokeBorder(palette.borderSoft)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
    }

    // MARK: Hazmat reroute band

    private var hazmatBand: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white)
            Text(hazmatReroute)
                .font(EType.mono(.micro)).tracking(0.8)
                .fontWeight(.semibold)
                .foregroundStyle(Color.white)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(
            LinearGradient(
                colors: [Brand.danger, Brand.warning],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.pill)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
        .shadow(color: Brand.danger.opacity(0.28), radius: 10, y: 3)
    }

    // MARK: §3 route-cell weather band (over the active load route)

    /// A bespoke floating panel that draws the §3 weather hazard CROSSING
    /// the active route — the same showpiece idiom as `RouteCellDiagram`
    /// (a curved road with a translucent hazard column over the peak leg),
    /// rendered inline here over the map canvas. The band intensity tracks
    /// `tier` (severe sits mid-lane, lesser tiers shift toward the
    /// destination so it reads "later"), the peak label comes straight from
    /// the §3 `peakLeg`, and an ice/wet-pavement-ahead chip surfaces when
    /// the §3 drivers indicate freezing / wet pavement. Every glyph is a
    /// `WeatherIcons` glyph — zero SF Symbols. Honest: the caller only
    /// mounts this when `weatherRiskTier != nil`.
    @ViewBuilder
    private func weatherRouteBand(tier: LaneRiskTier) -> some View {
        let bandColor = tier == .severe ? WeatherV3.danger
            : (tier == .watch ? Brand.warning : WeatherV3.danger.opacity(0.85))
        VStack(alignment: .leading, spacing: 7) {
            // header row — route glyph · WEATHER ON ROUTE · tier pill
            HStack(spacing: 7) {
                WeatherIcons.utility(.route, size: 13, tint: WeatherV3.nodeOrigin)
                Text("WEATHER ON ROUTE")
                    .font(EType.mono(.micro)).tracking(0.8)
                    .fontWeight(.heavy)
                    .foregroundStyle(.white.opacity(0.82))
                Spacer(minLength: 4)
                Text(tier.rawValue.uppercased())
                    .font(EType.mono(.micro)).tracking(0.6)
                    .fontWeight(.heavy)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(bandColor.opacity(0.22)))
                    .overlay(Capsule().strokeBorder(bandColor.opacity(0.5), lineWidth: 1))
            }

            // the hazard band crossing the route — a curved road with the
            // translucent weather column over the peak leg + the §3 peak
            // label drawn over the band.
            weatherBandCanvas(tier: tier)
                .frame(height: 46)

            // ice / wet-pavement-ahead warning chip — only when a §3 driver
            // indicates it (pavementHazard != nil); otherwise hidden.
            if let hazard = pavementHazard {
                HStack(spacing: 6) {
                    WeatherGlyph(kind: hazard.glyph)
                        .frame(width: 16, height: 16)
                    Text(hazard.label)
                        .font(EType.mono(.micro)).tracking(0.7)
                        .fontWeight(.heavy)
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(hazard.tone.opacity(0.18)))
                .overlay(Capsule().strokeBorder(hazard.tone.opacity(0.55), lineWidth: 1))
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(bandColor.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .shadow(color: bandColor.opacity(0.22), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(weatherBandA11y(tier: tier))
    }

    /// The Canvas showpiece — a curved route stroke with a translucent
    /// vertical hazard column over the peak leg + origin/dest nodes + a
    /// peak marker. Mirrors `RouteCellDiagram`'s truck idiom on a compact
    /// 320×46 stage. Pure geometry + the live tier — no fabricated data.
    private func weatherBandCanvas(tier: LaneRiskTier) -> some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x / 320.0 * w, y: y / 46.0 * h)
            }
            // band center tracks the tier: severe mid-lane, lesser later.
            let bandX: CGFloat = {
                switch tier {
                case .severe:   return 178
                case .elevated: return 206
                case .watch:    return 232
                case .none:     return 256
                }
            }()
            let bandColor = tier == .watch ? Brand.warning : WeatherV3.danger

            // translucent hazard column (soft left→right fade, glows mid).
            let bw: CGFloat = 46 / 320.0 * w
            let bx = bandX / 320.0 * w
            ctx.fill(
                Path(CGRect(x: bx - bw / 2, y: 0, width: bw, height: h)),
                with: .linearGradient(
                    Gradient(colors: [bandColor.opacity(0), bandColor.opacity(0.5), bandColor.opacity(0)]),
                    startPoint: CGPoint(x: bx - bw / 2, y: 0),
                    endPoint: CGPoint(x: bx + bw / 2, y: 0)))

            // route curve — base stroke + dashed iridescent centerline.
            var road = Path()
            road.move(to: P(20, 34))
            road.addCurve(to: P(300, 16), control1: P(110, 8), control2: P(160, 40))
            ctx.stroke(road, with: .color(Color.white.opacity(0.18)),
                       style: StrokeStyle(lineWidth: 6, lineCap: .round))
            ctx.stroke(road, with: .linearGradient(
                Gradient(colors: [WeatherV3.auroraA, WeatherV3.auroraB, WeatherV3.auroraC]),
                startPoint: .zero, endPoint: CGPoint(x: w, y: 0)),
                style: StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [1, 7]))

            // origin + dest nodes.
            func node(_ p: CGPoint, ring: Color) {
                let r: CGFloat = 4
                let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(.black.opacity(0.6)))
                ctx.stroke(Path(ellipseIn: rect), with: .color(ring), style: StrokeStyle(lineWidth: 2))
            }
            node(P(20, 34), ring: WeatherV3.nodeOrigin)
            node(P(300, 16), ring: WeatherV3.nodeDest)

            // peak marker on the band.
            let mk = P(bandX, 26)
            let mr: CGFloat = 5
            let mrect = CGRect(x: mk.x - mr, y: mk.y - mr, width: mr * 2, height: mr * 2)
            ctx.fill(Path(ellipseIn: mrect), with: .color(bandColor))
            ctx.stroke(Path(ellipseIn: mrect), with: .color(.white), style: StrokeStyle(lineWidth: 1.6))

            // §3 peak-leg label over the band — real peakLeg only.
            if let peak = weatherPeakLeg {
                let raw = peak.time.isEmpty ? peak.label : peak.time
                let text = raw.trimmingCharacters(in: .whitespaces).uppercased()
                if !text.isEmpty {
                    ctx.draw(
                        Text(text).font(.system(size: 10, weight: .heavy))
                            .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.82)),
                        at: P(bandX, 8), anchor: .center)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func weatherBandA11y(tier: LaneRiskTier) -> String {
        var s = "Weather on route, \(tier.rawValue) risk"
        if let peak = weatherPeakLeg {
            let p = [peak.label, peak.time]
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            if !p.isEmpty { s += ", peak leg \(p)" }
        }
        if let hazard = pavementHazard { s += ", \(hazard.label.lowercased())" }
        return s
    }

    // MARK: Map control rail (right edge)

    private var mapControlRail: some View {
        VStack(spacing: 10) {
            Button {
                presentOfflineRoadDesk()
            } label: {
                glassDisc("location.north.fill", tinted: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open radio-silent offline journey")
            .accessibilityHint("Opens installed-data search, covered truck routing, and native offline guidance.")

            Button {
                toggleVoiceMute?()
            } label: {
                glassDisc("speaker.wave.2.fill")
            }
            .buttonStyle(.plain)
            .disabled(toggleVoiceMute == nil)
            .accessibilityLabel("Toggle voice coaching")
        }
    }

    private func glassDisc(
        _ systemName: String,
        tinted: Bool = false
    ) -> some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
            Circle()
                .strokeBorder(palette.borderSoft, lineWidth: 1)
            if tinted {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .frame(width: 40, height: 40)
    }

    // MARK: Speed limit + speedometer

    private var speedCluster: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // Speed limit sign (white card, black text)
            VStack(spacing: 2) {
                Text("LIMIT")
                    .font(EType.mono(.micro)).tracking(0.7)
                    .foregroundStyle(Color.black.opacity(0.7))
                Text(speedLimit)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.black)
            }
            .frame(width: 54, height: 68)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .strokeBorder(Color.black.opacity(0.22), lineWidth: 3)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            .accessibilityLabel("Speed limit \(speedLimit) miles per hour")

            // Live speed (big numeric + MPH)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(currentSpeed)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                Text("MPH")
                    .font(EType.mono(.micro)).tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(palette.borderSoft)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .accessibilityLabel("Current speed \(currentSpeed) miles per hour")
        }
    }

    // MARK: Bottom summary card

    private var bottomSummaryCard: some View {
        VStack(spacing: 10) {
            // ETA row
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(etaBig)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(etaSub)
                        .font(EType.mono(.micro)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                    // §3 severe/elevated-cell annotation — a bespoke weather
                    // pill when a loud cell crosses the next leg. The
                    // headline reads straight from the §3 LaneImpact; hidden
                    // when no severe/elevated risk is live (honest).
                    if let flag = etaWeatherFlag {
                        HStack(spacing: 5) {
                            WeatherIcons.utility(.alert, size: 11, tint: flag.tone)
                            Text(flag.label)
                                .font(EType.mono(.micro)).tracking(0.5)
                                .fontWeight(.heavy)
                                .foregroundStyle(flag.tone)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(flag.tone.opacity(0.14)))
                        .overlay(Capsule().strokeBorder(flag.tone.opacity(0.45), lineWidth: 0.5))
                        .padding(.top, 3)
                        .accessibilityLabel("Weather risk on the next leg: \(flag.label)")
                    }
                }
                Spacer()
                // Voice mute toggle
                Button { toggleVoiceMute?() } label: {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(palette.bgCardSoft)
                        .overlay(
                            Circle().strokeBorder(palette.borderSoft)
                        )
                        .clipShape(Circle())
                }
                .accessibilityLabel("Mute voice coaching")

                // Exit (red)
                Button { lifecycleExit?() } label: {
                    Text("Exit")
                        .font(EType.body).fontWeight(.semibold)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(Brand.danger)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
                        .shadow(color: Brand.danger.opacity(0.35), radius: 8, y: 3)
                }
                .accessibilityLabel("Exit navigation")
            }

            // Status chips row
            HStack(spacing: 8) {
                statusChip(
                    kicker: "HOS DRIVE LEFT",
                    value: hosDriveLeft,
                    tone: .success
                )
                statusChip(
                    kicker: "EUSOSHIELD LIVE",
                    value: shieldValue,
                    tone: .brand
                )
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderSoft)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
    }

    private enum ChipTone { case success, brand }

    @ViewBuilder
    private func statusChip(kicker: String, value: String, tone: ChipTone) -> some View {
        let strokeStyle: AnyShapeStyle = (tone == .brand)
            ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.55))
            : AnyShapeStyle(Brand.success.opacity(0.45))
        let kickerColor: Color = (tone == .brand) ? palette.textSecondary : Brand.success
        let valueColor: AnyShapeStyle = (tone == .brand)
            ? AnyShapeStyle(LinearGradient.diagonal)
            : AnyShapeStyle(palette.textPrimary)

        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kicker)
                    .font(EType.mono(.micro)).tracking(0.7)
                    .foregroundStyle(kickerColor)
                Text(value)
                    .font(EType.bodyStrong)
                    .foregroundStyle(valueColor)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(strokeStyle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: Map background

    /// Live HERE basemap gate (D-maps mandate · mirrors 013). When a live
    /// load carries real pickup + delivery coordinates, the map is the
    /// canonical OMV vector `HereLiveMapView` fed the load endpoints and
    /// the decoded HERE Routing v8 section polyline — the same live route
    /// 013 paints, NOT a decorative canvas. The coord gate matches 013:
    /// the server's geocode self-heal can return a load whose location
    /// JSON is present but whose lat/lng are still 0; drawing those frames
    /// the map on null island, so we require a real fix on BOTH endpoints
    /// and otherwise fall back to the honest placeholder canvas below.
    @ViewBuilder
    private var mapBackground: some View {
        if let load = activeLoad,
           let pickup = load.pickupLocation,
           let delivery = load.deliveryLocation,
           !(pickup.lat == 0 && pickup.lng == 0),
           !(delivery.lat == 0 && delivery.lng == 0) {
            // Prefer the decoded HERE section polyline (real road geometry);
            // fall back to the straight pickup→delivery line until it lands.
            let line: [HereLatLng] = routePolyline.count >= 2
                ? routePolyline
                : [HereLatLng(pickup.lat, pickup.lng), HereLatLng(delivery.lat, delivery.lng)]
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
                baseLayers: [
                    .route(polyline: line, colorHex: "#1473FF"),
                    .markers([
                        .init(at: .init(pickup.lat, pickup.lng), kind: .pickup,
                              label: pickup.optionalMapDisplayLabel),
                        .init(at: .init(delivery.lat, delivery.lng), kind: .delivery,
                              label: delivery.optionalMapDisplayLabel)
                    ])
                ] + fenceLayers,
                addOns: .driverEnRoute
            )
        } else {
            mapPlaceholder
        }
    }

    /// Neutral-grid placeholder shown only when no live load with real
    /// coordinates is on file (previews + first-run). It carries NO
    /// business data and paints NO route — just the register backdrop,
    /// the faint street grid, em-dash labels, and an honest "awaiting
    /// route" seam (W13 hygiene · E2E audit §4 · 2026-06-10; the prior
    /// decorative corridor + arrowheads read as a live route).
    private var mapPlaceholder: some View {
        ZStack {
            // Backdrop — register-specific ground color
            Rectangle()
                .fill(register == .dark
                      ? AnyShapeStyle(
                        RadialGradient(
                            colors: [Color(hex: "#0C1322"), Color(hex: "#080B13"), Color(hex: "#05060A")],
                            center: .init(x: 0.55, y: 0.45),
                            startRadius: 80, endRadius: 720
                        )
                      )
                      : AnyShapeStyle(
                        LinearGradient(
                            colors: [Color(hex: "#EEE7DC"), Color(hex: "#F1EBE1"), Color(hex: "#F5F1E8")],
                            startPoint: .top, endPoint: .bottom
                        )
                      )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Faint street grid — horizontal + vertical streets
            Canvas { ctx, size in
                let strokeColor: Color = register == .dark
                    ? Color.white.opacity(0.035)
                    : Color.black.opacity(0.05)
                let step: CGFloat = 52
                var x: CGFloat = 0
                while x < size.width {
                    ctx.stroke(Path { $0.move(to: .init(x: x, y: 0)); $0.addLine(to: .init(x: x, y: size.height)) },
                               with: .color(strokeColor), lineWidth: 1)
                    x += step
                }
                var y: CGFloat = 0
                while y < size.height {
                    ctx.stroke(Path { $0.move(to: .init(x: 0, y: y)); $0.addLine(to: .init(x: size.width, y: y)) },
                               with: .color(strokeColor), lineWidth: 1)
                    y += step
                }
            }

            // Cross-street labels scattered across the placeholder grid.
            // M2 cleanup (97th firing): register-keyed fixtures (e.g. "West Aire Rd"/"Old Lincoln Hwy")
            // were inherited Figma vignettes — replaced with em-dash neutrals until HERE Routing
            // turn-by-turn cross-street labels land for this screen. The four positions are
            // preserved so the placeholder keeps its visual rhythm.
            GeometryReader { geo in
                crossStreetLabel(text: "-",
                                 at: .init(x: geo.size.width * 0.18, y: geo.size.height * 0.18))
                crossStreetLabel(text: "-",
                                 at: .init(x: geo.size.width * 0.78, y: geo.size.height * 0.40))
                crossStreetLabel(text: "-",
                                 at: .init(x: geo.size.width * 0.20, y: geo.size.height * 0.56))
                crossStreetLabel(text: "-",
                                 at: .init(x: geo.size.width * 0.78, y: geo.size.height * 0.64))
            }

            // W13 hygiene (E2E audit §4 maps · 2026-06-10): the decorative
            // fake route corridor (iridescent hairlines + direction
            // arrowheads) is gone — a placeholder must never paint
            // something that reads as a live route (zero-fallback
            // doctrine, matches 018's honest-seam treatment). The neutral
            // grid above stays; an honest "awaiting route" seam below
            // says exactly why there is no corridor yet.
            GeometryReader { geo in
                HStack(spacing: 5) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 9, weight: .bold))
                    Text("AWAITING ROUTE")
                        .font(EType.mono(.micro)).tracking(0.6)
                }
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(palette.borderFaint))
                .clipShape(Capsule())
                .position(x: geo.size.width * 0.50, y: geo.size.height * 0.46)
                .accessibilityLabel("Awaiting route — the live corridor appears once this load's coordinates are on file")
            }

            // Interstate shield waypoint pill (center of the map)
            GeometryReader { geo in
                Text(waypointShield)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.black.opacity(0.4), lineWidth: 2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                    .position(x: geo.size.width * 0.50, y: geo.size.height * 0.30)
            }

            // Current-position ping
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(LinearGradient.diagonal.opacity(0.25))
                        .frame(width: 42, height: 42)
                    Circle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle().strokeBorder(
                                register == .dark ? palette.bgPage : Color.white,
                                lineWidth: 2.5)
                        )
                        .shadow(color: Brand.blue.opacity(register == .dark ? 0.55 : 0.30), radius: 12)
                    // Heading chevron
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.white)
                }
                .position(x: geo.size.width * pingX, y: geo.size.height * pingY)
            }
        }
    }

    @ViewBuilder
    private func crossStreetLabel(text: String, at point: CGPoint) -> some View {
        Text(text)
            .font(EType.mono(.micro)).tracking(0.3)
            .foregroundStyle(palette.textTertiary)
            .position(point)
    }
}

@MainActor
private struct OfflineDriverTurnBanner<Fallback: View>: View {
    @ObservedObject var composition: OfflineMapProductionComposition
    private let fallback: () -> Fallback

    init(
        composition: OfflineMapProductionComposition,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) {
        self.composition = composition
        self.fallback = fallback
    }

    var body: some View {
        if isActive {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: stateSymbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

                VStack(alignment: .leading, spacing: 4) {
                    Text("RADIO-SILENT GUIDANCE")
                        .font(EType.mono(.micro))
                        .tracking(0.7)
                        .foregroundStyle(Color.white.opacity(0.76))
                    if let maneuver = composition.currentNavigationManeuver {
                        Text(maneuver.instruction)
                            .font(EType.body.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .lineLimit(2)
                        Text("In \(distance(maneuver.distanceMeters))")
                            .font(EType.mono(.caption))
                            .foregroundStyle(Color.white.opacity(0.88))
                    } else {
                        Text(stateTitle)
                            .font(EType.body.weight(.semibold))
                            .foregroundStyle(Color.white)
                    }
                    if let deviation = composition.lastNavigationDeviation {
                        Text("Off route · \(Int(deviation.crossTrackMeters.rounded())) m · \(deviation.consecutiveSamples) fixes")
                            .font(EType.mono(.micro))
                            .foregroundStyle(Color.white.opacity(0.82))
                    } else {
                        Text(coverageTitle)
                            .font(EType.mono(.micro))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Circle())
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(LinearGradient.diagonal)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: Brand.blue.opacity(0.32), radius: 16, x: -2, y: 6)
            .shadow(color: Brand.magenta.opacity(0.32), radius: 16, x: 2, y: 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
        } else {
            fallback()
        }
    }

    private var isActive: Bool {
        switch composition.navigationState {
        case .starting, .navigating, .paused, .offRoute, .rerouting:
            return true
        case .idle, .arrived, .stopped, .failed:
            return false
        }
    }

    private var stateSymbol: String {
        switch composition.navigationState {
        case .offRoute, .rerouting: return "arrow.triangle.branch"
        case .paused: return "pause.fill"
        case .starting: return "hourglass"
        case .navigating: return "location.north.fill"
        case .idle, .arrived, .stopped, .failed: return "location.slash"
        }
    }

    private var stateTitle: String {
        switch composition.navigationState {
        case .starting: return "Starting native offline guidance"
        case .navigating: return "Waiting for the next verified maneuver"
        case .paused(_, let reason): return "Guidance paused · \(reason)"
        case .offRoute(_, let deviation):
            return "Off route · \(Int(deviation.crossTrackMeters.rounded())) m"
        case .rerouting: return "Calculating an offline reroute"
        case .idle, .arrived, .stopped, .failed: return "Offline guidance inactive"
        }
    }

    private var coverageTitle: String {
        switch composition.navigationCoverage {
        case .verified(let evidence):
            return "Coverage verified · \(evidence.regionIDs.map(\.rawValue).joined(separator: ", "))"
        case .approachingBoundary(_, let distanceMeters):
            return distanceMeters.map { "Coverage boundary in \(distance($0))" }
                ?? "Approaching the installed-coverage boundary"
        case .outsideInstalledCoverage:
            return "Outside verified installed coverage"
        case .unknown:
            return "Coverage state is being verified"
        }
    }

    private var accessibilityText: String {
        let instruction = composition.currentNavigationManeuver?.instruction ?? stateTitle
        return "Radio-silent guidance. \(instruction). \(coverageTitle)."
    }

    private func distance(_ meters: Int64) -> String {
        meters < 1_000
            ? "\(meters) m"
            : String(format: "%.1f km", Double(meters) / 1_000)
    }
}

// MARK: - Wrapper

struct EnRouteDriveScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            EnRouteDrive(register: theme.bgPage == Theme.dark.bgPage ? .dark : .light)
        } nav: {
            BottomNav(leading: driverNavLeading_035(),
                      trailing: driverNavTrailing_035(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_035() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",     isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box", isCurrent: true)]
}
private func driverNavTrailing_035() -> [NavSlot] {
    [NavSlot(label: DriverTab.wallet.label, systemImage: DriverTab.wallet.systemImage, isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",     isCurrent: false)]
}

// MARK: - Previews

#Preview("035 · En Route Drive · Dark") {
    EnRouteDriveScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("035 · En Route Drive · Light") {
    EnRouteDriveScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
